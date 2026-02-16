import Foundation
import CoreML

/// MiniLM embedding model for semantic search
/// Uses the all-MiniLM-L6-v2 model (384-dimensional embeddings)
public actor MiniLMEmbeddings {
    private let model: MLModel
    private let tokenizer: BertTokenizer

    /// Output dimension of the embeddings
    public static let outputDimension: Int = 384

    /// Maximum input length in tokens
    public static let maxInputLength: Int = 512

    public init() throws {
        // Load the compiled Core ML model
        guard let modelURL = Bundle.notesLibBundle.url(forResource: "all-MiniLM-L6-v2", withExtension: "mlmodelc") else {
            throw MiniLMError.modelNotFound
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all  // Use CPU, GPU, and Neural Engine

        self.model = try MLModel(contentsOf: modelURL, configuration: config)
        self.tokenizer = try BertTokenizer()
    }

    /// Generate embeddings for a single text
    /// - Parameter text: Input text to embed
    /// - Returns: 384-dimensional embedding vector, or nil if encoding fails
    public func encode(_ text: String) async -> [Float]? {
        // Tokenize
        let inputTokens = tokenizer.buildModelTokens(sentence: text)
        let (inputIds, attentionMask) = tokenizer.buildModelInputs(from: inputTokens)

        // Run inference
        return generateEmbeddings(inputIds: inputIds, attentionMask: attentionMask)
    }

    /// Generate embeddings for multiple texts
    /// - Parameter texts: Array of input texts
    /// - Returns: Array of embedding vectors
    public func encodeBatch(_ texts: [String]) async -> [[Float]] {
        var embeddings: [[Float]] = []
        for text in texts {
            if let embedding = await encode(text) {
                embeddings.append(embedding)
            }
        }
        return embeddings
    }

    // MARK: - Private Methods

    private func generateEmbeddings(inputIds: MLMultiArray, attentionMask: MLMultiArray) -> [Float]? {
        do {
            // Create input features
            let inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: inputIds),
                "attention_mask": MLFeatureValue(multiArray: attentionMask)
            ])

            // Run prediction
            let output = try model.prediction(from: inputFeatures)

            // Extract embeddings from output
            guard let embeddingsValue = output.featureValue(for: "embeddings"),
                  let embeddingsArray = embeddingsValue.multiArrayValue else {
                return nil
            }

            return MLMultiArray.toFloatArray(embeddingsArray)
        } catch {
            print("MiniLM embedding error: \(error)")
            return nil
        }
    }
}

// MARK: - Cosine Similarity

extension MiniLMEmbeddings {
    /// Calculate cosine similarity between two vectors
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0
    }
}

// MARK: - Errors

public enum MiniLMError: Error, LocalizedError {
    case modelNotFound
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "MiniLM Core ML model not found. Run the compile-coreml-model GitHub Action first."
        case .encodingFailed:
            return "Failed to encode text with MiniLM model"
        }
    }
}
