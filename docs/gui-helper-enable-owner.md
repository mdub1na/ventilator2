> Продолжение завершено 2026-10-04 в 19:13:33 +05:00: actual AX ON, native requiresApproval/serviceNotEnabled, helperVerified=false. **Не повторять включение/проверку/регистрацию.** [Фактический результат](research/evidence/gui-helper-enable-result.json).

# Продолжение: включить уже зарегистрированный помощник

Владелец подтвердил, что после последнего GUI register пропустил ON. Установка завершена; actual report в 18:33:33 +05:00 — requiresApproval/serviceNotEnabled, root job absent. Повторять reconnect/sign/register не требуется. Продолжение относится к той же подписанной установленной версии и текущей boot session.

## Действия владельца по порядку

1. В уже открытых **Системных настройках → Основные → Объекты входа → Активность фоновых приложений** включите только **Ventilator**. Если переключатель уже включён, оставьте его включённым.
2. Если macOS запросит пароль администратора или Touch ID, подтвердите в системном окне. Если появится уведомление о фоновых объектах именно Ventilator с действием Allow/«Разрешить», подтвердите его. Отсутствие уведомления само по себе не считается ошибкой. Пароль в чат не отправляйте.
3. Убедитесь, что переключатель остаётся включённым. Напишите: **«Включил; подтверждение было»** или **«Включил; подтверждения не было»**. Если переключатель вернулся в OFF, напишите об этом и остановитесь.

Terminal, sudo, Keychain, подпись, переустановка, закрытие Ventilator, сон и перезагрузка в этом продолжении не требуются. Кнопки «Подключить помощник» и «Проверить состояние» пока не нажимайте: проверку ниже выполнит агент один раз после вашего сообщения.

Ожидаемое время — **1–2 минуты**, включая проверку агентом.

## Проверка агентом после сообщения владельца

1. Прочитать фактический переключатель Ventilator через accessibility: только ON допускает дальнейшую проверку. Сообщение об отсутствии уведомления не заменяет ON.
2. Сверить frozen continuation manifest/PLAN, owner/machine/boot, установленные пять файлов с qualification seal, completed reconnect (30 файлов), 12 предыдущих protected директорий и два приватных GUI markers. Whole root runtime должен по-прежнему отсутствовать. Проверка ещё не начата — replay не допускается.
3. Сохранить exclusive verification-started marker; выполнить один bounded read-only вызов `/Applications/Ventilator.app/Contents/MacOS/Ventilator --helper-status` из non-root процесса, с внешним deadline 10 секунд. Команда сама проверяет canonical installed/dynamic signature перед ServiceManagement и nonce/UID 0/PID/CDHash/fingerprints перед helperVerified. Framework status и XPC не вызываются до owner ON.
4. Сохранить actual report, exit code и результат повторной проверки сохранности. Только actual enabled + helperVerified=true + error отсутствует для exact fingerprint подтверждает связь. Pending, timeout или иной отказ сохраняются; автоматического повтора нет. Root job PID отдельно не заявляется по одному полю enabled.

Полный список аппаратных записей: **`[]`**, число записей — **0**. Review/import/approval/start, аппаратные worker и Auto experiment не вызываются. Mac15,7 / 27.0.1 / 26A434 остаётся read-only даже при положительной связи.

## Остановка

Отсутствующая/неоднозначная строка Ventilator, переключатель, вернувшийся в OFF, другой запрос разрешений, изменённые файлы/boot/runtime или любой отказ проверки останавливают продолжение. Сообщите наблюдение. Установленная копия, оба backup и старые сеансы сохраняются; resetbtm, ручной запуск daemon, повтор register и автоматический rollback не выполняются. Аппаратного восстановления в этом продолжении нет: записи не планируются и предыдущего аппаратного опыта не было.

## Exact signed fingerprints

- Application SHA-256: `cf2b98b36f52a1c112dac327ae0ab5807c9db3721810fbe57c4e278667bd7157`.
- Helper SHA-256: `445228b93de5ef2903799c2837887bc670ab3a937e33ed9a1470ce440f1b4971`.
- LaunchDaemon SHA-256: `f4a3431e86d4a355664dc447d71e5283be7900ae2a7990d386a608330046cd2f`.

Qualification: positiveRevocation=true, Team `4659S5GD6X`, certificate SHA-1 `4895C06FF7407EAF5F350E78CF23D0B41AD466C9`. Предыдущие квалифицированные signed bytes используются без новой подписи. PLAN SHA-256 и подготовленные pins: [evidence](research/evidence/gui-helper-enable-preparation.json). Completed reconnect сохраняется целиком: [result](research/evidence/gui-helper-reconnect-result.json).
