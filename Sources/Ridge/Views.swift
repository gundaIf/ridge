import SwiftUI

/// App-wide live state that isn't a preference.
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var trusted = SystemControls.canPostEvents
    @Published var trackpads: Int32 = 0
    @Published var lastAction: String?
    @Published var volume: Float?
    @Published var brightness: Float?
    @Published var muted = false

    func refreshLevels() {
        volume = SystemControls.volume()
        brightness = SystemControls.brightness()
        muted = SystemControls.isMuted()
    }

    func record(_ action: EngineAction) {
        lastAction = switch action {
        case let .volume(up, _): up ? "Volume up" : "Volume down"
        case let .brightness(up, _): up ? "Brightness up" : "Brightness down"
        case .mute: "Mute toggled"
        case .playPause: "Play / Pause"
        case .next: "Next track"
        case .previous: "Previous track"
        }
    }
}

// MARK: Menu header: a little trackpad showing each level on the edge that controls it

struct LevelsView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        let volume = EdgeMeter(symbol: state.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                               value: state.muted ? 0 : state.volume, label: state.muted ? "Muted" : nil, colors: Icon.cool)
        let brightness = EdgeMeter(symbol: "sun.max.fill", value: state.brightness, label: nil, colors: Icon.warm)
        HStack(spacing: 0) {
            if prefs.swapSides { volume } else { brightness }
            Spacer()
            VStack(spacing: 4) {
                Text("Ridge").font(.system(size: 13, weight: .semibold))
                Text(state.trackpads > 0 ? "Slide along an edge" : "No trackpad found")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if prefs.swapSides { brightness } else { volume }
        }
        .padding(10)
        .frame(height: 104)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: 280)
    }
}

struct EdgeMeter: View {
    let symbol: String
    let value: Float?
    let label: String?
    let colors: [NSColor]

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule().fill(LinearGradient(colors: colors.map(Color.init), startPoint: .bottom, endPoint: .top))
                        .frame(height: max(6, geo.size.height * CGFloat(value ?? 0)))
                        .opacity(value == nil ? 0 : 1)
                }
            }
            .frame(width: 6)
            .animation(.easeOut(duration: 0.15), value: value)
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(label ?? value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                .font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(width: 44)
    }
}

// MARK: Menu sliders

struct TuningView: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Sensitivity", value: $prefs.sensitivity, in: 0.5...2,
                readout: String(format: "%.1f×", prefs.sensitivity))
            row("Edge Width", value: $prefs.edgeWidth, in: 0.03...0.12,
                readout: "\(Int((prefs.edgeWidth * 100).rounded()))%")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: 280)
    }

    private func row(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, readout: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                Text(readout).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).controlSize(.small)
        }
    }
}

// MARK: Settings window

struct SettingsView: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var state = AppState.shared

    var body: some View {
        Form {
            Section("Getting started") {
                HStack {
                    Label(state.trusted ? "Accessibility access granted" : "Ridge needs Accessibility access to change volume and brightness",
                          systemImage: state.trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(state.trusted ? .green : .orange)
                    Spacer()
                    if !state.trusted {
                        Button("Open Settings…") { SystemControls.openAccessibilitySettings() }
                    }
                }
                HStack {
                    Text(prefs.swapSides
                         ? "Slide one finger up the left edge for volume, the right edge for brightness."
                         : "Slide one finger up the right edge for volume, the left edge for brightness.")
                    Spacer()
                    Text(state.lastAction ?? "Waiting for a slide…")
                        .foregroundStyle(state.lastAction == nil ? .secondary : .primary)
                        .font(.body.monospacedDigit())
                }
                if state.trackpads == 0 {
                    Label("No trackpad found", systemImage: "rectangle.slash").foregroundStyle(.secondary)
                }
            }

            Section("Edges") {
                Toggle("Swap Sides", isOn: $prefs.swapSides)
                Picker("Active Area", selection: $prefs.activeArea) {
                    ForEach(ActiveArea.allCases) { Text($0.label).tag($0) }
                }
                Picker("Require Key While Sliding", selection: $prefs.modifier) {
                    ForEach(ModifierRequirement.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("While Sliding") {
                Toggle("Freeze Cursor", isOn: $prefs.freezeCursor)
                Toggle("Precise Sliding (quarter steps)", isOn: $prefs.preciseSliding)
                Toggle("Fine Control (hold Shift-Option for quarter steps)", isOn: $prefs.fineControl)
                Picker("Haptic Feedback", selection: $prefs.haptics) {
                    ForEach(HapticStrength.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Corners & Bottom Edge") {
                Toggle("Quick Mute (double-tap top-right corner)", isOn: $prefs.quickMute)
                Toggle("Media Strip (swipe the bottom edge to skip tracks)", isOn: $prefs.mediaStrip)
                Toggle("Double-Tap Bottom Edge to Play or Pause", isOn: $prefs.tapToPlay)
                    .disabled(!prefs.mediaStrip)
                Toggle("Reverse Swipe", isOn: $prefs.reverseSwipe)
                    .disabled(!prefs.mediaStrip)
            }

            Section("General") {
                Picker("Appearance", selection: $prefs.appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Open at Login", isOn: $prefs.openAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
