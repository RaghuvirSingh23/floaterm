import AppKit

struct GridSnap {
    static func snap(_ value: CGFloat, gridSize: CGFloat = Dimensions.gridSize, threshold: CGFloat = Dimensions.snapThreshold) -> (value: CGFloat, snapped: Bool) {
        let nearest = (value / gridSize).rounded() * gridSize
        if abs(value - nearest) <= threshold {
            return (nearest, true)
        }
        return (value, false)
    }

    static func snapPoint(_ point: CGPoint, gridSize: CGFloat = Dimensions.gridSize, threshold: CGFloat = Dimensions.snapThreshold) -> (point: CGPoint, snapped: Bool) {
        let sx = snap(point.x, gridSize: gridSize, threshold: threshold)
        let sy = snap(point.y, gridSize: gridSize, threshold: threshold)
        return (CGPoint(x: sx.value, y: sy.value), sx.snapped || sy.snapped)
    }

    static func hapticFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
}
