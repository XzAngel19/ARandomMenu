# D anti-slop copy report

Visible strings changed in the architecture pass:

| Surface/module | Before | After |
|---|---|---|
| SettingsPage | Keybind profile loaded: `<name>` | loaded profile `<name>` |
| SettingsPage | Keybind profile: enter a name first | enter a profile name |
| SettingsPage | Keybind profile saved: `<name>` | saved profile `<name>` |
| SettingsPage | Keybinds reset — profiles are untouched, as in Wurst | keybinds reset |
| SettingsPage | Reinject unavailable: this executor has no loadstring | reinject unavailable |
| SettingsPage | Could not download the latest build | download failed |
| SettingsPage | The downloaded build could not be compiled | compile failed |
| SettingsPage | Layout reset | layout reset |
| SettingsPage | This executor has no queue_on_teleport — … | queue on teleport unavailable — … |
| Furniture | Module search is not available | module search unavailable |
| Furniture | Ambiguous: … | ambiguous: … |
| Furniture | No module matches … | no module matches … |
| Fling | That player is protected by FriendList. | player protected |
| Fling | A fling is already running. | fling already running |
| Fling | Your character is not ready. | character not ready |
| Fling | Fling failed/completed/stopped… | fling failed/complete/stopped… |
| Fling | No matching player was found. | no matching player |
| Projectile Calibration | Universal projectile analytics saved in the executor workspace. | analytics saved |
| Projectile Calibration | Universal projectile analytics could not be saved; check F9. | save failed; check F9 |
| Projectile Calibration | Universal projectile analytics deleted for this PlaceId. | analytics deleted |
| Projectile Calibration | Universal projectile analytics could not be deleted; check F9. | delete failed; check F9 |

No row label was changed to add punctuation. Module names and frozen identity strings are untouched.
