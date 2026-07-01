import Foundation

final class MediaRemoteBridge {
    typealias RegisterForNowPlayingNotifications = @convention(c) (DispatchQueue) -> Void
    typealias GetNowPlayingClient = @convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void
    typealias GetBundleIdentifier = @convention(c) (AnyObject?) -> String?
    typealias SetCanBeNowPlayingApp = @convention(c) (Bool) -> Void
    typealias SetOverrideEnabled = @convention(c) (Bool) -> Void
    typealias SetNowPlayingInfo = @convention(c) (CFDictionary) -> Void

    private let registerForNowPlayingNotifications: RegisterForNowPlayingNotifications
    private let getNowPlayingClient: GetNowPlayingClient
    private let getBundleIdentifier: GetBundleIdentifier
    private let setCanBeNowPlayingApp: SetCanBeNowPlayingApp?
    private let setOverrideEnabled: SetOverrideEnabled?
    private let setNowPlayingInfo: SetNowPlayingInfo?

    init() throws {
        guard let bundle = CFBundleCreate(
            kCFAllocatorDefault,
            NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        ) else {
            throw MediaRemoteError.frameworkUnavailable
        }

        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let ptr = CFBundleGetFunctionPointerForName(bundle, name as CFString) else {
                return nil
            }
            return unsafeBitCast(ptr, to: type)
        }

        func require<T>(_ name: String, as type: T.Type) throws -> T {
            guard let fn = load(name, as: type) else {
                throw MediaRemoteError.symbolUnavailable(name)
            }
            return fn
        }

        self.getNowPlayingClient = try require(
            "MRMediaRemoteGetNowPlayingClient",
            as: GetNowPlayingClient.self
        )
        self.getBundleIdentifier = try require(
            "MRNowPlayingClientGetBundleIdentifier",
            as: GetBundleIdentifier.self
        )
        self.registerForNowPlayingNotifications = try require(
            "MRMediaRemoteRegisterForNowPlayingNotifications",
            as: RegisterForNowPlayingNotifications.self
        )

        // Optional: these may not exist on all macOS versions
        self.setCanBeNowPlayingApp = load("MRMediaRemoteSetCanBeNowPlayingApplication", as: SetCanBeNowPlayingApp.self)
        self.setOverrideEnabled = load("MRMediaRemoteSetNowPlayingApplicationOverrideEnabled", as: SetOverrideEnabled.self)
        self.setNowPlayingInfo = load("MRMediaRemoteSetNowPlayingInfo", as: SetNowPlayingInfo.self)
    }

    func startNotifications(on queue: DispatchQueue = .main) {
        registerForNowPlayingNotifications(queue)
    }

    func currentNowPlayingBundleID(completion: @escaping (String?) -> Void) {
        getNowPlayingClient(.main) { [getBundleIdentifier] client in
            completion(getBundleIdentifier(client))
        }
    }

    /// Registers our app as eligible to be a Now Playing application.
    func registerAsNowPlayingApp() {
        setCanBeNowPlayingApp?(true)
    }

    /// Forces remote commands to route to our app regardless of which app
    /// is the "current" Now Playing application.
    func enableOverride() {
        setOverrideEnabled?(true)
    }

    /// Sets Now Playing info via the private API (in addition to the public
    /// MPNowPlayingInfoCenter). This can be more aggressive about claiming
    /// the Now Playing slot.
    func setNowPlaying(info: [String: Any]) {
        setNowPlayingInfo?(info as CFDictionary)
    }

    func disableOverride() {
        setOverrideEnabled?(false)
    }
}

enum MediaRemoteError: Error, LocalizedError {
    case frameworkUnavailable
    case symbolUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .frameworkUnavailable:
            return "MediaRemote.framework is unavailable on this system."
        case .symbolUnavailable(let symbol):
            return "MediaRemote symbol unavailable: \(symbol)"
        }
    }
}
