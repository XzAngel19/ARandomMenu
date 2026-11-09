#!/usr/bin/env node
// Static analysis for the Wurst sources: Luau type checking + lints.
//
//   node tools/luau/analyze.mjs                      # whole src/ tree
//   node tools/luau/analyze.mjs src/Wurst.lua        # specific files
//   node tools/luau/analyze.mjs --mode=strict        # nonstrict (default)|strict|nocheck
//   node tools/luau/analyze.mjs --errors             # only errors (default: errors+warnings)
//   node tools/luau/analyze.mjs --json               # machine readable
//   node tools/luau/analyze.mjs --baseline            # only errors not in the baseline
//   node tools/luau/analyze.mjs --write-baseline      # record the current errors
//
// Exit code 1 when any error is reported, 0 otherwise. Warnings never fail the
// build.
//
// The baseline exists because the Luau analyzer cannot narrow types through
// `obj:IsA("MeshPart")`, and the wasm build does not resolve `Enum.KeyCode` as a
// *type* (only as a global table). Both patterns are correct runtime code and
// both report here; ~40 known lines are recorded in analyze-baseline.json so the
// gate fails on NEW problems instead of on the ones already read and accepted.
// Regenerate it only when a change legitimately adds an accepted limitation. This is the same Luau front end the game runs (`luau-analyze` through
// wasm), fed with tools/luau/definitions/core.d.luau plus the globals the
// runtime gets from the executor and from the menu host (see runtime.d.luau).
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Analysis } from '@luau-rs/luau/analysis';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');

export const DEFINITIONS = [
    join(HERE, 'definitions', 'core.d.luau'),
    join(HERE, 'definitions', 'runtime.d.luau'),
];

export function sourceFiles(patterns) {
    if (patterns.length > 0) return patterns.map((p) => resolve(p));
    return execFileSync('find', ['src', '-name', '*.lua'], { cwd: ROOT })
        .toString()
        .trim()
        .split('\n')
        .filter(Boolean)
        .sort()
        .map((p) => resolve(ROOT, p));
}

/** Build an `Analysis` loaded with the Roblox + executor definitions. */
export async function createAnalysis({ mode = 'nonstrict', lint = true } = {}) {
    const definitions = DEFINITIONS.filter((path) => existsSync(path)).map((path) => ({
        name: relative(HERE, path),
        source: readFileSync(path, 'utf8'),
    }));
    return Analysis.create({ mode, lint, definitions });
}

export const BASELINE_PATH = join(HERE, 'analyze-baseline.json');

/** Key used to match a reported error against the baseline. */
export function baselineKey(file, diagnostic) {
    return `${file}|${diagnostic.code}|${diagnostic.message.replace(/\s*\n\s*/g, ' ')}`;
}

export function loadBaseline(path = BASELINE_PATH) {
    if (!existsSync(path)) return [];
    const data = JSON.parse(readFileSync(path, 'utf8'));
    return Array.isArray(data.entries) ? data.entries : [];
}

function parseArgs(argv) {
    const files = [];
    const options = {
        mode: 'nonstrict',
        lint: true,
        errorsOnly: false,
        json: false,
        quiet: false,
        baseline: false,
        writeBaseline: false,
    };
    for (const arg of argv) {
        if (arg === '--errors') options.errorsOnly = true;
        else if (arg === '--json') options.json = true;
        else if (arg === '--no-lint') options.lint = false;
        else if (arg === '--quiet') options.quiet = true;
        else if (arg === '--baseline') options.baseline = true;
        else if (arg === '--write-baseline') options.writeBaseline = true;
        else if (arg.startsWith('--mode=')) options.mode = arg.slice('--mode='.length);
        else if (arg.startsWith('-')) {
            console.error(`unknown option ${arg}`);
            process.exit(2);
        } else files.push(arg);
    }
    return { files, options };
}

export function formatDiagnostic(diagnostic, root = ROOT) {
    const { location, severity, message, module } = diagnostic;
    const file = relative(root, module);
    const line = location.begin.line + 1;
    const column = location.begin.column + 1;
    const single = message.replace(/\s*\n\s*/g, ' ');
    return `${file}:${line}:${column}: ${severity}: ${single} (${diagnostic.code})`;
}

async function main() {
    const { files, options } = parseArgs(process.argv.slice(2));
    const targets = sourceFiles(files);
    const analysis = await createAnalysis({ mode: options.mode, lint: options.lint });
    for (const path of targets) {
        analysis.setModule(path, readFileSync(path, 'utf8'), 'module');
    }
    const results = [];
    for (const path of targets) {
        for (const diagnostic of analysis.check(path).diagnostics) {
            if (options.errorsOnly && diagnostic.severity !== 'error') continue;
            results.push(diagnostic);
        }
    }
    analysis[Symbol.dispose]?.();

    results.sort((a, b) =>
        a.module === b.module
            ? a.location.begin.line - b.location.begin.line
            : a.module.localeCompare(b.module),
    );

    if (options.json) {
        console.log(JSON.stringify(results.map((d) => ({
            file: relative(ROOT, d.module),
            line: d.location.begin.line + 1,
            column: d.location.begin.column + 1,
            severity: d.severity,
            code: d.code,
            message: d.message.replace(/\s*\n\s*/g, ' '),
        })), null, 2));
    } else {
        for (const diagnostic of results) console.log(formatDiagnostic(diagnostic));
    }

    const errors = results.filter((d) => d.severity === 'error');
    const warnings = results.length - errors.length;

    let accepted = 0;
    let fail = errors.length;
    if (options.writeBaseline) {
        const entries = [...new Set(errors.map((d) => baselineKey(relative(ROOT, d.module), d)))].sort();
        writeFileSync(BASELINE_PATH, JSON.stringify({
            comment: 'Known analyzer reports: IsA narrowing and Enum.* used as a type are not supported by the wasm front end.',
            entries,
        }, null, 2) + '\n');
        fail = 0;
    } else if (options.baseline) {
        const known = new Set(loadBaseline());
        const fresh = [];
        for (const diagnostic of errors) {
            const key = baselineKey(relative(ROOT, diagnostic.module), diagnostic);
            if (known.has(key)) accepted += 1;
            else fresh.push(diagnostic);
        }
        fail = fresh.length;
        for (const diagnostic of fresh) console.log(`NEW ${formatDiagnostic(diagnostic)}`);
        if (fresh.length > 0 && !options.quiet) {
            console.error('analyze: new errors above. Fix them, or record an accepted limitation with --write-baseline.');
        }
    }

    if (!options.quiet) {
        const scope = files.length > 0 ? `${files.length} file(s)` : `${targets.length} sources`;
        const acceptedNote = accepted > 0 ? ` · ${accepted} in baseline` : '';
        console.error(`analyze: ${scope} · ${fail} error(s)${acceptedNote} · ${warnings} warning(s) · mode=${options.mode}`);
    }
    process.exitCode = fail === 0 ? 0 : 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    await main();
}
