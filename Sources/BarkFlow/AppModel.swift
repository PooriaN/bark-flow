import AppKit
import AVFoundation
import Combine

enum Phase: Equatable {
    case loading, ready, arming, recording, processing, inserting, failed
}

@MainActor
final class AppModel: ObservableObject {
    @Published var recordingLimit: Int = {
        let value = UserDefaults.standard.integer(forKey: "recordingLimitSeconds")
        return [30,60,120,300,600].contains(value) ? value : 120
    }() { didSet { UserDefaults.standard.set(recordingLimit, forKey:"recordingLimitSeconds") } }
    @Published var phase: Phase = .loading
    @Published var status = "Preparing your local speech model…"
    @Published var transcript = ""
    @Published var level: Float = 0
    @Published var elapsed: TimeInterval = 0
    @Published var accessibilityAllowed = TextInsertion.allowed
    @Published var microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var shortcutError: String?
    @Published var showSettings = false
    @Published var theme: FlowTheme = .minimal {
        didSet { theme.save(in:preferences); onChange?() }
    }
    @Published var selectedModel: ModelChoice = .saved
    @Published var lastTranscriptionSeconds: Double?
    @Published var shortcuts: ShortcutBindings = .saved
    @Published var editingShortcut: ShortcutRole?
    @Published var autoInsert: Bool = UserDefaults.standard.object(forKey: "autoInsert") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoInsert, forKey: "autoInsert") }
    }
    @Published var sounds: Bool = UserDefaults.standard.bool(forKey: "sounds") {
        didSet { UserDefaults.standard.set(sounds, forKey: "sounds") }
    }
    private let preferences: UserDefaults
    let speech = SpeechEngine()
    private let recorder = MicrophoneRecorder()
    private var target: InsertionTarget?
    private var insertionIssue: InsertionIssue?
    private var timer: Timer?
    private var started: Date?
    private var discardResult = false
    var onChange: (() -> Void)?
    var showWindow: (() -> Void)?
    var configureShortcuts: ((ShortcutBindings) throws -> Void)?
    var suspendShortcuts: (() -> Void)?

    var recordingLimitLabel: String {
        recordingLimit == 30 ? "30 seconds" : "\(recordingLimit / 60) \(recordingLimit == 60 ? "minute" : "minutes")"
    }
    var busy: Bool { [.loading, .arming, .recording, .processing, .inserting].contains(phase) }
    var canToggle: Bool { editingShortcut == nil && (phase == .ready || phase == .recording) }
    var title: String {
        switch phase {
        case .loading: "Getting ready"
        case .ready: "Ready when you are"
        case .arming: "Opening microphone"
        case .recording: "Listening"
        case .processing: "Turning speech into text"
        case .inserting: "Inserting text"
        case .failed: "Let’s get you set up"
        }
    }

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        theme = .saved(in:preferences)
        recorder.onLevel = { [weak self] value in
            Task { @MainActor in self?.level = value }
        }
        recorder.onLimit = { [weak self] in
            Task { @MainActor in self?.finish() }
        }
    }

    func prepare() {
        guard phase != .recording && phase != .processing && phase != .arming && phase != .inserting else { return }
        let selected = selectedModel
        phase = .loading; status = "Loading \(selected.displayName). First-time preparation may take a few minutes."
        onChange?()
        Task { [self] in
            do {
                let root = try await ModelDownloads.ensureAvailable(selected) { [self] message in
                    await MainActor.run { self.status = message }
                }
                try await speech.prepare(root: root, model:selected) { [self] message in
                    await MainActor.run { self.status = message }
                }
                phase = .ready; status = "Press \(shortcuts.start.label) in any text field to start."
                UserDefaults.standard.set(selected.rawValue, forKey:"selectedModel")
            } catch {
                phase = .failed; status = error.localizedDescription
            }
            onChange?()
        }
    }

    func selectModel(_ model: ModelChoice) {
        guard !busy, model != selectedModel || phase == .failed else { return }
        selectedModel = model; lastTranscriptionSeconds = nil
        prepare()
    }

    func beginShortcutCapture(_ role: ShortcutRole) {
        guard !busy else { return }
        suspendShortcuts?(); editingShortcut = role; shortcutError = nil; onChange?()
    }
    func captureShortcut(_ chord: ShortcutChord, role: ShortcutRole) {
        guard editingShortcut == role else { return }
        var proposed = shortcuts
        if role == .start { proposed.start = chord } else { proposed.stop = chord }
        do {
            try chord.validate(for:role)
            try configureShortcuts?(proposed)
            shortcuts = proposed; proposed.save(); editingShortcut = nil; shortcutError = nil
            status = "Shortcuts saved. Start with \(shortcuts.start.label); stop with \(shortcuts.stop.label)."
        } catch {
            let failure = error.localizedDescription
            cancelShortcutCapture()
            shortcutError = failure
        }
        onChange?()
    }
    func cancelShortcutCapture() {
        guard editingShortcut != nil else { return }
        editingShortcut = nil
        do { try configureShortcuts?(shortcuts) } catch { shortcutError = error.localizedDescription }
        onChange?()
    }
    func resetShortcuts() {
        guard !busy, editingShortcut == nil else { return }
        do {
            try configureShortcuts?(.defaults)
            shortcuts = .defaults; shortcuts.save(); shortcutError = nil
            status = "Default shortcuts restored."
        } catch { shortcutError = error.localizedDescription }
        onChange?()
    }
    func handleShortcut(_ action: ShortcutAction) {
        guard editingShortcut == nil else { return }
        switch action {
        case .start:
            if phase == .ready || (phase == .recording && shortcuts.usesSameKey) { toggle() }
        case .stop: if phase == .recording { finish() }
        }
    }

    func refreshPermissions() {
        accessibilityAllowed = TextInsertion.allowed
        microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func grantMicrophone() {
        Task {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
            } else {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            }
            refreshPermissions()
        }
    }

    func grantInsertion() {
        TextInsertion.requestAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func toggle(origin: InsertionOrigin = .shortcut) {
        guard editingShortcut == nil else { return }
        if phase == .recording { finish(); return }
        guard phase == .ready else { return }
        target = nil; insertionIssue = nil
        if autoInsert {
            switch TextInsertion.capture(origin:origin) {
            case .target(let captured): target = captured
            case .failure(let issue): insertionIssue = issue
            }
        }
        lastTranscriptionSeconds = nil
        discardResult = false; phase = .arming
        onChange?()
        Task { [self] in
            do {
                let permission = AVCaptureDevice.authorizationStatus(for: .audio)
                let allowed: Bool
                if permission == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .audio) }
                else { allowed = permission == .authorized }
                microphoneAllowed = allowed
                guard allowed else { throw FlowError("Allow microphone access in System Settings > Privacy & Security > Microphone, then try again.") }
                try await recorder.start(maxSeconds: TimeInterval(recordingLimit))
                phase = .recording; elapsed = 0; started = Date()
                status = insertionIssue == .accessibilityMissing ?
                    "Recording to transcript only. Enable Text insertion for automatic paste. Press \(shortcuts.stop.label) to finish." :
                    "Press \(shortcuts.stop.label) or click Stop to finish. Limit: \(recordingLimitLabel)."
                if sounds { NSSound(named: "Tink")?.play() }
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let started = self.started else { return }
                        self.elapsed = Date().timeIntervalSince(started)
                        if self.elapsed >= TimeInterval(self.recordingLimit) { self.finish() }
                    }
                }
            } catch { phase = .ready; status = error.localizedDescription; showWindow?() }
            onChange?()
        }
    }

    func finish() {
        guard phase == .recording else { return }
        timer?.invalidate(); timer = nil; started = nil; level = 0
        phase = .processing; status = "Transcribing on your Mac…"; onChange?()
        Task {
            do {
                let samples = try await recorder.stop()
                if sounds { NSSound(named: "Pop")?.play() }
                guard !discardResult else { completeCancellation(); return }
                let transcriptionStart = Date()
                let text = try await speech.transcribe(samples)
                lastTranscriptionSeconds = Date().timeIntervalSince(transcriptionStart)
                guard !discardResult else { completeCancellation(); return }
                guard !text.isEmpty else { throw FlowError("No words were recognized. Try speaking closer to the microphone.") }
                transcript = text
                let destination = target
                target = nil
                if autoInsert, destination != nil {
                    let outcome = await TextInsertion.insert(text, into: destination!)
                    handleInsertion(outcome,application:destination!.application.localizedName ?? "your app")
                } else if autoInsert, let issue = insertionIssue {
                    TextInsertion.copy(text)
                    status = issue.message
                    refreshPermissions(); showWindow?()
                } else {
                    status = "Your transcript is ready to copy."
                    showWindow?()
                }
                phase = .ready
            } catch {
                if discardResult { completeCancellation(); return }
                phase = .ready; status = error.localizedDescription; showWindow?()
            }
            target = nil; onChange?()
        }
    }

    func cancel() {
        if phase == .recording {
            discardResult = true; finish()
        } else if phase == .processing {
            discardResult = true; status = "Discarding this dictation…"
        }
    }
    private func completeCancellation() {
        target = nil; insertionIssue = nil; phase = .ready; status = "Dictation discarded."; onChange?()
    }
    private func handleInsertion(_ outcome: InsertionOutcome, application: String) {
        switch outcome {
        case .inserted: status = "Inserted in \(application)."
        case .pasteSent: status = "Paste sent to \(application). The text is also on your clipboard."
        case .failed(let issue): status = issue.message; showWindow?()
        }
        refreshPermissions()
    }
    func insertLatest() {
        guard phase == .ready, !transcript.isEmpty else { return }
        let capture = TextInsertion.capture(origin:.window)
        guard case .target(let destination) = capture else {
            if case .failure(let issue) = capture {
                TextInsertion.copy(transcript); status = issue.message; refreshPermissions()
                if issue == .accessibilityMissing { grantInsertion() }
            }
            return
        }
        let text = transcript
        phase = .inserting; status = "Inserting text…"; onChange?()
        Task {
            let outcome = await TextInsertion.insert(text,into:destination)
            handleInsertion(outcome,application:destination.application.localizedName ?? "your app")
            phase = .ready; onChange?()
        }
    }
    func copyTranscript() {
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        status = "Transcript copied. Paste it wherever you need it."
    }
    func importAudio() {
        guard phase == .ready else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an audio clip up to two minutes long. It stays on this Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        lastTranscriptionSeconds = nil
        phase = .processing; status = "Transcribing your audio clip…"; discardResult = false; onChange?()
        Task {
            do {
                let transcriptionStart = Date()
                let text = try await speech.transcribe(file: url)
                lastTranscriptionSeconds = Date().timeIntervalSince(transcriptionStart)
                if discardResult { completeCancellation(); return }
                transcript = text
                status = text.isEmpty ? "No words were recognized in this clip." : "Your transcript is ready to copy."
            } catch { status = error.localizedDescription }
            phase = .ready; onChange?()
        }
    }
}
