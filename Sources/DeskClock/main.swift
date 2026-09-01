import AppKit
import ServiceManagement
import SwiftUI

// MARK: - App identity
//
// The display name lives in exactly one place so the app is trivial to rename.
// (The *bundle* / executable name is set in Package.swift and build.sh.)
enum AppInfo {
    static let name = "DeskClock"
}

// MARK: - App delegate
//
// Owns the floating clock window, the menu-bar item, and the settings model.
// The settings popover routes every change back through here (see the
// ClockController conformance below); this delegate applies the window-side
// effects (size, opacity, Space behavior, click-through) and the login item.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private let settings = ClockSettings()
    private var window: ClockWindow!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = ClockWindow(size: settings.size.points)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ClockView(settings: settings))

        applyOpacity()
        applyFloatsOverFullscreen()
        applyClickThrough()
        restorePosition()

        window.orderFrontRegardless()

        statusItem = StatusItemController(controller: self, settings: settings)

        startVisibilityTracking()
    }

    func applicationWillTerminate(_ notification: Notification) {
        captureOrigin()
        settings.save()
    }

    // MARK: Window delegate — persist position as the user drags.
    func windowDidMove(_ notification: Notification) {
        captureOrigin()
        settings.save()
    }

    // MARK: Applying settings to the live window
    private func applyOpacity() {
        window.alphaValue = settings.opacity
    }

    private func applyFloatsOverFullscreen() {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary]
        if settings.floatOverFullscreen { behavior.insert(.fullScreenAuxiliary) }
        window.collectionBehavior = behavior
    }

    private func applyClickThrough() {
        // When click-through is on, the window ignores the mouse entirely, which
        // also disables dragging by design — the menu-bar item is the way back.
        window.ignoresMouseEvents = settings.clickThrough
        window.isMovableByWindowBackground = !settings.clickThrough
    }

    private func resizeWindow(to size: ClockSize, animated: Bool) {
        let old = window.frame
        let center = CGPoint(x: old.midX, y: old.midY)
        let side = size.points
        let origin = CGPoint(x: center.x - side / 2, y: center.y - side / 2)
        window.setFrame(CGRect(origin: origin, size: CGSize(width: side, height: side)),
                        display: true, animate: animated)
    }

    // MARK: Position helpers
    private func captureOrigin() {
        settings.originX = Double(window.frame.origin.x)
        settings.originY = Double(window.frame.origin.y)
    }

    private func restorePosition() {
        if let x = settings.originX, let y = settings.originY {
            window.setFrameOrigin(NSPoint(x: x, y: y))
            ensureOnScreen()
        } else {
            positionTopRight()
        }
    }

    private func positionTopRight() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 24
        let side = settings.size.points
        window.setFrameOrigin(NSPoint(x: visible.maxX - side - margin,
                                      y: visible.maxY - side - margin))
    }

    // If the saved frame lands off every screen (e.g. a monitor was unplugged),
    // snap it back to a sensible on-screen spot.
    private func ensureOnScreen() {
        let frame = window.frame
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if !onScreen { positionTopRight() }
    }

    // MARK: - Render gating
    //
    // A `.periodic` TimelineView keeps firing while its view is off-screen
    // (unlike `.animation`, it doesn't pause on occlusion). For a borderless
    // floating overlay that means the face would redraw — up to ~30 fps with the
    // sweeping hand — behind the screen saver or a sleeping display, around the
    // clock. We track the three ways the clock goes unseen and collapse them into
    // settings.renderActive, which the face reads to fall back to a static draw.
    private var windowVisible = true
    private var screensAwake = true
    private var screenSaverIdle = true

    private func startVisibilityTracking() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionDidChange),
            name: NSWindow.didChangeOcclusionStateNotification, object: window)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screensDidSleep),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenSaverDidStart),
                                name: .init("com.apple.screensaver.didstart"), object: nil)
        distributed.addObserver(self, selector: #selector(screenSaverDidStop),
                                name: .init("com.apple.screensaver.didstop"), object: nil)
    }

    private func refreshRenderActive() {
        settings.renderActive = windowVisible && screensAwake && screenSaverIdle
    }

    @objc private func occlusionDidChange() {
        windowVisible = window.occlusionState.contains(.visible)
        refreshRenderActive()
    }

    @objc private func screensDidSleep() { screensAwake = false; refreshRenderActive() }

    // Waking implies the screen saver is gone too — clear it as a safety net in
    // case a `didstop` distributed notification is ever missed.
    @objc private func screensDidWake() {
        screensAwake = true
        screenSaverIdle = true
        refreshRenderActive()
    }

    @objc private func screenSaverDidStart() { screenSaverIdle = false; refreshRenderActive() }
    @objc private func screenSaverDidStop()  { screenSaverIdle = true;  refreshRenderActive() }
}

// MARK: - Settings popover hooks
extension AppDelegate: ClockController {

    // Size — preview just resizes the window; commit also persists.
    func previewSize(_ size: ClockSize) {
        resizeWindow(to: size, animated: false)
    }

    func commitSize(_ size: ClockSize) {
        settings.size = size
        resizeWindow(to: size, animated: false)
        ensureOnScreen()
        captureOrigin()
        settings.save()
    }

    // Theme — preview is a transient overlay; commit persists.
    func previewTheme(_ theme: ClockTheme) {
        settings.previewTheme = theme
    }

    func commitTheme(_ theme: ClockTheme) {
        settings.theme = theme
        settings.previewTheme = nil
        settings.save()
    }

    func endPreviews() {
        if window.frame.width != settings.size.points {
            resizeWindow(to: settings.size, animated: false)
            captureOrigin()
            settings.save()
        }
        settings.previewTheme = nil
    }

    func setOpacity(_ value: Double) {
        settings.opacity = min(max(value, ClockSettings.minOpacity), ClockSettings.maxOpacity)
        applyOpacity()
        settings.save()
    }

    func setSweepSeconds(_ on: Bool) {
        settings.sweepSeconds = on
        settings.save()
    }

    func setShowNumerals(_ on: Bool) {
        settings.showNumerals = on
        settings.save()
    }

    func setFloatOverFullscreen(_ on: Bool) {
        settings.floatOverFullscreen = on
        applyFloatsOverFullscreen()
        settings.save()
    }

    func setClickThrough(_ on: Bool) {
        settings.clickThrough = on
        applyClickThrough()
        settings.save()
    }

    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("\(AppInfo.name): launch-at-login change failed: \(error.localizedDescription)")
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Bootstrap
//
// Accessory activation policy: no Dock icon and no app menu bar — the clock is
// driven entirely from its menu-bar status item.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
