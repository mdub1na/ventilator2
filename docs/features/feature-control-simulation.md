---
id: feature-control-simulation
title: Симуляция ограниченного сеанса управления
type: feature
status: active
owner: unassigned
involved_services: [ventilator-helper]
client_entries: []
api: []
tags: [macOS, XPC, simulation]
---

# Ограниченный сеанс: симуляция

Реализована логика подготовки M2, которую можно проверять без аппаратных записей. Сеанс использует `SimulatedFanTransport`: методы `simulateFixed2500RPM` и `simulateAuto` изменяют модель в памяти. Отдельный [нативный протокол](feature-experiment-protocol.md) подготовлен, но аппаратный старт закрыт; этот worker его не вызывает. Каждый ответ содержит `simulationOnly=true`, `hardwareControlAvailable=false`; UI управления остаётся закрыт.

Кандидатный профиль — `Mac15,7` / `27.0.0` / `26A428`, два вентилятора, номинальный thermal pressure, свежие данные и `Ftst=0`. Начальный preflight использует проверку из [наблюдения](feature-observation.md). Это проверка предпосылок симуляции, без выдачи аппаратного разрешения.

Срок сеанса — 10 с, heartbeat — не реже двух секунд. Heartbeat не продлевает первоначальный срок. Подтверждение fixed требует независимого чтения двух вентиляторов, режима, цели и actual RPM в пределах пяти секунд. Отсутствие эффекта завершает опыт восстановлением. Владелец сеанса определяется на сервере по XPC-соединению; другой клиент не может продлить или восстановить этот сеанс.

Перед изменением модели сохраняется маркер. `FileSessionJournal` работает в приватном каталоге владельца процесса, отвергает симлинки, проверяет владельца/права, заменяет файл атомарно и делает `fsync` файла/каталога. При перезапуске незавершённый маркер вызывает восстановление; fixed не возобновляется. Маркер удаляется после трёх разнесённых на секунду чтений кода Auto и `Ftst=0`. Итог называется `autoCodeObserved`: это не физическое подтверждение системного управления.

При ошибке восстановления или удаления маркера состояние — `recoveryRequired`; автоматический повтор fixed запрещён. XPC coordinator использует отдельный worker с файловым журналом и своим clock. Worker единолично изменяет модель, удерживает эксклюзивную блокировку каталога и сохраняет итог перед выходом. SIGKILL/SIGSTOP coordinator не останавливает восстановление. Сохранность при отключении питания, авария самого worker и восстановление настоящих вентиляторов не доказаны.

`CandidateExperimentPlan` описывает **неодобренный** кандидат аппаратного опыта: точный профиль, считанные ранее диапазоны, 2500 RPM, сроки и бинарные хеши. Целостность проверяется сравнением с разрешённой формой и каноническим SHA-256. Изменение записи, срока, readiness, бинарника или диапазона отвергается. Даже корректное совпадение не выдаёт аппаратного разрешения. Пакеты нативного writer совпадают со списком кандидата; исполняющий аппаратный путь ещё не подключён. [Экспорт](../research/evidence/candidate-experiment-plan.json).

## Code anchors

| Компонент | Code |
|---|---|
| Сеанс и lease | `Sources/VentilatorControl/ControlSession.swift` |
| Подставной транспорт | `Sources/VentilatorControl/SimulatedFanTransport.swift` |
| Маркер | `Sources/VentilatorControl/FileSessionJournal.swift` |
| Ограниченный RPC | `Sources/VentilatorControl/HelperProtocol.swift` |
| Сериализация, таймер и binding соединения | `Sources/VentilatorHelper/HelperServer.swift` |
| XPC smoke test | `Sources/VentilatorHelper/HelperMain.swift` |
| SIGKILL и новый процесс | `scripts/control-dry-run.py` |
| Worker/системные события | `Sources/VentilatorHelper/SimulationWorker.swift`, `Sources/VentilatorHelper/SystemPowerObserver.swift` |
| Форма кандидатного плана | `Sources/VentilatorControl/CandidateExperimentPlan.swift`, `Tests/VentilatorControlTests/CandidateExperimentPlanTests.swift` |

### Scenario: Истечение lease

**Дано:** подтверждённый подставной fixed и регулярные heartbeat.
**Когда:** прошло десять секунд от начала.
**Тогда:** инициируется подставной Auto; поздний heartbeat и повторный start не возобновляют fixed.

**Automated:** `Tests/VentilatorControlTests/ControlSessionTests.swift::testHeartbeatCannotExtendLeaseOrStartAnotherSession`

### Scenario: Потеря heartbeat или другое соединение

**Дано:** активный сеанс, привязанный к своему серверному owner ID.
**Когда:** другой owner присылает heartbeat или правильный owner молчит две секунды.
**Тогда:** чужой вызов отвергнут, потеря heartbeat запускает восстановление.

**Automated:** `Tests/VentilatorControlTests/ControlSessionTests.swift::testLostHeartbeatAndWrongOwnerCannotKeepFixedModeAlive`

### Scenario: Невозможно сохранить маркер

**Дано:** ошибка начальной записи журнала.
**Когда:** запрошен сеанс.
**Тогда:** ни одна команда изменения модели не выполняется.

**Automated:** `Tests/VentilatorControlTests/ControlSessionTests.swift::testInitialJournalFailurePreventsFixedChange`

### Scenario: Сбой во время изменения

**Дано:** подставной транспорт изменил состояние и вернул ошибку.
**Когда:** обрабатывается ошибка.
**Тогда:** запрашивается восстановление, а маркер остаётся до трёх независимых чтений.

**Automated:** `Tests/VentilatorControlTests/ControlSessionTests.swift::testChangeFailureRequestsRestoreAndKeepsMarkerUntilThreeReads`

### Scenario: Восстановление не удалось

**Дано:** ошибка подставной команды Auto.
**Когда:** продолжается опрос.
**Тогда:** состояние требует восстановления, маркер сохранён, команда не повторяется молча.

**Automated:** `Tests/VentilatorControlTests/ControlSessionTests.swift::testRestoreFailureKeepsMarkerAndDoesNotRetrySilently`

### Scenario: Перезапуск после незавершённого сеанса

**Дано:** маркер на диске, оставшийся от предыдущего процесса.
**Когда:** новый экземпляр загружает журнал.
**Тогда:** запрашивается только Auto, fixed не возобновляется; маркер удаляется после наблюдения кодов.

**Automated:** `Tests/VentilatorControlTests/FileSessionJournalTests.swift::testNewInstanceFindsPendingRecordAndOnlyClearsAfterRestoration`

Реальный SIGKILL отдельного **симулятора** и новый процесс проверены [dry-run](../research/evidence/control-dry-run.txt).

### Scenario: Небезопасное наблюдение или жизненный цикл

**Дано:** активный подставной сеанс.
**Когда:** вызван disconnect/sleep, исчезли показания, повысился thermal pressure, сменился профиль или часы пошли назад.
**Тогда:** инициируется восстановление, сохранён маркер.

**Automated:** `Tests/VentilatorControlTests/ControlSessionTests.swift::testDisconnectSleepSensorLossPressureAndProfileChangeRequestRestore`

Системный observer теперь подключён к worker и регистрация проверена. Событие sleep в dry-run подставное: реальная доставка при сне ещё не проверена, Mac не усыплялся.

### Scenario: Нет роста фактических RPM

**Дано:** режим и цель изменились, actual RPM не выросли.
**Когда:** истекли пять секунд подтверждения.
**Тогда:** fixed не объявлен подтверждённым; запрошен Auto.

**Automated:** `Tests/VentilatorControlTests/ControlSessionTests.swift::testNoRPMMovementFailsVerificationInsteadOfClaimingFixedMode`

### Scenario: Изменились пределы вентилятора

**Дано:** активный сеанс и сохранённые исходные min/max.
**Когда:** один предел изменился, даже если 2500 RPM ещё входит в диапазон.
**Тогда:** запрашивается Auto с причиной `rangeChanged`; маркер сохраняется до чтений восстановления.

**Automated:** `Tests/VentilatorControlTests/ControlSessionTests.swift::testChangedRangeStopsEvenWhenTargetRemainsInsideIt`

### Scenario: Авария или зависание XPC-помощника

**Дано:** модель fixed в отдельном worker с журналом.
**Когда:** собственный процесс помощника получает SIGKILL или SIGSTOP.
**Тогда:** worker самостоятельно выполняет один Auto, наблюдает три разнесённых чтения и удаляет маркер; fixed повторно не запускается.

**Automated:** `scripts/control-dry-run.py::independent_worker_case`

### Scenario: Второй восстановитель

**Дано:** worker удерживает эксклюзивную блокировку журнала.
**Когда:** другой экземпляр пытается занять тот же каталог.
**Тогда:** захват отвергнут; после закрытия первого lock владение может перейти второму.

**Automated:** `Tests/VentilatorControlTests/FileSessionJournalTests.swift::testWorkerLockExcludesAnotherOwnerAndIsReleasedOnClose`

### Scenario: Изменён кандидатный план

**Дано:** экспортированный план с хешами app/helper и точными диапазонами.
**Когда:** изменена команда, lease, readiness, бинарник или предел.
**Тогда:** хеш либо проверка предпосылок перестаёт совпадать; даже исходный план остаётся неодобренным.

**Automated:** `Tests/VentilatorControlTests/CandidateExperimentPlanTests.swift`
