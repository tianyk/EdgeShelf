# Dropshelf on macOS 26/27 — notes

## What Dropshelf is

- Menu-bar-only drag-and-drop shelf by Pilotmoon (Nick Moore), sold on the
  Mac App Store 2012–2021.
- Last public build: **1729**, 1 July 2021, universal (x86_64 + arm64),
  built against the **macOS 11.3 SDK**, minimum macOS 10.15.7.
- It is not sandboxed on disk? It is a sandboxed app (`com.apple.security.app-sandbox`)
  with an app-group helper, `DropshelfHelper`.

### How it works (from the 1729 binary)

- `DPDragValidator` installs `DS2UniversalMonitor` objects for mouse drags.
  Each monitor launches `DropshelfHelper` with a mach-port name, and the
  helper uses `NSEvent.addGlobalMonitorForEventsMatchingMask:` to watch
  global drags and send mach messages back.
- `DPAppController` / `DPTriggerController` show a `DPTriggerWindow` at the
  nearest screen edge when a drag starts.
- Dropping on the trigger creates a `DPPodWindow` (the shelf), which slides
  in with `DPSlidingLayer` and holds `DPItemView`s.
- Ingesters (`DPIngesterFile`, `DPIngesterImage`, `DPIngesterURL`, …) copy
  dropped data into the app container's `Caches/DroppedFiles`.
- It also calls `CGWindowListCreate` (`kCGWindowListOptionOnScreenOnly |
  kCGWindowListExcludeDesktopElements`) to get on-screen window IDs, and
  `AXUIElementCopyElementAtPosition` for the item under the cursor.

## Why it can freeze on macOS 26/27

macOS 26 (Tahoe) added stricter Core Drag IPC handling around drag
destinations. Resizing, moving, or re-ordering a window **from inside a drag
callback** can produce:

```
Reentrant message: kDragIPCWithinWindow, current message: kDragIPCWithinWindow
Reentrant message: kDragIPCLeaveApplication, current message: kDragIPCEnterLeaveHandler
```

and the drag stalls for seconds or the whole drag/hover system gets stuck
(dragged item remains attached to the pointer, hover highlights stop).

This is not theoretical: it is reported on the exact OS build running here
(macOS 26.5.2, 25F84) in Atoll issue #650, where the trigger was a
`window.setFrame(targetFrame, display: true)` inside `draggingEntered`. Apple
Feedback **FB21223363** covers the broader “drag & drop + hover animations
break after a while” regression.

Dropshelf does the risky things by design:

- creates and positions a trigger window while a drag is in progress;
- slides shelf windows in/out with layer/window animations;
- resizes the shelf as items are added;
- does main-thread `NSTask launch` for its helper;
- calls `CGWindowListCreate` on the drag path;
- reads pasteboard data during the drag lifecycle.

Any one of those is enough to hit the macOS 26 reentrancy path. The original
binary is closed-source and hardened-runtime signed, so a proper fix would
require either patching + re-signing it (which resets TCC grants) or
reimplementing the window handling.

## Observed on this machine (24 Oct 2026)

- Dropshelf 1729 had been running since 18:11 on macOS 26.5.2 (25F84).
- After a drag to the left edge, a **146 × 146 Dropshelf window** remained at
  screen (0, 322), layer 8, alpha 1, showing a yellow/black striped
  placeholder. It survived mouse-up and a Finder restart.
- While that window existed, a drop at the left edge was captured by it and
  the drag image stayed stuck on screen; EdgeShelf never received
  `draggingEntered`.
- Killing Dropshelf (pid 86736) removed the window, and the same drag then
  reached EdgeShelf normally.

That is a concrete instance of the stuck drag-destination state, not just a
theory. The original app can leave a trigger window alive after a drag and
then sit in front of every later drop.

## What EdgeShelf does differently

- Every shelf window is created once, at a fixed frame, before any drag
  starts. Its frame never changes during a drag.
- The shelf is shown/hidden by changing alpha and `ignoresMouseEvents` only;
  no `setFrame:display:`, no window ordering, no Core Animation during a
  drag.
- The panel background is a solid layer, not a live `NSVisualEffectView`
  backdrop, so appearing during a drag does not trigger a backdrop resample.
- Drag-monitor callbacks only record the cursor and schedule work with
  `DispatchQueue.main.async`; all window work happens on the next run-loop
  turn, outside the Core Drag callback.
- `performDragOperation` parses URLs/text quickly and returns; the shelf is
  rebuilt, thumbnails are generated, and only pasted image data or promised
  files are written to disk. Finder drops are referenced in place, never copied.
- Each referenced file has a kqueue vnode watcher: unlink or a move to the
  Trash removes its card, while a rename/move on the same volume updates the
  card through `F_GETPATH` on the still-open descriptor.
- No periodic polling: a one-off reconciliation runs at launch, after sleep,
  and when a volume is mounted or unmounted.
- File promises use `NSFilePromiseReceiver.receivePromisedFiles` instead of
  materialising promised data on the main thread.
- No `CGWindowListCreate`, no Accessibility/Input Monitoring permission, no
  screen capture, no synchronous XPC, no `NSTask`.

## If you want to keep the original app

Possible, but invasive:

1. Copy `Dropshelf.app`, strip its signature, add a `disable-library-validation`
   entitlement, re-sign ad-hoc.
2. Inject a shim that defers `-[NSWindow setFrame:display:]`,
   `-[NSWindow orderFront:]` and `-[NSWindow animator]` calls made while
   `NSEvent.pressedMouseButtons != 0` to the next run-loop turn.
3. Re-grant Accessibility/Input Monitoring (the signature change resets TCC).

That is a research project with a fragile result. EdgeShelf is the safer
path and the source is here to change.
