import SwiftUI
import AVFoundation
import ServiceManagement

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        appState.selectedSettingsTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(appState.selectedSettingsTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(10)
            .frame(width: 180)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            Group {
                switch appState.selectedSettingsTab {
                case .general, .none:
                    GeneralSettingsView()
                case .runLog:
                    RunLogView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    @State private var apiKeyInput = ""
    @State private var isValidatingKey = false
    @State private var keyValidationError: String?
    @State private var keyValidationSuccess = false
    @State private var micPermissionGranted = false

    @ObservedObject private var updateManager = UpdateManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)

                    Text("FreeFlow")
                        .font(.system(size: 20, weight: .bold, design: .rounded))

                    Text("OpenAI Audio Transcriptions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("Model: `gpt-4o-mini-transcribe`")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 4)

                SettingsCard("Startup", icon: "power") {
                    startupSection
                }

                SettingsCard("Updates", icon: "arrow.triangle.2.circlepath") {
                    updatesSection
                }

                SettingsCard("OpenAI API Key", icon: "key.fill") {
                    apiKeySection
                }

                SettingsCard("Push-to-Talk Key", icon: "keyboard.fill") {
                    hotkeySection
                }

                SettingsCard("Microphone", icon: "mic.fill") {
                    microphoneSection
                }

                SettingsCard("Permissions", icon: "lock.shield.fill") {
                    permissionsSection
                }
            }
            .padding(24)
        }
        .onAppear {
            apiKeyInput = appState.apiKey
            checkMicPermission()
            appState.refreshLaunchAtLoginStatus()
        }
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Launch FreeFlow at login", isOn: $appState.launchAtLogin)

            if SMAppService.mainApp.status == .requiresApproval {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Login item requires approval in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Automatically check for updates", isOn: Binding(
                get: { updateManager.autoCheckEnabled },
                set: { updateManager.autoCheckEnabled = $0 }
            ))

            HStack(spacing: 10) {
                Button {
                    Task {
                        await updateManager.checkForUpdates(userInitiated: true)
                    }
                } label: {
                    if updateManager.isChecking {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking...")
                        }
                    } else {
                        Text("Check for Updates Now")
                    }
                }
                .disabled(updateManager.isChecking || updateManager.updateStatus != .idle)

                if let lastCheck = updateManager.lastCheckDate {
                    Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if updateManager.updateAvailable {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    Text("A new version of FreeFlow is available.")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Update Now") {
                        if let release = updateManager.latestRelease {
                            updateManager.downloadAndInstall(release: release)
                        }
                    }
                    .font(.caption)
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FreeFlow uses OpenAI's audio transcription endpoint for dictation. The key is stored locally on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                SecureField("Enter your OpenAI API key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(isValidatingKey)
                    .onChange(of: apiKeyInput) { _ in
                        keyValidationError = nil
                        keyValidationSuccess = false
                    }

                Button(isValidatingKey ? "Validating..." : "Save") {
                    validateAndSaveKey()
                }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidatingKey)
            }

            if let error = keyValidationError {
                Label(error, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if keyValidationSuccess {
                Label("API key saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }

    private func validateAndSaveKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        isValidatingKey = true
        keyValidationError = nil
        keyValidationSuccess = false

        Task {
            let result = await TranscriptionService.validateAPIKey(key, baseURL: appState.apiBaseURL)
            await MainActor.run {
                isValidatingKey = false
                if result.isValid {
                    appState.apiKey = key
                    keyValidationSuccess = true
                } else {
                    keyValidationError = result.message ?? "OpenAI key validation failed. Check the key and model access."
                }
            }
        }
    }

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hold this key to record, release it to transcribe.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
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
        }
    }

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose which microphone FreeFlow should record from.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                MicrophoneOptionRow(
                    name: "System Default",
                    isSelected: appState.selectedMicrophoneID == "default" || appState.selectedMicrophoneID.isEmpty,
                    action: { appState.selectedMicrophoneID = "default" }
                )

                ForEach(appState.availableMicrophones) { device in
                    MicrophoneOptionRow(
                        name: device.name,
                        isSelected: appState.selectedMicrophoneID == device.uid,
                        action: { appState.selectedMicrophoneID = device.uid }
                    )
                }
            }
        }
        .onAppear {
            appState.refreshAvailableMicrophones()
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            permissionRow(
                title: "Microphone",
                icon: "mic.fill",
                granted: micPermissionGranted,
                action: {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        DispatchQueue.main.async {
                            micPermissionGranted = granted
                        }
                    }
                }
            )

            permissionRow(
                title: "Accessibility",
                icon: "hand.raised.fill",
                granted: appState.hasAccessibility,
                action: {
                    appState.openAccessibilitySettings()
                }
            )
        }
    }

    private func permissionRow(title: String, icon: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
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
                    .font(.caption)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    private func checkMicPermission() {
        micPermissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}

struct MicrophoneOptionRow: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(name)
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

struct RunLogView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run Log")
                        .font(.headline)
                    Text("Stored locally. Only the \(appState.maxPipelineHistoryCount) most recent runs are kept.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Clear History") {
                    appState.clearPipelineHistory()
                }
                .disabled(appState.pipelineHistory.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            if appState.pipelineHistory.isEmpty {
                VStack {
                    Spacer()
                    Text("No runs yet. Use dictation to populate history.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(appState.pipelineHistory) { item in
                            RunLogEntryView(item: item)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
}

struct RunLogEntryView: View {
    let item: PipelineHistoryItem

    @EnvironmentObject var appState: AppState
    @State private var isExpanded = false

    private var isError: Bool {
        item.postProcessingStatus.hasPrefix("Error:")
    }

    private var displayTranscript: String {
        let text = item.postProcessedTranscript.isEmpty ? item.rawTranscript : item.postProcessedTranscript
        return text.isEmpty ? "(no transcript)" : text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        if isError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.timestamp.formatted(date: .numeric, time: .standard))
                                .font(.subheadline.weight(.semibold))
                            Text(displayTranscript)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.deleteHistoryEntry(id: item.id)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete this run")
            }
            .padding(12)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 16) {
                    if let audioFileName = item.audioFileName {
                        let audioURL = AppState.audioStorageDirectory().appendingPathComponent(audioFileName)
                        AudioPlayerView(audioURL: audioURL)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Transcript")
                            .font(.caption.weight(.semibold))
                        Text(displayTranscript)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status")
                            .font(.caption.weight(.semibold))
                        Text(item.postProcessingStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 12) {
                        Button("Copy Transcript") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(displayTranscript, forType: .string)
                        }
                        .font(.caption)

                        if let audioFileName = item.audioFileName {
                            let audioURL = AppState.audioStorageDirectory().appendingPathComponent(audioFileName)
                            Button("Reveal Audio") {
                                NSWorkspace.shared.activateFileViewerSelecting([audioURL])
                            }
                            .font(.caption)
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isError ? Color.red.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

struct AudioPlayerView: View {
    @StateObject private var controller: AudioPlayerController

    init(audioURL: URL) {
        _controller = StateObject(wrappedValue: AudioPlayerController(audioURL: audioURL))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recorded Audio")
                .font(.caption.weight(.semibold))

            HStack(spacing: 10) {
                Button(controller.isPlaying ? "Pause" : "Play") {
                    controller.togglePlayback()
                }

                if let duration = controller.durationText {
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

final class AudioPlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var durationText: String?

    private let audioURL: URL
    private var player: AVAudioPlayer?

    init(audioURL: URL) {
        self.audioURL = audioURL
        super.init()
        preparePlayer()
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func preparePlayer() {
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            durationText = Self.formatDuration(player.duration)
        } catch {
            durationText = "Unavailable"
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }

    private static func formatDuration(_ value: TimeInterval) -> String {
        let totalSeconds = Int(value.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
