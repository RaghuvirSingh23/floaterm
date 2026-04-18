import AppKit
import SwiftUI

@main
struct FloatermApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("floaterm", id: "main") {
            ContentView()
                .frame(minWidth: 1100, minHeight: 720)
        }
        .defaultSize(width: 1440, height: 920)
        .windowToolbarStyle(.unifiedCompact)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var isPoweringOff = false
    private weak var primaryWindow: NSWindow?
    private var pendingHideWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowBecameMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillPowerOff(_:)),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )

        for window in NSApp.windows {
            configureWindowIfNeeded(window)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard AppModel.shared.settings.terminalPersistenceMode == .keepRunningUntilShutdown else {
            return false
        }

        cancelPendingHide()

        guard !flag, let hiddenWindow = resolvedPrimaryWindow(in: sender) else {
            return false
        }

        revealWindow(hiddenWindow, in: sender)
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard AppModel.shared.settings.terminalPersistenceMode == .keepRunningUntilShutdown else {
            return
        }

        cancelPendingHide()

        guard
            let window = resolvedPrimaryWindow(in: NSApp),
            !window.isVisible || NSApp.isHidden
        else {
            return
        }

        revealWindow(window, in: NSApp)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppModel.shared.flushPersistence()

        guard
            AppModel.shared.settings.terminalPersistenceMode == .keepRunningUntilShutdown,
            !isPoweringOff
        else {
            return .terminateNow
        }

        deferAppHide()
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.flushPersistence()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard AppModel.shared.settings.terminalPersistenceMode == .keepRunningUntilShutdown else {
            return true
        }

        AppModel.shared.flushPersistence()
        deferAppHide()
        return false
    }

    @objc
    private func handleWindowBecameMain(_ notification: Notification) {
        configureWindowIfNeeded(notification.object as? NSWindow)
    }

    @objc
    private func handleWillPowerOff(_ notification: Notification) {
        isPoweringOff = true
    }

    private func configureWindowIfNeeded(_ window: NSWindow?) {
        guard let window else {
            return
        }

        window.delegate = self
        primaryWindow = window
    }

    private func deferAppHide() {
        guard pendingHideWorkItem == nil else {
            return
        }

        let hideWorkItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.pendingHideWorkItem = nil
            NSApp.hide(nil)
        }

        pendingHideWorkItem = hideWorkItem
        DispatchQueue.main.async(execute: hideWorkItem)
    }

    private func cancelPendingHide() {
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
    }

    private func resolvedPrimaryWindow(in application: NSApplication) -> NSWindow? {
        if let primaryWindow, application.windows.contains(where: { $0 === primaryWindow }) {
            return primaryWindow
        }

        let resolvedWindow = application.mainWindow
            ?? application.keyWindow
            ?? application.windows.first

        if let resolvedWindow {
            configureWindowIfNeeded(resolvedWindow)
        }

        return resolvedWindow
    }

    private func revealWindow(_ window: NSWindow, in application: NSApplication) {
        if application.isHidden {
            application.unhide(nil)
        }

        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
    }
}
