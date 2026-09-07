import AppKit
@preconcurrency import ApplicationServices
import Carbon

@MainActor
final class TextInsertion {
    struct Target {
        let pid: pid_t
        let element: AXUIElement?
    }
    private(set) var isBusy = false

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func captureTarget() -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return Target(pid: app.processIdentifier, element: focusedElement(pid: app.processIdentifier))
    }

    private func focusedElement(pid: pid_t) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid),
                kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    func insert(_ text: String, into target: Target?) async throws {
        guard !text.isEmpty else { return }
        guard !isBusy else { throw VoceloError("A paste is already in progress.") }
        guard AXIsProcessTrusted() else { throw VoceloError("Enable Vocelo in System Settings → Privacy & Security → Accessibility.") }
        guard let target, NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else {
            throw VoceloError("The active app changed. Use Copy Last Transcript from the menu.")
        }
        let current = focusedElement(pid: target.pid)
        if let original = target.element {
            guard let current, CFEqual(original, current) else {
                throw VoceloError("The focused field changed. Use Copy Last Transcript from the menu.")
            }
        }
        if let current {
            var role: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(current, kAXSubroleAttribute as CFString, &role)
            if role as? String == kAXSecureTextFieldSubrole {
                throw VoceloError("Vocelo does not insert into secure text fields.")
            }
            var settable = DarwinBoolean(false)
            if AXUIElementIsAttributeSettable(current, kAXSelectedTextAttribute as CFString, &settable) == .success,
               settable.boolValue,
               AXUIElementSetAttributeValue(current, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
                return
            }
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            throw VoceloError("Unable to create a paste keyboard event.")
        }
        isBusy = true
        defer { isBusy = false }
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        var saved: [NSPasteboardItem] = []
        for item in pasteboard.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    throw VoceloError("The clipboard cannot be safely saved. Use Copy Last Transcript.")
                }
                copy.setData(data, forType: type)
            }
            saved.append(copy)
        }
        guard pasteboard.changeCount == before else {
            throw VoceloError("The clipboard changed while preparing to paste. Use Copy Last Transcript.")
        }
        let ownershipType = NSPasteboard.PasteboardType("com.cyberneura.vocelo.clipboard-owner")
        let ownershipToken = UUID().uuidString
        let temporary = NSPasteboardItem()
        temporary.setString(text, forType: .string)
        temporary.setString(ownershipToken, forType: ownershipType)
        let cleared = pasteboard.clearContents()
        guard pasteboard.changeCount == cleared, pasteboard.writeObjects([temporary]) else {
            if pasteboard.changeCount == cleared, !saved.isEmpty { pasteboard.writeObjects(saved) }
            throw VoceloError("Unable to write the transcript to the clipboard.")
        }
        let ownedChangeCount = pasteboard.changeCount
        guard pasteboard.string(forType: ownershipType) == ownershipToken,
              pasteboard.changeCount == ownedChangeCount else {
            throw VoceloError("The clipboard changed before pasting. Use Copy Last Transcript.")
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(target.pid)
        up.postToPid(target.pid)
        // macOS provides no paste-consumed acknowledgment. Allow the target time
        // to read, then restore only if nobody has subsequently changed the board.
        try? await Task.sleep(for: .milliseconds(500))
        if pasteboard.changeCount == ownedChangeCount,
           pasteboard.string(forType: ownershipType) == ownershipToken,
           pasteboard.changeCount == ownedChangeCount {
            pasteboard.clearContents()
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
        }
    }
}
