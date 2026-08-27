# PolloV2 — design documents, parked here

These two files describe **PolloV2**, a separate menu project, not ARandomMenu.
They live in this repository only because the session that wrote them has push
access here and nowhere else; PolloV2's own repository (`XzAngel19/PolloV2`)
exists but is empty and unreachable from that session.

They are not part of this project. Nothing in `src/`, `tools/` or the validation
workflow reads them, and no gate in this repository applies to them.

- `idea.md` — intent: identity, curated palette, total customization, the
  inspector, the contrast guarantee, the effect budget, mobile.
- `arquitectura.md` — the derived design: declared spec tree, path identity,
  role-based themes and the resolution chain, serialization, the module
  contract, folder layout and the build order.

`idea.md` wins. If the architecture contradicts the intent, the architecture is
what gets redesigned.

Move both files to the PolloV2 repository as its first commit and delete this
directory.
