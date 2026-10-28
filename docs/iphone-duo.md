# ScratchPad on iPhone Duo

Design notes: [iPhone Duo canvas](https://claude.ai/artifact/L8kjQ6MXNqsNdFPr6WpGPX).
Apple: <https://developer.apple.com/iphone-duo/>.

## Closed (≈ 466 × 678 pt, compact width)

The iPhone layout (`RootView.phone`): the rail in a `NavigationStack`, the sheet
pushed over it, to-dos in a bottom sheet from the toolbar's To-do button.

## Open (≈ 890 × 626 pt, regular × regular)

The iPad layout (`RootView.desktop`): the 180–200 pt rail beside the sheet on the
desk, the rail folding away and staying folded (`@AppStorage` `sidebarColumns`).
The sheet's to-do column sits beside the canvas only when the sheet is at least
760 pt wide (`PadView.sideBySideWidth`). Narrower, as in the open Duo with the
rail showing (~700 pt) or a half-screen iPad, the column slides over the canvas
from the trailing edge, toggled by a To-do toolbar button. Fold the rail away and
the 890 pt sheet has room for both again. The decision reads the sheet's own
width only: nothing looks at `UIScreen`, the device idiom or orientation.
The fixed `.frame(width: 440)` in `ScratchpadApp.swift` is the macOS Settings
scene, inside `#if os(macOS)`.

## Through a fold

The app targets iOS 18 and macOS 15, so everything below holds on every supported system.

- **The open sheet**: folding pushes it onto the phone stack (`phonePath`); unfolding
  shows it in the split view. The to-do slide-over and the phone's to-do sheet share
  `state.showTodoSheet`, so whichever is open stays open.
- **Focus and caret**: every field keeps both in `AppState.caret` (`keepsFocus`,
  `KeptTextField` in `BlockViews.swift`): text and code blocks, table cells and the
  formula bar (its cell in `AppState.tableCell`), a link's title and address, the
  sheet title, to-do rows, and the date and tag entries.
- **The DATE and tag popovers**: open state in `AppState.headerPopover`, typed text in
  `entryDrafts`, the grid's month in `dateGridMonth`. If SwiftUI closes a popover as
  the header is torn down, the rebuilt header reopens it (`reopenHeaderPopoverAfterFold`).
- **Scroll**: the canvas offset per sheet (`ScrollPosition`, `AppState.canvasOffset`);
  the to-do list by its top row (`scrollPosition(id:)`, `todoTopRow`); the rail by its
  top visible row (`ScrollViewReader`, `railTopRow`), to the row, not the point.

## Waits on the iOS 27.1 SDK / a device

- The caret lands mid-sentence: the selection is set on appear, focus 150 ms later;
  if focusing moves the caret to the end, set the selection again after focusing.
- The canvas offset: if the old layout reports a clamped offset as it is torn down,
  record only while the sheet is not mid-resize. The reopened popover: no flicker.
- The toolbars in their vertical 27.1 form (To-do is a system item); 760 pt is a guess.
