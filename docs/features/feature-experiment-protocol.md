---
id: feature-experiment-protocol
title: Подготовленный транспорт и одноразовое одобрение опыта
type: feature
status: active
owner: unassigned
involved_services: [ventilator-helper]
client_entries: []
api: []
tags: [macOS, SMC, approval, preparation]
---

# Протокол ограниченного опыта

Реализованы нативный код формирования/проверки SMC-записей и файловая логика одобрения. **Experimental hardware entry подключён за installed/local-receipt gates, положительный запуск не выполнялся.** Никакие записи на Mac не выполнялись; `hardwareControlAvailable=false`. Эта feature описывает подготовленный код и проверку на моделях, не успешное управление оборудованием.

## Нативная граница

`CSMCExperiment` предоставляет только десять шагов из `ExperimentStep`; ключи, типы и байты фиксированы. Произвольного writer(key, bytes) нет. Все пакеты проверены на совпадение с `CandidateExperimentPlan`. Нативный open требует root, `Mac15,7`/`26A428` и конечный будущий deadline не более 10 с для Fixed либо 8 с для восстановления.

Перед записью повторно проверяются профиль, два вентилятора, свежая метаинформация ключа и условия шага. Для Fixed также проверяются точные диапазоны, порядок, трёхсекундное ожидание после unlock и deadline непосредственно перед IOKit. Повтор одного шага на соединении запрещён; ошибка закрывает дальнейший Fixed. Kernel failure, неверный размер ответа, SMC result и неквалифицированный nonzero status отвергаются. Это проверено чистыми пакетами и компиляцией; сам аппаратный путь **не запускался**.

`NativeExperimentDevice` дополнительно требует signed/root-owned installed bundle и аппаратный журнал, текущую загрузку ОС, совпадающие хеши, Apple-issued подписи app/helper одной команды и `ArmedHardwareRecovery`. Свидетельство восстановления нельзя декодировать из XPC и у него нет публичного конструктора. Симуляция его не выдаёт. Подготовленный аппаратный child может получить его из bound probe и consumed hardware ledger; experimental start требует signed installed daemon и локальный receipt; локальный issuer только сохраняет approval. Синхронный IOKit вызов не имеет доказанного здесь верхнего предела задержки: проверки deadline не гарантируют отмену уже начатого вызова.

GUI не зависит от `VentilatorExperiment`/`CSMCExperiment`; CLI зависит от отдельного `VentilatorInstallation`, который не линкует writer; отсутствие writer-symbols проверяется на собранном executable.

Перед каждым device I/O `ExperimentWriteAdmission` повторно проверяет живой ledger, boot, pending состояние, последнюю зарезервированную попытку, роль и исходный срок. Durable closure отзывает уже выданный, но ещё не исполненный Fixed reservation. Нативный device проверяет журнал после ответа восстановителя; роль Fixed не может выполнить Auto, роль восстановления — Fixed. Это уменьшает окно между reservation и I/O; атомарная отмена начатого kernel вызова не установлена.

## Независимое чтение для опыта

`ReadOnlyExperimentObserver` открывает отдельное **read-only** соединение через `CSMCRead`; проверяет точный профиль и читает `FNum`, `Ftst`, actual/target/min/max/mode обоих вентиляторов. Принимаются только локально подтверждённые `ui8 `/`flt ` с точными размерами; Intel fallback не используется. Нулевые RPM остаются нулевыми; отсутствующая метаинформация, NaN/отрицательный RPM или не два вентилятора отвергают весь снимок.

Timestamp берётся **до** первого чтения. Бюджет чтения — 0,5 с по `mach_continuous_time`; обратный/невалидный clock и медленный возврат отвергают снимок. Этот бюджет не отменяет синхронный IOKit; подготовленный общий broker получает снимки из отдельного reader процесса. Thermal pressure остаётся явным входом preflight, не скрывается отсутствием CPU/GPU-атрибуции.

`--experiment-read-only` запускает только этот наблюдатель без root/одобрения и выводит снимок/результат preflight. Чтение на текущем Mac выполнено без sudo; [результат](../research/evidence/experiment-read-only.json). Успешный кандидатный preflight не разрешает аппаратные записи.

## Свежий ответ восстановителя

`RecoveryProbeClient` использует наследуемые pipe и новый request ID для каждого обращения. Ответ должен совпасть по session/owner/boot/hash/nonce, роли/фазе и deadline запроса; окно не более 0,5 с. Неверный или поздний ответ, EOF, ошибка clock либо oversized frame навсегда закрывают данный probe без retry. `RecoveryMonitor.reply` не продлевает heartbeat владельца или срок операции. Установка `F_SETNOSIGPIPE` на свои дескрипторы защищает процесс при закрытом peer; проверена локальными pipe-тестами.

`ArmedHardwareRecovery` теперь требует bound probe и hardware ledger, а нативный factory и каждая запись требуют свежего ответа. Публичного конструктора/декодирования witness по-прежнему нет. Проверено IPC на модели и отказ превращения model probe в hardware witness; подготовленный аппаратный child содержит guarded issuance, но **positive signed/root ветка не запускалась**. Локальный issuer описан ниже; он не запускает broker или устройство.

## Общий процессный runtime

`ExperimentRecoveryBroker` используется модельным harness и содержит внутренний подготовленный hardware entry. Аппаратный entry теперь вызывается отдельным proxy после signed installed identity, локального receipt и isolated preflight; issuer сам его не запускает. Одна схема IPC обслуживает отдельные Fixed/Auto/reader children. `ScopedExperimentChild` проверяет domain/scope/phase/роль до probe/device open; native factory сохраняет собственные root/signature/boot/hash проверки. Private child mode `--prepared-hardware-child` отвергает non-root, обычный терминал и отсутствие bound аппаратного ledger. Симуляционные faults в аппаратном domain запрещены.

Reader не имеет executor, а его снимок не содержит reservation. Broker принимает только ответ на текущий reader request с точными ID/scope/ролью/PID, свежим timestamp после запроса, конечным read duration ≤0,5 с, текущим deadline, проверенным профилем и диапазонами. Чтения IOKit не выполняются в broker loop. Ошибка/зависание reader в Fixed закрывают writer и вызывают Auto. Отказ Auto reader сохраняет pending и не мешает остальным допустимым Auto-попыткам; device effects сами по себе не являются доказательством восстановления.

Startup handshake и передача device/probe фреймов имеют ограниченные сроки. После durable closure Auto по-прежнему начинается только после подтверждённого завершения **writer**. Read-only child не пишет; ожидание его возможного kernel read не блокирует Auto. SIGKILL не считается доказательством отмены kernel I/O. Даже три аппаратных Auto-кода оставляют hardware pending и `physicalAutoVerified=false` в outcome. Общий broker содержит отдельный путь restart в Auto; положительный аппаратный запуск, signing/installation и владельческий сеанс остаются открытыми.

## Одобрение и журнал

`ExperimentAuthority` создаёт challenge для серверного owner ID, точного хеша плана, двух binary fingerprints, boot UUID и digest полного review. Challenge действует 300 с. Решение выдаётся локально; XPC метода выдачи нет. Hardware domain требует root, локальный Terminal и digest полного review. CLI issuer подготовлен; положительный installed сценарий ещё не проверен. Отдельные файлы simulation/hardware, проверка владельца/прав и domain не позволяют использовать симуляционное решение для нативного устройства.

Начало атомарно сохраняет consumed ledger с pending restoration **до первой операции**. `flock` сериализует транзакции, `fsync` предшествует I/O. Каждая попытка резервируется до вызова и получает одноразовый недекодируемый `ExperimentWriteReservation`. Неудачный вызов может уже изменить оборудование; поэтому попытка остаётся потраченной, Fixed закрывается и сохраняется срок восстановления. Повторное закрытие не продлевает срок. Новый экземпляр не возобновляет Fixed и не принимает потраченное одобрение даже после Auto.

Три разнесённых чтения после запроса, `Ftst=0` и правильный профиль отмечают `autoCodesObserved`. В simulation снимается pending marker; в hardware он сохраняется для результата физической проверки. Эти коды сами по себе не доказывают устойчивый возврат системного управления. Аппаратная ветка журнала/подписи/восстановления пока не проверена.

## Отдельный надзор за writer

`RecoveryMonitor` и режимы `--approved-model-*` добавляют отдельный broker для полного одноразового протокола. Helper передаёт heartbeat через private pipe; broker запускает отдельный writer, а после остановки — отдельный Auto-процесс. Все три используют тот же helper executable. Нынешний исполняемый путь работает только с `FileSimulatedStepDevice`, требует non-root и не создаёт нативного устройства или `ArmedHardwareRecovery`.

При потере heartbeat/pipe, выходе writer, задержке ответа 0,5 с, SIGTERM или sleep broker сначала сохраняет `fixedClosed`, затем останавливает **свой** writer и ждёт подтверждения завершения процесса не более 1 с. Auto не запускается до этого подтверждения. Если завершение не подтверждено, состояние остаётся pending. Новая попытка Fixed через authority после durable closure отвергается, даже если предыдущий writer позже пришлёт ответ.

Восстановление ограничено 8 с; если writer уже сохранил начало восстановления при ошибке, broker сохраняет этот ранний срок. Отдельный Auto-процесс выполняет только шаги 5–9; отказ одного вентилятора не мешает запросу Auto для другого. Зависший Auto-процесс завершается без повтора потраченной операции, pending остаётся. Broker независимо читает файловую модель: после трёх чтений сначала завершает Auto-процесс и только затем отмечает коды Auto. Потраченное одобрение сохраняется.

Power observer теперь поддерживает отложенный acknowledgement. В новом пути он отправляется после ограниченного восстановления либо его отказа с pending marker. Подставной sleep проверен; реальная доставка сна по-прежнему не проверена. Успешный обычный путь и SIGKILL/SIGSTOP helper/writer проверены отдельными процессами; [результаты](../research/evidence/recovery-dry-run.txt).

Проверка `Process.isRunning=false` подтверждает завершение процесса согласно [Apple](https://developer.apple.com/documentation/foundation/process/isrunning); **она не доказывает отмену уже начатой SMC-операции в ядре**. SIGKILL самого broker проверен отдельно на модели; потеря питания и физический возврат Auto не проверены. Аппаратная интеграция и signed/installed проверка остаются блокерами, GUI read-only. Candidate schema 3 включает сроки ответа/остановки, условие завершения writer перед Auto и политику restart.

## Доступный XPC

`prepareHardwareExperiment` возвращает хеш кандидата и причины `readyForOwnerApproval=false`. Обычный anonymous simulation `startApprovedHardwareExperiment` отвергает старт с `hardwareRuntimeNotPrepared`, даже если передан правильный хеш; неверный формат — `invalidApprovalRequest`. Signed installed ветка теперь требует локальный receipt того же connection owner и отдельный preflight; [новый runtime](feature-owner-experiment-runtime.md) проверен настоящим private model XPC. Legacy anonymous отказ также проверен. Самостоятельное предъявление digest не выдаёт согласие.

Новый [installed gate](feature-helper-installation.md) усиляет native identity: точный root-owned bundle, layout, expiry/trust anchors и CDHash текущего процесса. Положительный установленный путь по-прежнему не выполнялся.

## Локальное подтверждение полного сеанса

`LocalApprovalReview` содержит domain, точный кандидат и полный текст инструкций владельцу. Канонический SHA-256 связывает всё содержимое. Защищённый `local-review-<domain>.json` ограничен 16 KiB; инструкции — 8192 UTF-8 байт, без управляющих символов кроме LF/tab. Пустой текст, symlink, неверные права/владелец, domain, candidate или digest отвергаются. Полнота реального владельческого сеанса остаётся отдельным review gate: формат не доказывает, что автор перечислил все действия.

CLI `--approve-local-model <directory> <ownerUUID> <planSHA> <reviewSHA>` требует non-root TTY. `--approve-local-hardware <ownerUUID> <planSHA> <reviewSHA>` использует фиксированный `/Library/Application Support/Ventilator/Experiment`; перед prepare и confirm проверяет root TTY, профиль, Apple-issued подписи app/helper одной команды, boot и binary hashes, регистрацию `SMAppService.daemon(...).status == .enabled`. Это предварительная проверка допуска службы, не доказательство работающего установленного демона.

Перед вводом выводятся все инструкции и полный candidate. Принимается только `APPROVE <challengeUUID> <planSHA> <reviewSHA>` без дополнительных пробелов. EOF, отказ и неполная строка не одобряют план. После ввода заново проверяются review/identity и 300-секундный срок. Сохранение approval не создаёт consumed ledger и не вызывает устройство; повторная выдача отвергается. Полный model TTY → approval → begin → broker путь проверен; положительный аппаратный issuer не запускался. `readyForOwnerApproval=false` в offline экспорте сохраняется; experimental hardware start подготовлен за отдельными identity/receipt gates, пользовательское управление закрыто.

## Восстановление после перезапуска broker

Каждый writer/restorer удерживает domain-specific device lifetime lock до закрытия устройства. Новый broker сверяет тот же session/boot/current binary hashes/candidate digest, сохраняет closure Fixed и до 1 с пытается получить эту блокировку. PID не сохраняется; новый broker не посылает сигналы старым процессам. При занятом устройстве результат `deviceStillActive`, pending остаётся, новая restoration epoch не создаётся.

После подтверждения свободного устройства broker начинает только Auto с новым nonce. Продолжаются лишь ещё не зарезервированные шаги 5–9; прежние попытки не повторяются. Уже сохранённая restoration epoch и исходный срок 8 с не продлеваются; смена boot/бинарников/плана или истёкший срок отвергают restart. Каждый успешный возврат device.write записывается как audit `successfulReturns`. Это не физическая проверка. Прежняя Auto-попытка без return вызывает `ambiguousAutoAttempt`: остальные допустимые шаги выполняются, но pending не снимается даже при Auto-кодах модели.

[Процессная проверка](../research/evidence/local-approval-restart-dry-run.txt) покрывает SIGKILL broker в Fixed и частичном Auto, независимый процесс с занятым device lock, неизвестный результат Auto, истёкший исходный срок и другую boot session. Hardware positive restart не запускался; общий внутренний entry подготовлен, автоматическое подключение к установленному daemon остаётся задачей M2.

## Code anchors

| Компонент | Code |
|---|---|
| Фиксированный C ABI и операции | `Sources/CSMCExperiment/SMCExperiment.c`, `Sources/CSMCExperiment/include/SMCExperiment.h` |
| Challenge, решение, budget | `Sources/VentilatorControl/ExperimentAuthority.swift` |
| Полный review и локальный issuer | `Sources/VentilatorExperiment/LocalApprovalIssuer.swift`, `Sources/VentilatorHelper/LocalApprovalCLI.swift` |
| Перезапуск в Auto с исходным бюджетом | `Sources/VentilatorExperiment/BrokerRestartRecovery.swift`, `Tests/VentilatorExperimentTests/BrokerRestartRecoveryTests.swift` |
| Приватные файлы и транзакционная блокировка | `Sources/VentilatorControl/FileSessionJournal.swift` |
| Передача зарезервированной операции | `Sources/VentilatorExperiment/ApprovedStepExecutor.swift` |
| Нативные подписи/хеши/scope | `Sources/VentilatorExperiment/NativeExperimentDevice.swift` |
| Отзыв reservation перед I/O | `Sources/VentilatorExperiment/ExperimentWriteAdmission.swift` |
| Независимый read-only наблюдатель | `Sources/VentilatorExperiment/ReadOnlyExperimentObserver.swift`, `Sources/VentilatorHelper/ExperimentReadOnlyCheck.swift` |
| Общая граница child и ограниченный снимок | `Sources/VentilatorExperiment/ScopedExperimentChild.swift`, `Tests/VentilatorExperimentTests/BrokerObservationTests.swift` |
| Свежая проверка recovery | `Sources/VentilatorExperiment/RecoveryProbe.swift` |
| Подставное устройство | `Sources/VentilatorExperiment/SimulatedStepDevice.swift` |
| Broker, scope и файловая модель | `Sources/VentilatorExperiment/RecoveryMonitor.swift`, `Sources/VentilatorExperiment/FileSimulatedStepDevice.swift`, `Sources/VentilatorHelper/ExperimentRecoveryBroker.swift`, `Sources/VentilatorHelper/ApprovedModelRecovery.swift` |
| XPC и встроенный dry-run | `Sources/VentilatorControl/HelperProtocol.swift`, `Sources/VentilatorHelper/ExperimentProtocolCheck.swift` |
| Исполняемые проверки | `Tests/VentilatorExperimentTests/`, `scripts/control-dry-run.py` |
| Проверка изоляции writer | `Tests/VentilatorExperimentTests/RecoveryMonitorTests.swift`, `scripts/recovery-dry-run.py` |
| TTY и авария broker | `Tests/VentilatorExperimentTests/LocalApprovalIssuerTests.swift`, `scripts/local-approval-restart-dry-run.py` |

### Scenario: Одобрение для точного запроса

**Дано:** challenge с owner ID, boot UUID и хешами.
**Когда:** отсутствует решение либо не совпал challenge, boot, бинарник или соединение.
**Тогда:** начало отвергнуто до сохранения сеанса и вызова устройства.

**Automated:** `Tests/VentilatorExperimentTests/ExperimentAuthorityTests.swift::testApprovalMustMatchChallengeBootBinaryAndConnection`

### Scenario: Потраченное одобрение после перезапуска

**Дано:** сохранённый consumed ledger.
**Когда:** новый экземпляр пытается начать тот же опыт или подготовить ещё один.
**Тогда:** Fixed не возобновляется; pending состояние сохраняется.

**Automated:** `Tests/VentilatorExperimentTests/ExperimentAuthorityTests.swift::testConsumedApprovalSurvivesNewProcessObjectAndCannotResumeFixed`

### Scenario: Частичная ошибка устройства

**Дано:** шаг зарезервирован и устройство изменило модель перед ошибкой.
**Когда:** вызов завершается ошибкой.
**Тогда:** попытка потрачена, Fixed закрыт, маркер остаётся; срок восстановления не продлевается повторным запросом.

**Automated:** `Tests/VentilatorExperimentTests/ExperimentAuthorityTests.swift::testPartialDeviceFailureIsConsumedBeforeIOAndRestorationBudgetDoesNotReset`

### Scenario: Симуляция не даёт аппаратного доступа

**Дано:** simulation authority и зарезервированный шаг.
**Когда:** пытаются открыть нативное устройство или превратить reservation в hardware.
**Тогда:** запрос отвергнут; повторное использование reservation также невозможно.

**Automated:** `Tests/VentilatorExperimentTests/ExperimentAuthorityTests.swift::testAReservationCannotBeUsedTwiceOrConvertedToHardware`

### Scenario: Пакет не соответствует разрешённому типу

**Дано:** фиксированная операция с ожидаемой метаинформацией.
**Когда:** неизвестен шаг либо изменились тип/размер ключа.
**Тогда:** команда записи не формируется; output buffer остаётся нулевым.

**Automated:** `Tests/VentilatorExperimentTests/NativePacketTests.swift::testUnknownStepAndWrongMetadataCannotProduceWritePacket`

### Scenario: Старые Auto-показания или повреждённый журнал

**Дано:** pending restoration и расходованный сеанс.
**Когда:** предъявляют снимки до запроса Auto либо журнал повреждён.
**Тогда:** pending не снимается; новый I/O при ошибке журнала не выполняется.

**Automated:** `Tests/VentilatorExperimentTests/ExperimentAuthorityTests.swift::testCorruptJournalPreventsDeviceIOAndOldSamplesCannotClearPendingState`

### Scenario: Writer не подтвердил завершение

**Дано:** истёк срок ответа writer и broker запросил остановку.
**Когда:** завершение writer не подтверждено за 1 с.
**Тогда:** Auto не запускается, состояние остаётся recoveryRequired и pending ledger сохраняется.

**Automated:** `Tests/VentilatorExperimentTests/RecoveryMonitorTests.swift::testAutoCannotStartBeforeWriterExitAndTimeoutPreservesPendingLedger`

### Scenario: Чужое или позднее сообщение

**Дано:** scope с одноразовым nonce и фиксированным сроком lease.
**Когда:** приходит чужой nonce/operation ID либо поздний heartbeat.
**Тогда:** сообщение не продлевает lease и не возобновляет writer.

**Automated:** `Tests/VentilatorExperimentTests/RecoveryMonitorTests.swift::testWrongNonceSessionAndOperationAcknowledgementCannotExtendLease`, `Tests/VentilatorExperimentTests/RecoveryMonitorTests.swift::testLateHeartbeatAndReplyCannotReviveWriter`

### Scenario: Durable closure и сохранённый срок

**Дано:** Fixed закрыт в журнале до остановки writer.
**Когда:** writer запрашивает следующий шаг либо broker начинает Auto после уже записанной ошибки.
**Тогда:** Fixed отвергнут, исходное начало восстановления не переносится на более позднее время.

**Automated:** `Tests/VentilatorExperimentTests/RecoveryMonitorTests.swift::testDurableClosureBlocksLateWriterAndExistingRestoreEpochIsNotRenewed`

### Scenario: Аварии и блокирующий эффект

**Дано:** отдельные broker и writer с файловой моделью и потраченным одобрением.
**Когда:** helper/writer получает SIGKILL/SIGSTOP, либо Fixed/Auto зависает после сохранённого эффекта.
**Тогда:** Auto начинается только после выхода writer; при зависшем Auto потраченный шаг не повторяется, pending сохраняется. Отказ fan zero не блокирует Auto fan one.

**Automated:** `scripts/recovery-dry-run.py`

### Scenario: Timestamp начала независимого чтения

**Дано:** точный профиль, допустимые типы и реальные нулевые RPM.
**Когда:** наблюдатель читает отдельное соединение.
**Тогда:** снимок содержит Ftst/оба вентилятора и время начала чтения; ноль не заменяется unknown.

**Automated:** `Tests/VentilatorExperimentTests/ReadOnlyExperimentObserverTests.swift::testExactTypesZeroRPMAndTimestampAtReadStart`

### Scenario: Неверные или медленные показания

**Дано:** read-only источник опыта.
**Когда:** тип/размер отличается либо чтение выходит за бюджет/clock перестаёт быть монотонным.
**Тогда:** весь снимок отвергнут, старые значения не публикуются как свежие.

**Automated:** `Tests/VentilatorExperimentTests/ReadOnlyExperimentObserverTests.swift::testWrongTypeOrSizeDoesNotUseAnIntelFallback`, `Tests/VentilatorExperimentTests/ReadOnlyExperimentObserverTests.swift::testSlowReadBackwardClockAndUnavailableClockRejectWholeSample`

### Scenario: Reservation отозван до I/O

**Дано:** Fixed reservation уже сохранён.
**Когда:** broker сохраняет durable closure до исполнения устройства.
**Тогда:** повторная проверка ledger запрещает этот ранее зарезервированный Fixed шаг.

**Automated:** `Tests/VentilatorExperimentTests/ExperimentWriteAdmissionTests.swift::testPreviouslyReservedFixedStepIsRevokedByDurableClosure`

### Scenario: Роль и исходный срок устройства

**Дано:** отдельный восстановитель с reserved Auto шагом.
**Когда:** шаг предъявлен Fixed device или исходный срок восстановления истёк.
**Тогда:** I/O не допускается; срок не переносится на момент нового вызова.

**Automated:** `Tests/VentilatorExperimentTests/ExperimentWriteAdmissionTests.swift::testRestorationUsesOriginalDeadlineAndCannotUseFixedDevice`

### Scenario: Свежий ответ по приватному каналу

**Дано:** recovery probe на модели с точным scope.
**Когда:** peer не отвечает, меняет binding/deadline/phase либо model probe предъявляют hardware witness.
**Тогда:** запрос отвергнут; неудачный probe больше не используется, hardware доступ не появляется.

**Automated:** `Tests/VentilatorExperimentTests/RecoveryProbeTests.swift::testStoppedPeerTimesOutWithoutAWriteRetry`, `Tests/VentilatorExperimentTests/RecoveryProbeTests.swift::testWrongReplyBindingDeadlineOrPhasePermanentlyInvalidatesProbe`, `Tests/VentilatorExperimentTests/RecoveryProbeTests.swift::testFreshBoundAcknowledgementOnEachProbeAndModelCannotArmHardware`

### Scenario: Probe не заменяет heartbeat владельца

**Дано:** writer запрашивает свежий ответ broker.
**Когда:** heartbeat владельца истекает и Fixed закрывается.
**Тогда:** probe не продлевает lease/heartbeat и больше не получает разрешённую фазу.

**Automated:** `Tests/VentilatorExperimentTests/RecoveryMonitorTests.swift::testWriterProbeCannotRenewHeartbeatOrRespondAfterClosure`

### Scenario: Отложенное подтверждение сна

**Дано:** активный опыт на модели и подставное will-sleep сообщение.
**Когда:** broker завершает ограниченное восстановление.
**Тогда:** acknowledgement следует после выхода writer, Auto-процесса и наблюдения кодов Auto. Реальный сон этим не подтверждён.

**Automated:** `scripts/recovery-dry-run.py`

### Scenario: Независимый reader остановился

**Дано:** Fixed подтверждается отдельным процессом reader.
**Когда:** reader получает SIGSTOP либо зависает/возвращает ошибку.
**Тогда:** broker закрывает Fixed и выполняет Auto после выхода writer; таймер продолжает работать.

**Automated:** `scripts/recovery-dry-run.py`

### Scenario: Auto без независимого подтверждения

**Дано:** Auto child может выполнить оставшиеся допустимые шаги, но отдельный reader отказал.
**Когда:** модель уже вернулась в Auto, а свежих независимых снимков нет.
**Тогда:** остальные допустимые Auto-попытки выполняются без retry, outcome остаётся recoveryRequired и pending сохраняется.

**Automated:** `scripts/recovery-dry-run.py`

### Scenario: Чужой или устаревший снимок reader

**Дано:** ожидается снимок текущего read request.
**Когда:** timestamp предшествует запросу/находится в будущем, reply поздний либо изменились профиль/диапазоны/числа.
**Тогда:** снимок отвергнут и не становится доказательством Fixed/Auto.

**Automated:** `Tests/VentilatorExperimentTests/BrokerObservationTests.swift::testReplyFromEarlierRequestAndFutureSampleAreRejected`, `Tests/VentilatorExperimentTests/BrokerObservationTests.swift::testLateReplyAndInvalidReadDurationDoNotBecomeEvidence`, `Tests/VentilatorExperimentTests/BrokerObservationTests.swift::testChangedProfileOrRangeAndUnreadableNumbersAreRejected`

### Scenario: Роль дочернего процесса связана с журналом

**Дано:** consumed ledger и scope broker.
**Когда:** child предъявляет чужой session, закрытый Fixed или несовместимую роль/phase.
**Тогда:** init отвергнут до probe и device open; новых аппаратных попыток нет.

**Automated:** `Tests/VentilatorExperimentTests/BrokerObservationTests.swift::testChildRoleAndScopeAreCheckedBeforeAnyProbeOrDeviceOpen`

### Scenario: Код Auto не становится физическим доказательством

**Дано:** подготовленный аппаратный outcome.
**Когда:** broker формирует результат наблюдения кодов.
**Тогда:** physicalAutoVerified остаётся false; non-root не может сохранить аппаратный result.

**Automated:** `Tests/VentilatorExperimentTests/BrokerObservationTests.swift::testHardwareOutcomeNeverClaimsPhysicalAutoAndNonRootCannotPersistIt`

### Scenario: Точное локальное согласие без начала опыта

**Дано:** защищённый полный review с candidate и двумя digest.
**Когда:** владелец вводит точную confirmation строку в TTY.
**Тогда:** сохраняется одно approval; ledger/устройство не создаются, replay отвергается.

**Automated:** `Tests/VentilatorExperimentTests/LocalApprovalIssuerTests.swift::testExactReviewAndConfirmationPersistSingleApprovalWithoutStarting`, `scripts/local-approval-restart-dry-run.py`

### Scenario: Отказ или неполное подтверждение

**Дано:** показанный локальный review.
**Когда:** поступает EOF, отказ, короткое согласие или строка с лишними пробелами.
**Тогда:** approval не выдаётся.

**Automated:** `Tests/VentilatorExperimentTests/LocalApprovalIssuerTests.swift::testDeclineEOFAndPartialConsentNeverApprove`

### Scenario: Подмена review или identity

**Дано:** challenge для показанного review и текущих бинарников.
**Когда:** изменён текст после показа, digest, binary/domain либо истёк challenge.
**Тогда:** подтверждение отвергнуто до approval и I/O.

**Automated:** `Tests/VentilatorExperimentTests/LocalApprovalIssuerTests.swift::testReviewChangedAfterDisplayOrWrongDigestCannotApprove`, `Tests/VentilatorExperimentTests/LocalApprovalIssuerTests.swift::testChangedBinaryDomainOrExpiredChallengeAreRejected`

### Scenario: Небезопасный review или неверный domain issuer

**Дано:** локальный файл review.
**Когда:** файл является symlink, превышает лимит, содержит ESC или non-root пытается создать hardware issuer.
**Тогда:** review/issuer отвергнуты; аппаратного approval нет.

**Automated:** `Tests/VentilatorExperimentTests/LocalApprovalIssuerTests.swift::testSymlinkOversizedOrUnsafeInstructionsCannotBeReviewed`, `Tests/VentilatorExperimentTests/LocalApprovalIssuerTests.swift::testNonRootCannotConstructHardwareIssuerOrWriteHardwareReview`

### Scenario: Новый broker продолжает только Auto

**Дано:** consumed ledger после SIGKILL broker и освобождённое устройство.
**Когда:** новый broker принимает тот же boot/hash/session.
**Тогда:** Fixed закрыт; новый nonce и только оставшиеся Auto-шаги, без повторного согласия или Fixed.

**Automated:** `Tests/VentilatorExperimentTests/BrokerRestartRecoveryTests.swift::testRestartClosesFixedAndIssuesOnlyRemainingAutoWithNewNonce`, `scripts/local-approval-restart-dry-run.py`

### Scenario: Устройство ещё занято после аварии

**Дано:** другой процесс удерживает device lifetime lock.
**Когда:** broker запускает restart.
**Тогда:** Fixed закрывается, Auto не начинается; pending остаётся, новая restoration epoch отсутствует.

**Automated:** `Tests/VentilatorExperimentTests/BrokerRestartRecoveryTests.swift::testLiveDeviceLockPreventsAutoAndDoesNotCreateRestorationEpoch`, `scripts/local-approval-restart-dry-run.py`

### Scenario: Исходный срок и попытки переживают restart

**Дано:** начатое Auto с сохранённой epoch и одной выполненной попыткой.
**Когда:** broker перезапускается до или после исходного восьмисекундного срока.
**Тогда:** срок не продлевается, попытка не повторяется; истёкший restart отвергается.

**Automated:** `Tests/VentilatorExperimentTests/BrokerRestartRecoveryTests.swift::testOriginalRestorationDeadlineAndAttemptBudgetSurviveRestart`, `scripts/local-approval-restart-dry-run.py`

### Scenario: Неизвестный результат прежнего Auto

**Дано:** Auto был зарезервирован, но успешный return не сохранён.
**Когда:** новый broker исполняет оставшиеся допустимые шаги.
**Тогда:** прежняя попытка не повторена; даже при Auto-кодах результат ambiguousAutoAttempt и pending сохраняется.

**Automated:** `Tests/VentilatorExperimentTests/BrokerRestartRecoveryTests.swift::testUnreturnedAutoIsNeverRepeatedOrDeclaredSuccessful`, `scripts/local-approval-restart-dry-run.py`

### Scenario: Другая загрузка или сборка при restart

**Дано:** pending ledger для точной boot/session/binary связки.
**Когда:** предъявлен другой boot, session или hash.
**Тогда:** restart отвергнут до closure и device доступа; попытки не изменены.

**Automated:** `Tests/VentilatorExperimentTests/BrokerRestartRecoveryTests.swift::testWrongBootHashOrSessionCannotCloseOrRestore`
