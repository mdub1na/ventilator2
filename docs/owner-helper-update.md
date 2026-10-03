# Сеанс владельца: обновление диагностического helper

Системное переключение загрузило job. Теперь Mac15,7 работает на **macOS 27.0.1 (26A434)**; прежний аппаратный кандидат относится к **27.0.0 (26A428)**. Старый helper завершался на несовпадении профиля с ошибочным сообщением untrustedSignature. Новая сборка оставляет диагностический XPC доступным, а аппаратный runtime на текущей ОС закрытым.

**Этот сеанс обновляет приложение и собирает результат. Аппаратные записи: пустой список, 0 SMC write.** Hardware review/receipt не создаются, ready/run/APPROVE/START в этом пакете запрещены. Старый аппаратный пакет сохраняется; на текущей ОС его не выполнять.

## Все действия по порядку

Сохраните работу, не усыпляйте и не перезагружайте Mac во время замены. Закройте Ventilator перед выключением службы. Сеанс обычно занимает 5–10 минут с системными запросами. Пароли вводятся только в системное окно/Terminal, в чат их не передавать. Не открывайте staging или backup; единственная запускаемая пользовательская копия — `/Applications/Ventilator.app`.

1. В обычном Terminal, **без sudo перед python3**, запустите одну команду:

```sh
python3 /Users/mdub1na/IdeaProjects/ventilator2/.build/owner-profile-update/session.py update-read-only
```

Wrapper проверит план/скрипт, новую копию, exact прежнюю установку, модель/ОС Mac15,7 + 27.0.1/26A434 и отсутствие runtime/staging/backup. Затем сохранит one-shot marker и покажет этот план. Changed machine → STOP до подписи/настроек.

2. Wrapper подпишет новые app/helper. Если Keychain попросит доступ к ключу Apple Development — разрешите текущую подпись. Сертификаты/ACL создавать или менять не нужно. Два codesign и две strict verify, затем **одна** public certificate qualification с пределом 20 с, без повторного доступа к ключу. После успеха сохраняются seal и точные signed hashes, которые Terminal покажет до изменения установки. Отказ подписи/revocation → STOP; повторять команду/sign/qualify нельзя, файлы остаются для диагностики.

3. Только когда Terminal попросит **OFF**, закройте Ventilator. В **Системные настройки → Основные → Объекты входа → Активность фоновых приложений** выключите только **Ventilator**. Если система запросит пароль/Touch ID — подтвердите. Вернитесь в Terminal и введите **OFF** с Enter. Если запись отсутствует/неоднозначна или выключение отказало — Ctrl+C, STOP и сообщить результат.

4. Wrapper проверит фактический disabled статус, root ownership/подписи/старые hashes и отсутствие всего runtime. Затем выполнит один unregister старой службы. При неподтверждённом notRegistered замена запрещена. Только exact inactive job без PID может получить один scoped bootout; active/unknown job → STOP. Wrapper копирует новую подписанную сборку в staging, проверяет её, сохраняет старую установку в backup и ставит новую. Для bootout/ditto/chown/chmod/mv Terminal может попросить sudo пароль; кэш не предполагается. Ни файлы пакетов, ни журналы не удаляются.

5. Wrapper выполнит один register новой копии. Если Terminal попросит **ON**, включите **только Ventilator один раз**, подтвердите системное разрешение, если оно появится, и вернитесь в Terminal: **ON** с Enter. Если регистрация уже enabled и root peer проверен, этот шаг пропускается автоматически. Отсутствие запроса само по себе не доказывает успех; одна проверка root XPC определит результат.

6. Wrapper проверит signed root peer и диагностический аппаратный status. Ожидаются helperVerified=true, hardwareControlAvailable=false и отказ unsupportedMachine. Успех:

```text
Read-only helper verified; snapshot saved at .../result.json
```

Сообщите **«обновление helper завершено»** и остановитесь. При STOP сообщите полный вывод; команду/переключение не повторять. Аппаратный опыт и новые температурные атрибуции требуют отдельного исследования 26A434.

## Файлы и команды

Новая локальная копия: `.build/owner-profile-update/Ventilator.app`; script/PLAN и исходные ad hoc hashes связаны manifest. Финальные signed hashes — sealed.json после шага 2. Identity `4895C06FF7407EAF5F350E78CF23D0B41AD466C9`, Team `4659S5GD6X`; local Development без заявления notarization. Gatekeeper не обходить.

Прежние exact installed hashes:

```text
Ventilator:       342343978d1f133bde0affea14d664eab9431e9ec3a5edb57d49894793a27caa
VentilatorHelper: 24017940cc5a6447c95002083e026e2ad1f22cc9dab1e3e18a4177ae5e361430
LaunchDaemon:     f4a3431e86d4a355664dc447d71e5283be7900ae2a7990d386a608330046cd2f
```

Staging `/Applications/Ventilator-profile-staging.app`; backup `/Applications/Ventilator-before-profile-fix.bundle-backup`. Расширение backup не `.app`, чтобы сохранённая версия не воспринималась как ещё одна запускаемая app. Backup сохраняется целиком, автоматически не удаляется.

Полный список действий wrapper: обычные файловые/hash проверки; codesign новых helper/bundle с `--options runtime`, strict verify; новая app `--qualify-owner-signature` (20 с); прежняя installed app `--helper-status`, `--unregister-helper` (до 10 с); `launchctl print system/dev.ventilator.helper` (5 с); при необходимости `sudo /bin/launchctl bootout system/dev.ventilator.helper` один раз; `sudo /usr/bin/ditto`, `/usr/sbin/chown -R root:wheel`, `/bin/chmod -R go-w` только staging; два `sudo /bin/mv` только указанных app/staging/backup. Staging app `--helper-status` подтверждает подписи/hashes без installed XPC. Затем новая installed app `--register-helper`, при необходимости `--verify-installed-helper`, `--owner-experiment-status` (каждая до 10 с). Последняя команда только читает status; аппаратный start/preflight/writer не вызываются. XPC nonce/CDHash/audit UID/PID bound deadline — 2 с.

## Остановка и сохранение

Неожиданный запрос, changed hash, existing/unreadable runtime, active/unknown job, alias, certificate/registration/XPC отказ, другой аппаратный status → STOP до следующего действия. Повтор исключён marker. При Ctrl+C/partial copy/move сохраняются stage/backup/markers; ничего самостоятельно не удалять и не откатывать. Если установленная app ещё старая или замена не закончилась, оставьте Ventilator выключенным и сообщите вывод. Если отказ случился после включения новой службы, оставьте состояние для диагностики; аппаратного восстановления в этом сеансе нет. Resetbtm, ручной bootstrap/kickstart, новые sign/install/register/ready попытки не выполнять.
