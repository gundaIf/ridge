import AppKit

enum Icon {
    /// Menu bar glyph: the trackpad block from the app icon, ridge along the top, both control edges cut out.
    static func menuBar() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            NSColor.black.set()
            let block = NSBezierPath()
            block.windingRule = .evenOdd
            block.move(to: NSPoint(x: 1.5, y: 2))
            for p in [(18.5, 2.0), (18.5, 11.6), (15.6, 13.6), (12.8, 11.9), (9.6, 14.2), (6.6, 12.1), (4.1, 13.4), (1.5, 11.8)] {
                block.line(to: NSPoint(x: p.0, y: p.1))
            }
            block.close()
            block.append(NSBezierPath(roundedRect: NSRect(x: 3.6, y: 4, width: 2, height: 6.5), xRadius: 1, yRadius: 1))
            block.append(NSBezierPath(roundedRect: NSRect(x: 14.4, y: 4, width: 2, height: 6.5), xRadius: 1, yRadius: 1))
            block.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws the app icon into the current context, filling a square of `size` at `origin`.
    /// Artwork is laid out on Apple's 1024 grid (an 824pt tile with room for its shadow): a linocut
    /// of a trackpad whose top edge is a mountain ridge, with its two slider edges carved out.
    static func drawAppIcon(at origin: NSPoint = .zero, size: CGFloat) {
        let s = size / 1024
        var rng = Ink.Random(0x5249_4447_45)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: origin.x, yBy: origin.y)
        transform.scale(by: s)
        transform.concat()

        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
        NSGraphicsContext.saveGraphicsState()
        let drop = NSShadow()
        drop.shadowColor = NSColor.black.withAlphaComponent(0.3)
        drop.shadowBlurRadius = 28 * s
        drop.shadowOffset = NSSize(width: 0, height: -12 * s)
        drop.set()
        Ink.paper.setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        Ink.sheet(tile.bounds, rng: &rng)
        Ink.plateMark(NSRect(x: 150, y: 150, width: 724, height: 724), wobble: 3, rng: &rng)

        // The block: a trackpad slab with a ridge line for its top edge
        let block = NSBezierPath()
        block.move(to: NSPoint(x: 196, y: 248))
        for p in [(828, 248), (828, 668), (756, 722), (704, 686), (614, 776), (546, 708), (496, 738),
                  (414, 662), (340, 714), (278, 676), (196, 704)] {
            block.line(to: NSPoint(x: CGFloat(p.0), y: CGFloat(p.1)))
        }
        block.close()
        Ink.print(Ink.rough(block, wobble: 3.5, step: 5, rng: &rng), rng: &rng)

        // Brightness on the left, volume on the right: the level is the carved part, the
        // rest of the track a run of nicks, and a fingertip resting at the top of the volume.
        let trackBottom: CGFloat = 310, trackHeight: CGFloat = 320, barWidth: CGFloat = 44
        for (x, level) in [(CGFloat(246), CGFloat(0.5)), (CGFloat(734), CGFloat(0.76))] {
            let bar = NSBezierPath(roundedRect: NSRect(x: x, y: trackBottom, width: barWidth, height: trackHeight * level),
                                   xRadius: barWidth / 2, yRadius: barWidth / 2)
            Ink.carve(Ink.rough(bar, wobble: 2.2, step: 4, rng: &rng))
            var y = trackBottom + trackHeight * level + 26
            while y < trackBottom + trackHeight {
                let nick = NSBezierPath(ovalIn: NSRect(x: x + barWidth / 2 - 8, y: y, width: 16, height: 16))
                Ink.carve(Ink.rough(nick, wobble: 1.4, step: 3, rng: &rng))
                y += 34
            }
        }
        let tip = NSPoint(x: 734 + barWidth / 2, y: trackBottom + trackHeight * 0.76)
        Ink.carve(Ink.rough(NSBezierPath(ovalIn: NSRect(x: tip.x - 50, y: tip.y - 50, width: 100, height: 100)),
                            wobble: 2.6, step: 4, rng: &rng))
        Ink.chips(in: NSRect(x: 360, y: 300, width: 300, height: 120), count: 4, size: 30, rng: &rng)

        NSGraphicsContext.restoreGraphicsState() // tile clip

        let rim = NSBezierPath(roundedRect: NSRect(x: 101.5, y: 101.5, width: 821, height: 821), xRadius: 184, yRadius: 184)
        rim.lineWidth = 3
        NSColor.black.withAlphaComponent(0.12).setStroke()
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
