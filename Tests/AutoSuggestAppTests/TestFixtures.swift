import Foundation
@testable import AutoSuggestApp

enum TestFixtures {
    static var sampleAppConfig: AppConfig {
        AppConfig.default
    }

    static var sampleLocalModelConfig: LocalModelConfig {
        AppConfig.default.localModel
    }

    static var sampleModelManifest: ModelManifest {
        ModelManifest(
            modelID: "test-model",
            version: "1.0.0",
            fileName: "test-model-1.0.0.mlmodelc.zip",
            downloadURL: URL(string: "https://example.com/model.zip")!,
            sha256: "",
            signatureKeyID: nil,
            signatureEd25519Base64: nil,
            huggingFaceFolder: nil
        )
    }

    static var sampleExclusionRule: ExclusionRule {
        ExclusionRule(
            enabled: true,
            bundleID: "com.example.app",
            windowTitleContains: nil,
            contentPattern: nil
        )
    }
}
