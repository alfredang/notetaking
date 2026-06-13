import Foundation

/// A bridge that lets SwiftUI views trigger imperative actions on the UIKit
/// canvas (e.g. toolbar buttons acting on the current shape selection).
@MainActor
final class CanvasController {
    var deleteSelection: () -> Void = {}
    var duplicateSelection: () -> Void = {}
    var hasSelection: () -> Bool = { false }
    var reload: (Page) -> Void = { _ in }
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
}
