import Darwin
import Foundation
import VentilatorInstallation

func runHelperServiceCommand(_ arguments: [String]) -> Bool {
    guard let command = arguments.first, ["--inspect-signed-bundle", "--helper-status", "--verify-installed-helper", "--register-helper", "--unregister-helper"].contains(command) else { return false }
    do {
        if command == "--inspect-signed-bundle" {
            guard arguments.count == 1 || (arguments.count == 2 && arguments[1].hasPrefix("/")) else {
                throw InstallationError.invalidChallenge
            }
        } else {
            guard arguments.count == 1 else { throw InstallationError.invalidChallenge }
        }
        let report: HelperServiceReport
        if command == "--inspect-signed-bundle" {
            report = HelperServiceController.inspectBundle(arguments.count == 2 ? URL(fileURLWithPath: arguments[1]) : nil)
        } else if command == "--register-helper" { report = try HelperServiceController.register() }
        else if command == "--unregister-helper" { report = try HelperServiceController.unregister() }
        else { report = HelperServiceController.status() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
        if command == "--verify-installed-helper" && !report.helperVerified { exit(78) }
        if command == "--inspect-signed-bundle" && !report.trustedBundle { exit(78) }
    } catch {
        fputs("Ventilator installation: \(error)\n", stderr); exit(78)
    }
    return true
}
