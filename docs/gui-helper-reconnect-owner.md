> Сеанс завершён 2026-10-04 в 18:33:33 +05:00: requiresApproval, system job absent, hardware writes 0. **Не повторять reconnect/update/register/ready.** [Проверенный итог](research/evidence/gui-helper-reconnect-result.json).

# Один сеанс повторного подключения после исправления startup

Снимок разрешений уже завершён: записи allowed, system job отсутствует. Новая проверенная сборка убирает лишнее mainApp status при startup. Его влияние на старую регистрацию не доказано; этот сеанс проверяет новый путь после штатного снятия старой регистрации. Профиль **Mac15,7 / macOS 27.0.1 / 26A434 — read-only**. Полный список аппаратных записей: **`[]`**, число записей — **0**. Аппаратный review/approval/ready/start/worker/Auto/sleep experiment в пакете отсутствуют.

## Полный порядок владельца — примерно 3–7 минут

Выполните **один раз** в своём обычном Terminal, без внешнего sudo:

```bash
python3 /Users/mdub1na/IdeaProjects/ventilator2/.build/gui-helper-reconnect-owner/session.py reconnect
```

Затем следуйте подсказкам одного скрипта в следующем порядке:

1. **Command-Q → CLOSED.** Завершите установленный Ventilator через «Выйти» или Command-Q. Закрытие окна не завершает приложение. Введите CLOSED только после выхода. Скрипт проверит отсутствие процесса; при живом процессе остановится без сигналов и повтора.
2. **Подпись → проверка → sudo.** Если Keychain запросит доступ к ключу Apple Development, подтвердите его в системном окне. Скрипт подпишет только payload нового пакета и проверит positive revocation до системных изменений. Если проверка подписи откажет, он остановится до OFF/removal/replacement. Хеши signed app/helper/plist будут напечатаны и сохранены в seal. При запросе sudo введите пароль администратора только в Terminal; он может понадобиться для root-owned staging, bounded чтения job и точной замены. Старые пакеты не переподписываются.
3. **Настройки → OFF.** После подсказки откройте «Системные настройки → Основные → Объекты входа и расширения → Фоновая активность приложений». Выключите **только Ventilator**, затем введите OFF. Если нужной записи нет или её нельзя выключить, введите CANCEL. До этого шага подпись/staging уже проверены, system job должен отсутствовать. Скрипт потребует actual requiresApproval/serviceNotEnabled либо already unregistered. Enabled/ошибка/изменённый runtime запрещают снятие регистрации и замену. Для requiresApproval выполняется один прежний guarded unregister; после него status=notRegistered и root job absent обязательны.
4. **Новое окно → одно подключение → ON/Allow.** Скрипт сохранит exact старую копию в `previous-installed.bundle` нового пакета, установит новую root-owned копию и откроет раздел «Приложение». Нажмите **«Подключить помощник» один раз**, если кнопка включена. Затем включите только Ventilator в той же фоновой активности. Если появится Background Items Added, выберите Allow и подтвердите пароль/Touch ID администратора. Не ищите замену отсутствующему уведомлению: после включения введите NONE, если запроса не было; ALLOW — только после настоящего Allow/admin. Если запись/кнопка отсутствует или действие невозможно, введите CANCEL. Ключ и sudo не заменяют это системное разрешение.
5. **Итог → прислать последние строки.** Скрипт один раз прочитает native report/root job. Только actual enabled + bound root XPC + loaded job считаются read-only helper verification; при успехе один status подтвердит unsupportedMachine без аппаратного опыта. Pending/failed вывод сохраняется и завершает сеанс. При любом STOP не повторяйте reconnect или прежние collect/update/register/ready; пришлите последние строки.

Сон и перезагрузка не нужны. После STOP остаются подписанный payload, markers, staging/backup и текущая установленная копия в достигнутом состоянии; автоматического отката, повторов или ручного bootstrap нет. До замены старая копия остаётся в /Applications; после замены её exact bytes находятся в backup этого пакета. Не перемещайте эти файлы и не меняйте разрешения снова до анализа результата.

## Связанные данные и действия

Manifest связывает owner/machine/boot, script/PLAN, предыдущий installed fingerprint и пять файлов, новую payload, private GUI history и **12 protected директорий**, включая 27 файлов GUI update и 7 файлов completed administrative read. Staging только статически inspect-ится из pinned payload; не запускается и не обращается к ServiceManagement. На этом Mac helper startup/status не создают отсутствующее simulation/hardware storage.

Системные действия ограничены подписью двух новых executable/bundle, одним root staging/exact backup/replacement, owner OFF/ON только Ventilator, условным одним unregister и одним GUI register. Lifecycle-команды наследуют прежние signed/canonical/root-owned/absent-runtime guards. Root job должен отсутствовать и до OFF, и непосредственно перед old unregister; loaded/unknown ответ запрещает снятие регистрации. Enabled без подтверждённого OFF не обходит требование живого root peer. Никакого global resetbtm, manual bootstrap, bootout/kickstart, отключения защиты или private-key ACL changes нет.

Повтор после run-started запрещён. Signed hashes появляются только после owner signing/qualification и до OFF/removal; пока пакет содержит проверенную ad hoc payload. Script/PLAN/подготовительные hashes записаны в manifest и исследование. Успех отдельного probe и моделей не заменяет actual production root verification.
