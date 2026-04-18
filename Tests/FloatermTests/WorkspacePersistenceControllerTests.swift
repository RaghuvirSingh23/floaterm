import Foundation
import XCTest
@testable import Floaterm

@MainActor
final class WorkspacePersistenceControllerTests: XCTestCase {
    func testPersistenceRoundTripRestoresCanvasAndTranscript() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("workspace.json", isDirectory: false)
        let controller = WorkspacePersistenceController(fileURL: fileURL, saveDelay: 0)
        let terminalID = UUID()
        let frameID = UUID()
        let snapshot = WorkspaceSnapshot(
            nodes: [
                TerminalNode(
                    id: terminalID,
                    title: "TERM 01",
                    frame: CGRect(x: 10, y: 20, width: 520, height: 320)
                ),
            ],
            frameItems: [
                CanvasFrameItem(
                    id: frameID,
                    title: "FRAME 01",
                    frame: CGRect(x: 0, y: 0, width: 620, height: 420),
                    childIDs: [terminalID]
                ),
            ],
            textItems: [],
            camera: CanvasCamera(zoom: 1.15, pan: CGPoint(x: 120, y: 80)),
            terminalCounter: 2,
            frameCounter: 2
        )

        controller.noteCanvasChanged(snapshot)
        controller.recordTerminalOutput(Data("echo hi\n".utf8), for: terminalID)
        controller.flush(canvas: snapshot)

        let restored = WorkspacePersistenceController(fileURL: fileURL, saveDelay: 0).restoreWorkspace()

        XCTAssertEqual(restored?.canvas, snapshot)
        XCTAssertEqual(restored?.terminalTranscripts[terminalID], Data("echo hi\n".utf8))
    }

    func testRemovingTerminalPrunesSavedTranscript() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = rootURL.appendingPathComponent("workspace.json", isDirectory: false)
        let controller = WorkspacePersistenceController(fileURL: fileURL, saveDelay: 0)
        let terminalID = UUID()
        let snapshot = WorkspaceSnapshot(
            nodes: [
                TerminalNode(
                    id: terminalID,
                    title: "TERM 01",
                    frame: CGRect(x: 10, y: 20, width: 520, height: 320)
                ),
            ],
            frameItems: [
                CanvasFrameItem(
                    id: UUID(),
                    title: "FRAME 01",
                    frame: CGRect(x: 0, y: 0, width: 620, height: 420),
                    childIDs: [terminalID]
                ),
            ],
            textItems: [],
            camera: CanvasCamera(),
            terminalCounter: 2,
            frameCounter: 2
        )

        controller.noteCanvasChanged(snapshot)
        controller.recordTerminalOutput(Data("pwd\n".utf8), for: terminalID)
        controller.flush(canvas: snapshot)

        let prunedSnapshot = WorkspaceSnapshot(
            nodes: [],
            frameItems: [],
            textItems: [],
            camera: CanvasCamera(),
            terminalCounter: 2,
            frameCounter: 2
        )
        controller.noteCanvasChanged(prunedSnapshot)
        controller.flush(canvas: prunedSnapshot)

        let restored = WorkspacePersistenceController(fileURL: fileURL, saveDelay: 0).restoreWorkspace()

        XCTAssertEqual(restored?.canvas, prunedSnapshot)
        XCTAssertTrue(restored?.terminalTranscripts.isEmpty ?? false)
    }
}
