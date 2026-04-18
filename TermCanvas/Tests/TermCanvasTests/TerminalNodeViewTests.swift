import AppKit
import XCTest
@testable import TermCanvas

@MainActor
final class TerminalNodeViewTests: XCTestCase {
    func testHeaderCenterHitTestResolvesToDragStrip() throws {
        let (_, rootView, nodeView) = makeHostedNodeView()

        let titleLabel = try XCTUnwrap(findSubview(in: nodeView, as: PassiveLabelTextField.self))
        let dragStrip = try XCTUnwrap(findSubview(in: nodeView, as: DragHeaderView.self))
        let localPoint = nodeView.convert(CGPoint(x: titleLabel.bounds.midX, y: titleLabel.bounds.midY), from: titleLabel)
        let rootPoint = rootView.convert(localPoint, from: nodeView)
        let hitView = rootView.hitTest(rootPoint)

        XCTAssertTrue(hitView === dragStrip, "Expected header center hit-test to resolve to drag strip, got \(String(describing: hitView))")
    }

    func testPencilRegionClickKeepsTitleEditorVisible() throws {
        let (window, rootView, nodeView) = makeHostedNodeView()

        let iconView = try XCTUnwrap(findSubview(in: nodeView, as: IconClickView.self))
        let editor = try XCTUnwrap(findHiddenSubview(in: nodeView, as: InlineTitleEditorView.self))
        XCTAssertTrue(editor.isHidden)

        let localPoint = nodeView.convert(CGPoint(x: iconView.bounds.midX, y: iconView.bounds.midY), from: iconView)
        let rootPoint = rootView.convert(localPoint, from: nodeView)
        let hitView = try XCTUnwrap(rootView.hitTest(rootPoint))
        let windowPoint = rootView.convert(rootPoint, to: nil)
        let down = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: windowPoint,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
        let up = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: windowPoint,
                modifierFlags: [],
                timestamp: 0.01,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 0
            )
        )

        XCTAssertTrue(
            hitView is DragHeaderView || hitView is IconClickView,
            "Expected pencil region to resolve to header chrome, got \(type(of: hitView))"
        )

        hitView.mouseDown(with: down)
        hitView.mouseUp(with: up)

        let timeout = Date().addingTimeInterval(1.0)
        while !editor.isEditing, Date() < timeout {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertFalse(editor.isHidden)
        XCTAssertTrue(editor.isEditing)
    }

    func testSelectionOutlineVisibilityTracksSelection() throws {
        let (_, _, nodeView) = makeHostedNodeView()
        let selectionOutline = try XCTUnwrap(findSubview(in: nodeView, as: DashedSelectionOutlineView.self))

        XCTAssertTrue(selectionOutline.isHidden)

        nodeView.isSelected = true
        nodeView.layoutSubtreeIfNeeded()
        XCTAssertFalse(selectionOutline.isHidden)

        nodeView.isSelected = false
        nodeView.layoutSubtreeIfNeeded()
        XCTAssertTrue(selectionOutline.isHidden)
    }

    private func findSubview<T: NSView>(in root: NSView, as type: T.Type) -> T? {
        if let view = root as? T {
            return view
        }

        for subview in root.subviews {
            if let match = findSubview(in: subview, as: type) {
                return match
            }
        }

        return nil
    }

    private func findHiddenSubview<T: NSView>(in root: NSView, as type: T.Type) -> T? {
        if let view = root as? T, view.isHidden {
            return view
        }

        for subview in root.subviews {
            if let match = findHiddenSubview(in: subview, as: type) {
                return match
            }
        }

        return nil
    }

    private func makeHostedNodeView() -> (NSWindow, NSView, TerminalNodeView) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let rootView = NSView(frame: window.contentView?.bounds ?? .zero)
        rootView.autoresizingMask = [.width, .height]
        window.contentView = rootView

        let nodeView = TerminalNodeView(title: "TERM 0")
        nodeView.frame = CGRect(x: 120, y: 180, width: 520, height: 320)
        rootView.addSubview(nodeView)
        window.makeKeyAndOrderFront(nil)
        rootView.layoutSubtreeIfNeeded()
        nodeView.layoutSubtreeIfNeeded()
        return (window, rootView, nodeView)
    }
}
