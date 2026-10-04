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

Подготовленный source candidate теперь **schema4 / Mac15,7 / 27.0.1 / 26A434**. Старые schema3 binaries/reviews/seals сохранены; legacy profile/schema3 review отвергаются новой версией. Fresh read-only data подтверждают exact metadata/ranges, но запись/physical Auto не подтверждены. Новый [полный owner сеанс](../current-hardware-owner.md) связывает qualification/backup/update, empty root state audit, signed full review и отдельные TTY APPROVE/START. Без receipt устройство не открывается; GUI controls остаются false. Actual installed root helper пока прежний и по-прежнему сообщает unsupportedMachine; новую сборку/опыт агент не устанавливает и не запускает. [Source verification](../research/evidence/current-experiment-source.json).

Owner сеанс новой identity завершён 2026-10-04 в 20:11:31 +05:00: **enabled, helperVerified=true, running root job PID 66079**, `readOnlyHelperVerified=true`. Owner сообщил ON и ALLOW; exact installed подпись/positive qualification и bound root XPC подтверждены. Сохранены 30 файлов completed пакета, old backup, 14 protected директорий и два прежних GUI marker; новый marker — третий. Staging/root runtime отсутствуют. Hardware status отдельно подтвердил **unsupportedMachine**, аппаратных записей 0, physicalAutoVerified=false. Завершённый run/register/ready не повторять. [Actual result](../research/evidence/gui-helper-identity-result.json).

Реализована новая compiled identity `dev.ventilator.app` / `dev.ventilator.app.helper` с одноимённым plist; Apple anchor/Team/CDHash и root peer gates сохранены. Старые identities и лишний legacy plist отвергаются до signature/framework. 29 installation/setup tests, strict ad hoc build и anonymous XPC/runtime models прошли. Это **source verification**, на момент подготовки installed версия была прежней. Полный [owner сеанс новой identity](../gui-helper-identity-owner.md) проверяет гипотезу сохранённой истории: positive qualification до lifecycle, pending/absent-only old removal, exact backup, sole GUI register и раздельные CONNECTED → ON → ALLOW/NONE. Hardware writes=[], при подготовке actual новая регистрация ещё не была выполнена. [Source evidence](../research/evidence/helper-identity-source-preparation.json).

После owner включения actual AX ON независимо подтверждён; единственный native status в 19:13:33 +05:00 остался **requiresApproval/serviceNotEnabled**, helperVerified=false. CLI exit 0 означает завершение диагностики. Frozen continuation4, completed reconnect30, protected12, installed5 и private GUI2 сохранены; runtime отсутствует, hardware writes 0. ON не привёл к root positive. Повтор статуса/регистрации не выполняется; исследуется системный допуск. [Actual result](../research/evidence/gui-helper-enable-result.json).

Владелец подтвердил, что после последнего register пропустил ON. Подготовлено [продолжение только с включением фоновой активности](../gui-helper-enable-owner.md): существующая установка/регистрация сохраняются, после owner ON агент независимо проверяет переключатель и делает один bounded native status. Повтор signing/reconnect/register не нужен. ON/positive root пока не подтверждены, hardware writes 0.

Последний owner reconnect установил подписанную source сборку без mainApp startup query. В 18:33:33 +05:00 actual requiresApproval/serviceNotEnabled, root lookup 113, helperVerified=false; новый register подтверждён marker PID 49998. Settings после сеанса показывает OFF; ON не подтверждён словом NONE. 30 файлов completed packet, exact old backup, installed seal и 12 protected директорий проверены; runtime отсутствует, аппаратных записей 0. Владелец затем подтвердил пропуск ON; продолжение включает только owner ON и одну проверку агентом. [Результат](../research/evidence/gui-helper-reconnect-result.json).

Холодный диагностический `HelperCoordinator` теперь не создаёт отсутствующий simulation journal directory. Existing directory/journal по-прежнему читается и, при необходимости, запускает прежний simulation recovery; lstat ошибки кроме ENOENT не игнорируются. Native unsupported-profile XPC проверяет отсутствие каталога после startup/status/prepare/start-denial/installation-denial. HardwareIfSupported/profile/recovery gates не расширены. Owner GUI update и последующий reconnect выполнены; production root positive пока не получен.

Завершённая owner проверка отдельной GUI identity подтвердила enabled и running root job с той же Apple Development подписью/Team на 27.0.1. Probe затем успешно unregistered, system job отсутствует. Первое архивирование остановилось на живом GUI PID; отдельный archive-only перенос затем завершён без повторного lifecycle. Это не production root peer: прямой status основного Ventilator после probe по-прежнему requiresApproval. Аппаратный runtime отсутствует; M2 не открыт. [Факты](../research/evidence/registration-probe-result.json), [archive-only порядок](../registration-probe-archive-owner.md).

## История состояния до GUI probe

Следующая диагностическая проверка подготовлена в отдельном приложении с собственными app/service IDs и noop daemon, без production модулей и аппаратного транспорта. Это GUI/consent/bootstrap isolation, не новый runtime Ventilator. Последующий прямой status текущей установки подтвердил requiresApproval; активный переключатель Settings не подтвердил root readiness. [Факт](../research/evidence/post-restart-framework-state.json), [отдельный полный план](../registration-probe-owner.md). До owner подписи/system approval actual probe ещё не запускался.

Последний завершённый owner snapshot 2026-10-04 — после перезапуска: boot UUID изменился, root launchd lookup снова вернул 113. BTM убрал pending authorization у parent; child enabled/allowed не изменился. Conditional native verify не запускался, framework status после перезапуска неизвестен; новая installed копия ещё не подтверждена как root peer. Семь файлов пакета сохранены. Collection/setup/register/ready и перезапуск не повторять. [Фактический результат](../research/evidence/after-restart-result.json). Notification/snapshot и post-restart сеансы завершены. Исходный wrapper теперь разделяет job load, попытку native verification и наблюдённый framework status; общее systemApprovalPending прежнего frozen пакета не является свежим SMAppService reply.

2026-10-04: один системный цикл загрузил job, но installed helper ещё завершался exit 78 при runtime admission. Mac теперь **27.0.1/26A434**, старый candidate — **27.0.0/26A428**; profile mismatch сообщался как untrustedSignature. Исправлена связь: signed/installed identity обязательна, при неподтверждённой машине аппаратный runtime отсутствует, диагностический listener остаётся доступным, preparation/start явно отказывают. Existing hardware journal читается diagnostic status и сохраняется; аппаратное восстановление на неподтверждённом профиле не запускается. Новая owner подпись завершена; public qualification остановилась до OFF, затем один developer qualify отдельного продолжения прошёл на тех же файлах. Owner продолжение затем установило exact новую копию с проверенным backup. До последнего перезапуска ON без administrative prompt оставил framework requiresApproval; root XPC новой сборки не подтверждён. Завершённый [отдельный сеанс](../helper-read-only-approval.md) проверил существующее уведомление и собрал global job/BTM snapshot, не повторяя lifecycle/signing; [actual installed state](../research/evidence/owner-read-only-update-installed-pending.json). [System результат](../research/evidence/owner-system-approval-result.json), [seal и сохранность](../research/evidence/owner-profile-update-resume-package.json), [полный сеанс продолжения](../owner-helper-update-resume.md).

Предыдущий административный снимок 2026-10-03 подтвердил отсутствие system job и runtime root при BTM child enabled/allowed и parent app pending authorization. После него выполнен [сеанс одного системного переключения и снимка](../helper-registration-approval.md); его результат 2026-10-04 приведён выше. [Предыдущие факты](../research/evidence/owner-registration-administrative-snapshot.json), [подготовка](../research/evidence/owner-system-approval-session.json).

SwiftPM собирает отдельный исполняемый файл и библиотеку `VentilatorControl`. Bundle содержит helper в `Contents/MacOS/` и plist в `Contents/Library/LaunchDaemons/`. В предыдущем сеансе 2026-10-03 владелец установил подписанный root-owned bundle; один owner setup получил **requiresApproval** и остановился до ready. Последующий read-only status — **enabled/remoteFailure**, job/runtime отсутствуют, root daemon/XPC не проверены. Владелец сообщил, что нового уведомления/подтверждения после setup не было; причина смены статуса пока не установлена. Подготовлен отдельный read-only system job/BTM снимок с owner sudo, helper в нём не запускается. Installed-continuation пакет сохраняется; повтор setup/register не назначен. [Исторические факты](../research/evidence/owner-setup-service-state.json). Автоматической регистрации нет; register вызывается явной app CLI-командой после native identity gate. Окно/значок не подключены к его XPC. Приложение явно отвергает root. [Подготовка пакета](../research/evidence/owner-installed-continuation.json).

Текущие действующие RPC: status, startSimulation, heartbeat(UUID), restoreSimulation(UUID), installationStatus(nonce). Все изменения только на подставном транспорте; installationStatus — только диагностика trusted root helper, anonymous simulation получает отказ. Добавлены prepareHardwareExperiment и startApprovedHardwareExperiment: первый возвращает кандидат/блокеры, второй в signed installed daemon требует локальный hardware receipt того же owner, isolated preflight и consuming begin; anonymous simulation по-прежнему отказывает; выдачи одобрения по XPC нет. Произвольных SMC-ключей/байтов, путей и команд оболочки на интерфейсе нет. Сеанс привязан к серверному owner ID соединения. Coordinator последовательно передаёт симуляционные команды worker через приватные pipe с ограниченными фреймами/таймаутами.

## Запуск и подпись

`scripts/build-app.sh` собирает оба бинарника, помещает plist, подписывает helper и bundle, проверяет каждую подпись. По умолчанию ad hoc. `VENTILATOR_SIGN_IDENTITY` позволяет использовать уже настроенную identity; самостоятельно сертификаты скрипт не создаёт.

Обычный режим демона требует root, текущий signed/root-owned `/Applications/Ventilator.app`, точный app/helper/LaunchDaemon layout и динамическую подпись helper по CDHash. Перед приёмом сообщений требует Apple anchor, identifier `dev.ventilator.app`, тот же Team ID и CDHash конкретного app. При отсутствии условий — exit 78. Происхождение от launchd отдельно не проверяется; клиент дополнительно подтверждает живой root peer через bound XPC. Реальные подписи/root-owned installed app gate и защищённая замена подтверждены. Первая framework регистрация создала BTM record и вернула error 1 до административного одобрения; read-only status=requiresApproval. **Положительный privileged XPC новой identity проверен 2026-10-04**. Team `4659S5GD6X`; [фактическое состояние](../research/evidence/owner-helper-approval-pending.json). [Gate и его границы](../features/feature-helper-installation.md).

`--loopback-check` использует приватный anonymous listener и клиента в том же непривилегированном процессе; его acceptance обход относится только к симуляционному anonymous listener. Публичный daemon listener эту политику не использует. Подход anonymous listener для начального XPC рекомендует [Apple DTS](https://developer.apple.com/forums/thread/799910).

## Независимый процесс симуляции

При первом start coordinator запускает тот же helper executable в режиме `--simulation-worker` с наследуемыми pipe. Worker — единственный владелец модели и `ControlSession`; сохраняет маркер через `FileSessionJournal`, удерживает эксклюзивный `flock` и опрашивает сеанс в цикле run loop примерно раз в 50 мс. Clock — `mach_continuous_time`, учитывает сон. Повторный worker в том же каталоге отвергается; после перезапуска pending record вызывает только Auto.

SIGKILL помощника закрывает pipe: worker запрашивает Auto. SIGSTOP помощника не останавливает clock/heartbeat worker. После терминального состояния worker сохраняет отдельный ограниченный JSON-результат и завершается. Не начатый worker завершается через пять секунд; начатый ограничен десятисекундным lease и восьмисекундным сроком наблюдения восстановления. Потеря pipe не приводит к повторному запуску fixed.

В anonymous XPC тесте используется приватный временный каталог. Для подписанного root daemon выбран `/Library/Application Support/Ventilator/HelperSimulation`; этот installed путь ещё не запускался. `worker-result.json` — результат симуляции, не доказательство аппаратного Auto. Ошибка Auto сохраняет `session.json` и `recoveryRequired`. Авария **самого worker**, отключение питания и блокирующий аппаратный I/O не покрыты этим восстановителем.

Worker подключает публичный `IORegisterForSystemPower`: при will-sleep выполняет операцию Auto модели перед `IOAllowPowerChange`; idle sleep разрешает, без запрета сна. SIGTERM также запрашивает Auto. Регистрация успешна в локальном dry-run, маршрутизация sleep проверена подставным сообщением. Доставка реального сна и системное завершение root daemon не проверены; [Apple QA1340](https://developer.apple.com/library/archive/qa/qa1340/_index.html).

## Черновик аппаратного плана

`--candidate-plan` экспортирует план из `CandidateExperimentPlan`, SHA-256 app/helper и канонический хеш плана. Worker использует тот же helper binary. Перечень предполагаемых записей, их пределы и restart policy хранятся в коде отдельного schema4 плана. Экспорт не читает/не пишет SMC, не принимает одобрение и не устанавливает helper. `readyForOwnerApproval=false`: guarded broker подключён к experimental start, но положительный signed/installed issuer не проверен; [единый сеанс владельца](../current-hardware-owner.md) подготовлен, но ещё не выполнялся.

В helper линкуются `CSMCExperiment` и `VentilatorExperiment`: подготовленные десять нативных операций, проверка подписи/хешей и файловый single-use authority. Нативный factory требует hardware domain и закрытое свидетельство armed recovery, которое текущий worker не выдаёт. Factory доступен только private hardware child; experimental XPC start проходит через guarded session proxy и broker, обычный GUI start native device не создаёт. `--experiment-protocol-check` проверяет чистые нативные пакеты и полный модельный путь разрешения/записей/Auto на отдельном файле simulation; [подробности](../features/feature-experiment-protocol.md).

`--experiment-read-only` независимо читает FNum/Ftst и обоих вентиляторов без root через `CSMCRead`. Точный профиль/типы, timestamp начала и 0,5-секундный бюджет не позволяют медленному чтению выглядеть свежим. Сам вызов остаётся синхронным и не доказывает cancellable hardware I/O. Native open/write не вызываются; кандидатный preflight не выдаёт одобрение. [Аппаратный read-only результат](../research/evidence/experiment-read-only.json).

Подготовлены `RecoveryProbeClient` и повторная проверка `ExperimentWriteAdmission` перед нативным I/O. Witness требует bound private pipe, hardware domain и свежий ответ на каждый вызов; после ответа вновь читается ledger. Closure отзывает ранее reserved Fixed. Текущий broker модели этим не выдаёт hardware witness; общий private handler подключён через guarded experimental session proxy; положительный hardware entry/issuer ещё не проверен.

Отдельный `--approved-model-parent` проверяет надзор за самим writer: private-pipe broker → fixed child → после подтверждённого выхода Auto child. CLI режимы broker/child требуют non-root и наследуемые pipe; domain строго simulation. Протокол scope включает session/owner/boot/hash/lease и nonce. Broker держит отдельный lifetime lock, сохраняет closure до сигнала, не запускает Auto при неподтверждённом выходе и не повторяет зависшую операцию. Модель читается в отдельном reader child; broker loop больше не читает устройство синхронно. Это следующий подготовительный путь, ещё не замена симуляционному RPC и не аппаратный восстановитель.

`ExperimentRecoveryBroker.swift` содержит общий process loop и private recovery probe handler. Модельный harness использует simulation domain; внутренний `runPreparedHardwareBroker` и native-ветка `ScopedExperimentChild` подключены к guarded experimental session proxy после полного local approval и fresh preflight. `--prepared-hardware-child` — узкая private-pipe ветка для root/consumed hardware ledger, не команда выдачи одобрения. Witness не создаётся из model probe. Read-only child лишён executor; брокер проверяет scope/роль/PID/ID, точный профиль/диапазоны и freshness снимка. При раннем отказе Auto reader оставшиеся допустимые Auto-попытки выполняются, но pending не снимается. Аппаратный outcome фиксирует physicalAutoVerified=false. Restart-путь подготовлен в общем loop и проверен на модели; положительный hardware/installed путь не запускался.

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

Продолжение: подпись исправления уже выполнена; public qualification отказал, затем отдельная диагностика прошла на exact файлах. Wrapper разделяет sign/qualify и их результаты; developer resume использует сохранённые signed файлы, без новой подписи. Installed update/root handshake всё ещё требуют владельца. [Свидетельство](../research/evidence/owner-signing-stages.json).

Последующая проверка: installed update выполнен, native signed/root-owned/installed gates прошли на exact новом seal. Backup сохранил предыдущую сборку, stage/runtime root отсутствуют. Повтор замены отказывает до мутаций; actual service=requiresApproval. Остаётся предусмотренный шаг 3: unregister/register, системное разрешение, ready; root XPC новой сборки не подтверждён. [Результат](../research/evidence/owner-helper-update-completed.json).

После включения владельцем фоновой активности actual service остался requiresApproval: Settings on подтверждён, BTM parent содержит pending authorization, job/runtime root отсутствуют. Root handshake не выполнялся. Системное административное одобрение ещё не подтверждено; причина расхождения/наличие auth prompt не установлены, sealed package сохраняется. [Диагностика](../research/evidence/owner-system-authorization-pending.json).

После owner удаления app/backup новые установочные команды находятся в fresh wrapper: пустые пути/runtime/job, one-shot markers, exact installed proof и максимум один bounded guarded unregister/register. Native daemon/XPC/broker не менялись; новый review запечатан на тех же signed файлах. Actual root XPC остаётся открытым. [Подготовка](../research/evidence/owner-fresh-install-package.json).

## Code anchors

| Компонент | Code |
|---|---|
| Контракт | `Sources/VentilatorControl/HelperProtocol.swift` |
| Сеанс и журнал | `Sources/VentilatorControl/ControlSession.swift`, `Sources/VentilatorControl/FileSessionJournal.swift` |
| XPC/собственная подпись | `Sources/VentilatorHelper/HelperServer.swift` |
| Worker и приватный IPC | `Sources/VentilatorHelper/SimulationWorker.swift` |
| Broker и отдельные device/reader-процессы | `Sources/VentilatorHelper/ExperimentRecoveryBroker.swift`, `Sources/VentilatorHelper/ApprovedModelRecovery.swift`, `Sources/VentilatorExperiment/ScopedExperimentChild.swift`, `Sources/VentilatorExperiment/RecoveryMonitor.swift`, `Sources/VentilatorExperiment/FileSimulatedStepDevice.swift` |
| Системные уведомления | `Sources/VentilatorHelper/SystemPowerObserver.swift`, `Sources/CSystemPower/` |
| Current full owner session | `scripts/current-hardware-owner.py`, `scripts/current-hardware-owner-dry-run.py` |
| Guarded session proxy/preflight | `Sources/VentilatorHelper/ExperimentSessionRuntime.swift`, `Sources/VentilatorHelper/ExperimentPreflight.swift`, `scripts/session-runtime-dry-run.py` |
| Кандидатный план | `Sources/VentilatorControl/CandidateExperimentPlan.swift`, `scripts/prepare-experiment-plan.py` |
| Подготовленный аппаратный протокол | `Sources/CSMCExperiment/`, `Sources/VentilatorExperiment/`, `Sources/VentilatorControl/ExperimentAuthority.swift` |
| Read-only наблюдение опыта | `Sources/VentilatorHelper/ExperimentReadOnlyCheck.swift`, `Sources/VentilatorExperiment/ReadOnlyExperimentObserver.swift` |
| Installed signature/lifecycle/XPC | `Sources/VentilatorInstallation/`, `Sources/Ventilator/HelperServiceCLI.swift`, `scripts/installation-dry-run.py` |
| Режимы запуска | `Sources/VentilatorHelper/HelperMain.swift` |
| Локальное одобрение и restart | `Sources/VentilatorHelper/LocalApprovalCLI.swift`, `Sources/VentilatorExperiment/LocalApprovalIssuer.swift`, `Sources/VentilatorExperiment/BrokerRestartRecovery.swift`, `scripts/local-approval-restart-dry-run.py` |
| Fresh identity orchestration | `scripts/gui-helper-identity.py`, `scripts/gui-helper-identity-dry-run.py` |
| Plist и сборка | `Resources/dev.ventilator.app.helper.plist`, `scripts/build-app.sh` |

См. [подставные сценарии](../features/feature-control-simulation.md) и [архитектуру](../research/research-architecture.md).
