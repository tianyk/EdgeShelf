# EdgeShelf

**English** | [中文](README.zh-CN.md)

![EdgeShelf](docs/screenshot-en.png)

EdgeShelf is a small drag-and-drop shelf for macOS 26/27 — a clean-room
reimplementation of [Dropshelf](https://pilotmoon.com/dropshelf/).

Drag a file, folder, image, link, or text snippet to the left or right edge
of the screen. A shelf appears and keeps the item until you drag it somewhere
else.

The original Dropshelf (build 1729, 2021) can beachball on macOS 26 because
of Core Drag reentrancy; see [DROPSHELF-NOTES.md](DROPSHELF-NOTES.md) for the
diagnosis.

## Features

- Drag files, folders, text, images, and links to the left or right edge.
- Items are copied into `~/Library/Application Support/EdgeShelf/Items`, so a
  shelf item survives if the original is moved or deleted.
- Dynamic shelf height (220–560 pt), frozen while a drag is in flight.
- Warm paper light theme and graphite dark theme, with a terracotta accent,
  quiet diagonal stripes, and a soft outer shadow.
- 64 pt cards with type-coloured thumbnails, real image previews, file name,
  type, and size; hover reveals the remove button.
- Collapses to an 8 × 96 pt gradient tab at the edge after 3 seconds; hover the
  edge to expand it again.
- Right-click menu: Open, Show in Finder, Copy, Remove — with keyboard
  shortcuts.
- Six UN languages plus “Follow System”.
- No Accessibility, Input Monitoring, or Screen Recording permission required.
- No `CGWindowListCreate`, no synchronous XPC, no `NSTask` on the main thread.
- The product name **EdgeShelf** is intentionally never translated.

## Languages

Choose **Preferences → Language**:

| Language | Native name | Layout |
|---|---|---|
| Follow System | — | system |
| English | English | LTR |
| Chinese | 中文 | LTR |
| French | Français | LTR |
| Spanish | Español | LTR |
| Russian | Русский | LTR |
| Arabic | العربية | RTL shelf |

The default is **Follow System**, which resolves to one of the six languages
above (falling back to English). The shelf mirrors its header and cards for
Arabic; secondary windows and system menus follow the system layout direction.

Arabic preview: [`docs/screenshot-ar.png`](docs/screenshot-ar.png).

## UI

- 300 pt panel; height follows the item count (220–560 pt) and is frozen while
  a drag is in flight.
- Warm paper light theme and graphite dark theme, with a terracotta accent,
  very quiet diagonal stripes, and a soft outer shadow.
- 64 pt item cards with a type-coloured thumbnail, file name, type, and size;
  hover reveals the remove button.
- Collapses to an 8 × 96 pt terracotta gradient tab at the edge with a soft
  glow; hover the edge to expand. Preview: [`docs/tab.png`](docs/tab.png).
- All user-facing copy lives in [`Sources/L10n.swift`](Sources/L10n.swift).

## Build

```bash
./build.sh
open build/EdgeShelf.app
```

Requires Xcode 26 (or the matching command line tools). The app is ad-hoc
signed. On another Mac, right-click → Open the first time.

## Usage

- Drag something to the left or right screen edge. A shelf appears.
- Drop it; the item is copied into EdgeShelf’s storage.
- Move away for 3 seconds and the shelf collapses to the edge tab.
- Hover the edge tab to expand the shelf again.
- Right-click an item for Open / Show in Finder / Copy / Remove.
- Drag an item out to Finder, Mail, Slack, etc. If the original file still
  exists, the drag uses the original path, so dropping it back where it came
  from is a no-op instead of a “replace?” prompt.
- Menu bar → Preferences for edges, behaviour, and language.

## Test

```bash
# Data model + pasteboard + store round-trip
build/EdgeShelf.app/Contents/MacOS/EdgeShelf --self-test

# Add demo items and show the left shelf
open build/EdgeShelf.app --args --demo

# Render the shelf to /tmp/edgeshelf-snapshot.png without screen capture
build/EdgeShelf.app/Contents/MacOS/EdgeShelf --snapshot

# Force a language for a screenshot or manual check
build/EdgeShelf.app/Contents/MacOS/EdgeShelf --lang en --snapshot --snapshot-many
```

## Manual checklist

1. Drag a file from Finder to the left edge. A shelf appears; drop the file.
2. Move away. After ~3 seconds the shelf collapses to a tab.
3. Move to the edge tab. The shelf expands.
4. Drag the file from the shelf back to its original folder. No “replace?”
   prompt.
5. Drag text from a browser/editor to the right edge.
6. Right-click an item; try Open, Show in Finder, and Copy.
7. Change the language in Preferences; the shelf and preferences update
   immediately.
8. Quit and relaunch; shelves, items, and the language choice come back.

## Known limitations

- One shelf per edge per display. Dropshelf allows several shelves stacked
  along the same edge.
- Top and bottom edges are not implemented yet.
- No Quick Look panel, “Open With” submenu, or multi-select yet.
- Very large folders take a while to copy; the item shows “Copying…” and
  cannot be dragged out until the copy finishes.
- Shelf state is keyed by display ID. If a display gets a different ID after
  reconnecting, its shelf items are not shown on the new display.
- Arabic mirrors the shelf header and cards; the preferences window and the
  status menu follow the system layout direction.
- The app is not notarized. It is built and signed locally.

## Project layout

```
Sources/
  main.swift                      entry point, self-test
  AppDelegate.swift               menu bar item and app lifecycle
  DragMonitor.swift               global mouse drag detection + edge polling
  ShelfManager.swift              state, persistence, edge windows, ingest
  ShelfWindow.swift               fixed-frame edge window, presentation states
  ShelfView.swift                 shelf panel and item cards
  Theme.swift                     metrics, palette, background, tab, empty state
  L10n.swift                      all UI strings and the six language tables
  Store.swift                     JSON + item file storage
  Models.swift                    ShelfItem/ShelfState/ShelfEdge
  Preferences.swift               UserDefaults
  PreferencesWindowController.swift
```

Built with AppKit, no third-party dependencies.
