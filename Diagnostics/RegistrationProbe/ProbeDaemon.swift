import Darwin
import Foundation
import os.log

@main enum RegistrationProbeDaemon {
    static func main() {
        if CommandLine.arguments == [CommandLine.arguments[0], "--model-check"] {
            print("Diagnostic daemon: no device code, file journal or XPC commands."); return
        }
        guard geteuid() == 0 else { fputs("Registration probe daemon requires root\n", stderr); exit(78) }
        Logger(subsystem: "dev.ventilator.registration-probe", category: "daemon").notice("Isolated registration probe started: pid=\(getpid(), privacy: .public) uid=\(geteuid(), privacy: .public)")
        dispatchMain()
    }
}
