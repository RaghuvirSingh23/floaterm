import SwiftUI

struct CanvasMinimapView: View {
    @ObservedObject var store: CanvasStore
    var isExpanded = false

    private let maximumMapSize = CGSize(width: 220, height: 152)
    private let minimumMapSize = CGSize(width: 168, height: 116)
    private let compactScale: CGFloat = 0.5

    var body: some View {
        let worldBounds = store.minimapWorldBounds
        let viewportRect = store.visibleWorldRect
        let mapSize = scaledMapSize(for: fittedMapSize(for: worldBounds.size))
        let cornerRadius = 16 * activeScale
        let padding = 10 * activeScale

        minimapCanvas(worldBounds: worldBounds, viewportRect: viewportRect, mapSize: mapSize)
            .frame(width: mapSize.width, height: mapSize.height)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.32))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 16, x: 0, y: 10)
            .help("Click or drag to pan the canvas")
    }

    private func minimapCanvas(worldBounds: CGRect, viewportRect: CGRect, mapSize: CGSize) -> some View {
        Canvas { context, size in
            let canvasRect = CGRect(origin: .zero, size: size)
            context.fill(Path(canvasRect), with: .color(Color.white.opacity(0.02)))

            for frameItem in store.frameItems {
                let rect = mapRect(for: frameItem.frame, in: worldBounds, size: size)
                let isSelected = store.selectedElementIDs.contains(frameItem.id)
                let path = Path(roundedRect: rect, cornerRadius: 4)
                context.stroke(
                    path,
                    with: .color(isSelected ? Color.orange.opacity(0.95) : Color.orange.opacity(0.55)),
                    style: StrokeStyle(lineWidth: isSelected ? 1.6 : 1.1, dash: isSelected ? [4, 3] : [])
                )
            }

            for node in store.nodes {
                let rect = mapRect(for: node.frame, in: worldBounds, size: size)
                let isSelected = store.selectedElementIDs.contains(node.id)
                let path = Path(roundedRect: rect, cornerRadius: 3)
                context.fill(path, with: .color(isSelected ? Color.white.opacity(0.26) : Color.white.opacity(0.14)))
                context.stroke(
                    path,
                    with: .color(isSelected ? Color(red: 0.75, green: 0.94, blue: 1.0) : Color.white.opacity(0.28)),
                    lineWidth: isSelected ? 1.5 : 1
                )
            }

            for item in store.textItems {
                let rect = mapRect(for: item.frame, in: worldBounds, size: size)
                let isSelected = store.selectedElementIDs.contains(item.id)
                let path = Path(roundedRect: rect, cornerRadius: 2)
                context.fill(
                    path,
                    with: .color(isSelected ? Color(red: 0.60, green: 0.92, blue: 1.0).opacity(0.55) : Color(red: 0.38, green: 0.78, blue: 1.0).opacity(0.32))
                )
            }

            let viewportPath = Path(roundedRect: mapRect(for: viewportRect, in: worldBounds, size: size), cornerRadius: 4)
            context.fill(viewportPath, with: .color(Color.white.opacity(0.06)))
            context.stroke(
                viewportPath,
                with: .color(Color.white.opacity(0.95)),
                style: StrokeStyle(lineWidth: 1.3, dash: [5, 4])
            )
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    centerViewport(at: value.location, worldBounds: worldBounds, mapSize: mapSize)
                }
        )
    }

    private func centerViewport(at location: CGPoint, worldBounds: CGRect, mapSize: CGSize) {
        guard mapSize.width > 0, mapSize.height > 0 else {
            return
        }

        let normalizedX = (location.x / mapSize.width).clamped(to: 0 ... 1)
        let normalizedY = (location.y / mapSize.height).clamped(to: 0 ... 1)
        let worldPoint = CGPoint(
            x: worldBounds.minX + normalizedX * worldBounds.width,
            y: worldBounds.maxY - normalizedY * worldBounds.height
        )
        store.centerCamera(on: worldPoint)
    }

    private func fittedMapSize(for worldSize: CGSize) -> CGSize {
        guard worldSize.width > 0, worldSize.height > 0 else {
            return minimumMapSize
        }

        let widthScale = maximumMapSize.width / worldSize.width
        let heightScale = maximumMapSize.height / worldSize.height
        let scale = min(widthScale, heightScale)
        let size = CGSize(width: worldSize.width * scale, height: worldSize.height * scale)

        return CGSize(
            width: max(minimumMapSize.width, size.width),
            height: max(minimumMapSize.height, size.height)
        )
    }

    private var activeScale: CGFloat {
        isExpanded ? 1 : compactScale
    }

    private func scaledMapSize(for size: CGSize) -> CGSize {
        CGSize(width: size.width * activeScale, height: size.height * activeScale)
    }

    private func mapRect(for worldRect: CGRect, in worldBounds: CGRect, size: CGSize) -> CGRect {
        let widthScale = size.width / max(worldBounds.width, 1)
        let heightScale = size.height / max(worldBounds.height, 1)

        return CGRect(
            x: (worldRect.minX - worldBounds.minX) * widthScale,
            y: (worldBounds.maxY - worldRect.maxY) * heightScale,
            width: max(worldRect.width * widthScale, 2),
            height: max(worldRect.height * heightScale, 2)
        )
    }
}

private extension CGFloat {
    func clamped(to limits: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, limits.lowerBound), limits.upperBound)
    }
}
