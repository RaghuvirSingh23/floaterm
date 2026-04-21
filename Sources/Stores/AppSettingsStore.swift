import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    private let userDefaults: UserDefaults
    private let appAppearanceModeKey = "floaterm.appAppearanceMode"
    private let terminalPersistenceModeKey = "floaterm.terminalPersistenceMode"

    @Published var appAppearanceMode: AppAppearanceMode {
        didSet {
            guard appAppearanceMode != oldValue else {
                return
            }

            userDefaults.set(appAppearanceMode.rawValue, forKey: appAppearanceModeKey)
        }
    }

    @Published var terminalPersistenceMode: TerminalPersistenceMode {
        didSet {
            guard terminalPersistenceMode != oldValue else {
                return
            }

            userDefaults.set(terminalPersistenceMode.rawValue, forKey: terminalPersistenceModeKey)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if
            let storedValue = userDefaults.string(forKey: appAppearanceModeKey),
            let storedMode = AppAppearanceMode(rawValue: storedValue)
        {
            appAppearanceMode = storedMode
        } else {
            appAppearanceMode = .dark
        }

        if
            let storedValue = userDefaults.string(forKey: terminalPersistenceModeKey),
            let storedMode = TerminalPersistenceMode(rawValue: storedValue)
        {
            terminalPersistenceMode = storedMode
        } else {
            terminalPersistenceMode = .restoreHistoryOnReopen
        }
    }
}
