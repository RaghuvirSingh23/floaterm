import AppKit
import Combine
import Foundation

@MainActor
final class CanvasStore: ObservableObject {
    @Published private(set) var nodes: [TerminalNode] = []
    @Published private(set) var textItems: [CanvasTextItem] = []
    @Published private(set) var selectedElementIDs: Set<UUID> = []
    @Published var camera = CanvasCamera()
    @Published var tool: CanvasTool = .select
    @Published private(set) var viewportSize: CGSize = .zero
    @Published var pendingTextEditID: UUID?

    private var terminalCounter = 1
    private var didSeedInitialNode = false

    var selectionCount: Int {
        selectedElementIDs.count
    }

    func seedInitialNodeIfNeeded() {
        guard !didSeedInitialNode else {
            return
        }

        let initialFrame = CGRect(
            x: -CanvasGeometry.defaultNodeSize.width * 0.5,
            y: -CanvasGeometry.defaultNodeSize.height * 0.5,
            width: CanvasGeometry.defaultNodeSize.width,
            height: CanvasGeometry.defaultNodeSize.height
        )

        _ = createTerminal(frame: initialFrame)
        didSeedInitialNode = true
    }

    func updateViewportSize(_ size: CGSize) {
        guard viewportSize != size else {
            return
        }

        viewportSize = size
    }

    func bootstrapCameraIfNeeded(center: CGPoint) {
        guard camera.pan == .zero else {
            return
        }

        camera.pan = center
    }

    func spawnPresetTerminal() {
        let centerPoint = CGPoint(x: viewportSize.width * 0.5, y: viewportSize.height * 0.5)
        let centerWorld = CanvasGeometry.screenToWorld(centerPoint, camera: camera)
        let frame = CGRect(
            x: centerWorld.x - CanvasGeometry.defaultNodeSize.width * 0.5,
            y: centerWorld.y - CanvasGeometry.defaultNodeSize.height * 0.5,
            width: CanvasGeometry.defaultNodeSize.width,
            height: CanvasGeometry.defaultNodeSize.height
        )

        _ = createTerminal(frame: frame)
    }

    @discardableResult
    func createTerminal(frame: CGRect) -> UUID {
        let normalizedFrame = CGRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: max(frame.width, CanvasGeometry.minimumNodeSize.width),
            height: max(frame.height, CanvasGeometry.minimumNodeSize.height)
        )

        let node = TerminalNode(
            id: UUID(),
            title: String(format: "TERM %02d", terminalCounter),
            frame: normalizedFrame
        )
        terminalCounter += 1

        nodes.append(node)
        setSelection([node.id])
        return node.id
    }

    @discardableResult
    func createText(at point: CGPoint, content: String = "") -> UUID {
        let item = CanvasTextItem(
            id: UUID(),
            text: content,
            frame: CanvasGeometry.frameForText(content, centeredAt: point),
            wrapWidth: nil
        )

        textItems.append(item)
        setSelection([item.id])
        pendingTextEditID = item.id
        return item.id
    }

    func acknowledgePendingTextEdit(id: UUID) {
        guard pendingTextEditID == id else {
            return
        }

        pendingTextEditID = nil
    }

    func removeSelectedNode() {
        deleteSelection()
    }

    func deleteSelection() {
        guard !selectedElementIDs.isEmpty else {
            return
        }

        let deletedIDs = selectedElementIDs
        nodes.removeAll { deletedIDs.contains($0.id) }
        textItems.removeAll { deletedIDs.contains($0.id) }
        selectedElementIDs.removeAll()
    }

    func removeNode(id: UUID) {
        nodes.removeAll { $0.id == id }
        selectedElementIDs.remove(id)
    }

    func selectNode(_ id: UUID?) {
        setSelection(id.map { [$0] } ?? [])
    }

    func activateElement(_ id: UUID) {
        if selectedElementIDs.contains(id) {
            bringSelectionToFront()
        } else {
            setSelection([id])
        }
    }

    func setSelection(_ ids: Set<UUID>) {
        selectedElementIDs = ids
        bringSelectionToFront()
    }

    func clearSelection() {
        selectedElementIDs.removeAll()
    }

    func selectElements(intersecting rect: CGRect, append: Bool = false) {
        let hitIDs = Set(nodes.lazy.filter { rect.intersects($0.frame) }.map(\.id))
            .union(textItems.lazy.filter { rect.intersects($0.frame) }.map(\.id))

        if append {
            selectedElementIDs.formUnion(hitIDs)
        } else {
            selectedElementIDs = hitIDs
        }

        bringSelectionToFront()
    }

    func renameNode(id: UUID, title: String) {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        mutateNode(id: id) { node in
            node.title = normalized
        }
    }

    func updateTextDraft(id: UUID, content: String) {
        mutateTextItem(id: id) { item in
            item.text = content
            item.frame.size = CanvasGeometry.sizeForText(content, wrapWidth: item.wrapWidth)
        }
    }

    func commitText(id: UUID, content: String) {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            textItems.removeAll { $0.id == id }
            selectedElementIDs.remove(id)
            pendingTextEditID = nil
            return
        }

        mutateTextItem(id: id) { item in
            item.text = content
            item.frame.size = CanvasGeometry.sizeForText(content, wrapWidth: item.wrapWidth)
        }
    }

    func resizeTextItem(id: UUID, handle: ResizeHandle, byScreenDelta delta: CGPoint) {
        let deltaInWorld = CGPoint(x: delta.x / camera.zoom, y: delta.y / camera.zoom)

        mutateTextItem(id: id) { item in
            let resizedFrame = CanvasGeometry.resizedText(frame: item.frame, handle: handle, deltaInWorld: deltaInWorld)
            let wrapWidth = max(1, resizedFrame.width - CanvasGeometry.textPadding.width)
            let measuredSize = CanvasGeometry.sizeForText(item.text, wrapWidth: wrapWidth)

            item.wrapWidth = wrapWidth
            item.frame.origin.x = resizedFrame.origin.x
            item.frame.size = measuredSize

            if case .left = handle {
                item.frame.origin.x = resizedFrame.maxX - measuredSize.width
            } else if case .topLeft = handle {
                item.frame.origin.x = resizedFrame.maxX - measuredSize.width
            } else if case .bottomLeft = handle {
                item.frame.origin.x = resizedFrame.maxX - measuredSize.width
            }
        }
    }

    func moveSelection(anchorID: UUID, byScreenDelta delta: CGPoint) {
        let targetIDs = selectedElementIDs.contains(anchorID) ? selectedElementIDs : [anchorID]
        moveElements(ids: targetIDs, byScreenDelta: delta)
    }

    func moveTextItem(id: UUID, byScreenDelta delta: CGPoint) {
        moveElements(ids: [id], byScreenDelta: delta)
    }

    func moveNode(id: UUID, byScreenDelta delta: CGPoint) {
        moveSelection(anchorID: id, byScreenDelta: delta)
    }

    func resizeNode(id: UUID, handle: ResizeHandle, byScreenDelta delta: CGPoint) {
        let deltaInWorld = CGPoint(x: delta.x / camera.zoom, y: delta.y / camera.zoom)

        mutateNode(id: id) { node in
            node.frame = CanvasGeometry.resized(frame: node.frame, handle: handle, deltaInWorld: deltaInWorld)
        }
    }

    func panBy(_ delta: CGPoint) {
        camera.pan.x += delta.x
        camera.pan.y += delta.y
    }

    func setPan(_ value: CGPoint) {
        camera.pan = value
    }

    func zoom(by factor: CGFloat, around anchorInScreen: CGPoint) {
        camera = CanvasGeometry.zoomed(camera: camera, factor: factor, anchorInScreen: anchorInScreen)
    }

    func resetZoom() {
        camera.zoom = 1
    }

    private func moveElements(ids: Set<UUID>, byScreenDelta delta: CGPoint) {
        let deltaInWorld = CGPoint(x: delta.x / camera.zoom, y: delta.y / camera.zoom)

        for id in ids {
            mutateNode(id: id) { node in
                node.frame.origin.x += deltaInWorld.x
                node.frame.origin.y += deltaInWorld.y
            }

            mutateTextItem(id: id) { item in
                item.frame.origin.x += deltaInWorld.x
                item.frame.origin.y += deltaInWorld.y
            }
        }
    }

    private func bringSelectionToFront() {
        guard !selectedElementIDs.isEmpty else {
            return
        }

        let selectedNodes = nodes.filter { selectedElementIDs.contains($0.id) }
        nodes.removeAll { selectedElementIDs.contains($0.id) }
        nodes.append(contentsOf: selectedNodes)

        let selectedTextItems = textItems.filter { selectedElementIDs.contains($0.id) }
        textItems.removeAll { selectedElementIDs.contains($0.id) }
        textItems.append(contentsOf: selectedTextItems)
    }

    private func mutateNode(id: UUID, _ mutate: (inout TerminalNode) -> Void) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&nodes[index])
    }

    private func mutateTextItem(id: UUID, _ mutate: (inout CanvasTextItem) -> Void) {
        guard let index = textItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&textItems[index])
    }
}
