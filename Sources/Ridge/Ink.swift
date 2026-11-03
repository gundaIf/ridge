import AppKit

/// Block-print drawing kit: hand-cut edges, speckled ink and fibrous paper, so the artwork reads
/// like a linocut pulled by hand. Everything is seeded, so every build renders the same print.
enum Ink {
    static let black = NSColor(srgbRed: 0.090, green: 0.086, blue: 0.075, alpha: 1)
    /// The sheet, and the slightly paler area the plate pressed into.
    static let paper = NSColor(srgbRed: 0.918, green: 0.886, blue: 0.808, alpha: 1)
    static let plate = NSColor(srgbRed: 0.945, green: 0.922, blue: 0.857, alpha: 1)

    struct Random {
        private var state: UInt64
        init(_ seed: UInt64) { state = seed }

        mutating func next() -> UInt64 { // SplitMix64
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
        mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * unit() }
    }

    // MARK: Cutting

    /// Re-traces `path` with a hand-cut edge: a slow wobble, fine jitter and the odd chip.
    static func rough(_ path: NSBezierPath, wobble: CGFloat, step: CGFloat = 6, rng: inout Random) -> NSBezierPath {
        let out = NSBezierPath()
        out.windingRule = path.windingRule
        for loop in loops(of: path.flattened) {
            let points = resample(loop, step: step)
            let n = points.count
            guard n > 3 else { continue }
            // Value noise with a knot every 7 points, eased between knots.
            let period = 7, knotCount = (n + period - 1) / period
            let knots = (0..<knotCount).map { _ in rng.range(-1, 1) }
            var chip = 0, chipDepth: CGFloat = 0
            for i in 0..<n {
                let a = points[(i + n - 1) % n], b = points[(i + 1) % n]
                let len = max(hypot(b.x - a.x, b.y - a.y), 0.0001)
                let normal = NSPoint(x: (b.y - a.y) / len, y: (a.x - b.x) / len)
                let k = CGFloat(i) / CGFloat(period), k0 = Int(k), t = k - CGFloat(k0), e = t * t * (3 - 2 * t)
                let slow = knots[k0 % knotCount] * (1 - e) + knots[(k0 + 1) % knotCount] * e
                if chip == 0, rng.unit() < 0.025 { chip = Int(rng.range(2, 5)); chipDepth = rng.range(1.5, 3.5) }
                var d = wobble * (slow + rng.range(-0.35, 0.35))
                if chip > 0 { d -= wobble * chipDepth; chip -= 1 }
                let p = NSPoint(x: points[i].x + normal.x * d, y: points[i].y + normal.y * d)
                if i == 0 { out.move(to: p) } else { out.line(to: p) }
            }
            out.close()
        }
        return out
    }

    /// Clears `shape` back to bare paper, as if cut out of the block.
    static func carve(_ shape: NSBezierPath) {
        plate.setFill()
        shape.fill()
    }

    /// Small slivers knocked out of the block where the gouge slipped.
    static func chips(in rect: NSRect, count: Int, size: CGFloat, rng: inout Random) {
        plate.setFill()
        for _ in 0..<count {
            let c = NSPoint(x: rng.range(rect.minX, rect.maxX), y: rng.range(rect.minY, rect.maxY))
            let angle = rng.range(0, .pi * 2), length = size * rng.range(0.4, 1), width = length * rng.range(0.2, 0.45)
            let dir = NSPoint(x: cos(angle), y: sin(angle)), perp = NSPoint(x: -dir.y, y: dir.x)
            let sliver = NSBezierPath()
            sliver.move(to: NSPoint(x: c.x - dir.x * length * 0.5, y: c.y - dir.y * length * 0.5))
            sliver.line(to: NSPoint(x: c.x + perp.x * width, y: c.y + perp.y * width))
            sliver.line(to: NSPoint(x: c.x + dir.x * length * rng.range(0.5, 1), y: c.y + dir.y * length * rng.range(0.5, 1)))
            sliver.line(to: NSPoint(x: c.x - perp.x * width * 0.5, y: c.y - perp.y * width * 0.5))
            sliver.close()
            sliver.fill()
        }
    }

    /// A tapered gouge stroke carved along `points`, thickest in the middle.
    static func gouge(_ points: [NSPoint], width: CGFloat, rng: inout Random) {
        guard points.count > 1 else { return }
        var left: [NSPoint] = [], right: [NSPoint] = []
        for (i, p) in points.enumerated() {
            let a = points[max(i - 1, 0)], b = points[min(i + 1, points.count - 1)]
            let len = max(hypot(b.x - a.x, b.y - a.y), 0.0001)
            let normal = NSPoint(x: -(b.y - a.y) / len, y: (b.x - a.x) / len)
            let w = width * sin(.pi * CGFloat(i) / CGFloat(points.count - 1)) * rng.range(0.7, 1.15) / 2
            left.append(NSPoint(x: p.x + normal.x * w, y: p.y + normal.y * w))
            right.append(NSPoint(x: p.x - normal.x * w, y: p.y - normal.y * w))
        }
        let stroke = NSBezierPath()
        stroke.move(to: left[0])
        left.dropFirst().forEach { stroke.line(to: $0) }
        right.reversed().forEach { stroke.line(to: $0) }
        stroke.close()
        carve(stroke)
    }

    // MARK: Printing

    /// Inks `shape` the way a brayer lays it down: mostly solid, flecked with paper where the
    /// ink didn't take, uneven in pressure and worn along the cut edges. `grain` scales the flecks.
    static func print(_ shape: NSBezierPath, grain: CGFloat = 1, rng: inout Random) {
        black.setFill()
        shape.fill()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        let b = shape.bounds
        for _ in 0..<(Int(b.width * b.height / (40000 * grain * grain)) + 1) {
            let r = rng.range(60, 200) * grain
            plate.withAlphaComponent(rng.range(0.008, 0.022)).setFill()
            NSBezierPath(ovalIn: NSRect(x: rng.range(b.minX, b.maxX) - r, y: rng.range(b.minY, b.maxY) - r,
                                        width: r * 2, height: r * 1.4)).fill()
        }
        for _ in 0..<Int(b.width * b.height / (32 * grain * grain)) {
            let r = (pow(rng.unit(), 5) * 3 + 0.3) * grain
            plate.withAlphaComponent(rng.range(0.35, 0.95)).setFill()
            NSBezierPath(ovalIn: NSRect(x: rng.range(b.minX, b.maxX), y: rng.range(b.minY, b.maxY),
                                        width: r, height: r * rng.range(0.6, 1.4))).fill()
        }
        for loop in loops(of: shape.flattened) {
            for p in resample(loop, step: 3 * grain) where rng.unit() < 0.5 {
                let r = rng.range(0.6, 2.4) * grain
                plate.withAlphaComponent(rng.range(0.5, 1)).setFill()
                NSBezierPath(ovalIn: NSRect(x: p.x + rng.range(-3, 3) * grain - r / 2, y: p.y + rng.range(-3, 3) * grain - r / 2,
                                            width: r, height: r)).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Cream sheet with flecks and fibres in it.
    static func sheet(_ rect: NSRect, rng: inout Random) {
        paper.setFill()
        rect.fill()
        for _ in 0..<Int(rect.width * rect.height / 90) {
            let r = rng.range(0.5, 1.6)
            (rng.unit() < 0.7 ? NSColor.black.withAlphaComponent(rng.range(0.03, 0.08))
                              : NSColor.white.withAlphaComponent(rng.range(0.15, 0.35))).setFill()
            NSBezierPath(ovalIn: NSRect(x: rng.range(rect.minX, rect.maxX), y: rng.range(rect.minY, rect.maxY), width: r, height: r)).fill()
        }
        for _ in 0..<Int(rect.width * rect.height / 9000) {
            let start = NSPoint(x: rng.range(rect.minX, rect.maxX), y: rng.range(rect.minY, rect.maxY))
            let angle = rng.range(0, .pi * 2), length = rng.range(6, 18)
            let fibre = NSBezierPath()
            fibre.move(to: start)
            fibre.curve(to: NSPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length),
                        controlPoint1: NSPoint(x: start.x + rng.range(-6, 6), y: start.y + rng.range(-6, 6)),
                        controlPoint2: NSPoint(x: start.x + cos(angle) * length * 0.6 + rng.range(-6, 6),
                                               y: start.y + sin(angle) * length * 0.6 + rng.range(-6, 6)))
            fibre.lineWidth = rng.range(0.5, 1)
            NSColor.black.withAlphaComponent(rng.range(0.04, 0.08)).setStroke()
            fibre.stroke()
        }
    }

    /// The pressed, slightly paler rectangle a plate leaves in the sheet, with its raised torn edge.
    static func plateMark(_ rect: NSRect, wobble: CGFloat = 2.2, rng: inout Random) {
        let edge = rough(NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8), wobble: wobble, step: 3, rng: &rng)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = wobble * 1.6
        shadow.shadowOffset = NSSize(width: 0, height: -wobble * 0.6)
        shadow.set()
        plate.setFill()
        edge.fill()
        NSGraphicsContext.restoreGraphicsState()
        edge.lineWidth = wobble * 0.6
        NSColor.white.withAlphaComponent(0.55).setStroke()
        edge.stroke()
    }

    // MARK: Geometry

    private static func loops(of path: NSBezierPath) -> [[NSPoint]] {
        var loops: [[NSPoint]] = [], current: [NSPoint] = []
        var points = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<path.elementCount {
            switch path.element(at: i, associatedPoints: &points) {
            case .moveTo:
                if current.count > 2 { loops.append(current) }
                current = [points[0]]
            case .lineTo:
                current.append(points[0])
            case .closePath:
                if current.count > 2 { loops.append(current) }
                current = []
            default:
                break
            }
        }
        if current.count > 2 { loops.append(current) }
        return loops
    }

    private static func resample(_ loop: [NSPoint], step: CGFloat) -> [NSPoint] {
        var out: [NSPoint] = [], carry: CGFloat = 0
        let closed = loop + [loop[0]]
        for (a, b) in zip(closed, closed.dropFirst()) {
            let len = hypot(b.x - a.x, b.y - a.y)
            var d = carry
            while d < len {
                out.append(NSPoint(x: a.x + (b.x - a.x) * d / len, y: a.y + (b.y - a.y) * d / len))
                d += step
            }
            carry = d - len
        }
        return out
    }
}
