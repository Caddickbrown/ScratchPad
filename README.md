# Scratchpad

[![Apple](https://github.com/Caddickbrown/ScratchPad/actions/workflows/apple.yml/badge.svg)](https://github.com/Caddickbrown/ScratchPad/actions/workflows/apple.yml)
[![Linux](https://github.com/Caddickbrown/ScratchPad/actions/workflows/linux.yml/badge.svg)](https://github.com/Caddickbrown/ScratchPad/actions/workflows/linux.yml)

One pad per day: a dot grid you paste anything onto, with a to-do column at its side. Modelled on the paper desk pad.

| Platform | Stack | Folder |
|---|---|---|
| macOS 14+, iOS 17+ | SwiftUI, Swift Package for the core | `apple/` |
| Linux | Tauri 2, Rust store, vanilla TypeScript front end | `linux/` |
| Both | JSON pad format and sample | `shared/` |

Design canvas (desktop light and dark, iPhone, components): https://claude.ai/artifact/WBbNwYn7g4qxNZR3vPUZie

## How it behaves

- **A pad is a day.** The rail lists days. Pinned pads are the few undated ones.
- **Paste decides the block.** Image data becomes an image block, an HTML or tab-separated table becomes a table, a file becomes a file chip, a bare URL becomes a link card, fenced text becomes code, everything else is text. Same classifier on both platforms, with the same tests.
- **Blocks sit on a 24 px grid.** Drag anywhere on a block to move it, drag its right edge to resize, double-click the dots to start a text block, right-click the dots (or type `/` in an empty text block) for the insert menu.
- **To-dos cycle open, done, deferred.** Deferred is the paper's slashed circle. A row open for three days or more turns the overdue colour.
- **Midnight rollover.** Opening today's pad for the first time copies open and deferred rows from the latest earlier pad, as open, keeping their original date. Done rows stay behind.
- **Dark mode.** Follows the system, with a System / Light / Dark override (View menu on macOS, the half-circle button on Linux).
- **Search** across every pad's title, tag, blocks and to-dos. Cmd-K / Ctrl-K, or the sidebar search field on Apple.
- **Drag a to-do** by its circle to reorder it, or drop it on the dots to turn it into a text block.
- **Link cards fetch their page title** after the paste; the URL stays until the page answers, and your own edit always wins.

## Storage

Both apps write the same layout, so one synced folder works for both:

```
<root>/pads/<id>.json     id = YYYY-MM-DD for daily pads, a slug for pinned pads
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

Shortcuts: Cmd-N new pad, Cmd-Shift-T new to-do, Cmd-Shift-V paste as block (Cmd-V on the canvas also works), Return in a to-do adds the next row.

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

Shortcuts: Ctrl-N new pad, Ctrl-Shift-T new to-do, Ctrl-Shift-V paste as block, Ctrl-D toggles the focused to-do.

## CI

- **Apple**: `swift test` for the core, then `xcodebuild` for macOS and the iOS simulator on a macOS runner.
- **Linux**: front-end and Rust tests, then `tauri build`; the `.deb` and AppImage are uploaded as the `scratchpad-linux` artifact on every push to `master`.

## Not done yet

- iCloud needs the container enabled on the App ID in the developer portal; until then the Apple app stays on the local folder.
- Conflict handling when two devices edit the same pad offline. Last write wins today.
- Link titles on Linux need outbound network from the app; there is no proxy setting yet.
