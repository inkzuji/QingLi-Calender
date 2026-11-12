import AppKit

@MainActor
final class QingLiAppDelegate: NSObject, NSApplicationDelegate {
    var reopenDesktop: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let reopenDesktop else { return true }
        reopenDesktop()
        return false
    }
}
