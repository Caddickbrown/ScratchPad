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
- **The caret**: text and code blocks keep their focus and caret in
  `AppState.caret` (`BlockTextEditor` in `BlockViews.swift`), and the rebuilt
  editor takes both back. The caret position needs iOS 18
  (`TextEditor(text:selection:)`); on iOS 17 only the focus returns. Table cells,
  link fields, the title and to-do rows don't keep it yet.

## Waits on the iOS 27.1 SDK / a device

- Check the caret lands mid-sentence after a fold: the editor sets the selection
  on appear and focuses 150 ms later; if focusing moves the caret to the end,
  set the selection again after focusing.
- Check the toolbars in their vertical 27.1 form; the To-do button is a system
  toolbar item, so it should follow.
- 760 pt is a guess; tune it on a device.
