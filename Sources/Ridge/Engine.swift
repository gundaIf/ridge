import AppKit
import CMultitouch

enum EngineAction {
    case volume(up: Bool, quarter: Bool)
    case brightness(up: Bool, quarter: Bool)
    case mute, playPause, next, previous
}

/// Turns raw trackpad frames into edge gestures. Everything below `config` runs on the
/// multitouch thread; side effects (keys, cursor, UI) are sent to the main thread.
final class Engine {
    static let shared = Engine()

    private let lock = NSLock()
    private var _config = EngineConfig()
    var config: EngineConfig {
        get { lock.lock(); defer { lock.unlock() }; return _config }
        set { lock.lock(); _config = newValue; lock.unlock() }
    }

    /// Called on the main thread after each action, for the setup guide.
    var onAction: ((EngineAction) -> Void)?

    @discardableResult
    func start() -> Int32 {
        RTStart { device, touches, count, timestamp in
            Engine.shared.frame(device: device, touches: touches, count: Int(count), timestamp: timestamp)
        }
    }

    func stop() { RTStop() }

    // MARK: Tuning (normalized trackpad units, 0...1 on each axis)

    /// Vertical travel per full step at sensitivity 1: sixteen steps over 60% of the height.
    private let baseStep: Float = 0.6 / 16
    private let slideActivation: Float = 0.025
    private let sidewaysCancel: Float = 0.06
    private let swipeDistance: Float = 0.18
    private let tapTravel: Float = 0.03
    private let tapDuration = 0.3
    private let doubleTapGap = 0.4
    /// How long a slide may lose its finger and still pick up where it left off.
    private let regrabWindow = 0.15

    // MARK: Multitouch-thread state

    private enum Zone { case left, right, bottom }
    private enum Phase { case idle, pending, sliding, done, ignored }
    private enum TapTarget { case corner, bottom }

    private var phase = Phase.idle
    private var cfg = EngineConfig()
    private var device: UInt = 0
    private var zone = Zone.left
    private var slideAllowed = false
    private var startedInCorner = false
    private var origin = (x: Float(0), y: Float(0), time: 0.0)
    private var last = (x: Float(0), y: Float(0))
    private var travel: Float = 0
    private var anchorY: Float = 0
    private var cursorAtStart: CGPoint?
    private var frozen = false
    private var lastTap: (target: TapTarget, time: Double)?
    private var lostSlide: (device: UInt, time: Double, x: Float, y: Float)?

    private func frame(device dev: UInt, touches: UnsafePointer<RTTouch>?, count: Int, timestamp: Double) {
        if phase != .idle && dev != device { return }
        var down: [RTTouch] = []
        if let touches {
            for i in 0..<count where touches[i].state == 4 || touches[i].state == 5 { down.append(touches[i]) }
        }

        if down.isEmpty {
            if phase != .idle { lift(timestamp) }
            return
        }
        if down.count > 1 {
            // Multi-finger gestures belong to macOS; stay out until every finger is up.
            if phase == .sliding { releaseCursor() }
            phase = .ignored
            device = dev
            lostSlide = nil
            return
        }

        let touch = down[0]
        switch phase {
        case .idle: begin(dev, touch, timestamp)
        case .pending: pending(touch)
        case .sliding: slide(touch)
        case .done, .ignored: break
        }
    }

    private func begin(_ dev: UInt, _ t: RTTouch, _ time: Double) {
        device = dev
        // The trackpad briefly lost the finger mid-slide: carry on as the same slide.
        if let lost = lostSlide, lost.device == dev, time - lost.time < regrabWindow, abs(t.x - lost.x) < 0.08 {
            lostSlide = nil
            anchorY += t.y - lost.y
            last = (t.x, t.y)
            phase = .sliding
            holdCursor()
            return
        }
        lostSlide = nil

        cfg = config
        origin = (t.x, t.y, time)
        last = (t.x, t.y)
        travel = 0
        cursorAtStart = CGEvent(source: nil)?.location
        let edge = cfg.edgeWidth
        startedInCorner = cfg.quickMute && t.x > 1 - max(edge, 0.1) && t.y > 0.85
        let onSide = t.x < edge || t.x > 1 - edge

        if onSide || startedInCorner {
            zone = t.x < 0.5 ? .left : .right
            slideAllowed = onSide && t.y <= cfg.activeMaxY + 0.001 && modifierHeld()
            phase = slideAllowed || startedInCorner ? .pending : .ignored
        } else if cfg.mediaStrip && t.y < edge * 1.6 {
            zone = .bottom
            phase = .pending
        } else {
            phase = .ignored
        }
    }

    private func pending(_ t: RTTouch) {
        let dx = t.x - origin.x, dy = t.y - origin.y
        travel = max(travel, (dx * dx + dy * dy).squareRoot())
        last = (t.x, t.y)
        switch zone {
        case .left, .right:
            if slideAllowed && abs(dy) > slideActivation && abs(dy) > abs(dx) * 1.5 {
                phase = .sliding
                anchorY = origin.y
                holdCursor()
                slide(t)
            } else if abs(dx) > sidewaysCancel || (!slideAllowed && travel > tapTravel) {
                phase = .ignored  // an ordinary pointer move that happened to start at the edge
            }
        case .bottom:
            if abs(dx) > swipeDistance && abs(dx) > abs(dy) * 2 {
                phase = .done
                perform((dx > 0) != cfg.reverseSwipe ? .next : .previous, haptic: .medium)
            } else if abs(dy) > 0.06 {
                phase = .ignored
            }
        }
    }

    private func slide(_ t: RTTouch) {
        last = (t.x, t.y)
        let quarter = cfg.preciseSliding || (cfg.fineControl && shiftOptionHeld())
        let step = baseStep / max(cfg.sensitivity, 0.1) * (quarter ? 0.25 : 1)
        let volume = (zone == .right) != cfg.swapSides
        var steps = 0
        while abs(t.y - anchorY) >= step && steps < 8 {
            let up = t.y > anchorY
            anchorY += up ? step : -step
            steps += 1
            perform(volume ? .volume(up: up, quarter: quarter) : .brightness(up: up, quarter: quarter), haptic: cfg.haptics)
        }
    }

    private func lift(_ time: Double) {
        switch phase {
        case .sliding:
            lostSlide = (device, time, last.x, last.y)
            releaseCursor()
        case .pending where time - origin.time < tapDuration && travel < tapTravel:
            tapped(time)
        default:
            break
        }
        phase = .idle
    }

    private func tapped(_ time: Double) {
        let target: TapTarget? = startedInCorner ? .corner : (zone == .bottom && cfg.tapToPlay ? .bottom : nil)
        guard let target else { lastTap = nil; return }
        if let previous = lastTap, previous.target == target, time - previous.time < doubleTapGap {
            lastTap = nil
            perform(target == .corner ? .mute : .playPause, haptic: .strong)
        } else {
            lastTap = (target, time)
        }
    }

    // MARK: Effects

    private func perform(_ action: EngineAction, haptic: HapticStrength) {
        if cfg.haptics != .off {
            let strength = haptic == .strong || cfg.haptics == .strong ? HapticStrength.strong : haptic
            buzz(strength)
            if case .mute = action { buzz(.strong) }
        }
        DispatchQueue.main.async {
            switch action {
            case let .volume(up, quarter): SystemControls.press(up ? .soundUp : .soundDown, quarterStep: quarter)
            case let .brightness(up, quarter): SystemControls.press(up ? .brightnessUp : .brightnessDown, quarterStep: quarter)
            case .mute: SystemControls.press(.mute)
            case .playPause: SystemControls.press(.play)
            case .next: SystemControls.press(.next)
            case .previous: SystemControls.press(.previous)
            }
            Engine.shared.onAction?(action)
        }
    }

    private func buzz(_ strength: HapticStrength) {
        guard strength != .off else { return }
        if RTHaptic(device, Int32(strength.rawValue)) { return }
        DispatchQueue.main.async {
            let pattern: NSHapticFeedbackManager.FeedbackPattern = strength == .light ? .alignment : (strength == .medium ? .generic : .levelChange)
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        }
    }

    private func holdCursor() {
        guard cfg.freezeCursor else { return }
        frozen = true
        let point = cursorAtStart
        DispatchQueue.main.async { SystemControls.freezeCursor(true, at: point) }
    }

    private func releaseCursor() {
        guard frozen else { return }
        frozen = false
        DispatchQueue.main.async { SystemControls.freezeCursor(false) }
    }

    private func modifierHeld() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        switch cfg.modifier {
        case .none: return true
        case .fn: return flags.contains(.maskSecondaryFn)
        case .option: return flags.contains(.maskAlternate)
        }
    }

    private func shiftOptionHeld() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.contains(.maskShift) && flags.contains(.maskAlternate)
    }
}
