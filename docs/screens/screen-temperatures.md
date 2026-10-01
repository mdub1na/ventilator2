---
id: screen-temperatures
title: Температуры
type: client_screen
platform: [macOS]
status: active
entry: {macOS: "Боковая панель → Температуры"}
parent_feature: feature-observation
calls_api: []
source: Sources/Ventilator
---

# Температуры

## Состояния

- [x] **Reading:** `SSD (NAND CH0)` показывает температуру одного NAND-канала на проверенной модели/сборке и имя источника.
- [x] **Unverified:** CPU/GPU показывают «Нет данных» и отсутствие подтверждённого источника; SSD на иных профилях тоже остаётся неизвестным.
- [x] **Candidate:** `Tf26`, если читается и правдоподобен, виден как отдельный неразмеченный датчик.
- [x] **Unavailable:** если датчик недоступен, неоднозначен, событие NAND старше двух секунд или значение вне допустимого интервала, соответствующая строка показывает «Нет данных».

Значение `Tf26` не выдаётся за температуру CPU/GPU/SSD. Пояснение отличает NAND-канал от общей температуры накопителя. См. [feature](../features/feature-observation.md) и [исследование](../research/research-temperatures.md). После перезапуска владельцем 2026-09-30 раздел проверен по accessibility-дереву и скриншоту: NAND 29.0 °C, CPU/GPU без данных, `Tf26` 50.9 °C. [Протокол](../research/evidence/temperature-product-probe.txt).

## Code anchors

| Компонент | Code |
|---|---|
| Экран | `Sources/Ventilator/MainWindowView.swift` |
| Декодирование и граница | `Sources/VentilatorCore/Monitoring.swift` |
| Профиль/политика NAND | `Sources/VentilatorCore/TemperatureSources.swift` |
| HID только на чтение | `Sources/CHIDTemperature/HIDTemperatureRead.c` |
