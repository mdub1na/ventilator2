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

Реализованы нативный код формирования/проверки SMC-записей и файловая логика одобрения. **Аппаратный запуск не подключён.** Никакие записи на Mac не выполнялись; `hardwareControlAvailable=false`. Эта feature описывает подготовленный код и проверку на моделях, не успешное управление оборудованием.

## Нативная граница

`CSMCExperiment` предоставляет только десять шагов из `ExperimentStep`; ключи, типы и байты фиксированы. Произвольного writer(key, bytes) нет. Все пакеты проверены на совпадение с `CandidateExperimentPlan`. Нативный open требует root, `Mac15,7`/`26A428` и конечный будущий deadline не более 10 с для Fixed либо 8 с для восстановления.

Перед записью повторно проверяются профиль, два вентилятора, свежая метаинформация ключа и условия шага. Для Fixed также проверяются точные диапазоны, порядок, трёхсекундное ожидание после unlock и deadline непосредственно перед IOKit. Повтор одного шага на соединении запрещён; ошибка закрывает дальнейший Fixed. Kernel failure, неверный размер ответа, SMC result и неквалифицированный nonzero status отвергаются. Это проверено чистыми пакетами и компиляцией; сам аппаратный путь **не запускался**.

`NativeExperimentDevice` дополнительно требует аппаратный журнал, текущую загрузку ОС, совпадающие хеши, Apple-issued подписи app/helper одной команды и `ArmedHardwareRecovery`. Свидетельство восстановления нельзя декодировать из XPC и у него нет публичного конструктора. Нынешний симуляционный worker его не выдаёт; подключение живого аппаратного recovery broker остаётся задачей. Синхронный IOKit вызов не имеет доказанного здесь верхнего предела задержки: проверки deadline не гарантируют отмену уже начатого вызова.

GUI не зависит от `VentilatorExperiment`/`CSMCExperiment`; отсутствие writer-symbols проверяется на собранном executable.

## Одобрение и журнал

`ExperimentAuthority` создаёт challenge для серверного owner ID, точного хеша плана, двух binary fingerprints и boot UUID. Challenge действует 300 с. Решение выдаётся локально; XPC метода выдачи нет. Hardware domain требует root и локальный Terminal для выдачи решения; соответствующий CLI issuer и installed проверка **ещё не подключены**. Отдельные файлы simulation/hardware, проверка владельца/прав и domain не позволяют использовать симуляционное решение для нативного устройства.

Начало атомарно сохраняет consumed ledger с pending restoration **до первой операции**. `flock` сериализует транзакции, `fsync` предшествует I/O. Каждая попытка резервируется до вызова и получает одноразовый недекодируемый `ExperimentWriteReservation`. Неудачный вызов может уже изменить оборудование; поэтому попытка остаётся потраченной, Fixed закрывается и сохраняется срок восстановления. Повторное закрытие не продлевает срок. Новый экземпляр не возобновляет Fixed и не принимает потраченное одобрение даже после Auto.

Три разнесённых чтения после запроса, `Ftst=0` и правильный профиль отмечают `autoCodesObserved`. В simulation снимается pending marker; в hardware он сохраняется для результата физической проверки. Эти коды сами по себе не доказывают устойчивый возврат системного управления. Аппаратная ветка журнала/подписи/восстановления пока не проверена.

## Отдельный надзор за writer

`RecoveryMonitor` и режимы `--approved-model-*` добавляют отдельный broker для полного одноразового протокола. Helper передаёт heartbeat через private pipe; broker запускает отдельный writer, а после остановки — отдельный Auto-процесс. Все три используют тот же helper executable. Нынешний исполняемый путь работает только с `FileSimulatedStepDevice`, требует non-root и не создаёт нативного устройства или `ArmedHardwareRecovery`.

При потере heartbeat/pipe, выходе writer, задержке ответа 0,5 с, SIGTERM или sleep broker сначала сохраняет `fixedClosed`, затем останавливает **свой** writer и ждёт подтверждения завершения процесса не более 1 с. Auto не запускается до этого подтверждения. Если завершение не подтверждено, состояние остаётся pending. Новая попытка Fixed через authority после durable closure отвергается, даже если предыдущий writer позже пришлёт ответ.

Восстановление ограничено 8 с; если writer уже сохранил начало восстановления при ошибке, broker сохраняет этот ранний срок. Отдельный Auto-процесс выполняет только шаги 5–9; отказ одного вентилятора не мешает запросу Auto для другого. Зависший Auto-процесс завершается без повтора потраченной операции, pending остаётся. Broker независимо читает файловую модель: после трёх чтений сначала завершает Auto-процесс и только затем отмечает коды Auto. Потраченное одобрение сохраняется.

Power observer теперь поддерживает отложенный acknowledgement. В новом пути он отправляется после ограниченного восстановления либо его отказа с pending marker. Подставной sleep проверен; реальная доставка сна по-прежнему не проверена. Успешный обычный путь и SIGKILL/SIGSTOP helper/writer проверены отдельными процессами; [результаты](../research/evidence/recovery-dry-run.txt).

Проверка `Process.isRunning=false` подтверждает завершение процесса согласно [Apple](https://developer.apple.com/documentation/foundation/process/isrunning); **она не доказывает отмену уже начатой SMC-операции в ядре**. SIGKILL самого broker, потеря питания и физический возврат Auto не проверены. Аппаратная интеграция и локальный hardware issuer остаются блокерами, GUI read-only. Candidate schema 2 включает сроки ответа/остановки и условие завершения writer перед Auto.

## Доступный XPC

`prepareHardwareExperiment` возвращает хеш кандидата и причины `readyForOwnerApproval=false`. `startApprovedHardwareExperiment` отвергает старт с `hardwareRuntimeNotPrepared`, даже если передан правильный хеш; неверный формат — `invalidApprovalRequest`. Отказ проверен настоящим anonymous XPC до старта симуляции. Самостоятельное предъявление digest не выдаёт согласие.

## Code anchors

| Компонент | Code |
|---|---|
| Фиксированный C ABI и операции | `Sources/CSMCExperiment/SMCExperiment.c`, `Sources/CSMCExperiment/include/SMCExperiment.h` |
| Challenge, решение, budget | `Sources/VentilatorControl/ExperimentAuthority.swift` |
| Приватные файлы и транзакционная блокировка | `Sources/VentilatorControl/FileSessionJournal.swift` |
| Передача зарезервированной операции | `Sources/VentilatorExperiment/ApprovedStepExecutor.swift` |
| Нативные подписи/хеши/scope | `Sources/VentilatorExperiment/NativeExperimentDevice.swift` |
| Подставное устройство | `Sources/VentilatorExperiment/SimulatedStepDevice.swift` |
| Broker, scope и файловая модель | `Sources/VentilatorExperiment/RecoveryMonitor.swift`, `Sources/VentilatorExperiment/FileSimulatedStepDevice.swift`, `Sources/VentilatorHelper/ApprovedModelRecovery.swift` |
| XPC и встроенный dry-run | `Sources/VentilatorControl/HelperProtocol.swift`, `Sources/VentilatorHelper/ExperimentProtocolCheck.swift` |
| Исполняемые проверки | `Tests/VentilatorExperimentTests/`, `scripts/control-dry-run.py` |
| Проверка изоляции writer | `Tests/VentilatorExperimentTests/RecoveryMonitorTests.swift`, `scripts/recovery-dry-run.py` |

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

### Scenario: Отложенное подтверждение сна

**Дано:** активный опыт на модели и подставное will-sleep сообщение.
**Когда:** broker завершает ограниченное восстановление.
**Тогда:** acknowledgement следует после выхода writer, Auto-процесса и наблюдения кодов Auto. Реальный сон этим не подтверждён.

**Automated:** `scripts/recovery-dry-run.py`
