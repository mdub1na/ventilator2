import AppKit
import VentilatorCore

@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let showWindow: () -> Void
    private let toggleWindow: () -> Void
    private var snapshot = MonitorSnapshot.placeholder
    private var contextClickMonitor: Any?

    init(showWindow: @escaping () -> Void, toggleWindow: @escaping () -> Void) {
        self.showWindow = showWindow
        self.toggleWindow = toggleWindow
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp])
            button.imagePosition = .imageLeading
            button.toolTip = "Ventilator — показания Mac"
        }
        contextClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, event.window == self.item.button?.window else { return event }
            self.showContextMenu()
            return nil
        }
        update(MonitorSnapshot.placeholder)
    }

    deinit {
        if let contextClickMonitor { NSEvent.removeMonitor(contextClickMonitor) }
    }

    func update(_ snapshot: MonitorSnapshot) {
        self.snapshot = snapshot
        guard let button = item.button else { return }
        button.image = statusImage(level: snapshot.maximumFanLevel)
        button.title = snapshot.cpuTemperature.map { String(format: " %.0f°", $0) } ?? " —°"
        button.setAccessibilityLabel("Ventilator, CPU: \(snapshot.cpuTemperature.map { String(format: "%.0f градусов", $0) } ?? "нет данных"), вентиляторы: \(snapshot.fans.map { "\($0.index + 1): \($0.actualRPM.map { String(Int($0)) } ?? "нет данных") оборотов" }.joined(separator: ", "))")
    }

    @objc private func clicked() {
        toggleWindow()
    }

    private func showContextMenu() {
        guard let button = item.button else { return }
        let menu = NSMenu()
        let device = NSMenuItem(title: "\(snapshot.modelIdentifier) · macOS \(snapshot.macOSVersion)", action: nil, keyEquivalent: "")
        device.isEnabled = false
        menu.addItem(device)
        menu.addItem(.separator())
        for temperature in snapshot.temperatures.prefix(3) {
            let row = NSMenuItem(title: "\(temperature.label): \(temperature.celsius.map { String(format: "%.1f °C", $0) } ?? "нет данных")", action: nil, keyEquivalent: "")
            row.isEnabled = false
            menu.addItem(row)
        }
        for fan in snapshot.fans {
            let row = NSMenuItem(title: "Вентилятор \(fan.index + 1): \(fan.actualRPM.map { String(format: "%.0f RPM", $0) } ?? "нет данных")", action: nil, keyEquivalent: "")
            row.isEnabled = false
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Открыть окно", action: #selector(openWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let auto = NSMenuItem(title: "Вернуть Auto — недоступно до проверки", action: nil, keyEquivalent: "")
        auto.isEnabled = false
        menu.addItem(auto)
        let quit = NSMenuItem(title: "Выйти из Ventilator", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    @objc private func openWindow() { showWindow() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private func statusImage(level: Int?) -> NSImage {
        let image = NSImage(size: NSSize(width: 65, height: 18), flipped: false) { rect in
            let fan = NSImage(systemSymbolName: "fanblades", accessibilityDescription: "Вентилятор")
            fan?.draw(in: NSRect(x: 0, y: 1, width: 17, height: 17))
            NSColor.secondaryLabelColor.setStroke()
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: 19, y: 9))
            arrow.line(to: NSPoint(x: 25, y: 9))
            arrow.line(to: NSPoint(x: 22, y: 12))
            arrow.move(to: NSPoint(x: 25, y: 9))
            arrow.line(to: NSPoint(x: 22, y: 6))
            arrow.stroke()
            let colors: [NSColor] = [.systemGreen, .systemGreen, .systemYellow, .systemOrange, .systemRed]
            for index in 0..<5 {
                let segment = NSBezierPath(roundedRect: NSRect(x: 29 + index * 7, y: 4, width: 5, height: 10), xRadius: 1, yRadius: 1)
                if let level, index < level {
                    colors[index].setFill()
                    segment.fill()
                } else {
                    NSColor.quaternaryLabelColor.setFill()
                    segment.fill()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
