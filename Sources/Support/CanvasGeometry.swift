import AppKit
import Foundation

enum CanvasGeometry {
    static let minimumNodeSize = CGSize(width: 280, height: 190)
    static let defaultNodeSize = CGSize(width: 520, height: 320)
    static let minimumFrameSize = CGSize(width: 260, height: 180)
    static let defaultFrameSize = CGSize(width: 540, height: 360)
    static let frameWrapInsets = NSEdgeInsets(top: 40, left: 24, bottom: 24, right: 24)
    static let minimumTextHeight: CGFloat = 32
    static let textPadding = CGSize(width: 18, height: 10)
    static let minimumZoom: CGFloat = 0.35
    static let maximumZoom: CGFloat = 2.6
    static let baseGridStep: CGFloat = 48
    static let snapThresholdInScreenPoints: CGFloat = 10

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

    static func visibleWorldRect(camera: CanvasCamera, viewportSize: CGSize) -> CGRect {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return .zero
        }

        return CGRect(
            origin: CGPoint(
                x: -camera.pan.x / camera.zoom,
                y: -camera.pan.y / camera.zoom
            ),
            size: CGSize(
                width: viewportSize.width / camera.zoom,
                height: viewportSize.height / camera.zoom
            )
        )
    }

    static func centeredPan(for worldPoint: CGPoint, viewportSize: CGSize, zoom: CGFloat) -> CGPoint {
        CGPoint(
            x: viewportSize.width * 0.5 - worldPoint.x * zoom,
            y: viewportSize.height * 0.5 - worldPoint.y * zoom
        )
    }

    static func union(of rects: [CGRect]) -> CGRect? {
        rects.reduce(nil) { partialResult, rect in
            guard !rect.isNull, !rect.isEmpty else {
                return partialResult
            }

            return partialResult.map { $0.union(rect) } ?? rect
        }
    }

    static func minimapWorldBounds(contentBounds: CGRect?, visibleRect: CGRect) -> CGRect {
        let baseBounds = union(of: [contentBounds, visibleRect].compactMap { $0 }) ?? CGRect(
            x: -defaultFrameSize.width * 0.5,
            y: -defaultFrameSize.height * 0.5,
            width: defaultFrameSize.width,
            height: defaultFrameSize.height
        )

        let padding = max(baseGridStep * 2, min(baseBounds.width, baseBounds.height) * 0.12)
        let paddedBounds = baseBounds.insetBy(dx: -padding, dy: -padding)
        let minimumWidth = max(visibleRect.width * 1.1, defaultFrameSize.width)
        let minimumHeight = max(visibleRect.height * 1.1, defaultFrameSize.height)

        guard paddedBounds.width < minimumWidth || paddedBounds.height < minimumHeight else {
            return paddedBounds
        }

        let expandedSize = CGSize(
            width: max(paddedBounds.width, minimumWidth),
            height: max(paddedBounds.height, minimumHeight)
        )

        return CGRect(
            x: paddedBounds.midX - expandedSize.width * 0.5,
            y: paddedBounds.midY - expandedSize.height * 0.5,
            width: expandedSize.width,
            height: expandedSize.height
        )
    }

    static func resized(frame: CGRect, handle: ResizeHandle, deltaInWorld: CGPoint) -> CGRect {
        resized(frame: frame, handle: handle, deltaInWorld: deltaInWorld, minimumSize: minimumNodeSize)
    }

    static func resizedFrameItem(frame: CGRect, handle: ResizeHandle, deltaInWorld: CGPoint) -> CGRect {
        resized(frame: frame, handle: handle, deltaInWorld: deltaInWorld, minimumSize: minimumFrameSize)
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

    static func gridSnapThreshold(for camera: CanvasCamera) -> CGFloat {
        snapThresholdInScreenPoints / camera.zoom
    }

    static func snappedValue(_ value: CGFloat, step: CGFloat, threshold: CGFloat) -> CGFloat? {
        let snapped = (value / step).rounded() * step
        return abs(value - snapped) <= threshold ? snapped : nil
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
