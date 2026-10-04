# Один перезапуск macOS и read-only проверка Ventilator

## Зачем этот сеанс

Текущая exact подписанная копия уже установлена. Последний сеанс завершился с NONE: уведомления не было; чтение с sudo подтвердило отсутствие `system/dev.ventilator.helper`. BTM сохранил незавершённое системное разрешение. Mac работает с 2 октября, после последней установки 4 октября macOS не перезапускалась.

Проверяем **гипотезу**: после обычного перезапуска состояние системных служб будет согласовано с сохранённой регистрацией. Перезапуск не заменяет административное разрешение и не гарантирует загрузку helper. Новая подпись/установка/регистрация в этом сеансе не выполняется. Исправление исходников из PR #28 не требуется устанавливать для этой проверки: текущие signed файлы остаются прежними.

## Полная последовательность владельца

1. Сохраните работу в открытых приложениях.
2. Выполните один обычный перезапуск Mac через меню Apple → «Перезагрузить». Не сбрасывайте BTM и не удаляйте приложения, службы или пакеты.
3. Войдите в ту же учётную запись владельца. Не запускайте sign/setup/register/ready, не переключайте фоновую активность Ventilator и не повторяйте прежний collect.
4. Откройте обычный Terminal и выполните **одну** команду, без внешнего sudo:

   ```bash
   python3 /Users/mdub1na/IdeaProjects/ventilator2/.build/helper-after-restart/snapshot.py collect
   ```

5. При `Password:` в этом Terminal введите пароль администратора для двух read-only системных чтений. Ввод скрыт; sudo может использовать свой действующий cache, поэтому второго запроса пароля может не быть. Keychain, Touch ID для подписи, OFF/ON/ALLOW и одобрение аппаратного опыта скрипт не запрашивает.
6. После `Saved read-only snapshot` остановитесь и сообщите результат. Если вместо него появился STOP, сообщите полный текст STOP; не запускайте команду ещё раз и ничего не очищайте.

## Привязки и границы

Пакет допускает только owner UID из manifest, `Mac15,7 / macOS 27.0.1 / 26A434` и **другой boot UUID**, чем при подготовке. Запуск до перезапуска отказывает до marker/sudo. Обновление версии ОС при перезапуске также блокирует сбор: это другой неподтверждённый профиль.

Frozen script/PLAN связаны SHA-256 в manifest. Связаны все восемь файлов завершённого `.build/helper-read-only-approval`, 17 файлов stopped `.build/owner-profile-update-resume`, пять backup файлов и exact installed fingerprint:

| Файл текущей установки | SHA-256 |
|---|---|
| `Contents/MacOS/Ventilator` | `c29cf7caa4f28908b50eebd99e600ccffe58c2de45506983d307aac324330bfc` |
| `Contents/MacOS/VentilatorHelper` | `49805829c7c8118bbbfa0177d1960547be9259f036da89c19bfe27cc08887c27` |
| `Contents/Library/LaunchDaemons/dev.ventilator.helper.plist` | `f4a3431e86d4a355664dc447d71e5283be7900ae2a7990d386a608330046cd2f` |

Другой owner, changed hash/source/backup, alias, unreadable state и существующий runtime root останавливают сеанс до marker/sudo. Ничего не удаляется. Если daemon уже создал runtime после загрузки, это сохраняемое состояние, а не повод обходить gate.

Список разрешённых аппаратных записей: **пустой**. Аппаратных approval/review/receipt/start нет. Current installed helper сохраняет диагностический listener на неподтверждённом профиле без аппаратного runtime/startup recovery. Подготовленный код аппаратного writer остаётся закрытым.

## Все исполняемые действия

До marker выполняются только проверки файлов, machine/boot и owner TTY. Затем один exclusive `started.json` запрещает повтор. Только следующие системные команды выполняются с sudo:

```text
/usr/bin/sudo -- /usr/bin/perl -e 'alarm 5; exec "/bin/launchctl", "print", "system/dev.ventilator.helper"; die "exec failed\n";'
/usr/bin/sudo -- /usr/bin/perl -e 'alarm 20; exec "/usr/bin/sfltool", "dumpbtm"; die "exec failed\n";'
```

Сроки 5 и 20 секунд начинаются **после** успешной sudo-аутентификации; alarm сохраняется при exec и завершает сам utility. Пароль в Terminal ожидается отдельно. Из BTM сохраняются только точные Ventilator identifiers, raw записи других приложений не сохраняются.

Только при loaded job (exit 0), полном распознанном BTM и отсутствующем runtime допускается один запуск:

```text
/Applications/Ventilator.app/Contents/MacOS/Ventilator --verify-installed-helper
```

Внешний deadline — 10 секунд, native XPC deadline — 2 секунды. Проверяются подпись/root ownership/location, bound audit UID/PID/CDHash, nonce, fingerprint и реальный helperVerified. Запуск не регистрирует/удаляет службу и не выдаёт аппаратное одобрение. Diagnostic reply может создать собственный simulation runtime при старте daemon; его состояние сохраняется, дальнейшего опыта нет.

## Результат и остановка

- `readOnlyHelperVerified`: живой root peer подтверждён. Это не разрешение управлять вентиляторами.
- `systemApprovalPending`: job по-прежнему отсутствует; перезапуск не завершил системное разрешение. Причина ещё требует разбора; новые install/register/OFF/ON циклы этим результатом не разрешаются.
- `runtimeStatePresent`: runtime появился при чтении; peer verification пропущен, состояние сохранено.
- `rootPeerUnverified`: job есть, но одна bound peer проверка не прошла. Timeout/error не вызывают retry.
- `diagnosticIncomplete`: sudo/read/format отказал или истёк alarm; последующие зависимые действия не вызываются. Сохранённые части пакета не очищаются.

Report находится в `.build/helper-after-restart/result.json`. После любого исхода остановитесь: этот пакет одноразовый. Old notification snapshot, stopped update, installed копия и backup не меняются скриптом.
