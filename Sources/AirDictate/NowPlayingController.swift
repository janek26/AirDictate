import Foundation
import MediaPlayer
import AppKit

enum NowPlayingStatus: Equatable {
    case disabled
    case activeFakePlayer
    case passiveRealPlayer(String)
    case error(String)

    var displayString: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .activeFakePlayer:
            return "Active — waiting for AirPods command"
        case .passiveRealPlayer(let bundleID):
            let name = friendlyAppName(for: bundleID)
            return "Passive — real media app owns Now Playing: \(name)"
        case .error(let msg):
            return "Error — \(msg)"
        }
    }

    static func == (lhs: NowPlayingStatus, rhs: NowPlayingStatus) -> Bool {
        switch (lhs, rhs) {
        case (.disabled, .disabled), (.activeFakePlayer, .activeFakePlayer): return true
        case (.passiveRealPlayer(let a), .passiveRealPlayer(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

private func friendlyAppName(for bundleID: String) -> String {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
       let bundle = Bundle(url: url),
       let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
        ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
        ?? bundle.localizedInfoDictionary?["CFBundleName"] as? String
        ?? bundle.infoDictionary?["CFBundleName"] as? String {
        return name
    }
    return bundleID
}

@MainActor
final class NowPlayingController: ObservableObject {
    @Published private(set) var status: NowPlayingStatus = .disabled
    @Published var isGloballyEnabled = true {
        didSet { if !isGloballyEnabled { clearFaker(); status = .disabled } else { refreshOwnership() } }
    }

    private let bridge: MediaRemoteBridge?
    private let log: DebugLog
    private var bundleID = Bundle.main.bundleIdentifier ?? "com.airdictate.app"
    private var commandTargets: [Any] = []
    private var onCommand: (() -> Void)?
    private var lastPublishTime: Date = .distantPast
    private var isFakePlaying = false

    init(log: DebugLog, onCommand: (() -> Void)? = nil) {
        self.log = log
        self.onCommand = onCommand

        do {
            self.bridge = try MediaRemoteBridge()
            log.info("MediaRemote bridge loaded")
        } catch {
            self.bridge = nil
            log.error("MediaRemote bridge unavailable: \(error.localizedDescription)")
        }
    }

    // MARK: - Lifecycle

    func start() {
        bridge?.registerAsNowPlayingApp()
        warmUpNowPlaying()
        registerCommandHandlers()
        registerMediaRemoteNotifications()
        refreshOwnership()
    }

    func stop() {
        disableRemoteCommands()
        clearFaker()
    }

    func forceReclaim() {
        guard isGloballyEnabled else { return }
        publishFakePlayer()
        log.info("Force reclaimed fake player")
    }

    func forceRelease() {
        clearFaker()
        status = .disabled
        log.info("Force released fake player")
    }

    // MARK: - Warm up

    private func warmUpNowPlaying() {
        MPNowPlayingInfoCenter.default().playbackState = .playing
        MPNowPlayingInfoCenter.default().playbackState = .paused
        log.debug("Now Playing warmed up")
    }

    // MARK: - Fake player

    private func fakeNowPlayingInfo() -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "AirDictate",
            MPMediaItemPropertyArtist: "Press AirPods to dictate",
            MPMediaItemPropertyPlaybackDuration: 300,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
            MPNowPlayingInfoPropertyPlaybackRate: isFakePlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if let artwork = makeArtwork() {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        return info
    }

    private func makeArtwork() -> MPMediaItemArtwork? {
        let size = NSSize(width: 40, height: 40)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.controlAccentColor.setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            path.fill()
            return true
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }

    private func publishFakePlayer() {
        isFakePlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = fakeNowPlayingInfo()
        MPNowPlayingInfoCenter.default().playbackState = .paused
        bridge?.enableOverride()
        enableRemoteCommands()
        status = .activeFakePlayer
        lastPublishTime = Date()
        log.info("Fake player published")
    }

    private func clearFaker() {
        bridge?.disableOverride()
        disableRemoteCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        log.debug("Fake player cleared")
    }

    // MARK: - Remote commands

    private func registerCommandHandlers() {
        let center = MPRemoteCommandCenter.shared()
        // All remote commands trigger the same action: toggle transcription
        commandTargets.append(center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.handleCommand() ?? .commandFailed })
        commandTargets.append(center.playCommand.addTarget { [weak self] _ in self?.handleCommand() ?? .commandFailed })
        commandTargets.append(center.pauseCommand.addTarget { [weak self] _ in self?.handleCommand() ?? .commandFailed })
        log.debug("Remote command handlers registered")
    }

    private func handleCommand() -> MPRemoteCommandHandlerStatus {
        guard isGloballyEnabled else { return .success }
        isFakePlaying.toggle()
        refreshNowPlayingState()
        onCommand?()
        return .success
    }

    private func refreshNowPlayingState() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = fakeNowPlayingInfo()
        MPNowPlayingInfoCenter.default().playbackState = isFakePlaying ? .playing : .paused
    }

    private func setRemoteCommandsEnabled(_ enabled: Bool) {
        let c = MPRemoteCommandCenter.shared()
        c.togglePlayPauseCommand.isEnabled = enabled
        c.playCommand.isEnabled = enabled
        c.pauseCommand.isEnabled = enabled
    }

    private func enableRemoteCommands() { setRemoteCommandsEnabled(true) }
    private func disableRemoteCommands() { setRemoteCommandsEnabled(false) }

    // MARK: - MediaRemote notifications

    private func registerMediaRemoteNotifications() {
        guard bridge != nil else {
            log.info("MediaRemote bridge unavailable — fallback: always-active fake player")
            return
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshOwnership() }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.bridge?.startNotifications(on: .main)
        }

        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshOwnership() }
        }
    }

    private func refreshOwnership() {
        guard let bridge else {
            if isGloballyEnabled, status != .activeFakePlayer {
                publishFakePlayer()
            }
            return
        }

        bridge.currentNowPlayingBundleID { [weak self] currentBundleID in
            Task { @MainActor in
                guard let self else { return }

                if !self.isGloballyEnabled {
                    self.clearFaker()
                    self.status = .disabled
                    return
                }

                if let currentBundleID, currentBundleID != self.bundleID {
                    if Date().timeIntervalSince(self.lastPublishTime) < 3 {
                        self.log.debug("Ignoring foreign owner \(currentBundleID) during cooldown")
                        return
                    }
                    if NSWorkspace.shared.urlForApplication(withBundleIdentifier: currentBundleID) == nil {
                        self.bundleID = currentBundleID
                        self.log.info("Resolved self bundleID to: \(currentBundleID)")
                        return
                    }
                    self.clearFaker()
                    self.status = .passiveRealPlayer(currentBundleID)
                } else if self.status != .activeFakePlayer {
                    self.publishFakePlayer()
                }
            }
        }
    }
}
