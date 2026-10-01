# Единый сеанс владельца: ограниченный опыт 2500 RPM

Профиль: Mac15,7, macOS 27.0.0 (26A428), два вентилятора. До этого сеанса запись не проверена. GUI остаётся монитором. План предусматривает **один Fixed и один Auto**, без повторов, принудительных аварий и проверки сна. Результат обычного возврата не квалифицирует сон/аварию или независимое управление.

Длительность: примерно 10–20 минут с системными диалогами; аппаратная часть — до 25 с. Подключите питание, сохраните работу, закройте тяжёлые нагрузки. Не усыпляйте Mac. Сон/перезагрузка для штатного опыта не нужны.

## Проверенные файлы и подпись

Подготовленный пакет: `.build/owner-session/`. `manifest.json` содержит SHA-256 проверенных ad hoc app/helper, plist, этого плана и команды `session.py`. Подпись изменит Mach-O: финальные хеши заранее неизвестны. После подписи `sealed.json`, `candidate.json`, `review.json` и `review.sha256` связывают **фактически подписанные** бинарники с этим полным планом. Root TTY ещё раз показывает точный candidate и просит локальное `APPROVE challenge planSHA reviewSHA`. До этого и отдельного `START` запись не начинается.

SHA-256 проверенной **ad hoc** сборки:

```text
Ventilator:       1bb278033159a5cb0e14c732d167311d9886dc7693ad32eeefb2d8014ee018e8
VentilatorHelper: edbc8b0a93eee5693f66eff1903c2901a4fd27f129c70cf6f41fd4e72877f92a
```

Используется только identity `4895C06FF7407EAF5F350E78CF23D0B41AD466C9`, Team `568959LQ99`. Это непроверенный кандидат; первая найденная identity revoked и исключена. Возможен запрос Keychain/Touch ID для codesign. Выбирайте разовое разрешение; пароль вводится только в системном окне/Terminal. ACL/keychain не изменяются. Проверка публичного сертификата требует положительного revocation-ответа, максимум 20 с. Отказ/timeout останавливает сеанс до установки. Apple Development — локальная сборка; notarization и готовность распространения не заявлены. При блокировке Gatekeeper остановитесь, не обходите её.

## Команды по порядку

Terminal A, без root. Пакет уже подготовлен разработчиком:

```sh
cd /Users/mdub1na/IdeaProjects/ventilator2
python3 .build/owner-session/session.py check
python3 .build/owner-session/session.py sign
python3 .build/owner-session/session.py install
python3 .build/owner-session/session.py register
```

`install` выполняет только три адресные команды после проверки seal и отсутствия `/Applications/Ventilator.app`:

```sh
sudo /usr/bin/ditto /Users/mdub1na/IdeaProjects/ventilator2/.build/owner-session/Ventilator.app /Applications/Ventilator.app
sudo /usr/sbin/chown -R root:wheel /Applications/Ventilator.app
sudo /bin/chmod -R go-w /Applications/Ventilator.app
```

Если приложение уже существует — остановка без замены. `register` вызывает `/Applications/Ventilator.app/Contents/MacOS/Ventilator --register-helper`. macOS может запросить административное разрешение и включение фоновой активности: «Системные настройки → Основные → Объекты входа и расширения», разрешите Ventilator. Название раздела может отличаться. Затем:

```sh
python3 .build/owner-session/session.py ready
python3 .build/owner-session/session.py run
```

`ready` требует enabled service, root audit UID/PID и живой CDHash/nonce/hash-bound XPC ответ, сверяет signed candidate и выполняет через sudo `--stage-local-hardware-review` с абсолютным `review.json` и его digest. Staging не выдаёт receipt и не пишет SMC.

`run` держит одно соединение. Он выведет **готовую команду** для Terminal B вида:

```text
sudo /Applications/Ventilator.app/Contents/MacOS/VentilatorHelper --approve-local-hardware OWNER_UUID PLAN_SHA256 REVIEW_SHA256
```

Параметры берутся из живого соединения, не заменяйте их вручную. В Terminal B прочитайте полный review/candidate; единственное явное аппаратное одобрение — точная строка `APPROVE ...`, показанная там. Срок receipt — 300 с, одна загрузка ОС и те же бинарники. Вернитесь в A и введите `START CHALLENGE_UUID` из B. Receipt другого соединения не работает. Не закрывайте A до результата.

Клиент посылает heartbeat, после независимого подтверждения Fixed запрашивает Auto. Закрытие A/ошибка XPC закрывает private owner pipe; независимый broker сам инициирует Auto. При потере heartbeat — 2 с; lease жёстко 10 с и не продлевается. Подтверждение Fixed — до 5 с от begin, ожидание после Ftst — минимум 3 с, отдельный I/O — 0.5 с, quiescence writer — 1 с, Auto — 8 с от начала восстановления. Три независимых Auto-чтения разделены минимум 1 с. Это модельные пределы; завершение процесса не доказывает отмену kernel I/O.

## Все допустимые аппаратные записи

Каждая строка — максимум одна попытка; успешный return не доказывает физический эффект. Failed/ambiguous шаг не повторяется. Общее верхнее число — **10 вызовов**, включая восстановление.

| Порядок | Ключ | Тип | Bytes hex | Значение |
|---|---|---|---|---|
| 1 | Ftst | ui8 | 01 | тестовый режим |
| 2 | F0Md | ui8 | 01 | manual, после ожидания |
| 3 | F1Md | ui8 | 01 | manual |
| 4 | F0Tg | flt | 00401c45 | 2500 RPM |
| 5 | F1Tg | flt | 00401c45 | 2500 RPM |
| 6 | F0Md | ui8 | 00 | запрос Auto |
| 7 | F1Md | ui8 | 00 | запрос Auto |
| 8 | F0Tg | flt | 00000000 | сброс цели, после non-manual F0 |
| 9 | F1Tg | flt | 00000000 | сброс цели, после non-manual F1 |
| 10 | Ftst | ui8 | 00 | выход из теста, после non-manual обоих |

Baseline требует Ftst=0, modes=3/3, диапазоны F0 1350–5349 и F1 1458–5777, nominal pressure. Fixed требует manual обоих, цель 2500±100, actual 2500±500 и прирост actual минимум 300 RPM от baseline. Прочитанные baseline/Fixed/три Auto сохраняются в outcome. Эффект/Auto на этом Mac до опыта неизвестны.

## Немедленная остановка и восстановление

Любой отказ подписи/сертификата/установки/root peer, смена профиля/хеша, отсутствующий датчик, elevated pressure, отказ записи, отсутствие ожидаемых RPM или Auto — **не повторять опыт**. До START просто остановитесь: SMC-записей ещё нет. После START нажмите Ctrl-C в A при проблеме: связь закроется, broker отзовёт Fixed, подтвердит выход собственного writer и выполнит только ещё не попытанные Auto. Не используйте kill/sudo-команды против daemon/broker и не удаляйте journal.

Если через 25 с Auto не подтверждён либо процесс завис, прекратите нагрузку и штатно выключите Mac через меню Apple. При невозможности штатного выключения удерживайте кнопку питания до выключения. Это запасной физический способ остановки сеанса, **не доказательство Auto**. После включения выполняйте только чтение и сбор отчёта; новые записи запрещены. Cross-boot recovery не запускается. Отдельная ручная SMC contingency не реализована: `maximumOwnerRecoveryRuns=1` в candidate — верхняя граница, не разрешение и не дополнительный набор записей.

## Отчёт и завершение

После результата (либо после включения при аварии):

```sh
python3 .build/owner-session/session.py collect
```

Собираются sealed fingerprints, read-only snapshot, XPC status и защищённый ledger/outcome через адресный `sudo ... --owner-hardware-audit`. Отчёт `.build/owner-session/result.json`; отправьте его разработчику вместе с наблюдениями/сообщениями Terminal. `physicalAutoVerified=false` и hardware pending сохраняются до разбора. Нельзя очищать pending ради удаления/повтора. При наличии consumed ledger оставьте helper установленным для диагностики; removal guard блокирует unregister. Если остановились до START:

```sh
python3 .build/owner-session/session.py unregister
```

Команда проверяет pending/active state; не удаляет app/journal и не обещает подтверждённый выход всех процессов. Весь перечень действий согласуется одним планом; неожиданный новый запрос macOS означает остановку и обновление плана целиком.
