import SwiftUI

@main
struct AirDictateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    appDelegate.openSettings()
                }
        }
    }
}
