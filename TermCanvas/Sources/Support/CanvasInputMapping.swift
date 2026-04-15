import AppKit
import Foundation

enum CanvasInputMapping {
    static func mouseDragDelta(deltaX: CGFloat, deltaY: CGFloat) -> CGPoint {
        CGPoint(x: deltaX, y: -deltaY)
    }

    static func normalizedGestureDelta(scrollingDelta: CGPoint, directionInvertedFromDevice: Bool) -> CGPoint {
        let multiplier: CGFloat = directionInvertedFromDevice ? -1 : 1

        return CGPoint(
            x: scrollingDelta.x * multiplier,
            y: scrollingDelta.y * multiplier
        )
    }

    static func panDelta(for gestureDelta: CGPoint) -> CGPoint {
        // AppKit reports positive horizontal gesture deltas for leftward motion
        // and positive vertical deltas for upward motion.
        CGPoint(x: -gestureDelta.x, y: gestureDelta.y)
    }

    static func zoomFactor(for verticalGestureDelta: CGFloat) -> CGFloat {
        exp(verticalGestureDelta * 0.008)
    }
}
