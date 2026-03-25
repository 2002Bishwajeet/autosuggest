import CoreML
import Foundation
import Tokenizers

enum TokenizerStrategy {
    case byteLevel
    case huggingFace(URL)
}

@MainActor
final class CoreMLModelAdapter {
    private let logger = Logger(scope: "CoreMLModelAdapter")
    private var cachedModelPath: String?
    private var cachedModel: MLModel?
    private var cachedTokenizer: (any Tokenizer)?
    private var tokenizerStrategy: TokenizerStrategy = .byteLevel

    var stopTokens: Set<Int32> = [0, 2, 3]
    var maxContextTokens: Int = 512

    func invalidate() {
        cachedModelPath = nil
        cachedModel = nil
        cachedTokenizer = nil
        tokenizerStrategy = .byteLevel
        logger.info("CoreML model cache cleared.")
    }

    func generate(prompt: String, modelURL: URL, maxNewTokens: Int) throws -> String? {
        let model = try loadModelIfNeeded(at: modelURL)

        let inputNameMap = dictionaryByLowercasedKey(model.modelDescription.inputDescriptionsByName)
        let outputNameMap = dictionaryByLowercasedKey(model.modelDescription.outputDescriptionsByName)

        if let stringResult = try predictString(
            prompt: prompt,
            model: model,
            inputNameMap: inputNameMap,
            outputNameMap: outputNameMap
        ) {
            return stringResult
        }

        if let tokenResult = try predictTokens(
            prompt: prompt,
            model: model,
            inputNameMap: inputNameMap,
            outputNameMap: outputNameMap,
            maxNewTokens: maxNewTokens
        ) {
            return tokenResult
        }

        return nil
    }

    // MARK: - Tokenizer

    func loadTokenizerIfNeeded(modelURL: URL, explicitTokenizerURL: URL? = nil) async {
        if cachedTokenizer != nil { return }

        let tokenizerURL = explicitTokenizerURL ?? findTokenizerJSON(near: modelURL)
        guard let tokenizerURL else {
            tokenizerStrategy = .byteLevel
            logger.info("No tokenizer.json found, using byte-level tokenization fallback.")
            return
        }

        let folderURL = tokenizerURL.deletingLastPathComponent()

        do {
            let tokenizer = try await AutoTokenizer.from(modelFolder: folderURL)
            cachedTokenizer = tokenizer
            tokenizerStrategy = .huggingFace(tokenizerURL)

            if let eosId = tokenizer.eosTokenId {
                stopTokens.insert(Int32(eosId))
            }

            logger.info("Loaded HuggingFace tokenizer from \(tokenizerURL.path)")
        } catch {
            logger.warn("Failed to load tokenizer from \(folderURL.path): \(error.localizedDescription). Falling back to byte-level.")
            tokenizerStrategy = .byteLevel
        }
    }

    private func findTokenizerJSON(near modelURL: URL) -> URL? {
        let candidates: [URL]
        if ["mlmodelc", "mlpackage"].contains(modelURL.pathExtension.lowercased()) {
            let parentDir = modelURL.deletingLastPathComponent()
            candidates = [
                parentDir.appendingPathComponent("tokenizer.json"),
                modelURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tokenizer.json"),
            ]
        } else {
            candidates = [
                modelURL.appendingPathComponent("tokenizer.json"),
            ]
        }

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    func encodeTokens(_ text: String) -> [Int32] {
        if let tokenizer = cachedTokenizer {
            let encoded = tokenizer.encode(text: text)
            return encoded.map { Int32($0) }
        }
        return encodeByteTokens(text)
    }

    func decodeTokens(_ tokens: [Int32]) -> String {
        if let tokenizer = cachedTokenizer {
            return tokenizer.decode(tokens: tokens.map { Int($0) })
        }
        return decodeByteTokens(tokens)
    }

    func isStopToken(_ token: Int32) -> Bool {
        stopTokens.contains(token)
    }

    // MARK: - Model Loading

    private func loadModelIfNeeded(at url: URL) throws -> MLModel {
        let modelURL = try resolveModelURL(from: url)
        if cachedModelPath == modelURL.path, let cachedModel {
            return cachedModel
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        cachedModelPath = modelURL.path
        cachedModel = model
        logger.info("Loaded CoreML model from \(modelURL.path)")
        return model
    }

    func resolveModelURL(from url: URL) throws -> URL {
        if ["mlmodelc", "mlpackage"].contains(url.pathExtension.lowercased()) {
            return url
        }

        if let nested = findFirstModelArtifact(in: url) {
            return nested
        }
        return url
    }

    private func findFirstModelArtifact(in directory: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "mlmodelc" || ext == "mlpackage" {
                return fileURL
            }
        }
        return nil
    }

    // MARK: - String Prediction

    private func predictString(
        prompt: String,
        model: MLModel,
        inputNameMap: [String: String],
        outputNameMap: [String: String]
    ) throws -> String? {
        let promptInputName = firstExisting(
            ["prompt", "text", "input_text", "input"],
            in: inputNameMap
        )
        let stringOutputName = firstOutputWithType(.string, outputNameMap: outputNameMap, model: model)
        guard let promptInputName, let stringOutputName else { return nil }

        let provider = try MLDictionaryFeatureProvider(
            dictionary: [promptInputName: MLFeatureValue(string: prompt)]
        )
        let prediction = try model.prediction(from: provider)
        return prediction.featureValue(for: stringOutputName)?.stringValue
    }

    // MARK: - Token Prediction

    private func predictTokens(
        prompt: String,
        model: MLModel,
        inputNameMap: [String: String],
        outputNameMap: [String: String],
        maxNewTokens: Int
    ) throws -> String? {
        let inputIDsName = firstExisting(["input_ids", "tokens", "token_ids"], in: inputNameMap)
            ?? firstInputWithType(.multiArray, model: model)
        guard let inputIDsName else { return nil }

        let attentionMaskName = firstExisting(["attention_mask", "mask"], in: inputNameMap)
        let logitsOutputName = firstExisting(["logits", "output_logits"], in: outputNameMap)
        let generatedIDsOutputName = firstExisting(["generated_ids", "output_ids", "token_ids"], in: outputNameMap)

        var tokens = encodeTokens(prompt)
        guard !tokens.isEmpty else { return nil }
        tokens = Array(tokens.suffix(maxContextTokens))
        var generated: [Int32] = []

        for _ in 0..<maxNewTokens {
            let inputArray = try makeTokenArray(tokens)
            var features: [String: MLFeatureValue] = [
                inputIDsName: MLFeatureValue(multiArray: inputArray),
            ]
            if let attentionMaskName {
                let mask = try makeAttentionMask(count: tokens.count)
                features[attentionMaskName] = MLFeatureValue(multiArray: mask)
            }
            let provider = try MLDictionaryFeatureProvider(dictionary: features)
            let prediction = try model.prediction(from: provider)

            if let generatedIDsOutputName,
               let outputArray = prediction.featureValue(for: generatedIDsOutputName)?.multiArrayValue,
               let predictedToken = readLastToken(from: outputArray) {
                if isStopToken(predictedToken) { break }
                tokens.append(predictedToken)
                generated.append(predictedToken)
                continue
            }

            if let logitsOutputName,
               let logits = prediction.featureValue(for: logitsOutputName)?.multiArrayValue,
               let next = argmaxLastLogits(logits) {
                if isStopToken(next) { break }
                tokens.append(next)
                generated.append(next)
                continue
            }

            break
        }

        guard !generated.isEmpty else { return nil }
        let text = decodeTokens(generated)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : text
    }

    // MARK: - MLMultiArray Helpers

    private func makeTokenArray(_ tokens: [Int32]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: tokens.count)], dataType: .int32)
        for (i, token) in tokens.enumerated() {
            array[i] = NSNumber(value: token)
        }
        return array
    }

    private func makeAttentionMask(count: Int) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: count)], dataType: .int32)
        for i in 0..<count {
            array[i] = 1
        }
        return array
    }

    private func readLastToken(from array: MLMultiArray) -> Int32? {
        guard array.count > 0 else { return nil }
        let value = array[array.count - 1]
        return Int32(truncating: value)
    }

    func argmaxLastLogits(_ logits: MLMultiArray) -> Int32? {
        guard logits.count > 0 else { return nil }
        let shape = logits.shape.map { Int(truncating: $0) }
        guard let lastDim = shape.last, lastDim > 0 else { return nil }
        guard logits.count >= lastDim else { return nil }

        let base = logits.count - lastDim
        var bestIndex = 0
        var bestValue = Double.leastNormalMagnitude
        for i in 0..<lastDim {
            let value = Double(truncating: logits[base + i])
            if value > bestValue {
                bestValue = value
                bestIndex = i
            }
        }
        return Int32(bestIndex)
    }

    // MARK: - Byte-Level Fallback

    private func encodeByteTokens(_ text: String) -> [Int32] {
        text.utf8.map { Int32($0) }
    }

    private func decodeByteTokens(_ tokens: [Int32]) -> String {
        let bytes: [UInt8] = tokens.compactMap {
            guard (0...255).contains($0) else { return nil }
            return UInt8($0)
        }
        return String(data: Data(bytes), encoding: .utf8) ?? ""
    }

    // MARK: - Name Resolution Helpers

    private func dictionaryByLowercasedKey<T>(_ input: [String: T]) -> [String: String] {
        var map: [String: String] = [:]
        for key in input.keys {
            map[key.lowercased()] = key
        }
        return map
    }

    private func firstExisting(_ candidates: [String], in map: [String: String]) -> String? {
        for candidate in candidates {
            if let original = map[candidate.lowercased()] {
                return original
            }
        }
        return nil
    }

    private func firstOutputWithType(
        _ type: MLFeatureType,
        outputNameMap: [String: String],
        model: MLModel
    ) -> String? {
        for original in outputNameMap.values {
            if model.modelDescription.outputDescriptionsByName[original]?.type == type {
                return original
            }
        }
        return nil
    }

    private func firstInputWithType(_ type: MLFeatureType, model: MLModel) -> String? {
        for (name, desc) in model.modelDescription.inputDescriptionsByName where desc.type == type {
            return name
        }
        return nil
    }
}
