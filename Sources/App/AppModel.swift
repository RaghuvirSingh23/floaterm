import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settings: AppSettingsStore
    let store: CanvasStore

    private let persistenceController: WorkspacePersistenceController
    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: AppSettingsStore = AppSettingsStore(),
        persistenceController: WorkspacePersistenceController = WorkspacePersistenceController()
    ) {
        self.settings = settings
        self.persistenceController = persistenceController

        let restoredWorkspace = persistenceController.restoreWorkspace()
        store = CanvasStore(snapshot: restoredWorkspace?.canvas)

        store.objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.saveWorkspaceSnapshot()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.flushPersistence()
            }
            .store(in: &cancellables)

        persistenceController.primeCanvasSnapshot(store.workspaceSnapshot)
    }

    func restoredTranscript(for terminalID: UUID) -> Data? {
        persistenceController.restoredTranscript(for: terminalID)
    }

    func recordTerminalOutput(_ data: Data, for terminalID: UUID) {
        persistenceController.recordTerminalOutput(data, for: terminalID)
    }

    func flushPersistence() {
        persistenceController.flush(canvas: store.workspaceSnapshot)
    }

    private func saveWorkspaceSnapshot() {
        persistenceController.noteCanvasChanged(store.workspaceSnapshot)
    }
}
