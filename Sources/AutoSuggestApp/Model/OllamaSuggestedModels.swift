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
    /// Latest + smallest first. Edit freely.
    static let all: [OllamaSuggestedModel] = [
        .init(name: "qwen3:0.6b", sizeGB: 0.52, blurb: "Latest Qwen, smallest — fastest general autocomplete"),
        .init(name: "qwen3:1.7b", sizeGB: 1.36, blurb: "Latest Qwen, better quality, still small (default)"),
        .init(name: "qwen2.5-coder:1.5b", sizeGB: 0.99, blurb: "Best small code model for code completion"),
        .init(name: "llama3.2:1b", sizeGB: 1.30, blurb: "Tiny general-purpose alternative"),
    ]
}
