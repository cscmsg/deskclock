import AppKit
import SwiftUI

// Actions the settings popover drives. AppDelegate implements it; the SwiftUI
// panel reads live state from ClockSettings and routes every change back through
// here so window-side effects and persistence happen in one place.
protocol ClockController: AnyObject {
    // Size — hover-preview resizes the live window; commit persists it.
    func previewSize(_ size: ClockSize)
    func commitSize(_ size: ClockSize)

    // Theme — hover-preview recolors the live face; commit persists it.
    func previewTheme(_ theme: ClockTheme)
    func commitTheme(_ theme: ClockTheme)

    // Drop any active hover-preview, reverting to the committed size/theme.
    func endPreviews()

    func setOpacity(_ value: Double)
    func setSweepSeconds(_ on: Bool)
    func setShowNumerals(_ on: Bool)
    func setFloatOverFullscreen(_ on: Bool)
    func setClickThrough(_ on: Bool)

    var isLaunchAtLoginEnabled: Bool { get }
    func setLaunchAtLogin(_ on: Bool)

    func quit()
}

// Owns the menu-bar status item and the settings popover. Clicking the icon
// toggles the popover, which is transient — it dismisses on an outside click or
// Esc, and reverts any dangling hover-preview as it closes.
final class StatusItemController: NSObject, NSPopoverDelegate {

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private weak var controller: (any ClockController)?

    init(controller: any ClockController, settings: ClockSettings) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()

        popover.behavior = .transient
        popover.contentViewController =
            NSHostingController(rootView: SettingsPanel(settings: settings, controller: controller))
        popover.delegate = self
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "clock", accessibilityDescription: AppInfo.name)
        image?.isTemplate = true
        button.image = image
        button.toolTip = AppInfo.name
        button.action = #selector(togglePopover)
        button.target = self
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        controller?.endPreviews()
    }
}
