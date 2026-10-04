# Архив прежнего сеанса для macOS 27.0.0

**Этот сеанс завершён/заменён; команды ниже не выполнять на текущей macOS 27.0.1.** Старые frozen PLAN и пакеты сохранены без изменений. Используйте только [новый полный сеанс schema4](current-hardware-owner.md).

**Шаги 1 → 6, переход после указанного успеха. При STOP сохраните вывод и сообщите разработчику; команду не повторять.**

Прежний register отказал после успешного unregister. Владелец подтвердил запрос администратора; actual status=notRegistered, runtime/job отсутствуют. Новый пакет продолжает установленную копию. Старый sealed пакет сохранён целиком.

Mac15,7, macOS 27.0.0 (26A428), два вентилятора; GUI read-only. Один Fixed и один Auto без повторов/сна/аварийных тестов. Сохраните работу, подключите питание, закройте нагрузки и Ventilator. Сеанс 15–25 минут; опыт до 25 с. Без перезагрузки.

## Одна выбранная сборка

Root XPC этой сборки ещё не подтверждён; проверка в шаге 3.

`.build/owner-session/` содержит те же signed файлы и новый полный review. Установленная `/Applications/Ventilator.app` совпадает с ними. Новый wrapper не устанавливает/не заменяет файлы, не делает unregister. Открывать только эту app. До START записей нет.

Новая **signed** сборка; **sign повторно не выполнять**:

```text
Ventilator:       342343978d1f133bde0affea14d664eab9431e9ec3a5edb57d49894793a27caa
VentilatorHelper: 24017940cc5a6447c95002083e026e2ad1f22cc9dab1e3e18a4177ae5e361430
```

Identity `4895C06FF7407EAF5F350E78CF23D0B41AD466C9`, Team `4659S5GD6X`. Local Development без notarization; Gatekeeper не обходить. ACL/ключи не менять.

## Шаг 1. Проверить подготовленный пакет

В обычном **Terminal A**, script без sudo; команды по одной:

```sh
cd /Users/mdub1na/IdeaProjects/ventilator2
python3 .build/owner-session/session.py check
```

Успех: packagePath заканчивается на `.build/owner-session`, installationMode=installed, signature=complete, certificateQualification=complete, fullReview=sealed. Иначе STOP. Новый seal подготовлен разработчиком: public qualification без private key, одна попытка до 20 с. Подпись не повторять.

## Шаг 2. Продолжить настройку одной командой

Фоновое разрешение уже включено и подтверждено владельцем. В A, без sudo:

```sh
python3 .build/owner-session/session.py setup
```

Wrapper проверяет exact signed/installed identity, runtime/job и сохраняет marker до одного register. NotFound/notRegistered → register; requiresApproval сохраняется, enabled не меняется. При enabled setup сам выполняет ready: проверка root XPC, затем sudo для импорта review. Пароль sudo только в Terminal, ввод не отображается. Import review не выдаёт approval и не пишет SMC.

Успех: **Ready for local review/approval** — переход к шагу 4. Install/replace-installed/sign/unregister не выполнять. После ошибки STOP, setup/register не повторять.

Если setup сообщает **Setup paused for system approval**, переход к шагу 3. Это ещё не успех. Любой другой отказ — STOP и сообщить полный вывод; пакет/службу сохранить.

Окно/значок остаются read-only, автозапуск приложения не включать. При блокировке Gatekeeper STOP без обхода.

## Шаг 3. Только если появилось новое системное разрешение

Если после setup macOS показала новое уведомление о фоновых объектах Ventilator: **Параметры/Options → Разрешить/Allow**, подтвердите пароль/Touch ID. Это разрешение службы, не одобрение SMC-опыта. После подтверждения в A ровно один раз:

```sh
python3 .build/owner-session/session.py ready
```

Успех: **Ready for local review/approval** — шаг 4. Если нового уведомления/auth prompt нет, либо ready опять отказал — STOP и сообщить вывод. Не переключать off/on и не повторять register/ready. Включённый переключатель уже наблюдался без effective approval. Resetbtm/manual bootstrap не выполнять.

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

Script выполняет только перечисленное, отдельно команды не вводить. Setup/register требуют non-root Terminal, native команда до 10 с; один register без unregister. Exact installed/source hashes проверены при подготовке до/после копирования локального пакета; runtime/job запрещают продолжение. Install/replacement в этом режиме запрещены.

Ready: `--verify-installed-helper` проверяет enabled/root audit UID/PID/XPC nonce/CDHash/fingerprint, затем:

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
