import AppKit
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let hotkey = HotKeyManager()
    private let speech = SpeechManager()
    private let insertion = TextInsertion()
    private var config = VoceloConfig()
    private var configured = false
    private var held = false
    private var target: TextInsertion.Target?
    private var lastTranscript = ""
    private var insertionTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Vocelo")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Vocelo", action: nil, keyEquivalent: ""))
        menu.addItem(statusLine)
        menu.addItem(.separator())
        add("Grant Permissions…", action: #selector(grantPermissions), to: menu)
        add("Open Configuration", action: #selector(openConfiguration), to: menu)
        add("Reload Configuration", action: #selector(reloadConfiguration), to: menu)
        add("Copy Last Transcript", action: #selector(copyLastTranscript), to: menu)
        add("Cancel Recording", action: #selector(cancelRecording), to: menu)
        menu.addItem(.separator())
        add("Quit Vocelo", action: #selector(quit), to: menu)
        statusItem.menu = menu
        hotkey.onPress = { [weak self] in self?.pressed() }
        hotkey.onRelease = { [weak self] in self?.released() }
        speech.onStatus = { [weak self] in self?.setStatus($0) }
        speech.onComplete = { [weak self] text, warning in
            guard let self else { return }
            self.lastTranscript = text
            let target = self.target
            self.insertionTask = Task { [weak self] in
                guard let self else { return }
                defer { self.insertionTask = nil }
                do {
                    try await self.insertion.insert(text, into: target)
                    self.setStatus(warning ?? (text.isEmpty ? "No speech detected" : "Inserted transcript"))
                } catch { self.setStatus(error.localizedDescription); NSSound.beep() }
            }
        }
        reloadConfiguration()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(cancelRecording),
            name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(cancelRecording),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioConfigurationChanged),
            name: .AVAudioEngineConfigurationChange, object: nil)
    }

    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    private func setStatus(_ text: String) {
        statusLine.title = text
        statusItem.button?.toolTip = "Vocelo — \(text)"
        statusItem.button?.image = NSImage(systemSymbolName: speech.isRecording ? "mic.fill" : "mic",
                                          accessibilityDescription: text)
    }

    private func pressed() {
        guard configured, !held, !speech.isBusy, insertionTask == nil else { return }
        held = true
        target = insertion.captureTarget()
        do { try speech.start(config: config) }
        catch { setStatus(error.localizedDescription); NSSound.beep() }
    }

    private func released() {
        held = false
        speech.stop()
    }

    @objc private func grantPermissions() {
        TextInsertion.requestAccessibility()
        Task { [weak self] in
            let granted = await SpeechManager.requestPermissions()
            self?.setStatus(granted ? "Speech and microphone ready; check Accessibility access" :
                "Enable Microphone and Speech Recognition in System Settings → Privacy & Security")
        }
    }

    @objc private func openConfiguration() {
        _ = NSWorkspace.shared.open(ConfigManager.url)
    }

    @objc private func reloadConfiguration() {
        guard !speech.isBusy, !held else { setStatus("Release the hotkey before reloading configuration"); return }
        do {
            let next = try ConfigManager.load()
            if !configured || next.keyCode != config.keyCode || next.carbonModifiers != config.carbonModifiers {
                try hotkey.register(config: next)
            }
            config = next
            configured = true
            setStatus("Ready — \(config.language) · \(config.modifiers.joined(separator: "+"))+key \(config.keyCode)")
        } catch { setStatus(error.localizedDescription); NSSound.beep() }
    }

    @objc private func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { setStatus("No transcript to copy"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
        setStatus("Transcript copied")
    }

    @objc private func cancelRecording() {
        held = false
        speech.cancel()
        setStatus("Recording cancelled")
    }

    @objc nonisolated private func audioConfigurationChanged() {
        // AVAudioEngine may post this notification from an audio thread.
        Task { @MainActor [weak self] in
            guard let self, self.speech.isRecording else { return }
            self.speech.stop()
            self.setStatus("Microphone changed; finalizing available audio")
        }
    }

    @objc private func quit() {
        // Do not exit while a temporary pasteboard value still needs restoring.
        Task { [weak self] in
            await self?.insertionTask?.value
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.unregister()
        speech.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
