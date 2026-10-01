import Darwin
import Foundation
import Security

// Only this disposable process changes sessions. No keychain unlock, import or ACL change.
func fail(_ message: String) -> Never { fputs("headless-sign: \(message)\n", stderr); exit(78) }
guard geteuid() != 0 else { fail("non-root required") }
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments == ["--probe"] || (arguments.count == 3 && ["helper", "application"].contains(arguments[0]) &&
    arguments[1].utf8.count == 40 && arguments[1].utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })) else {
    fail("usage: --probe | helper/application certificateSHA1 owned-build-bundle")
}
let created = SessionCreate([], [])
guard created == errSecSuccess else { fail("SessionCreate OSStatus=\(created)") }
var session: SecuritySessionId = 0, attributes: SessionAttributeBits = []
let inspected = SessionGetInfo(callerSecuritySession, &session, &attributes)
guard inspected == errSecSuccess, !attributes.contains(.sessionHasGraphicAccess), !attributes.contains(.sessionHasTTY) else {
    fail("noninteractive security session unavailable")
}
fputs("headless-sign: graphicAccess=false, tty=false; session inherited across exec\n", stderr)
if arguments == ["--probe"] { exit(0) }
let bundle = URL(fileURLWithPath: arguments[2]).standardizedFileURL
let build = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build").resolvingSymlinksInPath()
guard bundle.path.hasPrefix(build.path + "/"), bundle.pathExtension == "app", bundle.resolvingSymlinksInPath() == bundle else {
    fail("only a regular bundle in this workspace's .build is allowed")
}
let helper = arguments[0] == "helper"
let path = helper ? bundle.appendingPathComponent("Contents/MacOS/VentilatorHelper").path : bundle.path
for executable in ["Ventilator", "VentilatorHelper"] {
    let file = bundle.appendingPathComponent("Contents/MacOS/\(executable)")
    guard file.resolvingSymlinksInPath().path == file.path,
          (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { fail("invalid executable layout") }
}
let command = ["/usr/bin/codesign", "--force", "--sign", arguments[1], "--options", "runtime", "--timestamp=none"] +
    (helper ? ["--identifier", "dev.ventilator.helper"] : []) + [path]
var pointers = command.map { strdup($0) } + [nil]
// exec preserves this process's no-graphics/no-TTY session, unlike a change to the parent's keychain.
pointers.withUnsafeMutableBufferPointer { _ = execv(command[0], $0.baseAddress!) }
fail("codesign exec failed errno=\(errno)")
