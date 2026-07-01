import SwiftUI

// MARK: - Setup Step

private enum SetupStep: Int, CaseIterable {
    case microphone
    case accessibility
    case keychain
    case apiKey

    var title: String {
        switch self {
        case .microphone:    return "Microphone"
        case .accessibility: return "Accessibility"
        case .keychain:      return "Keychain"
        case .apiKey:        return "API Key"
        }
    }

    var icon: String {
        switch self {
        case .microphone:    return "mic.fill"
        case .accessibility: return "hand.tap.fill"
        case .keychain:      return "key.fill"
        case .apiKey:        return "lock.shield.fill"
        }
    }
}

// MARK: - SetupView

struct SetupView: View {
    @EnvironmentObject var sttController: STTController
    @EnvironmentObject var permissionManager: PermissionManager

    @State private var apiKey: String = ""
    @State private var showApiKey: Bool = false
    @State private var model: String = STTSettings.model
    @State private var completedSteps: Set<SetupStep> = []
    @State private var isSubmitting: Bool = false
    @State private var hasOpenedAccessibility: Bool = false
    @State private var didAutoResetAccessibility: Bool = false
    var onComplete: () -> Void

    private var pickerModels: [STTModel] {
        let base = sttController.availableModels
        if base.contains(where: { $0.id == model }) { return base }
        return base + [STTModel(id: model, displayName: model, pricing: "")]
    }

    private var allStepsDone: Bool {
        completedSteps.contains(.microphone) &&
        completedSteps.contains(.accessibility) &&
        completedSteps.contains(.keychain) &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Steps
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(SetupStep.allCases, id: \.self) { step in
                        stepRow(step)
                        if step != .apiKey {
                            stepConnector(step)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }

            Divider()

            // Footer
            footerView
        }
        .frame(minWidth: 520, minHeight: 620)
        .onAppear {
            permissionManager.refresh()
            apiKey = Keychain.load() ?? ""
            model = STTSettings.model
            sttController.fetchAvailableModels()

            autoResetAndRequestAccessibility()
            refreshCompletedSteps()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Refresh permissions when user returns from System Settings
            permissionManager.refresh()
            refreshCompletedSteps()
        }
        .onChange(of: apiKey) { _, _ in refreshCompletedSteps() }
        .onChange(of: permissionManager.microphoneAuthorized) { _, _ in refreshCompletedSteps() }
        .onChange(of: permissionManager.accessibilityTrusted) { _, _ in refreshCompletedSteps() }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 10) {
            Image(systemName: "airpods.gen3")
                .font(.system(size: 40))
                .foregroundStyle(.blue, .green)
                .padding(.top, 28)

            Text("Welcome to AirDictate")
                .font(.title2)
                .fontWeight(.bold)

            Text("We need a few permissions to get you dictating.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Step Row

    private func stepRow(_ step: SetupStep) -> some View {
        let isComplete = completedSteps.contains(step)
        let isUnlocked = step == .microphone || completedSteps.contains(SetupStep(rawValue: step.rawValue - 1)!)

        return HStack(alignment: .top, spacing: 14) {
            // Step circle
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green : Color.primary.opacity(0.1))
                    .frame(width: 32, height: 32)
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: step.icon)
                        .font(.caption)
                        .foregroundStyle(isUnlocked ? .secondary : .tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.headline)
                    .foregroundStyle(isUnlocked ? .primary : .tertiary)

                stepDescription(step)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isUnlocked && !isComplete {
                    stepAction(step)
                }
            }

            Spacer()
        }
        .padding(.vertical, 14)
        .opacity(isUnlocked ? 1 : 0.4)
    }

    // MARK: - Step Connector

    private func stepConnector(_ step: SetupStep) -> some View {
        HStack {
            Spacer().frame(width: 30)
            Rectangle()
                .fill(completedSteps.contains(step) ? Color.green.opacity(0.3) : Color.primary.opacity(0.08))
                .frame(width: 2, height: 16)
            Spacer()
        }
    }

    // MARK: - Step Description

    @ViewBuilder
    private func stepDescription(_ step: SetupStep) -> some View {
        switch step {
        case .microphone:
            Text("AirDictate records your voice to transcribe it. Your audio is sent to OpenRouter over an encrypted connection and discarded after transcription.")
        case .accessibility:
            Text("AirDictate needs Accessibility access to paste text into your applications.")
        case .keychain:
            Text("Your OpenRouter API key is stored securely in the macOS Keychain — the same place Safari saves your passwords. You'll be prompted once to allow this.")
        case .apiKey:
            Text("Sign up at [openrouter.ai](https://openrouter.ai) to get an API key. You only pay for what you use — most models cost fractions of a cent per minute.")
        }
    }

    // MARK: - Step Action

    @ViewBuilder
    private func stepAction(_ step: SetupStep) -> some View {
        switch step {
        case .microphone:
            Button("Allow Microphone") {
                permissionManager.requestMicrophone()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .accessibility:
            if hasOpenedAccessibility {
                HStack(spacing: 8) {
                    Button("Restart AirDictate") {
                        restartApp()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Check again") {
                        permissionManager.refresh()
                        refreshCompletedSteps()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            } else {
                Button("Open Accessibility Settings") {
                    permissionManager.openAccessibilitySettings()
                    hasOpenedAccessibility = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .keychain:
            Button("Continue") {
                completedSteps.insert(.keychain)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .apiKey:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if showApiKey {
                        TextField("sk-or-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-or-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { showApiKey.toggle() }) {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption2)
                    Link("Get an API key from OpenRouter",
                         destination: URL(string: "https://openrouter.ai/settings/keys")!)
                        .font(.caption)
                }

                if !sttController.availableModels.isEmpty {
                    Picker("Model", selection: $model) {
                        ForEach(pickerModels) { m in
                            Text("\(m.displayName)  —  \(m.pricing)")
                                .tag(m.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: model) { _, newValue in
                        STTSettings.model = newValue
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text(allStepsDone
                 ? "You're all set!"
                 : "Complete all steps above to continue")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Get Started") {
                submit()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!allStepsDone || isSubmitting)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    // MARK: - Logic

    private func refreshCompletedSteps() {
        if permissionManager.microphoneAuthorized {
            completedSteps.insert(.microphone)
        }
        if permissionManager.accessibilityTrusted {
            completedSteps.insert(.accessibility)
        }
    }

    private func submit() {
        isSubmitting = true
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            Keychain.save(apiKey: trimmed)
        }
        STTSettings.model = model
        onComplete()
    }


    private func autoResetAndRequestAccessibility() {
        guard !didAutoResetAccessibility else { return }
        didAutoResetAccessibility = true

        // Reset stale TCC entry so the app appears cleanly in the list
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", "Accessibility", "com.airdictate.app"]
        try? task.run()
        task.waitUntilExit()

        // Request accessibility to add the app to the System Settings list
        permissionManager.requestAccessibility()
        permissionManager.refresh()
    }

    private func restartApp() {
        let appURL = Bundle.main.bundleURL
        let script = "sleep 0.5; open '\(appURL.path)'"
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]
        try? task.run()
        Darwin.exit(0)
    }
}
