import AppKit

enum Icon {
    /// Menu bar glyph: a trackpad outline with its two control edges filled in.
    static func menuBar() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            NSColor.black.set()
            let pad = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 2.25, width: 16.5, height: 11.5), xRadius: 2.5, yRadius: 2.5)
            pad.lineWidth = 1.4
            pad.stroke()
            NSBezierPath(roundedRect: NSRect(x: 4, y: 4.5, width: 1.8, height: 7), xRadius: 0.9, yRadius: 0.9).fill()
            NSBezierPath(roundedRect: NSRect(x: 14.2, y: 4.5, width: 1.8, height: 7), xRadius: 0.9, yRadius: 0.9).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    static let warm = [NSColor(srgbRed: 1.0, green: 0.48, blue: 0.20, alpha: 1), NSColor(srgbRed: 1.0, green: 0.82, blue: 0.36, alpha: 1)]
    static let cool = [NSColor(srgbRed: 0.24, green: 0.62, blue: 1.0, alpha: 1), NSColor(srgbRed: 0.62, green: 0.45, blue: 1.0, alpha: 1)]

    private static func hex(_ value: Int, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255, alpha: alpha)
    }

    private static func shadow(_ color: NSColor, blur: CGFloat, y: CGFloat = 0, scale: CGFloat) {
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowBlurRadius = blur * scale
        shadow.shadowOffset = NSSize(width: 0, height: y * scale)
        shadow.set()
    }

    /// Draws the app icon into the current context, filling a square of `size` at `origin`.
    /// Artwork is laid out on Apple's 1024 grid (an 824pt tile with room for its shadow).
    static func drawAppIcon(at origin: NSPoint = .zero, size: CGFloat) {
        let s = size / 1024
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: origin.x, yBy: origin.y)
        transform.scale(by: s)
        transform.concat()

        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
        NSGraphicsContext.saveGraphicsState()
        shadow(.black.withAlphaComponent(0.35), blur: 28, y: -12, scale: s)
        hex(0x1A1B27).setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        NSGradient(colors: [hex(0x0E0F17), hex(0x1D1F2E), hex(0x34385A)], atLocations: [0, 0.45, 1], colorSpace: .sRGB)?
            .draw(in: tile, angle: 90)
        NSGradient(colors: [hex(0x7C8CFF, 0.22), hex(0x7C8CFF, 0)])?
            .draw(in: tile, relativeCenterPosition: NSPoint(x: -0.15, y: 0.55))

        // The trackpad
        let slabRect = NSRect(x: 196, y: 286, width: 632, height: 452)
        let slab = NSBezierPath(roundedRect: slabRect, xRadius: 70, yRadius: 70)
        NSGraphicsContext.saveGraphicsState()
        shadow(.black.withAlphaComponent(0.6), blur: 60, y: -26, scale: s)
        hex(0x262938).setFill()
        slab.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors: [hex(0x232636), hex(0x3A3E58)])?.draw(in: slab, angle: 90)
        NSGraphicsContext.saveGraphicsState()
        slab.addClip()
        let sheen = NSBezierPath(roundedRect: slabRect.insetBy(dx: 2, dy: 2), xRadius: 68, yRadius: 68)
        sheen.lineWidth = 4
        NSGradient(colors: [hex(0xFFFFFF, 0.0), hex(0xFFFFFF, 0.22)])?.draw(in: slab, angle: 90)
        hex(0x12131C).setFill()
        NSBezierPath(roundedRect: slabRect.insetBy(dx: 4, dy: 4).offsetBy(dx: 0, dy: -2), xRadius: 66, yRadius: 66).fill()
        NSGradient(colors: [hex(0x24273A), hex(0x353954)])?
            .draw(in: NSBezierPath(roundedRect: slabRect.insetBy(dx: 4, dy: 4).offsetBy(dx: 0, dy: -2), xRadius: 66, yRadius: 66), angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        // Edge sliders: brightness (warm) on the left, volume (cool) on the right
        let trackBottom: CGFloat = 346, trackHeight: CGFloat = 332, barWidth: CGFloat = 34
        for (x, colors, level) in [(CGFloat(240), warm, CGFloat(0.5)), (CGFloat(750), cool, CGFloat(0.74))] {
            let track = NSBezierPath(roundedRect: NSRect(x: x, y: trackBottom, width: barWidth, height: trackHeight), xRadius: 17, yRadius: 17)
            hex(0x000000, 0.28).setFill()
            track.fill()
            let fillRect = NSRect(x: x, y: trackBottom, width: barWidth, height: trackHeight * level)
            let fill = NSBezierPath(roundedRect: fillRect, xRadius: 17, yRadius: 17)
            NSGraphicsContext.saveGraphicsState()
            shadow(colors[0].withAlphaComponent(0.9), blur: 46, scale: s)
            colors[0].setFill()
            fill.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGradient(colors: colors)?.draw(in: fill, angle: 90)
        }

        // A fingertip resting on the volume edge
        let tip = NSPoint(x: 767, y: trackBottom + trackHeight * 0.74)
        let dot = NSBezierPath(ovalIn: NSRect(x: tip.x - 38, y: tip.y - 38, width: 76, height: 76))
        NSGraphicsContext.saveGraphicsState()
        shadow(cool[1].withAlphaComponent(1), blur: 50, scale: s)
        hex(0xFFFFFF).setFill()
        dot.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors: [hex(0xDCE3FF), hex(0xFFFFFF)])?.draw(in: dot, angle: 90)

        NSGraphicsContext.restoreGraphicsState() // tile clip

        let rim = NSBezierPath(roundedRect: NSRect(x: 101.5, y: 101.5, width: 821, height: 821), xRadius: 184, yRadius: 184)
        rim.lineWidth = 3
        hex(0xFFFFFF, 0.10).setStroke()
        rim.stroke()

        NSGraphicsContext.restoreGraphicsState()
    }

    /// Renders `draw` into a PNG of the given pixel size.
    static func png(width: Int, height: Int, _ draw: () -> Void) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// 1024px app icon, written as PNG by `Ridge --icon <path>` during the build.
    static func writeAppIcon(to path: String) {
        try? png(width: 1024, height: 1024) { drawAppIcon(size: 1024) }?.write(to: URL(fileURLWithPath: path))
    }
}
