import AppKit
import Foundation

enum CanvasGeometry {
    static let minimumNodeSize = CGSize(width: 280, height: 190)
    static let defaultNodeSize = CGSize(width: 520, height: 320)
    static let minimumTextHeight: CGFloat = 32
    static let textPadding = CGSize(width: 18, height: 10)
    static let minimumZoom: CGFloat = 0.35
    static let maximumZoom: CGFloat = 2.6
    static let baseGridStep: CGFloat = 48

    @MainActor
    static var textFont: NSFont {
        NSFont.systemFont(ofSize: 28, weight: .semibold)
    }

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
        resized(frame: frame, handle: handle, deltaInWorld: deltaInWorld, minimumSize: minimumNodeSize)
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

    @MainActor
    static func frameForText(_ text: String, origin: CGPoint) -> CGRect {
        let size = sizeForText(text, wrapWidth: nil)
        return CGRect(origin: origin, size: size)
    }

    @MainActor
    static func frameForText(_ text: String, centeredAt point: CGPoint) -> CGRect {
        let size = sizeForText(text, wrapWidth: nil)
        return CGRect(
            x: point.x - size.width * 0.5,
            y: point.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )
    }

    @MainActor
    static func sizeForText(_ text: String, wrapWidth: CGFloat?) -> CGSize {
        let normalized = text.isEmpty ? " " : text
        let measured = measuredTextSize(text: normalized, wrapWidth: wrapWidth)
        let paddedWidth = ceil(measured.width + textPadding.width)
        let paddedHeight = ceil(measured.height + textPadding.height)
        let minimumWidth = minimumTextFrameWidth(for: normalized)

        if let wrapWidth {
            return CGSize(
                width: max(minimumWidth, ceil(wrapWidth + textPadding.width)),
                height: max(minimumTextHeight, paddedHeight)
            )
        }

        return CGSize(
            width: paddedWidth,
            height: max(minimumTextHeight, paddedHeight)
        )
    }

    static func resizedText(frame: CGRect, handle: ResizeHandle, deltaInWorld: CGPoint, minimumWidth: CGFloat) -> CGRect {
        var candidate = frame

        switch handle {
        case .topLeft, .bottomLeft, .left:
            candidate.origin.x += deltaInWorld.x
            candidate.size.width -= deltaInWorld.x
        case .topRight, .bottomRight, .right:
            candidate.size.width += deltaInWorld.x
        case .top, .bottom:
            break
        }

        if candidate.size.width < minimumWidth {
            switch handle {
            case .topLeft, .bottomLeft, .left:
                candidate.origin.x = frame.maxX - minimumWidth
            default:
                break
            }

            candidate.size.width = minimumWidth
        }

        candidate.size.height = max(candidate.height, minimumTextHeight)
        return candidate.standardized
    }

    @MainActor
    static func minimumTextFrameWidth(for text: String) -> CGFloat {
        let normalized = text.isEmpty ? " " : text
        let widestFragmentWidth = normalized
            .split(whereSeparator: \.isNewline)
            .flatMap { line -> [Substring] in
                let words = line.split(whereSeparator: \.isWhitespace)
                return words.isEmpty ? [Substring(" ")] : words
            }
            .map { measuredTextSize(text: String($0), wrapWidth: nil).width }
            .max() ?? measuredTextSize(text: normalized, wrapWidth: nil).width

        return ceil(widestFragmentWidth + textPadding.width)
    }

    private static func resized(frame: CGRect, handle: ResizeHandle, deltaInWorld: CGPoint, minimumSize: CGSize) -> CGRect {
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

        if candidate.width < minimumSize.width {
            switch handle {
            case .topLeft, .bottomLeft, .left:
                candidate.origin.x = frame.maxX - minimumSize.width
            default:
                break
            }

            candidate.size.width = minimumSize.width
        }

        if candidate.height < minimumSize.height {
            switch handle {
            case .bottomLeft, .bottomRight, .bottom:
                candidate.origin.y = frame.maxY - minimumSize.height
            default:
                break
            }

            candidate.size.height = minimumSize.height
        }

        return candidate.standardized
    }

    @MainActor
    private static func measuredTextSize(text: String, wrapWidth: CGFloat?) -> CGSize {
        let constraint = CGSize(
            width: wrapWidth ?? CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let attributes: [NSAttributedString.Key: Any] = [.font: textFont]
        let rect = (text as NSString).boundingRect(with: constraint, options: options, attributes: attributes)

        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
