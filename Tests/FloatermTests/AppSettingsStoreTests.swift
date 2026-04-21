import XCTest
@testable import Floaterm

@MainActor
final class AppSettingsStoreTests: XCTestCase {
    func testDefaultsToDarkAppearanceMode() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.appAppearanceMode, .dark)
        XCTAssertEqual(store.terminalPersistenceMode, .restoreHistoryOnReopen)
    }

    func testPersistsAppearanceModeSelection() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(userDefaults: defaults)

        store.appAppearanceMode = .light

        let restored = AppSettingsStore(userDefaults: defaults)
        XCTAssertEqual(restored.appAppearanceMode, .light)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
