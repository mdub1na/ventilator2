import AppKit
import Darwin
import SwiftUI
import VentilatorCore

@main
enum VentilatorMain {
    static func main() {
        guard geteuid() != 0 else { fputs("Ventilator must run without root\n", stderr); exit(78) }
        if runHelperServiceCommand(Array(CommandLine.arguments.dropFirst())) { return }
        if runOwnerExperimentCommand(Array(CommandLine.arguments.dropFirst())) { return }
        if CommandLine.arguments.contains("--probe") {
            let snapshot = SMCMonitor.poll()
            print("Model: \(snapshot.modelIdentifier), macOS \(snapshot.macOSVersion) (\(snapshot.macOSBuild))")
            print("SMC available: \(snapshot.smcAvailable), fans: \(snapshot.fans.count)")
            for fan in snapshot.fans {
                let actual = probeNumber(fan.actualRPM)
                let target = probeNumber(fan.targetRPM)
                let minimum = probeNumber(fan.minimumRPM)
                let maximum = probeNumber(fan.maximumRPM)
                let mode = fan.modeCode.map { String($0) } ?? "n/a"
                print("Fan \(fan.index + 1): actual=\(actual) target=\(target) min=\(minimum) max=\(maximum) mode=\(mode)")
            }
            for temperature in snapshot.temperatures {
                print("\(temperature.label): \(probeNumber(temperature.celsius)) (\(temperature.source))")
            }
            return
        }
        let app = NSApplication.shared
        let delegate = VentilatorAppDelegate()
        app.delegate = delegate
        app.run()
    }

    private static func probeNumber(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "n/a"
    }
}

@MainActor
private final class VentilatorAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = MonitorStore()
    private var window: NSWindow?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 610),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Ventilator"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: MainWindowView(store: store))
        window.center()
        self.window = window
        statusItem = StatusItemController(
            showWindow: { [weak self] in self?.showWindow() },
            toggleWindow: { [weak self] in self?.toggleWindow() }
        )
        store.onSnapshot = { [weak self] snapshot in self?.statusItem?.update(snapshot) }
        store.start()
        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    private func showWindow() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func toggleWindow() {
        guard let window else { return }
        if window.isVisible { window.orderOut(nil) }
        else { showWindow() }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = appMenu.addItem(withTitle: "О Ventilator", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Настройки…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        let open = appMenu.addItem(withTitle: "Открыть окно", action: #selector(openWindow), keyEquivalent: "1")
        open.target = self
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "Выйти из Ventilator", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() { NSApp.orderFrontStandardAboutPanel(nil) }
    @objc private func openWindow() { showWindow() }
    @objc private func showSettings() { store.selectedSection = .application; showWindow() }
    @objc private func quit() { NSApp.terminate(nil) }
}
