import Foundation
@testable import PhotoScanner

enum BaselineVectorMath {
    static func firstMismatchIndex(expected: [Int], actual: [Int]) -> Int? {
        guard expected.count == actual.count else {
            return min(expected.count, actual.count)
        }

        for index in expected.indices where expected[index] != actual[index] {
            return index
        }
        return nil
    }

    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else {
            return -1
        }

        let aNorm = sqrt(a.reduce(Float.zero) { $0 + $1 * $1 })
        let bNorm = sqrt(b.reduce(Float.zero) { $0 + $1 * $1 })
        guard aNorm.isFinite, bNorm.isFinite, aNorm > .ulpOfOne, bNorm > .ulpOfOne else {
            return -1
        }

        return dotProduct(a, b) / (aNorm * bNorm)
    }

    static func maximumAbsoluteDifference(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else {
            return .greatestFiniteMagnitude
        }

        var maximum: Float = 0
        for (lhs, rhs) in zip(a, b) {
            maximum = max(maximum, abs(lhs - rhs))
        }
        return maximum
    }

    static func loadFloat32Array(from url: URL, expectedCount: Int) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let elementSize = MemoryLayout<Float>.stride
        guard data.count == expectedCount * elementSize else {
            throw PSError.invalidInput(
                "图像预处理基线长度异常：期望字节数 \(expectedCount * elementSize)，实际 \(data.count)"
            )
        }

        return data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
    }

    static func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).reduce(Float.zero) { partial, pair in
            partial + pair.0 * pair.1
        }
    }
}
