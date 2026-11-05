# Scratchpad: Rust core conversion spec

Status: plan only, nothing built. Written 2026-11-05 from reading the code at commit `f050afa`. No build or device test backs it.

Reference pattern: Quire (`core/` with `Vault`, `bindings/`, Tauri and Apple shells on one core), MiniOffice (`core/crates`, `mo-ffi`) and BestShot (`core/bestshot-ffi`, `apple/scripts/build-core.sh`).

**In short:** this is the best candidate of Dan's apps. Scratchpad already has two shells over one file format, and it pays for that with three copies of its logic. Part of the Rust core already exists, in `linux/store`. The port also fixes real gaps in how the Apple store treats iCloud.

## 1. What it is today

- **Languages:** Swift, TypeScript and Rust.

  | Part | Lines | What it is |
  |---|---|---|
  | `apple/Sources/ScratchpadCore` | 1,780 | Swift model, store, formula, dates, paste, export |
  | `apple/Sources/ScratchpadApp` | 4,760 | SwiftUI, macOS 15+, iOS 18+ |
  | `apple/Tests` | 720 | 73 tests |
  | `linux/store/src/lib.rs` | 413 | Rust store, model, migrate, archive |
  | `linux/src-tauri` | 120 | Tauri 2 commands, thin |
  | `linux/src` | about 3,200 | TypeScript: UI, plus a second copy of model, formula, dates, paste, Markdown |

- **Data store:** plain files, and both apps write the same layout, so one synced folder serves both.
  - `<root>/pads/<id>.json`: a sheet, format v2, schema in `shared/schema/pad.schema.json`, samples in `shared/samples`.
  - `<root>/assets/<uuid>.<ext>`: pasted files.
  - Archive `.scratchpad`: JSON with base64 assets.
- **Sync:** iCloud Drive on Apple when available, under `Documents/Scratchpad`, otherwise Application Support. Linux uses a local folder, which can be a synced one. There's no sync code as such.
- **Network:** one thing only, the page title for a pasted link (`LinkTitle.fetch` in Swift, `fetch_title` with `ureq` in `linux/src-tauri`). 5 seconds, first 256 KB.

### Drift and gaps found while reading

These are the case for the port. Each should get a test before the code moves.

| Finding | Where | Consequence |
|---|---|---|
| Logic exists three times: `PadStore`/`Models.swift`, `linux/store/src/lib.rs`, `linux/src/model.ts`. Formula twice: `Formula.swift` is 370 lines, `formula.ts` 179 | Throughout | Every behaviour change is two or three changes |
| **Dates differ.** Swift writes whole seconds. chrono's default writes 3, 6 or 9 fractional digits, while the Swift comment says "the Linux app writes milliseconds" | `ISODate.parse`, `Store::save` | If Swift can't parse a sheet's date, see the next row |
| **A sheet that can't be read vanishes silently.** Both `list()`s drop failures (`compactMap { try? }`, `filter_map(...ok())`) | `PadStore.list`, `Store::list` | No error shown. The file stays on disk, but the sheet looks gone |
| **No file coordination.** No `NSFileCoordinator` or `NSFilePresenter` anywhere, though the store may be in iCloud Drive | `PadStore` | Writes can race with the iCloud daemon |
| **Files not yet downloaded are invisible.** `list()` only reads `.json` files, and iCloud placeholders aren't handled | `PadStore.list` | On a new device, `today()` can think no sheet exists for today, make one, and carry over to-dos a second time |
| Last write wins. A debounced save overwrites whatever another device wrote since the sheet was loaded | `AppState`, `PadStore.save` | Lost edits when two devices are in use |
| Save behaviour differs: Swift drops empty to-do rows (`compacted`) and has `touch`; Rust does neither | `PadStore.save`, `Store::save` | Files differ by writer |
| Field shape differs: Swift always writes `font`, `fontSize` and `rotation`; Rust omits defaults. Sort tie-break differs too (Swift adds id) | `Block`, `newestFirst` | Harmless, but it makes a synced folder churn |
| Unknown fields are dropped by every reader | All three models | An older build rewriting a newer sheet loses data |

## 2. What moves and what stays

### Moves to Rust

| Today | Why |
|---|---|
| `Models.swift` (`Block`, `Todo`, `Pad`, `SheetID`, `Tags`, `PadJSON`, `DayKey`), `linux/store`, `model.ts` | One model, one JSON shape |
| `PadStore.swift` | One store, through a vault |
| `Formula.swift`, `formula.ts` | Keep the fuller Swift behaviour, checked against both |
| `Dates.swift`, `dates.ts` (phrase parsing, month grid, labels) | Pure |
| `PasteClassifier.swift`, `paste.ts` (classification and HTML/TSV table parsing) | Pure, given clipboard contents as plain values |
| `Placement.swift`, `Rollover.swift`, `Sidebar.swift`, `TodoSort.swift`, `MonitorFit.swift` | Pure |
| `Export.swift`, `markdown.ts`, archive code in `linux/store` | Markdown, JSON and archive text. `isSafeAssetPath` matters on import |
| `LinkTitle.parse`, `html_title` | The parsing only |

### Must stay native

| Today | Why |
|---|---|
| `apple/Sources/ScratchpadApp/*`, `linux/src` UI (`canvas.ts`, `todos.ts`, `header.ts`, `dialogs.ts`, `styles.css`) | The look of each platform |
| `PasteBridge.swift`, `fromDataTransfer` in `paste.ts` | Reading the clipboard is platform work |
| PNG export in `ExportView.swift` | Rendering is the UI's |
| `MonitorDisplay.swift`, `Motion.swift`, `Theme.swift` | External display, animation |
| iCloud container lookup (`PadStore.iCloudRoot`), `NSFileCoordinator`, placeholder download | Apple-only, inside `AppleVault` |
| `LinkTitle.fetch`, `fetch_title` | Keeps networking out of the core |
| Drag-time geometry in `canvas.ts` and `CanvasView.swift` | Runs every frame, in UI units. Only the snapping rules are shared |

## 3. Target structure

```
core/
  Cargo.toml                 workspace; uniffi pinned as in MiniOffice
  scratchpad-core/           from linux/store, grown: model, vault, store, formula, dates,
                             paste, rollover, sidebar, sort, export, archive
  scratchpad-ffi/            UniFFI: PadLibrary object, records, Vault foreign trait
apple/scripts/build-core.sh  as BestShot
linux/src-tauri              commands call scratchpad-core directly
shared/vectors/              test cases for anything still implemented twice during the move
```

**Vault** (Quire's rule: the core never opens a file itself):

```rust
#[uniffi::export(with_foreign)]
pub trait Vault: Send + Sync {
    fn list(&self, dir: String) -> Result<Vec<VaultEntry>, VaultError>;  // includes not-downloaded items
    fn read(&self, path: String) -> Result<Vec<u8>, VaultError>;
    fn write(&self, path: String, data: Vec<u8>) -> Result<(), VaultError>;   // atomic
    fn remove(&self, path: String) -> Result<(), VaultError>;
    fn local_url(&self, path: String) -> Option<String>;                 // for showing images
}
```

`VaultEntry` carries `path`, `modified` and `state` (`Available`, `NotDownloaded`). `FsVault` lives in the core for Linux and tests. `AppleVault` lives in Swift. It follows Quire's measured lesson: **plain reads, coordinated writes**, because coordinating every read cost about 25 ms per file on a file-provider folder. It maps `.<name>.json.icloud` placeholders to `NotDownloaded` and asks for a download, and it refuses paths outside the root.

**FFI surface.** `PadLibrary::open(vault)`, `list() -> ListResult { sheets, unreadable, pending }`, `load`, `save`, `delete`, `today(now_key)`, `create`, `create_pinned`, `duplicate`, `move_to`, `store_asset`, `archive`, `import_archive`. Free functions: `evaluate_table`, `parse_day_phrase`, `classify_paste`, `sidebar(mode)`, `sort_todos`, `export_markdown`. Records are UniFFI records, and `Pad` is plain data, so no JSON hop is needed. A `Clock` isn't needed: the host passes `now` and the local day key, as `PadStore` already allows.

**Callbacks.** Only `Vault`. No async. Everything is small and synchronous, so call it off the main thread as `AppState` does, or on a background queue. This is the simplest FFI of all Dan's apps.

**How each shell uses it.**

- Apple: `ScratchpadCore` remains as a thin Swift layer with the same type names, so views don't change: `typealias`es or small extensions over generated records. `AppState` keeps its debounce.
- Linux: `src-tauri` commands call the core. TS loses `formula.ts`, `dates.ts`, the logic in `paste.ts`, `markdown.ts` and most of `model.ts`. Tauri commands are async, so the front end asks for computed values (`evaluate_table` when a table changes, `sidebar` when the list changes) rather than computing during a draw. `api.ts` already has that shape.

## 4. Data

- **Format stays v2.** No version bump, no folder move. Old builds keep working with what the core writes.
- **Never rewrite on read.** v1 sheets migrate in memory, and only reach disk when edited. Otherwise the first launch would rewrite every file and push them all through iCloud.
- **Pick one written shape, safe for every existing reader:** sorted keys, pretty printed, dates with whole seconds or fixed milliseconds, and `font`, `fontSize` and `rotation` as Swift writes them. Keep the reader lenient: any fractional digits, missing fields, `tag` from v1.
- **Keep unknown fields.** Add a `serde(flatten)` extras map on `Pad`, `Block` and `Todo`, so an older core won't delete what a newer one wrote. MiniOffice's `.minical` does the same.
- **Unreadable is not absent.** `list()` returns unreadable files by name, and the UI says so. Nothing ever deletes or overwrites a file it couldn't parse.
- **`today()` must wait.** If any `pads/` entry is `NotDownloaded`, the answer to "does today's sheet exist?" is unknown. Fetch first, and don't make a sheet or carry over until it's known. A short timeout then falls back to a new sheet with no carry-over, which is safe.
- **Overwrite guard.** `save` takes the `updatedAt` it loaded. If the file on disk is newer, write the edit as a new sheet ("… (conflict)") and tell the user, instead of overwriting. Ship after parity, as its own stage.
- **Backup.** Before the first Rust build writes anything, export a `.scratchpad` archive to Application Support (or the data folder on Linux), outside the synced folder, and keep the last three. `Archive.build` already does nearly all of this. Also, Dan should copy his folder by hand once.
- **Proof.** Run `shared/samples` and a copy of Dan's real `pads/` through read, write, read. Compare values, and confirm old Swift and old Rust read the new output. Only the copy, and never in a repo.
- **Going back.** No format change means an old build still opens everything. Sheets made by the conflict stage are ordinary sheets.

## 5. Migration steps

Each stage ships on both platforms and leaves the app working.

1. **Tests first.** Create `shared/vectors` from the 73 Swift tests and the TS tests. Add the drift cases from section 1, then fix the date output in the Rust store now, as that's a one-liner and it removes a real hazard.
2. **Linux, pure logic.** Move `linux/store` to `core/scratchpad-core`, and add formula, dates, paste, sort, sidebar and export. Tauri commands call them, and TS copies are deleted one at a time.
3. **Apple pure functions.** Add `scratchpad-ffi` and `build-core.sh`. Formula, dates, paste, sort, sidebar, export go through Rust behind the same Swift names. Files are still Swift's. Vectors prove agreement.
4. **Apple store.** Backup runs. `AppleVault` lands with coordinated writes and placeholder handling, and `PadStore` becomes a façade on `PadLibrary`. Unreadable and pending sheets show in the UI. Keep a hidden switch back to the Swift store for one release.
5. **Delete Swift's copies.** `ScratchpadCore` shrinks to the façade, and tests run in `cargo test`, plus a small Swift integration test.
6. **Overwrite guard,** then consider a folder watcher in Linux and `NSFilePresenter` on Apple, so an open sheet updates when another device saves.

## 6. Risks, questions, rating

**Risks.**

- Biggest: a mistake in the store on a synced folder spreads to every device. The answers are the backup, never rewriting on read, and never touching a file that can't be parsed.
- iCloud behaviour can't be tested in `cargo test`. Stage 4 needs two real devices, including a fresh install with undownloaded sheets.
- `Pad` crossing FFI on each debounced save, with a big table or lots of blocks, is a copy each time. It should be fine at sheet sizes. Measure one big sheet.
- UTF-16 positions: to-do text is edited natively, so none should cross, but check anything in `paste` that hands offsets back.
- The Linux `npm run dev` browser preview uses a `localStorage` store and would lose logic that moves to Tauri commands.

**Questions for Dan.**

1. Does the browser preview still matter? If yes, build the core to wasm for it. If no, it can go. It's the only reason the TS logic has to run without Tauri.
2. Is the conflict-copy approach right, or would you prefer plain last-write-wins?
3. Do you want to share `Vault` as a small crate between Quire, Scratchpad and others, or copy it per app? Copying is simpler, and the `kit` precedent suggests copying is acceptable until it hurts.
4. Android, ever? Scratchpad's core would suit it with a Storage Access Framework vault.

**Benefit: high. Worth doing, and first.** Three copies become one, most of the design is already proved by Quire, a third of it exists in `linux/store`, and the iCloud fixes are worth having anyway.

## 7. Size

**Medium.** About 1,800 lines of Swift logic to port, of which 400 already exist in Rust, and an almost trivial FFI. Most of the care goes on stage 4.
