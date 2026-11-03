import AppKit
import ServiceManagement

enum ActiveArea: Int, CaseIterable, Identifiable {
    case anywhere, bottomThreeQuarters, bottomHalf, bottomQuarter
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .anywhere: "Anywhere along the edge"
        case .bottomThreeQuarters: "Bottom ¾"
        case .bottomHalf: "Bottom half"
        case .bottomQuarter: "Bottom quarter"
        }
    }
    /// Highest point (normalized, 0 = bottom) where a slide may start.
    var maxY: Float { [1, 0.75, 0.5, 0.25][rawValue] }
}

enum HapticStrength: Int, CaseIterable, Identifiable {
    case off, light, medium, strong
    var id: Int { rawValue }
    var label: String { ["Off", "Light", "Medium", "Strong"][rawValue] }
}

enum ModifierRequirement: Int, CaseIterable, Identifiable {
    case none, fn, option
    var id: Int { rawValue }
    var label: String { ["Nothing", "Fn (Globe)", "Option"][rawValue] }
}

enum Appearance: Int, CaseIterable, Identifiable {
    case system, light, dark
    var id: Int { rawValue }
    var label: String { ["Match System", "Light", "Dark"][rawValue] }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// The settings the gesture engine reads on the multitouch thread, as a plain value.
struct EngineConfig {
    var swapSides = false
    var edgeWidth: Float = 0.05
    var activeMaxY: Float = 1
    var sensitivity: Float = 1
    var preciseSliding = false
    var fineControl = true
    var quickMute = true
    var mediaStrip = true
    var tapToPlay = false
    var reverseSwipe = false
    var freezeCursor = true
    var haptics = HapticStrength.light
    var modifier = ModifierRequirement.none
}

final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    // Menu
    @Published var haptics: HapticStrength { didSet { save(haptics.rawValue, "haptics") } }
    @Published var quickMute: Bool { didSet { save(quickMute, "quickMute") } }
    @Published var mediaStrip: Bool { didSet { save(mediaStrip, "mediaStrip") } }
    @Published var preciseSliding: Bool { didSet { save(preciseSliding, "preciseSliding") } }
    @Published var sensitivity: Double { didSet { save(sensitivity, "sensitivity") } }
    @Published var edgeWidth: Double { didSet { save(edgeWidth, "edgeWidth") } }
    // Settings window
    @Published var swapSides: Bool { didSet { save(swapSides, "swapSides") } }
    @Published var activeArea: ActiveArea { didSet { save(activeArea.rawValue, "activeArea") } }
    @Published var modifier: ModifierRequirement { didSet { save(modifier.rawValue, "modifier") } }
    @Published var freezeCursor: Bool { didSet { save(freezeCursor, "freezeCursor") } }
    @Published var fineControl: Bool { didSet { save(fineControl, "fineControl") } }
    @Published var tapToPlay: Bool { didSet { save(tapToPlay, "tapToPlay") } }
    @Published var reverseSwipe: Bool { didSet { save(reverseSwipe, "reverseSwipe") } }
    @Published var appearance: Appearance {
        didSet { save(appearance.rawValue, "appearance"); NSApp.appearance = appearance.nsAppearance }
    }
    @Published var openAtLogin: Bool {
        didSet {
            guard openAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if openAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Ridge: open at login failed: \(error)")
            }
        }
    }
    var hasLaunchedBefore: Bool {
        get { d.bool(forKey: "hasLaunchedBefore") }
        set { d.set(newValue, forKey: "hasLaunchedBefore") }
    }

    private init() {
        d.register(defaults: [
            "haptics": HapticStrength.light.rawValue, "quickMute": true, "mediaStrip": true,
            "preciseSliding": false, "sensitivity": 1.0, "edgeWidth": 0.05, "swapSides": false,
            "activeArea": ActiveArea.anywhere.rawValue, "modifier": ModifierRequirement.none.rawValue,
            "freezeCursor": true, "fineControl": true, "tapToPlay": false, "reverseSwipe": false,
            "appearance": Appearance.system.rawValue,
        ])
        haptics = HapticStrength(rawValue: d.integer(forKey: "haptics")) ?? .light
        quickMute = d.bool(forKey: "quickMute")
        mediaStrip = d.bool(forKey: "mediaStrip")
        preciseSliding = d.bool(forKey: "preciseSliding")
        sensitivity = d.double(forKey: "sensitivity")
        edgeWidth = d.double(forKey: "edgeWidth")
        swapSides = d.bool(forKey: "swapSides")
        activeArea = ActiveArea(rawValue: d.integer(forKey: "activeArea")) ?? .anywhere
        modifier = ModifierRequirement(rawValue: d.integer(forKey: "modifier")) ?? .none
        freezeCursor = d.bool(forKey: "freezeCursor")
        fineControl = d.bool(forKey: "fineControl")
        tapToPlay = d.bool(forKey: "tapToPlay")
        reverseSwipe = d.bool(forKey: "reverseSwipe")
        appearance = Appearance(rawValue: d.integer(forKey: "appearance")) ?? .system
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func save(_ value: Any, _ key: String) {
        d.set(value, forKey: key)
        Engine.shared.config = engineConfig
    }

    var engineConfig: EngineConfig {
        EngineConfig(
            swapSides: swapSides, edgeWidth: Float(edgeWidth), activeMaxY: activeArea.maxY,
            sensitivity: Float(sensitivity), preciseSliding: preciseSliding, fineControl: fineControl,
            quickMute: quickMute, mediaStrip: mediaStrip, tapToPlay: tapToPlay, reverseSwipe: reverseSwipe,
            freezeCursor: freezeCursor, haptics: haptics, modifier: modifier)
    }
}
