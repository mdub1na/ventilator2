---
id: screen-application
title: Приложение
type: client_screen
platform: [macOS]
status: active
entry: {macOS: "Боковая панель → Приложение"}
parent_feature: feature-helper-installation
calls_api: []
source: Sources/Ventilator
---

# Приложение

Actual signed GUI update выполнен владельцем: после одноразового нажатия экран остался в requiresApproval, кнопка подключения disabled. Поздний отдельный CLI report — enabled/remoteFailure при отсутствующем system job. Наблюдения относятся к разным моментам; refresh агентом не вызывался, причина расхождения не доказана. Нельзя объяснять этот результат отсутствием GUI нажатия или исправлять повторным register. [Факты](../research/evidence/gui-helper-update-result.json), [следующее только чтение](../gui-helper-state-owner.md).

Исходники GUI шага объединены в main, для installed проверки подготовлен [один полный owner update](../gui-helper-owner-update.md). Source shortcut `--show-helper-setup` открывает именно этот раздел и не вызывает register. Положительный новый production GUI/root result ещё не получен.

## Состояния

- [x] **Unchecked / Checking:** состояние ещё не прочитано либо выполняется проверка вне UI потока.
- [x] **Unavailable:** signed/canonical/root-owned/process gates не пройдены, подключение отключено.
- [x] **NotRegistered:** helper не зарегистрирован; доступно одно явное «Подключить помощник».
- [x] **Registering:** регистрация из GUI main actor, повторное действие отключено.
- [x] **RequiresApproval:** actual framework status требует системного разрешения; доступны настройки macOS и явная проверка после Allow.
- [x] **Registered:** enabled без подтверждённого root handshake не показан как готовность.
- [x] **Verified:** actual trusted installed/root XPC status подтверждён; подпись и связь проверены.
- [x] **ConnectionFailed:** enabled, но peer verification отказала; детали доступны без обещания готовности.
- [x] **Stopped:** сохранена предыдущая попытка либо отказ действия; автоматической повторной регистрации нет.
- [x] **ReadOnly:** значок всегда включён; RPM controls остаются отключены во всех helper состояниях.
- [x] **LoginBlocked:** строка автозапуска сообщает «Пока недоступно». OS login-item status при startup не запрашивается; controls/register/unregister для этой недоступной функции отсутствуют.

Первое открытие раздела запускает одно диагностическое чтение. Обновление после системного Allow выполняется кнопкой «Проверить состояние», таймер monitoring helper не опрашивает. Pending/enabled register не повторяют. Старые CLI/owner пакеты не выполняются из GUI. Текущая подписанная production установка ещё не содержит этот экран; для owner испытания нужна отдельная подписанная замена. На Mac15,7 / 27.0.1 hardware runtime остаётся закрыт.

Закрытие окна оставляет процесс работающим. Действие закрытия проверено на запущенном приложении. Владелец подтвердил работу значка на живом экране 2026-09-30; [протокол](../research/evidence/m1-product-probe.txt). См. [feature](../features/feature-observation.md).

## Code anchors

| Компонент | Code |
|---|---|
| Экран | `Sources/Ventilator/MainWindowView.swift` |
| Helper states/actions | `Sources/Ventilator/HelperSetupView.swift`, `Sources/VentilatorInstallation/HelperSetupModel.swift` |
| Signature/process gate и GUI registration | `Sources/VentilatorInstallation/HelperServiceController.swift`, `Sources/VentilatorInstallation/GUIRegistrationAttempt.swift` |
| Отключённый rendering fixture | `Sources/Ventilator/HelperSetupPreview.swift` |
| Недоступный автозапуск без mainApp query | `Sources/Ventilator/MainWindowView.swift`, `Sources/Ventilator/MonitorStore.swift` |
| Жизненный цикл окна | `Sources/Ventilator/VentilatorMain.swift` |
