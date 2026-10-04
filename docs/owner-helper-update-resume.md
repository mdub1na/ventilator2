# Сеанс владельца: продолжение обновления helper

Предыдущий пакет остановился до OFF: подпись завершилась, но macOS не смогла проверить отзыв сертификата. Все его файлы сохранены. Это продолжение использует **те же подписанные app/helper**, без пересборки, codesign, доступа к закрытому ключу или изменения Keychain. Разработчик должен завершить одну public qualification и сохранить seal в новом пакете **до** этой owner-команды; без seal она откажет до системных действий.

Mac15,7 + **macOS 27.0.1 (26A434)** остаётся read-only профилем. Новый helper предоставляет диагностический XPC, аппаратный runtime закрыт с unsupportedMachine. **Полный список аппаратных записей: пустой, 0 SMC write.** Hardware candidate/review/receipt не создаются; ready/run/APPROVE/START запрещены. Старый аппаратный план 27.0.0/26A428 не выполнять.

## Все действия по порядку

Сохраните работу. Во время замены не усыпляйте и не перезагружайте Mac. Сеанс обычно занимает 5–10 минут с системными запросами. Пароли вводятся только в системное окно/Terminal. Не открывайте staging или backup; пользовательская копия — `/Applications/Ventilator.app`.

1. В обычном Terminal, **без sudo перед python3**, запустите один раз:

```sh
python3 /Users/mdub1na/IdeaProjects/ventilator2/.build/owner-profile-update-resume/session.py update-read-only
```

Wrapper проверит frozen PLAN/script, seal, exact новые и прежние hashes, модель/ОС и отсутствие runtime/staging/backup. Затем сохранит one-shot marker и покажет этот план и signed fingerprint. **Запрос Keychain не ожидается.** Уже выполненная public qualification не повторяется.

2. Когда Terminal попросит **OFF**, закройте Ventilator. В **Системные настройки → Основные → Объекты входа → Активность фоновых приложений** выключите только **Ventilator**. Если система попросит пароль/Touch ID — подтвердите. Вернитесь в Terminal, введите **OFF** и Enter. Если запись отсутствует/неоднозначна или выключение отказало — Ctrl+C, STOP и сообщить результат. Не выключайте заранее: wrapper сначала проверяет файлы.

3. Wrapper проверит фактический disabled статус, root ownership/подписи/старые hashes и отсутствие всего runtime. Один unregister должен подтвердить notRegistered. Только exact inactive job без PID может получить один scoped bootout; active/unknown job → STOP. Новая копия переносится через проверенный staging, старая сохраняется в backup. Terminal может попросить **sudo пароль** для bootout/ditto/chown/chmod/mv; если он закэширован системой, нового запроса может не быть. Ни пакеты, ни журналы не удаляются.

4. Wrapper выполнит один register новой копии. Если попросит **ON**, включите **только Ventilator один раз**, подтвердите системное разрешение, если оно появится, и вернитесь в Terminal: **ON** и Enter. Если регистрация уже enabled и root peer проверен, ON пропускается автоматически. Отсутствие системного диалога само по себе не доказывает успех: результат определит root XPC проверка.

5. Wrapper проверит signed root peer и прочитает аппаратный status. Ожидаются helperVerified=true, hardwareControlAvailable=false и отказ unsupportedMachine. Успех:

```text
Read-only helper verified; snapshot saved at .../result.json
```

Сообщите **«обновление helper завершено»**. При STOP пришлите полный вывод и остановитесь: команду и переключение не повторять. Аппаратный опыт и атрибуции температур на 26A434 требуют отдельного исследования.

## Точные файлы и команды

Новый пакет `.build/owner-profile-update-resume` импортирует `.build/owner-profile-update/Ventilator.app`. Manifest связывает каждый сохранённый source файл, новые PLAN/script и fingerprint. Sealed.json подтверждает CodeSigning + positive revocation до owner-команды. Identity `4895C06FF7407EAF5F350E78CF23D0B41AD466C9`, Team `4659S5GD6X`; local Development без заявления notarization. Gatekeeper не обходить.

| Файл | Новая подписанная копия SHA-256 | Прежняя установленная SHA-256 |
|---|---|---|
| Ventilator | c29cf7caa4f28908b50eebd99e600ccffe58c2de45506983d307aac324330bfc | 342343978d1f133bde0affea14d664eab9431e9ec3a5edb57d49894793a27caa |
| VentilatorHelper | 49805829c7c8118bbbfa0177d1960547be9259f036da89c19bfe27cc08887c27 | 24017940cc5a6447c95002083e026e2ad1f22cc9dab1e3e18a4177ae5e361430 |
| LaunchDaemon | f4a3431e86d4a355664dc447d71e5283be7900ae2a7990d386a608330046cd2f | f4a3431e86d4a355664dc447d71e5283be7900ae2a7990d386a608330046cd2f |

Staging `/Applications/Ventilator-profile-staging.app`; backup `/Applications/Ventilator-before-profile-fix.bundle-backup`. Backup сохраняется целиком; расширение не `.app`, чтобы не создавать ещё одну запускаемую копию.

Полный список действий owner wrapper: обычные файловые/hash проверки; `/usr/sbin/sysctl -n hw.model`, `/usr/bin/sw_vers -productVersion/-buildVersion` (каждая до 5 с); прежняя installed app `--helper-status`, `--unregister-helper` (до 10 с); `/bin/launchctl print system/dev.ventilator.helper` (5 с); при необходимости один `sudo /bin/launchctl bootout system/dev.ventilator.helper`; `sudo /usr/bin/ditto`, `sudo /usr/sbin/chown -R root:wheel`, `sudo /bin/chmod -R go-w` только staging; два `sudo /bin/mv` только указанных installed/staging/backup. Staging app `--helper-status` проверяет identity/hashes без installed XPC. Новая installed app `--register-helper`, при необходимости один `--verify-installed-helper`, затем `--owner-experiment-status` (каждая до 10 с). XPC nonce/CDHash/audit UID/PID bound deadline — 2 с. Последняя команда только читает status; hardware start/preflight/writer не вызываются.

## Остановка и сохранение

Неожиданный запрос, changed hash/OS, existing/unreadable runtime, active/unknown job, alias, registration/XPC отказ или другой аппаратный status → STOP до следующего действия. Marker исключает повтор. При Ctrl+C/partial copy/move сохраняются stage/backup/markers: самостоятельно не удалять и не откатывать. Если замена не закончилась, оставьте Ventilator выключенным и сообщите вывод. Если отказ произошёл после ON, сохраните состояние для диагностики. Аппаратного восстановления в этом сеансе нет. Resetbtm, ручной bootstrap/kickstart, новые sign/install/register/ready попытки не выполнять.
