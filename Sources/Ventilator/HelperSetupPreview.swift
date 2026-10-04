import AppKit
import SwiftUI
import VentilatorInstallation

/// Rendering fixture with no MonitorStore, SMC polling, framework status or registration actions.
@MainActor func runHelperSetupPreview(_ arguments: [String]) -> Bool {
    guard arguments.first == "--preview-helper-setup" else { return false }
    guard arguments.count == 2, let phase = HelperSetupPhase(rawValue: arguments[1]) else { exit(78) }
    let app = NSApplication.shared
    let delegate = HelperPreviewDelegate(phase: phase)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
    return true
}

@MainActor private final class HelperPreviewDelegate: NSObject, NSApplicationDelegate {
    let phase: HelperSetupPhase
    var window: NSWindow?
    init(phase: HelperSetupPhase) { self.phase = phase }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(), item = NSMenuItem(), submenu = NSMenu()
        submenu.addItem(withTitle: "Завершить предпросмотр", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu; menu.addItem(item); NSApp.mainMenu = menu
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 690, height: 510),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Ventilator — предпросмотр настройки"
        window.contentView = NSHostingView(rootView: Form {
            HelperSetupContent(phase: phase, diagnostic: phase == .connectionFailed ? "deadline" : nil,
                canRegister: false, canOpenSettings: false, refresh: {}, connect: {}, openSettings: {}, preview: true)
        }.formStyle(.grouped))
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
