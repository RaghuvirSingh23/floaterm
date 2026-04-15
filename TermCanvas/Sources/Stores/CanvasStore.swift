import AppKit
import Combine
import Foundation

@MainActor
final class CanvasStore: ObservableObject {
    @Published private(set) var nodes: [TerminalNode] = []
    @Published var camera = CanvasCamera()
    @Published var selectedNodeID: UUID?
    @Published var tool: CanvasTool = .select
    @Published private(set) var viewportSize: CGSize = .zero

    private var terminalCounter = 1
    private var didSeedInitialNode = false

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
        selectedNodeID = node.id
        return node.id
    }

    func removeSelectedNode() {
        guard let selectedNodeID else {
            return
        }

        removeNode(id: selectedNodeID)
    }

    func removeNode(id: UUID) {
        nodes.removeAll { $0.id == id }

        if selectedNodeID == id {
            selectedNodeID = nodes.last?.id
        }
    }

    func selectNode(_ id: UUID?) {
        selectedNodeID = id

        guard let id, let index = nodes.firstIndex(where: { $0.id == id }) else {
            return
        }

        let node = nodes.remove(at: index)
        nodes.append(node)
    }

    func moveNode(id: UUID, byScreenDelta delta: CGPoint) {
        let deltaInWorld = CGPoint(x: delta.x / camera.zoom, y: delta.y / camera.zoom)

        mutateNode(id: id) { node in
            node.frame.origin.x += deltaInWorld.x
            node.frame.origin.y += deltaInWorld.y
        }
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

    private func mutateNode(id: UUID, _ mutate: (inout TerminalNode) -> Void) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&nodes[index])
    }
}
