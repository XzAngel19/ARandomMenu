# Agent D — theme engine and presets

Read `docs/agents/RULES.md` and `docs/design/UI-V2.md` first.

You own **`src/library/Theme.luau`**, **`src/themes/*.luau`** and the theme page
inside **`src/library/SettingsPage.luau`**. Nothing else. In particular you do
not touch `Widgets.luau` or the shell — if a widget reads a colour the wrong
way, file it in `docs/requests/D.md` and say it in your reply.

Do not start until agent A has pushed phase 0: the single token set and
`Theme:Bind`. Your work sits on top of that interface. If it is not there yet,
read it, review it, and tell A what a theme author will need that it is missing.

## The job

The default stays monochrome and near-black with a white accent — that is a
product decision, not a limitation. Your job is to make it *one preset among
many* rather than a palette compiled into the code.

### Presets

Ship six, each a small data file in `src/themes/`, each exporting nothing but a
token table and a display name:

| Name | Character |
|------|-----------|
| Monochrome | The current look. The default. Must be pixel-identical to today. |
| Vape | Near-black, pure white accent, hairline strokes, minimal radius. |
| Wurst | Dark neutral, magenta accent, gradient title bars, accent glow on. |
| Midnight | Navy-charcoal surfaces, cyan accent. |
| Ember | Warm charcoal, amber accent. |
| Custom | Starts as a copy of the active preset, every token editable. |

A theme sets colour tokens *and* the shape tokens — corner radius, surface
transparency, stroke thickness, font, accent glow, gradient title bars. A theme
that can only change colours is a palette, not a theme, and the four in
`docs/design/mock-themes.jpg` are distinguishable mostly by shape.

Semantic colours are not yours. Health green, danger red and MM2 role colours
label game data, not chrome; a theme that recolours "murderer" is a theme that
lies. Leave them in the semantic block.

### The Themes page

A grid of preview cards — each card renders a real miniature of a window under
that theme, not a swatch strip, because the shape tokens are half the
difference. Clicking applies live, with a short tween, no reload.

Below it, for Custom: the token list with the existing colour picker, the shape
sliders, and:

### Export / import

A theme is a string the player can paste to a friend. Base64 of a compact
serialisation, versioned, and **validated on import** — an import that produces
an unreadable menu, or that throws mid-apply and leaves half the tokens
switched, is worse than no import. Apply into a copy, validate contrast between
`text` and `surface`, then swap.

## Definition of done

- Switching preset repaints every pixel of the menu with no reload and no
  flicker, including windows that are currently closed (they must be correct
  when reopened).
- Monochrome renders identically to today. Screenshot-compare it if you can.
- The selected theme and any custom tokens survive a reload, per config profile.
- A suite in `tools/test/suites/` boots the shell headless, applies each preset,
  and asserts no bound instance was left holding a stale colour.
