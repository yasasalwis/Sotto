#!/usr/bin/env swift
//
// Renders Sotto's app icon set from the same mark the app draws in `LogoMark`:
// a rounded square in the brand teal with a white "s" set in Geist.
//
// Run from the repository root:
//     swift Scripts/make-app-icon.swift
//
// Writes PNGs into Sotto/Assets.xcassets/AppIcon.appiconset and rewrites its
// Contents.json so every slot the catalog declares has a file behind it.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Brand

/// Theme.Colors.accent — the same teal the app uses for LogoMark.
let accent = (r: 0x1F / 255.0, g: 0x6B / 255.0, b: 0x63 / 255.0)
/// Theme.Colors.accentDark — the foot of the light-appearance gradient.
let accentDeep = (r: 0x14 / 255.0, g: 0x40 / 255.0, b: 0x3C / 255.0)
/// Dark appearance sits on near-black so the mark keeps its weight against a dark Home Screen.
let darkTop = (r: 0x10 / 255.0, g: 0x1A / 255.0, b: 0x19 / 255.0)
let darkBottom = (r: 0x05 / 255.0, g: 0x0A / 255.0, b: 0x0A / 255.0)

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appending(path: "Sotto/Assets.xcassets/AppIcon.appiconset")
let fontURL = root.appending(path: "Sotto/Resources/Fonts/Geist-Variable.ttf")

// MARK: - Font

/// Loads the bundled Geist face. The icon is the app's own wordmark letter, so it must be
/// the app's own typeface; falling back to a system face would ship a different mark.
func brandFont(size: CGFloat) -> CTFont {
    guard let data = try? Data(contentsOf: fontURL),
          let provider = CGDataProvider(data: data as CFData),
          let cgFont = CGFont(provider) else {
        FileHandle.standardError.write(Data("error: cannot read \(fontURL.path)\n".utf8))
        exit(1)
    }
    let base = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
    // Geist ships as a variable font; pin the weight axis to 500 (Medium) to match LogoMark.
    let weightAxis = 0x77676874 // 'wght'
    let variation = [weightAxis: 500] as CFDictionary
    let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: variation] as CFDictionary)
    return CTFontCreateCopyWithAttributes(base, size, nil, descriptor)
}

// MARK: - Drawing

enum Appearance {
    case light   // brand teal
    case dark    // near-black
    case tinted  // greyscale; the system applies the user's tint to the luminance
}

/// Draws the mark. `inset` is the fraction of the canvas left empty around the rounded square:
/// iOS icons are full-bleed (the system masks them), macOS icons carry their own shape and margin.
func drawIcon(size: Int, appearance: Appearance, inset: CGFloat) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // Full-bleed icons must be opaque; the macOS shape needs alpha around its corners.
    let alpha: CGImageAlphaInfo = inset > 0 ? .premultipliedLast : .noneSkipLast
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: alpha.rawValue
    ) else { fatalError("cannot create \(size)px context") }

    let side = CGFloat(size)
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    let margin = side * inset
    let body = CGRect(x: margin, y: margin, width: side - margin * 2, height: side - margin * 2)
    // 22.37% of the side is the corner radius Apple's own icon grid uses for the squircle.
    let radius = body.width * (inset > 0 ? 0.2237 : 0.2237)

    if inset > 0 {
        // macOS: clip to the rounded square so the corners stay transparent.
        context.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
    }

    let (top, bottom): ((r: Double, g: Double, b: Double), (r: Double, g: Double, b: Double))
    switch appearance {
    case .light:  (top, bottom) = (accent, accentDeep)
    case .dark:   (top, bottom) = (darkTop, darkBottom)
    case .tinted: (top, bottom) = ((0.18, 0.18, 0.18), (0.05, 0.05, 0.05))
    }
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(colorSpace: space, components: [top.r, top.g, top.b, 1])!,
            CGColor(colorSpace: space, components: [bottom.r, bottom.g, bottom.b, 1])!,
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: body.maxY),
        end: CGPoint(x: 0, y: body.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // The letter. LogoMark sets it at 52% of the mark's side.
    let font = brandFont(size: body.width * 0.62)
    let ink: CGFloat = appearance == .tinted ? 0.97 : 1.0
    // CoreText attribute names, so the script needs no AppKit/UIKit.
    let attributes: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(colorSpace: space, components: [ink, ink, ink, 1])!,
    ]
    let attributed = CFAttributedStringCreate(nil, "s" as CFString, attributes as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attributed)
    // Centre on the glyph's inked bounds, not its typographic box, so the letter sits optically
    // centred in the square rather than riding the baseline.
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    context.textPosition = CGPoint(
        x: body.midX - bounds.width / 2 - bounds.minX,
        y: body.midY - bounds.height / 2 - bounds.minY
    )
    CTLineDraw(line, context)

    guard let image = context.makeImage() else { fatalError("cannot render \(size)px icon") }
    return image
}

func write(_ image: CGImage, to name: String) {
    let url = iconSet.appending(path: name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write(Data("error: cannot write \(name)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("error: cannot finalise \(name)\n".utf8))
        exit(1)
    }
    print("  \(name)  \(image.width)×\(image.height)")
}

// MARK: - Run

try? FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

print("iOS (full-bleed, opaque):")
write(drawIcon(size: 1024, appearance: .light, inset: 0), to: "icon-ios-light-1024.png")
write(drawIcon(size: 1024, appearance: .dark, inset: 0), to: "icon-ios-dark-1024.png")
write(drawIcon(size: 1024, appearance: .tinted, inset: 0), to: "icon-ios-tinted-1024.png")

print("macOS (rounded, transparent margin):")
// Apple's macOS icon grid: the body fills 824 of a 1024 canvas, a 9.765% margin per side.
let macInset: CGFloat = 100.0 / 1024.0
var macImages: [(size: Int, scale: Int)] = []
for point in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        macImages.append((point, scale))
    }
}
for entry in macImages {
    let pixels = entry.size * entry.scale
    write(drawIcon(size: pixels, appearance: .light, inset: macInset), to: "icon-mac-\(entry.size)x\(entry.size)@\(entry.scale)x.png")
}

// MARK: - Contents.json

var images: [String] = [
    """
    {
          "filename" : "icon-ios-light-1024.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        }
    """,
    """
    {
          "appearances" : [
            {
              "appearance" : "luminosity",
              "value" : "dark"
            }
          ],
          "filename" : "icon-ios-dark-1024.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        }
    """,
    """
    {
          "appearances" : [
            {
              "appearance" : "luminosity",
              "value" : "tinted"
            }
          ],
          "filename" : "icon-ios-tinted-1024.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        }
    """,
]
for entry in macImages {
    images.append("""
    {
          "filename" : "icon-mac-\(entry.size)x\(entry.size)@\(entry.scale)x.png",
          "idiom" : "mac",
          "scale" : "\(entry.scale)x",
          "size" : "\(entry.size)x\(entry.size)"
        }
    """)
}

let contents = """
{
  "images" : [
    \(images.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: ",\n    "))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(to: iconSet.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("\nWrote Contents.json with \(images.count) entries.")
