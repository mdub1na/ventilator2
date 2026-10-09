import AppKit
import SwiftUI
import VentilatorInstallation

/// Rendering fixture with no MonitorStore, SMC polling, framework status or registration actions.
@MainActor func runHelperSetupPreview(_ arguments: [String]) -> Bool {
    let render = arguments.first == "--render-helper-setup"
    guard render || arguments.first == "--preview-helper-setup" else { return false }
    guard arguments.count == (render ? 3 : 2), let phase = HelperSetupPhase(rawValue: arguments[1]) else { exit(78) }
    let app = NSApplication.shared
    if render {
        do { try renderHelperSetup(phase, path: arguments[2]) }
        catch { fputs("Helper setup render: \(error)\n", stderr); exit(78) }
        return true
    }
    let delegate = HelperPreviewDelegate(phase: phase)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
    return true
}

@MainActor private func helperSetupFixture(_ phase: HelperSetupPhase) -> some View {
    Form {
        HelperSetupContent(phase: phase, diagnostic: phase == .connectionFailed ? "deadline" : nil,
            canRegister: false, canOpenSettings: false, refresh: {}, connect: {}, openSettings: {}, preview: true)
    }.formStyle(.grouped)
}

/// Offscreen artifact rendering exits before the normal app/MonitorStore can initialize.
@MainActor private func renderHelperSetup(_ phase: HelperSetupPhase, path: String) throws {
    guard path.hasPrefix("/") else { throw CocoaError(.fileWriteInvalidFileName) }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 690, height: 510),
                          styleMask: [], backing: .buffered, defer: false)
    let view = NSHostingView(rootView: helperSetupFixture(phase))
    view.appearance = NSAppearance(named: .aqua)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)
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
        window.contentView = NSHostingView(rootView: helperSetupFixture(phase))
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
