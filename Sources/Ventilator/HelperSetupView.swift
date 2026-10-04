import ServiceManagement
import SwiftUI
import VentilatorInstallation

struct HelperSetupView: View {
    @ObservedObject var model: HelperSetupModel
    var body: some View {
        HelperSetupContent(phase: model.phase, diagnostic: model.report?.error ?? model.report?.registrationDiagnostic,
            canRegister: model.canRegister, canOpenSettings: model.canOpenSettings,
            refresh: model.refresh, connect: model.connect,
            openSettings: { SMAppService.openSystemSettingsLoginItems() })
            .task { model.refreshIfNeeded() }
    }
}

struct HelperSetupContent: View {
    let phase: HelperSetupPhase
    let diagnostic: String?
    let canRegister: Bool
    let canOpenSettings: Bool
    let refresh: () -> Void
    let connect: () -> Void
    let openSettings: () -> Void
    var preview = false

    var body: some View {
        Section("Помощник") {
            LabeledContent("Состояние") {
                HStack(spacing: 8) {
                    if phase == .checking || phase == .registering { ProgressView().controlSize(.small) }
                    Text(title).multilineTextAlignment(.trailing)
                }
            }
            Text(explanation).foregroundStyle(.secondary)
            HStack {
                Button("Подключить помощник", action: connect).disabled(!canRegister || preview)
                Button("Открыть настройки macOS", action: openSettings).disabled(!canOpenSettings || preview)
            }
            Button("Проверить состояние", action: refresh)
                .disabled(phase == .checking || phase == .registering || preview)
            Text("Приложение продолжает наблюдение. Ручное управление будет доступно после отдельной проверки оборудования.")
                .font(.callout).foregroundStyle(.secondary)
            if let diagnostic {
                DisclosureGroup("Подробности проверки") {
                    Text(diagnostic).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            if preview { Text("Предпросмотр: действия отключены.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var title: String {
        switch phase {
        case .unchecked: "Не проверено"
        case .checking: "Проверяю состояние…"
        case .registering: "Подключаю…"
        case .unavailable: "Настройка недоступна в этой сборке"
        case .notRegistered: "Не подключён"
        case .requiresApproval: "Ожидает разрешения macOS"
        case .registered: "Зарегистрирован; соединение не проверено"
        case .verified: "Помощник доступен"
        case .connectionFailed: "Соединение не подтверждено"
        case .stopped: "Подключение приостановлено"
        }
    }
    private var explanation: String {
        switch phase {
        case .unchecked, .checking: "Проверяется установленная версия приложения и связь с помощником."
        case .registering: "macOS может показать запрос на разрешение фоновой службы."
        case .unavailable: "Для настройки нужна подписанная версия Ventilator, установленная в папке «Программы»."
        case .notRegistered: "Нажмите «Подключить помощник», чтобы запросить его регистрацию в macOS."
        case .requiresApproval: "Разрешите Ventilator в системном уведомлении. macOS может запросить пароль администратора. После подтверждения нажмите «Проверить состояние»."
        case .registered: "Регистрация включена. Чтобы подтвердить связь с помощником, проверьте состояние."
        case .verified: "Подпись и связь с установленным помощником проверены."
        case .connectionFailed: "Регистрация включена, но проверка связи не прошла. Данные отказа доступны ниже."
        case .stopped: "Предыдущая попытка сохранена. Для продолжения требуется разобрать причину отказа."
        }
    }
}
