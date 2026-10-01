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

Реализованы диагностика bundle, явные app CLI-команды управления регистрацией и ограниченный XPC handshake. Владелец подписал и установил прежний пакет: native static/dynamic подписи, root ownership, installed path и совпадение seal подтверждены. **Первая регистрация остановилась до framework register**, privileged XPC не проверен. Новая исправленная сборка ad hoc требует подписи/замены владельцем. Это gate M2, не аппаратная готовность; GUI-кнопки RPM отключены.

## Проверки и границы

`SignedBundleInspector` проверяет точный Info/LaunchDaemon layout, регулярные app/helper/plist без symlink, Apple anchor/identifiers/общий Team ID, строгие подписи всех архитектур и вложенного кода. Для операций lifecycle и root helper требуется `/Applications/Ventilator.app`, все элементы bundle принадлежат root и не доступны для group/other write. Неполный обход файлов отвергается. Снимок связывает SHA-256 app/helper/plist и CDHash обеих программ. Это проверка кода/файлов; она не подтверждает регистрацию или живой процесс.

Проверяются expiration и системные trust anchors; network lookup отключён в этих диагностических/device путях. Строгая code-signature проверка требует explicit Apple anchor/identifier/leaf OU; отдельный BasicX509 trust использует системные anchors без network fetch. Online CodeSigning + обязательный положительный revocation-ответ проверяются отдельным процессом до seal, с внешним сроком 20 с; notarization не заявляется. SDK-флаг `checkTrustedAnchors` оказался недопустимым для validation на macOS 27 (`-67070`); оставлены реально проверенные `considerExpiration`/`noNetworkAccess`. [Матрица флагов и qualification](../research/evidence/owner-signing-validation.json).

Для signed installed ветки требуется Hardened Runtime без разрешений debugger, DYLD injection, unsigned executable memory, JIT или отключения library validation. Signing wrapper задаёт runtime; native gate сверяет flags/entitlements. Эта policy проверена на данных модели и на сохранённом подписанном владельцем пакете. Исправленные executable ещё нужно подписать; старый пакет с ошибкой validation устанавливать нельзя.

Перед запуском обычного daemon, root simulation worker и подготовленного аппаратного device проверяется также динамическая подпись текущего процесса по CDHash. Приложение явно отказывается запускаться от root. Root-owned расположение — наш выбор для фиксированного M2 bundle, не требование Apple ко всем приложениям SMAppService.

`InstalledHelperClient` использует privileged Mach service. Обе стороны XPC требуют Apple anchor, точный identifier/Team ID и CDHash своего counterpart. Каждый запрос имеет новый nonce и срок 2 с по continuous clock. JSON не аутентифицирует peer: UID/PID берутся из `NSXPCConnection`, UID должен быть root, PID должен совпасть с reply. Версия, nonce, CDHash и все три digest сверяются; oversized (>16 KiB), поздний, чужой или заявляющий hardware control ответ отвергается. Успешный handshake означает живой проверенный helper, не SMC admission или физический Auto.

`installationStatus` не создаёт approval/ledger и не вызывает SMC. При наличии hardware журнала он читает pending, при ошибке чтения возвращает отказ. Anonymous simulation не может выдать installation proof. Новый RPC — диагностический внутренний XPC, сетевого API нет.

## Явные app CLI-команды

Все команды выполняются обычным пользователем из app executable:

| Команда | Поведение |
|---|---|
| `--helper-status` | Диагностика подписи, местоположения, прав, регистрации; при enabled и валидном bundle проверяется XPC. Ошибка отражается в JSON. Регистрацию не меняет. |
| `--verify-installed-helper` | Та же проверка; exit 78, если helper не подтверждён. |
| `--register-helper` | После native identity/layout/ownership gate один раз вызывает register для notRegistered/notFound. Enabled/requiresApproval не регистрируются повторно. Framework error сохраняется, автоматического retry нет. |
| `--unregister-helper` | После identity gate и живого enabled XPC запрещает удаление при pending hardware или активной/неопределённой simulation. Для notRegistered — без изменения. |

Положительная регистрация требует административного одобрения по [Apple](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29). `enabled` означает допуск службы, не подтверждение процесса. На ad hoc bundle register/unregister отказывают до framework mutation. На owner-signed installed bundle status=notFound: системный журнал подтвердил отсутствие BTM record, а не повреждённый plist. Прежний код ошибочно превращал это состояние в invalidLayout и не вызывал первую регистрацию; исправлен переход. [Фактический результат](../research/evidence/owner-registration-failure.json). Положительная регистрация, privileged XPC и unregister ещё не проверены.

`owner-session.py replace-installed` допускает только точные прежние signed hashes из manifest, native trusted/root-owned/installed identity, notFound/notRegistered с serviceNotEnabled и отсутствие любого `/Library/Application Support/Ventilator`. Сначала staging копируется/chown/chmod и проверяется native inspector, затем прежняя установка проверяется повторно и сохраняется как backup; только после этого новая переносится на fixed path. Existing stage/backup и одноразовый marker блокируют повтор; ошибка ничего не удаляет. Pure policy и orchestration с mocked внешними командами проверены; реальная privileged замена требует владельца по [полному плану](../owner-session.md).

## Подпись без диалогов

`scripts/sign-app-without-ui.py` читает public fingerprint настроенных identities, исключает явно flagged записи и требует единственного кандидата. Wrapper `tools/sign_without_ui.swift` сначала создаёт отдельную security session без graphics/TTY и проверяет эти атрибуты. Только после этого разрешён exec `/usr/bin/codesign` для собственного staging bundle в `.build`; исходный ad hoc bundle сохраняется. Keychain не разблокируется, ключи не экспортируются, ACL не изменяются. После обеих подписей нужны strict verify и native inspector.

На текущем Mac SessionCreate вернул `OSStatus=100001`, wrapper завершился до codesign. [Результат](../research/evidence/installation-signing.json): `signed=false`, `signingAttempted=false`, `headlessSecuritySessionUnavailable`. Это прежняя бездиалоговая попытка. Подпись владельцем затем прошла, но старый qualification завершился exit 78 из-за недопустимого флага. После исправления владелец повторно подписал пакет, создал seal и установил root-owned bundle; эти gates подтверждены на реальных файлах. Первая регистрация остановилась на неверной предварительной проверке notFound. Новая сборка требует подписи и ограниченной замены; положительная регистрация/удаление, настоящий сон и аппаратный опыт ещё не проверены.

## Code anchors

| Компонент | Code |
|---|---|
| Layout, подписи, root ownership и runtime | `Sources/VentilatorInstallation/SignedBundleInspector.swift` |
| XPC peer, nonce, fingerprint и срок | `Sources/VentilatorInstallation/InstalledHelperClient.swift`, `Sources/VentilatorControl/HelperProtocol.swift` |
| Registration/removal | `Sources/VentilatorInstallation/HelperServiceController.swift`, `Sources/Ventilator/HelperServiceCLI.swift` |
| Server/client requirements | `Sources/VentilatorHelper/HelperServer.swift`, `Sources/VentilatorHelper/HelperMain.swift` |
| Native gate | `Sources/VentilatorExperiment/NativeExperimentDevice.swift` |
| Signing gate | `tools/sign_without_ui.swift`, `scripts/sign-app-without-ui.py` |
| Owner seal и online public certificate qualification | `scripts/owner-session.py`, `Sources/VentilatorInstallation/CertificateQualification.swift` |
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
