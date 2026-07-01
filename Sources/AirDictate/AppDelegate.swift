import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let log = DebugLog()
    let permissionManager = PermissionManager()
    let loginItemManager: LoginItemManager
    private(set) lazy var keySender = KeyEventSender(permissionManager: permissionManager, log: log)
    private(set) var sttController: STTController!
    private(set) var nowPlayingController: NowPlayingController!
    private var statusBarController: StatusBarController!
    private var cancellables = Set<AnyCancellable>()

    override init() {
        loginItemManager = LoginItemManager(log: log)
        super.init()
    }

    private var menuRefreshTimer: Timer?

    var isSetupComplete: Bool {
        Keychain.hasKey()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("AirDictate")
        log.info("AirDictate starting")
        permissionManager.refresh()
        sttController = STTController(log: log)
        Task { @MainActor in sttController.setKeySender(keySender) }

        nowPlayingController = NowPlayingController(log: log) { [weak self] in
            self?.sttController.toggle()
        }
        nowPlayingController.start()

        sttController.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.statusBarController?.updateMenuState()
            }
            .store(in: &cancellables)

        statusBarController = StatusBarController()
        statusBarController.setup(with: self)

        menuRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.statusBarController.updateMenuState() }
        }

        // Show setup if anything is missing
        if !isSetupComplete {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.statusBarController?.openSetup()
            }
        }
    }

    func openSettings() {
        statusBarController?.openSettings()
    }
}
