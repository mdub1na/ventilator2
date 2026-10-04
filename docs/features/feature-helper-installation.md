---
id: feature-helper-installation
title: Подготовка подписи и проверка установленного helper
type: feature
status: active
owner: unassigned
involved_services: [ventilator-app, ventilator-helper]
client_entries: []
api: []
tags: [macOS, signing, SMAppService, XPC, preparation]
---

# Подпись и installed gate

Текущее состояние 2026-10-04: новая exact signed/root-owned копия установлена, backup подтверждён; один register требует approval. Owner ON прошёл без administrative prompt, subsequent verify и один developer status сохранили requiresApproval/serviceNotEnabled. Settings on не совпадает с global parent BTM disallowed/pending. Положительного root XPC новой сборки нет. [Markers и scoped state](../research/evidence/owner-read-only-update-installed-pending.json). Следующий [owner сеанс](../helper-read-only-approval.md) проверяет существующее уведомление и собирает global job/BTM snapshot, с одной conditional peer проверкой; новую подпись/установку/register не выполняет. [Frozen подготовка](../research/evidence/owner-read-only-approval-preparation.json).

Реализованы диагностика bundle, явные app CLI-команды регистрации и ограниченный XPC handshake. После одного owner off/on **system job загружен**, хотя parent BTM всё ещё содержит pending authorization. Один installed XPC verify получил enabled/deadline: helper завершается на runtime с untrustedSignature. Read-only проверка обнаружила смену ОС на **27.0.1 (26A434)** при candidate **27.0.0 (26A428)**; профиль ошибочно объединялся с signature guard. Root XPC ещё не подтверждён; GUI-кнопки RPM отключены. [Последние факты](../research/evidence/owner-system-approval-result.json).

Исправленный daemon на неподтверждённом профиле проходит прежний signed/root-owned identity gate и сохраняет диагностический XPC, не создавая аппаратный runtime/authority и не вызывая startup hardware recovery. Preparation/start явно отказывают с unsupportedMachine; старый аппаратный candidate не расширен. Installation status по-прежнему читает существующий pending journal и не очищает его. Новая копия установлена, actual signed root positive ожидает завершения системного разрешения.

`--read-only-update` готовит отдельный pinned пакет из новой ad hoc сборки и exact прежней установки. Один owner `update-read-only` связывает sign → public qualification → OFF → guarded unregister → проверенную замену с backup → один register → при необходимости ON → один root verify/status. Marker исключает повтор, неизвестный runtime/job/hash и любые отказы останавливают последующие действия. Seal содержит signed fingerprints; hardware candidate/review/receipt не сохраняются. Пакет запрещает ready/run/collect/setup и отдельные lifecycle команды. Полная последовательность и argv заданы в [плане read-only обновления](../owner-helper-update.md); подготовка и модели — [в свидетельстве](../research/evidence/owner-profile-update-package.json).

Прежний [системный сеанс](../helper-registration-approval.md) завершён: owner off/on загрузил job. Его frozen script/plan и снимок сохраняются, повтор не разрешён. Parent pending text сохранился при загруженном job, поэтому не является самостоятельным критерием успеха. [Подготовка](../research/evidence/owner-system-approval-session.json), [фактический результат](../research/evidence/owner-system-approval-result.json).

2026-10-04: owner подпись обновления завершилась, но public qualification отказала до OFF с -67635 «не удалось проверить аннулирование». Сохранены все 12 файлов, установленная копия неизменна. `prepare --read-only-update --signed-session --previous-session` теперь импортирует exact signature-complete source, остановленный до lifecycle действий, в новый пакет. Все source файлы связаны и проверяются после копирования; markers должны совпасть с fingerprint/previous pin, read-only source не может стать hardware package. Разработчик завершил одну public qualification нового продолжения на тех же файлах: positiveRevocation=true, новой подписи нет. До seal owner update запрещён; после seal он начинает с OFF. [Отказ](../research/evidence/owner-profile-update-qualification-stop.json), [seal и сохранность](../research/evidence/owner-profile-update-resume-package.json), [полная новая последовательность](../owner-helper-update-resume.md). Actual новой установки/root XPC ещё нет.

## Проверки и границы

`SignedBundleInspector` проверяет точный Info/LaunchDaemon layout, регулярные app/helper/plist без symlink, Apple anchor/identifiers/общий Team ID, строгие подписи всех архитектур и вложенного кода. Для операций lifecycle и root helper требуется `/Applications/Ventilator.app`, все элементы bundle принадлежат root и не доступны для group/other write. Неполный обход файлов отвергается. Снимок связывает SHA-256 app/helper/plist и CDHash обеих программ. Это проверка кода/файлов; она не подтверждает регистрацию или живой процесс.

Проверяются expiration и системные trust anchors; network lookup отключён в этих диагностических/device путях. Строгая code-signature проверка требует explicit Apple anchor/identifier/leaf OU; отдельный BasicX509 trust использует системные anchors без network fetch. Online CodeSigning + обязательный положительный revocation-ответ проверяются отдельным процессом до seal, с внешним сроком 20 с; notarization не заявляется. SDK-флаг `checkTrustedAnchors` оказался недопустимым для validation на macOS 27 (`-67070`); оставлены реально проверенные `considerExpiration`/`noNetworkAccess`. [Матрица флагов и qualification](../research/evidence/owner-signing-validation.json).

Для signed installed ветки требуется Hardened Runtime без разрешений debugger, DYLD injection, unsigned executable memory, JIT или отключения library validation. Signing wrapper задаёт runtime; native gate сверяет flags/entitlements. Эта policy проверена на данных модели и на сохранённом подписанном владельцем пакете. На момент исправления validation executable требовали новой подписи; старый пакет с ошибкой устанавливать нельзя. Последующая owner подпись и текущее состояние приведены ниже.

Перед запуском обычного daemon, root simulation worker и подготовленного аппаратного device проверяется также динамическая подпись текущего процесса по CDHash. Приложение явно отказывается запускаться от root. Root-owned расположение — наш выбор для фиксированного M2 bundle, не требование Apple ко всем приложениям SMAppService.

`CurrentExecutable` получает путь загруженного executable через `_NSGetExecutablePath`; argv[0] не используется для bundle, candidate hashes или дочерних процессов. По [Apple dyld](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/dyld.3.html) путь может содержать symlink: helper не скрывает его через realpath, прежний layout gate по-прежнему отвергает aliases. Relative/foreign/opaque argv[0] реально проверены из cwd=/ на app/helper. Startup log `dev.ventilator.helper/startup` фиксирует этап identity/runtime/listener и отказ без nonce/approval содержимого.

`InstalledHelperClient` использует privileged Mach service. Обе стороны XPC требуют Apple anchor, точный identifier/Team ID и CDHash своего counterpart. Каждый запрос имеет новый nonce и срок 2 с по continuous clock. JSON не аутентифицирует peer: UID/PID берутся из `NSXPCConnection`, UID должен быть root, PID должен совпасть с reply. Версия, nonce, CDHash и все три digest сверяются; oversized (>16 KiB), поздний, чужой или заявляющий hardware control ответ отвергается. Успешный handshake означает живой проверенный helper, не SMC admission или физический Auto.

`installationStatus` не создаёт approval/ledger и не вызывает SMC. При наличии hardware журнала он читает pending, при ошибке чтения возвращает отказ. Anonymous simulation не может выдать installation proof. Новый RPC — диагностический внутренний XPC, сетевого API нет.

## Явные app CLI-команды

Все команды выполняются обычным пользователем из app executable:

| Команда | Поведение |
|---|---|
| `--helper-status` | Диагностика подписи, местоположения, прав, регистрации; при enabled и валидном bundle проверяется XPC. Ошибка отражается в JSON. Регистрацию не меняет. |
| `--verify-installed-helper` | Та же проверка; exit 78, если helper не подтверждён. |
| `--register-helper` | После native gates один register для notRegistered/notFound. Enabled/requiresApproval без повторного register. Только framework error 1 с actual requiresApproval возвращает отчёт с registrationDiagnostic; другие ошибки сохраняются, retry нет. |
| `--unregister-helper` | Enabled требует живой root XPC без pending hardware/active simulation. Для requiresApproval разрешён только узкий pre-experiment repair при lstat ENOENT всего runtime root. Файл/каталог/broken symlink/ошибка доступа блокируют этот путь. NotRegistered — без изменения. |

Положительная регистрация требует административного одобрения по [Apple](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29). `enabled` означает допуск службы, не подтверждение процесса. На ad hoc bundle register/unregister отказывают до framework mutation. До исправления на owner-signed installed bundle status=notFound: системный журнал подтвердил отсутствие BTM record, а не повреждённый plist. Прежний код ошибочно превращал это состояние в invalidLayout и не вызывал первую регистрацию; исправлен переход. [Фактический результат](../research/evidence/owner-registration-failure.json). Enabled служба, privileged XPC и unregister ещё не проверены; текущий этап requiresApproval описан ниже.

`owner-session.py replace-installed` допускает только точные прежние signed hashes, native trusted/root-owned/installed identity, notFound/notRegistered/requiresApproval с serviceNotEnabled и отсутствие **всего** runtime root. Enabled никогда не допускается. После отключения фонового разрешения владельцем оставшийся точный inactive launchd job допускает один scoped bootout; active PID/чужие metadata/ошибка чтения запрещают его. Перед staging и mv job обязан отсутствовать. Staging копируется/chown/chmod и проверяется native inspector, затем прежняя установка повторно проверяется и сохраняется как backup. Existing stage/backup/marker блокируют повтор, ошибка ничего не удаляет. Новые stage/backup paths сохраняют прежний backup. Policy/orchestration проверены на mocked командах, реальная новая замена ещё не выполнена.

Фактическое продолжение 2026-10-02: владелец выполнил replacement, новый installed fingerprint совпадает с seal, backup — с предыдущим pin. Framework register вернул `SMAppServiceErrorDomain / 1 / Operation not permitted`; subsequent status **requiresApproval**, BTM log `registerLaunchItem: result=no error` и disallowed disposition. Apple DTS [описывает error 1 до административного одобрения](https://developer.apple.com/forums/thread/802443). Wrapper сохраняет ошибку и печатает STOP; диагноз требует чтения actual status, номер ошибки сам по себе не разрешает продолжение. На данном пакете подтверждено ожидание одобрения. Следующий шаг уже есть в sealed PLAN: системное разрешение Ventilator, затем ready. Повтор register/sign/replace не нужен; бинарники, session.py/PLAN/review не меняются. [Результат](../research/evidence/owner-helper-approval-pending.json). Enabled root XPC, unregister и аппаратное одобрение ещё не проверены.

2026-10-03: системное разрешение выполнено, ready остановился с deadline до root review staging. Launchd успешно spawn-ил helper, тот завершался exit 78 до listener. Старое приложение с относительным argv[0] воспроизвело invalidLayout; фактический argv root-процесса и точный этап прежнего отказа не установлены. Runtime root отсутствовал; аппаратный опыт не начинался. Прежний sealed пакет сохраняется целиком, изменённый код требует новой подписи и полной процедуры disabled update. [Факты](../research/evidence/owner-ready-deadline.json), [план](../owner-session.md).

## Подпись без диалогов

После удаления владельцем установленных копий подготовлен fresh пакет из неизменённого signed source. `prepare --signed-session --fresh-install` сохраняет исходный pin в provenance, но не переносит его как требование новой установки; вместе с `--previous-session` или без signed source отказывает. Package check показывает выбранный путь и installationMode. Install запрещён для replacement manifest, существующего app/backup/stage/runtime/job; до sudo создаётся exclusive marker, partial failure сохраняет файлы и запрещает повтор, после копирования проверяются native signed/root-owned/installed identity и hashes. Fresh register проверяет exact report: notFound/notRegistered → один register; requiresApproval сохраняется без unregister/register при отсутствующих runtime/job. Enabled не меняется; unknown state, смена fingerprint, state/job, ошибка и неожиданный post-register status останавливают путь. Ошибка называет native action; marker запрещает повтор. Полный PLAN включает exact installed GUI и административное одобрение. [Подготовка первого fresh пакета](../research/evidence/owner-fresh-install-package.json).

Actual первый fresh пакет PR #18 содержал прежнее автоматическое unregister/register. Установка прошла; system log подтверждает unregister error=0 и status 2→0, затем через 70 мс register error=1, `Job is not allowed to bootstrap`, status=0. Повторы wrapper заблокированы до новых native операций. Read-only Settings сейчас показывает on, BTM parent содержит pending authorization, job/runtime root отсутствуют; почему разрешение не стало effective, не доказано. Apple DTS обсуждает race немедленного unregister/register даже после completion; это внешнее свидетельство, не доказательство причины на macOS 27. Новый wrapper сохраняет pending регистрацию; модель проверяет отсутствие обеих lifecycle mutations, но остановленный sealed пакет не переписан и не возобновлён. Факт административного подтверждения ожидается от владельца. [Диагноз и сохранённые хеши](../research/evidence/owner-fresh-register-denied.json), [Apple DTS о re-registration](https://developer.apple.com/forums/thread/783539).

Последующее подтверждение владельца: запрос администратора был и подтверждён. Read-only native status всё ещё notRegistered, job/runtime отсутствуют; причина effective authorization не установлена. `prepare --signed-session --continue-installed` создаёт **новый** полный review для exact уже установленной unstarted копии. До native status проверяются отсутствие runtime/job и совпадение source/installed hashes; admission повторяется после копирования. Прежний source pin сохраняется только в provenance, manifest содержит installedContinuation с текущим fingerprint; check отвергает несовпадение и смешанные режимы. Install/replacement в этом режиме запрещены. `setup` требует owner Terminal и этот mode: один bounded register при notFound/notRegistered, pending не меняет, ready вызывается только после enabled. Ready проверяет root XPC и импортирует review с owner sudo; approval/start не выполняются. Pending/failure сохраняют marker без повторов. Actual подготовка, strict verify и одна public qualification прошли на прежних signed файлах. Старый stopped пакет сохранён целиком (16 SHA); новый root XPC всё ещё требует владельца. [Факты и новый пакет](../research/evidence/owner-installed-continuation.json), [полный план](../owner-session.md).

Новая проверка после включения фоновой активности: Settings показывает on, но actual SMAppService по-прежнему requiresApproval. BTM parent текущего installed app содержит pending authorization; helper allowed, launchd job отсутствует, runtime root отсутствует. Поэтому переключатель не является критерием успеха daemon approval; нужен фактический enabled и проверенный root XPC. Apple DTS описывает Allow системного уведомления с подтверждением администратора. Причина расхождения на macOS 27 и факт auth prompt не установлены; не повторять регистрацию и не сбрасывать BTM для обхода этого отказа. [Свидетельство](../research/evidence/owner-system-authorization-pending.json), [Apple DTS](https://developer.apple.com/forums/thread/802443).

После новой регистрации владелец получил `requiresApproval/serviceNotEnabled`; `ready` остановился с тем же статусом. Native status отказывает до root XPC, wrapper — до protected review staging. Требуется системное разрешение фоновой активности Ventilator, затем `ready` после изменения этого состояния; новая подпись/замена/регистрация не нужна. Переключатель Settings и успешный root handshake пока не проверены. [Вывод владельца](../research/evidence/owner-helper-update-completed.json), [нужный раздел настроек](https://support.apple.com/ru-ru/guide/mac-help/mtusr003/mac).

2026-10-03, продолжение: защищённая замена исправленной сборки владельцем завершена. Installed hashes совпадают с новым seal/completion marker, backup — с прежним pin, stage/runtime root отсутствуют. Повтор replace-installed отказывает до мутаций, поскольку проверяет pin прежней версии. Native installed gates новой сборки прошли; actual registration=requiresApproval. Следующий уже описанный в sealed PLAN шаг — unregister/register, включить фоновое разрешение, ready. Новая подпись/замена/repin не нужны; exact root XPC ещё не проверен. [Свидетельство](../research/evidence/owner-helper-update-completed.json).

2026-10-03: после подписи новой сборки owner команда sign опять остановилась на positive-revocation evaluation. Оба файла уже подписаны: strict verify прошёл, отдельная public проверка exact файлов затем прошла без ключа. Это не доказательство отзыва сертификата; причина различия network/cache/process не установлена. Теперь `sign` завершает только два codesign/strict verify и сохраняет signature-ready, `qualify` отдельно проверяет public certificate и создаёт seal. `check` показывает signature/certificateQualification/fullReview раздельно; stopped этап сохраняет запрет повторов, завершённая подпись не объявляется потерянной. Текущий owner пакет импортируется из сохранённых signed файлов и квалифицируется разработчиком; новой подписи/пересборки нет. [Результат](../research/evidence/owner-signing-stages.json).

Дополнение 2026-10-02: `owner-session.py prepare --signed-session` копирует сохранённый failed signing package в новый output с текущим полным PLAN/script, проверкой исходных bindings/owner signing marker и неизменности signed хешей при копировании. Прежний installed pin переносится. Частичный seal, изменённые инструкции или отсутствие marker запрещают импорт. `sign` для такого пакета запрещён. Отдельный `qualify` не требует TTY: он не использует ключ/sudo/service/device, только public certificate CLI (20 с) и candidate CLI. До seal проверяются exact leaf/Team/positive revocation/неизменные хеши и инструкции. Одноразовый marker запрещает повтор после ошибки; диагноз и новый пакет предшествуют следующей попытке. Это подготовка полного review, а не локальное аппаратное одобрение. [Реальный отказ и последующий успех](../research/evidence/owner-revocation-failure.json).

`scripts/sign-app-without-ui.py` читает public fingerprint настроенных identities, исключает явно flagged записи и требует единственного кандидата. Wrapper `tools/sign_without_ui.swift` сначала создаёт отдельную security session без graphics/TTY и проверяет эти атрибуты. Только после этого разрешён exec `/usr/bin/codesign` для собственного staging bundle в `.build`; исходный ad hoc bundle сохраняется. Keychain не разблокируется, ключи не экспортируются, ACL не изменяются. После обеих подписей нужны strict verify и native inspector.

На текущем Mac SessionCreate вернул `OSStatus=100001`, wrapper завершился до codesign. [Результат](../research/evidence/installation-signing.json): `signed=false`, `signingAttempted=false`, `headlessSecuritySessionUnavailable`. Это прежняя бездиалоговая попытка. Подпись владельцем затем прошла, но старый qualification завершился exit 78 из-за недопустимого флага. После исправления владелец повторно подписал пакет, создал seal и установил root-owned bundle; эти gates подтверждены на реальных файлах. Первая регистрация остановилась на неверной предварительной проверке notFound. Владелец затем выполнил ограниченную замену; BTM регистрация ожидает системного одобрения. Enabled root XPC/удаление, настоящий сон и аппаратный опыт ещё не проверены.

## Code anchors

| Компонент | Code |
|---|---|
| Layout, подписи, root ownership и runtime | `Sources/VentilatorInstallation/SignedBundleInspector.swift` |
| Путь загруженного executable | `Sources/VentilatorInstallation/CurrentExecutable.swift` |
| XPC peer, nonce, fingerprint и срок | `Sources/VentilatorInstallation/InstalledHelperClient.swift`, `Sources/VentilatorControl/HelperProtocol.swift` |
| Registration/removal | `Sources/VentilatorInstallation/HelperServiceController.swift`, `Sources/Ventilator/HelperServiceCLI.swift` |
| Server/client requirements | `Sources/VentilatorHelper/HelperServer.swift`, `Sources/VentilatorHelper/HelperMain.swift` |
| Native gate | `Sources/VentilatorExperiment/NativeExperimentDevice.swift` |
| Signing gate | `tools/sign_without_ui.swift`, `scripts/sign-app-without-ui.py` |
| Owner seal и online public certificate qualification | `scripts/owner-session.py`, `Sources/VentilatorInstallation/CertificateQualification.swift` |
| Диагностическое обновление неподтверждённого профиля | `scripts/read-only-update-dry-run.py`, `Sources/VentilatorHelper/SessionRuntimeCheck.swift` |
| Снимок system job / BTM и один owner цикл системного разрешения | `scripts/helper-registration-diagnostics.py`, `scripts/helper-registration-diagnostics-dry-run.py` |
| Проверки | `Tests/VentilatorInstallationTests/InstallationTests.swift`, `scripts/installation-dry-run.py` |

### Scenario: Ad hoc bundle не устанавливает helper

**Дано:** текущая ad hoc сборка вне installed location.
**Когда:** вызываются status, verify, register или unregister.
**Тогда:** helperVerified/hardwareControlAvailable=false; verify/mutations завершаются exit 78, регистрация не меняется.

**Automated:** `scripts/installation-dry-run.py`

### Scenario: Подменённый executable или LaunchDaemon

**Дано:** bundle с лишними launch arguments, чужим executable/service или symlink.
**Когда:** выполняется инспекция.
**Тогда:** layout отвергнут до service mutation.

**Automated:** `Tests/VentilatorInstallationTests/InstallationTests.swift::testLaunchLayoutRejectsAnotherExecutableExtraArgumentsOrMachService`, `Tests/VentilatorInstallationTests/InstallationTests.swift::testUnsignedBundleAndSymlinkAreRejectedBeforeServiceAccess`

### Scenario: Путь, права или requirement не допускают регистрацию

**Дано:** модель policy proof для staging/writable bundle либо недопустимый Team/CDHash.
**Когда:** проверяется installed policy или строится requirement.
**Тогда:** доступ отвергнут; валидные CDHash requirements компилируются нативным Security API.

**Automated:** `Tests/VentilatorInstallationTests/InstallationTests.swift::testStagingLocationOrWritableOwnershipCannotRegister`, `Tests/VentilatorInstallationTests/InstallationTests.swift::testPinnedRequirementsCompileAndRejectInjection`, `Tests/VentilatorInstallationTests/InstallationTests.swift::testHardenedRuntimeCannotOptIntoDebuggingOrInjectedCode`

### Scenario: Ответ не подтверждает проверенного peer

**Дано:** модель bound installed reply.
**Когда:** audit UID/PID, nonce, версия, digest, claim либо срок не совпали.
**Тогда:** validation отвергнута; поздний/сломанный clock не выдаёт proof.

**Automated:** `Tests/VentilatorInstallationTests/InstallationTests.swift::testPeerAuditUIDAndPIDOverrideReplyClaims`, `Tests/VentilatorInstallationTests/InstallationTests.swift::testWrongNonceFingerprintVersionOrHardwareClaimCannotVerify`, `Tests/VentilatorInstallationTests/InstallationTests.swift::testLateOrBrokenClockNeverVerifiesDaemon`

### Scenario: Pending запрещает removal

**Дано:** модель reply с pending hardware или активной/неопределённой simulation.
**Когда:** проверяется removal policy.
**Тогда:** unregister запрещён; ошибка не подменяется idle.

**Automated:** `Tests/VentilatorInstallationTests/InstallationTests.swift::testPendingRecoveryOrActiveSimulationBlocksRemoval`

### Scenario: Отказ headless session не запускает подпись

**Дано:** настроенная identity и signing wrapper.
**Когда:** SessionCreate не может создать подтверждённую сессию без UI.
**Тогда:** codesign не вызывается; исходный bundle, keychain и hardware не изменяются.

**Automated:** `scripts/sign-app-without-ui.py`

### Scenario: Нативный validation принимает флаги и проверяет requirement

**Дано:** подписанный XCTest executable и текущий процесс.
**Когда:** Security API вызывается с используемыми offline-флагами.
**Тогда:** допустимый requirement проходит static/dynamic проверку, чужой identifier отвергается; ошибка invalid flags не маскирует результат.

**Automated:** `Tests/VentilatorInstallationTests/InstallationTests.swift::testValidationFlagsAreAcceptedByNativeAPIAndRejectWrongRequirement`

### Scenario: Первая регистрация не требует существующей BTM record

**Дано:** identity/layout gates прошли, preliminary status notFound либо notRegistered.
**Когда:** владелец вызывает register.
**Тогда:** framework вызывается один раз; его ошибка сохраняется без retry, enabled/requiresApproval не регистрируются повторно.

**Automated:** `Tests/VentilatorInstallationTests/InstallationTests.swift::testFirstRegistrationDoesNotRequireExistingServiceRecord`, `Tests/VentilatorInstallationTests/InstallationTests.swift::testFirstRegistrationPreservesFrameworkErrorWithoutRetry`

### Scenario: Замена не затрагивает активную или изменённую установку

**Дано:** pinned previous fingerprint и replacement package.
**Когда:** registration/identity/hash/journal не удовлетворяют policy либо installed hash меняется во время staging.
**Тогда:** замена отвергнута; после изменения hash обе mv-команды не выполняются, marker сохраняется. Успех модели сохраняет старый bundle до переноса нового.

**Automated:** `scripts/owner-session-dry-run.py`

### Scenario: Диагностический снимок не допускает неподтверждённый запуск sudo

**Дано:** frozen диагностический пакет с привязкой к текущим owner/installed файлам.
**Когда:** collect вызван без owner TTY, от root или после подмены скрипта, owner seal либо installed helper.
**Тогда:** отказ происходит до привилегированных команд; marker до попытки не создаётся. Допустимый collect выполняет только два фиксированных system read, app/helper не запускаются.

**Automated:** `scripts/helper-registration-diagnostics-dry-run.py`

### Scenario: Зависшее системное чтение сохраняет неполный результат

**Дано:** owner collect и read-only system utility после sudo authentication.
**Когда:** дочерняя утилита не завершает чтение либо sudo отказывает.
**Тогда:** alarm переживает exec и завершает utility, exit/неполнота сохраняются без объявления готовности; отказ первой команды исключает вторую, повторный collect не запускает sudo. Owner package не меняется.

**Automated:** `scripts/helper-registration-diagnostics-dry-run.py`

### Scenario: Снимок BTM сохраняет только записи Ventilator

**Дано:** BTM dump с несколькими UID, embedded numbering и записями других приложений.
**Когда:** snapshot извлекает app/helper records.
**Тогда:** UID, URL и parent disposition Ventilator сохраняются, похожее имя с другим identifier и чужие записи исключаются. Незнакомый формат помечается отдельно; пустой stdout не доказывает отсутствие records.

**Automated:** `scripts/helper-registration-diagnostics-dry-run.py`

### Scenario: Системный цикл требует отсутствующего job и runtime

**Дано:** пакет одного owner цикла, привязанный к предыдущему полному административному снимку и исходному owner UID.
**Когда:** runtime существует или недоступен, job загружен, owner UID либо прошлый снимок изменился.
**Тогда:** отказ происходит до owner UI prompt и sudo. Старый аппаратный пакет сохраняется.

**Automated:** `scripts/helper-registration-diagnostics-dry-run.py`

### Scenario: Отмена и повтор системного цикла

**Дано:** допустимый owner сеанс с exclusive marker до ручного системного действия.
**Когда:** владелец отменяет ввод либо сообщает DONE после одного цикла; затем пытается повторить collect.
**Тогда:** отмена исключает sudo; DONE выполняет только два фиксированных system read, сохраняет owner report без hardware approval. Повтор не показывает UI prompt и не вызывает sudo. DONE само по себе не подтверждает системное разрешение или root peer.

**Automated:** `scripts/helper-registration-diagnostics-dry-run.py`

### Scenario: Read-only update завершает ограниченную замену

**Дано:** отдельный pinned read-only пакет без аппаратного review, runtime отсутствует.
**Когда:** владелец выполняет один update-read-only с OFF и при необходимости ON.
**Тогда:** подпись/public qualification завершаются до мутаций, old identity/notRegistered подтверждаются до замены, backup сохраняется до установки, один register и root verify/status собирают результат с аппаратным отказом unsupportedMachine. При уже проверенном enabled повтор verify/ON не выполняется.

**Automated:** `scripts/read-only-update-dry-run.py`

### Scenario: Read-only update останавливает отказы и повтор

**Дано:** неподписанный либо sealed read-only пакет с exact прежним pin.
**Когда:** signing/qualification, OFF/ON, runtime/hash, removal, register, root peer или hardware denial не подтверждены; либо команда повторяется.
**Тогда:** последующие действия не выполняются, markers/partial files сохраняются, sign/qualification/lifecycle/UI не повторяются. Hardware review и восемь отдельных запрещённых CLI-команд отвергаются; без owner TTY update не начинается.

**Automated:** `scripts/read-only-update-dry-run.py`

### Scenario: Read-only продолжение сохраняет завершённую подпись

**Дано:** read-only source остановлен на qualification после signature-ready и до OFF; прежняя installed копия закреплена отдельным sealed пакетом.
**Когда:** prepare получает --read-only-update, --signed-session и --previous-session.
**Тогда:** CLI копирует exact signed bytes без ключа/кандидата, связывает каждый source файл и проверяет неизменность после копирования. Изменённые markers/PLAN/executable, lifecycle или hardware файлы отвергаются; read-only source не может стать hardware package.

**Automated:** `scripts/read-only-update-dry-run.py`

### Scenario: Public seal предшествует owner продолжению

**Дано:** импортированный signatureReady read-only пакет без seal.
**Когда:** вызываются owner update, sign либо developer qualify.
**Тогда:** update отказывает до marker/OFF/system actions, sign не обращается к ключу. Только один qualify может создать seal без hardware review; повтор запрещён. Исходный остановленный пакет сохраняется.

**Automated:** `scripts/read-only-update-dry-run.py`

### Scenario: Снимок новой установленной копии связывает stopped source и backup

**Дано:** read-only update завершил replacement и register, затем остановился с requiresApproval.
**Когда:** готовится prepare-read-only и запускается diagnostic collect.
**Тогда:** 17 source файлов, installed fingerprint, backup, owner UID и exact неподтверждённая машина закреплены в manifest; изменение любой привязки или advanced source отказывает. Existing/unreadable runtime и отсутствие owner Terminal исключают первый owner prompt/sudo.

**Automated:** `scripts/helper-registration-diagnostics-dry-run.py`

### Scenario: Сообщение ALLOW не заменяет проверку root peer

**Дано:** frozen read-only consent inspection с ответом ALLOW либо NONE после просмотра существующего уведомления.
**Когда:** выполняются один administrative job/BTM snapshot и условная проверка установленного helper.
**Тогда:** missing job сохраняет pending без app invocation; загруженный job допускает одну bounded диагностику только при отсутствии runtime. Sudo отказ, BTM timeout, peer refusal или timeout сохраняются без positive proof и повторов. Успех требует actual enabled/root peer/exact hashes/hardwareControlAvailable=false; отмена и source race до sudo исключают последующие вызовы. Ни register, ни аппаратное одобрение не выполняются.

**Automated:** `scripts/helper-registration-diagnostics-dry-run.py`

### Scenario: Installed continuation связывает установленную копию без замены

**Дано:** сохранённый signed source и exact уже установленный unstarted bundle.
**Когда:** prepare получает --continue-installed.
**Тогда:** admission проверяется до/после копирования пакета; signatureReady сохраняется, operative old pin отсутствует, installedContinuation совпадает с fingerprint. Check показывает installationMode=installed, новый полный review запечатывается без подписи. Install/replacement, missing source и смешанные режимы отвергаются без внешних мутаций.

**Automated:** `scripts/owner-session-dry-run.py`

### Scenario: Continuation не активирует helper при неизвестном runtime

**Дано:** runtime path, broken alias, ошибка доступа, любой job или другой installed hash.
**Когда:** проверяется admission продолжения.
**Тогда:** отказ происходит до запуска installed app; runtime/approval/journal сохраняются. Disabled native report обязан подтвердить identity/ownership/hashes; enabled, чужой report hash и неверные права отвергаются.

**Automated:** `scripts/owner-session-dry-run.py`

### Scenario: Setup импортирует review только после enabled

**Дано:** sealed installed continuation в owner Terminal.
**Когда:** вызывается setup.
**Тогда:** register следует one-shot policy без unregister; ready выполняется только после enabled. Pending, failed register и другой package mode не выполняют ready; approval/аппаратный start в setup отсутствуют. Без owner Terminal отказ предшествует действиям.

**Automated:** `scripts/owner-session-dry-run.py`

### Scenario: Fresh import сохраняет источник без требования прежней установки

**Дано:** сохранённый signed source с прежним installed pin и запрос --fresh-install.
**Когда:** prepare создаёт новый пакет и полный review.
**Тогда:** исходные файлы/provenance сохраняются; operative pin отсутствует, sign запрещён, новый review включает весь fresh PLAN. Отсутствующий signed source и сочетание с previous-session отвергаются до создания пакета.

**Automated:** `scripts/owner-session-dry-run.py`

### Scenario: Чистая установка не заменяет оставшееся состояние

**Дано:** fresh пакет и целевой app/backup/stage/runtime path либо launchd job.
**Когда:** вызывается install.
**Тогда:** существующий путь, broken runtime alias, ошибка доступа и любой job запрещают копирование. Допустимая установка сохраняет marker до трёх sudo команд, проверяет native installed identity после копирования; copy/ownership/native отказ и повтор не вызывают новые sudo команды. Replacement пакет не устанавливается как fresh.

**Automated:** `scripts/owner-session-dry-run.py`

### Scenario: Fresh register сохраняет ожидающую одобрения регистрацию

**Дано:** exact signed installed proof и actual service status.
**Когда:** fresh wrapper выполняет register.
**Тогда:** notFound/notRegistered допускают один register; requiresApproval без runtime/job сохраняется без unregister/register. Enabled не меняется. Unknown status, чужой hash до/после register, state/job, ошибка и неожиданный post-register status останавливают путь. Ошибка называет --register-helper; marker запрещает повтор попытки, включая ожидание системного одобрения.

**Automated:** `scripts/owner-session-dry-run.py`

### Scenario: Отказ проверки отзыва не требует повторной подписи

**Дано:** сохранённый unsealed signing package с owner marker, валидными исходными bindings и прежним installation pin.
**Когда:** подготовлен новый пакет из signed файлов и вызван qualify.
**Тогда:** source не меняется, sign запрещён; seal создаётся только после exact certificate/Team/positive response и проверки хешей/инструкций. Timeout/отказ/подмена не создают seal; повтор не вызывает external CLI. Ad hoc fixture отвергается реальным native gate, положительный путь проверен отдельно на ответе модели.

**Automated:** `scripts/owner-session-dry-run.py`

### Scenario: Первая системная регистрация ожидает администратора

**Дано:** исправленный signed/root-owned installed bundle совпадает с seal; прежний bundle сохранён в backup.
**Когда:** owner register возвращает framework error 1, затем выполнена read-only диагностика.
**Тогда:** BTM record создана, status=requiresApproval, helperVerified/hardwareControlAvailable=false. Следующий предусмотренный шаг — системное одобрение; до него root XPC и аппаратная готовность не подтверждены, register не повторяется.

Проверено на Mac15,7/macOS 27; [ручное свидетельство](../research/evidence/owner-helper-approval-pending.json).

### Scenario: Относительное имя запуска не меняет bundle

**Дано:** реальный app/helper запускается из cwd=/ с относительным, чужим абсолютным или opaque argv[0].
**Когда:** выполняется status либо candidate-plan.
**Тогда:** используется загруженный executable; layout достигает прежнего ad hoc signature refusal, candidate hashes соответствуют реальным файлам, записей нет.

**Automated:** `scripts/installation-dry-run.py`, `Tests/VentilatorInstallationTests/InstallationTests.swift::testLoadedExecutablePathMatchesSecurityCodeIdentity`

### Scenario: Disabled repair не удаляет runtime state

**Дано:** requiresApproval либо иной service status и путь runtime root.
**Когда:** проверяется unstarted removal.
**Тогда:** только requiresApproval с lstat ENOENT допускается; enabled/неизвестное состояние, файл и broken symlink отвергаются. В wrapper active/неопределённый launchd job запрещает update, job после staging останавливает оба mv.

**Automated:** `Tests/VentilatorInstallationTests/InstallationTests.swift::testUnapprovedUnstartedRemovalRequiresAbsentRuntimeRoot`, `scripts/owner-session-dry-run.py`

### Scenario: Error 1 сам по себе не означает ожидание одобрения

**Дано:** framework registration error и actual post-register status.
**Когда:** выбирается pending-approval response.
**Тогда:** только SMAppServiceErrorDomain/code 1 с requiresApproval допускает diagnostic response; другие domain/code/status остаются ошибками без retry.

**Automated:** `Tests/VentilatorInstallationTests/InstallationTests.swift::testRegistrationErrorNeedsActualPendingApprovalState`

### Scenario: Отказ public qualification сохраняет завершённую подпись

**Дано:** owner подпись обоих файлов завершена и strict verify прошёл.
**Когда:** public qualification останавливается либо владелец повторно вызывает sign.
**Тогда:** check показывает signature=complete, certificateQualification=stopped, fullReview=notSealed; повтор sign не вызывает codesign. Sign сам не вызывает public qualification, sealed import показывает оба complete только после полного bound check.

**Automated:** `scripts/owner-session-dry-run.py`
