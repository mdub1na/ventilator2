---
id: screen-application
title: Приложение
type: client_screen
platform: [macOS]
status: active
entry: {macOS: "Боковая панель → Приложение"}
parent_feature: feature-observation
calls_api: []
source: Sources/Ventilator
---

# Приложение

## Состояния

- [x] **ReadOnly:** значок всегда включён, помощник обозначен как не установленный.
- [x] **LoginBlocked:** переключатель автозапуска отключён до проверки установленной подписанной сборки.

Закрытие окна оставляет процесс работающим. Действие закрытия проверено на запущенном приложении. Владелец подтвердил работу значка на живом экране 2026-09-30; [протокол](../research/evidence/m1-product-probe.txt). См. [feature](../features/feature-observation.md).

## Code anchors

| Компонент | Code |
|---|---|
| Экран | `Sources/Ventilator/MainWindowView.swift` |
| Состояние/SMAppService | `Sources/Ventilator/MonitorStore.swift` |
| Жизненный цикл окна | `Sources/Ventilator/VentilatorMain.swift` |
