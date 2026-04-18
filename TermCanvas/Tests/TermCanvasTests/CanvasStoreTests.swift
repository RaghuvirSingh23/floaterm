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

    @MainActor
    func testResetZoomCentersOnSelectionAtOneHundredPercent() {
        let store = CanvasStore()
        store.updateViewportSize(CGSize(width: 1000, height: 800))
        _ = store.createTerminal(frame: CGRect(x: 100, y: 100, width: 320, height: 240))
        let selectedID = store.createTerminal(frame: CGRect(x: 900, y: 500, width: 320, height: 240))
        store.camera = CanvasCamera(zoom: 1.8, pan: CGPoint(x: -240, y: 120))
        store.setSelection([selectedID])

        store.resetZoom()

        XCTAssertEqual(store.camera.zoom, 1, accuracy: 0.0001)
        XCTAssertEqual(store.camera.pan.x, -560, accuracy: 0.0001)
        XCTAssertEqual(store.camera.pan.y, -220, accuracy: 0.0001)
    }

    @MainActor
    func testCameraInteractionIncrementsMinimapActivityTick() {
        let store = CanvasStore()
        let initialTick = store.minimapActivityTick

        store.panBy(CGPoint(x: 40, y: 20))
        XCTAssertEqual(store.minimapActivityTick, initialTick + 1)

        store.zoom(by: 1.12, around: CGPoint(x: 400, y: 300))
        XCTAssertEqual(store.minimapActivityTick, initialTick + 2)
    }

    @MainActor
    func testResetZoomCentersOnAllContentWithoutSelection() {
        let store = CanvasStore()
        store.updateViewportSize(CGSize(width: 1000, height: 800))
        _ = store.createTerminal(frame: CGRect(x: 100, y: 100, width: 320, height: 240))
        _ = store.createTerminal(frame: CGRect(x: 900, y: 500, width: 320, height: 240))
        store.camera = CanvasCamera(zoom: 2.2, pan: CGPoint(x: 180, y: -40))
        store.clearSelection()

        store.resetZoom()

        XCTAssertEqual(store.camera.zoom, 1, accuracy: 0.0001)
        XCTAssertEqual(store.camera.pan.x, -160, accuracy: 0.0001)
        XCTAssertEqual(store.camera.pan.y, -20, accuracy: 0.0001)
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
    func testBroadcastTargetsOnlyOtherSelectedTerminals() {
        let store = CanvasStore()
        let firstID = store.createTerminal(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let secondID = store.createTerminal(frame: CGRect(x: 360, y: 0, width: 320, height: 240))
        let thirdID = store.createTerminal(frame: CGRect(x: 720, y: 0, width: 320, height: 240))
        let textID = store.createText(at: CGPoint(x: 200, y: 320), content: "note")

        store.setSelection([firstID, secondID, textID])
        store.setTerminalBroadcastEnabled(true)

        XCTAssertTrue(store.isTerminalBroadcastEnabled)
        XCTAssertTrue(store.canBroadcastSelectedTerminals)
        XCTAssertEqual(store.selectedTerminalCount, 2)
        XCTAssertEqual(Set(store.terminalBroadcastTargetIDs(forOriginID: firstID)), [secondID])
        XCTAssertEqual(store.terminalBroadcastTargetIDs(forOriginID: thirdID), [])
    }

    @MainActor
    func testBroadcastDisablesWhenSelectionDropsBelowTwoTerminals() {
        let store = CanvasStore()
        let firstID = store.createTerminal(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let secondID = store.createTerminal(frame: CGRect(x: 360, y: 0, width: 320, height: 240))

        store.setSelection([firstID, secondID])
        store.setTerminalBroadcastEnabled(true)
        XCTAssertTrue(store.isTerminalBroadcastEnabled)

        store.setSelection([firstID])
        XCTAssertFalse(store.isTerminalBroadcastEnabled)
        XCTAssertFalse(store.canBroadcastSelectedTerminals)
        XCTAssertEqual(store.terminalBroadcastTargetIDs(forOriginID: firstID), [])
    }

    @MainActor
    func testRequestFocusOnSelectedTerminalTargetsSelectedTerminal() {
        let store = CanvasStore()
        let firstID = store.createTerminal(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let secondID = store.createTerminal(frame: CGRect(x: 360, y: 0, width: 320, height: 240))

        store.setSelection([firstID, secondID])
        store.requestFocusOnSelectedTerminal()

        XCTAssertEqual(store.pendingTerminalFocusID, secondID)

        store.acknowledgePendingTerminalFocus(id: secondID)
        XCTAssertNil(store.pendingTerminalFocusID)
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
    func testWrapSelectionInFrameCreatesContainerAroundContent() throws {
        let store = CanvasStore()
        let nodeID = store.createTerminal(frame: CGRect(x: 100, y: 120, width: 320, height: 240))
        let textID = store.createText(at: CGPoint(x: 220, y: 180), content: "deploy")
        store.setSelection([nodeID, textID])

        let frameID = try XCTUnwrap(store.wrapSelectionInFrame())

        let frameItem = try XCTUnwrap(store.frameItems.first(where: { $0.id == frameID }))
        XCTAssertEqual(Set(frameItem.childIDs), [nodeID, textID])
        XCTAssertEqual(store.selectedElementIDs, [frameID])

        let nodeFrame = try XCTUnwrap(store.nodes.first(where: { $0.id == nodeID })?.frame)
        XCTAssertTrue(frameItem.frame.contains(CGPoint(x: nodeFrame.midX, y: nodeFrame.midY)))
    }

    @MainActor
    func testMovingFrameMovesItsChildren() throws {
        let store = CanvasStore()
        let nodeID = store.createTerminal(frame: CGRect(x: 100, y: 100, width: 320, height: 240))
        let frameID = store.createFrame(frame: CGRect(x: 80, y: 80, width: 400, height: 320), childIDs: [nodeID])
        let originalNodeFrame = try XCTUnwrap(store.nodes.first(where: { $0.id == nodeID })?.frame)

        store.moveSelection(anchorID: frameID, byScreenDelta: CGPoint(x: 96, y: 48))

        let movedFrame = try XCTUnwrap(store.frameItems.first(where: { $0.id == frameID }))
        let movedNode = try XCTUnwrap(store.nodes.first(where: { $0.id == nodeID }))
        XCTAssertEqual(movedFrame.frame.origin.x, 176, accuracy: 0.0001)
        XCTAssertEqual(movedFrame.frame.origin.y, 128, accuracy: 0.0001)
        XCTAssertEqual(movedNode.frame.origin.x, originalNodeFrame.origin.x + 96, accuracy: 0.0001)
        XCTAssertEqual(movedNode.frame.origin.y, originalNodeFrame.origin.y + 48, accuracy: 0.0001)
    }

    @MainActor
    func testMovingSelectedChildDoesNotMoveSelectedParentFrame() throws {
        let store = CanvasStore()
        let nodeID = store.createTerminal(frame: CGRect(x: 100, y: 100, width: 320, height: 240))
        let frameID = store.createFrame(frame: CGRect(x: 80, y: 80, width: 400, height: 320), childIDs: [nodeID])
        let originalFrame = try XCTUnwrap(store.frameItems.first(where: { $0.id == frameID })?.frame)
        let originalNodeFrame = try XCTUnwrap(store.nodes.first(where: { $0.id == nodeID })?.frame)

        store.setSelection([frameID, nodeID])
        store.moveSelection(anchorID: nodeID, byScreenDelta: CGPoint(x: 72, y: 36))

        let movedFrame = try XCTUnwrap(store.frameItems.first(where: { $0.id == frameID })?.frame)
        let movedNode = try XCTUnwrap(store.nodes.first(where: { $0.id == nodeID })?.frame)
        XCTAssertEqual(movedFrame, originalFrame)
        XCTAssertEqual(movedNode.origin.x, originalNodeFrame.origin.x + 72, accuracy: 0.0001)
        XCTAssertEqual(movedNode.origin.y, originalNodeFrame.origin.y + 36, accuracy: 0.0001)
    }

    @MainActor
    func testDeletingFrameKeepsChildrenOnCanvas() throws {
        let store = CanvasStore()
        let nodeID = store.createTerminal(frame: CGRect(x: 60, y: 60, width: 320, height: 240))
        let frameID = store.createFrame(frame: CGRect(x: 40, y: 40, width: 400, height: 320), childIDs: [nodeID])
        store.setSelection([frameID])

        store.deleteSelection()

        XCTAssertTrue(store.nodes.contains(where: { $0.id == nodeID }))
        XCTAssertFalse(store.frameItems.contains(where: { $0.id == frameID }))
    }

    @MainActor
    func testStoreRestoresWorkspaceSnapshotAndCounter() throws {
        let restoredNode = TerminalNode(
            id: UUID(),
            title: "TERM 07",
            frame: CGRect(x: 80, y: 120, width: 520, height: 320)
        )
        let restoredFrame = CanvasFrameItem(
            id: UUID(),
            title: "FRAME 02",
            frame: CGRect(x: 40, y: 80, width: 620, height: 420),
            childIDs: [restoredNode.id]
        )
        let restoredText = CanvasTextItem(
            id: UUID(),
            text: "deploy notes",
            frame: CGRect(x: 40, y: 40, width: 200, height: 80),
            wrapWidth: 160
        )
        let snapshot = WorkspaceSnapshot(
            nodes: [restoredNode],
            frameItems: [restoredFrame],
            textItems: [restoredText],
            camera: CanvasCamera(zoom: 1.4, pan: CGPoint(x: 280, y: 190)),
            terminalCounter: 8,
            frameCounter: 3
        )
        let store = CanvasStore(snapshot: snapshot)

        XCTAssertEqual(store.nodes, [restoredNode])
        XCTAssertEqual(store.frameItems, [restoredFrame])
        XCTAssertEqual(store.textItems, [restoredText])
        XCTAssertEqual(store.camera, snapshot.camera)

        let newID = store.createTerminal(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let newNode = try XCTUnwrap(store.nodes.first(where: { $0.id == newID }))
        XCTAssertEqual(newNode.title, "TERM 08")

        let newFrameID = store.createFrame(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let newFrame = try XCTUnwrap(store.frameItems.first(where: { $0.id == newFrameID }))
        XCTAssertEqual(newFrame.title, "FRAME 03")
    }
}
