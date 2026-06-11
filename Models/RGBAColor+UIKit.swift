import SwiftUI
import UIKit

extension RGBAColor {
    init(_ uiColor: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    init(_ color: Color) {
        self.init(UIColor(color))
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var cgColor: CGColor {
        uiColor.cgColor
    }
}
