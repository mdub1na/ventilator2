# Единый сеанс: новый план v4 и первый опыт 2500 RPM

**Mac15,7 / macOS 27.0.1 / 26A434, два вентилятора.** Это новый unapproved candidate schema4. Root helper подтверждён; запись и физический возврат Auto **не проверены**. GUI read-only. Сеанс обновляет сборку и предлагает один опыт. Фоновое разрешение, Keychain и sudo не одобряют опыт.

## До начала — около 10–15 минут на весь сеанс

Сохраните работу, подключите питание, закройте тяжёлые задачи и дайте Mac остыть. Не начинайте при сильном нагреве, неизвестной нагрузке или если физически не можете выключить Mac. Не используйте сон/перезагрузку и не уходите от компьютера во время опыта. Никаких аварийных/kill/sleep тестов в этом сеансе нет.

В обычном **Terminal A**, без внешнего sudo, выполните один раз:

```bash
python3 /Users/mdub1na/IdeaProjects/ventilator2/.build/current-hardware-owner/session.py run
```

1. **Выход → CLOSED.** Завершите Ventilator через Command-Q или «Выйти», затем CLOSED. Закрыть только окно недостаточно. Скрипт проверит процесс без сигналов/принудительного завершения.
2. **Подпись → qualification → sudo → точная замена.** Подтвердите Keychain только если запрос появится; отсутствие запроса при сохранённом доступе нормально. Скрипт подпишет лишь новую payload сертификатом `4895C06FF7407EAF5F350E78CF23D0B41AD466C9`, Team `4659S5GD6X`, и проверит positive revocation. До lifecycle будут сохранены/напечатаны точные signed app/helper/plist SHA-256, candidate plan SHA-256 и полный review SHA-256, включающий этот PLAN и все десять writes. При sudo введите пароль администратора только в настоящем Terminal. Новая root-owned staging копия статически проверяется без ServiceManagement. Только exact old enabled/bound root peer и отсутствующий whole root runtime допускают один штатный unregister; root job после него должен отсутствовать. Old bundle сохраняется целиком в `previous-installed.bundle` этого пакета, затем новая копия устанавливается в `/Applications/Ventilator.app`. Старые подписи сохраняются.
3. **Новое окно → CONNECTED → ON → ALLOW/NONE.** Нажмите «Подключить помощник» один раз, если кнопка включена, затем CONNECTED. В «Системные настройки → Основные → Объекты входа и расширения → Фоновая активность приложений» проверьте только новую запись Ventilator: уже включённую оставьте ON, выключенную включите; введите ON. ALLOW — только после настоящего Allow/admin подтверждения, NONE — если запроса не было. При недоступном действии/неразличимых записях введите CANCEL. Сохранённое разрешение может действовать; готовность подтверждается exact root XPC/job.
4. **Проверка пустого hardware state → импорт полного review.** Новый helper создаёт защищённое root storage для нового candidate, но без receipt не запускает writer. Скрипт проверит root audit: текущий boot и отсутствие прежних challenge/approval/ledger/outcome. При любом существующем state остановится; ничего не удаляет. Затем sudo импортирует только sealed review. Импорт не одобряет и не запускает опыт. До отдельного APPROVE/START аппаратных записей нет.
5. **Terminal B: единственное явное одобрение.** Клиент в A напечатает конкретную команду `sudo … VentilatorHelper --approve-local-hardware OWNER_UUID PLAN_SHA256 REVIEW_SHA256`. Откройте обычный Terminal B и скопируйте именно эту строку. Пароль — только в B. Прочитайте полный PLAN, signed hashes и десять writes. Если согласны с точным опытом, введите напечатанную строку **APPROVE CHALLENGE_UUID PLAN_SHA256 REVIEW_SHA256**. Это единственное аппаратное одобрение. Если не согласны, отмените; автоматических подтверждений нет. Receipt действует 300 секунд для этой загрузки, signed файлов и соединения A. Успех: «Approval saved for challenge …»; эта команда сама ничего не пишет в SMC.
6. **Terminal A: START → дождаться Auto → результат.** Введите **START CHALLENGE_UUID**, используя UUID из успешного сообщения B, а не OWNER_UUID. Если решили отменить, введите CANCEL. Перед Fixed клиент/helper ещё раз проверяют exact profile/ranges, свежие independent readings, nominal pressure, Ftst0/mode3, RPM/target ≤1800 и armed recovery. Один опыт длится не более 25 секунд ожидания клиента; исходный Fixed lease 10 с не продлевается heartbeat. A не закрывайте и Mac не усыпляйте. После подтверждённого подъёма к 2500 RPM клиент автоматически запрашивает Auto; ошибка/EOF/просрочка также закрывают Fixed и оставляют независимому broker только допустимое восстановление. Скрипт собирает root audit в `result.json`; пришлите последние строки и наблюдения. «Auto codes observed» — доказательство read-back кодов, **не физическая qualification** и не разрешение включить обычные RPM controls.

## Все аппаратные записи в хронологическом порядке

Только эти десять шагов; каждый максимум один раз. Диапазоны: fan0 **1350–5349 RPM**, fan1 **1458–5777 RPM**; общий target **2500 RPM**. Прежние диапазоны подтверждены новым read-only снимком. Произвольных key/bytes нет.

| Порядок | Ключ | Тип | Байты hex | Условие |
|---|---|---|---|---|
| 1 | Ftst | ui8 | 01 | Одобренный свежий preflight и armed recovery |
| 2 | F0Md | ui8 | 01 | Через 3 с после unlock, valid lease |
| 3 | F1Md | ui8 | 01 | Предыдущий шаг успешен, valid lease |
| 4 | F0Tg | flt | 00401c45 | Оба вентилятора read-back manual, valid lease |
| 5 | F1Tg | flt | 00401c45 | Предыдущий шаг успешен, valid lease |
| 6 | F0Md | ui8 | 00 | Durable pending, Fixed закрыт, writer вышел |
| 7 | F1Md | ui8 | 00 | Writer вышел, даже если другой fan отказал |
| 8 | F0Tg | flt | 00000000 | Fan0 независимо наблюдён non-manual |
| 9 | F1Tg | flt | 00000000 | Fan1 независимо наблюдён non-manual |
| 10 | Ftst | ui8 | 00 | Оба вентилятора наблюдены non-manual |

Типы именно `ui8 ` / `flt ` (пробел — часть fourCC). One Fixed run, one restore run; восстановитель продолжает только оставшиеся **непопытанные** Auto steps с исходным deadline 8 с. MaximumOwnerRecoveryRuns=1 в candidate не означает повтор вручную: этот сеанс дополнительных команд восстановления не даёт. Каждый device operation имеет бюджет 0.5 с, quiescence 1 с; синхронный IOKit не имеет доказанной отмены и уже начатый kernel вызов не гарантированно укладывается в бюджет.

Independent reader должен подтвердить manual/target/RPM rise; Auto evidence — минимум три отдельных mode readings с интервалами ≥1 с. Нулевые исходные RPM остаются нулевыми. Fixed не начинается при изменённых диапазонах/типах/числе вентиляторов, stale/slow data, elevated/unknown pressure, неверной подписи/boot/receipt или потерянном recovery probe. Неполный Auto сохраняет pending даже при успехе оставшихся шагов.

## STOP и физическая остановка

При любом STOP **ничего не повторять**: run/register/ready, APPROVE, START, Fixed, Auto и прежние owner scripts. Сохраните вывод и пакеты, пришлите последние строки. Если отказ произошёл до START, SMC writes не должны были начаться; достигнутая подпись/staging/backup/installation/root state сохраняются без автоматического отката.

После START при неизвестном восстановлении/recoveryRequired/ошибке или отсутствии результата через 25 с прекратите нагрузки. Не удаляйте root journal и не перезапускайте службу; не вводите дополнительные SMC команды. Если Mac нагревается, вентиляторы ведут себя неправильно либо нельзя подтвердить возврат управления, **физически выключите Mac удержанием кнопки питания**, оставьте выключенным и сообщите разработчику. Выключение не считается proof Auto; данные/конфигурацию не очищать. Broker самостоятельно пытается только разрешённые оставшиеся Auto steps, без нового Fixed и без продления lease; неизвестный эффект оставляет pending.

## Что зафиксировано

Manifest связывает owner/machine/boot, script/PLAN, десять writes, installed5/private GUI3 и **15 protected директорий**. Signed seal связывает новые пять файлов, positive qualification и полный review. GUI controls/hardwareControlAvailable/physicalAutoVerified остаются false. Resetbtm, ручные launchd действия и key ACL не меняются.
