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

    // MARK: - 常量

    /// 最大序列长度（含特殊 token）
    let contextLength: Int = 52

    /// 特殊 token ID
    enum SpecialToken {
        static let cls: Int = 101    // [CLS]
        static let sep: Int = 102    // [SEP]
        static let pad: Int = 0      // [PAD]
        static let unk: Int = 100    // [UNK]
    }

    // MARK: - 内部状态

    /// 词表：token string → token id
    private let vocab: [String: Int]

    /// 反向词表：token id → token string（调试用）
    private let idToToken: [Int: String]

    // MARK: - 初始化

    /// 从 vocab.txt 文件初始化
    ///
    /// - Parameter vocabPath: vocab.txt 的文件路径
    init(vocabPath: String) throws {
        Logger.model.info("加载词表: \(vocabPath)")

        let content = try String(contentsOfFile: vocabPath, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        var vocab: [String: Int] = [:]
        var idToToken: [Int: String] = [:]
        for (index, token) in lines.enumerated() {
            vocab[token] = index
            idToToken[index] = token
        }

        self.vocab = vocab
        self.idToToken = idToToken

        Logger.model.info("词表加载完成，共 \(vocab.count) 个 token")
    }

    // MARK: - 编码

    /// 将文本编码为固定长度的 token id 数组
    ///
    /// - Parameter text: 原始文本
    /// - Returns: 长度为 contextLength (52) 的 Int 数组
    func encode(_ text: String) -> [Int] {

        // Step 1: BasicTokenizer — 分词
        let tokens = basicTokenize(text)

        // Step 2: WordpieceTokenizer — 子词切分
        var wordpieceIds: [Int] = []
        for token in tokens {
            let subIds = wordpieceTokenize(token)
            wordpieceIds.append(contentsOf: subIds)
        }

        // Step 3: 拼接特殊 token 并截断
        let maxContentLength = contextLength - 2  // 留出 [CLS] 和 [SEP] 的位置
        let truncated = Array(wordpieceIds.prefix(maxContentLength))

        var result = [SpecialToken.cls] + truncated + [SpecialToken.sep]

        // Step 4: PAD 填充到 contextLength
        while result.count < contextLength {
            result.append(SpecialToken.pad)
        }

        return result
    }

    // MARK: - BasicTokenizer

    /// 基础分词：中文逐字拆分 + 小写 + 去音标 + 标点切分
    ///
    /// 对应 Python 端 bert_tokenizer.py 的 BasicTokenizer
    private func basicTokenize(_ text: String) -> [String] {
        // TODO: Phase1 完整实现
        // 1. 清理空白字符
        // 2. 中文字符前后加空格（CJK Unified Ideographs）
        // 3. 转小写
        // 4. 去除 Unicode 音标（accent stripping）
        // 5. 按空白和标点切分

        // 临时简化实现：按空格切分 + 小写
        return text.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
    }

    // MARK: - WordpieceTokenizer

    /// WordPiece 子词切分
    ///
    /// 对应 Python 端 bert_tokenizer.py 的 WordpieceTokenizer
    private func wordpieceTokenize(_ token: String) -> [Int] {
        // TODO: Phase1 完整实现
        // 1. 尝试在词表中查找完整 token
        // 2. 如果找不到，用 ## 前缀逐步缩短匹配
        // 3. 完全无法匹配的部分映射为 [UNK]

        if let id = vocab[token] {
            return [id]
        }
        return [SpecialToken.unk]
    }
}
