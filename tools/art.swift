import AppKit

// Usage: swift tools/art.swift <header|search> <screenshot dir> <out.png>
// App Store creative assets: the product page header (21:9, 3840 × 1646) and the search results asset
// (3:2, 3840 × 2560), from the 6.9" screenshots tools/screenshots.sh takes. The app's near-black,
// its mint accent and the collision screen's bit grid. No alpha channel.

func rgb(_ v: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: a)
}
// Style.swift's appBackground and hairline, and the accent colour.
let background = rgb(0x0A0A0B), hairline = rgb(0x232326), mint = rgb(0x5EE6A8)

let args = CommandLine.arguments
let kind = args[1], shots = args[2]
let (W, H): (CGFloat, CGFloat) = kind == "header" ? (3840, 1646) : (3840, 2560)

let cg = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
cg.translateBy(x: 0, y: H); cg.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
background.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()

/// The app's generator, so every render draws the same grid.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The collision screen's grid, filling the canvas: dim cells, with a mint run of matching bits that
/// fades out towards the edges so the app screens stay the focus.
func bitGrid(cell: CGFloat, gap: CGFloat, litRows: ClosedRange<Int>) {
    let pitch = cell + gap
    let columns = Int(W / pitch) + 1, rows = Int(H / pitch) + 1
    let x0 = (W - CGFloat(columns) * pitch + gap) / 2, y0 = (H - CGFloat(rows) * pitch + gap) / 2
    var rng = SplitMix64(state: 2022)
    for row in 0..<rows {
        for column in 0..<columns {
            let rect = NSRect(x: x0 + CGFloat(column) * pitch, y: y0 + CGFloat(row) * pitch, width: cell, height: cell)
            let fromCentre = abs(rect.midX - W / 2) / (W / 2)
            let lit = litRows.contains(row) && Double.random(in: 0..<1, using: &rng) > Double(fromCentre) * 0.9
            (lit ? mint.withAlphaComponent(0.55 * (1 - fromCentre * 0.7)) : hairline.withAlphaComponent(0.6)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: cell * 0.18, yRadius: cell * 0.18).fill()
        }
    }
}

/// An app screen with rounded corners and a hairline edge, rotated by `angle` degrees about its centre.
func phone(_ name: String, center: NSPoint, height: CGFloat, angle: CGFloat = 0) {
    guard let img = NSImage(contentsOfFile: "\(shots)/\(name)") else { fatalError("missing \(shots)/\(name)") }
    let h = height, w = h * img.size.width / img.size.height, r = w * 0.12
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform(); t.translateX(by: center.x, yBy: center.y); t.rotate(byDegrees: angle); t.concat()
    let rect = NSRect(x: -w / 2, y: -h / 2, width: w, height: h)
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.8); shadow.shadowBlurRadius = 120
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    rgb(0x3A3A3F).setFill(); NSBezierPath(roundedRect: rect.insetBy(dx: -10, dy: -10), xRadius: r + 10, yRadius: r + 10).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).addClip()
    img.draw(in: rect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
}

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    return NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
                                                      .paragraphStyle: p, .kern: -size * 0.02])
}

let home = "iPhone 17 Pro Max-1-home.png", settings = "iPhone 17 Pro Max-2-settings.png", collision = "iPhone 17 Pro Max-3-collision.png"
if kind == "header" {
    // No words: the grid behind, a search in progress and the collision it finds, kept in the centre
    // because each device crops the edges and the page's title covers the bottom.
    bitGrid(cell: 84, gap: 18, litRows: 6...9)
    phone(home, center: NSPoint(x: 1530, y: 860), height: 1420, angle: -5)
    phone(collision, center: NSPoint(x: 2310, y: 860), height: 1420, angle: 5)
} else {
    // Search results: what the app does at a glance, then the app itself.
    bitGrid(cell: 84, gap: 18, litRows: 7...7)
    // Clear the grid behind the words so they read cleanly, fading into it below.
    let fade = NSGradient(starting: background, ending: background.withAlphaComponent(0))!
    background.setFill(); NSRect(x: 0, y: 0, width: W, height: 560).fill()
    fade.draw(in: NSRect(x: 0, y: 560, width: W, height: 140), angle: 90)
    let head = NSMutableAttributedString(attributedString: text("Find SHA-256 collisions", size: 210, weight: .bold, color: .white))
    head.addAttribute(.foregroundColor, value: mint, range: NSRange(location: 5, length: 7))
    head.draw(in: NSRect(x: 0, y: 190, width: W, height: head.size().height))
    let sub = text("On your iPhone's GPU. Every search reproducible from a seed.", size: 96, weight: .regular, color: rgb(0xA0A0A8))
    sub.draw(in: NSRect(x: 0, y: 190 + head.size().height + 40, width: W, height: sub.size().height))
    phone(home, center: NSPoint(x: 780, y: 1960), height: 2050)
    phone(collision, center: NSPoint(x: 1920, y: 1900), height: 2050)
    phone(settings, center: NSPoint(x: 3060, y: 1960), height: 2050)
}

NSGraphicsContext.current = nil
let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[3]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dst, cg.makeImage()!, nil); CGImageDestinationFinalize(dst)
print(args[3])
