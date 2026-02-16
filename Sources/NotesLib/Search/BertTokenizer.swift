import Foundation
import CoreML

/// BERT tokenizer for MiniLM model
/// Adapted from SimilaritySearchKit (MIT License)
/// https://github.com/ZachNagengast/similarity-search-kit
public class BertTokenizer {
    private let basicTokenizer = BasicTokenizer()
    private let wordpieceTokenizer: WordpieceTokenizer
    private let maxLen = 512

    private let vocab: [String: Int]
    private let idsToTokens: [Int: String]

    public init() throws {
        guard let url = Bundle.notesLibBundle.url(forResource: "bert_tokenizer_vocab", withExtension: "txt") else {
            throw TokenizerError.vocabFileNotFound
        }
        let vocabTxt = try String(contentsOf: url)
        let tokens = vocabTxt.split(separator: "\n").map { String($0) }

        var vocab: [String: Int] = [:]
        var idsToTokens: [Int: String] = [:]
        for (i, token) in tokens.enumerated() {
            vocab[token] = i
            idsToTokens[i] = token
        }

        self.vocab = vocab
        self.idsToTokens = idsToTokens
        self.wordpieceTokenizer = WordpieceTokenizer(vocab: self.vocab)
    }

    /// Build model input tokens from a sentence
    public func buildModelTokens(sentence: String) -> [Int] {
        var tokens = tokenizeToIds(text: sentence)

        let clsSepTokenCount = 2 // Account for [CLS] and [SEP] tokens

        if tokens.count + clsSepTokenCount > maxLen {
            tokens = Array(tokens[..<(maxLen - clsSepTokenCount)])
        }

        let paddingCount = maxLen - tokens.count - clsSepTokenCount

        let inputTokens: [Int] = [
            tokenToId(token: "[CLS]"),
        ] + tokens + [
            tokenToId(token: "[SEP]"),
        ] + Array(repeating: 0, count: paddingCount)

        return inputTokens
    }

    /// Build MLMultiArray inputs for the model
    public func buildModelInputs(from inputTokens: [Int]) -> (inputIds: MLMultiArray, attentionMask: MLMultiArray) {
        let inputIds = MLMultiArray.from(inputTokens, dims: 2)
        let maskValue = 1

        let attentionMaskValues: [Int] = inputTokens.map { token in
            token == 0 ? 0 : maskValue
        }

        let attentionMask = MLMultiArray.from(attentionMaskValues, dims: 2)

        return (inputIds, attentionMask)
    }

    // MARK: - Private Methods

    private func tokenize(text: String) -> [String] {
        var tokens: [String] = []
        for token in basicTokenizer.tokenize(text: text) {
            for subToken in wordpieceTokenizer.tokenize(word: token) {
                tokens.append(subToken)
            }
        }
        return tokens
    }

    private func convertTokensToIds(tokens: [String]) -> [Int] {
        return tokens.compactMap { vocab[$0] }
    }

    private func tokenizeToIds(text: String) -> [Int] {
        return convertTokensToIds(tokens: tokenize(text: text))
    }

    private func tokenToId(token: String) -> Int {
        return vocab[token] ?? 0
    }
}

// MARK: - BasicTokenizer

private class BasicTokenizer {
    private let neverSplit = ["[UNK]", "[SEP]", "[PAD]", "[CLS]", "[MASK]"]

    func tokenize(text: String) -> [String] {
        let foldedText = text.folding(options: .diacriticInsensitive, locale: nil)
        let splitTokens = foldedText.components(separatedBy: NSCharacterSet.whitespaces)

        let tokens: [String] = splitTokens.flatMap { token -> [String] in
            if neverSplit.contains(token) {
                return [token]
            }

            var tokenFragments: [String] = []
            var currentFragment = ""

            for character in token.lowercased() {
                if character.isLetter || character.isNumber || character == "°" {
                    currentFragment.append(character)
                } else if !currentFragment.isEmpty {
                    tokenFragments.append(currentFragment)
                    tokenFragments.append(String(character))
                    currentFragment = ""
                } else {
                    tokenFragments.append(String(character))
                }
            }

            if !currentFragment.isEmpty {
                tokenFragments.append(currentFragment)
            }

            return tokenFragments
        }

        return tokens
    }
}

// MARK: - WordpieceTokenizer

private class WordpieceTokenizer {
    private let unkToken = "[UNK]"
    private let maxInputCharsPerWord = 100
    private let vocab: [String: Int]

    init(vocab: [String: Int]) {
        self.vocab = vocab
    }

    func tokenize(word: String) -> [String] {
        if word.count > maxInputCharsPerWord {
            return [unkToken]
        }

        var outputTokens: [String] = []
        var isBad = false
        var start = 0
        var subTokens: [String] = []

        while start < word.count {
            var end = word.count
            var currentSubstring: String?

            while start < end {
                var substring = String(word[word.index(word.startIndex, offsetBy: start)..<word.index(word.startIndex, offsetBy: end)])
                if start > 0 {
                    substring = "##\(substring)"
                }

                if vocab[substring] != nil {
                    currentSubstring = substring
                    break
                }

                end -= 1
            }

            if currentSubstring == nil {
                isBad = true
                break
            }

            subTokens.append(currentSubstring!)
            start = end
        }

        if isBad {
            outputTokens.append(unkToken)
        } else {
            outputTokens.append(contentsOf: subTokens)
        }

        return outputTokens
    }
}

// MARK: - MLMultiArray Extension

extension MLMultiArray {
    /// Create MLMultiArray from Int array
    static func from(_ arr: [Int], dims: Int = 1) -> MLMultiArray {
        var shape = Array(repeating: 1, count: dims)
        shape[shape.count - 1] = arr.count

        let output = try! MLMultiArray(shape: shape as [NSNumber], dataType: .int32)
        let ptr = UnsafeMutablePointer<Int32>(OpaquePointer(output.dataPointer))
        for (i, item) in arr.enumerated() {
            ptr[i] = Int32(item)
        }
        return output
    }

    /// Convert MLMultiArray to Float array
    static func toFloatArray(_ o: MLMultiArray) -> [Float] {
        var arr: [Float] = Array(repeating: 0, count: o.count)
        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(o.dataPointer))
        for i in 0..<o.count {
            arr[i] = Float(ptr[i])
        }
        return arr
    }
}

// MARK: - Errors

public enum TokenizerError: Error, LocalizedError {
    case vocabFileNotFound

    public var errorDescription: String? {
        switch self {
        case .vocabFileNotFound:
            return "BERT tokenizer vocab file not found in bundle"
        }
    }
}
