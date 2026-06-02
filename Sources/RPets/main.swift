import AppKit

// RPets — skeleton entry point.
// Menu-bar (accessory) app: no Dock icon, lives in the status bar.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
