import Foundation
import SwiftUI

/// Le déroulé d'une écoute :
/// 1. la transcription d'Apple produit des phrases ;
/// 2. toutes les ~60 s, Claude en tire du texte propre, des notes détaillées, citations et références, et repère les changements de sujet ;
/// 3. à chaque fin de sujet, la partie est rédigée en compte rendu à partir de ses notes ;
/// 4. à l'arrêt, une synthèse de l'ensemble est rédigée, puis les fichiers sont écrits.
@MainActor
final class Engine: ObservableObject {
    enum State { case idle, preparing, listening, stopping, finalizing }

    @Published private(set) var state: State = .idle
    @Published private(set) var docId: UUID?          // enregistrement en cours ou en finalisation
    @Published private(set) var startedAt: Date?
    @Published var preparingText = ""
    @Published var lastProblem: String?
    @Published var banner: String?
    @Published var finishedDocId: UUID?               // pour ouvrir l'enregistrement terminé

    let store: Store
    let settings: Settings
    private let transcriber = Transcriber()
    private var buffer: [TimedText] = []
    private var busy = false
    private var tail: Task<Void, Never>?
    private var pending: [UUID: Task<Void, Never>] = [:]
    private var flushLoop: Task<Void, Never>?

    init(store: Store, settings: Settings) {
        self.store = store
        self.settings = settings
        transcriber.onFinal = { [weak self] text in self?.addSegment(text) }
        transcriber.onProblem = { [weak self] msg in self?.lastProblem = msg }
    }

    var isLive: Bool { state == .listening || state == .stopping }
    var doc: Doc? { docId.flatMap { store.doc($0) } }

    // MARK: Démarrer / arrêter

    func start(categoryId: String, continueId: UUID?, source: String) async {
        guard state == .idle else { return }
        state = .preparing
        preparingText = "Préparation de l'écoute…"
        lastProblem = nil
        guard await Transcriber.requestPermissions() else {
            show(TranscriberError.micDenied.localizedDescription); state = .idle; return
        }
        let now = Date()
        var createdNew = false
        let id: UUID
        if let cid = continueId, store.doc(cid) != nil {
            id = cid
        } else {
            let cat = store.cat(categoryId)
            let d = Doc(categoryId: cat.id, kind: cat.kind, source: source.trimmingCharacters(in: .whitespacesAndNewlines), created: now, updated: now)
            store.insertDoc(d)
            id = d.id
            createdNew = true
        }
        store.update(id) { $0.parts.append(Part(start: now)) }
        if let i = store.docs.firstIndex(where: { $0.id == id }), i > 0 { let d = store.docs.remove(at: i); store.docs.insert(d, at: 0) }
        docId = id
        buffer = []
        do {
            try await transcriber.start(localeId: settings.localeId) { [weak self] text in self?.preparingText = text }
        } catch {
            store.update(id) { d in if let last = d.parts.last, !last.hasContent { d.parts.removeLast() } }
            if createdNew { store.removeDoc(id) }
            docId = nil
            state = .idle
            show(error.localizedDescription)
            return
        }
        startedAt = Date()
        state = .listening
        flushLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.maybeFlush()
            }
        }
    }

    func stop() async {
        guard state == .listening, let id = docId else { return }
        state = .stopping
        flushLoop?.cancel()
        await transcriber.stop()                       // les derniers mots arrivent avant la suite
        guard let d = store.doc(id), let last = d.parts.last else { state = .idle; docId = nil; return }
        var after = tail
        if settings.hasKey && !buffer.isEmpty { after = enqueueChunk(id, take(), target: last.id) }
        if last.hasContent || after != nil { startClose(id, last.id, after: after) }
        else { store.update(id) { $0.parts.removeLast() } }
        let began = startedAt ?? Date()
        store.update(id) { $0.runs.append(Run(start: began, end: Date())) }
        state = .finalizing
        await after?.value
        while let t = pending.values.first { await t.value }
        guard let done = store.doc(id), !done.parts.isEmpty else {
            store.removeDoc(id); finish(nil); show("Aucune phrase reconnue pendant cette écoute."); return
        }
        if settings.hasKey { await synthesize(id) }
        writeFiles(id)
        finish(id)
    }

    private func finish(_ id: UUID?) {
        state = .idle
        docId = nil
        startedAt = nil
        finishedDocId = id
    }

    /// Bouton « Nouvelle partie » ou long silence.
    func newPart(reason: String = "Nouvelle partie") {
        guard state == .listening, let id = docId, let cur = store.doc(id)?.parts.last, cur.hasContent else { return }
        var after = tail
        if settings.hasKey && !buffer.isEmpty { after = enqueueChunk(id, take(), target: cur.id) }
        store.update(id) { $0.parts.append(Part(start: Date())) }
        startClose(id, cur.id, after: after)
        show("\(reason) : partie \((store.doc(id)?.parts.count) ?? 1) commencée.")
    }

    // MARK: Phrases reconnues

    private static let fillers = try! NSRegularExpression(pattern: "(^|\\s)(euh+|heu+|hum+|hmm+|mmh+|bah|ben|hein)(?=\\s|$|[,.!?])", options: [.caseInsensitive])

    private func clean(_ s: String) -> String {
        let padded = " " + s + " "
        let r = Engine.fillers.stringByReplacingMatches(in: padded, range: NSRange(padded.startIndex..., in: padded), withTemplate: " ")
        return r.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func addSegment(_ raw: String) {
        guard isLive, let id = docId, let cur = store.doc(id)?.parts.last else { return }
        let text = clean(raw)
        guard text.wordCount >= 2 else { return }
        if cur.segments.suffix(3).contains(where: { $0.text.lowercased() == text.lowercased() }) { return }
        let now = Date()
        if state == .listening, settings.gapMinutes > 0, let prev = cur.segments.last, cur.segments.count >= 2,
           now.timeIntervalSince(prev.t) > Double(settings.gapMinutes * 60) {
            newPart(reason: "Long silence")
        }
        let seg = TimedText(t: now, text: text)
        store.update(id) { d in d.parts[d.parts.count - 1].segments.append(seg) }
        buffer.append(seg)
        maybeFlush()
    }

    private func take() -> [TimedText] { let b = buffer; buffer = []; return b }

    private func maybeFlush() {
        guard state == .listening, settings.hasKey, !busy, let first = buffer.first, let id = docId else { return }
        let age = Date().timeIntervalSince(first.t)
        let words = buffer.reduce(0) { $0 + $1.text.wordCount }
        let period = Double(max(30, settings.chunkSeconds))
        if (age >= period && words >= 20) || words >= 320 || (age >= period * 2.5 && words >= 3) {
            enqueueChunk(id, take(), target: nil)
        }
    }

    // MARK: Étage 1 — notes en direct

    /// Les extraits sont traités un par un, dans l'ordre.
    @discardableResult
    private func enqueueChunk(_ id: UUID, _ segs: [TimedText], target: UUID?) -> Task<Void, Never> {
        busy = true
        let prev = tail
        let t = Task { [weak self] in
            await prev?.value
            guard let self else { return }
            await self.chunkNotes(id, segs, target: target)
            self.busy = false
            self.maybeFlush()
        }
        tail = t
        return t
    }

    private func chunkNotes(_ id: UUID, _ segs: [TimedText], target: UUID?) async {
        guard let first = segs.first, let last = segs.last, let d = store.doc(id) else { return }
        guard let part = target.flatMap({ tid in d.parts.first { $0.id == tid } }) ?? d.parts.last else { return }
        let text = segs.map(\.text).joined(separator: " ")
        let prompt = Prompts.chunk(doc: d, part: part, text: text, granularity: settings.granularity)
        var result: [String: Any]?
        var failure: Error?
        for attempt in 0..<2 where result == nil {
            do { result = try await Claude.call(key: settings.key, model: settings.modelNotes, prompt: prompt, maxTokens: 3000) }
            catch {
                failure = error
                if let ce = error as? ClaudeError, case .http(401, _) = ce { break }
                try? await Task.sleep(nanoseconds: UInt64(3 + attempt * 4) * 1_000_000_000)
            }
        }
        guard let r = result else {
            // Rien n'est perdu : le texte brut est gardé dans la partie.
            store.update(id) { d in
                if let i = d.parts.firstIndex(where: { $0.id == part.id }) { d.parts[i].clean.append(TimedText(t: first.t, text: text, raw: true)) }
            }
            lastProblem = "Prise de notes perturbée (\(failure?.localizedDescription ?? "erreur")) : le texte est conservé."
            return
        }
        lastProblem = nil
        let segments = (r["segments"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? [r]
        let total = max(1, segments.reduce(0) { $0 + jStr($1["texte_propre"]).count })
        var acc = 0
        var toClose: [UUID] = []
        let span = last.t.timeIntervalSince(first.t)
        store.update(id) { d in
            guard var pi = d.parts.firstIndex(where: { $0.id == part.id }) else { return }
            for s in segments {
                let t = first.t.addingTimeInterval(span * Double(acc) / Double(total))
                acc += jStr(s["texte_propre"]).count
                let sujet = jStr(s["sujet"])
                // Changement de sujet repéré par Claude : la partie en cours est close et rédigée.
                if (s["nouveau_sujet"] as? Bool) == true, target == nil, settings.topicAuto, d.parts[pi].status == .open,
                   d.parts[pi].notes.count >= 3, pi == d.parts.count - 1 {
                    let cut = max(t, d.parts[pi].start.addingTimeInterval(1))
                    var np = Part(start: cut)
                    np.label = sujet
                    np.segments = d.parts[pi].segments.filter { $0.t >= cut }
                    d.parts[pi].segments.removeAll { $0.t >= cut }
                    d.parts[pi].status = .summarizing
                    toClose.append(d.parts[pi].id)
                    d.parts.append(np)
                    pi = d.parts.count - 1
                }
                if !sujet.isEmpty && (d.parts[pi].label.isEmpty || d.parts[pi].notes.count < 3) { d.parts[pi].label = sujet }
                let clean = jStr(s["texte_propre"])
                if !clean.isEmpty { d.parts[pi].clean.append(TimedText(t: t, text: clean)) }
                for n in jStrs(s["notes"]) { d.parts[pi].notes.append(TimedText(t: t, text: n)) }
                for c in jObjs(s["citations"], "texte") { d.parts[pi].quotes.append(Quote(texte: jStr(c["texte"]), auteur: jStr(c["auteur"]))) }
                for f in jObjs(s["references"], "nom") {
                    let nom = jStr(f["nom"])
                    if !d.parts[pi].refs.contains(where: { $0.nom.lowercased() == nom.lowercased() }) {
                        d.parts[pi].refs.append(Reference(nom: nom, type: jStr(f["type"]), contexte: jStr(f["contexte"])))
                    }
                }
            }
        }
        for pid in toClose {
            startClose(id, pid, after: nil)
            if let label = store.doc(id)?.parts.last?.label, !label.isEmpty { show("Nouveau sujet : « \(label) »") }
        }
    }

    // MARK: Étage 2 — compte rendu d'une partie

    private func startClose(_ id: UUID, _ partId: UUID, after: Task<Void, Never>?) {
        store.update(id) { d in if let i = d.parts.firstIndex(where: { $0.id == partId }) { d.parts[i].status = .summarizing } }
        let t = Task { [weak self] in
            await after?.value
            await self?.writePart(id, partId)
            self?.pending[partId] = nil
        }
        pending[partId] = t
    }

    private func writePart(_ id: UUID, _ partId: UUID) async {
        store.update(id) { d in
            guard let i = d.parts.firstIndex(where: { $0.id == partId }) else { return }
            let p = d.parts[i]
            d.parts[i].end = [p.segments.last?.t, p.notes.last?.t, p.clean.last?.t].compactMap { $0 }.max() ?? p.end ?? p.start
            if p.clean.isEmpty { d.parts[i].clean = p.segments.map { TimedText(t: $0.t, text: $0.text, raw: true) } }
        }
        guard let d = store.doc(id), let p = d.parts.first(where: { $0.id == partId }) else { return }
        var writeup: Writeup?
        var error: String?
        if settings.hasKey, let job = Prompts.writeUp(doc: d, part: p) {
            do {
                let r = try await Claude.call(key: settings.key, model: settings.modelWrite, prompt: job.prompt, maxTokens: job.maxTokens)
                writeup = Prompts.parseWriteup(r, fallbackTitle: p.label)
            } catch let e {
                error = e.localizedDescription
                show("Compte rendu non rédigé (\(e.localizedDescription)) : les notes sont gardées, tu pourras le relancer.")
            }
        } else if !settings.hasKey {
            error = "pas de clé API"
        }
        store.update(id) { d in
            guard let i = d.parts.firstIndex(where: { $0.id == partId }) else { return }
            if let writeup { d.parts[i].writeup = writeup }
            d.parts[i].error = writeup == nil ? error : nil
            d.parts[i].status = d.parts[i].writeup == nil ? .failed : .done
            if d.parts[i].title.isEmpty || writeup != nil {
                d.parts[i].title = writeup?.titre.nonEmpty ?? d.parts[i].label.nonEmpty ?? String(d.parts[i].segments.first?.text.prefix(50) ?? "Partie")
            }
        }
        writeFiles(id)
    }

    /// « Rédiger à nouveau » depuis la page d'un enregistrement.
    func rewrite(docId id: UUID, partId: UUID) async {
        guard settings.hasKey else { show("Ajoute ta clé API Anthropic dans les réglages."); return }
        store.update(id) { d in if let i = d.parts.firstIndex(where: { $0.id == partId }) { d.parts[i].status = .summarizing } }
        await writePart(id, partId)
        if let d = store.doc(id), d.synthesis != nil || d.parts.filter({ $0.writeup != nil }).count > 1 {
            await synthesize(id)
            writeFiles(id)
        }
    }

    func rewriteMissing(docId id: UUID) async {
        guard let d = store.doc(id) else { return }
        for p in d.parts where p.writeup == nil && p.status != .open && p.status != .summarizing && p.hasContent {
            await rewrite(docId: id, partId: p.id)
        }
    }

    // MARK: Étage 3 — synthèse

    private func synthesize(_ id: UUID) async {
        guard let d = store.doc(id), let prompt = Prompts.synthesis(doc: d) else { return }
        do {
            let r = try await Claude.call(key: settings.key, model: settings.modelWrite, prompt: prompt, maxTokens: 3500)
            let s = Prompts.parseSynthesis(r)
            store.update(id) { d in
                d.synthesis = s
                if !s.titre.isEmpty { d.title = s.titre }
            }
        } catch {
            show("Synthèse non rédigée : \(error.localizedDescription)")
        }
    }

    // MARK: Fichiers et messages

    func writeFiles(_ id: UUID) {
        guard var d = store.doc(id) else { return }
        Files.write(&d, cat: store.cat(d.categoryId), includeTranscript: settings.includeTranscript)
        let folder = d.folder, names = d.parts.map(\.fileName)
        store.update(id) { doc in
            doc.folder = folder
            for i in doc.parts.indices where i < names.count && doc.parts[i].fileName == nil { doc.parts[i].fileName = names[i] }
        }
    }

    func show(_ text: String) {
        banner = text
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if self?.banner == text { self?.banner = nil }
        }
    }
}
