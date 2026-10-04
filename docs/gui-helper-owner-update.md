# Один сеанс обновления Ventilator с настройкой помощника через окно

## Статус этого сеанса

Этот update выполнен владельцем 2026-10-04. Подпись и замена завершились, но helper не подтверждён: bootstrap запрещён macOS, поздний CLI enabled/remoteFailure, system job отсутствует. **Не повторяйте run этого пакета.** Следующий шаг — [один снимок административных записей](gui-helper-state-owner.md). [Результат и сохранённые хеши](research/evidence/gui-helper-update-result.json). Ниже сохранён исходный порядок уже завершённого update; frozen PLAN прежнего пакета не изменён.

## Цель и состояние

Отдельный GUI probe получил разрешение и запустился, затем снят с регистрации и архивирован. Основной Ventilator пока сообщает requiresApproval. Новый экран умеет читать действительное состояние, явно подключать helper из GUI и сохранять единственную попытку перед register. Успех нового probe не установил причину прежней BTM history; этот сеанс проверяет новый production GUI путь.

**Mac15,7 / macOS 27.0.1 / 26A434 остаётся read-only профилем. Аппаратные записи: `[]`.** Hardware candidate остаётся на 27.0.0/26A428. Hardware review, локальное одобрение опыта, ready/start, worker/device команды в этом пакете отсутствуют. Диагностический helper на неподтверждённом профиле не создаёт аппаратный runtime; холодный listener теперь не создаёт и папку симуляции только ради чтения статуса.

## Полная последовательность владельца

Ожидаемая длительность 5–10 минут плюс системные окна. Все действия — в вашей учётной записи. Не открывайте staging, backup или старые пакеты.

1. В обычном Terminal, **без внешнего sudo**, выполните:

   ```bash
   python3 /Users/mdub1na/IdeaProjects/ventilator2/.build/gui-helper-update-owner/session.py run
   ```

2. Скрипт напечатает этот план и попросит **CLOSED**. Завершите обычный **Ventilator через Command-Q**; закрытия окна недостаточно, приложение остаётся в строке меню. Если оно уже завершено, вводите CLOSED. Скрипт проверит отсутствие его процесса, owner/machine/всех файлов и отсутствие runtime до подписи.

3. Подписываются только app/helper новой копии существующей identity **4895C06FF7407EAF5F350E78CF23D0B41AD466C9**, Team **4659S5GD6X**, с Hardened Runtime. **Keychain может запросить разрешение, пароль или Touch ID до двух раз.** Подтвердите текущий codesign для этой identity; постоянный доступ/Always Allow не выбирайте. Отсутствие окна при разрешённом доступе не является ошибкой. Затем mandatory positive revocation проверяется отдельным процессом до любых системных изменений. Подписанные hashes и seal сохраняются и печатаются.

4. Для staging, bounded чтения system-службы, backup и переноса **sudo может попросить пароль в этом Terminal**. Новая копия полностью проверяется до unregister прежней. Если прежняя регистрация pending/enabled, выполняется один guarded unregister; notRegistered/notFound пропускают его. Требуются отсутствие runtime, exact signed/root-owned старые файлы и absent system job после удаления. Старая копия сохраняется в `.build/gui-helper-update-owner/previous-installed.bundle`; новый canonical bundle устанавливается в `/Applications/Ventilator.app`. Staging не исполняется и не обращается к ServiceManagement.

5. Откроется обычный Ventilator, раздел **«Приложение» → «Помощник»**. Если **«Подключить помощник»** включено, нажмите **один раз**. Если кнопка отключена и уже написано «Ожидает разрешения macOS», новой попытки не делайте. Если появится системное уведомление Ventilator, выберите Allow/«Разрешить» и завершите административное подтверждение. После него можно нажать **«Проверить состояние»**. «Открыть настройки macOS» только открывает системный раздел; OFF/ON цикл не выполняйте, другие приложения не меняйте.

6. Вернитесь в Terminal. Введите **ALLOW** только после системного Allow и административного подтверждения; **NONE**, если запроса не было. Другой ответ отменяет продолжение с сохранением уже установленной копии. Скрипт сверит native GUI marker, если он появился, прочитает один canonical helper status и bounded system job. Enabled без проверенного root XPC успехом не является. Только при подтверждённом peer прочитается аппаратный status — ожидается отказ unsupportedMachine и отсутствие hardware experiment.

7. После **`Saved GUI helper update: … Stop and report`** пришлите последние строки. Pending/непроверенный peer тоже сохраняются как результат; повторной регистрации нет. На этом сеанс закончен. Новое аппаратное одобрение не запрашивается.

## Файлы и действия

Owner UID, точные machine/build, frozen script/PLAN, новая payload и прежняя установленная копия связаны manifest. После подписи signature-ready.json фиксирует пять файлов, sealed.json — positive qualification и их неизменность. Сохраняются десять прежних директорий: старые owner/diagnostic пакеты, прежний backup, completed probe и его архив. Текущий installed bundle сохраняется отдельно при замене.

| Действие | Точный scope | Предел |
|---|---|---|
| codesign helper/app | Только frozen payload, закреплённая identity; runtime/timestamp=none | По 180 с на owner Keychain |
| Native static inspect / public qualifier | Payload либо указанные файлы stage/installed; ServiceManagement не вызывается | 10 с / 30 с |
| Process list | Проверка отсутствия exact canonical app перед подписью/удалением/заменой; без сигналов | Один ps 5 с, выход GUI до 10 с |
| sudo mkdir/ditto/chown/chmod | Только `/Applications/Ventilator-gui-staging.app`, exclusive absent target | Alarm 20 с после аутентификации |
| Старый canonical status / conditional unregister | Только `/Applications/Ventilator.app`; при enabled требуется проверенный peer, runtime отсутствует | По 10 с |
| sudo launchctl print | `system/dev.ventilator.helper` до/после удаления и после GUI; 0/113 различаются | Alarm 5 с после аутентификации |
| sudo mv -n | Старый installed → новый previous-installed.bundle; stage → vacant canonical installed | Alarm 20 с после аутентификации |
| open -n -a | Только новый canonical app с `--show-helper-setup`; открытие само не регистрирует службу | 10 с |
| GUI marker | Приватный owner `~/Library/Application Support/Ventilator/Helper Setup/<appSHA>-<helperSHA>-<plistSHA>.json`, 0600, uid/pid/fingerprint/date; fsync до register | Только explicit GUI action |
| Новый canonical helper status / conditional owner-experiment-status | Только diagnostic status, без prepare/approval/start | По 10 с |

Sudo имеет внешний предел 180 с на ручную аутентификацию; alarm начинается после неё. UI/ввод ответа не ограничены таймером. Подпись, старые пакеты, journals и настройки безопасности не сбрасываются. Новых сертификатов/изменений Keychain ACL, SIP, Gatekeeper или global BTM reset нет. Bootstrap/kickstart/root daemon start вручную отсутствуют.

## STOP и сохранение

- При ошибке подписи/отзыва, изменённом hash/машине, живой старой app, существующем/появившемся runtime, неизвестном framework/job/native reply, отказе sudo или changed GUI marker зависимые действия прекращаются. Не повторяйте run/sign/register/ready/OFF/ON и не удаляйте папки.
- Если STOP до qualification, installed app/service не менялись. Signature-ready.json, если создан, сохраняет уже подписанные файлы; повторный codesign не нужен. Отдельное продолжение после анализа должен подготовить разработчик.
- Если staging или removal/replacement начали выполняться, сохраняйте все пути. До первого mv прежняя копия остаётся installed; после него backup содержит её exact bytes. При partial copy/mv completion отсутствует — не запускайте staging/backup и не возвращайте файлы вручную.
- После GUI открытия pending/peer failure сохраняются в result.json. Уже выполненный register не повторяется; marker привязан к подписанным бинарникам и остаётся после перезапуска GUI. Повтор run после run-started.json закрыт.
- Если Mac уснул/обновился, возник новый запрос не из этой последовательности или результат непонятен, остановитесь и пришлите полный вывод. Аппаратного восстановления в этом сеансе нет: ни Fixed, ни Auto записи не запрашиваются.

## Code anchors

| Компонент | Code |
|---|---|
| Полная подготовка/update | `scripts/gui-helper-update.py` |
| Файловые/Terminal/bounded sudo utilities из сохранённого сеанса | `scripts/registration-probe-session.py` |
| One-shot GUI/native marker | `Sources/VentilatorInstallation/HelperServiceController.swift`, `Sources/VentilatorInstallation/GUIRegistrationAttempt.swift` |
| Экран/state и shortcut | `Sources/Ventilator/HelperSetupView.swift`, `Sources/VentilatorInstallation/HelperSetupModel.swift`, `Sources/Ventilator/VentilatorMain.swift` |
| Диагностический startup без создания отсутствующего journal | `Sources/VentilatorHelper/HelperServer.swift`, `Sources/VentilatorHelper/SessionRuntimeCheck.swift` |
| Модели полной последовательности | `scripts/gui-helper-update-dry-run.py` |
