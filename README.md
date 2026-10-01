# Ventilator

Нативное приложение macOS для наблюдения за вентиляторами Mac. Текущий прототип работает **только на чтение**: показывает обнаруженные вентиляторы, их RPM, пределы и сырой код режима. На проверенном `Mac15,7` + macOS 27.0.0 (`26A428`) показывает температуру NAND-канала встроенного SSD. CPU/GPU пока обозначены как «Нет данных»: [результаты проверки](docs/research/research-temperatures.md). Кнопки управления отключены.

Сборка и запуск на Mac с Xcode 27:

```bash
scripts/build-app.sh
open .build/Ventilator.app
```

Диагностический снимок без окна: `.build/Ventilator.app/Contents/MacOS/Ventilator --probe`. Сборка использует ad hoc подпись для локального прототипа; помощник не установлен. Подробнее: [документация](docs/README.md), [исследование аппаратных ограничений](docs/research/research-architecture.md), [план работ](BACKLOG.md).

Подготовка M2: прототип помощника встроен в bundle, но не зарегистрирован. `python3 scripts/control-dry-run.py` проверяет XPC, одноразовое одобрение на модели и независимый процесс восстановления **симулятора** при SIGKILL/SIGSTOP помощника без root и SMC-записей. `python3 scripts/prepare-experiment-plan.py` экспортирует неодобренный черновик аппаратного плана с хешами бинарников. Нативный writer подготовлен, аппаратный запуск закрыт; [границы проверки](docs/features/feature-experiment-protocol.md).

`python3 scripts/recovery-dry-run.py` проверяет отдельный broker и точные шаги опыта на файловой модели: аварии helper/writer/reader, зависания, частичный отказ Auto, потерю независимого подтверждения и отложенное подтверждение подставного сна. [Результаты](docs/research/evidence/recovery-dry-run.txt) подтверждают процессную логику; аппаратный возврат Auto ещё не проверен.

`.build/Ventilator.app/Contents/MacOS/VentilatorHelper --experiment-read-only` читает отдельный снимок FNum/Ftst/вентиляторов и сообщает кандидатный preflight без root. Он не выдаёт аппаратное одобрение; [проверенный результат](docs/research/evidence/experiment-read-only.json).

В подготовленном общем runtime writer, восстановитель и read-only reader разделены по процессам и связаны свежими private recovery probes. Аппаратный entry/локальный issuer и проверка установленной подписи ещё не подключены; GUI остаётся только на чтение.
