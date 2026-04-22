import AppKit
import Combine
import Foundation

@MainActor
final class CanvasStore: ObservableObject {
    private let maximumNodeTitleLength = 20
    private let maximumFrameTitleLength = 40
    private let duplicateOffset = CGPoint(x: 48, y: -48)

    @Published private(set) var nodes: [TerminalNode] = []
    @Published private(set) var frameItems: [CanvasFrameItem] = []
    @Published private(set) var textItems: [CanvasTextItem] = []
    @Published private(set) var selectedElementIDs: Set<UUID> = []
    @Published var camera = CanvasCamera()
    @Published var tool: CanvasTool = .select
    @Published var isTerminalBroadcastEnabled = false
    @Published private(set) var viewportSize: CGSize = .zero
    @Published var pendingTextEditID: UUID?
    @Published var pendingTerminalFocusID: UUID?
    @Published private(set) var minimapActivityTick = 0

    private var terminalCounter = 1
    private var frameCounter = 1
    private var didSeedInitialNode = false

    init(snapshot: WorkspaceSnapshot? = nil) {
        if let snapshot {
            nodes = snapshot.nodes
            frameItems = snapshot.frameItems
            textItems = snapshot.textItems
            camera = snapshot.camera
            terminalCounter = max(snapshot.terminalCounter, snapshot.nodes.count + 1)
            frameCounter = max(snapshot.frameCounter, snapshot.frameItems.count + 1)
            sanitizeFrameMemberships()
            didSeedInitialNode = true
        }
    }

    var selectionCount: Int {
        selectedElementIDs.count
    }

    var selectedTerminalIDs: Set<UUID> {
        Set(nodes.lazy.filter { self.selectedElementIDs.contains($0.id) }.map(\.id))
    }

    var selectedTerminalCount: Int {
        selectedTerminalIDs.count
    }

    var canWrapSelectionInFrame: Bool {
        !selectedFrameableElementIDs.isEmpty
    }

    var canBroadcastSelectedTerminals: Bool {
        selectedTerminalCount > 1
    }

    var visibleWorldRect: CGRect {
        CanvasGeometry.visibleWorldRect(camera: camera, viewportSize: viewportSize)
    }

    var contentBounds: CGRect? {
        CanvasGeometry.union(of: frameItems.map(\.frame) + nodes.map(\.frame) + textItems.map(\.frame))
    }

    var minimapWorldBounds: CGRect {
        CanvasGeometry.minimapWorldBounds(contentBounds: contentBounds, visibleRect: visibleWorldRect)
    }

    var workspaceSnapshot: WorkspaceSnapshot {
        WorkspaceSnapshot(
            nodes: nodes,
            frameItems: frameItems,
            textItems: textItems,
            camera: camera,
            terminalCounter: terminalCounter,
            frameCounter: frameCounter
        )
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
        let standardizedFrame = frame.standardized
        let normalizedFrame = CGRect(
            x: standardizedFrame.origin.x,
            y: standardizedFrame.origin.y,
            width: max(standardizedFrame.width, CanvasGeometry.minimumNodeSize.width),
            height: max(standardizedFrame.height, CanvasGeometry.minimumNodeSize.height)
        )

        let nodeID = appendTerminalNode(
            title: String(format: "TERM %02d", terminalCounter),
            frame: normalizedFrame
        )
        setSelection([nodeID])
        return nodeID
    }

    @discardableResult
    func createFrame(frame: CGRect, childIDs: Set<UUID> = []) -> UUID {
        let standardizedFrame = frame.standardized
        let normalizedFrame = CGRect(
            x: standardizedFrame.origin.x,
            y: standardizedFrame.origin.y,
            width: max(standardizedFrame.width, CanvasGeometry.minimumFrameSize.width),
            height: max(standardizedFrame.height, CanvasGeometry.minimumFrameSize.height)
        )
        let memberIDs = orderedFrameableElementIDs(in: childIDs)
        detachElementsFromFrames(Set(memberIDs))

        let frameID = appendFrameItem(
            title: String(format: "FRAME %02d", frameCounter),
            frame: normalizedFrame,
            childIDs: memberIDs
        )
        setSelection([frameID])
        return frameID
    }

    @discardableResult
    func createText(at point: CGPoint, content: String = "") -> UUID {
        let itemID = appendTextItem(
            text: content,
            frame: CanvasGeometry.frameForText(content, centeredAt: point),
            wrapWidth: nil
        )
        setSelection([itemID])
        pendingTextEditID = itemID
        return itemID
    }

    @discardableResult
    func wrapSelectionInFrame() -> UUID? {
        let childIDs = selectedFrameableElementIDs
        let childFrames = orderedFrameableElementIDs(in: childIDs).compactMap { frame(for: $0) }
        guard let boundingRect = childFrames.reduce(nil, { partial, frame in
            partial.map { $0.union(frame) } ?? frame
        }) else {
            return nil
        }

        let paddedFrame = CGRect(
            x: boundingRect.minX - CanvasGeometry.frameWrapInsets.left,
            y: boundingRect.minY - CanvasGeometry.frameWrapInsets.bottom,
            width: boundingRect.width + CanvasGeometry.frameWrapInsets.left + CanvasGeometry.frameWrapInsets.right,
            height: boundingRect.height + CanvasGeometry.frameWrapInsets.top + CanvasGeometry.frameWrapInsets.bottom
        )

        return createFrame(frame: paddedFrame, childIDs: childIDs)
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

    func duplicateSelection() {
        guard !selectedElementIDs.isEmpty else {
            return
        }

        let selectedFrameIDs = Set(frameItems.lazy.filter { self.selectedElementIDs.contains($0.id) }.map(\.id))
        let framedChildIDs = Set(selectedFrameIDs.flatMap { self.childIDs(forFrameID: $0) })
        let standaloneContentIDs = frameableElementIDs(in: selectedElementIDs).subtracting(framedChildIDs)
        var duplicatedIDs: Set<UUID> = []

        for node in nodes where standaloneContentIDs.contains(node.id) {
            let duplicatedID = appendTerminalNode(
                title: node.title,
                frame: node.frame.offsetBy(dx: duplicateOffset.x, dy: duplicateOffset.y)
            )
            duplicatedIDs.insert(duplicatedID)
        }

        for item in textItems where standaloneContentIDs.contains(item.id) {
            let duplicatedID = appendTextItem(
                text: item.text,
                frame: item.frame.offsetBy(dx: duplicateOffset.x, dy: duplicateOffset.y),
                wrapWidth: item.wrapWidth
            )
            duplicatedIDs.insert(duplicatedID)
        }

        for frameItem in frameItems where selectedFrameIDs.contains(frameItem.id) {
            var duplicatedChildIDs: [UUID] = []

            for childID in frameItem.childIDs {
                if let node = nodes.first(where: { $0.id == childID }) {
                    let duplicatedID = appendTerminalNode(
                        title: node.title,
                        frame: node.frame.offsetBy(dx: duplicateOffset.x, dy: duplicateOffset.y)
                    )
                    duplicatedChildIDs.append(duplicatedID)
                    duplicatedIDs.insert(duplicatedID)
                } else if let item = textItems.first(where: { $0.id == childID }) {
                    let duplicatedID = appendTextItem(
                        text: item.text,
                        frame: item.frame.offsetBy(dx: duplicateOffset.x, dy: duplicateOffset.y),
                        wrapWidth: item.wrapWidth
                    )
                    duplicatedChildIDs.append(duplicatedID)
                    duplicatedIDs.insert(duplicatedID)
                }
            }

            detachElementsFromFrames(Set(duplicatedChildIDs))
            let duplicatedFrameID = appendFrameItem(
                title: frameItem.title,
                frame: frameItem.frame.offsetBy(dx: duplicateOffset.x, dy: duplicateOffset.y),
                childIDs: duplicatedChildIDs
            )
            duplicatedIDs.insert(duplicatedFrameID)
        }

        guard !duplicatedIDs.isEmpty else {
            return
        }

        setSelection(duplicatedIDs)
        registerMinimapActivity()
    }

    func setTerminalBroadcastEnabled(_ enabled: Bool) {
        isTerminalBroadcastEnabled = enabled && canBroadcastSelectedTerminals
    }

    func requestFocusOnSelectedTerminal() {
        pendingTerminalFocusID = nodes.last(where: { selectedElementIDs.contains($0.id) })?.id
    }

    func acknowledgePendingTerminalFocus(id: UUID) {
        guard pendingTerminalFocusID == id else {
            return
        }

        pendingTerminalFocusID = nil
    }

    func terminalBroadcastTargetIDs(forOriginID originID: UUID) -> [UUID] {
        guard
            isTerminalBroadcastEnabled,
            canBroadcastSelectedTerminals,
            selectedTerminalIDs.contains(originID)
        else {
            return []
        }

        return nodes
            .map(\.id)
            .filter { selectedTerminalIDs.contains($0) && $0 != originID }
    }

    func deleteSelection() {
        guard !selectedElementIDs.isEmpty else {
            return
        }

        let deletedIDs = selectedElementIDs
        let deletedFrameIDs = Set(frameItems.lazy.filter { deletedIDs.contains($0.id) }.map(\.id))
        let deletedContentIDs = frameableElementIDs(in: deletedIDs)

        nodes.removeAll { deletedIDs.contains($0.id) }
        textItems.removeAll { deletedIDs.contains($0.id) }
        frameItems.removeAll { deletedFrameIDs.contains($0.id) }
        detachElementsFromFrames(deletedContentIDs)
        selectedElementIDs.removeAll()
        normalizeTerminalBroadcastState()
    }

    func removeNode(id: UUID) {
        nodes.removeAll { $0.id == id }
        detachElementsFromFrames([id])
        selectedElementIDs.remove(id)
        normalizeTerminalBroadcastState()
    }

    func removeFrame(id: UUID) {
        frameItems.removeAll { $0.id == id }
        selectedElementIDs.remove(id)
        normalizeTerminalBroadcastState()
    }

    func selectNode(_ id: UUID?) {
        setSelection(id.map { [$0] } ?? [])
    }

    func activateElement(_ id: UUID, extendSelection: Bool = false) {
        if extendSelection {
            var nextSelection = selectedElementIDs
            if nextSelection.contains(id) {
                nextSelection.remove(id)
            } else {
                nextSelection.insert(id)
            }
            setSelection(nextSelection)
            return
        }

        if selectedElementIDs.contains(id) {
            bringSelectionToFront()
        } else {
            setSelection([id])
        }
    }

    func setSelection(_ ids: Set<UUID>) {
        selectedElementIDs = ids
        normalizeTerminalBroadcastState()
        bringSelectionToFront()
    }

    func clearSelection() {
        selectedElementIDs.removeAll()
        normalizeTerminalBroadcastState()
    }

    func selectAllElements() {
        let allIDs = Set(frameItems.map(\.id))
            .union(nodes.map(\.id))
            .union(textItems.map(\.id))
        setSelection(allIDs)
    }

    func cycleSelection(backward: Bool = false) {
        let orderedIDs = selectionCycleOrder
        guard !orderedIDs.isEmpty else {
            return
        }

        let orderedSelectedIDs = orderedIDs.filter { selectedElementIDs.contains($0) }
        let nextID: UUID

        if let anchorID = backward ? orderedSelectedIDs.first : orderedSelectedIDs.last,
           let currentIndex = orderedIDs.firstIndex(of: anchorID)
        {
            let offset = backward ? -1 : 1
            let nextIndex = (currentIndex + offset + orderedIDs.count) % orderedIDs.count
            nextID = orderedIDs[nextIndex]
        } else {
            nextID = backward ? orderedIDs.last! : orderedIDs.first!
        }

        setSelection([nextID])
    }

    func selectElements(intersecting rect: CGRect, append: Bool = false) {
        let hitIDs = Set(frameItems.lazy.filter { rect.intersects($0.frame) }.map(\.id))
            .union(nodes.lazy.filter { rect.intersects($0.frame) }.map(\.id))
            .union(textItems.lazy.filter { rect.intersects($0.frame) }.map(\.id))

        if append {
            selectedElementIDs.formUnion(hitIDs)
        } else {
            selectedElementIDs = hitIDs
        }

        normalizeTerminalBroadcastState()
        bringSelectionToFront()
    }

    func renameNode(id: UUID, title: String) {
        let normalized = String(
            title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maximumNodeTitleLength)
        )
        guard !normalized.isEmpty else {
            return
        }

        mutateNode(id: id) { node in
            node.title = normalized
        }
    }

    func renameFrame(id: UUID, title: String) {
        let normalized = String(
            title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maximumFrameTitleLength)
        )
        guard !normalized.isEmpty else {
            return
        }

        mutateFrame(id: id) { frameItem in
            frameItem.title = normalized
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
            detachElementsFromFrames([id])
            selectedElementIDs.remove(id)
            pendingTextEditID = nil
            normalizeTerminalBroadcastState()
            return
        }

        mutateTextItem(id: id) { item in
            item.text = content
            item.frame.size = CanvasGeometry.sizeForText(content, wrapWidth: item.wrapWidth)
        }
        updateFrameMemberships(for: [id])
    }

    @discardableResult
    func resizeTextItem(id: UUID, handle: ResizeHandle, byScreenDelta delta: CGPoint) -> CanvasSnapState {
        let deltaInWorld = CGPoint(x: delta.x / camera.zoom, y: delta.y / camera.zoom)
        let step = CanvasGeometry.adaptiveGridStep(for: camera)
        let threshold = CanvasGeometry.gridSnapThreshold(for: camera)
        var feedbackState = CanvasSnapState.none

        mutateTextItem(id: id) { item in
            let minimumWidth = CanvasGeometry.minimumTextFrameWidth(for: item.text)
            let resizedFrame = CanvasGeometry.resizedText(
                frame: item.frame,
                handle: handle,
                deltaInWorld: deltaInWorld,
                minimumWidth: minimumWidth
            )
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

            switch handle {
            case .topLeft, .bottomLeft, .left:
                feedbackState.x = CanvasGeometry.snappedValue(item.frame.minX, step: step, threshold: threshold)
            case .topRight, .bottomRight, .right:
                feedbackState.x = CanvasGeometry.snappedValue(item.frame.maxX, step: step, threshold: threshold)
            case .top, .bottom:
                break
            }
        }

        updateFrameMemberships(for: [id])
        registerMinimapActivity()
        return feedbackState
    }

    @discardableResult
    func moveSelection(anchorID: UUID, byScreenDelta delta: CGPoint) -> CanvasSnapState {
        let targetIDs = moveTargetIDs(forAnchorID: anchorID)
        return moveElements(ids: targetIDs, anchorID: anchorID, byScreenDelta: delta)
    }

    @discardableResult
    func moveTextItem(id: UUID, byScreenDelta delta: CGPoint) -> CanvasSnapState {
        moveElements(ids: [id], anchorID: id, byScreenDelta: delta)
    }

    @discardableResult
    func moveNode(id: UUID, byScreenDelta delta: CGPoint) -> CanvasSnapState {
        moveSelection(anchorID: id, byScreenDelta: delta)
    }

    @discardableResult
    func resizeNode(id: UUID, handle: ResizeHandle, byScreenDelta delta: CGPoint) -> CanvasSnapState {
        let deltaInWorld = CGPoint(x: delta.x / camera.zoom, y: delta.y / camera.zoom)
        let step = CanvasGeometry.adaptiveGridStep(for: camera)
        let threshold = CanvasGeometry.gridSnapThreshold(for: camera)
        var feedbackState = CanvasSnapState.none

        mutateNode(id: id) { node in
            node.frame = CanvasGeometry.resized(frame: node.frame, handle: handle, deltaInWorld: deltaInWorld)

            switch handle {
            case .topLeft, .bottomLeft, .left:
                feedbackState.x = CanvasGeometry.snappedValue(node.frame.minX, step: step, threshold: threshold)
            case .topRight, .bottomRight, .right:
                feedbackState.x = CanvasGeometry.snappedValue(node.frame.maxX, step: step, threshold: threshold)
            case .top, .bottom:
                break
            }

            switch handle {
            case .topLeft, .topRight, .top:
                feedbackState.y = CanvasGeometry.snappedValue(node.frame.maxY, step: step, threshold: threshold)
            case .bottomLeft, .bottomRight, .bottom:
                feedbackState.y = CanvasGeometry.snappedValue(node.frame.minY, step: step, threshold: threshold)
            case .left, .right:
                break
            }
        }

        updateFrameMemberships(for: [id])
        registerMinimapActivity()
        return feedbackState
    }

    @discardableResult
    func resizeFrame(id: UUID, handle: ResizeHandle, byScreenDelta delta: CGPoint) -> CanvasSnapState {
        let deltaInWorld = CGPoint(x: delta.x / camera.zoom, y: delta.y / camera.zoom)
        let step = CanvasGeometry.adaptiveGridStep(for: camera)
        let threshold = CanvasGeometry.gridSnapThreshold(for: camera)
        var feedbackState = CanvasSnapState.none

        mutateFrame(id: id) { frameItem in
            frameItem.frame = CanvasGeometry.resizedFrameItem(frame: frameItem.frame, handle: handle, deltaInWorld: deltaInWorld)

            switch handle {
            case .topLeft, .bottomLeft, .left:
                feedbackState.x = CanvasGeometry.snappedValue(frameItem.frame.minX, step: step, threshold: threshold)
            case .topRight, .bottomRight, .right:
                feedbackState.x = CanvasGeometry.snappedValue(frameItem.frame.maxX, step: step, threshold: threshold)
            case .top, .bottom:
                break
            }

            switch handle {
            case .topLeft, .topRight, .top:
                feedbackState.y = CanvasGeometry.snappedValue(frameItem.frame.maxY, step: step, threshold: threshold)
            case .bottomLeft, .bottomRight, .bottom:
                feedbackState.y = CanvasGeometry.snappedValue(frameItem.frame.minY, step: step, threshold: threshold)
            case .left, .right:
                break
            }
        }

        registerMinimapActivity()
        return feedbackState
    }

    func panBy(_ delta: CGPoint) {
        camera.pan.x += delta.x
        camera.pan.y += delta.y
        registerMinimapActivity()
    }

    func setPan(_ value: CGPoint) {
        camera.pan = value
        registerMinimapActivity()
    }

    func zoom(by factor: CGFloat, around anchorInScreen: CGPoint) {
        camera = CanvasGeometry.zoomed(camera: camera, factor: factor, anchorInScreen: anchorInScreen)
        registerMinimapActivity()
    }

    func resetZoom() {
        let preferredBounds = bounds(for: selectedElementIDs) ?? contentBounds
        let preferredFocusPoint = preferredBounds.map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
        centerCamera(on: preferredFocusPoint, zoom: 1)
    }

    func centerCamera(on worldPoint: CGPoint, zoom: CGFloat? = nil) {
        let nextZoom = zoom.map(CanvasGeometry.clampZoom) ?? camera.zoom

        guard viewportSize.width > 0, viewportSize.height > 0 else {
            camera.zoom = nextZoom
            return
        }

        camera = CanvasCamera(
            zoom: nextZoom,
            pan: CanvasGeometry.centeredPan(for: worldPoint, viewportSize: viewportSize, zoom: nextZoom)
        )
        registerMinimapActivity()
    }

    private var selectedFrameableElementIDs: Set<UUID> {
        frameableElementIDs(in: selectedElementIDs)
    }

    private var selectionCycleOrder: [UUID] {
        struct CycleEntry {
            let id: UUID
            let frame: CGRect
            let priority: Int
        }

        let entries =
            nodes.map { CycleEntry(id: $0.id, frame: $0.frame, priority: 0) } +
            textItems.map { CycleEntry(id: $0.id, frame: $0.frame, priority: 1) } +
            frameItems.map { CycleEntry(id: $0.id, frame: $0.frame, priority: 2) }

        return entries
            .sorted { lhs, rhs in
                if abs(lhs.frame.minX - rhs.frame.minX) > 0.001 {
                    return lhs.frame.minX < rhs.frame.minX
                }
                if abs(lhs.frame.maxY - rhs.frame.maxY) > 0.001 {
                    return lhs.frame.maxY > rhs.frame.maxY
                }
                return lhs.priority < rhs.priority
            }
            .map(\.id)
    }

    private func normalizeTerminalBroadcastState() {
        guard !isTerminalBroadcastEnabled || !canBroadcastSelectedTerminals else {
            return
        }

        isTerminalBroadcastEnabled = false
    }

    private func registerMinimapActivity() {
        minimapActivityTick &+= 1
    }

    private func moveTargetIDs(forAnchorID anchorID: UUID) -> Set<UUID> {
        guard selectedElementIDs.contains(anchorID) else {
            return [anchorID]
        }

        if isFrameID(anchorID) {
            let selectedFrameIDs = Set(frameItems.lazy.filter { self.selectedElementIDs.contains($0.id) }.map(\.id))
            return selectedFrameIDs.isEmpty ? [anchorID] : selectedFrameIDs
        }

        if isFrameableElementID(anchorID) {
            let selectedContentIDs = frameableElementIDs(in: selectedElementIDs)
            return selectedContentIDs.isEmpty ? [anchorID] : selectedContentIDs
        }

        return [anchorID]
    }

    private func moveElements(ids: Set<UUID>, anchorID: UUID, byScreenDelta delta: CGPoint) -> CanvasSnapState {
        let deltaInWorld = CGPoint(x: delta.x / camera.zoom, y: delta.y / camera.zoom)
        let movingFrameIDs = Set(frameItems.lazy.filter { ids.contains($0.id) }.map(\.id))
        let childIDsOwnedByMovingFrames = Set(movingFrameIDs.flatMap { childIDs(forFrameID: $0) })
        let independentlyMovedIDs = ids.subtracting(childIDsOwnedByMovingFrames)

        for frameID in movingFrameIDs {
            mutateFrame(id: frameID) { frameItem in
                frameItem.frame.origin.x += deltaInWorld.x
                frameItem.frame.origin.y += deltaInWorld.y
            }

            moveFrameChildren(frameID: frameID, deltaInWorld: deltaInWorld)
        }

        let independentlyMovedContentIDs = frameableElementIDs(in: independentlyMovedIDs)
        for id in independentlyMovedContentIDs {
            guard !childIDsOwnedByMovingFrames.contains(id) else {
                continue
            }

            mutateNode(id: id) { node in
                node.frame.origin.x += deltaInWorld.x
                node.frame.origin.y += deltaInWorld.y
            }

            mutateTextItem(id: id) { item in
                item.frame.origin.x += deltaInWorld.x
                item.frame.origin.y += deltaInWorld.y
            }
        }

        updateFrameMemberships(for: independentlyMovedContentIDs)

        guard let anchorFrame = frame(for: anchorID) else {
            return .none
        }

        let step = CanvasGeometry.adaptiveGridStep(for: camera)
        let threshold = CanvasGeometry.gridSnapThreshold(for: camera)
        var feedbackState = CanvasSnapState.none

        if abs(deltaInWorld.x) > 0.0001 {
            feedbackState.x = CanvasGeometry.snappedValue(anchorFrame.origin.x, step: step, threshold: threshold)
        }

        if abs(deltaInWorld.y) > 0.0001 {
            feedbackState.y = CanvasGeometry.snappedValue(anchorFrame.origin.y, step: step, threshold: threshold)
        }

        registerMinimapActivity()
        return feedbackState
    }

    private func moveFrameChildren(frameID: UUID, deltaInWorld: CGPoint) {
        for id in childIDs(forFrameID: frameID) {
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

    private func updateFrameMemberships(for ids: Set<UUID>) {
        let candidateIDs = orderedFrameableElementIDs(in: ids)
        guard !candidateIDs.isEmpty else {
            return
        }

        detachElementsFromFrames(Set(candidateIDs))

        for id in candidateIDs {
            guard
                let elementFrame = frame(for: id),
                let frameIndex = bestContainingFrameIndex(for: elementFrame)
            else {
                continue
            }

            if !frameItems[frameIndex].childIDs.contains(id) {
                frameItems[frameIndex].childIDs.append(id)
            }
        }
    }

    private func bestContainingFrameIndex(for childFrame: CGRect) -> Int? {
        let center = CGPoint(x: childFrame.midX, y: childFrame.midY)

        return frameItems.enumerated()
            .filter { $0.element.frame.contains(center) }
            .min { lhs, rhs in
                lhs.element.frame.width * lhs.element.frame.height < rhs.element.frame.width * rhs.element.frame.height
            }?
            .offset
    }

    private func frameableElementIDs(in ids: Set<UUID>) -> Set<UUID> {
        let nodeIDs = Set(nodes.lazy.filter { ids.contains($0.id) }.map(\.id))
        let textIDs = Set(textItems.lazy.filter { ids.contains($0.id) }.map(\.id))
        return nodeIDs.union(textIDs)
    }

    private func isFrameID(_ id: UUID) -> Bool {
        frameItems.contains { $0.id == id }
    }

    private func isFrameableElementID(_ id: UUID) -> Bool {
        nodes.contains { $0.id == id } || textItems.contains { $0.id == id }
    }

    private func orderedFrameableElementIDs(in ids: Set<UUID>) -> [UUID] {
        let orderedNodes = nodes.filter { ids.contains($0.id) }.map(\.id)
        let orderedText = textItems.filter { ids.contains($0.id) }.map(\.id)
        return orderedNodes + orderedText
    }

    private func bounds(for ids: Set<UUID>) -> CGRect? {
        CanvasGeometry.union(of:
            frameItems.filter { ids.contains($0.id) }.map(\.frame) +
            nodes.filter { ids.contains($0.id) }.map(\.frame) +
            textItems.filter { ids.contains($0.id) }.map(\.frame)
        )
    }

    private func childIDs(forFrameID id: UUID) -> [UUID] {
        frameItems.first(where: { $0.id == id })?.childIDs ?? []
    }

    private func detachElementsFromFrames(_ ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }

        for index in frameItems.indices {
            frameItems[index].childIDs.removeAll { ids.contains($0) }
        }
    }

    private func sanitizeFrameMemberships() {
        let liveElementIDs = Set(nodes.map(\.id)).union(textItems.map(\.id))
        var seenIDs: Set<UUID> = []

        for index in frameItems.indices {
            frameItems[index].childIDs = frameItems[index].childIDs.filter { id in
                guard liveElementIDs.contains(id), !seenIDs.contains(id) else {
                    return false
                }

                seenIDs.insert(id)
                return true
            }
        }
    }

    private func bringSelectionToFront() {
        guard !selectedElementIDs.isEmpty else {
            return
        }

        let selectedFrames = frameItems.filter { selectedElementIDs.contains($0.id) }
        frameItems.removeAll { selectedElementIDs.contains($0.id) }
        frameItems.append(contentsOf: selectedFrames)

        let selectedNodes = nodes.filter { selectedElementIDs.contains($0.id) }
        nodes.removeAll { selectedElementIDs.contains($0.id) }
        nodes.append(contentsOf: selectedNodes)

        let selectedTextItems = textItems.filter { selectedElementIDs.contains($0.id) }
        textItems.removeAll { selectedElementIDs.contains($0.id) }
        textItems.append(contentsOf: selectedTextItems)
    }

    private func appendTerminalNode(title: String, frame: CGRect) -> UUID {
        let node = TerminalNode(
            id: UUID(),
            title: title,
            frame: frame
        )
        terminalCounter += 1
        nodes.append(node)
        updateFrameMemberships(for: [node.id])
        return node.id
    }

    private func appendFrameItem(title: String, frame: CGRect, childIDs: [UUID]) -> UUID {
        let frameItem = CanvasFrameItem(
            id: UUID(),
            title: title,
            frame: frame,
            childIDs: childIDs
        )
        frameCounter += 1
        frameItems.append(frameItem)
        return frameItem.id
    }

    private func appendTextItem(text: String, frame: CGRect, wrapWidth: CGFloat?) -> UUID {
        let item = CanvasTextItem(
            id: UUID(),
            text: text,
            frame: frame,
            wrapWidth: wrapWidth
        )
        textItems.append(item)
        updateFrameMemberships(for: [item.id])
        return item.id
    }

    private func mutateNode(id: UUID, _ mutate: (inout TerminalNode) -> Void) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&nodes[index])
    }

    private func mutateFrame(id: UUID, _ mutate: (inout CanvasFrameItem) -> Void) {
        guard let index = frameItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&frameItems[index])
    }

    private func mutateTextItem(id: UUID, _ mutate: (inout CanvasTextItem) -> Void) {
        guard let index = textItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&textItems[index])
    }

    private func frame(for id: UUID) -> CGRect? {
        if let frameItem = frameItems.first(where: { $0.id == id }) {
            return frameItem.frame
        }

        if let node = nodes.first(where: { $0.id == id }) {
            return node.frame
        }

        if let textItem = textItems.first(where: { $0.id == id }) {
            return textItem.frame
        }

        return nil
    }
}
