import SwiftUI
import CoreGraphics

/// Canonical A4 page size in points (A4 @ 96 dpi, aspect 1:√2).
enum PageGeometry {
    static let a4 = CGSize(width: 794, height: 1123)
    static var aspectRatio: CGFloat { a4.width / a4.height }
}

/// Shared visual styling tokens for the paper-notebook look.
enum Theme {
    static let paper = Color.white
    static let canvasBackground = Color(white: 0.93)
    static let cardCornerRadius: CGFloat = 14
    static let pageCornerRadius: CGFloat = 6
    static let toolbarCornerRadius: CGFloat = 18

    static let softShadow = ShadowStyle(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

extension View {
    /// Applies the standard soft shadow used across cards and pages.
    func softShadow(_ style: Theme.ShadowStyle = Theme.softShadow) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
