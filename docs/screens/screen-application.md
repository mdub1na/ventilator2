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

Реализована новая compiled identity `dev.ventilator.app` / `dev.ventilator.app.helper` с одноимённым plist; Apple anchor/Team/CDHash и root peer gates сохранены. Старые identities и лишний legacy plist отвергаются до signature/framework. 29 installation/setup tests, strict ad hoc build и anonymous XPC/runtime models прошли. Это **source verification**, installed версия ещё прежняя. Полный [owner сеанс новой identity](../gui-helper-identity-owner.md) проверяет гипотезу сохранённой истории: positive qualification до lifecycle, pending/absent-only old removal, exact backup, sole GUI register и раздельные CONNECTED → ON → ALLOW/NONE. Hardware writes=[], actual новая регистрация пока не выполнена. [Source evidence](../research/evidence/helper-identity-source-preparation.json).

После owner включения actual AX ON независимо подтверждён; единственный native status в 19:13:33 +05:00 остался **requiresApproval/serviceNotEnabled**, helperVerified=false. CLI exit 0 означает завершение диагностики. Frozen continuation4, completed reconnect30, protected12, installed5 и private GUI2 сохранены; runtime отсутствует, hardware writes 0. ON не привёл к root positive. Повтор статуса/регистрации не выполняется; исследуется системный допуск. [Actual result](../research/evidence/gui-helper-enable-result.json).

Владелец подтвердил, что после последнего register пропустил ON. Подготовлено [продолжение только с включением фоновой активности](../gui-helper-enable-owner.md): существующая установка/регистрация сохраняются, после owner ON агент независимо проверяет переключатель и делает один bounded native status. Повтор signing/reconnect/register не нужен. ON/positive root пока не подтверждены, hardware writes 0.

Последний installed reconnect завершён в 18:33:33 +05:00: GUI PID 49998 остаётся в requiresApproval, «Подключить помощник» disabled, «Открыть настройки macOS» и «Проверить состояние» доступны. Чтение экрана агентом не повторяет framework status/register. Строка автозапуска показывает «Пока недоступно» в новой установленной версии. Отдельное чтение Settings показывает Ventilator OFF; сообщение NONE само по себе не подтверждает ON. Владелец затем подтвердил пропуск ON; следующий план продолжает только это включение и одну проверку агентом. [Факты](../research/evidence/gui-helper-reconnect-result.json).

Прежний GUI PID 35574 и enabled/remoteFailure относятся к предыдущей установке. Последующий refresh того GUI показал connectionFailed; persistent расхождение GUI/CLI не доказано. Source shortcut `--show-helper-setup` только открывает раздел. Positive production root result ещё не получен.

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
