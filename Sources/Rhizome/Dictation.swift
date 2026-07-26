import AVFoundation
import Speech
import SwiftUI

/// On-device dictation for audio notes. Streams the microphone through iOS 26's `SpeechAnalyzer`
/// + `SpeechTranscriber` (Apple's on-device speech-to-text — no network), exposing a live transcript
/// that grows as you speak. Nothing is uploaded; the audio is never persisted, only its transcript.
@MainActor
@Observable
final class Dictation {
    enum Phase: Equatable { case idle, preparing, recording, transcribing, failed }

    private(set) var phase: Phase = .idle
    private(set) var finalized = ""          // segments the recognizer has committed to
    private(set) var draft = ""              // the in-progress (volatile) tail
    private(set) var errorText: String?
    private(set) var recordingStart: Date?   // for the elapsed-time readout in the sheet
    private(set) var localeName: String?     // the resolved recognition language, shown in the sheet

    /// The full transcript so far (committed segments plus the live tail).
    var text: String {
        let tail = draft.isEmpty ? "" : (finalized.isEmpty ? "" : " ") + draft
        return finalized + tail
    }

    var isBusy: Bool { phase == .preparing || phase == .transcribing }

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    enum DictationError: LocalizedError {
        case micDenied, speechDenied, noLocale, noFormat, noConverter
        var errorDescription: String? {
            switch self {
            case .micDenied: "Kein Mikrofon-Zugriff. In den Einstellungen erlauben."
            case .speechDenied: "Keine Erlaubnis für Spracherkennung. In den Einstellungen erlauben."
            case .noLocale: "Für deine Sprache ist keine On-Device-Transkription verfügbar."
            case .noFormat: "Audioformat für die Transkription nicht verfügbar."
            case .noConverter: "Audio konnte nicht aufbereitet werden."
            }
        }
    }

    // A non-Sendable converter + its target format, boxed so the realtime audio tap can use them
    // without tripping Swift 6 actor isolation (the tap runs off the main actor).
    private final class ConverterBox: @unchecked Sendable {
        let converter: AVAudioConverter
        let format: AVAudioFormat
        init(_ c: AVAudioConverter, _ f: AVAudioFormat) { converter = c; format = f }
    }

    /// Holds the source buffer + a one-shot "handed it over" flag for the converter input block,
    /// keeping the non-Sendable buffer out of that (@Sendable) closure's captures.
    private final class ConvertState: @unchecked Sendable {
        let source: AVAudioPCMBuffer
        var delivered = false
        init(_ source: AVAudioPCMBuffer) { self.source = source }
    }

    func start(preferredLocaleID: String? = nil) async {
        guard phase == .idle else { return }
        phase = .preparing
        errorText = nil
        finalized = ""; draft = ""
        localeName = nil
        do {
            try await authorize()

            guard let locale = await Self.resolveLocale(preferred: preferredLocaleID) else { throw DictationError.noLocale }
            localeName = Self.displayName(for: locale)
            let transcriber = SpeechTranscriber(locale: locale,
                                                transcriptionOptions: [],
                                                reportingOptions: [.volatileResults],
                                                attributeOptions: [])
            self.transcriber = transcriber
            try await ensureModel(for: transcriber, locale: locale)

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer

            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw DictationError.noFormat
            }

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.continuation = continuation

            // Fold recognizer results into the transcript as they arrive. Volatile results replace
            // the live tail; final ones get committed and the tail is cleared.
            resultsTask = Task { [weak self, transcriber] in
                do {
                    for try await result in transcriber.results {
                        guard let self else { return }
                        let piece = String(result.text.characters)
                        if result.isFinal {
                            self.finalized += (self.finalized.isEmpty ? "" : " ") + piece
                            self.draft = ""
                        } else {
                            self.draft = piece
                        }
                    }
                } catch {
                    self?.errorText = error.localizedDescription
                }
            }

            try await analyzer.start(inputSequence: stream)

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true)

            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
                throw DictationError.noConverter
            }
            let box = ConverterBox(converter, analyzerFormat)
            Self.installTap(on: input, format: inputFormat, box: box, into: continuation)
            engine.prepare()
            try engine.start()

            recordingStart = Date()
            phase = .recording
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed
            teardownAudio()
            await finishAnalyzer()
        }
    }

    /// Stop recording, flush the recognizer, and return the final transcript.
    func stop() async -> String {
        guard phase == .recording else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        phase = .transcribing
        teardownAudio()
        continuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
        await finishAnalyzer()
        recordingStart = nil
        phase = .idle
        return final
    }

    /// Abandon the recording, discarding whatever was transcribed.
    func cancel() async {
        teardownAudio()
        continuation?.finish()
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        await finishAnalyzer()
        finalized = ""; draft = ""
        recordingStart = nil
        phase = .idle
    }

    private func teardownAudio() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func finishAnalyzer() async {
        analyzer = nil
        transcriber = nil
        continuation = nil
        resultsTask = nil
    }

    // MARK: - Audio conversion (realtime thread)

    /// Install the mic tap. MUST be `nonisolated` so the tap closure doesn't inherit this class's
    /// @MainActor isolation — the tap fires on a realtime audio queue, and a main-actor-isolated
    /// closure would trip the Swift 6 executor check there (EXC_BREAKPOINT in swift_task_checkIsolated
    /// → dispatch_assert_queue on RealtimeMessenger.mServiceQueue). It captures only Sendable values
    /// (the boxed converter + the stream continuation) and calls the nonisolated `convert`.
    private nonisolated static func installTap(on input: AVAudioInputNode,
                                               format: AVAudioFormat,
                                               box: ConverterBox,
                                               into continuation: AsyncStream<AnalyzerInput>.Continuation) {
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let converted = convert(buffer, with: box) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    /// Resample/repackage a mic buffer into the analyzer's preferred format. Runs on the audio tap
    /// thread (`nonisolated`), so it touches only the boxed converter — no main-actor state.
    private nonisolated static func convert(_ buffer: AVAudioPCMBuffer, with box: ConverterBox) -> AVAudioPCMBuffer? {
        let ratio = box.format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard capacity > 0, let out = AVAudioPCMBuffer(pcmFormat: box.format, frameCapacity: capacity) else { return nil }
        // The converter's input block may be invoked more than once; hand the buffer over exactly
        // once. A reference box keeps that flag out of the (Sendable) closure's captured vars.
        let state = ConvertState(buffer)
        var err: NSError?
        box.converter.convert(to: out, error: &err) { _, status in
            if state.delivered { status.pointee = .noDataNow; return nil }
            state.delivered = true
            status.pointee = .haveData
            return state.source
        }
        if err != nil || out.frameLength == 0 { return nil }
        return out
    }

    // MARK: - Permissions & model assets

    private func authorize() async throws {
        guard await Self.requestMicrophone() else { throw DictationError.micDenied }
        guard await Self.requestSpeech() == .authorized else { throw DictationError.speechDenied }
    }

    // These privacy prompts invoke their completion handler on an arbitrary background queue. The
    // wrappers MUST be `nonisolated` so the closures don't inherit this class's @MainActor isolation
    // — otherwise the Swift 6 runtime asserts main-actor isolation when the callback fires off-main
    // and traps (EXC_BREAKPOINT in swift_task_checkIsolated → dispatch_assert_queue).
    private nonisolated static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    private nonisolated static func requestSpeech() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
    }

    /// Download + install the on-device model for this locale on first use (a one-time, ~cached step).
    private func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let want = locale.identifier(.bcp47)
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == want }) { return }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    /// Resolve the recognition locale. An explicit `preferred` BCP-47 id wins (the Settings choice);
    /// otherwise pick automatically by walking the user's *preferred languages* in order (so German
    /// is chosen even when the UI language is English), then the device language, then English.
    private static func resolveLocale(preferred: String?) async -> Locale? {
        let supported = await SpeechTranscriber.supportedLocales
        guard !supported.isEmpty else { return nil }

        if let preferred, let hit = supported.first(where: { $0.identifier(.bcp47) == preferred }) { return hit }

        var candidates = Locale.preferredLanguages.map(Locale.init(identifier:))
        candidates.append(Locale.current)
        for cand in candidates {
            if let hit = supported.first(where: { $0.identifier(.bcp47) == cand.identifier(.bcp47) }) { return hit }
            if let lang = cand.language.languageCode?.identifier,
               let hit = supported.first(where: { $0.language.languageCode?.identifier == lang }) { return hit }
        }
        return supported.first(where: { $0.identifier(.bcp47).hasPrefix("en") }) ?? supported.first
    }

    /// The languages the on-device transcriber supports, sorted by localized name — for the picker.
    nonisolated static func supportedLocales() async -> [Locale] {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.sorted { displayName(for: $0).localizedCompare(displayName(for: $1)) == .orderedAscending }
    }

    /// A human-readable language name for a locale, e.g. "Deutsch (Deutschland)".
    nonisolated static func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier(.bcp47))
            ?? locale.identifier(.bcp47)
    }
}

/// The recording overlay: starts dictating on appear, shows the live transcript and elapsed time,
/// and hands the finished text back via `onDone` (empty string ⇒ nothing to insert).
struct DictationSheet: View {
    var preferredLocaleID: String?
    var onDone: (String) -> Void
    @State private var dictation = Dictation()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 8)
                indicator
                transcriptArea
                Spacer(minLength: 8)
                controls
            }
            .padding()
            .navigationTitle("Audionotiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { Task { await dictation.cancel(); onDone(""); dismiss() } }
                }
            }
            .task { await dictation.start(preferredLocaleID: preferredLocaleID) }
            .interactiveDismissDisabled(dictation.phase == .recording)
        }
    }

    @ViewBuilder private var indicator: some View {
        switch dictation.phase {
        case .preparing:
            Label("Wird vorbereitet …", systemImage: "hourglass")
                .font(.rz(15)).foregroundStyle(.secondary)
        case .recording:
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    PulsingDot()
                    if let start = dictation.recordingStart {
                        TimelineView(.periodic(from: start, by: 0.5)) { ctx in
                            Text(Self.elapsed(from: start, to: ctx.date))
                                .font(.rzFixed(17, .medium)).monospacedDigit()
                        }
                    }
                }
                if let lang = dictation.localeName {
                    Text(lang).font(.rz(13)).foregroundStyle(.secondary)
                }
            }
        case .transcribing:
            Label("Wird transkribiert …", systemImage: "waveform")
                .font(.rz(15)).foregroundStyle(.secondary)
        case .failed:
            Label(dictation.errorText ?? "Fehler", systemImage: "exclamationmark.triangle")
                .font(.rz(15)).foregroundStyle(.orange).multilineTextAlignment(.center)
        case .idle:
            EmptyView()
        }
    }

    private var transcriptArea: some View {
        ScrollView {
            Text(dictation.text.isEmpty ? "Sprich jetzt …" : dictation.text)
                .font(.rz(18))
                .foregroundStyle(dictation.text.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 240)
    }

    @ViewBuilder private var controls: some View {
        switch dictation.phase {
        case .recording:
            Button {
                Task { let text = await dictation.stop(); onDone(text); dismiss() }
            } label: {
                Label("Stopp & einfügen", systemImage: "stop.circle.fill")
                    .font(.rz(17, .semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.rzAccent).controlSize(.large)
        case .failed:
            Button("Schließen") { onDone(""); dismiss() }
                .font(.rz(17, .semibold)).frame(maxWidth: .infinity)
                .buttonStyle(.bordered).controlSize(.large)
        default:
            Button { } label: {
                ProgressView().frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large).disabled(true)
        }
    }

    private static func elapsed(from start: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// A soft pulsing red dot that reads as "recording".
private struct PulsingDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 12, height: 12)
            .opacity(on ? 1 : 0.3)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
