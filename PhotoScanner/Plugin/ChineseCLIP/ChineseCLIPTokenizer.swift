//
// ChineseCLIPTokenizer.swift
// PhotoScanner
//
// Bert WordPiece Tokenizer for Chinese-CLIP。
// 必须与 Python 端 cn_clip/clip/bert_tokenizer.py 逐步对齐。
//
// 编码格式：[CLS] + tokens[:50] + [SEP] + [PAD]...
// 输出长度固定为 context_length (52)
//
// ⚠️ Tokenizer 一致性是结果准确性的最大风险点。
//    实现后必须用 Python 参考输出做 golden test。
//

import Foundation
import OSLog

// MARK: - ChineseCLIPTokenizer

final class ChineseCLIPTokenizer: Sendable {

    // MARK: - 特殊 token

    enum SpecialToken {
        nonisolated static let pad = "[PAD]"
        nonisolated static let unk = "[UNK]"
        nonisolated static let cls = "[CLS]"
        nonisolated static let sep = "[SEP]"
    }

    // MARK: - 常量

    /// 最大序列长度（含特殊 token）
    nonisolated let contextLength: Int

    /// WordPiece 单词最大字符数
    private nonisolated let maxInputCharactersPerWord: Int = 200

    /// 是否执行 lowercase，与 Python 默认行为保持一致
    private nonisolated let doLowerCase: Bool

    // MARK: - 内部状态

    /// 词表：token string → token id
    private nonisolated let vocab: [String: Int]

    /// 反向词表：token id → token string（调试用）
    private nonisolated let idToToken: [Int: String]

    /// 特殊 token id
    private nonisolated let padTokenID: Int
    private nonisolated let unkTokenID: Int
    private nonisolated let clsTokenID: Int
    private nonisolated let sepTokenID: Int

    // MARK: - 初始化

    /// 从 vocab.txt 文件初始化
    ///
    /// - Parameters:
    ///   - vocabPath: vocab.txt 的文件路径
    ///   - contextLength: 固定输出长度，Chinese-CLIP 为 52
    ///   - doLowerCase: 是否小写化，Chinese-CLIP 默认 true
    nonisolated init(
        vocabPath: String,
        contextLength: Int = ChineseCLIPPlugin.contextLength,
        doLowerCase: Bool = true
    ) throws {
        Logger.model.info("加载词表: \(vocabPath)")

        let content = try String(contentsOfFile: vocabPath, encoding: .utf8)
        let lines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
            .filter { !$0.isEmpty }

        var vocab: [String: Int] = [:]
        var idToToken: [Int: String] = [:]
        for (index, token) in lines.enumerated() {
            vocab[token] = index
            idToToken[index] = token
        }

        self.contextLength = contextLength
        self.doLowerCase = doLowerCase
        self.vocab = vocab
        self.idToToken = idToToken
        self.padTokenID = vocab[SpecialToken.pad] ?? 0
        self.unkTokenID = vocab[SpecialToken.unk] ?? 100
        self.clsTokenID = vocab[SpecialToken.cls] ?? 101
        self.sepTokenID = vocab[SpecialToken.sep] ?? 102

        guard vocab[SpecialToken.pad] != nil,
              vocab[SpecialToken.unk] != nil,
              vocab[SpecialToken.cls] != nil,
              vocab[SpecialToken.sep] != nil else {
            throw PSError.invalidInput("词表缺少必要特殊 token")
        }

        Logger.model.info("词表加载完成，共 \(vocab.count) 个 token")
    }

    // MARK: - 编码

    /// 将文本编码为固定长度的 token id 数组
    ///
    /// - Parameter text: 原始文本
    /// - Returns: 长度为 contextLength 的 Int 数组
    nonisolated func encode(_ text: String) -> [Int] {
        let wordpieceTokens = tokenize(text)
        let tokenIDs = wordpieceTokens.map { vocab[$0] ?? unkTokenID }

        let maxContentLength = contextLength - 2
        let truncated = Array(tokenIDs.prefix(maxContentLength))

        var result = [clsTokenID] + truncated + [sepTokenID]
        while result.count < contextLength {
            result.append(padTokenID)
        }

        return result
    }

    /// 与 ONNX 输入对齐的 Int64 版本
    nonisolated func encodeToInt64(_ text: String) -> [Int64] {
        encode(text).map(Int64.init)
    }

    /// 仅用于调试：返回 WordPiece token 字符串
    nonisolated func tokenize(_ text: String) -> [String] {
        var splitTokens: [String] = []
        for token in basicTokenize(text) {
            splitTokens.append(contentsOf: wordpieceTokenize(token))
        }
        return splitTokens
    }

    // MARK: - 调试

    nonisolated func tokenString(for id: Int) -> String? {
        idToToken[id]
    }

    // MARK: - BasicTokenizer

    /// 基础分词：清理控制字符 → 中文逐字拆分 → lowercase → 去音标 → 标点切分
    private nonisolated func basicTokenize(_ text: String) -> [String] {
        let cleaned = cleanText(text)
        let chineseSpaced = tokenizeChineseCharacters(in: cleaned)
        let originalTokens = whitespaceTokenize(chineseSpaced)

        var splitTokens: [String] = []
        for originalToken in originalTokens {
            let normalizedToken: String
            if doLowerCase {
                normalizedToken = stripAccents(from: originalToken.lowercased())
            } else {
                normalizedToken = originalToken
            }
            splitTokens.append(contentsOf: splitOnPunctuation(normalizedToken))
        }

        return whitespaceTokenize(splitTokens.joined(separator: " "))
    }

    private nonisolated func cleanText(_ text: String) -> String {
        var output = String.UnicodeScalarView()
        output.reserveCapacity(text.unicodeScalars.count)

        for scalar in text.unicodeScalars {
            let codePoint = scalar.value
            if codePoint == 0 || codePoint == 0xFFFD || isControl(scalar) {
                continue
            }

            if isWhitespace(scalar) {
                output.append(" ")
            } else {
                output.append(scalar)
            }
        }

        return String(output)
    }

    private nonisolated func tokenizeChineseCharacters(in text: String) -> String {
        var output = String.UnicodeScalarView()
        output.reserveCapacity(text.unicodeScalars.count * 3)

        for scalar in text.unicodeScalars {
            if isChineseCharacter(scalar.value) {
                output.append(" ")
                output.append(scalar)
                output.append(" ")
            } else {
                output.append(scalar)
            }
        }

        return String(output)
    }

    private nonisolated func stripAccents(from text: String) -> String {
        let decomposed = text.decomposedStringWithCanonicalMapping
        let filteredScalars = decomposed.unicodeScalars.filter {
            $0.properties.generalCategory != .nonspacingMark
        }
        return String(String.UnicodeScalarView(filteredScalars))
    }

    private nonisolated func splitOnPunctuation(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let characters = Array(text)
        var output: [[Character]] = []
        var startNewWord = true

        for character in characters {
            if isPunctuation(character) {
                output.append([character])
                startNewWord = true
            } else {
                if startNewWord {
                    output.append([])
                }
                startNewWord = false
                output[output.count - 1].append(character)
            }
        }

        return output.map { String($0) }
    }

    // MARK: - WordPieceTokenizer

    private nonisolated func wordpieceTokenize(_ token: String) -> [String] {
        let tokenCharacters = Array(token)
        if tokenCharacters.count > maxInputCharactersPerWord {
            return [SpecialToken.unk]
        }

        var start = 0
        var subTokens: [String] = []

        while start < tokenCharacters.count {
            var end = tokenCharacters.count
            var currentSubToken: String?

            while start < end {
                var substring = String(tokenCharacters[start..<end])
                if start > 0 {
                    substring = "##" + substring
                }

                if vocab[substring] != nil {
                    currentSubToken = substring
                    break
                }
                end -= 1
            }

            guard let currentSubToken else {
                return [SpecialToken.unk]
            }

            subTokens.append(currentSubToken)
            start = end
        }

        return subTokens
    }

    // MARK: - Unicode helpers

    private nonisolated func whitespaceTokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private nonisolated func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" {
            return true
        }
        return scalar.properties.generalCategory == .spaceSeparator
    }

    private nonisolated func isControl(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "\t" || scalar == "\n" || scalar == "\r" {
            return false
        }

        switch scalar.properties.generalCategory {
        case .control, .format:
            return true
        default:
            return false
        }
    }

    private nonisolated func isPunctuation(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        let codePoint = scalar.value

        if (33...47).contains(codePoint)
            || (58...64).contains(codePoint)
            || (91...96).contains(codePoint)
            || (123...126).contains(codePoint) {
            return true
        }

        switch scalar.properties.generalCategory {
        case .connectorPunctuation,
             .dashPunctuation,
             .openPunctuation,
             .closePunctuation,
             .initialPunctuation,
             .finalPunctuation,
             .otherPunctuation:
            return true
        default:
            return false
        }
    }

    private nonisolated func isChineseCharacter(_ codePoint: UInt32) -> Bool {
        (0x4E00...0x9FFF).contains(codePoint)
        || (0x3400...0x4DBF).contains(codePoint)
        || (0x20000...0x2A6DF).contains(codePoint)
        || (0x2A700...0x2B73F).contains(codePoint)
        || (0x2B740...0x2B81F).contains(codePoint)
        || (0x2B820...0x2CEAF).contains(codePoint)
        || (0xF900...0xFAFF).contains(codePoint)
        || (0x2F800...0x2FA1F).contains(codePoint)
    }
}
