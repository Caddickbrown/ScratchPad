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

- **The open sheet**: folding pushes it onto the phone stack (`phonePath`), so
  you stay on the sheet, not the rail. Unfolding shows it in the split view.
- **The to-do column**: the slide-over and the phone's to-do sheet share
  `state.showTodoSheet`, so whichever is open stays open across the fold.
- **The caret**: every text field keeps its focus and caret in `AppState.caret`
  (`keepsFocus` and `KeptTextField` in `BlockViews.swift`): text and code blocks,
  table cells, a link's title and address, the sheet title and to-do rows. The
  rebuilt field takes both back. The caret position needs iOS 18
  (`TextEditor`/`TextField(text:selection:)`); the package targets iOS 17, where
  only the focus returns. The table's formula bar is not kept (its cell is).
- **The canvas scroll**: `AppState.canvasOffset` keeps the offset per sheet
  (`KeepsCanvasScroll` in `CanvasView.swift`, iOS 18 `ScrollPosition`); on iOS 17
  the canvas starts at the top left again. The to-do list's own scroll is not kept.

## Waits on the iOS 27.1 SDK / a device

- Check the caret lands mid-sentence after a fold: the editor sets the selection
  on appear and focuses 150 ms later; if focusing moves the caret to the end,
  set the selection again after focusing.
- Check the toolbars in their vertical 27.1 form; the To-do button is a system
  toolbar item, so it should follow.
- Check the canvas offset survives: if the old layout reports a clamped offset
  while it is torn down, record only while the sheet is not mid-resize.
- 760 pt is a guess; tune it on a device.
