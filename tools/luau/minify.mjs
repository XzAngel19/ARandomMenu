#!/usr/bin/env node
// DarkLua for the release artifact.
//
//   node tools/luau/minify.mjs src/Wurst.lua                 # -> stdout
//   node tools/luau/minify.mjs src/Wurst.lua -o build/Wurst.min.lua
//   node tools/luau/minify.mjs --rules                       # list DarkLua rules
//   node tools/luau/minify.mjs --levels
//
// DarkLua is the Lua/Luau source transformer the Roblox tooling world uses to
// build a single injected file: `remove_types` strips the Luau annotations,
// `rename_variables` and `remove_spaces` shrink it, `remove_comments` drops the
// documentation the game never needs. The pipeline below is the one this
// repository ships as "release": semantics-preserving, no require() rewriting
// (Wurst.lua is already a self-contained loader), no `inject_global_value`.
//
// Examples live in tools/luau/darklua.release.json so a human can read/edit the
// rule list; this script is the executable copy and rejects drift between them.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { process_code, get_all_rule_names } from 'darklua-wasm';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..', '..');
const RECIPE = join(HERE, 'darklua.release.json');

// Order matters: strip the types before renaming, and strip the comments last so
// a failure in an earlier rule still leaves a readable file to debug.
export const RELEASE_RULES = [
    'remove_types',
    'remove_debug_profiling',
    'remove_compound_assignment',
    'convert_local_function_to_assign',
    'group_local_assignment',
    'remove_empty_do',
    'remove_unused_if_branch',
    'remove_unused_while',
    'remove_unused_variable',
    'remove_method_definition',
    'rename_variables',
    'remove_comments',
    'remove_spaces',
];

export function ruleNames() {
    return get_all_rule_names();
}

/** Apply a DarkLua rule list to one source string. */
export function minifySource(source, rules = RELEASE_RULES) {
    const known = new Set(ruleNames());
    const unknown = rules.filter((rule) => !known.has(rule));
    if (unknown.length > 0) {
        throw new Error(`unknown DarkLua rule(s): ${unknown.join(', ')}`);
    }
    return process_code(source, { rules });
}

export function recipeMatches() {
    if (!existsSync(RECIPE)) return { ok: false, reason: `${relative(ROOT, RECIPE)} missing` };
    const recipe = JSON.parse(readFileSync(RECIPE, 'utf8'));
    const rules = recipe.rules ?? [];
    if (JSON.stringify(rules) !== JSON.stringify(RELEASE_RULES)) {
        return {
            ok: false,
            reason: `${relative(ROOT, RECIPE)} lists [${rules.join(', ')}], minify.mjs ships [${RELEASE_RULES.join(', ')}]`,
        };
    }
    return { ok: true, rules };
}

function usage() {
    console.error('usage: node tools/luau/minify.mjs <file.lua> [-o out.lua] | --rules | --levels');
    process.exitCode = 2;
}

function main() {
    const argv = process.argv.slice(2);
    if (argv.length === 0) return usage();

    if (argv.includes('--rules')) {
        for (const rule of ruleNames()) console.log(rule);
        return;
    }
    if (argv.includes('--levels')) {
        console.log(`release rules (${RELEASE_RULES.length}):`);
        for (const rule of RELEASE_RULES) console.log(`  ${rule}`);
        return;
    }

    const outIndex = argv.indexOf('-o');
    const out = outIndex >= 0 ? argv[outIndex + 1] : null;
    const input = argv.find((arg, index) => !arg.startsWith('-') && index !== outIndex + 1);
    if (!input) return usage();

    const source = readFileSync(resolve(input), 'utf8');
    let result;
    try {
        result = minifySource(source);
    } catch (error) {
        console.error(`minify: ${input}: ${(error && error.message) || error}`);
        process.exitCode = 1;
        return;
    }
    if (out) {
        writeFileSync(resolve(out), result);
        const saved = source.length - result.length;
        const percent = ((saved / source.length) * 100).toFixed(1);
        console.error(`minify: ${relative(ROOT, resolve(input))} -> ${out}: ${saved} bytes saved (${percent}%)`);
    } else {
        process.stdout.write(result);
    }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    main();
}
