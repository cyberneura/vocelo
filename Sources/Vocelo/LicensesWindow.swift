import AppKit

/// A read-only window showing the app's LICENSE and THIRD-PARTY-NOTICES.txt, as embedded
/// at build time.
@MainActor
final class LicensesWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // An accessory (LSUIElement) app is not active when its status menu is used,
        // so without this the window opens behind the frontmost app.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Third-Party Licenses"
        // Kept by this object and dropped in windowWillClose, so the default release on
        // close would free it twice.
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 360, height: 240)
        window.delegate = self

        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        // The app's own license first: LICENSE is not in the bundle, so this is the only
        // place an installed copy carries it.
        textView.string = ["Vocelo", ThirdPartyNotices.appLicense, String(repeating: "#", count: 80),
            ThirdPartyNotices.text].joined(separator: "\n\n")
        window.contentView = scrollView
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
