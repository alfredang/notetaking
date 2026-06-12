// Generates the 1024x1024 App Store marketing icon for NotePad.
// Full-bleed (no transparency / no rounded corners — Apple applies the mask).
//
// Usage:  swift scripts/generate_icon.swift [output.png]
// Default output: Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

import AppKit
import CoreGraphics
import Foundation

let side = 1024
let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

let cs = CGColorSpaceCreateDeviceRGB()
// noneSkipLast => opaque image with NO alpha channel (App Store requirement).
guard let ctx = CGContext(
    data: nil, width: side, height: side,
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("ctx") }

let S = CGFloat(side)
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

// MARK: Background gradient (brand blue)
let bg = CGGradient(colorsSpace: cs,
    colors: [rgb(0.27, 0.56, 0.98), rgb(0.16, 0.37, 0.86)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

// MARK: White paper card (portrait, centered, soft shadow)
let pageRect = CGRect(x: S * 0.255, y: S * 0.165, width: S * 0.46, height: S * 0.62)
let corner: CGFloat = 46

// shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 50, color: rgb(0, 0, 0, 0.28))
let pagePath = CGPath(roundedRect: pageRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
ctx.addPath(pagePath)
ctx.setFillColor(rgb(1, 1, 1))
ctx.fillPath()
ctx.restoreGState()

// MARK: Ruled lines
ctx.saveGState()
ctx.addPath(pagePath)
ctx.clip()
ctx.setStrokeColor(rgb(0.80, 0.84, 0.90))
ctx.setLineWidth(7)
let lineInsetX = pageRect.width * 0.13
let firstY = pageRect.maxY - pageRect.height * 0.26
let gap = pageRect.height * 0.115
for i in 0..<4 {
    let y = firstY - CGFloat(i) * gap
    ctx.move(to: CGPoint(x: pageRect.minX + lineInsetX, y: y))
    ctx.addLine(to: CGPoint(x: pageRect.maxX - lineInsetX, y: y))
}
ctx.strokePath()

// A small flowchart hint: two connected nodes near the top of the page
ctx.setStrokeColor(rgb(0.30, 0.69, 0.31))
ctx.setLineWidth(9)
let nodeA = CGRect(x: pageRect.minX + lineInsetX, y: pageRect.maxY - pageRect.height * 0.19, width: 86, height: 56)
let nodeB = CGRect(x: pageRect.maxX - lineInsetX - 86, y: pageRect.maxY - pageRect.height * 0.19, width: 86, height: 56)
ctx.addPath(CGPath(roundedRect: nodeA, cornerWidth: 14, cornerHeight: 14, transform: nil))
ctx.addPath(CGPath(roundedRect: nodeB, cornerWidth: 14, cornerHeight: 14, transform: nil))
ctx.strokePath()
// connector arrow between nodes
ctx.move(to: CGPoint(x: nodeA.maxX, y: nodeA.midY))
ctx.addLine(to: CGPoint(x: nodeB.minX, y: nodeB.midY))
ctx.strokePath()
ctx.restoreGState()

// MARK: Pencil (diagonal, over the page)
ctx.saveGState()
ctx.translateBy(x: S * 0.62, y: S * 0.30)
ctx.rotate(by: .pi / 4 * 1.15)
let pw: CGFloat = 92          // pencil body width
let bodyLen: CGFloat = 470
// body (orange)
ctx.setFillColor(rgb(1.0, 0.70, 0.16))
ctx.fill(CGRect(x: -pw/2, y: 0, width: pw, height: bodyLen))
// center stripe
ctx.setFillColor(rgb(0.96, 0.55, 0.10))
ctx.fill(CGRect(x: -pw*0.12, y: 0, width: pw*0.24, height: bodyLen))
// ferrule (metal band)
ctx.setFillColor(rgb(0.78, 0.82, 0.86))
ctx.fill(CGRect(x: -pw/2, y: -54, width: pw, height: 54))
// eraser (pink)
ctx.setFillColor(rgb(0.95, 0.45, 0.55))
ctx.fill(CGRect(x: -pw/2, y: -54 - 60, width: pw, height: 60))
// wooden tip (triangle)
ctx.setFillColor(rgb(0.97, 0.86, 0.70))
ctx.beginPath()
ctx.move(to: CGPoint(x: -pw/2, y: bodyLen))
ctx.addLine(to: CGPoint(x: pw/2, y: bodyLen))
ctx.addLine(to: CGPoint(x: 0, y: bodyLen + 120))
ctx.closePath()
ctx.fillPath()
// graphite point
ctx.setFillColor(rgb(0.18, 0.18, 0.20))
ctx.beginPath()
ctx.move(to: CGPoint(x: -pw*0.18, y: bodyLen + 86))
ctx.addLine(to: CGPoint(x: pw*0.18, y: bodyLen + 86))
ctx.addLine(to: CGPoint(x: 0, y: bodyLen + 120))
ctx.closePath()
ctx.fillPath()
ctx.restoreGState()

// MARK: Write PNG
guard let image = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
let url = URL(fileURLWithPath: outPath)
try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try! data.write(to: url)
print("Wrote \(outPath) (\(data.count) bytes)")
