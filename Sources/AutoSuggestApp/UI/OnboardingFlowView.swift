import AppKit
import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case model
    case finish
}

struct OnboardingFlowView: View {
    let permissionManager: PermissionManager
    let localModelConfig: LocalModelConfig
    let onSelectModelChoice: (OnboardingModelChoice) -> Void
    let onDownloadCoreML: () async throws -> Void
    let onOpenSettings: () -> Void
    let onComplete: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var selectedChoice: OnboardingModelChoice = .ollama
    @State private var isDownloadingCoreML = false
    @State private var downloadError: String?
    @State private var isCoreMLInstalled: Bool
    @State private var heartbeat = Date()
    @State private var copyFeedback: String?
    // Tracks whether Input Monitoring went from denied → granted this session,
    // which requires a relaunch before the CGEvent tap can be installed.
    @State private var inputMonitoringJustGranted = false
    @State private var prevInputMonitoringState = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(
        permissionManager: PermissionManager,
        localModelConfig: LocalModelConfig,
        onSelectModelChoice: @escaping (OnboardingModelChoice) -> Void,
        onDownloadCoreML: @escaping () async throws -> Void,
        onOpenSettings: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.permissionManager = permissionManager
        self.localModelConfig = localModelConfig
        self.onSelectModelChoice = onSelectModelChoice
        self.onDownloadCoreML = onDownloadCoreML
        self.onOpenSettings = onOpenSettings
        self.onComplete = onComplete
        _isCoreMLInstalled = State(initialValue: localModelConfig.isModelPresent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(stepTitle)
                    .font(.largeTitle.weight(.semibold))
                Text(stepSubtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Group {
                    switch currentStep {
                    case .welcome:
                        welcomeStep
                    case .permissions:
                        permissionsStep
                    case .model:
                        modelStep
                    case .finish:
                        finishStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            HStack {
                Button("Quit") {
                    NSApp.terminate(nil)
                }

                if canGoBack {
                    Button("Back") {
                        moveBackward()
                    }
                }

                Spacer()

                if currentStep == .model {
                    Button("Continue") {
                        onSelectModelChoice(selectedChoice)
                        moveForward()
                    }
                    .buttonStyle(.borderedProminent)
                } else if currentStep == .finish {
                    Button("Finish") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Continue") {
                        moveForward()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentStep == .permissions && (!permissionsReady || inputMonitoringJustGranted))
                }
            }
        }
        .padding(28)
        .frame(minWidth: 680, minHeight: 540, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(timer) { value in
            heartbeat = value
            // Detect Input Monitoring transitioning from denied → granted.
            // CGEvent tap installation requires a process restart, so we need
            // to warn the user immediately when this happens.
            let current = permissionManager.hasInputMonitoringPermission()
            if current && !prevInputMonitoringState {
                inputMonitoringJustGranted = true
            }
            prevInputMonitoringState = current
        }
    }

    private var stepTitle: String {
        switch currentStep {
        case .welcome:
            return "Welcome to AutoSuggest"
        case .permissions:
            return "Grant Permissions"
        case .model:
            return "Choose a Model Path"
        case .finish:
            return "First Use"
        }
    }

    private var stepSubtitle: String {
        switch currentStep {
        case .welcome:
            return "A native writing assistant for text fields across macOS."
        case .permissions:
            if inputMonitoringJustGranted {
                return "Relaunch AutoSuggest to apply Input Monitoring."
            }
            return permissionsReady ? "Both permissions are granted — tap Continue." : "AutoSuggest needs both permissions before it can listen and insert."
        case .model:
            return "Choose a runtime, then follow the matching setup path."
        case .finish:
            return "See how suggestions appear and which keys control them."
        }
    }

    private var permissionsReady: Bool {
        _ = heartbeat
        return permissionManager.isAccessibilityTrusted() && permissionManager.hasInputMonitoringPermission()
    }

    private var displayedSteps: [OnboardingStep] {
        permissionsReady ? [.welcome, .model, .finish] : [.welcome, .permissions, .model, .finish]
    }

    private var currentStep: OnboardingStep {
        displayedSteps.contains(step) ? step : .model
    }

    private var canGoBack: Bool {
        currentStep != displayedSteps.first
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if permissionsReady {
                SettingsCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Permissions already granted")
                                .font(.headline)
                            Text("Accessibility and Input Monitoring are already enabled, so onboarding will skip the permission step.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AutoSuggest stays lightweight in the menu bar and keeps advanced controls in a dedicated settings window.")
                    Text("Suggestions appear inline, accept with Tab or Enter, dismiss with Esc, and exclusions keep it out of editors and other sensitive contexts.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Relaunch banner — shown when Input Monitoring was just granted
            if inputMonitoringJustGranted {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Relaunch required")
                            .font(.headline)
                        Text("Input Monitoring was granted. AutoSuggest must relaunch before it can intercept keystrokes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Relaunch Now") {
                        permissionManager.relaunchApp()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                        )
                )
            }

            PermissionDetailRow(
                systemImage: "accessibility",
                title: "Accessibility",
                description: "Lets AutoSuggest read what you're typing and insert completions into any text field. Required for core functionality.",
                ready: permissionManager.isAccessibilityTrusted(),
                primaryAction: ("Show Prompt", {
                    _ = permissionManager.requestAccessibilityPermission()
                }),
                secondaryAction: ("Open Settings", {
                    permissionManager.openAccessibilitySettings()
                })
            )

            PermissionDetailRow(
                systemImage: "keyboard",
                title: "Input Monitoring",
                description: "Lets AutoSuggest detect when you press Tab, Enter, or Esc to accept or dismiss suggestions. Requires a relaunch after granting.",
                ready: permissionManager.hasInputMonitoringPermission(),
                primaryAction: ("Register App", {
                    permissionManager.requestInputMonitoringPermission()
                    permissionManager.openInputMonitoringSettings()
                }),
                secondaryAction: ("Open Settings", {
                    permissionManager.openInputMonitoringSettings()
                })
            )

            if permissionsReady && !inputMonitoringJustGranted {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("All permissions granted — you're ready to continue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                OnboardingChoiceCard(
                    title: "Recommended: Ollama",
                    subtitle: "Best overall quality path for the current app.",
                    selected: selectedChoice == .ollama
                ) {
                    selectedChoice = .ollama
                }

                OnboardingChoiceCard(
                    title: "Use Existing llama.cpp",
                    subtitle: "Good if you already run a local server.",
                    selected: selectedChoice == .llamaCpp
                ) {
                    selectedChoice = .llamaCpp
                }

                OnboardingChoiceCard(
                    title: "Import CoreML",
                    subtitle: "Use a local CoreML artifact or bootstrap the default package.",
                    selected: selectedChoice == .coreML
                ) {
                    selectedChoice = .coreML
                }
            }
            selectedModelSetupSection
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            SuggestionPreviewCard()

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Keyboard controls", systemImage: "keyboard")
                        .font(.headline)

                    ShortcutHighlightRow(
                        title: "Accept the suggestion",
                        subtitle: "The highlighted completion is inserted immediately.",
                        keycaps: ["Tab", "Enter"],
                        accentColor: .blue,
                        highlighted: true
                    )

                    ShortcutHighlightRow(
                        title: "Dismiss for now",
                        subtitle: "Hide the current suggestion and keep typing.",
                        keycaps: ["Esc"],
                        accentColor: .secondary,
                        highlighted: false
                    )
                }
            }

            HStack(spacing: 12) {
                ShortcutActionCard(
                    title: "Quick controls",
                    detail: "Left-click the menu bar icon for status, pause, and diagnostics.",
                    systemImage: "cursorarrow.click.2"
                )
                ShortcutActionCard(
                    title: "Overflow actions",
                    detail: "Right-click the menu bar icon for compact utility actions.",
                    systemImage: "ellipsis.circle"
                )
            }

            SettingsCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: selectedChoice == .coreML ? "cube.transparent" : "cpu")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(selectedChoice.displayTitle) is selected")
                            .font(.headline)
                        Text(selectedChoice.finishSummary(config: localModelConfig))
                            .foregroundStyle(.secondary)
                        Text("Open Settings any time to manage models, permissions, exclusions, accessibility, and diagnostics.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var selectedModelSetupSection: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(selectedChoice.setupTitle, systemImage: selectedChoice.systemImage)
                            .font(.headline)
                        Text(selectedChoice.setupSummary(config: localModelConfig))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    SetupStatusBadge(
                        title: selectedChoice.isReady(
                            config: localModelConfig,
                            isCoreMLInstalled: isCoreMLInstalled
                        ) ? "Ready" : "Needs setup",
                        isReady: selectedChoice.isReady(
                            config: localModelConfig,
                            isCoreMLInstalled: isCoreMLInstalled
                        )
                    )
                }

                if let copyFeedback {
                    Text(copyFeedback)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                switch selectedChoice {
                case .ollama:
                    CommandSnippetCard(
                        title: "Recommended commands",
                        command: selectedChoice.setupCommands(config: localModelConfig)
                    )
                    HStack {
                        Button("Copy Commands") {
                            copyToPasteboard(
                                selectedChoice.setupCommands(config: localModelConfig),
                                message: "Ollama commands copied."
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Open Model Settings") {
                            onOpenSettings()
                        }
                    }

                case .llamaCpp:
                    CommandSnippetCard(
                        title: "Example server command",
                        command: selectedChoice.setupCommands(config: localModelConfig)
                    )
                    HStack {
                        Button("Copy Command") {
                            copyToPasteboard(
                                selectedChoice.setupCommands(config: localModelConfig),
                                message: "llama.cpp command copied."
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Open Model Settings") {
                            onOpenSettings()
                        }
                    }

                case .coreML:
                    if isDownloadingCoreML {
                        ProgressView("Downloading CoreML model…")
                    } else {
                        Text(isCoreMLInstalled
                             ? "A local CoreML package is already available."
                             : "Download the default CoreML package now or open model settings to use a custom source.")
                            .foregroundStyle(.secondary)
                    }

                    if let downloadError {
                        Text(downloadError)
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        Button(isCoreMLInstalled ? "Reinstall CoreML Model" : "Download CoreML Now") {
                            startCoreMLDownload()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isDownloadingCoreML)

                        Button("Open Model Settings") {
                            onOpenSettings()
                        }
                    }
                }
            }
        }
    }

    private func startCoreMLDownload() {
        isDownloadingCoreML = true
        downloadError = nil
        Task { @MainActor in
            do {
                try await onDownloadCoreML()
                isDownloadingCoreML = false
                isCoreMLInstalled = true
            } catch {
                isDownloadingCoreML = false
                downloadError = error.localizedDescription
            }
        }
    }

    private func copyToPasteboard(_ string: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        copyFeedback = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copyFeedback == message {
                copyFeedback = nil
            }
        }
    }

    private func moveForward() {
        let steps = displayedSteps
        guard let currentIndex = steps.firstIndex(of: currentStep), currentIndex < steps.count - 1 else {
            return
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            step = steps[currentIndex + 1]
        }
    }

    private func moveBackward() {
        let steps = displayedSteps
        guard let currentIndex = steps.firstIndex(of: currentStep), currentIndex > 0 else {
            return
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            step = steps[currentIndex - 1]
        }
    }
}

private struct PermissionDetailRow: View {
    let systemImage: String
    let title: String
    let description: String
    let ready: Bool
    let primaryAction: (String, () -> Void)
    let secondaryAction: (String, () -> Void)

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Status icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ready ? Color.green.opacity(0.12) : Color.orange.opacity(0.10))
                    .frame(width: 44, height: 44)
                Image(systemName: ready ? "checkmark.shield.fill" : systemImage)
                    .font(.system(size: 20))
                    .foregroundStyle(ready ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text(ready ? "Granted" : "Required")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(ready ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                        )
                        .foregroundStyle(ready ? .green : .orange)
                }

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !ready {
                    HStack(spacing: 8) {
                        Button(primaryAction.0, action: primaryAction.1)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button(secondaryAction.0, action: secondaryAction.1)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            ready ? Color.green.opacity(0.2) : Color(nsColor: .separatorColor),
                            lineWidth: 1
                        )
                )
        )
    }
}

private struct OnboardingChoiceCard: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.blue : Color.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selected ? Color.blue : Color(nsColor: .separatorColor), lineWidth: selected ? 1.5 : 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SetupStatusBadge: View {
    let title: String
    let isReady: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isReady ? Color.green.opacity(0.16) : Color.orange.opacity(0.16))
            )
            .foregroundStyle(isReady ? Color.green : Color.orange)
    }
}

private struct CommandSnippetCard: View {
    let title: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(command)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .underPageBackgroundColor))
                )
        }
    }
}

private struct SuggestionPreviewCard: View {
    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("How suggestions appear", systemImage: "text.cursor")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 10) {
                    Text("When AutoSuggest has a completion, the suggested text appears inline and stays visually separate from what you already typed.")
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("Thanks for the")
                            .font(.title3.weight(.medium))
                        Text(" quick update")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .underPageBackgroundColor))
                    )

                    HStack(spacing: 10) {
                        KeycapView(label: "Tab", accentColor: .blue, highlighted: true)
                        Text("to accept the highlighted completion")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct ShortcutHighlightRow: View {
    let title: String
    let subtitle: String
    let keycaps: [String]
    let accentColor: Color
    let highlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                ForEach(keycaps, id: \.self) { keycap in
                    KeycapView(label: keycap, accentColor: accentColor, highlighted: highlighted)
                }
            }
        }
    }
}

private struct ShortcutActionCard: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct KeycapView: View {
    let label: String
    let accentColor: Color
    let highlighted: Bool

    var body: some View {
        Text(label)
            .font(.system(.body, design: .rounded).weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentColor.opacity(highlighted ? 0.16 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(accentColor.opacity(highlighted ? 0.35 : 0.25), lineWidth: 1)
                    )
            )
            .foregroundStyle(highlighted ? accentColor : .primary)
    }
}

private extension OnboardingModelChoice {
    var displayTitle: String {
        switch self {
        case .ollama:
            return "Ollama"
        case .llamaCpp:
            return "llama.cpp"
        case .coreML:
            return "CoreML"
        }
    }

    var systemImage: String {
        switch self {
        case .ollama:
            return "shippingbox"
        case .llamaCpp:
            return "server.rack"
        case .coreML:
            return "cube.transparent"
        }
    }

    var setupTitle: String {
        switch self {
        case .ollama:
            return "Set up Ollama"
        case .llamaCpp:
            return "Set up llama.cpp"
        case .coreML:
            return "Set up CoreML"
        }
    }

    func setupSummary(config: LocalModelConfig) -> String {
        switch self {
        case .ollama:
            return "AutoSuggest will use \(config.ollama.modelName) from \(config.ollama.baseURL) once the Ollama service is running."
        case .llamaCpp:
            return "Point AutoSuggest at a running llama.cpp server on \(config.llamaCpp.baseURL) and keep your GGUF model loaded there."
        case .coreML:
            return "AutoSuggest can download the default CoreML package or use a custom local source from Settings."
        }
    }

    func setupCommands(config: LocalModelConfig) -> String {
        switch self {
        case .ollama:
            return "ollama serve\nollama pull \(config.ollama.modelName)"
        case .llamaCpp:
            return "llama-server -m /path/to/model.gguf --port 8080"
        case .coreML:
            return "CoreML setup happens inside AutoSuggest."
        }
    }

    func isReady(config: LocalModelConfig, isCoreMLInstalled: Bool) -> Bool {
        switch self {
        case .ollama:
            return isProcessRunning("ollama")
        case .llamaCpp:
            return isProcessRunning("llama-server") || isProcessRunning("llama.cpp")
        case .coreML:
            return isCoreMLInstalled || config.isModelPresent
        }
    }

    func finishSummary(config: LocalModelConfig) -> String {
        switch self {
        case .ollama:
            return "Keep \(config.ollama.modelName) available in Ollama and AutoSuggest will prefer that path first."
        case .llamaCpp:
            return "Keep your llama.cpp server running on \(config.llamaCpp.baseURL) when you want suggestions."
        case .coreML:
            return "AutoSuggest will use the local CoreML package you downloaded or configured in Settings."
        }
    }

    private func isProcessRunning(_ processName: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", processName]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
