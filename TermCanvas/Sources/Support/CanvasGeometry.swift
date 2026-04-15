import AppKit
import Foundation

enum CanvasGeometry {
    static let minimumNodeSize = CGSize(width: 280, height: 190)
    static let defaultNodeSize = CGSize(width: 520, height: 320)
    static let minimumZoom: CGFloat = 0.35
    static let maximumZoom: CGFloat = 2.6
    static let baseGridStep: CGFloat = 48

    static func clampZoom(_ value: CGFloat) -> CGFloat {
        value.clamped(to: minimumZoom...maximumZoom)
    }

    static func worldToScreen(_ point: CGPoint, camera: CanvasCamera) -> CGPoint {
        CGPoint(
            x: point.x * camera.zoom + camera.pan.x,
            y: point.y * camera.zoom + camera.pan.y
        )
    }

    static func screenToWorld(_ point: CGPoint, camera: CanvasCamera) -> CGPoint {
        CGPoint(
            x: (point.x - camera.pan.x) / camera.zoom,
            y: (point.y - camera.pan.y) / camera.zoom
        )
    }

    static func worldToScreen(_ rect: CGRect, camera: CanvasCamera) -> CGRect {
        CGRect(
            origin: worldToScreen(rect.origin, camera: camera),
            size: CGSize(
                width: rect.width * camera.zoom,
                height: rect.height * camera.zoom
            )
        )
    }

    static func normalizedWorldRect(from startScreen: CGPoint, to endScreen: CGPoint, camera: CanvasCamera) -> CGRect {
        let startWorld = screenToWorld(startScreen, camera: camera)
        let endWorld = screenToWorld(endScreen, camera: camera)

        return CGRect(
            x: min(startWorld.x, endWorld.x),
            y: min(startWorld.y, endWorld.y),
            width: abs(endWorld.x - startWorld.x),
            height: abs(endWorld.y - startWorld.y)
        )
    }

    static func resized(frame: CGRect, handle: ResizeHandle, deltaInWorld: CGPoint) -> CGRect {
        var candidate = frame

        switch handle {
        case .topLeft:
            candidate.origin.x += deltaInWorld.x
            candidate.size.width -= deltaInWorld.x
            candidate.size.height += deltaInWorld.y
        case .top:
            candidate.size.height += deltaInWorld.y
        case .topRight:
            candidate.size.width += deltaInWorld.x
            candidate.size.height += deltaInWorld.y
        case .right:
            candidate.size.width += deltaInWorld.x
        case .bottomRight:
            candidate.size.width += deltaInWorld.x
            candidate.origin.y += deltaInWorld.y
            candidate.size.height -= deltaInWorld.y
        case .bottom:
            candidate.origin.y += deltaInWorld.y
            candidate.size.height -= deltaInWorld.y
        case .bottomLeft:
            candidate.origin.x += deltaInWorld.x
            candidate.size.width -= deltaInWorld.x
            candidate.origin.y += deltaInWorld.y
            candidate.size.height -= deltaInWorld.y
        case .left:
            candidate.origin.x += deltaInWorld.x
            candidate.size.width -= deltaInWorld.x
        }

        if candidate.width < minimumNodeSize.width {
            switch handle {
            case .topLeft, .bottomLeft, .left:
                candidate.origin.x = frame.maxX - minimumNodeSize.width
            default:
                break
            }

            candidate.size.width = minimumNodeSize.width
        }

        if candidate.height < minimumNodeSize.height {
            switch handle {
            case .bottomLeft, .bottomRight, .bottom:
                candidate.origin.y = frame.maxY - minimumNodeSize.height
            default:
                break
            }

            candidate.size.height = minimumNodeSize.height
        }

        return candidate.standardized
    }

    static func zoomed(camera: CanvasCamera, factor: CGFloat, anchorInScreen: CGPoint) -> CanvasCamera {
        let currentZoom = camera.zoom
        let nextZoom = clampZoom(camera.zoom * factor)

        guard nextZoom != currentZoom else {
            return camera
        }

        let worldAnchor = screenToWorld(anchorInScreen, camera: camera)
        let nextPan = CGPoint(
            x: anchorInScreen.x - worldAnchor.x * nextZoom,
            y: anchorInScreen.y - worldAnchor.y * nextZoom
        )

        return CanvasCamera(zoom: nextZoom, pan: nextPan)
    }

    static func adaptiveGridStep(for camera: CanvasCamera) -> CGFloat {
        var step = baseGridStep

        while step * camera.zoom < 18 {
            step *= 2
        }

        while step * camera.zoom > 160 {
            step /= 2
        }

        return step
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
