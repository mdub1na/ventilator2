---
id: screen-fans
title: Вентиляторы
type: client_screen
platform: [macOS]
status: active
entry: {macOS: "Боковая панель → Вентиляторы"}
parent_feature: feature-observation
calls_api: []
source: Sources/Ventilator
---

# Вентиляторы

## Состояния

- [x] **Detected:** для каждого вентилятора показаны фактические/целевые RPM, считанные пределы, код режима и относительная шкала.
- [x] **Unavailable:** если SMC или вентиляторы не найдены, показано диагностическое сообщение.
- [x] **Blocked:** кнопки Auto, фиксированных оборотов и «Вернуть Auto» отключены до аппаратной проверки.

Нуль RPM отображается явно. Неизвестные RPM не получают делений. См. [feature](../features/feature-observation.md).

## Code anchors

| Компонент | Code |
|---|---|
| Экран | `Sources/Ventilator/MainWindowView.swift` |
| Расчёт делений | `Sources/VentilatorCore/Monitoring.swift` |
