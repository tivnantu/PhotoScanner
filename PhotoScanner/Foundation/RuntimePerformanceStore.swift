import Foundation

enum RuntimePerformanceMetricKey: String, CaseIterable, Sendable {
    case stateRestore
    case assetRefresh
    case indexBuild
    case textEmbedding
    case vectorSearch
    case searchTotal
    case previewResolution
    case photoLibraryPreview
    case photoLibraryOriginal

    var title: String {
        switch self {
        case .stateRestore:
            return "索引恢复"
        case .assetRefresh:
            return "导入资源刷新"
        case .indexBuild:
            return "索引构建"
        case .textEmbedding:
            return "文本向量生成"
        case .vectorSearch:
            return "向量检索"
        case .searchTotal:
            return "搜索主链路"
        case .previewResolution:
            return "结果回填"
        case .photoLibraryPreview:
            return "相册预览读取"
        case .photoLibraryOriginal:
            return "相册原图读取"
        }
    }
}

struct RuntimePerformanceMetric: Identifiable, Sendable, Equatable {
    let key: RuntimePerformanceMetricKey
    let detail: String
    let durationMilliseconds: Double
    let recordedAt: Date

    var id: String {
        key.rawValue
    }

    var title: String {
        key.title
    }

    var durationText: String {
        Self.format(milliseconds: durationMilliseconds)
    }

    var recordedAtText: String {
        Self.timeFormatter.string(from: recordedAt)
    }

    init(
        key: RuntimePerformanceMetricKey,
        detail: String,
        duration: Duration,
        recordedAt: Date = Date()
    ) {
        self.key = key
        self.detail = detail
        self.durationMilliseconds = Self.durationMilliseconds(from: duration)
        self.recordedAt = recordedAt
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func durationMilliseconds(from duration: Duration) -> Double {
        let components = duration.components
        let seconds = Double(components.seconds)
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000_000
        return (seconds + attoseconds) * 1_000
    }

    private static func format(milliseconds: Double) -> String {
        if milliseconds >= 1_000 {
            return String(format: "%.2fs", milliseconds / 1_000)
        }
        if milliseconds >= 100 {
            return String(format: "%.0fms", milliseconds)
        }
        if milliseconds >= 1 {
            return String(format: "%.1fms", milliseconds)
        }
        return String(format: "%.2fms", milliseconds)
    }
}

actor RuntimePerformanceStore {
    private var latestMetrics: [RuntimePerformanceMetricKey: RuntimePerformanceMetric] = [:]

    func record(_ key: RuntimePerformanceMetricKey, duration: Duration, detail: String) {
        latestMetrics[key] = RuntimePerformanceMetric(key: key, detail: detail, duration: duration)
    }

    func metrics() -> [RuntimePerformanceMetric] {
        RuntimePerformanceMetricKey.allCases.compactMap { latestMetrics[$0] }
    }
}
