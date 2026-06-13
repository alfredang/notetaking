# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

NotePad — a native **iPad-only** (iPadOS 18+) note-taking app for Apple Pencil. SwiftUI + PencilKit + PDFKit, SwiftData persistence, Swift 6 with **complete strict concurrency** and `@MainActor` isolation throughout. MVVM + Repository pattern.

## Build & run

The `.xcodeproj` is **generated** from `project.yml` via [XcodeGen](https://github.com/yonsm/XcodeGen) and is **not** the source of truth — never hand-edit the `.xcodeproj`. After changing `project.yml`, target sources, settings, entitlements, or Info.plist wiring, regenerate:

```bash
xcodegen generate            # brew install xcodegen (once)
```

Command-line build (what CI runs — generic device, signing off):

```bash
xcodebuild -project NotePadApp.xcodeproj -scheme NotePadApp \
  -destination 'generic/platform=iOS' -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

Build + run on a booted simulator (iPad — `TARGETED_DEVICE_FAMILY` is iPad-only):

```bash
xcodebuild -project NotePadApp.xcodeproj -scheme NotePadApp -configuration Debug \
  -destination 'id=<SIMULATOR_UDID>' -derivedDataPath /tmp/dd build
xcrun simctl install <UDID> /tmp/dd/Build/Products/Debug-iphonesimulator/NotePadApp.app
xcrun simctl launch <UDID> com.notepad.app
```

There is **no test target** (`testTargets: []`). CI (`.github/workflows/build.yml`) only compiles for the iOS Simulator on every push/PR to `main`.

## Persistence & iCloud sync

- Two SwiftData `@Model`s: `Notebook` (self-referential parent/children nesting) and `Page`. The single `ModelContainer` is created in [App/NotePadApp.swift](App/NotePadApp.swift) and injected via `.modelContainer`.
- The store is **CloudKit-backed** (`cloudKitDatabase: .private("iCloud.com.notepad.app")`) — notebooks and pages auto-sync to the user's private iCloud DB. This imposes hard schema rules that are easy to break: **no `@Attribute(.unique)`**, every attribute must have a default value, and **every relationship must be optional** (that's why `Notebook.pages` / `Notebook.children` are `[Page]?` / `[Notebook]?`). Violating any of these makes the container fail to load and the app `fatalError`s at launch. Read array relationships through the non-optional `orderedPages` / `orderedChildren` accessors rather than touching the optionals directly.
- CloudKit requires the iCloud entitlements in [App/NotePadApp.entitlements](App/NotePadApp.entitlements) and the `remote-notification` background mode in `Info.plist`; signing is Automatic (team selected in Xcode).

## Architecture

```
SwiftUI Views ─> ViewModels (@Observable) ─> Repositories ─> SwiftData ─> CloudKit
                      ├─> AutoSaveService (debounced persistence)
                      └─> ExportService (PNG / JPG / PDF)
```

- **DI is constructor-based, rooted at [App/RootView.swift](App/RootView.swift)**: it reads `modelContext` from the environment and hands a `NotebookRepository` to `DashboardViewModel`. Repositories ([Services/Repositories.swift](Services/Repositories.swift)) wrap `ModelContext` behind `NotebookRepositoryProtocol` / `PageRepositoryProtocol` and are the **only** place that calls `context.save()`. All repo methods use Swift typed throws (`throws(StorageError)`).
- **Page ordering** is an explicit `pageIndex` field, re-indexed on every insert/delete/move/duplicate (see `PageRepository.reindex`). `sortIndex` plays the same role for sibling notebooks.

### The editor (the subtle part)

The editor stacks two independent layers per page and resolves a three-way gesture conflict (draw vs. pan vs. zoom):

- A single outer zoom/pan `UIScrollView` ([PencilKit/CanvasContainerView](PencilKit/)) owns pan & zoom and hosts a vertical stack of `PageContainerView`s. Each page's `PKCanvasView` has its **internal scrolling disabled** and `drawingPolicy = .pencilOnly`, so the Pencil draws while fingers pan/zoom. Finger-drawing is an opt-in toggle (`.anyInput`).
- **Layer 1 — handwriting**: `PKCanvasView`, serialized to `Page.drawingData` (`PKDrawing.dataRepresentation()`).
- **Layer 2 — vector overlay**: `ShapeOverlayView` renders shapes + flowchart connectors from `[CanvasItem]` (JSON-encoded into `Page.shapesData`; access via the `Page.items` computed property). `CanvasItem`/`ShapeKind` ([Models/Shape.swift](Models/Shape.swift)) is a plain `Codable` model — **not** SwiftData. Shapes use `frame`; line-like items use `start`/`end`; flowchart connectors bind to node ids and re-route when a node moves. Colors are stored as `RGBAColor` (SwiftUI/UIColor aren't `Codable`).
- **`EditorViewModel`** holds tool-palette state and resolves the active `PKTool` via its `pkTool`/`drawingPolicy` computed properties. **`CanvasController`** ([ViewModels/CanvasController.swift](ViewModels/CanvasController.swift)) is a closure-bag bridge letting SwiftUI toolbar buttons invoke imperative actions (delete/duplicate selection, undo/redo, zoom, scroll-to-page) on the UIKit canvas.
- **`AutoSaveService`** debounces edits (~0.4s) into a single `context.save()`, with an immediate `saveNow()` on editor exit/background. There is no save button.

## Conventions

- New `@Model` properties must stay CloudKit-compatible (optional or defaulted; no unique constraints) or the app won't launch — see the persistence section above.
- Everything is `@MainActor`; ViewModels are `@Observable` (Observation framework, not Combine). Keep new types `Sendable` where they cross concurrency boundaries — strict concurrency is set to `complete`.
- Repositories own all saves; views/view models mutate models and call repo methods rather than touching `ModelContext` directly.
