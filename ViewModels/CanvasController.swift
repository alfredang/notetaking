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
}
