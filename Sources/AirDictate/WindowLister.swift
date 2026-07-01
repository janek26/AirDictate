import AppKit
import CoreGraphics

struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let title: String
    let appName: String
    let bundleID: String?

    var displayName: String {
        let app = appName.isEmpty ? bundleID ?? "Unknown" : appName
        if title.isEmpty { return app }
        return "\(app) — \(title)"
    }

    /// Stable key for persistence — survives app restarts
    var stableKey: String {
        if let bundleID, !bundleID.isEmpty {
            return title.isEmpty ? bundleID : "\(bundleID)::\(title)"
        }
        return displayName
    }
}

final class WindowLister {
    /// Returns all visible, non-system windows with titles.
    func listWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return list.compactMap { dict in
            guard let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
                  let ownerName = dict[kCGWindowOwnerName as String] as? String,
                  let layer = dict[kCGWindowLayer as String] as? Int,
                  layer == 0  // normal windows only, skip docks/menubars/etc.
            else { return nil }

            let title = dict[kCGWindowName as String] as? String ?? ""
            let bundleID = dict[kCGWindowOwnerPID as String].flatMap { pid in
                NSRunningApplication(processIdentifier: pid as! pid_t)?.bundleIdentifier
            }

            // Skip tiny utility windows and our own app
            guard bundleID != Bundle.main.bundleIdentifier else { return nil }
            guard let bounds = dict[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat,
                  width > 200, height > 100
            else { return nil }

            return WindowInfo(id: windowID, title: title, appName: ownerName, bundleID: bundleID)
        }
        .sorted { $0.appName < $1.appName || ($0.appName == $1.appName && $0.title < $1.title) }
    }

    /// Focus a specific window, bringing its app to front and raising the window.
    func focus(window: WindowInfo) -> Bool {
        // Find the running app
        guard let bundleID = window.bundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return false }

        app.activate()
        // Give the app a moment to come to front
        Thread.sleep(forTimeInterval: 0.1)
        // Try to raise the specific window via Accessibility
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows)
        guard result == .success, let windowList = windows as? [AXUIElement] else { return true } // app is focused, good enough

        for w in windowList {
            var wTitle: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &wTitle)
            let titleStr = (wTitle as? String) ?? ""

            // Match by title
            if titleStr == window.title || window.title.isEmpty {
                AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                return true
            }
        }

        return true // app focused even if exact window not found
    }

    /// Try to find a matching window by stable key.
    func findWindow(matching stableKey: String) -> WindowInfo? {
        let windows = listWindows()
        return windows.first { $0.stableKey == stableKey }
    }
}
