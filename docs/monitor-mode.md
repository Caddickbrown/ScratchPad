# Monitor mode (iPhone / iPad)

Plug an iPhone or iPad into a monitor and Scratchpad gets its own window there instead of a
mirror: the **whole sheet** as a whiteboard, with the to-dos down its side. The phone is a
window onto that sheet at full size, and a frame on the monitor shows where the window is.

Code: `apple/Sources/ScratchpadApp/MonitorDisplay.swift`. Modelled on Pigeon's desk mode.

## How it works

- **No new gesture.** Panning the phone's canvas moves the frame. The canvas's own scroll is the
  window: `CanvasScrollKeeper` (`CanvasView.swift`) reports the scroll view's `visibleRect` and
  content size to `MonitorModel` on every scroll. While no monitor is attached, that only stores one value.
- **The monitor draws, the phone edits.** The external-display scene is non-interactive. The
  monitor observes the same `AppState`, so blocks, typing, the selected block and to-do ticks
  show up live.
- **Drags and resizes are live too.** A move, a corner resize or a column drag stays in the
  canvas's own state until it's let go, so it never reaches `AppState` mid-gesture (that would
  save on every touch). The phone tells `MonitorModel` instead, on every touch: `MonitorLive`
  holds the block, and only `MonitorLiveLayer` watches it, so a drag redraws that one block, with
  its dashed landing outline, not the board. With no monitor attached the call returns at once.
- **Moving a block shows the whole sheet.** A sheet too big to fit at 0.45× shrinks to fit for as
  long as a block is moving, then goes back.
- **Its own read-only block renderer** (`MonitorBlock`, `MonitorTable`). `BlockView`'s editors
  keep focus and caret in `AppState`, so a second copy on the monitor would fight the phone's.
  Tables show computed values. Images and files reuse `ImageBlock` and `FileBlock`.
- **Scaling.** The sheet is scaled to fit, between 0.45× and 1.6×. A sheet too big to fit at
  0.45× stays at that scale and scrolls on the monitor to keep the phone's window centred,
  clamped to the sheet's edges.
- **The paper fills the panel.** A sheet has no stored size or shape: its extent comes from its
  blocks. So the monitor draws the paper out to the panel's edges at the scale the content fits
  (`MonitorFit`), with the blocks where they always were. Nothing is saved, and the phone's canvas
  doesn't change, which also means the phone can't pan into the extra paper; a block has to be
  dragged towards it, the canvas growing as it lands.
- **Home.** While the iPhone is on its sheet list the monitor shows the list too (`MonitorHome`),
  so going home shows on the screen being watched. In a wide layout the sheet stays up.
- **Appearance:** an external-display scene doesn't follow the device, so the app pushes its
  resolved colour scheme to the monitor.
- **The phone stays awake** while a monitor is attached.
- **Esc goes home.** With a keyboard on the phone, each Esc takes one step towards the sheet list,
  from anywhere: a dialog, popover, picker or sheet closes first, then the caret leaves the text,
  then the block is deselected, then the sheet closes, then the search clears. Further presses do
  nothing. In a wide layout (iPad), which has no list to return to, the last step brings the rail
  back. Only while a monitor is attached: `MonitorEscape`, `RootView.stepBack`.

## Plumbing

`project.yml` declares `UIApplicationSceneManifest` with the
`UIWindowSceneSessionRoleExternalDisplayNonInteractive` role pointing at `MonitorSceneDelegate`.
`UIApplicationSupportsMultipleScenes` is on, which on iPad also allows several Scratchpad windows
(they share one `AppState`).

## Next

- Tap a mini-map on the phone to send the window to a spot.
- Paste and new blocks land in the middle of the phone's window, not below everything.
- Pinch the phone to zoom, which resizes the window.
- Show the caret on the monitor, not just the selected block.
- Check on a device: whether the frame keeps up with a fast pan, how text sizes look on a 4K
  panel, and the TextEditor inset guesses (13 / 12 pt) in `MonitorBlock`.
