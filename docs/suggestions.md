# Scratchpad: suggestion guide

A full review from reading the README, the docs and the code on 2026-11-06, at
`c0da8e0`. Nothing was built or run, so "check" marks a question for a real device,
not a confirmed fault.

The short version: this is the most charming idea in the family and a small, tidy
codebase. A day's pad with a to-do column is instantly understandable, and the paper
metaphor is carried through with real wit. It has also been built like a desk object
rather than a phone app: nothing reaches it from outside (no widget, share sheet or
Shortcut), and it doesn't notice time passing. Those two gaps are what stand between a
lovely demo and something used every day.

`docs/rust-core-spec.md` already has an excellent list of drift and gaps. This guide
doesn't repeat them at length; section 2 says where they stand, and adds what that list
doesn't have.

## 1. What's great and should be protected

- **The concept.** One pad per day, paste anything, to-dos at the side, unfinished items
  carried over. It needs no explanation. Guard it against becoming a whiteboard app.
- **"Paste decides the block."** `PasteClassifier` is the core of the product. A single
  gesture does the right thing for images, tables, links and code.
- **The whimsy.** Ticks that spray ink, ALL CLEAR, sheets tearing off the pad, a Full /
  Subtle / Off setting, and Reduce Motion turning it off. It's why someone would love this.
- **Monitor mode's central idea:** "no new gesture", the phone as a window framed on the
  whole sheet. `docs/monitor-mode.md` is a model design note.
- **"Moving a block shows the whole sheet"** and the dashed landing outline. Small,
  considered touches.
- **The fold-survival work in `AppState`:** caret, scroll and popovers kept outside the
  views so a fold doesn't lose your place. Few apps will care this much.
- **A strict Tauri setup:** a real CSP, an asset scope narrowed to `assets/` at runtime
  (`linux/src-tauri/src/lib.rs`), `valid_id`, and `asset_path` refusing traversal. Asset
  paths from archives are checked on both platforms (`isSafeAssetPath`, `asset_path`).
- **Shared schema and samples** in `shared/`, with Rust tests reading the same samples.
- **Natural date entry:** `fri`, `15 oct`, `+3`. Keep it.
- **An honest "Not done yet" in the README.** Last write wins is stated, not hidden.

## 2. Bugs and risks found

### Serious

1. **Turning iCloud on strands whatever is in the local store, and typing just after
   launch can land there too.** `AppState.live()` opens the local store first, then
   switches when `iCloudRoot()` returns (`AppState.swift:110`). `switchStore` does
   `flush()` into the local store, swaps stores, sets `current = nil`, and reloads. Two
   consequences:
   - Nothing copies local sheets across, so the day the iCloud entitlement starts working
     every existing sheet disappears from the app. The files are on disk in Application
     Support, with no way to reach them from inside the app.
   - On each launch, `openToday` runs against the local store first, and
     `forUbiquityContainerIdentifier` can take seconds on a cold start. Anything typed in
     that window is saved to the local store, then the sheet is swapped from under the
     user and the words are gone from view. It also makes a stray local sheet each day.
   Fix: resolve the store before showing the first sheet, with a brief loading state,
   and do a one-off merge of local into iCloud that skips existing ids. This matters more
   than it looks, because the README says enabling the container is the next step.

2. **Nothing reacts to the app coming back, or to a new day.** No `scenePhase`,
   `didBecomeActive` or day-change handling exists in `apple/Sources/ScratchpadApp`, and
   the Linux app only calls `openToday` at launch. For an app called "one pad per day":
   - An iPhone that keeps the app in memory opens on yesterday's sheet tomorrow morning.
     Rollover hasn't run, so to-dos aren't carried. On a Mac left open overnight, the same.
   - Sheets edited on another device don't appear until a relaunch, and the stale copy in
     memory then overwrites them at the next keystroke. The README mentions last write
     wins for offline editing. This makes it happen while everyone's online.
   - There's no flush when going to the background on Apple. The 400 ms debounce keeps the
     exposure small, but a swipe-away right after typing can lose the last words. Linux
     does flush on `blur` and `beforeunload`; Apple should match it.
   Fix: on `scenePhase == .active`, `reload()`, and if `todayKey` changed since the last
   check, offer today's sheet. Flush on `.inactive`. Same on `focus` on Linux, plus
   `.NSCalendarDayChanged` while the app is frontmost.

3. **Items already in `docs/rust-core-spec.md` that shouldn't wait for the port.** That
   list is right, and the port is a medium-sized job, so three of them need a fix now:
   - **Undownloaded iCloud files are invisible**, and `today()` can make a second sheet
     and carry to-dos twice on a new device. There is no `startDownloadingUbiquitousItem`
     anywhere, so on iOS a second device may see almost nothing.
   - **A sheet that won't parse vanishes silently** (`compactMap { try? }`, `filter_map`).
     Show "2 sheets couldn't be read" with the file names.
   - **Writes aren't coordinated.** Wrap `PadStore.save` in `NSFileCoordinator` now. It's
     ten lines, and they can later move into the `AppleVault` the spec plans.

### Medium

4. **Importing an archive replaces newer sheets with no question.** Both platforms
   overwrite on a matching id (`ScratchpadArchive.importInto`,
   `Store::import_archive`). Importing last month's backup quietly reverts every sheet in
   it. Swift counts `overwritten` but the toast doesn't say so, and neither side offers
   a choice. Linux doesn't even count them. Fix: keep the newer `updatedAt` by default, or
   ask "12 sheets already exist. Keep newer / Replace / Keep both".

5. **`Store::save` stamps `updated_at` during import on Linux.** Swift has `touch: false`
   to keep imported times, and Rust has no such option, so an import on Linux marks
   everything as edited now. That reorders "recent" and defeats any newer-wins check.
   The spec notes the `touch` difference but not this consequence.

6. **The link title fetch has no off switch, and the size limit isn't real on Apple.**
   Pasting a link makes a request straight away, on both platforms. It's the app's only
   network use, and it's undisclosed. That means URLs with tokens, private intranet
   addresses and tracking links all get visited silently. On Apple,
   `URLSession.shared.data(for:)` (`LinkTitle.swift:12`) downloads the whole response and
   only then takes the first 256 KB, so a link to a large file gets downloaded, and
   `timeoutInterval` is an idle timeout, not a total one. Fix: a setting, skip private
   hosts, and stream with `bytes(for:)`, stopping after the `</title>`.

7. **"Visible in Files" needs `NSUbiquitousContainers`.** The README says sheets show in
   Files under iCloud Drive, but `Info.plist` and `project.yml` don't declare
   `NSUbiquitousContainers` with `NSUbiquitousContainerIsDocumentScopePublic`. Without it,
   the folder won't appear. Check when the container is enabled.

8. **Sheet deletion is final,** with an 8-second undo for blocks but none for a whole
   sheet (`store.delete`). Orphaned assets staying behind is a deliberate choice, but it
   means the expensive thing is kept and the precious thing isn't. Move sheets to
   `<root>/trash/` for 30 days.

9. **Assets are all loaded into memory:** `Data(contentsOf:)` on paste, base64 through the
   Tauri bridge, and the whole archive built as one JSON string
   (`archive_json`, `ScratchpadArchive`). A few videos make an archive fail or get the app
   killed on a phone. Check with a 500 MB file. A zip container would stream.

### Small

10. `fs::write` then `fs::rename` in `Store::save` has no fsync.
11. `tokens.json` is recorded but nothing reads it, so `Theme.swift` and `styles.css` can
    drift. `design/README.md` says so. Generate at least one side.
12. Linux always uses `$XDG_DATA_HOME/com.caddickbrown.scratchpad`, and I found no way to
    choose a folder, though the README's "one synced folder works for both" needs one.
    A symlink works, but a setting would make the promise real.
13. There is no `PrivacyInfo.xcprivacy`.
14. There's no CLAUDE.md or AGENTS.md in the repo.

## 3. UX and flows

- **Capture is the whole game, and today it means opening the app.** See section 13.
- **Today should be one tap from anywhere.** A "Today" button and key (`t`) that opens
  today's sheet from an old one is a basic need for a day-based tool. If the rail is the
  only way, add it. It also answers the midnight problem.
- **A morning moment.** When today's sheet is new, show what carried over and how long
  it's been around: "3 carried over, one since Tuesday". Nudge the third-time-carried
  item to be dealt with: do it, defer it, or bin it. This is what real paper pads are
  good at: rewriting a task makes you question it.
- **Overdue means three or more days old** (`isOverdue`). It's a pleasingly humane
  definition. Use it more, with a gentle mark, not a red alarm.
- **Deferred** deserves a date. "Not today, ask me on Monday" would stop deferred items
  coming back every day. `carry` currently re-opens them all.
- **The sheet list by month could be a calendar:** the DATE picker has dots already, so
  promoting it to a browsing view is cheap.
- **Search** already reaches tables, captions and to-dos (`Pad.matches`). Next, show where
  the match is: a search that jumps to and flashes the block would feel good.
- **Multiple selection** of blocks (drag a lasso, move together) will be asked for quickly.
- **Paste position:** `docs/monitor-mode.md` already lists landing in the middle of the
  phone's window. Do this one first; it affects every paste on a phone.

## 4. Visual design

- The paper, dot grid and tear-off identity is strong. Don't add chrome.
- Make the dark sheet feel like a night version of the same paper rather than a dark UI.
  The dark-mode icon commit shows the right instinct.
- The Hand font is Bradley Hand with fallbacks on Apple and something else on Linux, so a
  sheet changes character between platforms. Bundling one open hand font would fix that.
- Plex on Linux and SF on Apple is a fair choice, but it means PNG exports differ.
- Ink colours for text and block backgrounds in a highlighter yellow, a blue biro and a
  red pen would stay on theme, and they're the natural next "font".
- Sticky note as a block style: it's the first thing most people would look for.
- A subtle coffee ring on sheets with over ten ticks, on Full whimsy only. You know you
  want to.

## 5. Accessibility

- 69 labels across 13 files, `accessibilityAction` on blocks and 24 `aria`/`role` uses in
  `canvas.ts`: thought has gone in. Linux can nudge blocks with arrow keys, too.
- A free-form canvas is inherently hard for VoiceOver. Give a rotor or a list view of
  blocks in reading order (top to bottom, left to right), so a sheet can be read through.
  The Markdown export already defines that order.
- Check that Apple blocks can be moved without dragging. Add "Move left/right/up/down"
  custom actions to match Linux's nudge.
- Block text uses `.system(size:)`, which is fixed by design as it's on paper. The chrome
  (rail, to-do column) should scale: RailView and TodoColumnView between them have seven
  fixed sizes. Use `Font.scaled` from `kit/swift/`.
- To-do status shows through ink and a slash: fine, since it isn't colour alone. Check the
  count announcement when ticking, and that "ALL CLEAR" is announced.
- Reduce Motion handling is good.

## 6. Monitor Mode and keyboard

Monitor mode is strong as a display, and thin as a keyboard experience. Compared with Quire
and MiniOffice, it's phone-led. The docs list the known next steps (mini-map, pinch zoom,
caret on the monitor, the height measuring problem); those are the right ones. Priority
order: caret, paste landing, height measuring, then the mini-map. In addition:

- **Key commands on the phone with a keyboard.** Today it's Esc plus the standard shortcuts.
  For Monitor Mode to work without touching the phone: arrows to walk blocks, ↵ to edit,
  Tab across to the to-dos, Space to tick, `n` new to-do, ⌘1-style sheet jumps. A desk
  setup should never need a finger.
- **A hint bar on the monitor,** as Quire has, listing what works now.
- **Pause and privacy.** A monitor showing today's sheet in a meeting room should be able
  to blank. Quire has it; there's nothing here.
- **Check Esc on a device.** The doc is candid that the simulator never delivers it.
- **Mac and Linux keyboard parity:** Linux has Ctrl-D, Delete and Alt-Up/Down; Apple's
  keyboard set is smaller. `kit/specs/keymap.json` is the shared map, so check against it.
- **Phone dim while on a monitor** isn't there, though Pigeon's desk mode has it.

## 7. Performance

- `PadStore.list()` decodes every sheet in full whenever the list refreshes
  (`refreshList`), which is after most sheet operations, plus `today()` and `create()`. At
  one or more sheets a day, that's over a thousand JSON files within a few years, read and
  fully decoded on the main actor, and on iCloud too. Keep a small index (id, date, title,
  tags, updatedAt, open count) in memory, updated by file date.
- `save` happens on the main actor via `flush`, with `queue.sync` inside. Fine for small
  sheets; move it off main if a sheet can hold a big table.
- `filteredPads` runs `matches` over all pads on each keystroke in search. Fine until the
  point above bites.
- Images: check the canvas decodes thumbnails rather than full-size originals. Phone
  photos at 12 MP or more on a sheet add up quickly. Use `CGImageSource` thumbnails.

## 8. Reliability and data safety

Beyond items 1 to 5:

- **Auto-backup.** The archive exists. Run one weekly to a chosen folder.
- **Conflict copies.** The spec's Question 2 asks about this. My answer: yes, keep both.
  For this format a better answer is cheap: merge by block id and to-do id, since both
  have stable ids. Block-level merge makes last-write-wins almost never lose anything.
- **Unknown fields are dropped by every reader** (spec). Before the next format change,
  make the readers preserve them, or an older build quietly erases newer data.
- **A format version check:** `v: 3` opened by an older app ought to refuse to save.
- **Fix the date precision** difference the spec lists, as a parse failure there leads
  straight to a vanishing sheet.

## 9. Privacy and security

- Item 6 is the main one: an undisclosed network request on paste.
- No app lock. Probably right for this app, unless widgets arrive.
- PNG export: check that it contains no metadata beyond the image.
- `fs:allow-write-file` and `fs:allow-read-text-file` have no explicit scope in the
  capability file's short form. Check the description's "writing or reading only" is
  enforced by scope, not only by the dialog.
- The monitor shows everything on the sheet. See "Pause and privacy" above.

## 10. Testing

- 73 Swift tests and a decent TS and Rust suite for a repo this size. Good.
- **Add shared test vectors.** With three copies of logic, the kit's `vectors/` approach
  is the cheap way to stop drift before the port: formula cases, date phrases and paste
  classification as JSON, run in Swift and TS. These same files become the port's safety
  net, so nothing is wasted.
- **Test the store switch** (item 1) and a new day while running (item 2). Inject a clock.
- **A cross-writer test in CI:** Rust writes a sheet, Swift reads it, and back. It catches
  the date bug directly.
- **Test `AppState`.** It holds most of the app's real behaviour and lives outside
  `ScratchpadCore`, so has no tests. Moving `moveTodo`-style logic to the core helps.

## 11. Code health

- A small, readable codebase. `AppState.swift` is carrying a lot of fold-restoring state;
  a `FoldMemory` struct would make it easier to see what's what.
- The Rust core plan (`docs/rust-core-spec.md`) is well argued and I agree with its
  rating: three copies of logic is the main debt. Do fixes 1 to 3 first, in Swift, as
  they're small and they protect data today.
- On its Question 1: drop the browser preview unless it's used. It's the only reason the
  TS logic must run without Tauri.
- `MonitorBlock` is a second renderer. That's justified by the doc, but it's a place
  features can be forgotten. A test or a list of block kinds handled by each would help.
- Add a CLAUDE.md. Other repos have one, and the rules here (three copies stay in step,
  schema first) are precisely what an agent needs to be told.

## 12. New feature ideas

Small delights:

- Tear a sheet off and it flutters away when you delete it.
- A stamp block: DONE, URGENT, or a date stamp, in ink, slightly crooked.
- "Yesterday's pad" peeking out underneath, dragged up to look at it.
- Sounds on Full whimsy: a pencil tick, a page tear. Off by default.
- ALL CLEAR streak: a small count of cleared days in the corner.
- Doodle block with Pencil. It's a pad; people will want to draw on it.

Medium:

- **Pencil and finger drawing layer.** The biggest missing piece of "paper". PencilKit
  makes it easy on Apple; Linux can show it as an image.
- **Templates:** pinned sheets you can stamp out as today's: a weekly plan, meeting notes.
  `duplicate` is most of the way there.
- **Repeating to-dos.** "Water plants every Monday" is natural given rollover.
- **To-do due dates and reminders,** simple and optional.
- **Sheet to PDF** for printing. A real desk pad page, with a dot grid, printed.
- **Scan paper into a sheet:** VisionKit document camera to an image block with text
  recognised. Lovely for an app modelled on paper.
- **Sections on the to-do column.** Work and home on one list.
- **Inline links between sheets.**

Bigger bets:

- **Share a sheet live with someone** would be the leap from tool to product, but it's a
  big step away from "plain files".
- **An iPad-first Pencil experience.** This could be the product that defines the app:
  a real desk pad on an iPad, with a Pencil, on the desk beside the keyboard.
- **A web viewer for a sheet,** read-only via an exported file. Only if asked for.

## 13. Platform features worth using

None of these exist yet (no `AppIntent`, `WidgetKit`, `CoreSpotlight` or share extension in
`apple/Sources`), so this list is the biggest single improvement available:

- **Share extension.** "Send to today's pad" from Safari, Photos or anywhere. This is the
  natural feed for an app whose core gesture is paste. Top priority. Follow MiniOffice's
  pattern: the extension writes to an App Group inbox and the app ingests it.
- **Widgets.** Today's open to-dos with interactive ticks. A small "N left" and a lock
  screen accessory. A widget of yesterday's sheet would be sweet.
- **App Intents and Shortcuts.** Add a to-do, paste the clipboard to today, open today.
  Back Tap to "paste to pad" becomes possible.
- **Control Center control** for "paste to today" and "new to-do".
- **Spotlight** for sheets and to-dos.
- **Quick Note style Mac menu bar item,** with a global key to paste to today.
- **Foundation Models, on device:** turn a pasted email or meeting notes into to-dos, or
  title an untitled sheet. Both are small, useful and private.
- **Live Text** on image blocks, so text in a pasted photo is selectable and searchable.
- **Reminders/EventKit import:** today's calendar as a block on a new sheet (opt in).
- **Pencil Scribble** in to-do fields.
- **Multiple windows on iPad** are on already and share one `AppState`, which means two
  windows show the same sheet. Check that it's intended, and consider per-window sheets.

## 14. App Store readiness

- The app doesn't appear to have been aimed at release yet, but it's the most marketable
  thing in the family. A strong screenshot, a one-line pitch, and no account needed.
- Needed first: the iCloud work (items 1, 3 and 7), privacy manifest, and disclosing the
  title fetch in the privacy details.
- `fatalError("Cannot open store")` in `AppState.live()` is a crash at launch if Application
  Support isn't writable. Replace it with an error screen.
- Bradley Hand availability differs by device, so check the fallbacks in screenshots.
- A short demo video of monitor mode for review notes.
- The name "Scratchpad" is very crowded in the store. The repo is `ScratchPad`, the app
  `Scratchpad`. A more distinctive name, such as one that leans on "desk pad", would help.

## 15. What to cut

- The Linux browser preview, if it's not used (`npm run dev`, `localStorage` store).
- Rotation on blocks is fun but costs in hit-testing and on the monitor renderer. Keep it
  if you love it; it's the sort of feature that stays quietly expensive.
- JSON export alongside the archive. They're nearly the same to a user.
- Keep the whimsy. If anything has to go, it isn't that.

## 16. Top 10

| # | Suggestion | Effort | Impact |
|---|---|---|---|
| 1 | Resolve the store before showing a sheet, and merge local into iCloud once | small | high |
| 2 | React to foreground and new day: reload, roll over, flush on background | small | high |
| 3 | Handle undownloaded iCloud files and show unreadable sheets; coordinate writes | medium | high |
| 4 | Add a share extension to today's pad | medium | high |
| 5 | Add a to-do widget with ticks, and App Intents for add and paste | medium | high |
| 6 | Make archive import keep newer sheets; fix `updated_at` on Linux | small | medium |
| 7 | Add an off switch for link titles, and really stop at 256 KB on Apple | small | medium |
| 8 | Add keyboard control and a hint bar to Monitor Mode | medium | medium |
| 9 | Add a sheet Trash and a drawing layer with Pencil | medium | high |
| 10 | Share test vectors now, then do the Rust core as already specified | large | high |
