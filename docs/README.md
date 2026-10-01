# Ventilator: документация

Начните с [архитектурного исследования](research/research-architecture.md), затем откройте [наблюдение](features/feature-observation.md) и нужный экран или [модуль приложения](services/ventilator-app.md). Документы описывают текущий read-only прототип. Дальнейшие этапы перечислены в [плане работ](../BACKLOG.md). Сетевого API нет.

## Coverage map

### Research (2)

- [x] [research-architecture](research/research-architecture.md) — факты о `Mac15,7` на macOS 27, подтверждённое чтение, архитектура и аппаратные ограничения.
- [x] [research-temperatures](research/research-temperatures.md) — каталог HID/SMC и физическая атрибуция температур.

### Features (5)

- [x] [feature-observation](features/feature-observation.md) — read-only показания, шкала и закрытое управление.
- [x] [feature-control-simulation](features/feature-control-simulation.md) — lease, журнал и восстановление на подставном транспорте.
- [x] [feature-experiment-protocol](features/feature-experiment-protocol.md) — подготовленный нативный ABI, локальное одобрение полного review, broker/restart модели и закрытый аппаратный старт.
- [x] [feature-helper-installation](features/feature-helper-installation.md) — подпись/layout, явный lifecycle CLI, pinned XPC диагностика и границы installed проверки.

- [x] [feature-owner-experiment-runtime](features/feature-owner-experiment-runtime.md) — guarded XPC/receipt/preflight/broker, proxy startup recovery и модельные границы.

### Screens (4)

- [x] [screen-overview](screens/screen-overview.md) — сводка устройства, датчиков и вентиляторов.
- [x] [screen-fans](screens/screen-fans.md) — значения по вентиляторам и недоступные команды.
- [x] [screen-temperatures](screens/screen-temperatures.md) — проверенные и неподтверждённые источники.
- [x] [screen-application](screens/screen-application.md) — запуск, значок и состояние помощника.

### Services (2)

- [x] [ventilator-app](services/ventilator-app.md) — сборка, SMC-чтение, поток снимков и ограничения.
- [x] [ventilator-helper](services/ventilator-helper.md) — незарегистрированный прототип помощника и проверка XPC без root.

## Проверка

```bash
python3 -m venv .venv-docs
.venv-docs/bin/python -m pip install -r requirements-docs.txt
.venv-docs/bin/python scripts/docs_check.py
```
