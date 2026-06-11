# NotePad — Native iPad Note-Taking App

A clean, lightweight, native iPad note-taking app optimized for Apple Pencil. It
feels like a paper notebook while providing digital note-taking, drawing,
flowchart creation, and notebook organization — fully offline and local-first.

![Build](https://github.com/alfredang/notetaking/actions/workflows/build.yml/badge.svg)

## Features

- **Dashboard** — grid of notebooks with cover thumbnail, page count, created /
  updated dates, instant search, and sort (last modified / created / alphabetical).
- **Nested notebooks** — sub-notebooks via a self-referential SwiftData relationship.
- **A4 pages** — white paper with soft shadows, continuous vertical scrolling.
- **Apple Pencil** — PencilKit canvas with pressure, tilt, palm rejection, low latency.
  Pencil draws; fingers pan and zoom (toggleable finger-drawing).
- **Tools** — pen (8 widths), highlighter (transparent), pixel & object erasers,
  8-color palette + custom color picker.
- **Shapes** — rectangle, circle, triangle, diamond, line, arrow, with stroke /
  fill / width / opacity. Rendered as an independent, editable **vector overlay**.
- **Flowcharts** — process, decision, start/end nodes and connectors that **snap to
  nodes** and re-route automatically when a node is moved.
- **Selection** — move, resize, duplicate, delete shapes; lasso for ink.
- **Zoom & pan** — pinch to zoom (25%–500% presets), two-finger pan.
- **Page management** — add (insert before / after / at end), duplicate, clear
  (with confirmation), delete, drag-to-reorder via the thumbnail sidebar.
- **Auto save** — every stroke and shape change is debounced and persisted; no save button.
- **Export** — page to PNG / JPG / PDF; whole notebook to a combined PDF.

## Tech Stack

- **SwiftUI** + **PencilKit** + **PDFKit**
- **SwiftData** persistence (local-first, offline)
- **Swift 6** language mode with **complete strict concurrency**
- **Observation** framework (`@Observable`), `@MainActor` isolation
- **MVVM** + **Repository** pattern
- iPadOS **18+**

## Architecture

```
SwiftUI Views ──> ViewModels (@Observable) ──> Repositories ──> SwiftData
                       │
                       ├─> AutoSaveService (debounced persistence)
                       └─> ExportService (PNG / JPG / PDF)

Editor = zoom/pan UIScrollView
         └─ vertical stack of PageContainerViews
              ├─ PKCanvasView      (handwriting / drawing, pencil-only)
              └─ ShapeOverlayView  (vector shapes + flowchart connectors)
```

The gesture conflict between drawing, panning and zooming is resolved by setting
`drawingPolicy = .pencilOnly` and disabling each canvas's internal scrolling, so a
single outer scroll view owns pan/zoom while the Pencil draws.

## Project Layout

```
App/          App entry, root view, theme
Models/       Notebook, Page (SwiftData), CanvasItem/Shape (Codable overlay model)
ViewModels/   Dashboard / Notebook / Editor view models, tool + canvas controllers
Services/     Storage, Repositories, AutoSave, Export, PageRenderer, date formatting
PencilKit/    CanvasContainerView (scroll + zoom host)
Components/   PageContainerView, ShapeOverlayView, ShapePath, ThumbnailView
Views/        Dashboard, Notebook, Editor, Sidebar, Toolbar, Settings, Export
```

## Building

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonsm/XcodeGen) (the `.xcodeproj` is **not** checked in).

```bash
brew install xcodegen      # once
xcodegen generate          # creates NotePadApp.xcodeproj
open NotePadApp.xcodeproj
```

Select an **iPad (iPadOS 18+) simulator** or a physical iPad and press **Run**.

### Command-line build

```bash
xcodegen generate
xcodebuild -project NotePadApp.xcodeproj -scheme NotePadApp \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Continuous Integration

`.github/workflows/build.yml` runs on every push / PR to `main`: it installs
XcodeGen, generates the project, and compiles for the iOS Simulator on a macOS runner.

## Roadmap (Phase 2)

iCloud sync · handwriting recognition / OCR search · notebook sharing &
collaboration · audio notes · infinite canvas · sticky notes · PDF annotation.
