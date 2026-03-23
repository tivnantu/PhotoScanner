import Foundation

struct ChineseCLIPBaseline: Decodable, Sendable {
    let baselineVersion: String
    let generatedAt: String?
    let generator: GeneratorInfo?
    let model: ModelInfo
    let tolerances: Tolerances
    let textCases: [TextCase]
    let imageCases: [ImageCase]
    let similarityCases: [SimilarityCase]

    enum CodingKeys: String, CodingKey {
        case baselineVersion = "baseline_version"
        case generatedAt = "generated_at"
        case generator
        case model
        case tolerances
        case textCases = "text_cases"
        case imageCases = "image_cases"
        case similarityCases = "similarity_cases"
    }

    struct GeneratorInfo: Decodable, Sendable {
        let name: String
        let onnxruntimeVersion: String?

        enum CodingKeys: String, CodingKey {
            case name
            case onnxruntimeVersion = "onnxruntime_version"
        }
    }

    struct ModelInfo: Decodable, Sendable {
        let id: String
        let imageSize: Int
        let contextLength: Int
        let embeddingDimension: Int
        let imageMean: [Float]
        let imageStd: [Float]

        enum CodingKeys: String, CodingKey {
            case id
            case imageSize = "image_size"
            case contextLength = "context_length"
            case embeddingDimension = "embedding_dimension"
            case imageMean = "image_mean"
            case imageStd = "image_std"
        }
    }

    struct Tolerances: Decodable, Sendable {
        let tokenIDsExactMatch: Bool
        let textEmbeddingCosineMin: Float
        let imagePreprocessCosineMin: Float
        let imagePreprocessAbsDiffMax: Float
        let imageEmbeddingCosineMin: Float
        let similarityAbsDiffMax: Float

        enum CodingKeys: String, CodingKey {
            case tokenIDsExactMatch = "token_ids_exact_match"
            case textEmbeddingCosineMin = "text_embedding_cosine_min"
            case imagePreprocessCosineMin = "image_preprocess_cosine_min"
            case imagePreprocessAbsDiffMax = "image_preprocess_abs_diff_max"
            case imageEmbeddingCosineMin = "image_embedding_cosine_min"
            case similarityAbsDiffMax = "similarity_abs_diff_max"
        }
    }

    struct TextCase: Decodable, Sendable {
        let id: String
        let text: String
        let tokenIDs: [Int]
        let textEmbedding: [Float]

        enum CodingKeys: String, CodingKey {
            case id
            case text
            case tokenIDs = "token_ids"
            case textEmbedding = "text_embedding"
        }
    }

    struct ImageCase: Decodable, Sendable {
        let id: String
        let image: String
        let preprocessedTensorFile: String
        let preprocessedTensorShape: [Int]
        let imageEmbedding: [Float]

        enum CodingKeys: String, CodingKey {
            case id
            case image
            case preprocessedTensorFile = "preprocessed_tensor_file"
            case preprocessedTensorShape = "preprocessed_tensor_shape"
            case imageEmbedding = "image_embedding"
        }
    }

    struct SimilarityCase: Decodable, Sendable {
        let id: String
        let imageCaseID: String
        let textCaseID: String
        let similarity: Float

        enum CodingKeys: String, CodingKey {
            case id
            case imageCaseID = "image_case_id"
            case textCaseID = "text_case_id"
            case similarity
        }
    }
}

extension ChineseCLIPBaseline {
    static func load(from url: URL) throws -> Self {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: data)
    }
}
