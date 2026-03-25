import Foundation

@MainActor
final class TypingPipeline {
    private let logger = Logger(scope: "TypingPipeline")
    private let inputMonitor: InputMonitor
    private let shortcutMonitor: SuggestionShortcutMonitor
    private let contextProvider: TextContextProvider
    private let suggestionOrchestrator: SuggestionOrchestrator
    private let overlayRenderer: OverlayRenderer
    private let insertionEngine: TextInsertionEngine
    private let metricsCollector: MetricsCollector
    private let telemetryManager: TelemetryManager
    private let personalizationEngine: PersonalizationEngine
    private let accessibilityAnnouncer: AccessibilityAnnouncer
    private let inputMethodMonitor = InputMethodMonitor()
    private let batteryMonitor = BatteryMonitor()
    private let batteryMode: BatteryMode
    private var currentContext: TextContext?
    private var activeSuggestion: SuggestionCandidate?
    private var highestPresentedRequestID = 0

    init(
        inputMonitor: InputMonitor,
        shortcutMonitor: SuggestionShortcutMonitor,
        contextProvider: TextContextProvider,
        suggestionOrchestrator: SuggestionOrchestrator,
        overlayRenderer: OverlayRenderer,
        insertionEngine: TextInsertionEngine,
        metricsCollector: MetricsCollector,
        telemetryManager: TelemetryManager,
        personalizationEngine: PersonalizationEngine,
        accessibilityAnnouncer: AccessibilityAnnouncer,
        batteryMode: BatteryMode
    ) {
        self.inputMonitor = inputMonitor
        self.shortcutMonitor = shortcutMonitor
        self.contextProvider = contextProvider
        self.suggestionOrchestrator = suggestionOrchestrator
        self.overlayRenderer = overlayRenderer
        self.insertionEngine = insertionEngine
        self.metricsCollector = metricsCollector
        self.telemetryManager = telemetryManager
        self.personalizationEngine = personalizationEngine
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.batteryMode = batteryMode

        suggestionOrchestrator.onSuggestion = { [weak self] candidate in
            self?.presentSuggestion(candidate)
        }
        suggestionOrchestrator.onClearSuggestion = { [weak self] in
            self?.clearSuggestion()
        }
        suggestionOrchestrator.onError = { [weak self] in
            Task {
                await self?.metricsCollector.recordSuggestionError()
                await self?.telemetryManager.record(event: "suggestion_error", payload: [:])
            }
        }
    }

    func start() {
        inputMonitor.start { [weak self] _ in
            Task { @MainActor in
                self?.handleInputEvent()
            }
        }
        shortcutMonitor.start { [weak self] command in
            self?.handleShortcut(command) ?? false
        }
        logger.info("Typing pipeline started.")
    }

    func stop() {
        inputMonitor.stop()
        shortcutMonitor.stop()
        clearSuggestion()
        logger.info("Typing pipeline stopped.")
    }

    private func handleInputEvent() {
        guard let context = contextProvider.currentContext() else { return }
        if inputMethodMonitor.isIMEActive() {
            clearSuggestion()
            return
        }
        if batteryMonitor.shouldPauseSuggestions(mode: batteryMode) {
            clearSuggestion()
            return
        }

        if let activeSuggestion, activeSuggestion.sourceContext != context.textBeforeCaret {
            if let adjusted = adjustSuggestionForSmartContinuation(activeSuggestion: activeSuggestion, newContext: context.textBeforeCaret) {
                presentSuggestion(adjusted)
            } else {
                clearSuggestion()
            }
        }
        if let activeSuggestion, !isSuggestion(activeSuggestion, validFor: context) {
            clearSuggestion()
        }
        currentContext = context
        if context.textBeforeCaret.isEmpty {
            clearSuggestion()
            return
        }
        suggestionOrchestrator.scheduleSuggestion(
            context: context.textBeforeCaret,
            policyContext: context.policyContext
        )
    }

    private func presentSuggestion(_ candidate: SuggestionCandidate) {
        if candidate.requestID < highestPresentedRequestID {
            return
        }
        if let context = currentContext, !isSuggestion(candidate, validFor: context) {
            return
        }
        highestPresentedRequestID = max(highestPresentedRequestID, candidate.requestID)
        activeSuggestion = candidate
        let caretRect = currentContext?.caretRectInScreen
        overlayRenderer.showSuggestion(candidate.completion, caretRectInScreen: caretRect)
        accessibilityAnnouncer.announceSuggestion(candidate.completion)
        Task {
            await metricsCollector.recordSuggestionShown(latencyMs: candidate.latencyMs)
            await telemetryManager.record(
                event: "suggestion_shown",
                payload: [
                    "confidence": String(format: "%.2f", candidate.confidence),
                    "latency_ms": candidate.latencyMs.map { String(format: "%.0f", $0) } ?? "",
                ]
            )
        }
    }

    private func clearSuggestion() {
        activeSuggestion = nil
        overlayRenderer.hideSuggestion()
    }

    private func handleShortcut(_ command: SuggestionCommand) -> Bool {
        guard let activeSuggestion else { return false }
        if let latestContext = contextProvider.currentContext(),
           !isSuggestion(activeSuggestion, validFor: latestContext) {
            clearSuggestion()
            return false
        }

        switch command {
        case .accept:
            let inserted = insertionEngine.insertSuggestion(activeSuggestion.completion)
            if !inserted {
                logger.warn("Suggestion insertion failed.")
                Task {
                    await metricsCollector.recordInsertionFailure()
                    await telemetryManager.record(event: "insertion_failed", payload: [:])
                }
            } else {
                Task {
                    await metricsCollector.recordSuggestionAccepted()
                    await personalizationEngine.recordAcceptedSuggestion(activeSuggestion.completion)
                    await telemetryManager.record(
                        event: "suggestion_accepted",
                        payload: ["completion": activeSuggestion.completion]
                    )
                }
            }
            clearSuggestion()
            return true
        case .dismiss:
            Task {
                await metricsCollector.recordSuggestionDismissed()
                await telemetryManager.record(event: "suggestion_dismissed", payload: [:])
            }
            clearSuggestion()
            return true
        }
    }

    private func adjustSuggestionForSmartContinuation(
        activeSuggestion: SuggestionCandidate,
        newContext: String
    ) -> SuggestionCandidate? {
        guard newContext.hasPrefix(activeSuggestion.sourceContext) else { return nil }
        let typedDelta = String(newContext.dropFirst(activeSuggestion.sourceContext.count))
        guard !typedDelta.isEmpty else { return activeSuggestion }
        guard activeSuggestion.completion.hasPrefix(typedDelta) else { return nil }
        let remaining = String(activeSuggestion.completion.dropFirst(typedDelta.count))
        guard !remaining.isEmpty else { return nil }
        return SuggestionCandidate(
            requestID: activeSuggestion.requestID,
            completion: remaining,
            confidence: activeSuggestion.confidence,
            sourceContext: newContext,
            sourceBundleID: activeSuggestion.sourceBundleID,
            sourceWindowTitle: activeSuggestion.sourceWindowTitle,
            latencyMs: activeSuggestion.latencyMs
        )
    }

    private func isSuggestion(_ suggestion: SuggestionCandidate, validFor context: TextContext) -> Bool {
        if context.policyContext.bundleID != suggestion.sourceBundleID {
            return false
        }
        let sourceTitle = suggestion.sourceWindowTitle ?? ""
        let currentTitle = context.policyContext.windowTitle ?? ""
        if !sourceTitle.isEmpty || !currentTitle.isEmpty {
            if sourceTitle != currentTitle {
                return false
            }
        }
        if !context.textBeforeCaret.hasPrefix(suggestion.sourceContext) &&
            !suggestion.sourceContext.hasPrefix(context.textBeforeCaret) {
            return false
        }
        return true
    }
}
