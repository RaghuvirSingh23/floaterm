import Foundation

enum AppResourceLocator {
    private static let terminalBundleName = "Floaterm_Floaterm.bundle"
    private static let terminalFrontendRelativePath = "Terminal/index.html"

    static func terminalFrontendURL(
        mainBundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL? {
        terminalFrontendURL(
            bundleURL: mainBundle.bundleURL,
            resourceURL: mainBundle.resourceURL,
            fileManager: fileManager
        )
    }

    static func terminalFrontendURL(
        bundleURL: URL,
        resourceURL: URL?,
        fileManager: FileManager = .default
    ) -> URL? {
        var seenPaths = Set<String>()
        let bundleCandidates = [
            resourceURL?.appendingPathComponent(Self.terminalBundleName, isDirectory: true),
            bundleURL.appendingPathComponent(Self.terminalBundleName, isDirectory: true),
            bundleURL.deletingLastPathComponent().appendingPathComponent(Self.terminalBundleName, isDirectory: true),
            bundleURL.appendingPathComponent("Contents/Resources/\(Self.terminalBundleName)", isDirectory: true),
        ].compactMap { $0 }

        for bundleCandidate in bundleCandidates {
            let frontendURL = bundleCandidate.appendingPathComponent(Self.terminalFrontendRelativePath, isDirectory: false)
            guard seenPaths.insert(frontendURL.path).inserted else {
                continue
            }

            if fileManager.fileExists(atPath: frontendURL.path) {
                return frontendURL
            }
        }

        return nil
    }
}
