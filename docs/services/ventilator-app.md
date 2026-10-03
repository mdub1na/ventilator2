---
id: ventilator-app
title: Нативное приложение Ventilator
type: service
module: Ventilator
tech_stack: [Swift, SwiftUI, AppKit, IOKit, SwiftPM]
owner: unassigned
repo_url: https://github.com/mdub1na/ventilator2
depends_on: [AppleSMC]
publishes: [Ventilator.app]
---

# Приложение

## Ответственность

SwiftPM собирает `VentilatorCore` с read-only C-транспортами `CSMCRead`, `CHIDTemperature` и исполняемый `Ventilator`. Core открывает AppleSMC, читает количество вентиляторов и ключи каждого, декодирует только известные типы. HID независимо читает подтверждённый датчик NAND на точном профиле модели/ОС. Главное приложение опрашивает Core каждые две секунды вне главного потока и передаёт снимок окну и значку. Сетевых интерфейсов и хранилища пользовательских данных нет.

Root-owned signed bundle установлен в `/Applications/Ventilator.app`, но живой привилегированный помощник ещё не подтверждён: owner setup остановился на requiresApproval; последующий read-only status=enabled/remoteFailure, launchd job отсутствует. [Последние факты](../research/evidence/owner-setup-service-state.json). Bundle содержит [прототип helper](ventilator-helper.md), не подключённый к обычному окну/значку; пути записи из GUI нет. App CLI содержит signed/installed диагностику и явные lifecycle команды; [проверки и ограничения](../features/feature-helper-installation.md). Fresh wrapper сохраняет requiresApproval без автоматического unregister/register и запрещает повтор остановленной попытки. Приложение не допускает root. Подготовленный writer находится в отдельных модулях, которые GUI не линкует; аппаратный старт helper закрыт. Вызовы `SMAppService.mainApp` присутствуют для будущего автозапуска, но переключатель пока отключён.

Wrapper поддерживает installed continuation полного owner review для exact уже установленного unstarted bundle. Admission отказывает до app invocation при runtime/job/changed hash; файлы установки в этом mode не меняются. Owner-only setup выполняет bounded one-shot register, затем ready только после enabled. Root review import может потребовать owner sudo; одобрение/аппаратный start выполняются отдельно. Новый пакет подготовлен и qualified без новой подписи, положительный installed root XPC ещё ожидается. [Проверки и границы](../research/evidence/owner-installed-continuation.json).

Владелец собрал административный snapshot: root job отсутствует (113), BTM child enabled/allowed, parent UID -2/501 pending authorization, runtime root отсутствует. [Снимок](../research/evidence/owner-registration-administrative-snapshot.json). Diagnostics wrapper теперь также готовит отдельный сеанс одного ручного off/on только Ventilator с последующим snapshot. До UI действия проверяются exact предыдущие доказательства/owner UID и отсутствие runtime/job; non-root TTY и exclusive marker обязательны. После DONE root используется для двух фиксированных чтений с exec alarm. Wrapper не запускает app/helper; отчёт сохраняет только Ventilator identifiers. Отмена/повтор блокируются, hardware staging/start отсутствуют. Actual системное разрешение и root peer пока не проверены. [Полный порядок](../helper-registration-approval.md), [подготовка](../research/evidence/owner-system-approval-session.json).

## Code anchors

| Компонент | Code |
|---|---|
| Сборка | `Package.swift`, `scripts/build-app.sh` |
| Подготовленная установка и диагностический XPC | `Sources/VentilatorInstallation/`, `Sources/Ventilator/HelperServiceCLI.swift` |
| SMC только на чтение | `Sources/CSMCRead/SMCRead.c` |
| HID NAND и профиль | `Sources/CHIDTemperature/HIDTemperatureRead.c`, `Sources/VentilatorCore/TemperatureSources.swift` |
| Модель и опрос | `Sources/VentilatorCore/Monitoring.swift` |
| Кандидатный preflight без записи | `Sources/VentilatorCore/ExperimentVerification.swift` |
| Запуск и обновление | `Sources/Ventilator/VentilatorMain.swift`, `Sources/Ventilator/MonitorStore.swift` |
| UI | `Sources/Ventilator/MainWindowView.swift`, `Sources/Ventilator/StatusItemController.swift` |

## Локальная сборка

Из корня репозитория: `scripts/build-app.sh`. Скрипт создаёт `.build/Ventilator.app`, ставит ad hoc подпись и проверяет bundle. Прототип запускается командой `open .build/Ventilator.app`; `--probe` печатает один снимок без GUI. Подпись ad hoc не подтверждает пригодность для `SMAppService`/helper.

## Особенности

- В песочнице процесса Codex открытие AppleSMC не удалось; тот же бинарник вне неё без `sudo` прочитал SMC. Это различие среды, которое нужно учитывать в тестах.
- Код режима `F*Md=3` показан как возможный системный режим, а не подтверждённая семантика.
- CPU/GPU остаются «Нет данных», пока физический источник не установлен. На точном `Mac15,7` + `27.0.0` + `26A428` SSD показывает один NAND-канал. `Tf26` показан отдельно как неразмеченный датчик.
- HID-граница использует четыре частных символа IOKit через `dlsym`. Она проверяет Product, location, классы датчика/родителя, отсутствие неоднозначности и возраст события ≤2 с. Отсутствие API или показания оставляет «Нет данных»; число не кэшируется. Это риск совместимости с будущими ОС, описанный в [исследовании температур](../research/research-temperatures.md).
- Закрытие окна не завершает процесс. Владелец подтвердил работу значка на живом экране 2026-09-30; [протокол](../research/evidence/m1-product-probe.txt).

См. [наблюдение](../features/feature-observation.md) и [исследование](../research/research-architecture.md).
