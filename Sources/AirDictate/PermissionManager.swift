import AppKit
import ApplicationServices
import AVFoundation

final class PermissionManager: ObservableObject {
    @Published var accessibilityTrusted = AXIsProcessTrusted()
    @Published var microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    func refresh() {
        // Force a fresh check — AXIsProcessTrusted() can cache stale results
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        accessibilityTrusted = AXIsProcessTrusted()
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }
}
