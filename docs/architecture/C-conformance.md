# Module contract conformance

The module architecture gate is blocking.

`tools/check_module_conformance.py` walks every file under `src/modules/**` and
rejects:

- direct access to shell GUI roots (`ScreenGui` or `PopupLayer`);
- bare `print` or `warn` calls;
- persistence keys outside the approved namespaces.

## Approved persistence namespaces

- `Universal.*`
- `UI.*`
- `ClickGUI.*`
- `Shortcut.*`
- `WurstLogo.*`

## Shell boundary

Gameplay code never needs to know where the menu is parented. A module that
must distinguish game UI from menu UI calls `host.isMenuOwned(instance)`.
This keeps `gethui`, `CoreGui`, protection and GUI-root changes inside the
shell.

User-facing diagnostics belong in `card:Notify(...)`, `card:SetStatus(...)` or
the documented `host.notify(...)` helper. Modules do not write to the executor
console. Remote Logger deliberately offers Save and Copy actions instead of a
console-print action.

The gate moved from report-only to hard-fail after the final findings in Auto
Clicker, Projectile Calibration, Rejoin Server and Remote Logger were removed.
A future violation fails `tools/validate.sh` and CI.
