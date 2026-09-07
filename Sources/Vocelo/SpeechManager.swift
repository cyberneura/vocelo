import AVFoundation
@preconcurrency import Speech
import Foundation

/// The audio render callback is not main-actor isolated. This lock protects request
/// handoff and ensures endAudio never races an append on the same request.
private final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    func replace(with next: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        defer { lock.unlock() }
        request?.endAudio()
        request = next
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        request?.append(buffer)
    }
}

@MainActor
final class SpeechManager {
    private struct Segment {
        var text = ""
        var done = false
        var task: SFSpeechRecognitionTask?
        var deadline: Task<Void, Never>?
    }
    private let engine = AVAudioEngine()
    private let sink = AudioSink()
    private var recognizer: SFSpeechRecognizer?
    private var segments: [Segment] = []
    private var rotation: Task<Void, Never>?
    private var session = UUID()
    private var config = VoceloConfig()
    private var tapInstalled = false
    private(set) var isRecording = false
    private(set) var isBusy = false
    var onStatus: ((String) -> Void)?
    /// Live transcript across all segments, called whenever a partial result arrives.
    var onTranscript: ((String) -> Void)?
    var onComplete: ((String, String?) -> Void)?
    private var warning: String?

    // SFSpeechRecognizer calls back on a background queue; a MainActor-inferred
    // closure would trap in the Swift 6 isolation check, so keep this nonisolated.
    nonisolated static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start(config: VoceloConfig) throws {
        guard !isBusy else { throw VoceloError("Wait for the previous transcription to finish.") }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw VoceloError("Grant Microphone and Speech Recognition access using the Vocelo menu.")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: config.language)),
              recognizer.supportsOnDeviceRecognition else {
            throw VoceloError("On-device recognition is unavailable for \(config.language). Install the language in macOS Dictation settings or choose another language.")
        }
        guard recognizer.isAvailable else { throw VoceloError("Speech recognition is currently unavailable. Try again later.") }
        self.recognizer = recognizer
        self.config = config
        session = UUID()
        segments = []
        warning = nil
        isBusy = true
        isRecording = true
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            cancel()
            throw VoceloError("No working microphone is available.")
        }
        beginSegment()
        let sink = self.sink
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in sink.append(buffer) }
        tapInstalled = true
        do {
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw error
        }
        onStatus?("Listening… Release hotkey to insert")
    }

    private func beginSegment() {
        guard isRecording, let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = config.autoPunctuation
        let index = segments.count
        let token = session
        segments.append(Segment())
        segments[index].task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.receive(index: index, token: token, text: text, final: final, error: message)
            }
        }
        sink.replace(with: request)
        rotation?.cancel()
        rotation = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(40)) } catch { return }
            guard let self, self.isRecording, self.session == token else { return }
            self.beginSegment()
            self.setDeadline(index: index, token: token)
        }
    }

    private func receive(index: Int, token: UUID, text: String?, final: Bool, error: String?) {
        guard token == session, segments.indices.contains(index), !segments[index].done else { return }
        if let text {
            segments[index].text = text
            onTranscript?(joinedTranscript())
        }
        if final || error != nil {
            segments[index].done = true
            segments[index].deadline?.cancel()
            segments[index].task = nil
            if let error {
                warning = "Speech recognition stopped: \(error). Available text was preserved."
                // Do not retry service/rate-limit failures in a tight loop.
                if isRecording { stop() }
            } else if isRecording && index == segments.count - 1 {
                beginSegment() // The recognizer may finalize early after silence.
            }
            finishIfReady()
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        rotation?.cancel()
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        sink.replace(with: nil)
        onStatus?("Finalizing…")
        for index in segments.indices where !segments[index].done {
            setDeadline(index: index, token: session)
        }
        finishIfReady()
    }

    private func setDeadline(index: Int, token: UUID) {
        guard !segments[index].done, segments[index].deadline == nil else { return }
        segments[index].deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self, self.session == token, !self.segments[index].done else { return }
            self.segments[index].done = true
            self.segments[index].task?.cancel()
            self.segments[index].task = nil
            self.warning = "Finalization timed out; the latest partial transcription was preserved."
            self.finishIfReady()
        }
    }

    private func finishIfReady() {
        guard isBusy, !isRecording, segments.allSatisfy(\.done) else { return }
        let text = joinedTranscript()
        let warning = self.warning
        isBusy = false
        segments = []
        onComplete?(text, warning)
    }

    private func joinedTranscript() -> String {
        let texts = segments.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let separator = config.language.hasPrefix("ja") || config.language.hasPrefix("zh") ? "" : " "
        return texts.joined(separator: separator)
    }

    func cancel() {
        session = UUID()
        isRecording = false
        isBusy = false
        rotation?.cancel()
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        sink.replace(with: nil)
        for segment in segments { segment.deadline?.cancel(); segment.task?.cancel() }
        segments = []
    }
}
