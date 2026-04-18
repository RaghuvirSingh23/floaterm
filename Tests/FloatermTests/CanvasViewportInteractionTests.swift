import AppKit
import XCTest
@testable import Floaterm

@MainActor
final class CanvasViewportInteractionTests: XCTestCase {
    func testTerminalWinsHitTestingOverFrame() throws {
        let store = CanvasStore()
        store.tool = .select
        let nodeID = store.createTerminal(frame: CGRect(x: 140, y: 120, width: 360, height: 240))
        _ = store.createFrame(frame: CGRect(x: 80, y: 80, width: 520, height: 360), childIDs: [nodeID])

        let (_, rootView, viewport) = makeHostedViewport(store: store)
        let nodeView = try XCTUnwrap(findSubview(in: viewport, as: TerminalNodeView.self))
        let hitView = try XCTUnwrap(
            waitForHitView(in: rootView) {
                let localPoint = CGPoint(x: nodeView.bounds.midX, y: nodeView.bounds.midY)
                let rootPoint = rootView.convert(localPoint, from: nodeView)
                return rootView.hitTest(rootPoint)
            }
        )

        XCTAssertNotNil(findAncestor(of: hitView, as: TerminalNodeView.self))
        XCTAssertFalse(hitView is CanvasFrameItemView, "Expected terminal layer to win hit-testing, got \(type(of: hitView))")
    }

    func testEmptyFrameInteriorHitsFrameInSelectTool() throws {
        let store = CanvasStore()
        store.tool = .select
        _ = store.createFrame(frame: CGRect(x: 120, y: 110, width: 420, height: 300))

        let (_, rootView, viewport) = makeHostedViewport(store: store)
        let frameView = try XCTUnwrap(findSubview(in: viewport, as: CanvasFrameItemView.self))
        let localPoint = CGPoint(x: frameView.bounds.midX, y: frameView.bounds.midY)
        let rootPoint = rootView.convert(localPoint, from: frameView)
        let hitView = try XCTUnwrap(rootView.hitTest(rootPoint))

        XCTAssertTrue(hitView === frameView, "Expected empty frame interior to hit the frame, got \(type(of: hitView))")
    }

    func testFrameBecomesPassiveForTerminalTool() throws {
        let store = CanvasStore()
        store.tool = .terminal
        _ = store.createFrame(frame: CGRect(x: 120, y: 110, width: 420, height: 300))

        let (_, rootView, viewport) = makeHostedViewport(store: store)
        let frameView = try XCTUnwrap(findSubview(in: viewport, as: CanvasFrameItemView.self))
        let localPoint = CGPoint(x: frameView.bounds.midX, y: frameView.bounds.midY)
        let rootPoint = rootView.convert(localPoint, from: frameView)
        let hitView = try XCTUnwrap(rootView.hitTest(rootPoint))

        XCTAssertFalse(hitView is CanvasFrameItemView, "Expected frame to be passive in terminal mode, got \(type(of: hitView))")
    }

    private func makeHostedViewport(store: CanvasStore) -> (NSWindow, NSView, CanvasViewportView) {
        let suiteName = "CanvasViewportInteractionTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        userDefaults.removePersistentDomain(forName: suiteName)
        let appModel = AppModel(
            settings: AppSettingsStore(userDefaults: userDefaults),
            persistenceController: WorkspacePersistenceController(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json"),
                saveDelay: 60
            )
        )

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let rootView = NSView(frame: window.contentView?.bounds ?? .zero)
        rootView.autoresizingMask = [.width, .height]
        window.contentView = rootView

        let viewport = CanvasViewportView(frame: rootView.bounds)
        viewport.autoresizingMask = [.width, .height]
        rootView.addSubview(viewport)
        viewport.apply(store: store, appModel: appModel)
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        rootView.layoutSubtreeIfNeeded()
        rootView.displayIfNeeded()
        viewport.layoutSubtreeIfNeeded()
        viewport.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return (window, rootView, viewport)
    }

    private func waitForHitView(in rootView: NSView, timeout: TimeInterval = 1.0, resolver: () -> NSView?) -> NSView? {
        let deadline = Date().addingTimeInterval(timeout)
        var hitView = resolver()

        while hitView == nil, Date() < deadline {
            rootView.window?.displayIfNeeded()
            rootView.layoutSubtreeIfNeeded()
            rootView.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            hitView = resolver()
        }

        return hitView
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

    private func findAncestor<T: NSView>(of view: NSView, as type: T.Type) -> T? {
        var current: NSView? = view
        while let candidate = current {
            if let typed = candidate as? T {
                return typed
            }
            current = candidate.superview
        }
        return nil
    }
}
