# Scratchpad

[![Apple](https://github.com/Caddickbrown/ScratchPad/actions/workflows/apple.yml/badge.svg)](https://github.com/Caddickbrown/ScratchPad/actions/workflows/apple.yml)
[![Linux](https://github.com/Caddickbrown/ScratchPad/actions/workflows/linux.yml/badge.svg)](https://github.com/Caddickbrown/ScratchPad/actions/workflows/linux.yml)

One pad per day: a dot grid you paste anything onto, with a to-do column at its side. Modelled on the paper desk pad.

| Platform | Stack | Folder |
|---|---|---|
| macOS 15+, iOS 18+ | SwiftUI, Swift Package for the core | `apple/` |
| Linux | Tauri 2, Rust store, vanilla TypeScript front end | `linux/` |
| Both | JSON pad format and sample | `shared/` |

Design canvas (desktop light and dark, iPhone, components): https://claude.ai/artifact/WBbNwYn7g4qxNZR3vPUZie

## How it behaves

Full behaviour spec: `docs/v0.2-spec.md`. Design canvas: https://claude.ai/artifact/Lr6cgFti87ULk2zK8U9G8d

- **Sheets, several a day.** New sheet (Ctrl/Cmd-N) always makes one, dated today, with the current tags. Its menu adds New sheet on a date, New pinned sheet and Duplicate.
- **By day or by tag.** The sidebar groups sheets by day, or by tag sorted A to Z, by count or by recent use. A sheet can carry several tags.
- **Date picker** on the DATE box. Days with sheets show a dot, and you can type `fri`, `15 oct` or `+3`.
- **Paste decides the block**: image, file, HTML or tab-separated table, bare URL, fenced code, else text.
- **Blocks**: drag the edge to move, drag a corner to resize (Shift keeps the ratio), rotate from the toolbar, pick a font (Sans, Serif, Mono, Hand), duplicate, delete with an 8 second undo.
- **Tables**: per-column widths (drag or double-click the line between letters), and formulas with `+ - * /`, cell references, and SUM, AVG, MIN, MAX and COUNT.
- **To-dos**: live count, a grip to drag rows (reorder, drop on the sheet, or drop on another sheet), and sorting by Manual, Open first, Overdue first, A to Z or Oldest first, with "Done sinks to the bottom". Unfinished rows carry over to the next day's first sheet.
- **Export** (Ctrl/Cmd-E): the sheet as a PNG in light or dark, to-dos as Markdown checkboxes, or everything as one `.scratchpad` archive, Markdown or JSON file. Import archives from Settings.
- **Whimsy**: ticks pop and spray ink, clearing the list stamps it ALL CLEAR, and new sheets tear off like the paper pad. Settings has Full, Subtle and Off, and the system's Reduce motion turns it off.
- **Dark mode**: follows the system, with a System, Light or Dark override.
- **Monitor mode (iPhone / iPad)**: plug into a monitor and it shows the whole sheet as a whiteboard, with the to-dos at its side; the phone is a window onto it, framed on the monitor, and panning moves the frame. See `docs/monitor-mode.md`.

## Storage

Both apps write the same layout, so one synced folder works for both:

```
<root>/pads/<id>.json     id = YYYY-MM-DD-xxxxxx for dated sheets, a slug for pinned ones (v0.1 ids still load)
<root>/assets/<uuid>.ext  pasted images and files
```

Apple: the iCloud Drive container `iCloud.com.caddickbrown.scratchpad` (under Documents/Scratchpad, visible in Files) when the entitlement is granted and the user is signed in, otherwise `~/Library/Application Support/Scratchpad`. Linux: `$XDG_DATA_HOME/com.caddickbrown.scratchpad`. Schema: `shared/schema/pad.schema.json`.

## Apple

```sh
cd apple
swift test                 # core: model, paste classifier, rollover, store
brew install xcodegen
xcodegen generate          # writes Scratchpad.xcodeproj (gitignored)
open Scratchpad.xcodeproj  # one multiplatform target: My Mac, iPhone, iPad
```

Shortcuts: Cmd-N new sheet, Cmd-K search, Cmd-E export, Cmd-Shift-V paste as block (Cmd-V on the canvas also works), Return in a to-do adds the next row.

## Linux

Needs Rust, Node 20+, and the Tauri 2 system packages (`libwebkit2gtk-4.1-dev libgtk-3-dev librsvg2-dev`).

```sh
cd linux
npm install
npm test                       # front-end classifier and model tests
(cd store && cargo test)       # Rust store tests
npm run tauri dev              # desktop app
npm run tauri build            # .deb and AppImage under src-tauri/target/release/bundle
npm run dev                    # browser preview only: localStorage store, no file import
```

Shortcuts: Ctrl-N new sheet, Ctrl-K search, Ctrl-E export, Ctrl-Shift-T new to-do, Ctrl-Shift-V paste as block, Ctrl-D duplicates the selected block or cycles the focused to-do, Delete removes the selected block, Alt-Up/Down moves a to-do.

## CI

- **Apple**: `swift test` for the core, then `xcodebuild` for macOS and the iOS simulator on a macOS runner.
- **Linux**: front-end and Rust tests, then `tauri build`; the `.deb` and AppImage are uploaded as the `scratchpad-linux` artifact on every push to `master`.

## Not done yet

- iCloud needs the container enabled on the App ID in the developer portal; until then the Apple app stays on the local folder.
- Conflict handling when two devices edit the same sheet offline. Last write wins today.
- Formulas are deliberately basic: no cross-table references, no text functions.
