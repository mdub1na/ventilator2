import SwiftUI
import VentilatorCore

struct MainWindowView: View {
    @ObservedObject var store: MonitorStore

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $store.selectedSection) { section in
                Label(section.rawValue, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Ventilator")
            .navigationSplitViewColumnWidth(min: 185, ideal: 210)
        } detail: {
            content
                .navigationTitle(store.selectedSection.rawValue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private var content: some View {
        switch store.selectedSection {
        case .overview: OverviewView(snapshot: store.snapshot)
        case .fans: FansView(snapshot: store.snapshot)
        case .temperatures: TemperaturesView(snapshot: store.snapshot)
        case .application: ApplicationView(store: store)
        }
    }
}

private struct OverviewView: View {
    let snapshot: MonitorSnapshot

    var body: some View {
        Form {
            Section("Температуры") {
                ForEach(snapshot.temperatures.filter { ["cpu", "gpu", "ssd"].contains($0.id) }) { reading in
                    LabeledContent(reading.label, value: formatTemperature(reading.celsius))
                }
            }
            Section("Вентиляторы") {
                if snapshot.fans.isEmpty {
                    Text(snapshot.smcAvailable ? "Вентиляторы не обнаружены" : "SMC недоступен")
                        .foregroundStyle(.secondary)
                }
                ForEach(snapshot.fans) { fan in
                    LabeledContent("Вентилятор \(fan.index + 1)", value: formatRPM(fan.actualRPM))
                }
            }
            Section("Управление") {
                LabeledContent("Текущий режим", value: modeSummary(snapshot.fans))
                Text("Ручное управление будет доступно после проверки на этом Mac.")
                    .foregroundStyle(.secondary)
            }
            Section("Устройство") {
                LabeledContent("Модель", value: snapshot.modelIdentifier)
                LabeledContent("macOS", value: "\(snapshot.macOSVersion) (\(snapshot.macOSBuild))")
            }
        }
        .formStyle(.grouped)
    }
}

private struct FansView: View {
    let snapshot: MonitorSnapshot

    var body: some View {
        Form {
            Section("Режим") {
                LabeledContent("Управление", value: modeSummary(snapshot.fans))
                HStack {
                    Button("Auto") {}
                        .disabled(true)
                    Button("Фиксированные обороты…") {}
                        .disabled(true)
                }
                Text("Команды управления заблокированы до проверки записи и возврата Auto на этой модели и версии macOS.")
                    .foregroundStyle(.secondary)
                Button("Вернуть Auto") {}
                    .disabled(true)
            }
            if snapshot.fans.isEmpty {
                Section("Обнаружение") {
                    Text(snapshot.smcAvailable ? "Вентиляторы не обнаружены" : "Чтение SMC недоступно")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(snapshot.fans) { fan in
                Section("Вентилятор \(fan.index + 1)") {
                    LabeledContent("Фактические обороты", value: formatRPM(fan.actualRPM))
                    LabeledContent("Цель", value: formatRPM(fan.targetRPM))
                    LabeledContent("Доступный диапазон", value: formatRange(fan))
                    LabeledContent("Режим SMC", value: fan.modeDescription)
                    if let level = fan.relativeLevel {
                        Gauge(value: Double(level), in: 0...5) {
                            Text("Относительный уровень")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TemperaturesView: View {
    let snapshot: MonitorSnapshot

    var body: some View {
        Form {
            Section("Основные показания") {
                ForEach(snapshot.temperatures.filter { ["cpu", "gpu", "ssd"].contains($0.id) }) { reading in
                    LabeledContent(reading.label) {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(formatTemperature(reading.celsius))
                            Text(reading.source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Другие датчики") {
                ForEach(snapshot.temperatures.filter { !["cpu", "gpu", "ssd"].contains($0.id) }) { reading in
                    LabeledContent(reading.label) {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(formatTemperature(reading.celsius))
                            Text("\(reading.source) · источник не установлен")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("Показания без подтверждённого физического источника не обозначаются как CPU, GPU или SSD.")
                .foregroundStyle(.secondary)
            Text("SSD: температура памяти NAND одного канала накопителя.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct ApplicationView: View {
    @ObservedObject var store: MonitorStore

    var body: some View {
        Form {
            Section("Запуск и значок") {
                LabeledContent("Открывать при входе в macOS", value: "Пока недоступно")
                LabeledContent("Значок в строке меню", value: "Показывать всегда")
                Text("Закрытие окна оставляет наблюдение работающим в строке меню.")
                    .foregroundStyle(.secondary)
            }
            HelperSetupView(model: store.helperSetup)
        }
        .formStyle(.grouped)
    }
}

private func formatTemperature(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "Нет данных" }
    return String(format: "%.1f °C", value)
}

private func formatRPM(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "Нет данных" }
    return "\(Int(value.rounded())) RPM"
}

private func formatRange(_ fan: FanReading) -> String {
    guard let minimum = fan.minimumRPM, let maximum = fan.maximumRPM else { return "Нет данных" }
    return "\(Int(minimum.rounded()))–\(Int(maximum.rounded())) RPM"
}

private func modeSummary(_ fans: [FanReading]) -> String {
    guard !fans.isEmpty else { return "Нет данных" }
    let modes = Set(fans.map(\.modeDescription))
    return modes.count == 1 ? (modes.first ?? "Нет данных") : "Разные режимы"
}
