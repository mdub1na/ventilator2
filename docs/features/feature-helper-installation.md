---
id: feature-helper-installation
title: Подготовка подписи и проверка установленного helper
type: feature
status: active
owner: unassigned
involved_services: [ventilator-app, ventilator-helper]
client_entries: [screen-application]
api: []
tags: [macOS, signing, SMAppService, XPC, preparation]
---

# Подпись и installed gate

Owner сеанс новой identity завершён 2026-10-04 в 20:11:31 +05:00: **enabled, helperVerified=true, running root job PID 66079**, `readOnlyHelperVerified=true`. Owner сообщил ON и ALLOW; exact installed подпись/positive qualification и bound root XPC подтверждены. Сохранены 30 файлов completed пакета, old backup, 14 protected директорий и два прежних GUI marker; новый marker — третий. Staging/root runtime отсутствуют. Hardware status отдельно подтвердил **unsupportedMachine**, аппаратных записей 0, physicalAutoVerified=false. Завершённый run/register/ready не повторять. [Actual result](../research/evidence/gui-helper-identity-result.json).

Новая compiled identity — `dev.ventilator.app` / `dev.ventilator.app.helper`; Apple anchor/Team/CDHash и root peer gates сохранены. Legacy layout/extra plist отказывают до signature/framework. Новая сборка проверена на модели, на момент подготовки installed версия была прежней. Подготовлен один [owner сеанс](../gui-helper-identity-owner.md) для проверки гипотезы identity history с positive qualification, pending/absent-only removal, exact backup и явными CONNECTED → ON → ALLOW/NONE. [Source evidence](../research/evidence/helper-identity-source-preparation.json).

После owner включения actual AX ON независимо подтверждён; единственный native status в 19:13:33 +05:00 остался **requiresApproval/serviceNotEnabled**, helperVerified=false. CLI exit 0 означает завершение диагностики. Frozen continuation4, completed reconnect30, protected12, installed5 и private GUI2 сохранены; runtime отсутствует, hardware writes 0. ON не привёл к root positive. Повтор статуса/регистрации не выполняется; исследуется системный допуск. [Actual result](../research/evidence/gui-helper-enable-result.json).

Владелец подтвердил, что после последнего register пропустил ON. Подготовлено [продолжение только с включением фоновой активности](../gui-helper-enable-owner.md): существующая установка/регистрация сохраняются, после owner ON агент независимо проверяет переключатель и делает один bounded native status. Повтор signing/reconnect/register не нужен. ON/positive root пока не подтверждены, hardware writes 0.

Owner [guarded reconnect](../gui-helper-reconnect-owner.md) завершён: qualification и root staging предшествовали OFF, actual requiresApproval и два absent-job gates допустили прежний guarded unregister; exact backup/replacement и одно новое GUI register выполнены. Итог требует системного одобрения, root job отсутствует; текущий Settings switch **OFF**, owner NONE не подтверждает фактический ON. Source без mainApp startup query установлен, но этого оказалось недостаточно в достигнутом состоянии. Владелец затем подтвердил пропуск ON; повтор lifecycle не требуется, следующий план продолжает только это включение. Hardware review/start отсутствуют, Mac остаётся read-only. [Actual result](../research/evidence/gui-helper-reconnect-result.json).

Administrative read выполнен владельцем: system job absent (113), четыре BTM records для UID -2/0/501 содержат allowed без pending authorization/disallowed. Current framework status в collector не читался; одно последующее обновление того же GUI показало enabled с connectionFailed и lookup No such process. Не требуется повтор collect. Недоступный mainApp login item теперь не обращается к ServiceManagement при monitoring startup; эта source поправка не заявлена как ремонт BTM. [Снимок](../research/evidence/gui-helper-state-result.json).

Owner GUI update завершён: installed/payload совпадают с новой квалифицированной подписью, прежняя копия сохранена. Exclusive marker подтверждает одно GUI register; системный журнал фиксирует disallowed/bootstrap error 1 до first light. Поздний CLI report enabled/remoteFailure и отсутствующий system job не подтверждают root helper. Следующий [пакет только чтения](../gui-helper-state-owner.md) проверяет completed update/installed/GUI hashes, owner/machine/boot и private marker до административного чтения launchd/BTM; framework status, XPC, registration и аппаратный runtime не вызываются. [Actual result](../research/evidence/gui-helper-update-result.json).

Подготовлен отдельный полный [GUI owner update](../gui-helper-owner-update.md). Новая подпись/positive qualification и root-owned staging/static inspection выполняются до conditional guarded unregister прежней копии; old bytes сохраняются в non-app backup. Root job после removal должен отсутствовать до mv. Новая GUI app открывается только canonical, сама не регистрирует helper; один explicit click сохраняет user marker. После ALLOW/NONE читаются actual status/job; успешный root peer отдельно от GUI attempt и только затем unsupportedMachine diagnostic status. CLI register, OFF/ON, hardware review/approval/start не вызываются. Replay, unknown/changed runtime/job/hash/marker/native reply останавливаются с сохранением путей. Actual owner update ещё не выполнен. [Подготовка/проверки](../research/evidence/gui-helper-update-preparation.json).

В исходниках добавлен [GUI раздел помощника](../screens/screen-application.md): проверка статуса/XPC вне UI потока, одно explicit register из main actor только после подписанного canonical root-owned process и совпадения fingerprint с прочитанным состоянием. Pending/enabled не вызывают claim/register. Перед register создаётся exclusive/fsynced marker для owner и трёх signed hashes в приватном user Application Support; restart не стирает failed attempt. Файлы аппаратного review/authority не используются. Enabled без bound root verification не показывается как «Помощник доступен». Этот код ещё не установлен в production bundle; положительный GUI registration/root peer на нём требует отдельного owner update.

Owner archive-only continuation завершён: exact signed probe архивирован в новый non-app bundle, installed target отсутствует, текущий status=notRegistered и root job absent. Старые 21 файл и девять protected директорий совпали; registration/unregister не повторялись. [Фактический итог](../research/evidence/registration-probe-archive-result.json).

## История isolated probe

2026-10-04: owner GUI probe подтверждён — после ALLOW status=enabled, root job running; один unregister вернул notRegistered и absent job (113). Архивирование остановилось после CLOSED на живом GUI PID. Подписанная тестовая копия сохранена в /Applications, старые 21 файл/девять protected директорий неизменны. Direct production status после probe всё ещё requiresApproval; production root XPC не подтверждён. [Факты и границы](../research/evidence/registration-probe-result.json).

Отдельный archive-only continuation допускает только уже снятый с регистрации exact probe. Он сохраняет прежний frozen session, ждёт фактического завершения GUI, читает один текущий probe status/absent system job и переносит пять signed файлов в новый non-app архив. Register/unregister/signing не повторяются; marker закрывает повтор после попытки. [Полный порядок владельца](../registration-probe-archive-owner.md). Actual перенос этим продолжением пока не выполнен.

## История подготовки до GUI probe

Добавлен отдельный diagnostic GUI probe (`dev.ventilator.registration-probe` / `.daemon`) с noop daemon и своим owner пакетом. Он не линкует модули Ventilator/аппаратный транспорт, не подтверждает production root XPC и не ремонтирует его регистрацию. CLI inspect/qualify не создают SMAppService; GUI registration и cleanup требуют canonical root-owned signed process, pinned Team/certificate и exact owner seal. Marker предшествует каждому sole register/unregister; retry закрыт. Owner workflow подписывает/qualifies до установки, scope root commands ограничен probe, cleanup подтверждает absent job/GUI exit и архивирует exact bundle. [Полный сеанс](../registration-probe-owner.md). Actual signed/system positive ещё не выполнен.

2026-10-04 14:29 +05:00 прямой installed `--helper-status` подтвердил requiresApproval после перезапуска, при прежних exact fingerprints/owner/machine/boot и отсутствии runtime. Предыдущее «не запрашивался» ниже относится к завершённому collector. [Прямой ответ](../research/evidence/post-restart-framework-state.json).

Текущее состояние 2026-10-04, после перезапуска: другой boot подтверждён, administrative root lookup снова вернул 113. BTM убрал pending authorization у parent, global parent остался disallowed, child enabled/allowed не изменился. Native verification и framework status после перезапуска не запрашивались. Общая метка systemApprovalPending в frozen скрипте не доказывает actual requiresApproval. Installed/backup и прежние сеансы сохранены; положительного root XPC нет, причина отсутствия службы не установлена. Collection/setup/register/ready не повторять. [Результат и сохранность](../research/evidence/after-restart-result.json). До перезапуска register/verify возвращали requiresApproval; уведомления не было. [Предыдущий снимок](../research/evidence/owner-read-only-approval-result.json).

Реализованы диагностика bundle, явные app CLI-команды регистрации и ограниченный XPC handshake. В предыдущем сеансе один owner off/on загрузил system job, хотя parent BTM всё ещё содержал pending authorization. Тогда installed XPC verify получил enabled/deadline: старый helper завершался на runtime с untrustedSignature. Read-only проверка обнаружила смену ОС на **27.0.1 (26A434)** при candidate **27.0.0 (26A428)**; профиль ошибочно объединялся с signature guard. GUI-кнопки RPM отключены. [Исторический результат старой сборки](../research/evidence/owner-system-approval-result.json).

Исправленный daemon на неподтверждённом профиле проходит прежний signed/root-owned identity gate и сохраняет диагностический XPC, не создавая аппаратный runtime/authority и не вызывая startup hardware recovery. Preparation/start явно отказывают с unsupportedMachine; старый аппаратный candidate не расширен. Installation status по-прежнему читает существующий pending journal и не очищает его. Новая копия установлена, actual signed root positive ещё не подтверждён. После перезапуска отсутствие job сохранено; причина и актуальный framework status не установлены.

`--read-only-update` готовит отдельный pinned пакет из новой ad hoc сборки и exact прежней установки. Один owner `update-read-only` связывает sign → public qualification → OFF → guarded unregister → проверенную замену с backup → один register → при необходимости ON → один root verify/status. Marker исключает повтор, неизвестный runtime/job/hash и любые отказы останавливают последующие действия. Seal содержит signed fingerprints; hardware candidate/review/receipt не сохраняются. Пакет запрещает ready/run/collect/setup и отдельные lifecycle команды. Полная последовательность и argv заданы в [плане read-only обновления](../owner-helper-update.md); подготовка и модели — [в свидетельстве](../research/evidence/owner-profile-update-package.json).

Прежний [системный сеанс](../helper-registration-approval.md) завершён: owner off/on загрузил job. Его frozen script/plan и снимок сохраняются, повтор не разрешён. Parent pending text сохранился при загруженном job, поэтому не является самостоятельным критерием успеха. [Подготовка](../research/evidence/owner-system-approval-session.json), [фактический результат](../research/evidence/owner-system-approval-result.json).

2026-10-04: owner подпись обновления завершилась, но public qualification отказала до OFF с -67635 «не удалось проверить аннулирование». Сохранены все 12 файлов, установленная копия неизменна. `prepare --read-only-update --signed-session --previous-session` теперь импортирует exact signature-complete source, остановленный до lifecycle действий, в новый пакет. Все source файлы связаны и проверяются после копирования; markers должны совпасть с fingerprint/previous pin, read-only source не может стать hardware package. Разработчик завершил одну public qualification нового продолжения на тех же файлах: positiveRevocation=true, новой подписи нет. До seal owner update запрещён; после seal он начинает с OFF. [Отказ](../research/evidence/owner-profile-update-qualification-stop.json), [seal и сохранность](../research/evidence/owner-profile-update-resume-package.json), [полная новая последовательность](../owner-helper-update-resume.md). Actual новой установки/root XPC ещё нет.

## Проверки и границы

`prepare-after-restart` связывает новый frozen сеанс с завершённым NONE/absent-job snapshot и текущим boot UUID. Collector допускает только другую загрузку на той же owner/machine, без нового notification/toggle prompt. Before-marker gates сохраняют installed/source/backup/runtime; два bounded read и одна conditional peer проверка используют прежний diagnostic path. [Полный порядок](../helper-after-restart.md) и [подготовка](../research/evidence/after-restart-preparation.json) сохраняются как история завершённого сеанса. Перезапуск не загрузил helper; повтор не назначен. Новая диагностика различает rootJobAbsent, факт native CLI попытки и registrationStatus из ответа; отсутствующий/неполный/malformed ответ не подставляет requiresApproval.

`--inspect-signed-bundle [absolute-bundle-path]` проверяет только файлы указанного либо текущего bundle и возвращает registration=notQueried, helperVerified=false, hardwareControlAvailable=false. Ошибка подписи/layout даёт JSON с error и exit 78; relative/лишние arguments отвергаются до inspection. Этот путь не создаёт SMAppService и не связывается с XPC; canonical location/root ownership отражаются в отчёте, но не являются обязательными для статической диагностики. Replacement запускает pinned исходную app для чтения staging файлов, временная копия не исполняется. До обоих mv требуются trusted/root-owned exact fingerprint, installedLocation=false, notQueried, отсутствие error и peer/hardware claims.

`--helper-status` допускает ServiceManagement только после non-root, статической подписи, canonical installed/root-owned bundle и динамической identity текущего процесса. При отказе registration остаётся notQueried; после допуска framework state читается один раз, peer проверяется только при enabled. Это предотвращает обновление BTM appURL диагностической временной копией; успех системного consent этим не заявляется. Frozen пакеты прежних сеансов и текущие signed installed binaries не изменяются при обновлении исходников.

`SignedBundleInspector` проверяет точный Info/LaunchDaemon layout, регулярные app/helper/plist без symlink, Apple anchor/identifiers/общий Team ID, строгие подписи всех архитектур и вложенного кода. Для операций lifecycle и root helper требуется `/Applications/Ventilator.app`, все элементы bundle принадлежат root и не доступны для group/other write. Неполный обход файлов отвергается. Снимок связывает SHA-256 app/helper/plist и CDHash обеих программ. Это проверка кода/файлов; она не подтверждает регистрацию или живой процесс.

Проверяются expiration и системные trust anchors; network lookup отключён в этих диагностических/device путях. Строгая code-signature проверка требует explicit Apple anchor/identifier/leaf OU; отдельный BasicX509 trust использует системные anchors без network fetch. Online CodeSigning + обязательный положительный revocation-ответ проверяются отдельным процессом до seal, с внешним сроком 20 с; notarization не заявляется. SDK-флаг `checkTrustedAnchors` оказался недопустимым для validation на macOS 27 (`-67070`); оставлены реально проверенные `considerExpiration`/`noNetworkAccess`. [Матрица флагов и qualification](../research/evidence/owner-signing-validation.json).

Для signed installed ветки требуется Hardened Runtime без разрешений debugger, DYLD injection, unsigned executable memory, JIT или отключения library validation. Signing wrapper задаёт runtime; native gate сверяет flags/entitlements. Эта policy проверена на данных модели и на сохранённом подписанном владельцем пакете. На момент исправления validation executable требовали новой подписи; старый пакет с ошибкой устанавливать нельзя. Последующая owner подпись и текущее состояние приведены ниже.

Перед запуском обычного daemon, root simulation worker и подготовленного аппаратного device проверяется также динамическая подпись текущего процесса по CDHash. Приложение явно отказывается запускаться от root. Root-owned расположение — наш выбор для фиксированного M2 bundle, не требование Apple ко всем приложениям SMAppService.

`CurrentExecutable` получает путь загруженного executable через `_NSGetExecutablePath`; argv[0] не используется для bundle, candidate hashes или дочерних процессов. По [Apple dyld](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/dyld.3.html) путь может содержать symlink: helper не скрывает его через realpath, прежний layout gate по-прежнему отвергает aliases. Relative/foreign/opaque argv[0] реально проверены из cwd=/ на app/helper. Startup log `dev.ventilator.app.helper/startup` фиксирует этап identity/runtime/listener и отказ без nonce/approval содержимого.

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
| Read-only reconnect после startup isolation | `scripts/gui-helper-reconnect.py`, `scripts/gui-helper-reconnect-dry-run.py` |
| Одно административное чтение после завершённого GUI update | `scripts/gui-helper-state.py`, `scripts/gui-helper-state-dry-run.py` |
| Изолированный GUI probe, static/process/owner gates | `Diagnostics/RegistrationProbe/ProbeApp.swift`, `Diagnostics/RegistrationProbe/ProbeBundle.swift` |
| Noop daemon и отдельная сборка | `Diagnostics/RegistrationProbe/ProbeDaemon.swift`, `scripts/build-registration-probe.py` |
| Полный owner run и модель | `scripts/registration-probe-session.py`, `scripts/registration-probe-dry-run.py` |
| Завершение переноса stopped probe без lifecycle повторов | `scripts/registration-probe-archive.py`, `scripts/registration-probe-archive-dry-run.py` |
| GUI state/registration и per-owner marker | `Sources/Ventilator/HelperSetupView.swift`, `Sources/VentilatorInstallation/HelperSetupModel.swift`, `Sources/VentilatorInstallation/GUIRegistrationAttempt.swift` |
| Полный diagnostic GUI update | `scripts/gui-helper-update.py`, `scripts/gui-helper-update-dry-run.py` |
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

### Scenario: Administrative read сохраняет расхождение регистрации и root job

**Дано:** completed GUI update с enabled/remoteFailure, сохранёнными signed hashes и private GUI attempt.
**Когда:** владелец один раз запускает pinned collect в своём обычном Terminal.
**Тогда:** читаются только system job и BTM; сохраняются только parent/helper records Ventilator вместе с UID. Absent job даёт rootJobAbsent, loaded job — rootPeerUnverified; registrationStatus остаётся null, nativeVerificationAttempted/helperVerified=false. Аппаратных записей нет.

**Automated:** `scripts/gui-helper-state-dry-run.py`

### Scenario: OFF допускает только штатное снятие unstarted регистрации

**Дано:** checked startup-isolated payload, exact previous installation и absent hardware runtime на unsupported Mac.
**Когда:** owner reconnect прошёл qualification/staging, root job absent и владелец сообщил OFF.
**Тогда:** actual framework требует requiresApproval/serviceNotEnabled либо already unregistered. Old unregister вызывается не более одного раза только после второго absent-job gate; enabled/loaded/unknown/changed state останавливают его. Qualified new bundle заменяет exact old bytes с backup; новое GUI register остаётся sole explicit action.

**Automated:** `scripts/gui-helper-reconnect-dry-run.py`

### Scenario: Reconnect сохраняет отсутствие root proof и запрещает повтор

**Дано:** source/protected/boot change, отказ qualification/OFF/removal, cancel либо уже начатый reconnect.
**Когда:** выполняется reconnect.
**Тогда:** запретные дальнейшие lifecycle действия не выполняются, старые protected файлы не переписываются; повтор после run-started не повторяет signing/root commands. После завершённого failed peer либо pending outcome root helper и hardware не объявляются готовыми.

**Automated:** `scripts/gui-helper-reconnect-dry-run.py`

### Scenario: Неизвестное состояние и повтор административного чтения останавливаются

**Дано:** changed package/installed/GUI/boot, unsafe marker, failed qualification, неполный read или уже созданный started.
**Когда:** выполняется collect.
**Тогда:** admission failures не доходят до root read, replay не повторяет root read; read failures сохраняют diagnosticIncomplete, изменение во время чтения останавливает следующий read. Framework/registration/XPC и прежние файлы не мутируются.

**Automated:** `scripts/gui-helper-state-dry-run.py`

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

### Scenario: Проверка после перезапуска требует другой загрузки

**Дано:** frozen пакет с prepared boot UUID и точными файлами завершённого NONE/absent-job snapshot, stopped update, installed и backup.
**Когда:** подготовка либо collect выполняется при changed files/owner/machine/runtime или в прежней загрузке.
**Тогда:** подготовка/допуск отказывает, same boot и existing runtime не создают marker и не вызывают sudo; новый collector не возобновляет старые пакеты и не предлагает UI цикл.

**Automated:** `scripts/helper-registration-diagnostics-dry-run.py`

### Scenario: Новая загрузка не объявляет helper готовым без bound ответа

**Дано:** другая загрузка на pinned неподтверждённой машине.
**Когда:** collector выполняет два scoped administrative read и условную native peer проверку.
**Тогда:** absent job даёт rootJobAbsent и registrationStatus=null; sudo/alarm/неизвестный BTM format запрещает peer; runtime appearance пропускает peer; timeout/плохой ответ остаётся unverified. Только exact bound positive даёт readOnlyHelperVerified, без hardware claim; повторы ничего не вызывают.

**Automated:** `scripts/helper-registration-diagnostics-dry-run.py`

### Scenario: Отсутствие job не выдаётся за ожидание системного разрешения

**Дано:** administrative job result и, только при выполненной native verification, её JSON reply.
**Когда:** сохраняется diagnostic outcome.
**Тогда:** rootJobLoaded вычисляется только из launchd exit 0/113; nativeVerificationAttempted отражает отдельный CLI вызов. RegistrationStatus остаётся null при absent job, runtime skip, timeout, неизвестном или non-object reply и наблюдается только из native enum value. Sudo/alarm у BTM сохраняет stoppedAt=btm, неизвестный успешный format — btmFormat; malformed reply не подтверждает helper.

**Automated:** `scripts/helper-registration-diagnostics-dry-run.py`

### Scenario: Status временной или непроверенной копии не обращается к службе

**Дано:** staging/writable bundle, root процесс, ошибка подписи либо dynamic process identity.
**Когда:** выполняется status.
**Тогда:** registration=notQueried, helperVerified=false; ServiceManagement и peer не вызываются. Для admitted installed процесса state читается один раз; только enabled допускает peer verification, peer ошибка сохраняется.

**Automated:** `Tests/VentilatorInstallationTests/InstallationTests.swift::testStatusRejectsUnadmittedBundleBeforeServiceOrPeerAccess`, `Tests/VentilatorInstallationTests/InstallationTests.swift::testStatusRejectsRootSignatureOrProcessFailureBeforeServiceAccess`, `Tests/VentilatorInstallationTests/InstallationTests.swift::testStatusQueriesOnlyAdmittedProcessAndVerifiesOnlyEnabledPeer`

### Scenario: Staging проверяется только статически перед заменой

**Дано:** signed staging bundle и pinned fingerprint.
**Когда:** replacement проверяет новую копию.
**Тогда:** pinned исходная app вызывает --inspect-signed-bundle с абсолютным staging path; staging executable не запускается. NotQueried и отсутствие peer/hardware claims обязательны; writable/error/changed hash либо service/peer claim останавливают оба mv. Прежние повторные проверки installed bundle и launchd gates сохраняются.

**Automated:** `Tests/VentilatorInstallationTests/InstallationTests.swift::testStaticInspectionReportsFilesWithoutInstalledAdmission`, `scripts/owner-session-dry-run.py`, `scripts/read-only-update-dry-run.py`, `scripts/installation-dry-run.py`

### Scenario: Отказ public qualification сохраняет завершённую подпись

**Дано:** owner подпись обоих файлов завершена и strict verify прошёл.
**Когда:** public qualification останавливается либо владелец повторно вызывает sign.
**Тогда:** check показывает signature=complete, certificateQualification=stopped, fullReview=notSealed; повтор sign не вызывает codesign. Sign сам не вызывает public qualification, sealed import показывает оба complete только после полного bound check.

**Automated:** `scripts/owner-session-dry-run.py`

### Scenario: Отдельная регистрационная проверка не исполняет аппаратный код

**Дано:** ad hoc probe либо неканонический процесс без sealed owner session.
**Когда:** запрашивается inspect/qualify/status/cleanup или preview.
**Тогда:** неподписанная Apple identity и неустановленные lifecycle пути отказывают до SMAppService; preview имеет отключённые service controls. Нативная модель сохраняет failed registration до запрета повторного вызова; noop daemon отвергает обычный non-root запуск.

**Automated:** `scripts/registration-probe-native-check.py`, `scripts/registration-probe-dry-run.py`

### Scenario: Изолированный owner workflow завершает только свой тест

**Дано:** frozen owner/machine/script/plan/protected-file bindings и отдельные app/service IDs.
**Когда:** выполняется sign → positive qualification → absent-job exclusive install → GUI register → status/root read → cleanup.
**Тогда:** qualification/job/sudo/format/отмена/partial install отказывают без зависимых действий; success означает только isolated bootstrap, не production peer. Unregister выполняется один раз, архивирование запрещено при active GUI; changed files/alias и replay не вызывают операций. Аппаратных записей нет.

**Automated:** `scripts/registration-probe-dry-run.py`

### Scenario: Архивирование после завершённого unregister не повторяет lifecycle

**Дано:** сохранённые cleanup=notRegistered, absent root job, exact signed installed probe и неизменный stopped session.
**Когда:** владелец завершает GUI и запускает archive-only continuation.
**Тогда:** новый status/absent-job read предшествуют одному mv; старый сеанс и protected файлы сохраняются. Живой GUI, неизвестный status/job, changed binding или существующий archive запрещают перенос; после marker повтор закрыт.

**Automated:** `scripts/registration-probe-archive-dry-run.py`

### Scenario: GUI не перерегистрирует существующий helper

**Дано:** прочитанный статус helper и динамически проверенная установленная app.
**Когда:** пользователь нажимает подключение, а actual state уже enabled или requiresApproval.
**Тогда:** claim/register не выполняются; enabled без root peer остаётся «Зарегистрирован», pending требует системного разрешения. Изменённый fingerprint, неканонический/не root-owned bundle или process отказ останавливают действие до ServiceManagement.

**Automated:** `Tests/VentilatorInstallationTests/HelperSetupTests.swift::testGUILeavesEnabledAndPendingRegistrationAloneWithoutClaimOrPeer`, `Tests/VentilatorInstallationTests/HelperSetupTests.swift::testGUIGatesRejectChangedOrUninstalledBundleBeforeFrameworkAndClaim`

### Scenario: GUI сохраняет sole registration attempt перед framework call

**Дано:** trusted installed helper с actual notRegistered/notFound.
**Когда:** выполняется первое явное подключение.
**Тогда:** exclusive marker с signed fingerprint сохранён и fsynced до register. Повтор не перезаписывает его; alias/public directory/invalid hashes отказывают, failure сохраняется. UI register выполняется на main thread, refresh — вне него; прочитанный enabled не заменяет root proof.

**Automated:** `Tests/VentilatorInstallationTests/HelperSetupTests.swift::testDurableMarkerSurvivesFailureAndRejectsReplayWithoutOverwriting`, `Tests/VentilatorInstallationTests/HelperSetupTests.swift::testMarkerRefusesAliasesPublicDirectoryAndMalformedHashes`, `Tests/VentilatorInstallationTests/HelperSetupTests.swift::testModelWaitsForExplicitRefreshAndCallsRegisterOnceOnMainThread`, `Tests/VentilatorInstallationTests/HelperSetupTests.swift::testDisplayedReadinessRequiresInstalledTrustEnabledAndBoundPeer`

### Scenario: GUI owner update квалифицирует новую копию до lifecycle действий

**Дано:** private frozen owner/machine/hash bindings, exact прежняя установка, отсутствующие runtime/stage/GUI attempt этой новой подписи.
**Когда:** владелец закрывает app и запускает один update.
**Тогда:** подпись/positive revocation и статическая проверка staging предшествуют conditional unregister и exact mv с backup. Runtime appearance, live GUI, unknown job/sudo/alarm/partial copy отказывают до replacement; frozen replay не вызывает новых команд. CLI register и hardware commands отсутствуют.

**Automated:** `scripts/gui-helper-update-dry-run.py`

### Scenario: Новый GUI marker и enabled не заменяют verified root peer

**Дано:** canonical новая signed/root-owned app после GUI Allow либо отсутствия запроса.
**Когда:** update читает native marker, framework report и system job.
**Тогда:** pending/failed peer сохраняются с readOnlyHelperVerified=false; отсутствии marker не подставляется факт GUI register. Только enabled, exact bound peer без error и loaded job допускают diagnostic unsupportedMachine status; неожиданное hardware claim отказывает. Физическое Auto и аппаратная запись не заявляются.

**Automated:** `scripts/gui-helper-update-dry-run.py`

### Scenario: Retired identity или лишний plist не допускают ServiceManagement

**Дано:** новая compiled app/helper identity и bundle со старым app id, helper Label/MachServices либо дополнительным legacy plist.
**Когда:** inspector проверяет layout или создаёт runtime signing requirement.
**Тогда:** старые layouts отвергаются; requirements связывают только новые identifiers, прежние Apple anchor/Team/CDHash сохраняются. Ad hoc статус остаётся notQueried, actual старый installed bundle отвергается до framework.

**Automated:** `Tests/VentilatorInstallationTests/InstallationTests.swift::testRetiredApplicationOrHelperIdentityIsRejected`, `Tests/VentilatorInstallationTests/InstallationTests.swift::testUnsignedBundleAndSymlinkAreRejectedBeforeServiceAccess`

### Scenario: Fresh identity требует отсутствующих jobs и явного ON

**Дано:** sealed новая payload, exact pending/unregistered old installation и private frozen owner/machine/boot bindings.
**Когда:** владелец выполняет один frozen identity run.
**Тогда:** квалификация предшествует new/old absent-job reads; enabled/unknown old state и loaded/unknown job запрещают unregister/replacement. Exact old backup сохраняется, новая служба подключается только из GUI. Без CONNECTED, ON и actual private new marker финальная проверка не выполняется. Pending/peer failure не означают готовность; hardware admission закрыт, replay не вызывает новых действий.

**Automated:** `scripts/gui-helper-identity-dry-run.py`
