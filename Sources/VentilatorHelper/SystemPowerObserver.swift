import Foundation
import CSystemPower
import IOKit
import IOKit.pwr_mgt

/// Uses the public IOKit power notification API; does not request sleep or inhibit it.
final class SystemPowerObserver {
    private var port: io_connect_t = 0
    private var notification: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private let beforeSleep: (@escaping () -> Void) -> Void
    private(set) var registered = false

    convenience init(willSleep: @escaping () -> Void) {
        self.init(beforeSleep: { acknowledge in willSleep(); acknowledge() })
    }

    /// An independent broker can complete its bounded recovery before acknowledging the power event.
    init(beforeSleep: @escaping (@escaping () -> Void) -> Void) {
        self.beforeSleep = beforeSleep
        let context = Unmanaged.passUnretained(self).toOpaque()
        port = IORegisterForSystemPower(context, &notification, { context, _, message, argument in
            guard let context else { return }
            let observer = Unmanaged<SystemPowerObserver>.fromOpaque(context).takeUnretainedValue()
            observer.receive(message: message, argument: argument)
        }, &notifier)
        if port != 0, let notification, let source = IONotificationPortGetRunLoopSource(notification)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            registered = true
        }
    }

    private func receive(message: UInt32, argument: UnsafeMutableRawPointer?) {
        handle(message: message) { IOAllowPowerChange(self.port, Int(bitPattern: argument)) }
    }

    // The dry-run injects messages here with an acknowledgement stub, without changing system power.
    func handle(message: UInt32, acknowledge: @escaping () -> Void) {
        if message == VentilatorSystemWillSleepMessage() {
            let lock = NSLock()
            var completed = false
            beforeSleep {
                lock.lock()
                guard !completed else { lock.unlock(); return }
                completed = true; lock.unlock()
                acknowledge()
            }
        } else if message == VentilatorCanSystemSleepMessage() { acknowledge() }
    }

    deinit {
        if let notification, let source = IONotificationPortGetRunLoopSource(notification)?.takeUnretainedValue() {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if notifier != 0 { IODeregisterForSystemPower(&notifier) }
        if port != 0 { IOServiceClose(port) }
        if let notification { IONotificationPortDestroy(notification) }
    }
}
