import Foundation

// MARK: - SimilarityScore Value Object

/// 相似度分数值对象
///
/// 封装相似度计算结果，提供类型安全和语义化操作。
/// 
/// ## 设计背景
/// CLIP 模型的余弦相似度范围是 [-1, 1]，但用户更习惯 [0, 1] 的百分比形式。
/// 此外，检索排序需要对微小差异敏感，而图图对比需要直观展示。
///
/// ## 两种映射模式
/// 1. **图文检索** (`from(cosine:)`)：高斜率 Sigmoid，放大差异便于排序
/// 2. **图图对比** (`fromImageComparison(cosine:)`)：温和刻度，直观展示相似度
///
/// ## 使用示例
/// ```swift
/// let score = SimilarityScore.from(cosine: 0.85, config: config)
/// print(score.value)  // 0.95 (图文检索)
/// 
/// let imageScore = SimilarityScore.fromImageComparison(cosine: 0.85, config: config)
/// print(imageScore.value)  // 0.75 (图图对比)
/// ```
struct SimilarityScore: Sendable, Equatable, Comparable, Codable {
    
    // MARK: - Properties
    
    /// 原始分数 [0, 1]
    let value: Float
    
    // MARK: - Initialization
    
    /// 创建相似度分数
    /// - Parameter value: 原始值，会被 clamp 到 [0, 1]
    init(_ value: Float) {
        self.value = max(0, min(1, value))  // Clamp to [0, 1]
    }
    
    /// 从余弦相似度计算（用于图文检索）
    ///
    /// 使用配置的相似度参数计算分数：
    /// - 高斜率使分数趋近于 0 或 1，放大微小差异便于排序
    /// - 仅用于检索排序，不用于直观展示
    ///
    /// ## 计算公式
    /// ```
    /// logit = cosine * logitScale + logitBias
    /// score = sigmoid(logit) = 1 / (1 + exp(-logit))
    /// ```
    ///
    /// - Parameters:
    ///   - cosine: 余弦相似度 [-1, 1]
    ///   - config: 相似度配置
    /// - Returns: 映射后的相似度分数
    static func from(cosine: Float, config: SimilarityConfig) -> SimilarityScore {
        let logit = cosine * config.logitScale + config.logitBias
        let score = 1.0 / (1.0 + exp(-logit))
        return SimilarityScore(score)
    }

    /// 图图相似度专用映射（更温和的刻度，避免 Sigmoid 饱和）
    ///
    /// 图文检索使用高斜率 sigmoid 区分排序，但图图对比需要直观展示分数。
    /// 使用配置的温和参数，确保：
    /// - cosine = 1.0 → 100%（完全相同）
    /// - cosine = 0.5 → 50%（中等相似）
    /// - cosine = 0.0 → ~8%（正交无关）
    ///
    /// - Parameters:
    ///   - cosine: 余弦相似度 [-1, 1]
    ///   - config: 相似度配置
    /// - Returns: 映射后的相似度分数
    static func fromImageComparison(cosine: Float, config: SimilarityConfig) -> SimilarityScore {
        let logit = cosine * config.imageComparisonScale + config.imageComparisonBias
        let score = 1.0 / (1.0 + exp(-logit))
        return SimilarityScore(score)
    }
    
    // MARK: - Comparable
    
    static func < (lhs: SimilarityScore, rhs: SimilarityScore) -> Bool {
        lhs.value < rhs.value
    }
}

// MARK: - SimilarityConfig

/// 相似度计算配置
///
/// 定义图文检索和图图对比的 Sigmoid 映射参数。
/// 这些参数是从训练数据中统计得出的敏感值，需要从本地配置读取。
///
/// ## 计算公式
/// ```swift
/// let logit = cosine * logitScale + logitBias
/// let score = 1.0 / (1.0 + exp(-logit))
/// ```
///
/// ## 参数来源
/// - `logitScale` / `logitBias`：从 WeCLIPv2 训练数据统计
/// - `imageComparisonScale` / `imageComparisonBias`：为图图对比场景调整
struct SimilarityConfig: Sendable, Codable {
    /// 图文检索 logit scale
    /// - Note: 敏感参数，从本地配置读取
    let logitScale: Float
    
    /// 图文检索 logit bias
    /// - Note: 敏感参数，从本地配置读取
    let logitBias: Float
    
    /// 图图相似度温和刻度 scale
    /// 用于图片对比场景，避免 sigmoid 饱和导致分数趋近 100%
    let imageComparisonScale: Float
    
    /// 图图相似度温和刻度 bias
    let imageComparisonBias: Float
    
    /// 默认配置（开发/测试用）
    /// - Note: 生产环境应从配置文件读取
    static let `default` = SimilarityConfig(
        logitScale: 98.864479,
        logitBias: -10.0,
        imageComparisonScale: 4.0,
        imageComparisonBias: 1.5
    )
}

// MARK: - PreprocessingConfig

/// 预处理配置
///
/// 定义图像预处理的参数，不同模型使用不同的标准化参数。
///
/// ## CLIP 标准化
/// WeCLIPv2 和 OpenAI CLIP 使用相同的标准化参数：
/// - mean: [0.48145466, 0.4578275, 0.40821073]
/// - std: [0.26862954, 0.26130258, 0.27577711]
struct PreprocessingConfig: Sendable, Codable {
    /// 归一化均值 [R, G, B]
    ///
    /// CLIP 标准: [0.48145466, 0.4578275, 0.40821073]
    let normalizeMean: [Float]
    
    /// 归一化标准差 [R, G, B]
    ///
    /// CLIP 标准: [0.26862954, 0.26130258, 0.27577711]
    let normalizeStd: [Float]
    
    // MARK: - Default Configurations
    
    /// CLIP 预处理配置
    static let clip = PreprocessingConfig(
        normalizeMean: [0.48145466, 0.4578275, 0.40821073],
        normalizeStd: [0.26862954, 0.26130258, 0.27577711]
    )
}
