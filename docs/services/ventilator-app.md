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

Установленного привилегированного помощника и доступного пути записи из GUI сейчас нет. Bundle содержит [прототип helper](ventilator-helper.md), который не зарегистрирован и не подключён к GUI. Подготовленный writer находится в отдельных модулях, которые GUI не линкует; аппаратный старт helper закрыт. Вызовы `SMAppService.mainApp` присутствуют для будущего автозапуска, но переключатель пока отключён.

## Code anchors

| Компонент | Code |
|---|---|
| Сборка | `Package.swift`, `scripts/build-app.sh` |
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
