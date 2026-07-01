import AppKit
import SwiftUI

final class StatusBarController: ObservableObject {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?

    private weak var appDelegate: AppDelegate?

    func setup(with appDelegate: AppDelegate) {
        self.appDelegate = appDelegate

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "airpods.gen3",
                accessibilityDescription: "AirDictate"
            )
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let headerItem = NSMenuItem(title: "AirDictate", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        headerItem.tag = 100
        menu.addItem(headerItem)

        let toggleItem = NSMenuItem(title: "Pause", action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.tag = 101
        menu.addItem(toggleItem)

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    @MainActor func updateMenuState() {
        guard let menu = statusItem?.menu, let ad = appDelegate else { return }

        let stt = ad.sttController.state

        if stt.isRecording {
            menu.item(withTag: 100)?.title = "Recording\u{2026}"
        } else if stt.isTranscribing {
            menu.item(withTag: 100)?.title = "Transcribing\u{2026}"
        } else {
            menu.item(withTag: 100)?.title = "AirDictate"
        }

        if let button = statusItem?.button {
            let symbolName: String
            let tint: NSColor?
            if stt.isRecording {
                symbolName = "mic.fill"
                tint = .systemRed
            } else if stt.isTranscribing {
                symbolName = "waveform"
                tint = .systemOrange
            } else {
                symbolName = "airpods.gen3"
                tint = nil
            }
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            if let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            {
                button.image = tintedImage(base, with: tint)
            }
        }

        let enabled = ad.nowPlayingController?.isGloballyEnabled ?? true
        menu.item(withTag: 101)?.title = enabled ? "Pause" : "Resume"
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let contentView = SettingsView()
                .environmentObject(appDelegate!.log)
                .environmentObject(appDelegate!.permissionManager)
                .environmentObject(appDelegate!.nowPlayingController)
                .environmentObject(appDelegate!.loginItemManager)
                .environmentObject(appDelegate!.sttController)

            let hosting = NSHostingController(rootView: contentView)
            let window = NSWindow(contentViewController: hosting)
            window.title = "AirDictate"
            window.setContentSize(NSSize(width: 660, height: 480))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleEnabled() {
        Task { @MainActor in
            guard let nc = appDelegate?.nowPlayingController else { return }
            nc.isGloballyEnabled.toggle()
            updateMenuState()
        }
    }

    func openSetup() {
        guard setupWindow == nil else {
            setupWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SetupView {
            self.setupWindow?.close()
            self.setupWindow = nil
        }
        .environmentObject(appDelegate!.sttController)
        .environmentObject(appDelegate!.permissionManager)

        let hosting = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to AirDictate"
        window.setContentSize(NSSize(width: 520, height: 620))
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private func tintedImage(_ image: NSImage, with tint: NSColor?) -> NSImage {
    guard let tint else { return image }
    let sized = image.size
    let result = NSImage(size: sized)
    result.isTemplate = false
    result.lockFocus()
    tint.setFill()
    NSRect(origin: .zero, size: sized).fill()
    image.draw(in: NSRect(origin: .zero, size: sized), from: .zero, operation: .destinationIn, fraction: 1)
    result.unlockFocus()
    return result
}
