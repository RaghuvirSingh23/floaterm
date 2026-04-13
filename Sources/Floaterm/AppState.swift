import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var boxes: [TerminalBox] = []
    @Published var shapes: [CanvasShape] = []
    @Published var transform = CanvasTransform()
    @Published var activeTool: Tool = .draw
    @Published var theme: Theme = .light
    @Published var focusedBoxId: String?

    // MARK: - Box management

    func addBox(_ box: TerminalBox) {
        var b = box
        b.focused = true
        boxes.indices.forEach { boxes[$0].focused = false }
        boxes.append(b)
        focusedBoxId = b.id
    }

    func removeBox(id: String) {
        boxes.removeAll { $0.id == id }
        if focusedBoxId == id {
            focusedBoxId = boxes.last?.id
            if let last = focusedBoxId {
                if let idx = boxes.firstIndex(where: { $0.id == last }) {
                    boxes[idx].focused = true
                }
            }
        }
    }

    func focusBox(id: String) {
        focusedBoxId = id
        boxes.indices.forEach { boxes[$0].focused = boxes[$0].id == id }
    }

    func boxIndex(id: String) -> Int? {
        boxes.firstIndex(where: { $0.id == id })
    }

    var existingIds: [String] {
        boxes.map(\.id)
    }

    // MARK: - Shape management

    func addShape(_ shape: CanvasShape) {
        shapes.append(shape)
    }

    func removeShape(id: UUID) {
        shapes.removeAll { $0.id == id }
    }

    // MARK: - Spawn helpers

    func spawnInCenter(windowSize: CGSize) -> TerminalBox {
        let offset = CGFloat(boxes.count) * Dimensions.spawnCascadeOffset
        let cx = windowSize.width / 2
        let cy = windowSize.height / 2
        let w = Dimensions.defaultTerminalWidth
        let h = Dimensions.defaultTerminalHeight
        let world = transform.screenToWorld(
            sx: cx - w / 2 + offset,
            sy: cy - h / 2 + offset
        )
        return TerminalBox(
            x: world.x, y: world.y,
            w: w / transform.scale, h: h / transform.scale,
            existingIds: existingIds
        )
    }

    func spawnWithCommand(label: String, windowSize: CGSize) -> TerminalBox {
        // Deduplicate label
        let existing = boxes.filter { $0.label == label || $0.label.hasPrefix("\(label)-") }
        let finalLabel = existing.isEmpty ? label : "\(label)-\(existing.count + 1)"

        let offset = CGFloat(boxes.count) * Dimensions.spawnCascadeOffset
        let cx = windowSize.width / 2
        let cy = windowSize.height / 2
        let w: CGFloat = 600
        let h: CGFloat = 420
        let world = transform.screenToWorld(
            sx: cx - w / 2 + offset,
            sy: cy - h / 2 + offset
        )
        return TerminalBox(
            x: world.x, y: world.y,
            w: w / transform.scale, h: h / transform.scale,
            label: finalLabel,
            existingIds: existingIds
        )
    }
}
