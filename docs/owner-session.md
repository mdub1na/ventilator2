# Единый сеанс владельца: обновление helper и опыт 2500 RPM

**Шаги 1 → 6, переход после указанного успеха. При STOP сохраните вывод и сообщите разработчику; команду не повторять.**

Mac15,7, macOS 27.0.0 (26A428), два вентилятора; GUI read-only. Один Fixed и один Auto без повторов/сна/аварийных тестов. Сохраните работу, подключите питание, закройте нагрузки и Ventilator. Сеанс 15–25 минут; опыт до 25 с. Без перезагрузки.

## Исправление и файлы

Ошибка пути argv[0] исправлена, добавлен startup log. Причина root exit 78 не доказана; новый XPC проверяется в шаге 3.

Подпись завершена владельцем; online qualification остановился на проверке отзыва. Отдельная public проверка тех же файлов затем прошла; причина отказа неизвестна. Failed пакет сохранён в `.build/owner-session-2026-10-03-path-sign-revocation-failed/`. Новый `.build/owner-session/` использует те же signed файлы, без пересборки/ключа. Manifest связывает source hashes, PLAN/script и прежнюю установку; seal/review — весь план и signed хеши. До START записей нет.

Новая **signed** сборка; **sign повторно не выполнять**:

```text
Ventilator:       342343978d1f133bde0affea14d664eab9431e9ec3a5edb57d49894793a27caa
VentilatorHelper: 24017940cc5a6447c95002083e026e2ad1f22cc9dab1e3e18a4177ae5e361430
```

Точная прежняя **signed** установка:

```text
Ventilator:       610afb3f3d3f3884ec3e2bec2a5a9e1495c1db5ee9a48c8cbfa362e4698c1b6d
VentilatorHelper: 9c6d361be0296c1a5b96c5d83946e98b3c6906bc669568f235e8f1d38cc03ffe
```

Identity `4895C06FF7407EAF5F350E78CF23D0B41AD466C9`, Team `4659S5GD6X`. Local Development без notarization; Gatekeeper не обходить. ACL/ключи не менять. Старый backup `/Applications/Ventilator-before-registration-fix.app` сохраняется.

## Шаг 1. Проверить подготовленный пакет

В обычном **Terminal A**, script без sudo; команды по одной:

```sh
cd /Users/mdub1na/IdeaProjects/ventilator2
python3 .build/owner-session/session.py check
```

Успех: signature=complete, certificateQualification=complete, fullReview=sealed. Sealed.json и review.sha256 уже подготовлены разработчиком. Иначе STOP. Разделённые sign/qualify сохраняют отдельные результаты; public qualification не требует private key, одна попытка до 20 с. Повтор подписи не нужен.

## Шаг 2. Отключить старую службу и заменить app

В «Системные настройки → Основные → Объекты входа и расширения» **выключите** фоновую активность Ventilator. Возможен запрос администратора/Touch ID. Затем в A:

```sh
python3 .build/owner-session/session.py replace-installed
```

Успех: **Replaced exact disabled unstarted bundle**. Новая копия на `/Applications/Ventilator.app`, прежняя — `/Applications/Ventilator-before-helper-path-fix.app`. Пароль sudo только в Terminal, ввод не отображается.

Замена требует exact прежних hashes, native identity/root ownership, non-enabled регистрации, отсутствия **всего** `/Library/Application Support/Ventilator` и активного PID. Любой runtime state/ошибка доступа запрещают её. Остаточный неактивный job допускает один bootout ниже; затем job должен отсутствовать до staging и mv. Existing stage/backup/marker или частичная ошибка — STOP без очистки/повтора.

## Шаг 3. Пересоздать регистрацию и проверить root helper

В A, по одной команде:

```sh
python3 .build/owner-session/session.py unregister
python3 .build/owner-session/session.py register
```

Unregister: requiresApproval и отсутствующий runtime root; notRegistered — без изменения. Иной state запрещает repair. Успех register: **requiresApproval** либо **enabled**. Error 1 допускается лишь при actual requiresApproval, выводится registrationDiagnostic; иначе STOP, без retry.

В системных настройках **включите** Ventilator; возможен запрос администратора/Touch ID. Затем в A:

```sh
python3 .build/owner-session/session.py ready
```

Успех: **Ready for local review/approval**, проверены root peer/review; receipt/записей нет. При отказе run запрещён.

## Шаг 4. Локально одобрить точный опыт

В A выполните и оставьте окно открытым:

```sh
python3 .build/owner-session/session.py run
```

В **Terminal B**, UUID/хеши не менять:

```text
sudo /Applications/Ventilator.app/Contents/MacOS/VentilatorHelper --approve-local-hardware OWNER_UUID PLAN_SHA256 REVIEW_SHA256
```

В B прочитайте review/signed хеши/десять записей. Если согласны: **APPROVE ...**, единственное аппаратное одобрение. Успех: **Approval saved for challenge UUID**. Срок 300 с, та же загрузка/файлы/соединение A.

## Шаг 5. Выполнить один опыт и дождаться Auto

В A: **START CHALLENGE_UUID**, UUID из `Approval saved for challenge` в B, не OWNER_UUID из sudo-команды. A не закрывать, Mac не усыплять.

Ждите до **25 с**. Успех: **Auto codes observed**. Fixed проверяется, Auto запрашивается автоматически. Ошибка — остановка ниже, без повтора Fixed.

## Шаг 6. Собрать результат

В A после результата или аварийного включения:

```sh
python3 .build/owner-session/session.py collect
```

Успех: **Saved .../result.json**. Сообщите «отчёт собран» и наблюдения. Auto-коды не доказывают квалификацию; helper/journal сохраняются, опыт не повторять.

## Команды script и сроки

Script сам выполняет команды ниже; отдельно не вводить. Bootout только для disabled неактивного job. Marker предшествует sudo; staging и прежняя установка проверяются перед backup.

```sh
sudo /bin/launchctl bootout system/dev.ventilator.helper
sudo /usr/bin/ditto /Users/mdub1na/IdeaProjects/ventilator2/.build/owner-session/Ventilator.app /Applications/Ventilator-helper-path-staging.app
sudo /usr/sbin/chown -R root:wheel /Applications/Ventilator-helper-path-staging.app
sudo /bin/chmod -R go-w /Applications/Ventilator-helper-path-staging.app
sudo /bin/mv /Applications/Ventilator.app /Applications/Ventilator-before-helper-path-fix.app
sudo /bin/mv /Applications/Ventilator-helper-path-staging.app /Applications/Ventilator.app
```

Register/unregister: signed app CLI после native gates, без SMC. Ready: `--verify-installed-helper` проверяет enabled/root audit UID/PID/XPC nonce/CDHash/fingerprint, затем:

```text
sudo /Applications/Ventilator.app/Contents/MacOS/VentilatorHelper --stage-local-hardware-review /Users/mdub1na/IdeaProjects/ventilator2/.build/owner-session/review.json REVIEW_SHA256
```

Импорт review без approval/SMC. Collect: read-only snapshot/status и `sudo /Applications/Ventilator.app/Contents/MacOS/VentilatorHelper --owner-hardware-audit`, без очистки pending.

Heartbeat — 2 с; lease — 10 с без продления. Fixed confirmation до 5 с от begin; после Ftst ожидание минимум 3 с; I/O 0.5 с; writer quiescence 1 с; Auto 8 с от начала восстановления. Независимый Fixed reader предшествует Auto, три Auto-чтения разделены минимум 1 с. Закрытие A/ошибка XPC закрывает private owner pipe, broker инициирует Auto. Это модельные пределы; exit не доказывает отмену kernel I/O.

## Все допустимые аппаратные записи

Каждая строка — максимум одна попытка; return не доказывает эффект. Failed/ambiguous шаг не повторяется. Верхняя граница **10 вызовов**, включая восстановление.

| № | Ключ | Тип | Bytes hex | Значение/условие |
|---|---|---|---|---|
| 1 | Ftst | ui8 | 01 | тестовый режим |
| 2 | F0Md | ui8 | 01 | manual после ожидания |
| 3 | F1Md | ui8 | 01 | manual |
| 4 | F0Tg | flt | 00401c45 | 2500 RPM |
| 5 | F1Tg | flt | 00401c45 | 2500 RPM |
| 6 | F0Md | ui8 | 00 | Auto |
| 7 | F1Md | ui8 | 00 | Auto |
| 8 | F0Tg | flt | 00000000 | после non-manual F0 |
| 9 | F1Tg | flt | 00000000 | после non-manual F1 |
| 10 | Ftst | ui8 | 00 | после non-manual обоих |

Baseline: Ftst=0, modes=3/3, диапазоны F0 1350–5349, F1 1458–5777, nominal pressure. Fixed: manual обоих, цель 2500±100, actual 2500±500, прирост actual минимум 300 RPM от baseline. Baseline/Fixed/три Auto сохраняются в outcome. Эффект/Auto на этом Mac неизвестны до опыта.

## Остановка и восстановление

Отказ подписи/сертификата/установки/root peer, смена профиля/хеша, отсутствие датчика, elevated pressure, отказ записи, неожиданные RPM или отсутствие Auto — **не повторять опыт**. До START остановитесь: записей нет. После START Ctrl-C в A закрывает связь: broker отзовёт Fixed, подтвердит exit своего writer и выполнит только ещё не попытанные Auto. Не используйте kill/sudo против daemon/broker после START; journal не удалять.

Если через 25 с Auto не подтверждён или процесс завис, прекратите нагрузку и штатно выключите Mac через меню Apple. Если невозможно — удерживайте питание до выключения. Это физический запасной способ остановки, **не доказательство Auto**. После включения только чтение/отчёт, без новых записей. Cross-boot recovery и ручной SMC contingency не реализованы; maximumOwnerRecoveryRuns=1 — верхняя граница, не дополнительное разрешение.

После опыта physicalAutoVerified=false/pending сохраняются, consumed ledger блокирует unregister. До START: `python3 .build/owner-session/session.py unregister`; enabled требует живой XPC без pending/active simulation, disabled — отсутствующий runtime root. App/journal сохраняются; выход всех процессов не доказан. Неожиданный запрос — STOP и обновление плана.
