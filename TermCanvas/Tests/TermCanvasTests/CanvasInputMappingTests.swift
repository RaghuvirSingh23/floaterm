import AppKit
import XCTest
@testable import TermCanvas

final class CanvasInputMappingTests: XCTestCase {
    func testNormalizedGestureDeltaCompensatesForNaturalScrolling() {
        let delta = CGPoint(x: 12, y: -8)

        XCTAssertEqual(
            CanvasInputMapping.normalizedGestureDelta(scrollingDelta: delta, directionInvertedFromDevice: false),
            delta
        )
        XCTAssertEqual(
            CanvasInputMapping.normalizedGestureDelta(scrollingDelta: delta, directionInvertedFromDevice: true),
            CGPoint(x: -12, y: 8)
        )
    }

    func testPanDeltaMatchesCanvasAxes() {
        let gesture = CGPoint(x: 15, y: 20)
        let pan = CanvasInputMapping.panDelta(for: gesture)

        XCTAssertEqual(pan.x, -15, accuracy: 0.0001)
        XCTAssertEqual(pan.y, 20, accuracy: 0.0001)
    }

    func testMouseDragDeltaFlipsVerticalAxisOnly() {
        let delta = CanvasInputMapping.mouseDragDelta(deltaX: 18, deltaY: 24)

        XCTAssertEqual(delta.x, 18, accuracy: 0.0001)
        XCTAssertEqual(delta.y, -24, accuracy: 0.0001)
    }

    func testZoomFactorGrowsForUpwardGesture() {
        XCTAssertGreaterThan(CanvasInputMapping.zoomFactor(for: 24), 1)
        XCTAssertLessThan(CanvasInputMapping.zoomFactor(for: -24), 1)
    }
}
