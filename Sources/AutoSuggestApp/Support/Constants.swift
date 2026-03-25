import CoreGraphics
import Foundation

enum Constants {
    // MARK: - Timing

    static let debounceNanoseconds: UInt64 = 150_000_000
    static let idleUnloadSeconds: TimeInterval = 120
    static let clipboardRestoreDelay: TimeInterval = 0.05

    // MARK: - Inference

    static let maxNewTokens: Int = 24
    static let ollamaNumPredict: Int = 24
    static let llamaCppNPredict: Int = 24
    static let llamaCppTemperature: Double = 0.2
    static let defaultCoreMLMaxContextTokens: Int = 256
    static let bpeMaxContextTokens: Int = 512

    // MARK: - Overlay

    static let overlayMinWidth: CGFloat = 100
    static let overlayMaxWidth: CGFloat = 420
    static let overlayHeight: CGFloat = 32
    static let overlayCornerRadius: CGFloat = 8
    static let overlayFontSize: CGFloat = 14
    static let overlayTextPadding: CGFloat = 12

    // MARK: - Animation

    static let fadeInDuration: Double = 0.14
    static let fadeOutDuration: Double = 0.12

    // MARK: - Latency

    static let slowLatencyThresholdSeconds: Double = 0.65

    // MARK: - Key Codes

    static let commandKeyCode: UInt16 = 0x37
    static let vKeyCode: UInt16 = 0x09

    // MARK: - Confidence

    static let coreMLConfidence: Double = 0.72
    static let ollamaConfidence: Double = 0.64
    static let llamaCppDirectConfidence: Double = 0.6
    static let llamaCppOpenAIConfidence: Double = 0.58

    // MARK: - Personalization

    static let maxNormalizedCompletionLength: Int = 120

    // MARK: - Network

    static let defaultOllamaBaseURL = "http://127.0.0.1:11434"
    static let defaultLlamaCppBaseURL = "http://127.0.0.1:8080"
    static let defaultOllamaModelName = "qwen2.5:1.5b"
}
