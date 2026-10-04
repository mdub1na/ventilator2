import Combine
import Foundation
import VentilatorCore
import VentilatorInstallation

@MainActor
final class MonitorStore: ObservableObject {
    let helperSetup = HelperSetupModel()
    @Published private(set) var snapshot = MonitorSnapshot.placeholder
    @Published var selectedSection: AppSection = .overview

    var onSnapshot: ((MonitorSnapshot) -> Void)?
    private var timer: Timer?
    private var polling = false

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
