import AppKit
import AudioToolbox
import CoreAudio

/// Talks to the system: media keys (which also show the native volume/brightness HUD),
/// current levels for the menu, and the cursor.
enum SystemControls {
    enum Key: Int32 {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
        case play = 16, next = 17, previous = 18
    }

    /// Posts a media key press, the same event the keyboard's function row sends. With
    /// `quarterStep`, Shift-Option is held, which macOS turns into a quarter-size step.
    static func press(_ key: Key, quarterStep: Bool = false) {
        let modifiers: UInt = quarterStep ? (NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.option.rawValue) : 0
        for down in [true, false] {
            let flag = down ? 0xa : 0xb
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flag << 8) | modifiers),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: Int((key.rawValue << 16) | Int32(flag << 8)), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    static var canPostEvents: Bool { AXIsProcessTrusted() }

    static func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: Levels

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : nil
    }

    /// 0...1, or nil when the output device has no volume control.
    static func volume() -> Float? {
        guard let device = defaultOutputDevice() else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr ? volume : nil
    }

    static func isMuted() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr && muted != 0
    }

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private static let getBrightness: GetBrightness? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    /// Built-in display brightness 0...1, or nil when there is no built-in display.
    static func brightness() -> Float? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count = UInt32(0)
        CGGetOnlineDisplayList(16, &displays, &count)
        guard let builtIn = displays.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }),
              let getBrightness else { return nil }
        var value = Float(0)
        return getBrightness(builtIn, &value) == 0 ? value : nil
    }

    // MARK: Cursor

    private static var cursorHidden = false

    /// Lets this background app hide the cursor (normally only the active app may).
    static func allowBackgroundCursorHiding() {
        typealias DefaultConnection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        guard let main = dlopen(nil, RTLD_LAZY),
              let connSym = dlsym(main, "_CGSDefaultConnection"),
              let setSym = dlsym(main, "CGSSetConnectionProperty") else { return }
        let connection = unsafeBitCast(connSym, to: DefaultConnection.self)()
        _ = unsafeBitCast(setSym, to: SetProperty.self)(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }

    /// Holds the pointer in place (at `point`, if given) and hides it, or releases it.
    static func freezeCursor(_ frozen: Bool, at point: CGPoint? = nil) {
        if frozen {
            if let point { CGWarpMouseCursorPosition(point) }
            CGAssociateMouseAndMouseCursorPosition(0)
            if !cursorHidden { CGDisplayHideCursor(CGMainDisplayID()); cursorHidden = true }
        } else {
            CGAssociateMouseAndMouseCursorPosition(1)
            if cursorHidden { CGDisplayShowCursor(CGMainDisplayID()); cursorHidden = false }
        }
    }
}
