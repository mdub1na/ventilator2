---
id: ventilator-helper
title: Прототип помощника и симулятор M2
type: service
module: VentilatorHelper
tech_stack: [Swift, Foundation, Security, XPC, SwiftPM]
owner: unassigned
repo_url: https://github.com/mdub1na/ventilator2
depends_on: []
publishes: [VentilatorHelper]
---

# Помощник

SwiftPM собирает отдельный исполняемый файл и библиотеку `VentilatorControl`. Bundle содержит helper в `Contents/MacOS/` и plist в `Contents/Library/LaunchDaemons/`. На текущем Mac владелец установил подписанный root-owned bundle и создал BTM record; **системное одобрение ожидается (requiresApproval), enabled root daemon/XPC не проверены**. Автоматической регистрации нет; подготовленный register вызывается только явной app CLI-командой после native identity gate. Окно/значок не подключены к его XPC; новый app CLI выполняет диагностику. Приложение явно отвергает root.

Текущие действующие RPC: status, startSimulation, heartbeat(UUID), restoreSimulation(UUID), installationStatus(nonce). Все изменения только на подставном транспорте; installationStatus — только диагностика trusted root helper, anonymous simulation получает отказ. Добавлены prepareHardwareExperiment и startApprovedHardwareExperiment: первый возвращает кандидат/блокеры, второй в signed installed daemon требует локальный hardware receipt того же owner, isolated preflight и consuming begin; anonymous simulation по-прежнему отказывает; выдачи одобрения по XPC нет. Произвольных SMC-ключей/байтов, путей и команд оболочки на интерфейсе нет. Сеанс привязан к серверному owner ID соединения. Coordinator последовательно передаёт симуляционные команды worker через приватные pipe с ограниченными фреймами/таймаутами.

## Запуск и подпись

`scripts/build-app.sh` собирает оба бинарника, помещает plist, подписывает helper и bundle, проверяет каждую подпись. По умолчанию ad hoc. `VENTILATOR_SIGN_IDENTITY` позволяет использовать уже настроенную identity; самостоятельно сертификаты скрипт не создаёт.

Обычный режим демона требует root, текущий signed/root-owned `/Applications/Ventilator.app`, точный app/helper/LaunchDaemon layout и динамическую подпись helper по CDHash. Перед приёмом сообщений требует Apple anchor, identifier `dev.ventilator.macos`, тот же Team ID и CDHash конкретного app. При отсутствии условий — exit 78. Происхождение от launchd отдельно не проверяется; клиент дополнительно подтверждает живой root peer через bound XPC. Реальные подписи/root-owned installed app gate и защищённая замена подтверждены. Первая framework регистрация создала BTM record и вернула error 1 до административного одобрения; read-only status=requiresApproval. **Положительный privileged XPC не проверен**. Team `4659S5GD6X`; [фактическое состояние](../research/evidence/owner-helper-approval-pending.json). [Gate и его границы](../features/feature-helper-installation.md).

`--loopback-check` использует приватный anonymous listener и клиента в том же непривилегированном процессе; его acceptance обход относится только к симуляционному anonymous listener. Публичный daemon listener эту политику не использует. Подход anonymous listener для начального XPC рекомендует [Apple DTS](https://developer.apple.com/forums/thread/799910).

## Независимый процесс симуляции

При первом start coordinator запускает тот же helper executable в режиме `--simulation-worker` с наследуемыми pipe. Worker — единственный владелец модели и `ControlSession`; сохраняет маркер через `FileSessionJournal`, удерживает эксклюзивный `flock` и опрашивает сеанс в цикле run loop примерно раз в 50 мс. Clock — `mach_continuous_time`, учитывает сон. Повторный worker в том же каталоге отвергается; после перезапуска pending record вызывает только Auto.

SIGKILL помощника закрывает pipe: worker запрашивает Auto. SIGSTOP помощника не останавливает clock/heartbeat worker. После терминального состояния worker сохраняет отдельный ограниченный JSON-результат и завершается. Не начатый worker завершается через пять секунд; начатый ограничен десятисекундным lease и восьмисекундным сроком наблюдения восстановления. Потеря pipe не приводит к повторному запуску fixed.

В anonymous XPC тесте используется приватный временный каталог. Для подписанного root daemon выбран `/Library/Application Support/Ventilator/HelperSimulation`; этот installed путь ещё не запускался. `worker-result.json` — результат симуляции, не доказательство аппаратного Auto. Ошибка Auto сохраняет `session.json` и `recoveryRequired`. Авария **самого worker**, отключение питания и блокирующий аппаратный I/O не покрыты этим восстановителем.

Worker подключает публичный `IORegisterForSystemPower`: при will-sleep выполняет операцию Auto модели перед `IOAllowPowerChange`; idle sleep разрешает, без запрета сна. SIGTERM также запрашивает Auto. Регистрация успешна в локальном dry-run, маршрутизация sleep проверена подставным сообщением. Доставка реального сна и системное завершение root daemon не проверены; [Apple QA1340](https://developer.apple.com/library/archive/qa/qa1340/_index.html).

## Черновик аппаратного плана

`--candidate-plan` экспортирует план из `CandidateExperimentPlan`, SHA-256 app/helper и канонический хеш плана. Worker использует тот же helper binary. Перечень предполагаемых записей и их пределы хранится в коде плана; schema 3 добавляет restart policy. Экспорт не читает/не пишет SMC, не принимает одобрение и не устанавливает helper. `readyForOwnerApproval=false`: guarded broker подключён к experimental start, но положительный signed/installed issuer не проверен; единый сеанс владельца с инструкциями ещё не готов.

В helper линкуются `CSMCExperiment` и `VentilatorExperiment`: подготовленные десять нативных операций, проверка подписи/хешей и файловый single-use authority. Нативный factory требует hardware domain и закрытое свидетельство armed recovery, которое текущий worker не выдаёт. Factory доступен только подготовленному private hardware child; public XPC start его не вызывает. `--experiment-protocol-check` проверяет чистые нативные пакеты и полный модельный путь разрешения/записей/Auto на отдельном файле simulation; [подробности](../features/feature-experiment-protocol.md).

`--experiment-read-only` независимо читает FNum/Ftst и обоих вентиляторов без root через `CSMCRead`. Точный профиль/типы, timestamp начала и 0,5-секундный бюджет не позволяют медленному чтению выглядеть свежим. Сам вызов остаётся синхронным и не доказывает cancellable hardware I/O. Native open/write не вызываются; кандидатный preflight не выдаёт одобрение. [Аппаратный read-only результат](../research/evidence/experiment-read-only.json).

Подготовлены `RecoveryProbeClient` и повторная проверка `ExperimentWriteAdmission` перед нативным I/O. Witness требует bound private pipe, hardware domain и свежий ответ на каждый вызов; после ответа вновь читается ledger. Closure отзывает ранее reserved Fixed. Текущий broker модели этим не выдаёт hardware witness; общий private handler подготовлен, аппаратный entry/issuer к public start ещё не подключены.

Отдельный `--approved-model-parent` проверяет надзор за самим writer: private-pipe broker → fixed child → после подтверждённого выхода Auto child. CLI режимы broker/child требуют non-root и наследуемые pipe; domain строго simulation. Протокол scope включает session/owner/boot/hash/lease и nonce. Broker держит отдельный lifetime lock, сохраняет closure до сигнала, не запускает Auto при неподтверждённом выходе и не повторяет зависшую операцию. Модель читается в отдельном reader child; broker loop больше не читает устройство синхронно. Это следующий подготовительный путь, ещё не замена симуляционному RPC и не аппаратный восстановитель.

`ExperimentRecoveryBroker.swift` содержит общий process loop и private recovery probe handler. Модельный harness использует simulation domain; внутренний `runPreparedHardwareBroker` и native-ветка `ScopedExperimentChild` подготовлены, но никто не вызывает hardware broker entry. `--prepared-hardware-child` — узкая private-pipe ветка для root/consumed hardware ledger, не команда выдачи одобрения. Witness не создаётся из model probe. Read-only child лишён executor; брокер проверяет scope/роль/PID/ID, точный профиль/диапазоны и freshness снимка. При раннем отказе Auto reader оставшиеся допустимые Auto-попытки выполняются, но pending не снимается. Аппаратный outcome фиксирует physicalAutoVerified=false. Restart-путь подготовлен в общем loop и проверен на модели; положительный hardware/installed путь не запускался.

Новый путь использует отложенное подтверждение will-sleep: callback запускает ограниченное восстановление, завершение/отказ освобождает acknowledgement. Старый simulation worker сохраняет синхронный порядок. Реальный сон Mac не запускался. [Проверки broker](../research/evidence/recovery-dry-run.txt) покрывают helper/writer SIGKILL/SIGSTOP, broker SIGTERM, зависания Fixed/Auto, частичный отказ Auto, reader SIGSTOP/зависание/ошибку, потерю независимого Auto-подтверждения, injected sleep и абсолютный lease. SIGKILL/restart самого broker покрыт отдельным модельным harness; питание/SMC-kernel cancellation не доказаны.

## Локальный issuer и restart

`LocalApprovalCLI` показывает защищённый полный `LocalApprovalReview` и принимает только challenge UUID с точными SHA-256 плана/review. Перед confirm заново проверяет identity/файл/300-секундный срок. Hardware CLI имеет фиксированный каталог, требует root TTY, подписи одной команды, текущую модель/ОС/boot и enabled SMAppService; positive путь не запускался. Approval само по себе не создаёт ledger, не запускает процессы и не пишет SMC. Model CLI non-root и отдельный domain; подробности и лимиты — в [протоколе](../features/feature-experiment-protocol.md).

`BrokerRestartRecovery` требует точную boot/session/hash связку, durable closure и свободный device lifetime lock. После proof lock передаётся единственному Auto child; прежний Fixed уже отозван. Broker не сохраняет PID и не ищет/убивает старые процессы. Новый nonce, исходный срок и запрет повтора каждой попытки сохраняются. Недостоверный прежний Auto return оставляет pending даже при успешных оставшихся шагах. `--approved-model-parent` умеет потребить готовое локальное approval; новые [процессные проверки](../research/evidence/local-approval-restart-dry-run.txt) проходят весь путь TTY → receipt → broker → restart.

## Проверка

После сборки:

```sh
python3 scripts/session-runtime-dry-run.py
python3 scripts/installation-dry-run.py
python3 scripts/control-dry-run.py
python3 scripts/recovery-dry-run.py
python3 scripts/local-approval-restart-dry-run.py
python3 scripts/prepare-experiment-plan.py
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache" swift test --disable-sandbox --scratch-path .build
```

Dry-run проверяет настоящий обмен XPC, binding соединения/UUID, heartbeat, три чтения Auto-кода модели, отказ daemon mode, SIGKILL симулятора с перезапуском, SIGKILL/SIGSTOP помощника с продолжающим работать worker, SIGTERM worker и отказ Auto. Работает без root; [протокол](../research/evidence/control-dry-run.txt). Физический эффект RPM/Auto не проверяет.

Подготовленный [session runtime](../features/feature-owner-experiment-runtime.md) связывает receipt, preflight и broker; новые experimental heartbeat/restore/status RPC отделены от simulation. Startup daemon продолжает только оставшиеся Auto при свободном lifetime lock и точном boot/binary binding. Hardware pending остаётся для владельческого результата.

[Единый сеанс владельца](../owner-session.md) подготовлен: Terminal client удерживает проверенное соединение, root staging импортирует full review, audit читает защищённый outcome. Независимые baseline/Fixed/три Auto сохраняются с фактическими значениями. Системное одобрение старой сборки выполнено, но enabled helper завершается exit 78; root XPC/hardware positive не подтверждены. Ошибка пути argv[0] воспроизведена и исправлена; bundle/candidate/child paths теперь используют `CurrentExecutable`, startup этапы пишутся в unified log. Новый код проверен на модели, требуется подпись/disabled update и новый root handshake. [Диагностика](../research/evidence/owner-ready-deadline.json).

## Code anchors

| Компонент | Code |
|---|---|
| Контракт | `Sources/VentilatorControl/HelperProtocol.swift` |
| Сеанс и журнал | `Sources/VentilatorControl/ControlSession.swift`, `Sources/VentilatorControl/FileSessionJournal.swift` |
| XPC/собственная подпись | `Sources/VentilatorHelper/HelperServer.swift` |
| Worker и приватный IPC | `Sources/VentilatorHelper/SimulationWorker.swift` |
| Broker и отдельные device/reader-процессы | `Sources/VentilatorHelper/ExperimentRecoveryBroker.swift`, `Sources/VentilatorHelper/ApprovedModelRecovery.swift`, `Sources/VentilatorExperiment/ScopedExperimentChild.swift`, `Sources/VentilatorExperiment/RecoveryMonitor.swift`, `Sources/VentilatorExperiment/FileSimulatedStepDevice.swift` |
| Системные уведомления | `Sources/VentilatorHelper/SystemPowerObserver.swift`, `Sources/CSystemPower/` |
| Guarded session proxy/preflight | `Sources/VentilatorHelper/ExperimentSessionRuntime.swift`, `Sources/VentilatorHelper/ExperimentPreflight.swift`, `scripts/session-runtime-dry-run.py` |
| Кандидатный план | `Sources/VentilatorControl/CandidateExperimentPlan.swift`, `scripts/prepare-experiment-plan.py` |
| Подготовленный аппаратный протокол | `Sources/CSMCExperiment/`, `Sources/VentilatorExperiment/`, `Sources/VentilatorControl/ExperimentAuthority.swift` |
| Read-only наблюдение опыта | `Sources/VentilatorHelper/ExperimentReadOnlyCheck.swift`, `Sources/VentilatorExperiment/ReadOnlyExperimentObserver.swift` |
| Installed signature/lifecycle/XPC | `Sources/VentilatorInstallation/`, `Sources/Ventilator/HelperServiceCLI.swift`, `scripts/installation-dry-run.py` |
| Режимы запуска | `Sources/VentilatorHelper/HelperMain.swift` |
| Локальное одобрение и restart | `Sources/VentilatorHelper/LocalApprovalCLI.swift`, `Sources/VentilatorExperiment/LocalApprovalIssuer.swift`, `Sources/VentilatorExperiment/BrokerRestartRecovery.swift`, `scripts/local-approval-restart-dry-run.py` |
| Plist и сборка | `Resources/dev.ventilator.helper.plist`, `scripts/build-app.sh` |

См. [подставные сценарии](../features/feature-control-simulation.md) и [архитектуру](../research/research-architecture.md).
