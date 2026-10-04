# Один сеанс отдельной проверки регистрации macOS

## Цель и границы

Ventilator после перезапуска сообщает requiresApproval, хотя переключатель фоновой активности включён. Причина не установлена. Проверяем независимо базовый GUI → SMAppService → административное разрешение → system job на той же машине. Новое приложение называется **Ventilator Registration Probe**, его служба — **dev.ventilator.registration-probe.daemon**. Это отдельная identity и новая регистрационная история; результат не доказывает причину прежнего отказа.

Probe не содержит модулей VentilatorCore/Control/Experiment, SMC, IOKit транспорта, аппаратного writer или XPC-команд. Его root daemon только пишет сообщение в системный журнал и ждёт завершения. Он не создаёт аппаратный или simulation runtime Ventilator. Положительный результат означает только enabled и loaded system job этого probe; root XPC и управление вентиляторами Ventilator этим не подтверждаются.

Список аппаратных записей: **пустой**. Аппаратное одобрение не запрашивается. Основное приложение, его службы, фоновая активность, backup и прежние сеансы сохраняются. Глобальный resetbtm, ручной bootstrap/kickstart/start и изменения Keychain ACL/Gatekeeper/SIP исключены.

## Полная последовательность владельца

Ожидаемая длительность — 5–10 минут плюс время на системные окна. Не перезапускайте Mac, не удаляйте приложения и не повторяйте прежние sign/setup/register/ready/collect.

1. Откройте обычный Terminal в своей учётной записи. Не добавляйте внешний sudo. Выполните одну команду:

   ```bash
   python3 /Users/mdub1na/IdeaProjects/ventilator2/.build/registration-probe-owner/session.py run
   ```

2. Скрипт проверит owner/machine/hash bindings, затем подпишет только два probe executable и bundle существующей identity `4895C06FF7407EAF5F350E78CF23D0B41AD466C9`, Team `4659S5GD6X`. **Keychain может попросить разрешение, пароль или Touch ID до двух раз.** Разрешайте только текущие запросы codesign на эту identity; не выбирайте изменение постоянного доступа/Always Allow. Отсутствие окна при уже разрешённом доступе само по себе не ошибка. Новой identity скрипт не создаёт.

3. После подписи один публичный qualifier проверит Apple anchor, точный certificate/Team, обе подписи и положительную revocation policy (deadline 30 с). Подписанные хеши сохранятся в sealed.json до системных изменений. Затем **sudo пароль может потребоваться в этом Terminal** для чтения только новой system-службы и установки probe в `/Applications/Ventilator Registration Probe.app`. Пароль в чат не отправляйте. Скрипт откажет при существующем target/job; замены или удаления чужой копии нет.

4. Откроется окно **«Ventilator — отдельная проверка регистрации»**. Нажмите **«Зарегистрировать один раз»** ровно один раз. Если macOS покажет уведомление для Ventilator Registration Probe, выберите Allow/«Разрешить» и завершите административное подтверждение. Это разрешение только диагностической root-службе. Кнопка «Объекты входа…» открывает системный раздел, если он нужен; переключатель обычного Ventilator не трогайте, OFF/ON цикл не выполняйте. Можно нажать «Прочитать статус» после подтверждения; enabled означает framework state, окончательный root job читает скрипт.

5. Вернитесь в Terminal. Введите **ALLOW** только после системного Allow и подтверждения администратора; **NONE**, если запроса не было. Любой другой ответ отменяет продолжение. Скрипт прочитает один native status и один administrative root job с пределом 5 с после sudo-аутентификации. Он сохранит result.json даже при requiresApproval/absent job; повторной регистрации нет.

6. Скрипт автоматически вызовет **один unregister только probe**, проверит notRegistered/notFound и отсутствие его system job. Это необходимая очистка диагностического теста. При запросе закройте только окно probe и введите **CLOSED** в Terminal. Скрипт проверит завершение GUI и перенесёт exact подписанную копию из /Applications в `.build/registration-probe-owner/retired.bundle`, не удаляя её байты. Для переноса sudo может снова потребовать пароль; кэш не предполагается. После `Saved isolated probe result` остановитесь и пришлите итоговый вывод.

## STOP и восстановление

- Любой STOP, неожиданный UI, changed owner/OS/hash/runtime, certificate/revocation отказ, timeout, неизвестный job read или незавершённая очистка останавливает зависимые действия. Нет автоматического retry. Сохраните весь пакет и сообщите полный вывод. Повтор run не разрешён: marker записывается до подписи.
- Если STOP произошёл **до установки**, службы probe ещё нет; аппаратного восстановления не требуется. Не переподписывайте пакет. Если остался частично установленный directory без installation.json, сохраните его для отдельной проверки; не удаляйте самостоятельно.
- Если installation.json появился, но cleanup-started.json ещё отсутствует, один отдельный cleanup в том же owner Terminal предусмотрен этим планом:

  ```bash
  python3 /Users/mdub1na/IdeaProjects/ventilator2/.build/registration-probe-owner/session.py cleanup
  ```

  Он выполняет только шаг 6; регистрации/подписи/установки нет. При cleanup-started.json или любом STOP очистки не повторяйте команду, сохраните noop probe и сообщите результат. Это не аппаратный режим Fixed: daemon не умеет обращаться к устройствам.

## Точные привязки и исполняемые действия

Только owner UID manifest, **Mac15,7 / macOS 27.0.1 / 26A434**, frozen script/PLAN и prepared payload допускаются. Подготовленные ad hoc fingerprints указаны в manifest; после owner подписи оба статических inspector и online qualifier должны вернуть exact пять файлов signed bundle. Signed seal обязателен до mkdir/ditto/open. Installed файл должен быть root-owned и без group/other write; canonical current process и dynamic CDHash обязательны до создания SMAppService. Частные ключи используются только owner run в настоящем Terminal.

Системные команды с sudo выполняются через perl exec с alarm после аутентификации:

| Действие | Точный scope | Alarm |
|---|---|---|
| launchctl print | `system/dev.ventilator.registration-probe.daemon` до установки, после регистрации, после unregister | 5 с |
| mkdir -m 755 | `/Applications/Ventilator Registration Probe.app`, только absent target | 20 с |
| ditto | frozen `payload.app` → этот target | 20 с |
| chown -R root:wheel / chmod -R go-w | только этот target | 20 с |
| mv | этот target → frozen session `retired.bundle`, только после unregister/absent job/GUI exit | 20 с |

Sudo/подпись имеют внешний предел 180 с с учётом ручной аутентификации; alarm ограничивает utility уже после неё. Native static qualification — 30 с, status/cleanup CLI — 10 с, open — 10 с. UI действия и ввод ответа ожиданием не ограничены. Пароли читаются системными окнами/Terminal, не скриптом и не чатом.

Файлы marker/results, source payload и retired.bundle сохраняются только в новом diagnostic пакете. Protected hashes связывают installed Ventilator/backup, owner-session/update/resume и все завершённые diagnostic snapshots, включая post-restart. Пакет одноразовый; probe не оставляется в /Applications после успешной очистки. BTM может сохранить запись об уже unregister probe — глобальная история не сбрасывается.

## Code anchors

| Компонент | Code |
|---|---|
| Отдельный GUI, одна попытка и CLI cleanup | `Diagnostics/RegistrationProbe/ProbeApp.swift` |
| Noop daemon | `Diagnostics/RegistrationProbe/ProbeDaemon.swift` |
| Статическая подпись, owner seal и process admission | `Diagnostics/RegistrationProbe/ProbeBundle.swift` |
| Ad hoc сборка без owner key | `scripts/build-registration-probe.py` |
| Подготовка и полный owner run | `scripts/registration-probe-session.py` |

## Проверенные исходные бинарники

Это ad hoc сборка до owner подписи. Полный список из пяти файлов связан manifest; новая Apple подпись изменит executable/CodeResources и будет отдельно квалифицирована в sealed.json до установки.

| Файл prepared payload | SHA-256 |
|---|---|
| Contents/MacOS/RegistrationProbe | e7b8fbc0b2be5b1ec9695c0a38db022e1bb507ebdf7b37d49ada750b770702d0 |
| Contents/MacOS/RegistrationProbeDaemon | 35ff3056d468d54ddcd6372b352ba668dc01542bad500ce94b06d2194aabdc1b |
| Contents/Library/LaunchDaemons/dev.ventilator.registration-probe.daemon.plist | f7b186e4c952d8f8bc768a23af5a59bbf5456ebd83c2bb4394c07c9b72960a8a |
