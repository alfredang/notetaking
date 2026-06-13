import Foundation

/// A bridge that lets SwiftUI views trigger imperative actions on the UIKit
/// canvas (e.g. toolbar buttons acting on the current shape selection).
@MainActor
final class CanvasController {
    var deleteSelection: () -> Void = {}
    var duplicateSelection: () -> Void = {}
    var hasSelection: () -> Bool = { false }
    var reload: (Page) -> Void = { _ in }
    /// Reloads every page view from the model (e.g. after a notebook-wide
    /// template/color change).
    var reloadAllPages: () -> Void = {}
    var undo: () -> Void = {}
    var redo: () -> Void = {}
    var setZoom: (CGFloat) -> Void = { _ in }
    var scrollToPage: (Int) -> Void = { _ in }
    /// The page currently most visible in the scroll view (what the user is
    /// looking at), used so page actions like Clear act on the right page.
    var currentVisiblePage: () -> Page? = { nil }
    /// Clears the strokes and shapes on the page the user is currently viewing,
    /// updating both the on-screen canvas and the model.
    var clearVisiblePage: () -> Void = {}
    /// Pushes the editor's current tool/color/width to every canvas immediately
    /// (called when the toolbar changes a setting, so it takes effect at once).
    var applyTool: () -> Void = {}
    /// Clears strokes and shapes on every page (live canvases + model).
    var clearAllPages: () -> Void = {}
    /// Asks the host to append a new blank page at the end (swipe-up past bottom).
    var requestNewPageAtEnd: () -> Void = {}
    /// Inserts a new blank page at the very start (swipe-down past the top).
    var requestNewPageAtStart: () -> Void = {}
    /// Inserts a new page just before / after the page currently in view.
    var requestNewPageAbove: () -> Void = {}
    var requestNewPageBelow: () -> Void = {}
    /// Recolors the currently selected shape/flowchart element.
    var setSelectedColor: (RGBAColor) -> Void = { _ in }
    /// The notebook's current paper template, and a setter that applies it
    /// notebook-wide — used by the in-canvas toolbar's template control.
    var currentPaperStyle: () -> PaperStyle = { .white }
    var setPaperStyle: (PaperStyle) -> Void = { _ in }
    /// Refreshes page thumbnails after a destructive edit (e.g. clear).
    var refreshThumbnails: () -> Void = {}
}
