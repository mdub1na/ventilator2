---
id: feature-observation
title: Наблюдение за вентиляторами и датчиками
type: feature
status: active
owner: unassigned
involved_services: [ventilator-app]
client_entries: [screen-overview, screen-fans, screen-temperatures, screen-application]
api: []
tags: [macOS, monitoring]
---

# Наблюдение

Приложение показывает read-only снимки AppleSMC для обнаруженных вентиляторов. `FNum` задаёт количество (в коде ограничено восемью); каждый вентилятор имеет фактические/целевые RPM, пределы и сырой код режима. Непрочитанное значение остаётся неизвестным. Нуль RPM остаётся нулём, а не ошибкой. На проверенном `Mac15,7` + macOS 27.0.0 (`26A428`) HID читает температуру NAND-канала встроенного SSD. CPU/GPU не имеют проверенных источников и показываются как «Нет данных». Кандидат `Tf26` виден отдельно. [Результаты исследования](../research/research-temperatures.md).

На `27.0.1 / 26A434` SSD остаётся «Нет данных» до отдельной квалификации. [NAND-only пробник](../nand-profile-read-only.md) подготовлен и проверен только на моделях; автоматическая проверка разрешений отклонила живой запуск. Это не подтверждение источника на новой ОС.

Управление в [разделе вентиляторов](../screens/screen-fans.md) отключено до аппаратного подтверждения. [Обзор](../screens/screen-overview.md), [температуры](../screens/screen-temperatures.md) и [приложение](../screens/screen-application.md) читают один снимок из [приложения](../services/ventilator-app.md). Внешнего API нет.

## Code anchors

| Компонент | Code |
|---|---|
| Чтение SMC | `Sources/CSMCRead/SMCRead.c` |
| Чтение NAND и профиль | `Sources/CHIDTemperature/HIDTemperatureRead.c`, `Sources/VentilatorCore/TemperatureSources.swift` |
| Отдельная квалификация NAND | `tools/nand_profile_probe.m`, `scripts/check-nand-profile.py`, `scripts/nand-profile-dry-run.py` |
| Снимок и шкала | `Sources/VentilatorCore/Monitoring.swift` |
| Окно | `Sources/Ventilator/MainWindowView.swift` |
| Значок | `Sources/Ventilator/StatusItemController.swift` |

### Scenario: Нулевые обороты

**Дано:** вентилятор с фактическим значением `0 RPM` и корректным диапазоном.
**Когда:** вычисляется пятиделённая шкала.
**Тогда:** уровень равен нулю, а показание остаётся `0 RPM`.

**Automated:** `Tests/VentilatorCoreTests/FanReadingTests.swift::testZeroRPMIsARealEmptyGauge`

### Scenario: Недоступное показание

**Дано:** фактические RPM не прочитаны.
**Когда:** вычисляется шкала.
**Тогда:** уровень неизвестен; UI показывает «Нет данных».

**Automated:** `Tests/VentilatorCoreTests/FanReadingTests.swift::testUnavailableRPMDoesNotBecomeZero`

### Scenario: Два индивидуальных диапазона

**Дано:** два вентилятора имеют одинаковые RPM и разные считанные пределы.
**Когда:** вычисляется относительный уровень.
**Тогда:** каждый уровень рассчитывается по собственному диапазону.

**Automated:** `Tests/VentilatorCoreTests/FanReadingTests.swift::testEachFanUsesItsOwnRange`

### Scenario: Запись пока закрыта

**Дано:** успешная аппаратная квалификация Fixed и возврата Auto отсутствует.
**Когда:** открыт раздел вентиляторов.
**Тогда:** элементы Auto, фиксированных оборотов и возврата Auto отключены с пояснением.

Отключённые элементы проверены по accessibility-дереву запущенного приложения 2026-09-30. Последующий [аппаратный опыт](../research/evidence/current-hardware-failed-result.json) завершился отказом; Fixed и physical Auto не подтверждены.

### Scenario: Температура NAND на подтверждённом профиле

**Дано:** точная модель/версия/сборка, единственный HID-датчик `NAND CH0 temp`, location `TN0n`, проверенные классы NVMe и свежее событие.
**Когда:** собирается снимок.
**Тогда:** поле `SSD (NAND CH0)` содержит конечную температуру; она не обозначена как SMART composite или максимум SSD.

**Automated:** `Tests/VentilatorCoreTests/TemperatureSourcesTests.swift::testConfirmedNANDReadingPreservesZeroAndNamesTheChannel` — границы модельного показания. Нативное чтение проверено продуктовым `--probe`; [протокол](../research/evidence/temperature-product-probe.txt).

### Scenario: Неизвестный аппаратный профиль

**Дано:** другая модель, версия или сборка macOS.
**Когда:** доступно даже правдоподобное число.
**Тогда:** SSD остаётся «Нет данных»; локальное подтверждение не переносится на другую машину.

**Automated:** `Tests/VentilatorCoreTests/TemperatureSourcesTests.swift::testReadingDoesNotTransferToAnotherHardwareOrOSProfile`

### Scenario: Подставные данные не открывают новый NAND профиль

**Дано:** модельный отчёт пробника с пятью допустимыми температурами на `27.0.1 / 26A434`.
**Когда:** модельные проверки завершены без живого чтения.
**Тогда:** диагностика принимает только модельный отчёт; продуктовая allowlist сохраняет отказ нового профиля, SSD остаётся неизвестным.

**Automated:** `scripts/nand-profile-dry-run.py`, `Tests/VentilatorCoreTests/TemperatureSourcesTests.swift::testReadingDoesNotTransferToAnotherHardwareOrOSProfile`

### Scenario: Повтор сбора в существующий каталог

**Дано:** каталог результата уже существует после предыдущего запуска.
**Когда:** коллектор запрашивает тот же каталог.
**Тогда:** дочерний процесс не запускается, файлы результата не меняются.

**Automated:** `scripts/nand-profile-dry-run.py`

### Scenario: Потеря температурного показания

**Дано:** отсутствующее или некорректное новое показание.
**Когда:** формируется строка NAND.
**Тогда:** значение неизвестно, без подмены нулём или предыдущей температурой.

**Automated:** `Tests/VentilatorCoreTests/TemperatureSourcesTests.swift::testUnavailableAndInvalidSamplesNeverBecomeAZeroReading`
