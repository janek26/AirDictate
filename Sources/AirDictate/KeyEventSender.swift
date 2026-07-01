import CoreGraphics
import AppKit

final class KeyEventSender {
    private let permissionManager: PermissionManager
    private let log: DebugLog

    init(permissionManager: PermissionManager, log: DebugLog) {
        self.permissionManager = permissionManager
        self.log = log
    }

    @discardableResult
    func send(_ action: KeyStrokeAction) -> Bool {
        guard permissionManager.accessibilityTrusted else {
            log.error("Accessibility permission not granted — cannot send key event")
            return false
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let flags = action.modifiers.reduce(CGEventFlags()) { f, m in
            var f = f; f.insert(m.cgEventFlag); return f
        }

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(action.keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(action.keyCode), keyDown: false)
        else {
            log.error("Failed to create CGEvent for key code \(action.keyCode)")
            return false
        }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        log.debug("Key event sent: \(action.displayName)")
        return true
    }

    /// Pastes the given text into the focused application via clipboard + Cmd+V.
    /// Saves and restores the original clipboard contents.
    @discardableResult
    func paste(text: String) -> Bool {
        guard permissionManager.accessibilityTrusted else {
            log.error("Accessibility permission not granted — cannot paste")
            return false
        }

        focusTargetWindow()

        let pasteboard = NSPasteboard.general
        let oldChangeCount = pasteboard.changeCount
        var savedItems: [NSPasteboardItem] = []
        if let items = pasteboard.pasteboardItems {
            savedItems = items.map { item in
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        copy.setData(data, forType: type)
                    }
                }
                return copy
            }
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else {
            log.error("Failed to create CGEvent for Cmd+V")
            restoreClipboard(pasteboard, items: savedItems, oldChangeCount: oldChangeCount)
            return false
        }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        // Restore clipboard after paste has a moment to take effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.restoreClipboard(pasteboard, items: savedItems, oldChangeCount: oldChangeCount)
        }

        log.debug("Pasted text (\(text.count) chars) via Cmd+V")
        return true
    }

    private func restoreClipboard(_ pasteboard: NSPasteboard, items: [NSPasteboardItem], oldChangeCount: Int) {
        guard pasteboard.changeCount == oldChangeCount + 2 else { return }
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private func focusTargetWindow() {
        let key = STTSettings.targetWindow
        guard !key.isEmpty else { return }

        let lister = WindowLister()
        if let window = lister.findWindow(matching: key) {
            if lister.focus(window: window) {
                log.debug("Focused target window: \(window.displayName)")
                Thread.sleep(forTimeInterval: 0.15)
                return
            }
        }

        log.debug("Target window unavailable, resetting to default")
        STTSettings.targetWindow = ""
    }
}
