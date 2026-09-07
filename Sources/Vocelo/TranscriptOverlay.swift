import AppKit

/// Floating HUD in the middle of the screen that mirrors the live transcript.
/// It never takes focus, so the target app keeps its first-responder text field.
@MainActor
final class TranscriptOverlay {
    private let panel: NSPanel
    private let container = NSVisualEffectView()
    private let iconView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let transcriptLabel = NSTextField(wrappingLabelWithString: "")
    private var hideTask: Task<Void, Never>?
    // Bumped on every show/hide so a fade-out that already started cannot order the
    // panel out after a newer show() has taken over.
    private var generation = 0

    private static let width: CGFloat = 560
    private static let padding: CGFloat = 28
    private static let placeholder = "Speak now…"
    private static let maxLines = 6

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 160),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none

        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 22
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        panel.contentView = container

        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        iconView.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Listening")?
            .withSymbolConfiguration(config)
        iconView.contentTintColor = NSColor.systemRed
        iconView.wantsLayer = true

        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Listening"

        transcriptLabel.font = .systemFont(ofSize: 24, weight: .regular)
        transcriptLabel.textColor = .labelColor
        transcriptLabel.maximumNumberOfLines = Self.maxLines
        transcriptLabel.lineBreakMode = .byWordWrapping
        transcriptLabel.preferredMaxLayoutWidth = Self.width - Self.padding * 2

        for view in [iconView, statusLabel, transcriptLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.padding),
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.padding - 4),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            statusLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            transcriptLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.padding),
            transcriptLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.padding),
            transcriptLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 14),
            transcriptLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.padding),
        ])
    }

    func show() {
        generation += 1
        hideTask?.cancel()
        hideTask = nil
        setStatus("Listening")
        iconView.contentTintColor = .systemRed
        setTranscript("")
        layout()
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        // Always animate to 1: a direct assignment would be overwritten by a fade-out
        // animation that is still running.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        startPulse()
    }

    func update(transcript: String) {
        setTranscript(transcript)
        layout()
    }

    func finalize() {
        setStatus("Finalizing")
        iconView.contentTintColor = .systemOrange
        stopPulse()
    }

    func hide(after delay: Duration = .zero) {
        generation += 1
        let token = generation
        stopPulse()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            if delay > .zero {
                do { try await Task.sleep(for: delay) } catch { return }
            }
            guard let self, self.generation == token else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                self.panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.panel.orderOut(nil)
                }
            })
        }
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    private func setTranscript(_ text: String) {
        if text.isEmpty {
            transcriptLabel.stringValue = Self.placeholder
            transcriptLabel.textColor = .tertiaryLabelColor
        } else {
            transcriptLabel.stringValue = Self.tail(of: text, font: transcriptLabel.font)
            transcriptLabel.textColor = .labelColor
        }
    }

    /// Keeps the end of a long transcript visible: the label clips at maxLines, and the
    /// words just spoken matter more than the opening ones.
    private static func tail(of text: String, font: NSFont?) -> String {
        let font = font ?? .systemFont(ofSize: 24)
        let width = Self.width - Self.padding * 2
        let maxHeight = font.ascender - font.descender + font.leading
        let limit = CGFloat(Self.maxLines) * ceil(maxHeight) + 1
        func height(_ s: String) -> CGFloat {
            (s as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading],
                                         attributes: [.font: font]).height
        }
        guard height(text) > limit else { return text }
        var shown = Substring(text)
        while height("…" + shown) > limit, shown.count > 1 {
            shown = shown.dropFirst(max(1, shown.count / 10))
        }
        return "…" + shown
    }

    /// Resizes to fit the text and keeps the panel centered on the screen with the cursor.
    private func layout() {
        container.layoutSubtreeIfNeeded()
        let height = container.fittingSize.height
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(x: visible.midX - Self.width / 2, y: visible.midY - height / 2 + visible.height * 0.08)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: Self.width, height: height)), display: true)
    }

    private func startPulse() {
        stopPulse()
        guard let layer = iconView.layer else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0.35
        animation.duration = 0.7
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "pulse")
    }

    private func stopPulse() {
        iconView.layer?.removeAnimation(forKey: "pulse")
    }
}
