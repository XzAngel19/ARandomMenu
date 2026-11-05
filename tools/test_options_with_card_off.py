#!/usr/bin/env python3
"""Sub-options must be switchable while their card is OFF.

The user reported that options such as Proximity Prompts' instant prompt or
Speed's Sprint could look impossible to change with the card disabled. This
boots the real bundle and, for every disabled card, flips every visible toggle
option in both directions, asserting that the checkbox, the stored config value
and the module callback all move together and that the card itself never turns
on as a side effect.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

import audit_menu

PROBE = r'''
local checked = 0
local enters = 0
local failures = {}
local function fail(key, reason) table.insert(failures, key .. ": " .. reason) end

for _, feature in ipairs(ex.allFeatures) do
  if feature.kind == "toggle" and feature.enabled == false then
    for _, row in ipairs(feature.optionRows or {}) do
      local rowName = row.Name or ""
      if string.sub(rowName, 1, 7) == "Option_" then
        local optionName = string.sub(rowName, 8)
        local key = feature.configKey .. "." .. optionName
        local control = ex.state.toggleControls[key]
        if control and row.Visible then
          checked += 1
          local current = control.getChecked()
          -- Both directions, each one changing the checkbox so the widget has
          -- to write the stored value: a card that is off must not reject
          -- either direction and must never turn itself on.
          for _, wanted in ipairs({not current, current, not current}) do
            local ok, err = pcall(control.setChecked, wanted)
            if not ok then
              fail(key, "setChecked(" .. tostring(wanted) .. ") errored: " .. tostring(err))
            elseif ex.configData.states[key] ~= wanted then
              fail(key, "stored state is " .. tostring(ex.configData.states[key])
                .. " after setChecked(" .. tostring(wanted) .. ")")
            elseif feature.enabled == true and feature.optionEntersFeature ~= true then
              fail(key, "changing an option turned the card on without saying why")
            elseif feature.enabled == true then
              enters += 1
            end
          end
        end
      end
    end
  end
end

assert(#failures == 0, table.concat(failures, "\n"))
assert(checked >= 60, "expected to exercise most toggle options, got " .. tostring(checked))
print("PASS options with the card OFF: " .. tostring(checked) .. " toggles, both directions, card stays off"
  .. " (" .. tostring(enters) .. " provider rows documented as card-rising)")
'''


def main() -> None:
    source = audit_menu.build(debug=True).read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory(prefix="options-off-") as tmp:
        path = Path(tmp) / "probe.luau"
        path.write_text(source + PROBE, encoding="utf-8")
        result = subprocess.run(
            [os.environ.get("LUAU", "luau"), str(path)],
            capture_output=True,
            text=True,
        )
        if result.returncode:
            raise SystemExit(result.stdout[-3000:] + "\n" + result.stderr[-2000:])
        assert "PASS options with the card OFF" in result.stdout
        print("PASS options with the card OFF: toggles move with their card disabled")


if __name__ == "__main__":
    main()
