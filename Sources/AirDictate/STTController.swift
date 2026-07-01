import Foundation
import AVFoundation
import AppKit

// MARK: - STT State

enum STTState: Equatable {
    case idle
    case recording(startedAt: Date)
    case transcribing
    case error(String)

    var displayString: String {
        switch self {
        case .idle: return "Idle"
        case .recording: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isTranscribing: Bool {
        if case .transcribing = self { return true }
        return false
    }
}

// MARK: - STT Models

struct STTModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let provider: String
    let pricing: String

    init(id: String, displayName: String, pricing: String) {
        self.id = id
        self.displayName = displayName
        self.provider = String(id.split(separator: "/").first ?? "")
        self.pricing = pricing
    }
}

let availableSTTModels: [STTModel] = [
    STTModel(id: "openai/whisper-large-v3",       displayName: "OpenAI Whisper Large V3",              pricing: "$0.0015/s"),
    STTModel(id: "openai/whisper-large-v3-turbo", displayName: "OpenAI Whisper Large V3 Turbo",       pricing: "$0.04/s"),
    STTModel(id: "openai/whisper-1",              displayName: "OpenAI Whisper 1",                     pricing: "$0.006/s"),
    STTModel(id: "openai/gpt-4o-transcribe",      displayName: "OpenAI GPT-4o Transcribe",             pricing: "per token"),
    STTModel(id: "openai/gpt-4o-mini-transcribe", displayName: "OpenAI GPT-4o Mini Transcribe",        pricing: "per token"),
    STTModel(id: "google/chirp-3",                displayName: "Google Chirp 3",                       pricing: "$0.016/s"),
    STTModel(id: "qwen/qwen3-asr-flash-2026-02-10", displayName: "Qwen Qwen3 ASR Flash",              pricing: "$0.000035/s"),
    STTModel(id: "mistralai/voxtral-mini-transcribe", displayName: "Mistral Voxtral Mini Transcribe",  pricing: "$0.003/s"),
    STTModel(id: "nvidia/parakeet-tdt-0.6b-v3",   displayName: "NVIDIA Parakeet TDT 0.6B v3",          pricing: "$0.0015/s"),
    STTModel(id: "microsoft/mai-transcribe-1.5",  displayName: "Microsoft MAI-Transcribe 1.5",         pricing: "$0.36/s"),
]

// MARK: - STT Settings

struct STTSettings {
    @StoredDefault(key: "STTModel", defaultValue: "openai/whisper-large-v3")
    static var model: String

    @StoredDefault(key: "STTLanguage", defaultValue: "")
    static var language: String

    @StoredDefault(key: "STTSilenceTimeout", defaultValue: 6.0)
    static var silenceTimeout: TimeInterval

    @StoredDefault(key: "STTMaxDuration", defaultValue: 300.0)
    static var maxDuration: TimeInterval

    @StoredDefault(key: "STTPressEnterAfterPaste", defaultValue: true)
    static var pressEnterAfterPaste: Bool

    @StoredDefault(key: "STTTargetWindow", defaultValue: "")
    static var targetWindow: String
}
@propertyWrapper
struct StoredDefault<T: Codable> {
    let key: String
    let defaultValue: T

    var wrappedValue: T {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let value = try? JSONDecoder().decode(T.self, from: data)
            else { return defaultValue }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "com.airdictate.app.stt"

    static func save(apiKey: String) {
        guard let data = apiKey.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "openrouter_api_key",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Returns true if an API key exists without triggering keychain prompt
    static func hasKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "openrouter_api_key",
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "openrouter_api_key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "openrouter_api_key",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - STTController

@MainActor
final class STTController: ObservableObject {
    @Published private(set) var state: STTState = .idle
    @Published private(set) var lastTranscription: String?
    @Published private(set) var availableModels: [STTModel] = availableSTTModels
    @Published private(set) var isLoadingModels = false

    nonisolated(unsafe) private let log: DebugLog
    nonisolated(unsafe) private var keySender: KeyEventSender?

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var silenceTimer: Timer?
    private var maxDurationTimer: Timer?
    private var recordingStartTime: Date?
    private var lastAudioLevelTime: Date = .distantPast

    init(log: DebugLog) {
        self.log = log
    }

    func setKeySender(_ sender: KeyEventSender) {
        self.keySender = sender
    }

    func fetchAvailableModels() {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        Task {
            defer { isLoadingModels = false }
            do {
                var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models?output_modalities=transcription")!)
                request.timeoutInterval = 10
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = json["data"] as? [[String: Any]] else { return }

                let fetched = models.compactMap { model -> STTModel? in
                    guard let id = model["id"] as? String,
                          let name = model["name"] as? String,
                          let pricing = model["pricing"] as? [String: Any],
                          let promptCost = pricing["prompt"] else { return nil }
                    let pricingStr: String
                    if let costNum = promptCost as? Double {
                        pricingStr = costNum < 0.01
                            ? "$\(String(format: "%.6f", costNum))/s"
                            : "$\(String(format: "%.4f", costNum))/s"
                    } else {
                        pricingStr = "per token"
                    }
                    return STTModel(id: id, displayName: name, pricing: pricingStr)
                }
                if !fetched.isEmpty {
                    self.availableModels = fetched
                    log.info("STT: Loaded \(fetched.count) models from API")
                }
            } catch {
                log.debug("STT: Failed to fetch model list — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Recording lifecycle

    func toggle() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .transcribing:
            log.info("STT: Ignoring toggle — already transcribing")
        case .error:
            state = .idle
            startRecording()
        }
    }

    func cancel() {
        guard state.isRecording else { return }
        stopRecorder()
        state = .idle
        cleanupRecordingFile()
        log.info("STT: Recording cancelled")
    }

    // MARK: - Private: Recording

    private func startRecording() {
        guard let apiKey = Keychain.load(), !apiKey.isEmpty else {
            state = .error("No OpenRouter API key configured")
            log.error("STT: No API key — cannot start recording")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.startRecordingAfterPermission()
                    } else {
                        self?.state = .error("Microphone access denied")
                        self?.log.error("STT: Microphone permission denied by user")
                    }
                }
            }
            return
        case .denied, .restricted:
            state = .error("Microphone access denied")
            log.error("STT: Microphone permission denied")
            return
        case .authorized:
            break
        @unknown default:
            break
        }

        startRecordingAfterPermission()
    }

    private func startRecordingAfterPermission() {
        let recURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stt_recording_\(UUID().uuidString).wav")
        self.recordingURL = recURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let rec: AVAudioRecorder
        do {
            rec = try AVAudioRecorder(url: recURL, settings: settings)
        } catch {
            state = .error("Failed to create recorder")
            log.error("STT: AVAudioRecorder init failed — \(error.localizedDescription)")
            return
        }

        rec.isMeteringEnabled = true
        rec.prepareToRecord()
        let started = rec.record()
        guard started else {
            state = .error("Failed to start recording")
            log.error("STT: record() returned false")
            return
        }

        self.recorder = rec
        let now = Date()
        recordingStartTime = now
        lastAudioLevelTime = now
        state = .recording(startedAt: now)
        log.info("STT: Recording started")

        // Play start sound after delay so mic is fully active and won't capture it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSSound(named: "Tink")?.play()
        }

        // Silence detection timer
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSilence() }
        }

        // Max duration timer
        let maxDur = STTSettings.maxDuration
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxDur, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.log.info("STT: Max duration (\(maxDur)s) reached — stopping")
                self?.stopRecording()
            }
        }
    }

    private func checkSilence() {
        guard state.isRecording, let rec = recorder else { return }
        rec.updateMeters()
        let level = rec.averagePower(forChannel: 0)

        if level > -50 {
            lastAudioLevelTime = Date()
        }

        let silenceDuration = Date().timeIntervalSince(lastAudioLevelTime)
        let timeout = STTSettings.silenceTimeout
        if silenceDuration >= timeout, Date().timeIntervalSince(recordingStartTime ?? Date()) > 0.5 {
            log.info("STT: Silence detected for \(String(format: "%.1f", silenceDuration))s — stopping")
            stopRecording()
        }
    }

    private func stopRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        recorder?.stop()
        recorder = nil

        // Play stop sound
        NSSound(named: "Blow")?.play()

        state = .transcribing
        log.info("STT: Recording stopped — transcribing…")

        guard let url = recordingURL, FileManager.default.fileExists(atPath: url.path) else {
            state = .error("Recording file missing")
            log.error("STT: Recording file not found at \(recordingURL?.path ?? "nil")")
            return
        }

        let capturedURL = url
        Task {
            do {
                let text = try await transcribe(audioURL: capturedURL)
                await MainActor.run {
                    self.lastTranscription = text
                    self.state = .idle
                    self.pasteText(text)
                }
                log.info("STT: Transcription complete — \(text.count) chars")
            } catch {
                await MainActor.run {
                    self.state = .error(error.localizedDescription)
                }
                log.error("STT: Transcription failed — \(error.localizedDescription)")
            }
            cleanupRecordingFile()
        }
    }

    private func stopRecorder() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        recorder?.stop()
        recorder = nil
    }

    private func cleanupRecordingFile() {
        guard let url = recordingURL else { return }
        try? FileManager.default.removeItem(at: url)
        recordingURL = nil
    }

    // MARK: - Transcription API

    private func transcribe(audioURL: URL) async throws -> String {
        let audioData = try Data(contentsOf: audioURL)
        let base64Audio = audioData.base64EncodedString()

        guard let apiKey = Keychain.load(), !apiKey.isEmpty else {
            throw STTError.noAPIKey
        }

        let model = STTSettings.model
        let language = STTSettings.language

        var body: [String: Any] = [
            "model": model,
            "input_audio": [
                "data": base64Audio,
                "format": "wav",
            ],
        ]

        if !language.isEmpty {
            body["language"] = language
        }

        body["provider"] = [
            "options": [
                "groq": [
                    "prompt": "Transcribe accurately. The speaker may stumble, restart sentences, or self-correct. Produce clean, final text without disfluencies.",
                ],
            ],
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw STTError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw STTError.apiError(status: httpResponse.statusCode, body: body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else {
            throw STTError.parseError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Paste

    private func pasteText(_ text: String) {
        guard !text.isEmpty else {
            log.info("STT: Empty transcription — not pasting")
            return
        }

        guard let sender = keySender else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            log.info("STT: Text copied to clipboard (no KeyEventSender available)")
            return
        }

        let success = sender.paste(text: text)
        if !success {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            log.info("STT: Paste failed — text copied to clipboard")
        }

        if STTSettings.pressEnterAfterPaste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                sender.send(KeyStrokeAction(keyCode: 36, modifiers: []))
            }
        }

        NSSound(named: "Purr")?.play()
    }
}

// MARK: - Errors

enum STTError: LocalizedError {
    case noAPIKey
    case networkError(String)
    case apiError(status: Int, body: String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenRouter API key not configured"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let status, let body):
            return "API error \(status): \(body.prefix(200))"
        case .parseError:
            return "Failed to parse transcription response"
        }
    }
}
