import AppKit

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--icon" {
    Icon.writeAppIcon(to: CommandLine.arguments[2])
    exit(0)
}
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--snapshot" {
    Snapshot.run(into: CommandLine.arguments[2])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
