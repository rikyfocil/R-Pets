import AppKit
import SwiftUI

/// RPetsTester — a tiny windowed app with buttons that send hardcoded commands to RPets.
final class TesterAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingView(rootView: TesterView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RPets Tester"
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let application = NSApplication.shared
let delegate = TesterAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
