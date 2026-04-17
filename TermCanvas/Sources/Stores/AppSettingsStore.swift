import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    private let userDefaults: UserDefaults
    private let terminalPersistenceModeKey = "termcanvas.terminalPersistenceMode"

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
            let storedValue = userDefaults.string(forKey: terminalPersistenceModeKey),
            let storedMode = TerminalPersistenceMode(rawValue: storedValue)
        {
            terminalPersistenceMode = storedMode
        } else {
            terminalPersistenceMode = .restoreHistoryOnReopen
        }
    }
}
