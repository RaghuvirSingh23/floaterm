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
}
