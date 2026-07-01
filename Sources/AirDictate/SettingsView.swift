import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var log: DebugLog
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var nowPlayingController: NowPlayingController
    @EnvironmentObject var loginItemManager: LoginItemManager
    @EnvironmentObject var sttController: STTController

    var body: some View {
        TabView {
            STTSettingsView()
                .tabItem { Label("Transcription", systemImage: "mic") }
            GeneralSettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
            LogsTab()
                .tabItem { Label("Logs", systemImage: "doc.text") }
        }
        .padding(.top, 8)
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsView: View {
    @EnvironmentObject var nowPlayingController: NowPlayingController
    @EnvironmentObject var loginItemManager: LoginItemManager
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var log: DebugLog

    @State private var availableWindows: [WindowInfo] = []
    @State private var targetWindowKey: String = STTSettings.targetWindow

    var body: some View {
        Form {
            Section {
                Toggle("Enable", isOn: $nowPlayingController.isGloballyEnabled)
                Toggle("Start at Login", isOn: Binding(
                    get: { loginItemManager.isEnabled },
                    set: { loginItemManager.setEnabled($0) }
                ))
            }

            Section("Status") {
                HStack {
                    statusDot
                    Text(nowPlayingController.status.displayString)
                        .font(.callout)
                }
            }

            Section("Fake Player") {
                Text("When no real media app owns Now Playing, a fake player is published so AirPods commands are captured here instead of launching Music.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Reclaim") { nowPlayingController.forceReclaim() }
                    Button("Release") { nowPlayingController.forceRelease() }
                }
            }

            Section("Accessibility Permission") {
                HStack {
                    Image(systemName: permissionManager.accessibilityTrusted
                        ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(permissionManager.accessibilityTrusted ? .green : .red)
                    VStack(alignment: .leading) {
                        Text(permissionManager.accessibilityTrusted
                            ? "Granted" : "Not granted")
                            .font(.headline)
                        Text("Needed to paste transcribed text and press Enter.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !permissionManager.accessibilityTrusted {
                        Button("Request") {
                            permissionManager.requestAccessibility()
                        }
                    }
                    Button("Open Settings") {
                        permissionManager.openAccessibilitySettings()
                    }
                }
            }

            Section {
                Toggle("Debug Logging", isOn: $log.debugEnabled)
            }

            Section("Paste Target") {
                Text("By default, AirDictate pastes into whichever window is currently focused. Choose a specific window to always focus before pasting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if availableWindows.isEmpty {
                    Text("No windows found. Open some applications first.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Picker("Window", selection: $targetWindowKey) {
                    Text("Active window (default)").tag("")
                    Divider()
                    ForEach(availableWindows) { win in
                        Text(win.displayName).tag(win.stableKey)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: targetWindowKey) { _, newValue in
                    STTSettings.targetWindow = newValue
                }
            }

            Section {
                Button("Reset Setup") {
                    resetSetup()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loginItemManager.refresh()
            permissionManager.refresh()
            refreshWindows()
            targetWindowKey = STTSettings.targetWindow
        }
    }


    private func refreshWindows() {
        availableWindows = WindowLister().listWindows()
    }

    private func resetSetup() {
        Keychain.delete()
        STTSettings.model = "openai/whisper-large-v3"
        STTSettings.language = ""
        STTSettings.silenceTimeout = 6.0
        STTSettings.maxDuration = 300.0
        STTSettings.pressEnterAfterPaste = true
        STTSettings.targetWindow = ""
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch nowPlayingController.status {
        case .activeFakePlayer: return .green
        case .passiveRealPlayer: return .yellow
        case .disabled: return .gray
        case .error: return .red
        }
    }
}

// MARK: - Logs Tab

struct LogsTab: View {
    @EnvironmentObject var log: DebugLog

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Copy Logs") { log.copyToClipboard() }
                Button("Clear") { log.clear() }
                Spacer()
            }
            .padding(.horizontal)

            ScrollViewReader { proxy in
                List(log.entries) { entry in
                    HStack(alignment: .top, spacing: 6) {
                        Text(entry.timestamp, style: .time)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.caption)
                            .foregroundStyle(entry.level == .error ? .red : .primary)
                    }
                    .id(entry.id)
                }
                .onChange(of: log.entries.count) { _, _ in
                    if let last = log.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Speech to Text Tab

struct STTSettingsView: View {
    @EnvironmentObject var sttController: STTController

    @State private var apiKey: String = ""
    @State private var model: String = STTSettings.model
    @State private var language: String = STTSettings.language
    @State private var silenceTimeout: Double = STTSettings.silenceTimeout
    @State private var maxDuration: Double = STTSettings.maxDuration
    @State private var showApiKey: Bool = false
    @State private var pressEnterAfterPaste: Bool = STTSettings.pressEnterAfterPaste

    private var pickerModels: [STTModel] {
        let base = sttController.availableModels
        if base.contains(where: { $0.id == model }) { return base }
        return base + [STTModel(id: model, displayName: model, pricing: "")]
    }

    var body: some View {
        Form {
            Section("OpenRouter API") {
                HStack {
                    if showApiKey {
                        TextField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { showApiKey.toggle() }) {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
                .onChange(of: apiKey) { _, newValue in
                    if !newValue.isEmpty {
                        Keychain.save(apiKey: newValue)
                    } else {
                        Keychain.delete()
                    }
                }

                HStack {
                    Circle()
                        .fill(apiKey.isEmpty ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(apiKey.isEmpty ? "No API key set" : "API key configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if sttController.isLoadingModels {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                        Text("Loading models…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Picker("Model", selection: Binding(
                    get: { sttController.availableModels.first(where: { $0.id == model })?.id ?? model },
                    set: { newID in
                        model = newID
                        STTSettings.model = newID
                    }
                )) {
                    ForEach(pickerModels) { m in
                        HStack {
                            Text(m.displayName)
                            Spacer()
                            Text(m.pricing)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .tag(m.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Language (optional)") {
                TextField("ISO-639-1 code (e.g. en, de, ja)", text: $language)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: language) { _, newValue in
                        STTSettings.language = newValue
                    }
                Text("Leave empty for automatic detection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Recording") {
                HStack {
                    Text("Silence timeout:")
                    Slider(value: $silenceTimeout, in: 0.5...20, step: 0.5)
                    Text("\(silenceTimeout, specifier: "%.1f")s")
                        .font(.caption.monospacedDigit())
                }
                .onChange(of: silenceTimeout) { _, newValue in
                    STTSettings.silenceTimeout = newValue
                }
                HStack {
                    Text("Max duration:")
                    Slider(value: $maxDuration, in: 10...600, step: 30)
                    Text("\(maxDuration, specifier: "%.0f")s")
                        .frame(width: 45, alignment: .trailing)
                        .font(.caption.monospacedDigit())
                }
                .onChange(of: maxDuration) { _, newValue in
                    STTSettings.maxDuration = newValue
                }
                Toggle("Press Enter after paste", isOn: $pressEnterAfterPaste)
                    .onChange(of: pressEnterAfterPaste) { _, newValue in
                        STTSettings.pressEnterAfterPaste = newValue
                    }
            }

            Section("Status") {
                HStack {
                    Text("Current state:")
                    Text(sttController.state.displayString)
                        .font(.callout)
                        .foregroundStyle(
                            sttController.state.isRecording ? .red :
                            sttController.state.isTranscribing ? .orange :
                            .primary
                        )
                }

                if let last = sttController.lastTranscription, !last.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last transcription:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(last)
                            .font(.caption)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(6)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            apiKey = Keychain.load() ?? ""
            model = STTSettings.model
            language = STTSettings.language
            silenceTimeout = STTSettings.silenceTimeout
            maxDuration = STTSettings.maxDuration
            pressEnterAfterPaste = STTSettings.pressEnterAfterPaste
            sttController.fetchAvailableModels()
        }
    }
}
