# Единый сеанс владельца: опыт 2500 RPM

**Выполняйте шаги 1 → 5 после указанного результата. При `STOP` сохраните вывод и сообщите разработчику; не повторяйте команду.**

Профиль: Mac15,7, macOS 27.0.0 (26A428), два вентилятора. Запись ещё не проверена; GUI read-only. План: **один Fixed и один Auto**, без повторов, аварийных тестов и сна. Сон/авария и независимое управление этим опытом не квалифицируются.

Время: 10–20 минут с диалогами, опыт до 25 с. Подключите питание, сохраните работу, закройте тяжёлые нагрузки. Без сна/перезагрузки.

## Почему подпись нужно выполнить снова

Первый `sign` подписал файлы, но наша ошибка проверки не позволила создать seal. Код и Team ID исправлены. Старый пакет сохранён в `.build/owner-session-2026-10-02-sign-failed/`, его не устанавливать. Новый `.build/owner-session/` требует подписи изменённых файлов. Опыт ещё не начинался.

## Проверенные файлы и подпись

`manifest.json` связывает проверенные ad hoc app/helper/plist/PLAN/script. Подпись меняет Mach-O: финальные SHA-256 неизвестны заранее. `sealed.json`, `candidate.json`, `review.json` и `review.sha256` свяжут **фактически подписанные** файлы с полным планом; root TTY покажет их перед `APPROVE challenge planSHA reviewSHA`. До одобрения и START записей нет.

SHA-256 проверенной **ad hoc** сборки:

```text
Ventilator:       61025c6fcd3d8a9d5c9fa4649fe0b9a4dfe5d3b6c89d2ad4851210a9062a48a9
VentilatorHelper: ab4571832312b08d9ecedc2ba634b3ca54ae49913f438e1ce76ea36d65f36097
```

Identity `4895C06FF7407EAF5F350E78CF23D0B41AD466C9`, Team `4659S5GD6X`. Сертификат проверен, новая подпись проверяется заново; revoked identity исключена. При Keychain/Touch ID выбирайте разовое разрешение; пароль только в системном окне/Terminal. ACL/keychain не меняются. Positive revocation обязателен, timeout 20 с — остановка до установки. Это локальная Apple Development сборка без notarization. Gatekeeper не обходить.

## Шаг 1. Подписать новый пакет

Откройте обычный Terminal — это **Terminal A**. Не запускайте весь script через sudo. Пакет уже подготовлен:

```sh
cd /Users/mdub1na/IdeaProjects/ventilator2
python3 .build/owner-session/session.py check
python3 .build/owner-session/session.py sign
```

Успех: строка **`Signed and public certificate qualified`** с Review SHA-256; появились `sealed.json` и `review.sha256`. До этого результата не устанавливайте приложение.

## Шаг 2. Установить и разрешить помощник

В том же A, по одной команде:

```sh
python3 .build/owner-session/session.py install
python3 .build/owner-session/session.py register
```

`install` запросит пароль sudo в Terminal; ввод не отображается. Успех: **`Copied exact signed bundle`**. Существующий `/Applications/Ventilator.app` не заменяется — остановитесь при таком отказе.

После `register` возможен запрос администратора. Разрешите Ventilator в «Системные настройки → Основные → Объекты входа и расширения» (название может отличаться). Затем в A:

```sh
python3 .build/owner-session/session.py ready
```

Успех: **`Ready for local review/approval`**. Helper проверен, review подготовлен; записей нет. При отказе `run` не выполнять.

## Шаг 3. Прочитать и локально одобрить точный опыт

В A выполните и оставьте окно открытым:

```sh
python3 .build/owner-session/session.py run
```

Скопируйте выведенную полную команду в **второй Terminal — B**. UUID/хеши не менять. Формат:

```text
sudo /Applications/Ventilator.app/Contents/MacOS/VentilatorHelper --approve-local-hardware OWNER_UUID PLAN_SHA256 REVIEW_SHA256
```

В B прочитайте полный план с **signed хешами и всеми десятью записями**. Для единственного аппаратного одобрения введите показанную строку **`APPROVE ...`**. Успех: **`Approval saved for challenge UUID`**. Срок 300 с, та же загрузка ОС, файлы и соединение A.

## Шаг 4. Запустить и дождаться Auto

В A введите **`START CHALLENGE_UUID`**, заменив CHALLENGE_UUID значением из `Approval saved for challenge` в B. Это не OWNER_UUID из sudo-команды. До START записей нет; A не закрывать, Mac не усыплять.

Ждите максимум **25 с**. Успех: **`Auto codes observed`**. Программа сама проверяет Fixed и запрашивает возврат Auto. При ошибке/зависании следуйте разделу остановки ниже; Fixed не повторять.

## Шаг 5. Собрать результат

В A после результата (или после включения при аварийном выключении):

```sh
python3 .build/owner-session/session.py collect
```

Успех: **`Saved .../result.json`**. Сообщите «отчёт собран» и наблюдения/ошибки; разработчик прочитает файл локально. Не повторяйте опыт и не удаляйте helper/journal. Auto-коды ещё не доказывают физическую квалификацию.

## Что выполняют команды и сколько ждут

`install` после seal-проверки выполняет только эти три адресные команды **самостоятельно; отдельно их вводить не нужно**:

```sh
sudo /usr/bin/ditto /Users/mdub1na/IdeaProjects/ventilator2/.build/owner-session/Ventilator.app /Applications/Ventilator.app
sudo /usr/sbin/chown -R root:wheel /Applications/Ventilator.app
sudo /bin/chmod -R go-w /Applications/Ventilator.app
```

`register`: app `--register-helper`. `ready`: `--verify-installed-helper` проверяет enabled/root peer/XPC/CDHash/fingerprint; sudo helper `--stage-local-hardware-review` импортирует review.json/digest без approval/SMC. `collect`: read-only snapshot/status и sudo helper `--owner-hardware-audit`, без очистки pending.

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

## Завершение без опыта

После опыта `physicalAutoVerified=false` и pending сохраняются; consumed ledger блокирует unregister. Если остановились **до START**, можно снять helper с регистрации:

```sh
python3 .build/owner-session/session.py unregister
```

Команда проверяет pending/active state, не удаляет app/journal; выход всех процессов не доказан. Неожиданный запрос macOS — остановка и обновление полного плана.
