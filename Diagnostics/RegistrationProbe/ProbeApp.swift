import AppKit
import Darwin
import Foundation
import ServiceManagement
import SwiftUI

enum ProbeAction {
    /// Persistent marker precedes the sole mutation, including failed attempts.
    static func once(session: URL, name: String, action: () -> [String: Any]) throws -> [String: Any] {
        try ProbeBundle.save(["pid": getpid(), "hardwareWritesExecuted": 0], to: session.appendingPathComponent(name + "-started.json"))
        let result = action()
        try ProbeBundle.save(result, to: session.appendingPathComponent(name + ".json"))
        return result
    }
    static func name(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: "enabled"
        case .notRegistered: "notRegistered"
        case .notFound: "notFound"
        case .requiresApproval: "requiresApproval"
        @unknown default: "unknown"
        }
    }
    static func service() -> SMAppService { SMAppService.daemon(plistName: ProbeBundle.plistName) }
    static func report(_ service: SMAppService, error: Error? = nil) -> [String: Any] {
        var value: [String: Any] = ["registration": name(service.status), "hardwareWritesExecuted": 0, "hardwareControlAvailable": false]
        if let error { value["diagnostic"] = String(describing: error) }
        return value
    }
}

@MainActor final class ProbeModel: ObservableObject {
    let session: URL?
    @Published var text = "Тестовая служба ничего не читает и не изменяет в оборудовании."
    @Published var attempted = false
    init(session: URL?) { self.session = session }
    func register() {
        guard let session else { return }
        attempted = true
        do {
            // Recheck the installed process and owner seal immediately before the GUI action.
            _ = try ProbeBundle.session(session.path, proof: ProbeBundle.installedProcess())
            let result = try ProbeAction.once(session: session, name: "registration") {
                let service = ProbeAction.service()
                do { try service.register(); return ProbeAction.report(service) }
                catch { return ProbeAction.report(service, error: error) }
            }
            text = String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self)
        } catch { text = "Остановлено: \(error). Повтор запрещён." }
    }
    func refresh() {
        guard let session else { return }
        do {
            _ = try ProbeBundle.session(session.path, proof: ProbeBundle.installedProcess())
            text = "Статус службы: \(ProbeAction.name(ProbeAction.service().status))"
        } catch { text = "Остановлено: \(error)" }
    }
}

struct ProbeView: View {
    @ObservedObject var model: ProbeModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Проверка регистрации службы").font(.title2)
            Text("Это отдельное диагностическое приложение. Оно не управляет вентиляторами. Действия выполняйте по PLAN.md в Terminal.")
            ScrollView { Text(model.text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 120)
            HStack {
                Button("Зарегистрировать один раз") { model.register() }.disabled(model.session == nil || model.attempted)
                Button("Объекты входа…") { SMAppService.openSystemSettingsLoginItems() }.disabled(model.session == nil)
                Button("Прочитать статус") { model.refresh() }.disabled(model.session == nil)
            }
            if model.session == nil { Text("Предпросмотр: все действия со службой отключены.").foregroundStyle(.secondary) }
            Text("Если запрос Allow или подтверждение администратора не появился, сообщите NONE в Terminal. Переключатели других приложений не меняйте.").foregroundStyle(.secondary)
        }.padding(24).frame(width: 690, height: 420)
    }
}

@MainActor final class ProbeDelegate: NSObject, NSApplicationDelegate {
    let model: ProbeModel
    var window: NSWindow?
    init(session: URL?) { model = ProbeModel(session: session) }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(), item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); item.submenu = appMenu
        appMenu.addItem(withTitle: "Завершить проверку регистрации", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 690, height: 420), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Ventilator — отдельная проверка регистрации"
        window.contentView = NSHostingView(rootView: ProbeView(model: model)); window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window; NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main enum RegistrationProbe {
    @MainActor static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        do {
            guard geteuid() != 0 else { throw ProbeFailure.ownership }
            if args == ["--model-check"] {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: dir) }
                var calls = 0
                _ = try ProbeAction.once(session: dir, name: "registration") { calls += 1; return ["registration": "requiresApproval", "diagnostic": "model error 1"] }
                do { _ = try ProbeAction.once(session: dir, name: "registration") { calls += 1; return [:] }; throw ProbeFailure.replay }
                catch CocoaError.fileWriteFileExists { }
                guard calls == 1 else { throw ProbeFailure.replay }
                print("Probe action model: failed registration recorded, repeat refused before service call; no actual SMAppService invoked."); return
            }
            if args.count == 2 && ["--inspect-probe", "--qualify-probe"].contains(args[0]) {
                guard args[1].hasPrefix("/") else { throw ProbeFailure.layout }
                let proof = try ProbeBundle.inspect(URL(fileURLWithPath: args[1]), online: args[0] == "--qualify-probe")
                printJSON(["fingerprint": proof.fingerprint, "positiveRevocation": args[0] == "--qualify-probe", "team": ProbeBundle.team, "certificate": ProbeBundle.certificate]); return
            }
            if args == ["--preview"] {
                launch(session: nil); return
            }
            guard args.count == 2, ["--owner-probe-session", "--probe-status", "--probe-cleanup"].contains(args[0]), args[1].hasPrefix("/") else { throw ProbeFailure.session }
            let session = try ProbeBundle.session(args[1], proof: ProbeBundle.installedProcess())
            if args[0] == "--probe-status" { printJSON(ProbeAction.report(ProbeAction.service())); return }
            if args[0] == "--probe-cleanup" {
                let result = try ProbeAction.once(session: session, name: "cleanup") {
                    let service = ProbeAction.service()
                    do { if service.status != .notRegistered && service.status != .notFound { try service.unregister() }; return ProbeAction.report(service) }
                    catch { return ProbeAction.report(service, error: error) }
                }
                printJSON(result); if result["diagnostic"] != nil { exit(78) }; return
            }
            try ProbeBundle.save(["pid": getpid(), "hardwareWritesExecuted": 0], to: session.appendingPathComponent("gui.json"))
            launch(session: session)
        } catch { fputs("Registration probe stopped: \(error)\n", stderr); exit(78) }
    }
    @MainActor static func launch(session: URL?) {
        let app = NSApplication.shared, delegate = ProbeDelegate(session: session)
        app.delegate = delegate; withExtendedLifetime(delegate) { app.run() }
    }
    static func printJSON(_ value: [String: Any]) {
        print(String(decoding: try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
