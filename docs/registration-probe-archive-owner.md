# Завершение архивирования тестового приложения

## Уже подтверждено

Тестовая служба `dev.ventilator.registration-probe.daemon` получила enabled и запустилась. Затем один unregister вернул notRegistered, system job отсутствовал. Старый скрипт остановился после CLOSED, потому что процесс тестового окна ещё работал. Повторять run/cleanup, регистрацию, подпись или unregister не требуется. Основной Ventilator остаётся requiresApproval; аппаратных записей не было.

Этот отдельный пакет завершает только перенос **Ventilator Registration Probe** в архив. Старые 21 файл сеанса и девять защищённых директорий сохраняются. Новый архив: `.build/registration-probe-archive-owner/retired.bundle`. Исходный PLAN/script не меняются; прежний cleanup-completed.json не создаётся задним числом.

## Полная последовательность

1. В обычном Terminal своей учётной записи, без внешнего sudo, выполните:

   ```bash
   python3 /Users/mdub1na/IdeaProjects/ventilator2/.build/registration-probe-archive-owner/session.py finish
   ```

2. При запросе выберите окно **«Ventilator — отдельная проверка регистрации»** и нажмите **Command-Q**. Это завершает тестовое приложение. Обычное окно Ventilator не закрывайте. Вернитесь в Terminal и введите **CLOSED**. Скрипт ждёт исчезновения сохранённого GUI PID до 10 секунд; если он жив, системные команды не выполняются.

3. Скрипт один раз прочитает текущий статус тестовой службы, затем отсутствие её system job. Для административного чтения/переноса **sudo может попросить пароль в Terminal**. Запроса Keychain, нового Allow или фоновых переключателей не ожидается. После `Probe archive complete` пришлите последние строки; повторные команды не нужны.

## Точные действия и остановка

До marker проверяются owner UID 501, Mac15,7 / macOS 27.0.1 / 26A434 через прежний frozen checker, exact hashes старого сеанса/нового script/PLAN, сохранённый signed seal с positiveRevocation=true, canonical root-owned установленная копия, отсутствие runtime Ventilator и нового archive target. Список аппаратных записей **пустой**.

| Действие | Scope | Предел |
|---|---|---|
| Installed CLI `--probe-status` | Только probe с его прежним sealed session; требуется notRegistered/notFound | 10 с |
| sudo launchctl print | `system/dev.ventilator.registration-probe.daemon`; только read, требуется exit 113 | Alarm 5 с после аутентификации |
| sudo mv -n | `/Applications/Ventilator Registration Probe.app` → новый `retired.bundle` | Alarm 20 с после аутентификации |

Sudo имеет внешний предел 180 секунд на ручную аутентификацию. Native inspection/SMAppService status не регистрирует службу и не вызывает XPC. Перед переносом повторно проверяются exact installed/source/protected hashes, отсутствие GUI PID и destination. После переноса проверяются отсутствие installed path, пять signed hashes архива и прежние файлы. Новый archive-completed.json отмечает только успешно проверенный перенос.

Отмена до marker сохраняет состояние. После archive-started.json повтор запрещён даже при ошибке чтения/переноса. При любом STOP сохраните оба пакета, пришлите полный вывод и остановитесь. Нет автоматического удаления, подписи, retry, unregister, перезапуска службы или глобального resetbtm. Если перенесены файлы, но completion отсутствует, пути сохраняются для чтения и отдельного разбора; не возвращайте копию вручную.

## Code anchors

| Поведение | Code |
|---|---|
| Отдельный перенос после завершённого unregister | `scripts/registration-probe-archive.py` |
| Сохранённые signature/owner/installed/root-read gates | `scripts/registration-probe-session.py` |
| Модели STOP/replay/GUI и переноса | `scripts/registration-probe-archive-dry-run.py` |
