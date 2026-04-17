import Foundation

struct PersistedWorkspaceEnvelope: Codable, Equatable {
    var version: Int
    var canvas: WorkspaceSnapshot
    var terminalTranscripts: [UUID: Data]

    init(version: Int = 1, canvas: WorkspaceSnapshot, terminalTranscripts: [UUID: Data]) {
        self.version = version
        self.canvas = canvas
        self.terminalTranscripts = terminalTranscripts
    }
}

@MainActor
final class WorkspacePersistenceController {
    private let fileURL: URL
    private let fileManager: FileManager
    private let ioQueue = DispatchQueue(label: "com.raghusi.TermCanvas.persistence", qos: .utility)
    private let saveDelay: TimeInterval
    private let transcriptByteLimit: Int

    private var latestCanvasSnapshot: WorkspaceSnapshot?
    private var terminalTranscripts: [UUID: Data] = [:]
    private var pendingSaveWorkItem: DispatchWorkItem?

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        saveDelay: TimeInterval = 0.5,
        transcriptByteLimit: Int = 512 * 1024
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultWorkspaceFileURL(fileManager: fileManager)
        self.saveDelay = saveDelay
        self.transcriptByteLimit = transcriptByteLimit
    }

    func restoreWorkspace() -> PersistedWorkspaceEnvelope? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let envelope = try JSONDecoder().decode(PersistedWorkspaceEnvelope.self, from: data)
            latestCanvasSnapshot = envelope.canvas
            terminalTranscripts = envelope.terminalTranscripts
            return envelope
        } catch {
            return nil
        }
    }

    func restoredTranscript(for terminalID: UUID) -> Data? {
        terminalTranscripts[terminalID]
    }

    func primeCanvasSnapshot(_ snapshot: WorkspaceSnapshot) {
        latestCanvasSnapshot = snapshot
        pruneTranscripts(toMatch: snapshot)
    }

    func noteCanvasChanged(_ snapshot: WorkspaceSnapshot) {
        latestCanvasSnapshot = snapshot
        pruneTranscripts(toMatch: snapshot)
        scheduleSave()
    }

    func recordTerminalOutput(_ data: Data, for terminalID: UUID) {
        guard !data.isEmpty else {
            return
        }

        var transcript = terminalTranscripts[terminalID] ?? Data()
        transcript.append(data)

        let overflow = transcript.count - transcriptByteLimit
        if overflow > 0 {
            transcript.removeFirst(overflow)
        }

        terminalTranscripts[terminalID] = transcript
        scheduleSave()
    }

    func flush(canvas snapshot: WorkspaceSnapshot) {
        latestCanvasSnapshot = snapshot
        pruneTranscripts(toMatch: snapshot)
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        persistCurrentEnvelopeIfNeeded(waitUntilFinished: true)
    }

    private func pruneTranscripts(toMatch snapshot: WorkspaceSnapshot) {
        let liveTerminalIDs = Set(snapshot.nodes.map(\.id))
        terminalTranscripts = terminalTranscripts.filter { liveTerminalIDs.contains($0.key) }
    }

    private func scheduleSave() {
        pendingSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.persistCurrentEnvelopeIfNeeded()
            }
        }

        pendingSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: workItem)
    }

    private func persistCurrentEnvelopeIfNeeded(waitUntilFinished: Bool = false) {
        guard let latestCanvasSnapshot else {
            return
        }

        let envelope = PersistedWorkspaceEnvelope(
            canvas: latestCanvasSnapshot,
            terminalTranscripts: terminalTranscripts
        )

        let parentDirectory = fileURL.deletingLastPathComponent()
        let encodedData: Data

        do {
            encodedData = try JSONEncoder().encode(envelope)
        } catch {
            return
        }

        let writeOperation: @Sendable () -> Void = { [fileURL, parentDirectory, encodedData] in
            do {
                try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true, attributes: nil)
                try encodedData.write(to: fileURL, options: .atomic)
            } catch {
                // Ignore autosave failures for now; the user keeps working with the in-memory canvas.
            }
        }

        if waitUntilFinished {
            ioQueue.sync(execute: writeOperation)
        } else {
            ioQueue.async(execute: writeOperation)
        }
    }

    private static func defaultWorkspaceFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        return applicationSupport
            .appendingPathComponent("TermCanvas", isDirectory: true)
            .appendingPathComponent("workspace.json", isDirectory: false)
    }
}
