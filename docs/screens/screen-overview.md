---
id: screen-overview
title: Обзор
type: client_screen
platform: [macOS]
status: active
entry: {macOS: "Боковая панель → Обзор"}
parent_feature: feature-observation
calls_api: []
source: Sources/Ventilator
---

# Обзор

## Состояния

- [x] **Reading:** CPU/GPU/SSD, обнаруженные вентиляторы, код режима и сведения об устройстве берутся из последнего снимка.
- [x] **Unavailable:** при недоступном SMC показано «SMC недоступен»; NAND опрашивается независимо через HID и остаётся неизвестным только при недоступности собственного источника.

Раздел реализован системным `Form` внутри `NavigationSplitView`. Названия режима не утверждают физическую семантику кода SMC. См. [feature](../features/feature-observation.md).

## Code anchors

| Компонент | Code |
|---|---|
| Экран | `Sources/Ventilator/MainWindowView.swift` |
| Снимок | `Sources/VentilatorCore/Monitoring.swift` |
