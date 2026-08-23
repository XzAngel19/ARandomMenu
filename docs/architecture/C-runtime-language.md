# C5 — runtime language gate

English is the only product language (`docs/design/PORT-DIRECTION.md`).
The integrator deleted the Spanish bootstrap / loader / asset / MM2
telemetry strings in `afe8223`. This gate holds that deletion.

## What it checks

`tools/check_runtime_language.py` walks:

- `ARandomMenu.luau`
- `loadstring`
- `src/library/**`
- `src/modules/**`
- `src/games/**`

and looks **only inside quoted string literals** for the phrases listed
in `tools/runtime_language_banned.txt`. Identifiers, comments and
`reference/` are ignored on purpose.

## How to extend it

When a player-visible Spanish string is removed, add **that exact
phrase** as a new line in `tools/runtime_language_banned.txt`. Lines
starting with `#` are comments.

Do not dump a Spanish dictionary. `Init` is not `Inicializando`. A
naive word list will flag Wurst identifiers, telemetry keys and
third-party names.

## What this gate does not hold

- Old product display names still appear in `Cards.luau` / `Widgets.luau`
  warn prefixes. That is identity debt for A, not a language miss.
- A few AssetManager / bootstrap leftovers the integrator did not delete
  (`carpeta principal`, `asset desconocido`, `fallback para`) stay in the
  shell. They are not in the seed list on purpose — adding them would fail
  the tree until A rewrites those lines.
- Docs, tools and `docs/agents/` — owner conversation stays Spanish.

`C_LANGUAGE_RESPONSIVE_READY`
