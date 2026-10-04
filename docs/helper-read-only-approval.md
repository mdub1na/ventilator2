# Сеанс владельца: проверить системное разрешение новой копии

Новая signed/root-owned копия установлена, старая сохранена в backup. Один register выполнен; после ON framework всё ещё сообщает requiresApproval. Переключатель фоновой активности включён, но global parent record содержит disallowed/pending authorization. Причина отсутствия административного запроса пока не доказана.

Этот сеанс проверяет **существующее** системное уведомление и собирает административный снимок. Подпись, установка и register уже завершены. Аппаратные записи: **пустой список, 0 SMC write**. Mac15,7 + 27.0.1/26A434 остаётся неподтверждённым аппаратным профилем, candidate 26A428 не расширен. Hardware review/receipt/START не создаются.

## Одна последовательность

1. В обычном Terminal, **без sudo перед python3**, запустите один раз:

```sh
python3 /Users/mdub1na/IdeaProjects/ventilator2/.build/helper-read-only-approval/snapshot.py collect
```

Скрипт сверит frozen PLAN/script, 17 файлов stopped update, текущую машину, installed hashes и все файлы backup. При existing/unreadable runtime, чужом owner/machine/hash → STOP до marker/системных действий. Затем покажет этот план и сохранит one-shot marker.

2. Когда Terminal попросит **ALLOW или NONE**, откройте Центр уведомлений нажатием даты/времени справа в строке меню. Найдите только уведомление о том, что **Ventilator добавил фоновые объекты**. Название и смысл должны однозначно относиться к Ventilator и запуску для всех пользователей.

Если такое уведомление существует, выберите его **Параметры → Разрешить** и подтвердите системную аутентификацию, если macOS её запросит. Это разрешает запуск уже установленного privileged helper; аппаратного одобрения не выдаёт. После успешного системного действия введите **ALLOW** с Enter. Неожиданный/неоднозначный запрос — Ctrl+C и сообщить результат.

Если подходящего уведомления нет или «Разрешить» недоступно, введите **NONE** с Enter. Это обычный диагностический исход, не ошибка. Повтор OFF/ON, переключение других приложений или повтор register не предусмотрены. Любой другой ответ отменяет сеанс до sudo.

3. Скрипт попросит **sudo пароль в Terminal**, если системе он нужен, и прочитает global `launchd` job и BTM. Это требуется для достоверного состояния root-службы: обычный non-root lookup не заменяет global контекст. Пароль не передавать в чат. Кэш пароля не предполагается. После аутентификации utilities ограничены 5 и 20 с; обычно весь снимок занимает менее минуты, время на просмотр уведомлений/ввод пароля не ограничено.

4. Если administrative job отсутствует, новый скрипт сохранит `rootJobAbsent` без запуска app/helper и с registrationStatus=null. В сохранённом завершённом пакете PR #26 использовалась общая метка `systemApprovalPending`; она не является фактическим framework state. Если job загружен, при прежней exact машине и отсутствии runtime выполнит **одну** read-only проверку signed root XPC, с пределом 10 с и внутренним nonce/deadline 2 с. Успех требует enabled/helperVerified=true, trusted/root-owned canonical bundle, exact hashes и hardwareControlAvailable=false. Ответ/timeout также сохраняются; повторов нет. Frozen PLAN/result прежнего пакета не изменяются.

5. Финальный вывод:

```text
Saved read-only snapshot: .../result.json
Outcome: ...; helperVerified=... . No hardware experiment.
```

Сообщите **«снимок системного разрешения новой копии собран»**. Pending/rootPeerUnverified/diagnosticIncomplete/runtimeStatePresent не означают успешный запуск. Появившийся runtime сохраняется в снимке и исключает helper request. При STOP пришлите полный вывод, команду не повторять. Файлы/состояние сохраняются для разработки.

## Файлы, хеши и полный список команд

Stopped source `.build/owner-profile-update-resume` остаётся целиком (17 файлов). Новый `.build/helper-read-only-approval/manifest.json` связывает его файлы, frozen script/PLAN, owner UID, текущую машину, installed fingerprint и всю прежнюю backup. Исходная подпись и positive public qualification сохраняются; Keychain/codesign в этом сеансе не используются.

| Файл | Installed SHA-256 | Backup SHA-256 |
|---|---|---|
| Ventilator | c29cf7caa4f28908b50eebd99e600ccffe58c2de45506983d307aac324330bfc | 342343978d1f133bde0affea14d664eab9431e9ec3a5edb57d49894793a27caa |
| VentilatorHelper | 49805829c7c8118bbbfa0177d1960547be9259f036da89c19bfe27cc08887c27 | 24017940cc5a6447c95002083e026e2ad1f22cc9dab1e3e18a4177ae5e361430 |
| LaunchDaemon | f4a3431e86d4a355664dc447d71e5283be7900ae2a7990d386a608330046cd2f | f4a3431e86d4a355664dc447d71e5283be7900ae2a7990d386a608330046cd2f |

Backup `/Applications/Ventilator-before-profile-fix.bundle-backup` не открывать и не удалять. Запускаемая копия только `/Applications/Ventilator.app`.

Полный список автоматических действий: файловые/hash/lstat проверки; `/usr/sbin/sysctl -n hw.model`, `/usr/bin/sw_vers -productVersion/-buildVersion` (по 5 с); `sudo -- /usr/bin/perl -e 'alarm 5; exec "/bin/launchctl", "print", "system/dev.ventilator.helper"; ...'`; `sudo -- /usr/bin/perl -e 'alarm 20; exec "/usr/bin/sfltool", "dumpbtm"; ...'`. В snapshot сохраняются только records с exact identifier Ventilator, данные остальных приложений отбрасываются. При загруженном job — `/Applications/Ventilator.app/Contents/MacOS/Ventilator --verify-installed-helper` один раз. UI действие только owner inspection и условное Allow указанного уведомления. Bootstrap/kickstart/resetbtm, lifecycle, копирование, ключи, SMC start/preflight/write не вызываются.

## Остановка

Изменённые source/installed/backup/OS/owner, runtime, чужое уведомление, отказ пароля, partial read/timeout или root peer refusal → сохранить полученное состояние. При Ctrl+C также сохраняются marker/частичный снимок. Ничего не удалять, не откатывать и не переустанавливать самостоятельно. Системные защита и trust policy не меняются. Одобрение UI, если произошло, записывается как сообщение владельца; фактический успех доказывает только проверенный root peer.
