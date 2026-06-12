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
    @State private var ollamaRunning = false
    @State private var llamaRunning = false
    @State private var permissionsReady = false
    @State private var copyFeedback: String?
    // Tracks whether Input Monitoring went from denied → granted this session,
    // which requires a relaunch before the CGEvent tap can be installed.
    @State private var inputMonitoringJustGranted = false
    @State private var prevInputMonitoringState = false

    private let logger = Logger(scope: "OnboardingFlowView")

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
        .onAppear { refreshPermissionState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Refresh the moment the app regains focus — e.g. when the user
            // returns from System Settings after toggling a permission — so the
            // wizard advances instantly instead of lagging behind a poll.
            refreshPermissionState()
        }
    }

    /// Recomputes permission-readiness from the live `PermissionManager` state.
    /// Driven by `.onAppear` and `NSApplication.didBecomeActiveNotification`
    /// (focus return) rather than an always-on timer.
    private func refreshPermissionState() {
        permissionsReady = permissionManager.isAccessibilityTrusted() && permissionManager
            .hasInputMonitoringPermission()

        // Detect Input Monitoring transitioning from denied → granted.
        // CGEvent tap installation requires a process restart, so we warn the
        // user immediately when this happens.
        let current = permissionManager.hasInputMonitoringPermission()
        if current && !prevInputMonitoringState {
            inputMonitoringJustGranted = true
            logger.info("Input Monitoring granted during onboarding; relaunch required")
        }
        prevInputMonitoringState = current
    }

    private var stepTitle: String {
        switch currentStep {
        case .welcome:
            "Welcome to AutoSuggest"
        case .permissions:
            "Grant Permissions"
        case .model:
            "Choose a Model Path"
        case .finish:
            "First Use"
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
                            Text(
                                "Accessibility and Input Monitoring are already enabled, so onboarding will skip the permission step."
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "AutoSuggest stays lightweight in the menu bar and keeps advanced controls in a dedicated settings window."
                    )
                    Text(
                        "Suggestions appear inline, accept with Tab or Enter, dismiss with Esc, and exclusions keep it out of editors and other sensitive contexts."
                    )
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
                        Text(
                            "Input Monitoring was granted. AutoSuggest must relaunch before it can intercept keystrokes."
                        )
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
        .task {
            await refreshRuntimeReadiness()
        }
    }

    private func refreshRuntimeReadiness() async {
        async let ollama = RuntimeDetectionService.live.status(for: .ollama)
        async let llama = RuntimeDetectionService.live.status(for: .llamaServer)
        ollamaRunning = await ollama == .running
        llamaRunning = await llama == .running
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
                        accentColor: AutoSuggestTheme.brand,
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
                        Text(
                            "Open Settings any time to manage models, permissions, exclusions, accessibility, and diagnostics."
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

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
                            isCoreMLInstalled: isCoreMLInstalled,
                            ollamaRunning: ollamaRunning,
                            llamaRunning: llamaRunning
                        ) ? "Ready" : "Needs setup",
                        isReady: selectedChoice.isReady(
                            config: localModelConfig,
                            isCoreMLInstalled: isCoreMLInstalled,
                            ollamaRunning: ollamaRunning,
                            llamaRunning: llamaRunning
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
