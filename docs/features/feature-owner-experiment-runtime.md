---
id: feature-owner-experiment-runtime
title: Подготовленный runtime единственного владельческого опыта
type: feature
status: active
owner: unassigned
involved_services: [ventilator-helper, ventilator-app]
client_entries: []
api: []
tags: [macOS, approval, XPC, broker, preparation]
---

# Runtime владельческого опыта

Одобренный hardware опыт завершён **recoveryRequired / restoreStepFailure** в 22:43:18 +05:00. Receipt consumed; reserved0/5–9, successful returns0/7–9, failed1/5/6. ManualZero1 отказал до reservation, остальные Fixed2–4 не выполнялись; 2500 RPM не наблюдены. Единственный independent snapshot — baseline до writes; physical Auto не подтверждён. Exact причины ошибок child reply потеряны прежним broker. Все пять Auto steps уже reserved; повторов, нового hardware owner плана, очистки pending и замены/restart службы не выполнять. Приложение остаётся read-only. [Actual audit](../research/evidence/current-hardware-failed-result.json). Source диагностический шаг сохраняет bounded phase/role/step/error/admission sample отдельно от independent reader evidence; модель не доказывает аппаратную причину.

Предыдущий owner сеанс schema4 завершён до запуска (исторический результат): exact signing/positive qualification, installed/root XPC и full review import прошли. Ввод APPROVE в A и START в B отклонён до start/approveLocally. Saved root audit содержит только challenge, без approval/ledger/outcome; hardware writes=0. Предыдущий wrapper не повторять. Было подготовлено [теперь завершённое продолжение установленной signed сборки](../current-hardware-continuation.md) с fresh audit/expired challenge и отдельными точными вводами B → A. Native подсказки уточнены в source, installed binaries пока прежние; новый полный PLAN объясняет их ввод. [Actual evidence](../research/evidence/current-hardware-declined-result.json).

Подготовленный source candidate теперь **schema4 / Mac15,7 / 27.0.1 / 26A434**. Старые schema3 binaries/reviews/seals сохранены; legacy profile/schema3 review отвергаются новой версией. Fresh read-only data подтверждают exact metadata/ranges, но запись/physical Auto не подтверждены. Новый [полный owner сеанс](../current-hardware-owner.md) связывает qualification/backup/update, empty root state audit, signed full review и отдельные TTY APPROVE/START. Без receipt устройство не открывается; GUI controls остаются false. На момент source подготовки installed helper был прежним и сообщал unsupportedMachine; последующий owner update описан выше. [Source verification](../research/evidence/current-experiment-source.json).

Owner сеанс новой identity завершён 2026-10-04 в 20:11:31 +05:00: **enabled, helperVerified=true, running root job PID 66079**, `readOnlyHelperVerified=true`. Owner сообщил ON и ALLOW; exact installed подпись/positive qualification и bound root XPC подтверждены. Сохранены 30 файлов completed пакета, old backup, 14 protected директорий и два прежних GUI marker; новый marker — третий. Staging/root runtime отсутствуют. Hardware status отдельно подтвердил **unsupportedMachine**, аппаратных записей 0, physicalAutoVerified=false. Завершённый run/register/ready не повторять. [Actual result](../research/evidence/gui-helper-identity-result.json).

Подключена подготовленная experimental связка XPC → локальный receipt → отдельный broker. **Hardware admission/begin выполнен, но опыт завершился recoveryRequired; управление/возврат Auto не квалифицированы.** Обычный GUI, `hardwareControlAvailable` и физическая квалификация остаются закрытыми. Этот документ описывает код и модельную проверку; он не разрешает запись на Mac15,7.

## Admission и процессы

Историческая source версия до schema4 оставляла diagnostics на 27.0.1 доступной и hardware runtime nil; эта signed версия была установлена до последующего owner update schema4. Новая source версия использует отдельный schema4 candidate текущей ОС. Anonymous unsupported модели теперь проверяют legacy 27.0.0/26A428, чужой build и неизвестную модель: authority/device не создаются. [Новая подготовка](../current-hardware-owner.md).

Signed daemon создаёт `ExperimentSessionRuntime.hardware()` только после root/installed/code-signature/profile/SMAppService enabled gates. Connection owner генерируется сервером для каждого XPC соединения и возвращается в preparation. Root TTY issuer из [протокола одобрения](feature-experiment-protocol.md) должен выдать receipt именно этому owner, plan и полному review; XPC не выдаёт одобрение.

Перед begin заново сверяются защищённый review, его digest, candidate и receipt. Отдельный preflight child возвращает read-only `BrokerObservation`; private pipe, nonce, domain, PID собственного Process и общий continuous deadline 2 с связывают ответ. Native sample имеет собственный бюджет 0.5 с. Требуются подтверждённый exit и свежий снимок. Ошибка до begin не расходует receipt и не открывает writer.

`ExperimentAuthority.begin` расходует receipt и сохраняет pending до запуска broker. Ошибка после begin сохраняет spent/pending; второй Fixed не допускается. У broker собственные private owner pipes, таймер и независимые Fixed/Auto/reader процессы. Hardware entry `--hardware-broker` принимает только fixed directory, inherited FIFO и installed root identity; `--hardware-preflight-child` не содержит writer. Native Fixed не начинается при отказе power observer; restart Auto этим дополнительным Fixed gate не блокируется.

Диагностический status читает атомарный защищённый снимок файла без transaction lock, чтобы polling не конкурировал с nonblocking reservation/admission writer. Status не выдаёт permits. Heartbeat/restore проверяют owner/session, затем отправляют bound broker frame. Invalidation/interruption закрывает owner pipe; broker самостоятельно начинает ограниченное восстановление. Ни XPC, ни proxy не принимают PID для сигнала.

В journal reader допустим `nlink=0` только у уже открытого private read descriptor: atomic rename мог убрать старое имя между openat и fstat, но inode/owner/mode/type не меняются. Lock требует ровно одну link; live hardlink, публичные права, неверный owner и symlink всё ещё отвергаются. Детерминированный тест сохраняет fd через настоящий rename и читает прежний snapshot.

Независимый reader сообщает `fixedRPMObserved` отдельным private event с scope и PID исходного reader. Это наблюдение режимов, целей и actual RPM по критерию кода; `physicalAutoVerified=false` сохраняется. Hardware outcome и pending не превращаются в пользовательскую квалификацию.

Отзыв Fixed теперь сначала сохраняется отдельным fsynced `fixed-revoked-<domain>.json` без authority transaction lock. Поэтому SIGSTOP внутри writer-транзакции не блокирует durable revocation. Reservation/executor/native pre-I/O проверяют этот marker. После confirmed writer exit broker сохраняет `fixedClosed`/restoration epoch в основном ledger и только затем начинает Auto. Marker не удаляется; уже начатый kernel I/O этим механизмом не отменяется.

## Startup recovery

До приёма XPC проверяется hardware ledger. При pending без наблюдённых Auto-кодов сверяются boot и бинарники. Если lifetime lock broker занят, второй broker не создаётся и неизвестные процессы не сигналятся. При свободном lock запускается restart broker с тем же consumed receipt; он допускает только оставшиеся Auto, сохраняет исходную epoch и не повторяет Fixed. Старый pending с другим boot/бинарником отказывает. После Auto-кодов hardware pending сохраняется для владельческого результата.

`HelperReply.hardwareExperiment` отделён от симуляционного `control`: domain/session/phase/pending/наблюдение Fixed. User availability остаётся false. Старый anonymous simulation listener по-прежнему всегда отвергает experimental start; отдельный private anonymous model listener использует immutable simulation authority и не может открыть native device.

## Границы

Native signed/root-owned installed/root XPC и administrative approval текущей read-only версии подтверждены; schema4 root runtime/import теперь подтверждены; hardware calls, actual sleep и физический Auto ещё не проверены. Owner CLI и [новый единый сеанс schema4](../current-hardware-owner.md) подготовлены. Исправленная сборка требует подписи/замены владельцем. `readyForOwnerApproval=false` в offline candidate сохраняется. Сценарии ниже проходят на non-root модели и не заменяют аппаратное одобрение.

## Клиент владельца и пакет сеанса

`InstalledHelperSession` удерживает одно audit/CDHash-verified соединение между prepare и start. Явный Terminal CLI `--run-owner-experiment reviewSHA` проверяет installed app/peer, получает connection owner, печатает адресную root TTY approval-команду и ждёт `START challengeUUID`. Start не повторяется; heartbeat, independent Fixed и Auto/status ограничены общим сроком 25 с. На ошибке соединение закрывается; broker остаётся ответственным за Auto. GUI этот путь не вызывает.

`--stage-local-hardware-review source SHA` требует installed root TTY/profile/service, полный canonical review с текущими бинарниками и отсутствие consumed ledger. Input — bounded regular no-follow file, без symlink/hardlink/FIFO. Только импорт защищённого review: approval/begin/SMC отсутствуют. `--owner-hardware-audit` читает ledger/outcome и текущий boot, не снимая pending.

Архивный wrapper для прежнего профиля (`owner-session.py`, [не выполнять](../owner-session.md)) создавал локальную копию, manifest с SHA-256 проверенных app/helper/plist/PLAN/script. Последующие sign/install/register/ready/run/collect/unregister требуют ручного non-root Terminal. Sign использует только подготовленный публичный certificate fingerprint, Hardened Runtime и отдельный процесс онлайн-проверки сертификата с positive revocation policy, timeout 20 с. После подписи создаются финальные candidate/review/seal; именно фактические signed hashes показываются в root approval. Notarization не заявлена, локальная Development сборка не квалифицирована для распространения. При любом отказе — остановка до записи, без обхода Gatekeeper или замены существующего installed app.

Полный UTF-8 план импортирован настоящим model CLI и совпал по Swift/Python canonical digest. Отказы owner-команд без TTY и ad hoc native gate проверены. Владелец подписал прежний пакет; исправленный read-only qualifier подтвердил подписи/сертификат, но старые executable содержат ошибку validation и не устанавливаются. Новая сборка требует повторной подписи; installed session не проверена. При qualification error script сохраняет исходный stderr в STOP, не повторяет подпись и не создаёт seal. Collect сохраняет ошибку отдельного чтения и продолжает остальные diagnostics. Outcome хранит максимум пять independent reader snapshots: baseline, первый подтверждённый Fixed и три Auto, включая actual/target/mode/pressure/timestamp/readSeconds. Эти данные предназначены для разбора владельцем, не выдают физическую qualification. Root result/consumed pending не удаляются. После failed Auto дополнительные ручные SMC attempts не реализованы: план предусматривает прекращение нагрузки и физическое выключение при неясном восстановлении.

## Code anchors

| Компонент | Code |
|---|---|
| Proxy/admission/startup | `Sources/VentilatorHelper/ExperimentSessionRuntime.swift` |
| Изолированный preflight | `Sources/VentilatorHelper/ExperimentPreflight.swift` |
| Daemon и XPC owner | `Sources/VentilatorHelper/HelperServer.swift`, `Sources/VentilatorControl/HelperProtocol.swift` |
| Broker и private hardware entries | `Sources/VentilatorHelper/ExperimentRecoveryBroker.swift`, `Sources/VentilatorHelper/HelperMain.swift` |
| Native child и recovery | `Sources/VentilatorExperiment/ScopedExperimentChild.swift`, `Sources/VentilatorExperiment/BrokerRestartRecovery.swift` |
| Клиент/публичный сертификат | `Sources/Ventilator/OwnerExperimentCLI.swift`, `Sources/VentilatorInstallation/InstalledHelperClient.swift`, `Sources/VentilatorInstallation/CertificateQualification.swift` |
| Failure diagnostics и модели | `Sources/VentilatorControl/FileSessionJournal.swift`, `Sources/VentilatorExperiment/ScopedExperimentChild.swift`, `scripts/failure-evidence-dry-run.py` |
| Terminal input и unstarted continuation | `Sources/VentilatorInstallation/OwnerExperimentTerminal.swift`, `scripts/current-hardware-continuation.py`, `scripts/current-hardware-continuation-dry-run.py` |
| Full review и owner package | `Sources/VentilatorControl/LocalApprovalReview.swift`, `Sources/VentilatorControl/LocalReviewFile.swift`, `Sources/VentilatorHelper/LocalApprovalCLI.swift`, `scripts/owner-session.py`, `scripts/owner-session-dry-run.py` |
| Process/XPC проверка | `Sources/VentilatorHelper/SessionRuntimeCheck.swift`, `scripts/session-runtime-dry-run.py` |

### Scenario: Неподтверждённый профиль сохраняет диагностику и закрывает аппаратный runtime

**Дано:** anonymous non-root модель, использующая тот же выбор runtime, с новой ОС, чужой сборкой или неизвестной моделью.
**Когда:** клиент запрашивает status, preparation и valid-form experimental start.
**Тогда:** idle diagnostic status доступен, preparation явно содержит unsupportedMachine/runtimePrepared=false, start отказывает до authority/device; hardware/simulation ledger отсутствуют. Installation status не выдаёт root proof модели. Immutable candidate не меняется.

**Automated:** `scripts/session-runtime-dry-run.py`

### Scenario: Receipt другого соединения не запускает broker

**Дано:** два model XPC соединения и локальный receipt первого owner.
**Когда:** второе соединение предъявляет правильный challenge/plan.
**Тогда:** отказ до begin, ledger ещё отсутствует; receipt не расходуется.

**Automated:** `scripts/session-runtime-dry-run.py`

### Scenario: Atomic snapshot переживает замену файла

**Дано:** reader открыл защищённый journal inode, затем writer атомарно заменил его.
**Когда:** old fd получает nlink=0 до проверки метаданных.
**Тогда:** private read snapshot доступен, тот же descriptor запрещён как lock; live hardlink и публичные permissions отвергаются.

**Automated:** `Tests/VentilatorControlTests/JournalSnapshotTests.swift`

### Scenario: Writer остановлен внутри authority transaction

**Дано:** модель writer сохраняет успешный target return и получает SIGSTOP, удерживая authority lock.
**Когда:** broker замечает timeout.
**Тогда:** отдельный durable marker закрывает Fixed до сигнала завершения; после writer exit ledger обновляется и Auto выполняется без повторов.

**Automated:** `scripts/recovery-dry-run.py`, `Tests/VentilatorExperimentTests/ExperimentWriteAdmissionTests.swift::testDurableRevocationDoesNotNeedStoppedWritersAuthorityLock`

### Scenario: Полный model путь подтверждает Fixed и Auto

**Дано:** model review/receipt того же XPC owner.
**Когда:** start проходит isolated preflight, heartbeat и explicit restore.
**Тогда:** независимый reader подтверждает Fixed, Auto-коды наблюдаются, replay не меняет spent ledger.

**Automated:** `scripts/session-runtime-dry-run.py`

### Scenario: Потеря XPC не лишает broker восстановления

**Дано:** model broker после consumed begin.
**Когда:** исходное XPC соединение invalidated.
**Тогда:** owner pipe закрывается, независимый broker возвращает модель в Auto; другой owner не управляет сеансом.

**Automated:** `scripts/session-runtime-dry-run.py`

### Scenario: Startup proxy не возобновляет Fixed

**Дано:** consumed model receipt и живой либо убитый собственный broker.
**Когда:** новый runtime выполняет startup recovery.
**Тогда:** живой lifetime lock исключает второй broker; после смерти — только оставшиеся Auto с тем же receipt, без повторов Fixed/Auto.

**Automated:** `scripts/session-runtime-dry-run.py`

### Scenario: Полный план импортируется без начала опыта

**Дано:** offline candidate и полный UTF-8 план сеанса с canonical digest.
**Когда:** model staging CLI импортирует review.
**Тогда:** digest совпадает между Python и Swift; review сохранён, approval/ledger/device отсутствуют; подмена digest и symlink отвергаются.

**Automated:** `scripts/owner-session-dry-run.py`, `Tests/VentilatorControlTests/LocalReviewFileTests.swift`

### Scenario: Команды участия владельца требуют Terminal

**Дано:** offline copied package и ad hoc сборка.
**Когда:** sign/install/register/ready/run/collect/unregister вызваны через pipe без Terminal.
**Тогда:** отказ до мутации; изменённый PLAN отвергается, native stage/audit и owner start не получают authority.

**Automated:** `scripts/owner-session-dry-run.py`

### Scenario: Отчёт содержит реальные независимые значения модели

**Дано:** model XPC опыт с успешным Fixed/Auto.
**Когда:** broker сохраняет outcome.
**Тогда:** baseline/Fixed/три Auto доступны в отчёте; actual модели 2400 не подменён target 2500; physicalAutoVerified не выставлен.

**Automated:** `scripts/session-runtime-dry-run.py`

### Scenario: Ошибка qualification и отдельного чтения видна владельцу

**Дано:** subprocess с non-zero exit и диагностическим stderr либо ошибкой чтения при collect.
**Когда:** session wrapper обрабатывает результат.
**Тогда:** STOP сохраняет exit и причину; collect сохраняет ошибку конкретного чтения и продолжает status/audit. Нет автоматического повторения или аппаратного запуска.

**Automated:** `scripts/owner-session-dry-run.py`

### Scenario: Ввод из другого окна не запрашивает аппаратный start

**Дано:** Terminal A ожидает адресную START строку; Terminal B показывает полный review/confirmation.
**Когда:** в A вводится APPROVE, bare START либо неполный/неверный UUID, или в B вводится START/bare APPROVE.
**Тогда:** A отвергает ввод до start RPC; B отвергает до сохранения approval. Нет ledger/device. Native source сообщает отсутствие start запроса отдельно от возможного отказа уже отправленного RPC; успешный B печатает полную START строку для A.

**Automated:** `Tests/VentilatorInstallationTests/OwnerExperimentTerminalTests.swift::testOnlyCompleteStartLineProducesChallengeForRPC`, `Tests/VentilatorExperimentTests/LocalApprovalIssuerTests.swift::testDeclineEOFAndPartialConsentNeverApprove`

### Scenario: Продолжение допускает только истёкший запрос без одобрения и запуска

**Дано:** exact installed qualified signed файлы, completed32/protected16/privateGUI4/full review и current boot.
**Когда:** владелец запускает новый отдельный wrapper.
**Тогда:** fresh root audit обязан совпасть с прежним challenge, уже истёкшим по continuous clock; approval/ledger/outcome/другой boot/challenge блокируют review import и client. Подпись/lifecycle не повторяются. Client failure сохраняет audit; replay не запускает клиент повторно.

**Automated:** `scripts/current-hardware-continuation-dry-run.py`

### Scenario: Причина исходного отказа сохраняется после ошибки Auto

**Дано:** file-model unlock возвращает успех без наблюдаемого эффекта; опционально оба Auto mode writes отказывают.
**Когда:** ManualZero admission отвергается и broker выполняет единственную ограниченную попытку Auto.
**Тогда:** initial unsafeObservation и последующие failedStep сохраняются с phase/role/step и уже прочитанным admission sample; последний restoreStepFailure не стирает исходную причину. Diagnostic samples не становятся independent Fixed/Auto evidence; reservations одноразовые и pending остаётся при ошибке Auto. Native hardware допускает только normal fault.

**Automated:** `scripts/failure-evidence-dry-run.py`

### Scenario: Старый hardware outcome читается без новой диагностики

**Дано:** сохранённый JSON до optional failures.
**Когда:** новый decoder читает outcome, либо сохраняется oversized diagnostic list с неизвестным clock.
**Тогда:** legacy failures=nil; новый список ограничен первыми16, error512 символами, невалидный elapsed остаётся nil. PhysicalAutoVerified=false и admission samples отделены от independent observations.

**Automated:** `Tests/VentilatorControlTests/RecoveryFailureEvidenceTests.swift::testLegacyHardwareOutcomeDecodesWithoutNewDiagnostics`, `Tests/VentilatorControlTests/RecoveryFailureEvidenceTests.swift::testDiagnosticLimitsKeepEarliestFailureAndUnknownTimeIsNotInvented`
