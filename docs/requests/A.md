# Requests from agent A

## Add Furniture.luau to the parity gate's constant scan

`tools/extract_prototype_spec.py` reads named ALL_CAPS constants only from
`Widgets.luau`, `WindowManager.luau`, `SettingsPage.luau` and
`ClickGui.luau`. The furniture now lives in `src/library/Furniture.luau`
and carries constants the gate should be holding to Wurst's defaults the
moment it can see them:

- `HACKLIST_COLOR` = `#FFFFFF`
- `HACKLIST_REVERSE` = `false`
- `HACKLIST_ANIMATIONS` = `true`
- `TOOLTIP_DELAY_MS` = `400` (also defined in the shell's
  `addFeatureTooltip`; the shell is not scanned either)

Please add the file to the scan list so a drifted value fails and names
both sides.

One deliberate deviation to record so the gate does not later demand it
silently: Wurst's `HackList.Position` default is `Left`, under its logo.
Our prototype gives the top-left corner to the wordmark and the stats
block, so the list hangs on the **right** edge (and moves top-left under
the stats on a phone, per UI-V2's mobile section). When the HackList
settings window ships and `HACKLIST_POSITION` becomes a named constant,
the spec row for it should carry our default, not upstream's — otherwise
the gate will force a Left default that contradicts the prototype.
