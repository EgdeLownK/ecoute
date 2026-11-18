import AVFoundation
import Speech

enum TranscriberError: LocalizedError {
    case micDenied, unsupportedLocale, noAudioFormat, noInput

    var errorDescription: String? {
        switch self {
        case .micDenied: return "Accès au micro refusé. Autorise-le dans Réglages › Apps › Écoute › Micro."
        case .unsupportedLocale: return "Cette langue n'est pas prise en charge par la transcription d'Apple sur cet iPhone."
        case .noAudioFormat: return "Format audio indisponible pour la transcription."
        case .noInput: return "Aucun micro disponible."
        }
    }
}

/// Écoute le micro et transcrit sur l'iPhone avec le moteur d'Apple (SpeechAnalyzer, iOS 26).
/// L'écoute continue écran verrouillé ou dans une autre app (mode audio en arrière-plan),
/// et la session audio est « mélangeable » : elle ne coupe pas le livre audio ou le podcast en cours de lecture.
@MainActor
final class Transcriber {
    var onFinal: ((String) -> Void)?
    var onProblem: ((String) -> Void)?
    private(set) var running = false

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var module: SpeechTranscriber?
    private var builder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    static func requestPermissions() async -> Bool {
        let mic = await AVAudioApplication.requestRecordPermission()
        // Demandée par précaution : selon la version d'iOS, la transcription peut aussi en avoir besoin.
        _ = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        return mic
    }

    /// Prépare la langue (téléchargement du modèle si besoin) puis démarre l'écoute.
    func start(localeId: String, onProgress: @escaping (String) -> Void) async throws {
        guard !running else { return }

        // 1. Session audio : enregistrement + lecture, sans interrompre les autres apps.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker])
        try session.setActive(true)
        // Micro de l'iPhone : évite de basculer la voiture ou le casque Bluetooth en mode « appel » (son dégradé).
        if let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) { try? session.setPreferredInput(mic) }

        // 2. Moteur de transcription pour la langue choisie.
        let wanted = Locale(identifier: localeId)
        let supported = await SpeechTranscriber.supportedLocales
        guard let locale = supported.first(where: { $0.identifier(.bcp47) == wanted.identifier(.bcp47) })
                ?? supported.first(where: { $0.language.languageCode == wanted.language.languageCode }) else {
            throw TranscriberError.unsupportedLocale
        }
        let module = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            onProgress("Téléchargement du modèle de langue…")
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw TranscriberError.noAudioFormat }
        let analyzer = SpeechAnalyzer(modules: [module])
        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        self.module = module
        self.analyzer = analyzer
        self.analyzerFormat = format
        self.builder = builder

        // 3. Résultats : seules les phrases définitives sont gardées (pas de flux provisoire).
        resultsTask = Task { @MainActor [weak self] in
            do {
                for try await result in module.results where result.isFinal {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { self?.onFinal?(text) }
                }
            } catch {
                self?.onProblem?("Transcription interrompue : \(error.localizedDescription)")
            }
        }
        try await analyzer.start(inputSequence: stream)

        // 4. Micro → moteur.
        try startEngine()
        running = true
        observe()
    }

    /// Arrête l'écoute en laissant le moteur rendre les derniers mots.
    func stop() async {
        guard running else { return }
        running = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        builder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil
        module = nil
        builder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startEngine() throws {
        guard let format = analyzerFormat, let builder = builder else { return }
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else { throw TranscriberError.noInput }
        input.removeTap(onBus: 0)
        Transcriber.installTap(on: input, from: inFormat, to: format, builder: builder)
        engine.prepare()
        try engine.start()
    }

    /// Le tap tourne sur le fil audio : il est créé hors de l'acteur principal.
    nonisolated private static func installTap(on input: AVAudioInputNode, from inFormat: AVAudioFormat, to outFormat: AVAudioFormat,
                                               builder: AsyncStream<AnalyzerInput>.Continuation) {
        let converter = AVAudioConverter(from: inFormat, to: outFormat)
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { buffer, _ in
            if let out = convert(buffer, with: converter, to: outFormat) {
                builder.yield(AnalyzerInput(buffer: out))
            }
        }
    }

    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter?, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }

    /// Appels, Siri, changement de sortie audio (voiture, casque) : on relance proprement.
    private func observe() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            let ended = AVAudioSession.InterruptionType(rawValue: raw) == .ended
            Task { @MainActor in
                guard let self, self.running else { return }
                if ended { self.restart() } else { self.onProblem?("Écoute interrompue par le système (appel, Siri…). Elle reprendra ensuite.") }
            }
        })
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restart() }
        })
    }

    private func restart() {
        guard running else { return }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(true)
        do { try startEngine() } catch { onProblem?("Micro indisponible : \(error.localizedDescription)") }
    }
}
