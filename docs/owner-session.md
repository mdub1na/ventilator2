# Единый сеанс владельца: опыт 2500 RPM

**Шаги 1 → 5, переход после указанного результата. При `STOP` сохраните вывод, сообщите разработчику; команду не повторять.**

Mac15,7, macOS 27.0.0 (26A428), два вентилятора. Запись ещё не проверена; GUI read-only. План: **один Fixed и один Auto**, без повторов, аварийных тестов и сна. Сон/авария и независимое управление этим опытом не квалифицируются.

Время: 10–20 минут с диалогами, опыт до 25 с. Подключите питание, сохраните работу, закройте тяжёлые нагрузки. Без сна/перезагрузки.

## Исправление и файлы

Первая регистрация без BTM record исправлена. Executable **уже подписаны** владельцем. Проверка отзыва остановилась, затем прошла на тех же файлах; причина временного отказа неизвестна.

Failed пакет: `.build/owner-session-2026-10-02-revocation-failed/`; прежний installed: `.build/owner-session-2026-10-02-register-failed/`. Новый `.build/owner-session/` сохраняет signed бинарники. Manifest связывает их, PLAN/script, прежнюю установку и source hashes. `qualify`: public certificate/positive revocation, срок 20 с, без ключа/sudo/SMC, одна попытка. Seal/review связывают полный план с финальными хешами.

Новая **signed** сборка:

```text
Ventilator:       610afb3f3d3f3884ec3e2bec2a5a9e1495c1db5ee9a48c8cbfa362e4698c1b6d
VentilatorHelper: 9c6d361be0296c1a5b96c5d83946e98b3c6906bc669568f235e8f1d38cc03ffe
```

Executable не пересобраны. Root TTY покажет хеши перед `APPROVE challenge planSHA reviewSHA`. До одобрения и START записей нет.

Прежняя **signed** установка:

```text
Ventilator:       0a1aac6866239bb78eda03b88107c01c17d119c9595874f4c156317fd9f96a9c
VentilatorHelper: 9c0a164d1fb6c56651402908471fac49f8704d99d5d1ab62bdefef4914fae7aa
```

Identity `4895C06FF7407EAF5F350E78CF23D0B41AD466C9`, Team `4659S5GD6X`. Подпись завершена: `sign` больше не выполнять. ACL не меняются. Локальная Development сборка без notarization; Gatekeeper не обходить.

## Шаг 1. Проверить подготовленный пакет

**Terminal A**, script без sudo:

```sh
cd /Users/mdub1na/IdeaProjects/ventilator2
python3 .build/owner-session/session.py check
```

Успех: manifest без STOP; **sealed.json и review.sha256 уже существуют** после qualification разработчиком. Иначе остановитесь и сообщите разработчику.

## Шаг 2. Замена и регистрация

В A, по одной команде:

```sh
python3 .build/owner-session/session.py replace-installed
python3 .build/owner-session/session.py register
```

Пароль sudo — в Terminal, ввод не отображается. Успех: **`Replaced exact unregistered bundle`**. Старое приложение сохранено в `/Applications/Ventilator-before-registration-fix.app`. Иные хеши, existing staging/backup, активная/одобренная служба или hardware directory запрещают замену.

Успех `register`: registration **`requiresApproval`** либо **`enabled`**. Разрешите Ventilator в «Системные настройки → Основные → Объекты входа и расширения» (название может отличаться). Затем:

```sh
python3 .build/owner-session/session.py ready
```

Успех: **`Ready for local review/approval`**. Проверены root helper и review; аппаратных записей нет. При отказе `run` не выполнять.

## Шаг 3. Одобрить точный опыт в Terminal B

В A выполните и оставьте окно открытым:

```sh
python3 .build/owner-session/session.py run
```

Скопируйте выведенную полную команду во **второй Terminal B**. UUID/хеши не менять. Формат:

```text
sudo /Applications/Ventilator.app/Contents/MacOS/VentilatorHelper --approve-local-hardware OWNER_UUID PLAN_SHA256 REVIEW_SHA256
```

В B прочитайте полный план с signed хешами и всеми десятью записями. Если согласны, введите показанную строку **`APPROVE ...`** — единственное явное аппаратное одобрение. Успех: **`Approval saved for challenge UUID`**. Срок 300 с, та же загрузка ОС, файлы и соединение A.

## Шаг 4. Запустить и дождаться Auto

В A введите **`START CHALLENGE_UUID`**: значение из `Approval saved for challenge` в B, не OWNER_UUID из sudo-команды. До START записей нет. A не закрывать, Mac не усыплять.

Ждите максимум **25 с**. Успех: **`Auto codes observed`**. Программа проверяет Fixed и сама запрашивает Auto. При ошибке следуйте остановке ниже; Fixed не повторять.

## Шаг 5. Собрать отчёт

В A после результата или аварийного включения:

```sh
python3 .build/owner-session/session.py collect
```

Успех: **`Saved .../result.json`**. Сообщите «отчёт собран» и наблюдения; файл прочитаем локально. Auto-коды не доказывают физическую квалификацию. Helper/journal не удалять, опыт не повторять.

## Действия установки и сроки

Замена требует прежних signed хешей, native identity/ownership, неактивной службы и отсутствия `/Library/Application Support/Ventilator`. Любой файл/каталог/symlink или ошибка доступа блокируют её. Одноразовый marker предшествует sudo; root-owned staging проверяется нативно, прежняя установка проверяется повторно и сохраняется как backup. Частичная ошибка — остановка без очистки/повтора.

Script **сам выполняет** следующие команды; отдельно вводить их не нужно:

```sh
sudo /usr/bin/ditto /Users/mdub1na/IdeaProjects/ventilator2/.build/owner-session/Ventilator.app /Applications/Ventilator-registration-fix-staging.app
sudo /usr/sbin/chown -R root:wheel /Applications/Ventilator-registration-fix-staging.app
sudo /bin/chmod -R go-w /Applications/Ventilator-registration-fix-staging.app
sudo /bin/mv /Applications/Ventilator.app /Applications/Ventilator-before-registration-fix.app
sudo /bin/mv /Applications/Ventilator-registration-fix-staging.app /Applications/Ventilator.app
```

`register`: app `--register-helper` после native gates, один framework register для notFound/notRegistered; enabled/requiresApproval без повторного register. `ready`: `--verify-installed-helper` проверяет enabled/root audit UID/PID/XPC nonce/CDHash/fingerprint; sudo helper `--stage-local-hardware-review` импортирует абсолютный review.json/digest без approval/SMC. `collect`: read-only snapshot/status и sudo helper `--owner-hardware-audit`, без очистки pending.

Клиент посылает heartbeat; независимый Fixed reader предшествует Auto. Закрытие A/ошибка XPC закрывает private owner pipe, broker сам инициирует Auto. Потеря heartbeat — 2 с, lease — 10 с без продления. Fixed confirmation — до 5 с от begin; ожидание после Ftst минимум 3 с; I/O 0.5 с; writer quiescence 1 с; Auto 8 с от начала восстановления. Три Auto-чтения разделены минимум 1 с. Это модельные пределы; exit процесса не доказывает отмену kernel I/O.

## Все допустимые аппаратные записи

Каждая строка — максимум одна попытка; return не доказывает эффект. Failed/ambiguous шаг не повторяется. Верхняя граница — **10 вызовов**, включая восстановление.

| № | Ключ | Тип | Bytes hex | Значение/условие |
|---|---|---|---|---|
| 1 | Ftst | ui8 | 01 | тестовый режим |
| 2 | F0Md | ui8 | 01 | manual после ожидания |
| 3 | F1Md | ui8 | 01 | manual |
| 4 | F0Tg | flt | 00401c45 | 2500 RPM |
| 5 | F1Tg | flt | 00401c45 | 2500 RPM |
| 6 | F0Md | ui8 | 00 | Auto |
| 7 | F1Md | ui8 | 00 | Auto |
| 8 | F0Tg | flt | 00000000 | сброс после non-manual F0 |
| 9 | F1Tg | flt | 00000000 | сброс после non-manual F1 |
| 10 | Ftst | ui8 | 00 | выход после non-manual обоих |

Baseline: Ftst=0, modes=3/3, диапазоны F0 1350–5349, F1 1458–5777, nominal pressure. Fixed: manual обоих, цель 2500±100, actual 2500±500, прирост actual минимум 300 RPM от baseline. Baseline/Fixed/три Auto сохраняются в outcome. Эффект/Auto на этом Mac неизвестны до опыта.

## Немедленная остановка и восстановление

Отказ подписи/сертификата/установки/root peer, смена профиля/хеша, отсутствующий датчик, elevated pressure, отказ записи, неожиданные RPM или отсутствие Auto — **не повторять опыт**. До START остановитесь: записей нет. После START при проблеме Ctrl-C в A закрывает связь: broker отзовёт Fixed, подтвердит exit своего writer и выполнит только ещё не попытанные Auto. Не используйте kill/sudo против daemon/broker и не удаляйте journal.

Если через 25 с Auto не подтверждён либо процесс завис, прекратите нагрузку и штатно выключите Mac через меню Apple. Если это невозможно, удерживайте кнопку питания до выключения. Это физический запасной способ остановки, **не доказательство Auto**. После включения — только чтение и отчёт, без новых записей. Cross-boot recovery отсутствует. Ручной SMC contingency не реализован; `maximumOwnerRecoveryRuns=1` — верхняя граница, не дополнительное разрешение/записи.

## Завершение без опыта

После опыта physicalAutoVerified=false и pending сохраняются; consumed ledger блокирует unregister. Если остановились **до START**, можно снять helper с регистрации:

```sh
python3 .build/owner-session/session.py unregister
```

Проверяются pending/active state, app/journal не удаляются; выход всех процессов не доказан. Неожиданный запрос macOS — остановка и обновление полного плана.
