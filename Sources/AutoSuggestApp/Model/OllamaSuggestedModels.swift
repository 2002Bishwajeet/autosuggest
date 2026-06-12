import Foundation

struct OllamaSuggestedModel: Equatable, Identifiable {
    var id: String {
        name
    }

    let name: String
    let sizeGB: Double
    let blurb: String
}

enum OllamaSuggestedModels {
    /// Fast, NON-"thinking" models first. Reasoning models (qwen3) emit a
    /// `<think>` block before answering — seconds of latency, a poor fit for
    /// inline autocomplete — so they're listed last with a clear warning.
    static let all: [OllamaSuggestedModel] = [
        .init(
            name: "qwen2.5-coder:1.5b",
            sizeGB: 0.99,
            blurb: "Best for code autocomplete — fast, no \"thinking\" delay (default)"
        ),
        .init(name: "qwen2.5-coder:0.5b", sizeGB: 0.40, blurb: "Smallest, fastest code model"),
        .init(name: "qwen2.5:0.5b", sizeGB: 0.40, blurb: "Smallest general-purpose model"),
        .init(name: "llama3.2:1b", sizeGB: 1.30, blurb: "Tiny general-purpose alternative"),
        .init(name: "qwen3:1.7b", sizeGB: 1.36, blurb: "Newest Qwen, but a reasoning model — slower for autocomplete"),
    ]
}
