import Combine
import Foundation
import ServiceManagement
import VentilatorCore

@MainActor
final class MonitorStore: ObservableObject {
    @Published private(set) var snapshot = MonitorSnapshot.placeholder
    @Published private(set) var loginItemStatus = SMAppService.mainApp.status
    @Published var selectedSection: AppSection = .overview
    @Published var settingsError: String?

    var onSnapshot: ((MonitorSnapshot) -> Void)?
    private var timer: Timer?
    private var polling = false

    var launchAtLogin: Bool { loginItemStatus == .enabled }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 0.25
    }

    func refresh() {
        guard !polling else { return }
        polling = true
        Task.detached(priority: .utility) { [weak self] in
            let next = SMCMonitor.poll()
            await self?.finish(next)
        }
    }

    private func finish(_ next: MonitorSnapshot) {
        snapshot = next
        polling = false
        onSnapshot?(next)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            settingsError = nil
        } catch {
            settingsError = error.localizedDescription
        }
        loginItemStatus = SMAppService.mainApp.status
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Обзор"
    case fans = "Вентиляторы"
    case temperatures = "Температуры"
    case application = "Приложение"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .fans: "fanblades"
        case .temperatures: "thermometer.medium"
        case .application: "gearshape"
        }
    }
}
