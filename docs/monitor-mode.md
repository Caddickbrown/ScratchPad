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
- **Its own read-only block renderer** (`MonitorBlock`, `MonitorTable`). `BlockView`'s editors
  keep focus and caret in `AppState`, so a second copy on the monitor would fight the phone's.
  Tables show computed values. Images and files reuse `ImageBlock` and `FileBlock`.
- **Scaling.** The sheet is scaled to fit, between 0.45× and 1.6×. A sheet too big to fit at
  0.45× stays at that scale and scrolls on the monitor to keep the phone's window centred,
  clamped to the sheet's edges.
- **No frame** while no canvas is showing (the iPhone's sheet list, say).
- **Appearance:** an external-display scene doesn't follow the device, so the app pushes its
  resolved colour scheme to the monitor.
- **The phone stays awake** while a monitor is attached.

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
