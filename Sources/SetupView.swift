import SwiftUI
import AVFoundation
import Combine
import Foundation
import ServiceManagement

struct SetupView: View {
    var onComplete: () -> Void

    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL

    private let openAIKeysURL = URL(string: "https://platform.openai.com/api-keys")!

    private enum SetupStep: Int, CaseIterable {
        case welcome = 0
        case apiKey
        case micPermission
        case accessibility
        case hotkey
        case launchAtLogin
        case testTranscription
        case ready
    }

    private enum TestPhase: Equatable {
        case idle
        case recording
        case transcribing
        case done
    }

    @State private var currentStep = SetupStep.welcome
    @State private var micPermissionGranted = false
    @State private var accessibilityGranted = false
    @State private var apiKeyInput = ""
    @State private var isValidatingKey = false
    @State private var keyValidationError: String?
    @State private var accessibilityTimer: Timer?

    @State private var testPhase: TestPhase = .idle
    @State private var testAudioRecorder: AudioRecorder? = nil
    @State private var testAudioLevel: Float = 0.0
    @State private var testTranscript = ""
    @State private var testError: String?
    @State private var testAudioLevelCancellable: AnyCancellable?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .apiKey:
                    apiKeyStep
                case .micPermission:
                    micPermissionStep
                case .accessibility:
                    accessibilityStep
                case .hotkey:
                    hotkeyStep
                case .launchAtLogin:
                    launchAtLoginStep
                case .testTranscription:
                    testTranscriptionStep
                case .ready:
                    readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)

            Divider()

            HStack {
                if currentStep != .welcome {
                    Button("Back") {
                        keyValidationError = nil
                        withAnimation {
                            currentStep = previousStep(currentStep)
                        }
                    }
                    .disabled(isValidatingKey)
                }

                Spacer()

                if currentStep != .ready {
                    if currentStep == .apiKey {
                        Button(isValidatingKey ? "Validating..." : "Continue") {
                            validateAndContinue()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidatingKey)
                    } else if currentStep == .testTranscription {
                        Button("Skip") {
                            stopTestHotkeyMonitoring()
                            withAnimation {
                                currentStep = nextStep(currentStep)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        Button("Continue") {
                            stopTestHotkeyMonitoring()
                            withAnimation {
                                currentStep = nextStep(currentStep)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(testPhase != .done || testTranscript.isEmpty || testError != nil)
                    } else {
                        Button("Continue") {
                            withAnimation {
                                currentStep = nextStep(currentStep)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canContinueFromCurrentStep)
                    }
                } else {
                    Button("Get Started") {
                        onComplete()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 520)
        .onAppear {
            apiKeyInput = appState.apiKey
            checkMicPermission()
            checkAccessibility()
        }
        .onDisappear {
            accessibilityTimer?.invalidate()
            stopTestHotkeyMonitoring()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 128, height: 128)

            Text("Welcome to FreeFlow")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("Hold a key to dictate anywhere on your Mac. This build uses OpenAI transcription with `gpt-4o-mini-transcribe`.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "waveform", text: "Record while holding your push-to-talk key")
                featureRow(icon: "text.cursor", text: "Paste the transcript into the focused field on release")
                featureRow(icon: "lock.shield", text: "Bring your own OpenAI API key")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)

            stepIndicator
        }
    }

    private var apiKeyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("OpenAI API Key")
                .font(.title)
                .fontWeight(.bold)

            Text("FreeFlow sends your recorded audio to the OpenAI transcription endpoint using `gpt-4o-mini-transcribe`.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How to get an API key")
                        .font(.subheadline.weight(.semibold))

                    VStack(alignment: .leading, spacing: 4) {
                        instructionRow(number: "1", text: "Open [platform.openai.com/api-keys](https://platform.openai.com/api-keys)")
                        instructionRow(number: "2", text: "Create a new secret key")
                        instructionRow(number: "3", text: "Paste it below")
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.06)))

                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key")
                        .font(.headline)

                    SecureField("Paste your OpenAI API key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(isValidatingKey)
                        .onChange(of: apiKeyInput) { _ in
                            keyValidationError = nil
                        }

                    if let error = keyValidationError {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }

            stepIndicator
        }
    }

    private var micPermissionStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Microphone Access")
                .font(.title)
                .fontWeight(.bold)

            Text("FreeFlow needs microphone access to record dictation.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            permissionRow(
                title: "Microphone",
                icon: "mic.fill",
                granted: micPermissionGranted,
                action: requestMicPermission
            )

            stepIndicator
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Accessibility Access")
                .font(.title)
                .fontWeight(.bold)

            Text("FreeFlow needs Accessibility permission so it can paste transcripts into the active app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            permissionRow(
                title: "Accessibility",
                icon: "hand.raised.fill",
                granted: accessibilityGranted,
                action: {
                    requestAccessibility()
                    startAccessibilityPolling()
                }
            )

            stepIndicator
        }
    }

    private var hotkeyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Push-to-Talk Key")
                .font(.title)
                .fontWeight(.bold)

            Text("Hold this key to record. Release it to send the audio for transcription.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(HotkeyOption.allCases) { option in
                    HotkeyOptionRow(
                        option: option,
                        isSelected: appState.selectedHotkey == option,
                        action: {
                            appState.selectedHotkey = option
                        }
                    )
                }
            }

            if appState.selectedHotkey == .fnKey {
                Text("Tip: if `Fn` opens the Emoji picker, change System Settings > Keyboard > “Press fn key to” to “Do Nothing”.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            stepIndicator
        }
    }

    private var launchAtLoginStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "power")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Launch at Login")
                .font(.title)
                .fontWeight(.bold)

            Text("Optional, but recommended if you want FreeFlow available whenever you log in.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Toggle("Launch FreeFlow at login", isOn: $appState.launchAtLogin)
                .toggleStyle(.switch)
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)

            if SMAppService.mainApp.status == .requiresApproval {
                Text("Login item approval is required in System Settings > Login Items.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            stepIndicator
        }
    }

    private var testTranscriptionStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Test Dictation")
                .font(.title)
                .fontWeight(.bold)

            Text("Use your selected push-to-talk key to record a short sample and confirm transcription works.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Status")
                        .font(.headline)
                    Spacer()
                    Text(testStatusText)
                        .foregroundStyle(testStatusColor)
                        .font(.subheadline.weight(.semibold))
                }

                ProgressView(value: Double(testAudioLevel), total: 1.0)
                    .progressViewStyle(.linear)

                if !testTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Transcript")
                            .font(.headline)
                        Text(testTranscript)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                if let testError {
                    Label(testError, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .onAppear {
                startTestHotkeyMonitoring()
            }
            .onDisappear {
                stopTestHotkeyMonitoring()
            }

            stepIndicator
        }
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("FreeFlow is Ready")
                .font(.title)
                .fontWeight(.bold)

            Text("Hold \(appState.selectedHotkey.displayName) anywhere on your Mac to dictate with OpenAI.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("View OpenAI API Keys") {
                openURL(openAIKeysURL)
            }

            stepIndicator
        }
    }

    private var canContinueFromCurrentStep: Bool {
        switch currentStep {
        case .micPermission:
            return micPermissionGranted
        case .accessibility:
            return accessibilityGranted
        default:
            return true
        }
    }

    private var testStatusText: String {
        switch testPhase {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording"
        case .transcribing:
            return "Transcribing"
        case .done:
            return testError == nil ? "Done" : "Failed"
        }
    }

    private var testStatusColor: Color {
        switch testPhase {
        case .recording:
            return .red
        case .transcribing:
            return .orange
        case .done:
            return testError == nil ? .green : .red
        default:
            return .secondary
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(SetupStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(width: 28, height: 6)
            }
        }
        .padding(.top, 8)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.blue)
            Text(text)
            Spacer()
        }
    }

    private func permissionRow(title: String, icon: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.blue)
            Text(title)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Grant Access", action: action)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func instructionRow(number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(number + ".")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.subheadline)
                .tint(.blue)
        }
    }

    private func validateAndContinue() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        isValidatingKey = true
        keyValidationError = nil

        Task {
            let result = await TranscriptionService.validateAPIKey(key, baseURL: appState.apiBaseURL)
            await MainActor.run {
                isValidatingKey = false
                if result.isValid {
                    appState.apiKey = key
                    withAnimation {
                        currentStep = nextStep(currentStep)
                    }
                } else {
                    keyValidationError = result.message ?? "OpenAI key validation failed. Check the key and verify it has access to gpt-4o-mini-transcribe."
                }
            }
        }
    }

    private func previousStep(_ step: SetupStep) -> SetupStep {
        SetupStep(rawValue: step.rawValue - 1) ?? .welcome
    }

    private func nextStep(_ step: SetupStep) -> SetupStep {
        SetupStep(rawValue: step.rawValue + 1) ?? .ready
    }

    private func checkMicPermission() {
        micPermissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func requestMicPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                micPermissionGranted = granted
            }
        }
    }

    private func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func startAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                checkAccessibility()
            }
        }
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func startTestHotkeyMonitoring() {
        appState.hotkeyManager.onKeyDown = { [self] in
            DispatchQueue.main.async {
                guard testPhase == .idle || testPhase == .done else { return }
                if testPhase == .done {
                    resetTest()
                }

                do {
                    let recorder = AudioRecorder()
                    try recorder.startRecording(deviceUID: appState.selectedMicrophoneID)
                    testAudioRecorder = recorder
                    testAudioLevelCancellable = recorder.$audioLevel
                        .receive(on: DispatchQueue.main)
                        .sink { level in
                            testAudioLevel = level
                        }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        testPhase = .recording
                    }
                } catch {
                    testError = error.localizedDescription
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        testPhase = .done
                    }
                }
            }
        }

        appState.hotkeyManager.onKeyUp = { [self] in
            DispatchQueue.main.async {
                guard testPhase == .recording, let recorder = testAudioRecorder else { return }
                let fileURL = recorder.stopRecording()
                testAudioLevelCancellable?.cancel()
                testAudioLevelCancellable = nil
                testAudioLevel = 0.0

                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    testPhase = .transcribing
                }

                guard let url = fileURL else {
                    testError = "No audio file was created."
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        testPhase = .done
                    }
                    return
                }

                Task {
                    do {
                        let service = TranscriptionService(apiKey: appState.apiKey, baseURL: appState.apiBaseURL)
                        let transcript = try await service.transcribe(fileURL: url)
                        await MainActor.run {
                            testTranscript = transcript
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                testPhase = .done
                            }
                        }
                    } catch {
                        await MainActor.run {
                            testError = error.localizedDescription
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                testPhase = .done
                            }
                        }
                    }
                    recorder.cleanup()
                }
            }
        }

        appState.hotkeyManager.start(option: appState.selectedHotkey)
    }

    private func stopTestHotkeyMonitoring() {
        appState.hotkeyManager.stop()
        appState.hotkeyManager.onKeyDown = nil
        appState.hotkeyManager.onKeyUp = nil
        testAudioLevelCancellable?.cancel()
        testAudioLevelCancellable = nil
        if let recorder = testAudioRecorder, recorder.isRecording {
            _ = recorder.stopRecording()
            recorder.cleanup()
        }
        testAudioRecorder = nil
    }

    private func resetTest() {
        testPhase = .idle
        testTranscript = ""
        testError = nil
        testAudioLevel = 0.0
        if let recorder = testAudioRecorder {
            if recorder.isRecording {
                _ = recorder.stopRecording()
            }
            recorder.cleanup()
            testAudioRecorder = nil
        }
    }
}

struct HotkeyOptionRow: View {
    let option: HotkeyOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(option.displayName)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
