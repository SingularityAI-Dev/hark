import AVFoundation
import CoreAudio
import Speech

/// Live speech-to-text. One implementation today (Apple, on device); the protocol is the
/// seam for a whisper.cpp fallback on Macs without Apple's speech assets.
protocol Transcriber: AnyObject {
    func prepare(locale: Locale) async
    func start(
        locale: Locale, contextualStrings: [String], inputDeviceUID: String?,
        onLevel: @escaping @Sendable (Float) -> Void
    ) async throws
    func finish() async throws -> String
    func cancel() async
}

enum TranscriberError: LocalizedError {
    case noAudioFormat, converterUnavailable, notRunning

    var errorDescription: String? {
        switch self {
        case .noAudioFormat: "No speech model is available for this language."
        case .converterUnavailable: "The microphone format could not be converted."
        case .notRunning: "Recording was not running."
        }
    }
}

final class AppleTranscriber: Transcriber {
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<String, Error>?
    private var cachedFormat: (localeID: String, format: AVAudioFormat)?

    /// Maps a preferred locale onto one the on-device recogniser supports.
    static func resolve(_ locale: Locale) async -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        let wanted = locale.identifier(.bcp47)
        if let exact = supported.first(where: { $0.identifier(.bcp47) == wanted }) { return exact }
        if let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: locale) { return equivalent }
        return Locale(identifier: "en-US")
    }

    private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
    }

    private static func installAssetsIfNeeded(for transcriber: SpeechTranscriber) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    private func format(for locale: Locale, transcriber: SpeechTranscriber) async throws -> AVAudioFormat {
        let id = locale.identifier(.bcp47)
        if let cachedFormat, cachedFormat.localeID == id { return cachedFormat.format }
        try await Self.installAssetsIfNeeded(for: transcriber)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriberError.noAudioFormat
        }
        cachedFormat = (id, format)
        return format
    }

    /// Does the slow one-off work (asset check, format lookup) before the first dictation.
    func prepare(locale: Locale) async {
        let resolved = await Self.resolve(locale)
        _ = try? await format(for: resolved, transcriber: Self.makeTranscriber(resolved))
    }

    func start(
        locale: Locale, contextualStrings: [String], inputDeviceUID: String?,
        onLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        let resolved = await Self.resolve(locale)
        let transcriber = Self.makeTranscriber(resolved)
        let targetFormat = try await format(for: resolved, transcriber: transcriber)

        if let inputDeviceUID, let deviceID = AudioDevices.deviceID(forUID: inputDeviceUID) {
            try? engine.inputNode.auAudioUnit.setDeviceID(deviceID)
        }
        let micFormat = engine.inputNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: micFormat, to: targetFormat) else {
            throw TranscriberError.converterUnavailable
        }

        // The microphone starts before the analyser so the first words are buffered, not lost.
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            onLevel(Self.level(of: buffer))
            if let converted = Self.convert(buffer, with: converter, to: targetFormat) {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            continuation.finish()
            throw error
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualStrings
            try? await analyzer.setContext(context)
        }
        self.analyzer = analyzer
        self.input = continuation
        self.results = Task {
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
            }
            return text
        }
        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            await cancel()
            throw error
        }
    }

    func finish() async throws -> String {
        guard let analyzer, let results else { throw TranscriberError.notRunning }
        stopMicrophone()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        self.analyzer = nil
        self.results = nil
        return try await results.value
    }

    func cancel() async {
        stopMicrophone()
        results?.cancel()
        await analyzer?.cancelAndFinishNow()
        analyzer = nil
        results = nil
    }

    private func stopMicrophone() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        input?.finish()
        input = nil
    }

    /// Transcribes an audio file. Used by the command-line checks, not by live dictation.
    static func transcribe(file url: URL, locale: Locale) async throws -> String {
        let resolved = await resolve(locale)
        let transcriber = makeTranscriber(resolved)
        try await installAssetsIfNeeded(for: transcriber)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let results = Task {
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
            }
            return text
        }
        let file = try AVAudioFile(forReading: url)
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await results.value
    }

    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        return min(1, (sum / Float(buffer.frameLength)).squareRoot() * 12)
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }
}

enum AudioDevices {
    static func inputs() -> [(uid: String, name: String)] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices.map { ($0.uniqueID, $0.localizedName) }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var cfUID = uid as CFString
        let status = withUnsafeMutablePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), qualifier, &size, &deviceID)
        }
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }
}
