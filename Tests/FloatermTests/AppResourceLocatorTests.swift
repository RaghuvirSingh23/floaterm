import Foundation
import XCTest
@testable import Floaterm

final class AppResourceLocatorTests: XCTestCase {
    func testTerminalFrontendURLResolvesFromAppResourcesDirectory() throws {
        let fixture = try makeTerminalResourceFixture(layout: .appBundle)

        let resolved = AppResourceLocator.terminalFrontendURL(
            bundleURL: fixture.bundleURL,
            resourceURL: fixture.resourceURL,
            fileManager: fixture.fileManager
        )

        XCTAssertEqual(resolved?.standardizedFileURL, fixture.expectedFrontendURL.standardizedFileURL)
    }

    func testTerminalFrontendURLResolvesFromSwiftPMBuildDirectory() throws {
        let fixture = try makeTerminalResourceFixture(layout: .swiftPMBuild)

        let resolved = AppResourceLocator.terminalFrontendURL(
            bundleURL: fixture.bundleURL,
            resourceURL: fixture.resourceURL,
            fileManager: fixture.fileManager
        )

        XCTAssertEqual(resolved?.standardizedFileURL, fixture.expectedFrontendURL.standardizedFileURL)
    }

    private enum FixtureLayout {
        case appBundle
        case swiftPMBuild
    }

    private struct Fixture {
        let bundleURL: URL
        let resourceURL: URL?
        let expectedFrontendURL: URL
        let fileManager: FileManager
    }

    private func makeTerminalResourceFixture(layout: FixtureLayout) throws -> Fixture {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let resourceBundleName = "Floaterm_Floaterm.bundle"
        let frontendPath = "Terminal/index.html"

        let bundleURL: URL
        let resourceURL: URL?
        let frontendURL: URL

        switch layout {
        case .appBundle:
            bundleURL = rootURL.appendingPathComponent("floaterm.app", isDirectory: true)
            resourceURL = bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
            frontendURL = resourceURL!
                .appendingPathComponent(resourceBundleName, isDirectory: true)
                .appendingPathComponent(frontendPath, isDirectory: false)
        case .swiftPMBuild:
            resourceURL = rootURL.appendingPathComponent("debug", isDirectory: true)
            bundleURL = resourceURL!.appendingPathComponent("Floaterm", isDirectory: false)
            frontendURL = resourceURL!
                .appendingPathComponent(resourceBundleName, isDirectory: true)
                .appendingPathComponent(frontendPath, isDirectory: false)
        }

        try fileManager.createDirectory(at: frontendURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("<html></html>".utf8).write(to: frontendURL)

        return Fixture(
            bundleURL: bundleURL,
            resourceURL: resourceURL,
            expectedFrontendURL: frontendURL,
            fileManager: fileManager
        )
    }
}
