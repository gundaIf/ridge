import AppKit
import SwiftUI

/// `Ridge --snapshot <dir>` renders the README artwork from the real views, so screenshots
/// never drift from the app. Not used at runtime.
enum Snapshot {
    static func run(into dir: String) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let state = AppState.shared
        state.volume = 0.62
        state.brightness = 0.8
        state.muted = false
        state.trusted = true
        state.trackpads = 1
        state.lastAction = "Volume up"

        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func save(_ name: String, _ data: Data?) { try? data?.write(to: out.appendingPathComponent(name)) }

        save("icon.png", Icon.png(width: 1024, height: 1024) { Icon.drawAppIcon(size: 1024) })
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            let menu = capture(MenuMock(), dark: dark)
            let settings = trimTop(capture(WindowMock(title: "Ridge Settings") { SettingsView() }, dark: dark))
            save("menu-\(suffix).png", shadowed(menu))
            save("settings-\(suffix).png", shadowed(settings))
            if dark { save("hero.png", hero(menu: menu)) }
        }
        save("gestures.png", gestures())
    }

    // MARK: Capturing views

    /// Renders a SwiftUI view at 2x through a real window, so AppKit-backed controls draw properly.
    private static func capture(_ view: some View, dark: Bool) -> NSBitmapImageRep {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = appearance
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        appearance?.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
        return rep
    }

    /// The grouped Form reserves an empty band above the window; cut it off at the title bar.
    private static func trimTop(_ rep: NSBitmapImageRep) -> NSBitmapImageRep {
        let x = rep.pixelsWide / 2
        let first = rep.colorAt(x: x, y: 0)
        var top = 0
        while top < rep.pixelsHigh / 4, let c = rep.colorAt(x: x, y: top), let f = first,
              abs(c.redComponent - f.redComponent) < 0.02 && abs(c.alphaComponent - f.alphaComponent) < 0.02 { top += 1 }
        guard top > 4, let cg = rep.cgImage?.cropping(to: CGRect(x: 0, y: top, width: rep.pixelsWide, height: rep.pixelsHigh - top))
        else { return rep }
        let cropped = NSBitmapImageRep(cgImage: cg)
        cropped.size = NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2)
        return cropped
    }

    /// Draws a capture clipped to its rounded window shape (the backing store has square corners).
    private static func drawRounded(_ rep: NSBitmapImageRep, in rect: NSRect) {
        let k = rect.width / rep.size.width
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect.insetBy(dx: k, dy: k), xRadius: 11 * k, yRadius: 11 * k).addClip()
        rep.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Pads a capture and gives it a soft drop shadow, like a window on the desktop.
    private static func shadowed(_ rep: NSBitmapImageRep) -> Data? {
        let pad = 80
        let w = rep.pixelsWide + pad * 2, h = rep.pixelsHigh + pad * 2
        return Icon.png(width: w, height: h) {
            let shadow = NSShadow()
            shadow.shadowColor = .black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 48
            shadow.shadowOffset = NSSize(width: 0, height: -16)
            shadow.set()
            let rect = NSRect(x: pad, y: pad, width: rep.pixelsWide, height: rep.pixelsHigh)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: 18, yRadius: 18).fill()
            NSShadow().set()
            drawRounded(rep, in: rect)
        }
    }

    // MARK: Composed artwork

    private static func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at point: NSPoint) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
        (string as NSString).draw(at: point, withAttributes: attributes)
    }

    private static func background(_ rect: NSRect) {
        NSGradient(colors: [NSColor(srgbRed: 0.05, green: 0.05, blue: 0.08, alpha: 1),
                            NSColor(srgbRed: 0.13, green: 0.14, blue: 0.23, alpha: 1)])?.draw(in: rect, angle: 60)
        NSGradient(colors: [NSColor(srgbRed: 0.48, green: 0.42, blue: 1, alpha: 0.25), .clear])?
            .draw(in: NSBezierPath(rect: rect), relativeCenterPosition: NSPoint(x: 0.55, y: 0.3))
    }

    private static func hero(menu: NSBitmapImageRep) -> Data? {
        let w = 2400, h = 1200
        return Icon.png(width: w, height: h) {
            let rect = NSRect(x: 0, y: 0, width: w, height: h)
            background(rect)
            Icon.drawAppIcon(at: NSPoint(x: 150, y: 560), size: 420)
            let white = NSColor.white
            text("Ridge", size: 150, weight: .bold, color: white, at: NSPoint(x: 200, y: 370))
            text("Volume and brightness,", size: 64, weight: .medium, color: white.withAlphaComponent(0.85), at: NSPoint(x: 204, y: 270))
            text("right on the edges of your trackpad.", size: 64, weight: .medium, color: white.withAlphaComponent(0.85), at: NSPoint(x: 204, y: 190))
            let scale = (CGFloat(h) - 200) / CGFloat(menu.pixelsHigh)
            let mw = CGFloat(menu.pixelsWide) * scale, mh = CGFloat(menu.pixelsHigh) * scale
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = .black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = 80
            shadow.shadowOffset = NSSize(width: 0, height: -30)
            shadow.set()
            let frame = NSRect(x: CGFloat(w) - mw - 230, y: (CGFloat(h) - mh) / 2, width: mw, height: mh)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: frame.insetBy(dx: 6, dy: 6), xRadius: 30, yRadius: 30).fill()
            NSShadow().set()
            drawRounded(menu, in: frame)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// A map of the trackpad showing where each gesture lives.
    private static func gestures() -> Data? {
        let w = 2400, h = 1300
        return Icon.png(width: w, height: h) {
            let rect = NSRect(x: 0, y: 0, width: w, height: h)
            background(rect)
            let pad = NSRect(x: 600, y: 230, width: 1200, height: 840)
            let slab = NSBezierPath(roundedRect: pad, xRadius: 90, yRadius: 90)
            NSGraphicsContext.saveGraphicsState()
            let drop = NSShadow()
            drop.shadowColor = .black.withAlphaComponent(0.6)
            drop.shadowBlurRadius = 90
            drop.shadowOffset = NSSize(width: 0, height: -36)
            drop.set()
            NSColor(srgbRed: 0.15, green: 0.16, blue: 0.22, alpha: 1).setFill()
            slab.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGradient(colors: [NSColor(srgbRed: 0.14, green: 0.15, blue: 0.21, alpha: 1),
                                NSColor(srgbRed: 0.22, green: 0.24, blue: 0.34, alpha: 1)])?.draw(in: slab, angle: 90)
            slab.lineWidth = 4
            NSColor.white.withAlphaComponent(0.12).setStroke()
            slab.stroke()

            func glow(_ path: NSBezierPath, _ colors: [NSColor], angle: CGFloat) {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = colors[0].withAlphaComponent(0.85)
                shadow.shadowBlurRadius = 60
                shadow.set()
                colors[0].setFill()
                path.fill()
                NSGraphicsContext.restoreGraphicsState()
                NSGradient(colors: colors)?.draw(in: path, angle: angle)
            }
            let green = [NSColor(srgbRed: 0.18, green: 0.82, blue: 0.55, alpha: 1), NSColor(srgbRed: 0.45, green: 0.95, blue: 0.75, alpha: 1)]
            let pink = [NSColor(srgbRed: 1, green: 0.32, blue: 0.48, alpha: 1), NSColor(srgbRed: 1, green: 0.55, blue: 0.62, alpha: 1)]
            glow(NSBezierPath(roundedRect: NSRect(x: pad.minX + 50, y: pad.minY + 150, width: 44, height: 560), xRadius: 22, yRadius: 22), Icon.warm, angle: 90)
            glow(NSBezierPath(roundedRect: NSRect(x: pad.maxX - 94, y: pad.minY + 150, width: 44, height: 460), xRadius: 22, yRadius: 22), Icon.cool, angle: 90)
            glow(NSBezierPath(roundedRect: NSRect(x: pad.minX + 260, y: pad.minY + 46, width: 680, height: 40), xRadius: 20, yRadius: 20), green, angle: 0)
            for i in 0..<2 {
                let r: CGFloat = 34
                let c = NSPoint(x: pad.maxX - 120 + CGFloat(i) * 36, y: pad.maxY - 110 - CGFloat(i) * 20)
                glow(NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), pink, angle: 90)
            }

            let label = NSColor.white, sub = NSColor.white.withAlphaComponent(0.6)
            text("Brightness", size: 58, weight: .semibold, color: label, at: NSPoint(x: 150, y: 640))
            text("Slide up or down", size: 40, weight: .regular, color: sub, at: NSPoint(x: 150, y: 580))
            text("Volume", size: 58, weight: .semibold, color: label, at: NSPoint(x: 1880, y: 590))
            text("Slide up or down", size: 40, weight: .regular, color: sub, at: NSPoint(x: 1880, y: 530))
            text("Mute", size: 58, weight: .semibold, color: label, at: NSPoint(x: 1880, y: 1010))
            text("Double-tap the corner", size: 40, weight: .regular, color: sub, at: NSPoint(x: 1880, y: 950))
            text("Media", size: 58, weight: .semibold, color: label, at: NSPoint(x: 1080, y: 140))
            text("Swipe to skip tracks", size: 40, weight: .regular, color: sub, at: NSPoint(x: 1015, y: 80))
        }
    }
}

// MARK: Stand-ins for system chrome the snapshot can't capture

/// The status menu as it appears when opened: the same header and sliders the app hosts,
/// with native-looking rows around them.
struct MenuMock: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LevelsView()
            separator
            MenuRowMock(title: "Haptic Feedback", checked: true, submenu: true)
            MenuRowMock(title: "Quick Mute", checked: true)
            MenuRowMock(title: "Media Strip", checked: true)
            MenuRowMock(title: "Precise Sliding", checked: false)
            separator
            TuningView()
            separator
            MenuRowMock(title: "Settings…", shortcut: "⌘,")
            MenuRowMock(title: "Quit Ridge", shortcut: "⌘Q")
        }
        .padding(.vertical, 5)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(scheme == .dark ? Color(white: 0.16) : Color(white: 0.96)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.18 : 0.1)))
        .padding(1)
    }

    private var separator: some View {
        Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1).padding(.horizontal, 14).padding(.vertical, 5)
    }
}

struct MenuRowMock: View {
    let title: String
    var checked = false
    var submenu = false
    var shortcut: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).opacity(checked ? 1 : 0).frame(width: 12)
            Text(title).font(.system(size: 13))
            Spacer()
            if let shortcut { Text(shortcut).font(.system(size: 13)).foregroundStyle(.secondary) }
            if submenu { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 14)
        .frame(height: 22)
    }
}

struct WindowMock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                             Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { Circle().fill($0).frame(width: 12, height: 12) }
                    Spacer()
                }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            content
        }
        .background(scheme == .dark ? Color(white: 0.13) : Color(white: 0.93))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
        .padding(1)
    }
}
