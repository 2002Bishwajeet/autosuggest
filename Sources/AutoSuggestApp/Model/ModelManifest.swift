import Foundation

struct HuggingFaceFolderSource: Codable, Equatable {
    let repo: String
    let revision: String
    let folderPath: String
}

struct ModelManifest: Codable {
    let modelID: String
    let version: String
    let fileName: String
    let downloadURL: URL
    let sha256: String
    let signatureKeyID: String?
    let signatureEd25519Base64: String?
    let huggingFaceFolder: HuggingFaceFolderSource?
}

extension ModelManifest {
    /// Fallback manifest: OpenELM-270M CoreML from Hugging Face (spec: small 1–3B class, CoreML, Apple Silicon).
    static let initial = ModelManifest(
        modelID: "OpenELM-270M",
        version: "1.0",
        fileName: "OpenELM-270M-128-float32.mlpackage",
        downloadURL: URL(string: "https://huggingface.co/corenet-community/coreml-OpenELM-270M")!,
        sha256: "",
        signatureKeyID: nil,
        signatureEd25519Base64: nil,
        huggingFaceFolder: HuggingFaceFolderSource(
            repo: "corenet-community/coreml-OpenELM-270M",
            revision: "main",
            folderPath: "OpenELM-270M-128-float32.mlpackage"
        )
    )
}
