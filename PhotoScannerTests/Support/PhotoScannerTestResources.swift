import Foundation
@testable import PhotoScanner

enum PhotoScannerTestResources {
    private final class BundleLocator: NSObject {}

    nonisolated private static let testBundle = Bundle(for: BundleLocator.self)

    static func baselineFileURL() throws -> URL {
        try requiredResource(named: "baseline", withExtension: "json")
    }

    static func fixtureURL(relativePath: String) throws -> URL {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension
        let resourceName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return try requiredResource(named: resourceName, withExtension: fileExtension)
    }

    private static func requiredResource(named name: String, withExtension ext: String) throws -> URL {
        if let directURL = testBundle.url(forResource: name, withExtension: ext) {
            return directURL
        }

        let targetFileName = "\(name).\(ext)"
        if let resourceURL = testBundle.resourceURL,
           let enumerator = FileManager.default.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
           ) {
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.lastPathComponent == targetFileName {
                    return fileURL
                }
            }
        }

        throw PSError.resourceNotFound(
            name: name,
            extension: ext,
            subdirectory: "PhotoScannerTests"
        )
    }
}
