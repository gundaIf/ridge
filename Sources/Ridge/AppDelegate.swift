import AppKit
import IOKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Prefs.shared
    private let state = AppState.shared
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var settingsWindow: NSWindow?
    private var levelTimer: Timer?
    private var restartWork: DispatchWorkItem?
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = prefs.appearance.nsAppearance
        SystemControls.allowBackgroundCursorHiding()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Icon.menuBar()
        menu.delegate = self
        statusItem.menu = menu

        Engine.shared.config = prefs.engineConfig
        Engine.shared.onAction = { [state] in state.record($0) }
        restartTrackpads()
        watchForTrackpads()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleRestart()
        }

        // Accessibility can be granted at any time; keep the UI in step.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [state] _ in
            let trusted = SystemControls.canPostEvents
            if trusted != state.trusted { state.trusted = trusted }
        }

        if !prefs.hasLaunchedBefore || !SystemControls.canPostEvents {
            prefs.hasLaunchedBefore = true
            if !SystemControls.canPostEvents { SystemControls.promptForAccessibility() }
            showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // MARK: Trackpads

    private func restartTrackpads() {
        state.trackpads = Engine.shared.start()
        NSLog("Ridge: listening to %d trackpad(s)", state.trackpads)
    }

    /// Restarts a moment after a change so the device has finished appearing (or the Mac waking).
    private func scheduleRestart() {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.restartTrackpads() }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func watchForTrackpads() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
            guard let refcon else { return }
            Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue().scheduleRestart()
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"), callback, refcon, &iterator)
            while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
            iterators.append(iterator)
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.appearance = prefs.appearance.nsAppearance

        menu.addItem(hosted(LevelsView(), height: 120))
        menu.addItem(.separator())

        let haptics = NSMenuItem(title: "Haptic Feedback", action: nil, keyEquivalent: "")
        haptics.state = prefs.haptics == .off ? .off : .on
        let strengths = NSMenu()
        for strength in HapticStrength.allCases {
            let item = NSMenuItem(title: strength.label, action: #selector(setHaptics(_:)), keyEquivalent: "")
            item.target = self
            item.tag = strength.rawValue
            item.state = prefs.haptics == strength ? .on : .off
            strengths.addItem(item)
        }
        haptics.submenu = strengths
        menu.addItem(haptics)
        menu.addItem(toggle("Quick Mute", prefs.quickMute, #selector(toggleQuickMute)))
        menu.addItem(toggle("Media Strip", prefs.mediaStrip, #selector(toggleMediaStrip)))
        menu.addItem(toggle("Precise Sliding", prefs.preciseSliding, #selector(togglePrecise)))
        menu.addItem(.separator())
        menu.addItem(hosted(TuningView(), height: 100))
        menu.addItem(.separator())

        if !state.trusted {
            let grant = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAccess), keyEquivalent: "")
            grant.target = self
            grant.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            menu.addItem(grant)
        }
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit Ridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func menuWillOpen(_ menu: NSMenu) {
        state.refreshLevels()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [state] _ in state.refreshLevels() }
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func hosted(_ view: some View, height: CGFloat) -> NSMenuItem {
        let item = NSMenuItem()
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 280, height: height)
        item.view = host
        return item
    }

    private func toggle(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    @objc private func setHaptics(_ sender: NSMenuItem) { prefs.haptics = HapticStrength(rawValue: sender.tag) ?? .light }
    @objc private func toggleQuickMute() { prefs.quickMute.toggle() }
    @objc private func toggleMediaStrip() { prefs.mediaStrip.toggle() }
    @objc private func togglePrecise() { prefs.preciseSliding.toggle() }
    @objc private func grantAccess() {
        SystemControls.promptForAccessibility()
        SystemControls.openAccessibilitySettings()
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Ridge Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
