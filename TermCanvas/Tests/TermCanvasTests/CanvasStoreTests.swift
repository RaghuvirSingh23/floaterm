import AppKit
import XCTest
@testable import TermCanvas

final class CanvasStoreTests: XCTestCase {
    func testZoomKeepsAnchorStable() {
        let camera = CanvasCamera(zoom: 1, pan: CGPoint(x: 600, y: 400))
        let anchor = CGPoint(x: 900, y: 700)
        let worldPointBefore = CanvasGeometry.screenToWorld(anchor, camera: camera)

        let zoomed = CanvasGeometry.zoomed(camera: camera, factor: 1.4, anchorInScreen: anchor)
        let worldPointAfter = CanvasGeometry.screenToWorld(anchor, camera: zoomed)

        XCTAssertEqual(worldPointBefore.x, worldPointAfter.x, accuracy: 0.0001)
        XCTAssertEqual(worldPointBefore.y, worldPointAfter.y, accuracy: 0.0001)
    }

    func testResizeClampsToMinimumFromLeftEdge() {
        let frame = CGRect(x: 10, y: 20, width: 320, height: 240)
        let resized = CanvasGeometry.resized(
            frame: frame,
            handle: .left,
            deltaInWorld: CGPoint(x: 200, y: 0)
        )

        XCTAssertEqual(resized.width, CanvasGeometry.minimumNodeSize.width, accuracy: 0.0001)
        XCTAssertEqual(resized.maxX, frame.maxX, accuracy: 0.0001)
    }

    @MainActor
    func testStoreMovesNodeUsingScreenDeltaAndZoom() throws {
        let store = CanvasStore()
        let nodeID = store.createTerminal(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        store.camera = CanvasCamera(zoom: 2, pan: CGPoint(x: 500, y: 400))

        store.moveNode(id: nodeID, byScreenDelta: CGPoint(x: 100, y: 50))

        let movedNode = try XCTUnwrap(store.nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(movedNode.frame.origin.x, 50, accuracy: 0.0001)
        XCTAssertEqual(movedNode.frame.origin.y, 25, accuracy: 0.0001)
    }

    @MainActor
    func testMoveNodeReportsGridFeedbackWithoutSnapping() throws {
        let store = CanvasStore()
        let nodeID = store.createTerminal(frame: CGRect(x: 0, y: 0, width: 320, height: 240))

        let feedbackState = store.moveNode(id: nodeID, byScreenDelta: CGPoint(x: 47, y: 0))

        let movedNode = try XCTUnwrap(store.nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(movedNode.frame.origin.x, 47, accuracy: 0.0001)
        XCTAssertEqual(feedbackState, CanvasSnapState(x: 48, y: nil))
    }

    @MainActor
    func testResizeNodeReportsGridFeedbackWithoutSnapping() throws {
        let store = CanvasStore()
        let nodeID = store.createTerminal(frame: CGRect(x: 0, y: 0, width: 320, height: 240))

        let feedbackState = store.resizeNode(id: nodeID, handle: .right, byScreenDelta: CGPoint(x: 14, y: 0))

        let resizedNode = try XCTUnwrap(store.nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(resizedNode.frame.maxX, 334, accuracy: 0.0001)
        XCTAssertEqual(feedbackState, CanvasSnapState(x: 336, y: nil))
    }

    @MainActor
    func testSelectElementsInRectFindsTerminalAndText() throws {
        let store = CanvasStore()
        let nodeID = store.createTerminal(frame: CGRect(x: 40, y: 40, width: 320, height: 240))
        let textID = store.createText(at: CGPoint(x: 120, y: 120), content: "Hello")

        store.selectElements(intersecting: CGRect(x: 0, y: 0, width: 200, height: 200))

        XCTAssertTrue(store.selectedElementIDs.contains(nodeID))
        XCTAssertTrue(store.selectedElementIDs.contains(textID))
    }

    @MainActor
    func testDraftTextGrowsWithoutFixedWidthAndDeletesWhenCommittedEmpty() throws {
        let store = CanvasStore()
        let textID = store.createText(at: CGPoint(x: 0, y: 0), content: "Hi")

        store.updateTextDraft(id: textID, content: String(repeating: "W", count: 40))
        let textItem = try XCTUnwrap(store.textItems.first(where: { $0.id == textID }))
        XCTAssertNil(textItem.wrapWidth)
        XCTAssertGreaterThan(textItem.frame.width, 420)

        store.commitText(id: textID, content: "   ")
        XCTAssertFalse(store.textItems.contains(where: { $0.id == textID }))
    }

    @MainActor
    func testResizeTextFromLeftKeepsRightEdgeStable() throws {
        let store = CanvasStore()
        let textID = store.createText(at: CGPoint(x: 0, y: 0), content: "one two three four five six seven eight")
        let originalItem = try XCTUnwrap(store.textItems.first(where: { $0.id == textID }))
        let originalMaxX = originalItem.frame.maxX

        store.resizeTextItem(id: textID, handle: .left, byScreenDelta: CGPoint(x: 80, y: 0))

        let resizedItem = try XCTUnwrap(store.textItems.first(where: { $0.id == textID }))
        XCTAssertEqual(resizedItem.frame.maxX, originalMaxX, accuracy: 0.0001)
        XCTAssertNotNil(resizedItem.wrapWidth)
        XCTAssertLessThan(resizedItem.frame.width, originalItem.frame.width)
    }

    @MainActor
    func testSingleCharacterTextCanShrinkBackAfterExpansion() throws {
        let store = CanvasStore()
        let textID = store.createText(at: CGPoint(x: 0, y: 0), content: "h")
        let originalItem = try XCTUnwrap(store.textItems.first(where: { $0.id == textID }))

        store.resizeTextItem(id: textID, handle: .right, byScreenDelta: CGPoint(x: 160, y: 0))
        store.resizeTextItem(id: textID, handle: .right, byScreenDelta: CGPoint(x: -600, y: 0))

        let resizedItem = try XCTUnwrap(store.textItems.first(where: { $0.id == textID }))
        XCTAssertEqual(resizedItem.frame.width, originalItem.frame.width, accuracy: 0.0001)
    }

    @MainActor
    func testRenameNodeTrimsAndLimitsTitleLength() throws {
        let store = CanvasStore()
        let nodeID = store.createTerminal(frame: CGRect(x: 0, y: 0, width: 320, height: 240))

        store.renameNode(id: nodeID, title: "   12345678901234567890extra   ")

        let renamedNode = try XCTUnwrap(store.nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(renamedNode.title, "12345678901234567890")
    }

    @MainActor
    func testStoreRestoresWorkspaceSnapshotAndCounter() throws {
        let restoredNode = TerminalNode(
            id: UUID(),
            title: "TERM 07",
            frame: CGRect(x: 80, y: 120, width: 520, height: 320)
        )
        let restoredText = CanvasTextItem(
            id: UUID(),
            text: "deploy notes",
            frame: CGRect(x: 40, y: 40, width: 200, height: 80),
            wrapWidth: 160
        )
        let snapshot = WorkspaceSnapshot(
            nodes: [restoredNode],
            textItems: [restoredText],
            camera: CanvasCamera(zoom: 1.4, pan: CGPoint(x: 280, y: 190)),
            terminalCounter: 8
        )
        let store = CanvasStore(snapshot: snapshot)

        XCTAssertEqual(store.nodes, [restoredNode])
        XCTAssertEqual(store.textItems, [restoredText])
        XCTAssertEqual(store.camera, snapshot.camera)

        let newID = store.createTerminal(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let newNode = try XCTUnwrap(store.nodes.first(where: { $0.id == newID }))
        XCTAssertEqual(newNode.title, "TERM 08")
    }
}
