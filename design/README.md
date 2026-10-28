# Design

Scratchpad's look is its own. This folder records it; the shared parts underneath
(checks, wording, keyboard map, helpers) come from `../kit/`, copied in from the
kit's home and checked for drift. See `../kit/README.md`.

## Identity

| | |
|---|---|
| Palette | `tokens.json`, recorded from `linux/src/styles.css`; `apple/Sources/ScratchpadApp/Theme.swift` matches |
| Modes | Light and dark, with a System / Light / Dark override |
| Type | IBM Plex Sans, Serif and Mono on Linux; SF, New York and SF Mono on Apple; a hand font for blocks |
| Shape | A paper sheet on a desk, dot grid |

`tokens.json` records the current values unchanged. Nothing is generated from it
yet: screens still read the original file. When they move over, add `css` and/or
`swift` outputs under `build` (see `../kit/specs/TOKENS.md`).

## Against the kit

Run `python3 kit/tools/build_tokens.py --check` and `python3 kit/tools/kit_check.py`
from the repo root; CI runs both in `.github/workflows/kit.yml`.

Contrast:

- Overdue orange (`late`) is 4.4:1 on the desk in light mode; text needs 4.5:1.

Notes:

- Fonts are bundled with the app; nothing loads from an outside font host.
- Animations stop under Reduce Motion.
- Block fonts on the sheet are a fixed size on purpose: they are content the person sized, not interface text.
