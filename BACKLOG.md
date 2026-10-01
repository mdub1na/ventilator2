# План реализации

Отмечено только то, что проверено. Основа — [исследование](docs/research/research-architecture.md) и [задание владельца](docs/research/evidence/owner-brief.txt).

## M1 — наблюдение

- [x] SwiftPM-приложение с read-only SMC-транспортом.
- [x] Окно с четырьмя разделами и созданный NSStatusItem.
- [x] Чтение двух вентиляторов на `Mac15,7` + macOS 27 без `sudo`.
- [x] Различение `0 RPM` и отсутствующего показания; индивидуальные диапазоны.
- [x] Кнопки аппаратного управления отключены.
- [x] Проверить визуальный вид и оба вида клика по значку на живом экране — подтверждено владельцем 2026-09-30.
- [x] Установить достоверные источники CPU/GPU/SSD либо сохранить «Нет данных» с результатом проверки — SSD NAND подтверждён и добавлен, CPU/GPU остаются неизвестными по [результатам исследования](docs/research/research-temperatures.md).

Итог этапа: наблюдение работает, SSD (NAND CH0) читается; необозначенный `Tf26` не выдан за CPU/GPU/SSD. Владелец подтвердил работу значка. Источники CPU/GPU остаются открытой задачей для полноценной поставки.

## M2 — подготовка единственного опыта

- [x] Собрать отдельный прототип помощника и ограниченный симуляционный RPC; проверить anonymous XPC без root.
- [x] Реализовать десятисекундный lease, binding соединения, маркер до изменения и восстановление на подставном транспорте; проверить файловый журнал после SIGKILL.
- [x] Подключить файловый журнал и независимый worker к симуляционному XPC-пути; проверить SIGKILL/SIGSTOP помощника, SIGTERM worker и отказ Auto.
- [x] Экспортировать неодобренный кандидатный план с бинарными хешами, точным перечнем предполагаемых команд и проверкой неизменности профиля/диапазонов/сроков.
- [x] Подготовить отдельный нативный writer с фиксированными операциями, проверками типа/размера/порядка/deadline; сверить каждый пакет с планом без аппаратных вызовов.
- [x] Реализовать файловые challenge/одноразовое решение и учёт каждой попытки до I/O; проверить подмену, replay, restart, частичную ошибку и разделение simulation/hardware.
- [x] Добавить отдельный broker надзора за writer: durable closure, подтверждённый выход перед Auto, ограниченные device-процессы, private IPC и отложенный sleep acknowledgement; проверить на файловой модели.
- [x] Подготовить независимое read-only наблюдение опыта, отзыв reservation перед I/O и свежий bound recovery probe; проверить чтение на Mac и IPC/ошибки на моделях.
- [x] Подготовить общую связку broker/Fixed/Auto/read-only reader и private recovery handler; проверить отказ reader и сохранение pending на модели.
- [x] Реализовать локальный TTY issuer полного review и recovery после restart broker: device lifetime lock, только оставшиеся Auto-шаги, исходный deadline, сохранение pending при неизвестном Auto; проверить полный путь на модели.
- [x] Подготовить installed bundle/signature gate, явный registration/removal CLI и bound диагностический XPC; проверить отрицательные случаи и signing probe без доступа к ключу.
- [x] Подключить guarded daemon/XPC session proxy, isolated preflight и startup recovery; проверить полный путь и lifetime lock на immutable non-root модели.
- [ ] Сделать аппаратный протокол с проверяемым одобрением конкретного плана и привязкой записей к точной модели/сборке ОС, диапазонам и сроку lease. Симуляция такого одобрения не выдаёт.
- [ ] Подключить файловый маркер, реальные системные события и независимый ограниченный восстановитель к аппаратному helper; доказать восстановление в утверждённом опыте.
- [x] Добавить предварительные проверки машины/показаний и отдельные критерии наблюдаемого изменения RPM и устойчивого кода Auto на подставных снимках.
- [ ] Провести dry-run, собрать и подписать установленный bundle с подходящей identity.
- [x] Подготовить owner client/full-review import и единый план с проверенными ad hoc хешами, seal финальных signed хешей, всеми SMC-записями и stop-процедурой; проверить offline/model путь.
- [x] Исправить owner qualification после реальной подписи: проверить допустимые Security flags, фактический Team и positive revocation; сохранить failed пакет и подготовить новую сборку/последовательность.
- [x] Исправить первую регистрацию без BTM record; подтвердить реальные signed/root-owned installed gates, подготовить ограниченную замену незарегистрированной версии с backup и проверками, сохранить план/результаты.
- [ ] Выполнить с владельцем подпись/qualification/установку и получить одно локальное одобрение точного sealed опыта.
- [ ] После одобрения выполнить ровно один ограниченный аппаратный опыт и проверить устойчивый возврат Auto.

Проверено 2026-09-30: [симуляция](docs/features/feature-control-simulation.md), независимый процесс восстановления, [подготовленный протокол](docs/features/feature-experiment-protocol.md) и [dry-run](docs/research/evidence/control-dry-run.txt). На текущем шаге локальный issuer и restart подготовлены и проверены на модели; для аппаратного runtime нужны подключение broker к daemon/public start и положительный signed/installed gate. Кандидатный план не готов к одобрению. GUI по-прежнему read-only; hardwareControlAvailable=false. До PR #2 локально было 0 valid identities; последняя команда сообщает 2, одна помечена revoked. Подпись второй identity и установленный helper ещё не проверены.

2026-10-01: [отдельный broker](docs/research/evidence/recovery-dry-run.txt) проверен для точных одобренных шагов **модели**, включая аварии самого writer и блокирующий эффект. На тот момент аппаратная привязка broker/локальный issuer оставались открытыми; свидетельство `ArmedHardwareRecovery` не выдавалось.

После создания [PR #1](https://github.com/mdub1na/ventilator2/pull/1) продолжена подготовка: [read-only наблюдатель](docs/research/evidence/experiment-read-only.json) прочитал FNum/Ftst/вентиляторы; новая admission проверка отзывает старый Fixed permit, recovery probe требует свежий private-pipe ответ. Это подготовленный код, не разрешение аппаратного старта.

PR #1, [PR #2](https://github.com/mdub1na/ventilator2/pull/2) и [PR #3](https://github.com/mdub1na/ventilator2/pull/3) объединены владельцем в main. После PR #3 полный model TTY → approval → begin → broker → restart проверен в [новом dry-run](docs/research/evidence/local-approval-restart-dry-run.txt). Новый broker не возобновляет Fixed, не повторяет попытки Auto и не продлевает исходные 8 с. Положительный root/Apple-signed/installed issuer и аппаратный restart ещё не запускались. Следующий шаг: signed/installed подготовка и подключение hardware admission/runtime; до первого действия владельца подготовить единый полный сеанс.

Подготовка после PR #4: [installed gate](docs/features/feature-helper-installation.md) реализован; ad hoc/register/layout отказы и peer/pending policies проверены. Headless signing probe остановился с SessionCreate OSStatus=100001 до codesign; ключи/ACL не изменялись. Положительные подпись, установка и privileged XPC остаются открытыми. Следующий шаг — завершить hardware admission/runtime и полный единый сеанс владельца; не просить отдельного keychain/installation действия до этого плана.

После PR #6: guarded session runtime реализован; положительные аппаратные проверки остаются открытыми. Следующий шаг — owner CLI/review staging и единый готовый сеанс, затем участие владельца для подписи/установки и конкретного опыта.

## M3 — управление и поставка

- [ ] Подтвердить атрибуцию CPU/GPU и повторить температурные чтения после сна/пробуждения; текущие кандидаты не считать доказанными датчиками.
- [ ] Только после доказанного M2 открыть UI ручного режима и проверить скрытое окно/выход.
- [ ] Проверить установку, автозапуск, сон/пробуждение, обновление и удаление.
- [ ] Добавлять иные Mac только после отдельных аппаратных проверок.

PR #7 объединил guarded runtime и исправление durable отзыва при SIGSTOP в authority transaction. Следующий шаг подготовил [единый сеанс владельца](docs/owner-session.md), Terminal client, защищённый импорт review и independent evidence. Дальнейший signed/installed/hardware positive требует действий владельца; обычный GUI остаётся read-only.

2026-10-02: подпись предыдущего owner package выполнена владельцем, но seal не создан из-за нашего `errSecCSInvalidFlags`. Ошибка и неверный Team исправлены; strict подписи и positive revocation сохранённых файлов подтверждены [реальным qualifier](docs/research/evidence/owner-signing-validation.json). Старые executable с ошибкой не устанавливаются; следующий шаг владельца — подписать новый пакет, затем следовать пяти шагам [обновлённого плана](docs/owner-session.md). Installed/root XPC и аппаратный опыт ещё не выполнялись.

Следующая owner попытка: подпись/seal и root-owned установка прошли, первая регистрация отказала до framework register из-за нашего notFound guard. Исправлен переход; 101 unit-тест, прежние process gates и owner replacement policy/orchestration прошли. Существующий signed пакет сохранён, новая сборка/план подготовлены с точными previous hashes. Следующий шаг владельца — подпись, ограниченная замена с backup и первый настоящий register; privileged XPC/аппаратный опыт ещё не проверены. [Факты](docs/research/evidence/owner-registration-failure.json), [полный план](docs/owner-session.md).
