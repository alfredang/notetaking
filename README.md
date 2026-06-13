# NotePad — Native iPad Note-Taking App

A clean, lightweight, native iPad note-taking app optimized for Apple Pencil. It
feels like a paper notebook while providing digital note-taking, drawing,
flowchart creation, and notebook organization — with iCloud sync across devices.

![Build](https://github.com/alfredang/notepadapp/actions/workflows/build.yml/badge.svg)

<p align="center">
  <img src="docs/screenshots/editor.png" alt="Editor with flowchart, sticky note and tool palette" width="45%" />
  &nbsp;&nbsp;
  <img src="docs/screenshots/dashboard.png" alt="Notebook dashboard" width="45%" />
</p>

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
- **iCloud sync** — notebooks and pages auto-sync across your devices via CloudKit (private database).
- **Handwriting / OCR search** — pages are indexed with Vision text recognition, so dashboard search finds words inside your handwriting and shapes.
- **Sticky notes** — drop a colored note card and double-tap to edit its text (also works on flowchart nodes).
- **Audio notes** — record, play back, and delete voice memos attached to a notebook.
- **PDF annotation** — import a PDF as annotatable pages and mark it up with any tool.
- **Infinite canvas** — extend a page in A4-height increments for a continuous, no-page-break vertical canvas.
- **Notebook sharing** — export a full notebook (pages, PDF backgrounds, voice memos) to a portable `.notebook` file and import it on another device.

## Tech Stack

- **SwiftUI** + **PencilKit** + **PDFKit** + **Vision** (OCR) + **AVFoundation** (audio)
- **SwiftData** persistence with **CloudKit** iCloud sync
- **Swift 6** language mode with **complete strict concurrency**
- **Observation** framework (`@Observable`), `@MainActor` isolation
- **MVVM** + **Repository** pattern
- iPadOS **18+**

## Architecture

```
SwiftUI Views ──> ViewModels (@Observable) ──> Repositories ──> SwiftData ──> CloudKit
                       │
                       ├─> AutoSaveService (debounced save + Vision OCR indexing)
                       ├─> ExportService / NotebookArchiveService (PDF, PNG, .notebook)
                       └─> AudioRecorder / PDFImport services

Editor = zoom/pan UIScrollView
         └─ vertical stack of PageContainerViews (height = N × A4)
              ├─ background image  (imported PDF page)
              ├─ PKCanvasView      (handwriting / drawing, pencil-only)
              └─ ShapeOverlayView  (vector shapes, flowchart connectors, sticky notes)
```

The gesture conflict between drawing, panning and zooming is resolved by setting
`drawingPolicy = .pencilOnly` and disabling each canvas's internal scrolling, so a
single outer scroll view owns pan/zoom while the Pencil draws.

## Project Layout

```
App/          App entry (CloudKit container), root view, theme, entitlements
Models/       Notebook, Page, AudioNote (SwiftData), CanvasItem/Shape (Codable overlay)
ViewModels/   Dashboard / Notebook / Editor view models, tool + canvas controllers
Services/     Repositories, AutoSave (+OCR), Export, NotebookArchive, PDFImport,
              TextRecognition (Vision), Audio (AVFoundation), PageRenderer
PencilKit/    CanvasContainerView (scroll + zoom host)
Components/   PageContainerView, ShapeOverlayView, ShapePath, ThumbnailView
Views/        Dashboard, Notebook, Editor, Sidebar, Toolbar, Settings, Export, AudioNotes
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

## Roadmap

**Phase 2 — shipped:** iCloud sync · handwriting / OCR search · sticky notes ·
audio notes · infinite (extendable) canvas · PDF annotation · notebook sharing.

**Next:** real-time collaboration (live CKShare co-editing — current sharing is
file-based) · handwriting-to-text conversion · sticky-note colors · web companion.
