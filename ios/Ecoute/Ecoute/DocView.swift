import SwiftUI
import UIKit

/// Les onglets d'un enregistrement.
enum DocTab: String, CaseIterable, Identifiable {
    case resume, retenir, lecons, decisions, citations
    var id: String { rawValue }
    var label: String {
        switch self {
        case .resume: return "Résumé"
        case .retenir: return "À retenir"
        case .lecons: return "Leçons"
        case .decisions: return "Décisions"
        case .citations: return "Citations"
        }
    }
}

/// Page d'un enregistrement : un résumé court, puis l'information rangée par onglets. Chaque partie a sa propre page.
struct DocView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: AppNav
    @Environment(\.dismiss) private var dismiss
    let docId: UUID
    @State private var tab: DocTab = .resume
    @State private var share: ShareItem?
    @State private var confirmDelete = false

    var body: some View {
        if let doc = store.doc(docId) {
            content(doc)
        } else {
            Text("Cet enregistrement n'existe plus.").foregroundStyle(.secondary)
        }
    }

    private func content(_ doc: Doc) -> some View {
        let c = store.cat(doc.categoryId)
        let isLive = engine.docId == doc.id
        let tabs = availableTabs(doc)
        let current = tabs.contains(tab) ? tab : .resume
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DocHeader(doc: doc, cat: c, isLive: isLive)
                if tabs.count > 1 {
                    Picker("Rubrique", selection: Binding(get: { current }, set: { tab = $0 })) {
                        ForEach(tabs) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                switch current {
                case .resume: ResumeTab(doc: doc, isLive: isLive)
                case .retenir: RetenirTab(doc: doc)
                case .lecons: LeconsTab(doc: doc)
                case .decisions: DecisionsTab(doc: doc)
                case .citations: CitationsTab(doc: doc)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !isLive {
                        Button { continueListening(doc) } label: { Label("Continuer l'écoute", systemImage: "play.fill") }
                    }
                    Button { exportFiles(doc) } label: { Label("Exporter les fichiers", systemImage: "square.and.arrow.up") }
                    if !isLive {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Supprimer", systemImage: "trash") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $share) { item in ShareSheet(items: item.items) }
        .confirmationDialog("Supprimer cet enregistrement ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let url = Files.folderURL(doc, cat: c) { try? FileManager.default.removeItem(at: url) }
                store.removeDoc(doc.id)
                dismiss()
            }
        }
    }

    private func availableTabs(_ doc: Doc) -> [DocTab] {
        var t: [DocTab] = [.resume]
        if doc.hasKeyPoints { t.append(.retenir) }
        if doc.kind == .reunion {
            if !doc.allDecisions.isEmpty || !doc.allActions.isEmpty { t.append(.decisions) }
        } else if !doc.lessons.isEmpty || !doc.furtherQuestions.isEmpty {
            t.append(.lecons)
        }
        if !doc.allQuotes.isEmpty || !doc.allRefs.isEmpty || !doc.allDefinitions.isEmpty { t.append(.citations) }
        return t
    }

    private func exportFiles(_ doc: Doc) {
        guard var d = store.doc(doc.id) else { return }
        let urls = Files.write(&d, cat: store.cat(d.categoryId), includeTranscript: settings.includeTranscript)
        engine.writeFiles(d.id)
        share = ShareItem(items: urls)
    }

    private func continueListening(_ doc: Doc) {
        settings.curCat = doc.categoryId
        nav.tab = .listen
        Task { await engine.start(categoryId: doc.categoryId, continueId: doc.id, source: doc.source) }
    }
}

// MARK: - En-tête

struct DocHeader: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var settings: Settings
    let doc: Doc
    let cat: Category
    let isLive: Bool

    var body: some View {
        let missing = doc.parts.filter { $0.writeup == nil && $0.hasContent && $0.status != .open && $0.status != .summarizing }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: cat.kind.icon).font(.caption)
                Text(cat.name).font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Color(hex: cat.colorHex))
            Text(doc.displayTitle).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            if !doc.source.isEmpty { Text(doc.source).font(.subheadline.weight(.semibold)) }
            Text(meta).font(.subheadline).foregroundStyle(.secondary)
            if isLive {
                Label(engine.state == .finalizing ? "Finalisation…" : "Écoute en cours", systemImage: "record.circle")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.red)
            } else if missing > 0 && settings.hasKey {
                Button { Task { await engine.rewriteMissing(docId: doc.id) } } label: {
                    Label("Rédiger \(missing) partie\(missing > 1 ? "s" : "") manquante\(missing > 1 ? "s" : "")", systemImage: "pencil")
                }
                .buttonStyle(.bordered).tint(.orange).controlSize(.small)
            }
        }
    }

    private var meta: String {
        let n = doc.parts.count
        let dur = doc.duration > 60 ? " · " + Fmt.duration(doc.duration) : ""
        return "\(Fmt.long(doc.created))\(dur) · \(n) partie\(n > 1 ? "s" : "")"
    }
}

// MARK: - Onglets

struct ResumeTab: View {
    @EnvironmentObject var engine: Engine
    let doc: Doc
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let s = doc.synthesis, !s.synthese.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(s.synthese.enumerated()), id: \.offset) { _, p in
                        Text(p).font(.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !parts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Parties").font(.title3.weight(.bold))
                    ForEach(parts, id: \.element.id) { item in
                        NavigationLink(value: LibRoute.part(doc.id, item.element.id)) {
                            PartRow(part: item.element, number: item.offset + 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Les parties qui ont du contenu (sans la partie en cours d'écoute).
    private var parts: [(offset: Int, element: Part)] {
        let last = doc.parts.count - 1
        return Array(doc.parts.enumerated()).filter { item in
            item.element.hasContent && !(isLive && engine.isLive && item.offset == last)
        }
    }
}

struct PartRow: View {
    let part: Part
    let number: Int
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NumberBadge(n: number)
            VStack(alignment: .leading, spacing: 4) {
                Text(part.shownTitle).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                if part.status == .summarizing {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Rédaction…") }
                        .font(.footnote).foregroundStyle(.secondary)
                } else if let c = part.writeup?.chapeau.nonEmpty {
                    Text(c).font(.subheadline).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
                } else if part.writeup == nil {
                    Text("Résumé non rédigé").font(.footnote).foregroundStyle(.orange)
                }
                Text("\(Fmt.time(part.start)) – \(Fmt.time(part.end ?? part.start))").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 6)
        }
        .card()
        .contentShape(Rectangle())
    }
}

struct RetenirTab: View {
    let doc: Doc
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let g = doc.synthesis?.aRetenir, !g.isEmpty {
                KeyPointsCard(title: "L'essentiel", items: g)
            }
            ForEach(Array(doc.parts.enumerated()), id: \.element.id) { item in
                if let pts = item.element.writeup?.aRetenir, !pts.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink(value: LibRoute.part(doc.id, item.element.id)) {
                            HStack(spacing: 10) {
                                NumberBadge(n: item.offset + 1)
                                Text(item.element.shownTitle).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        BulletList(items: pts)
                    }
                }
            }
        }
    }
}

struct LeconsTab: View {
    let doc: Doc
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(doc.lessons.enumerated()), id: \.offset) { k, l in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(k + 1)").font(.headline.monospacedDigit()).foregroundStyle(Color.accentColor)
                        Text(l.lecon).font(.headline).fixedSize(horizontal: false, vertical: true)
                    }
                    if !l.application.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "arrow.turn.down.right").font(.footnote).foregroundStyle(.secondary)
                            Text(l.application).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .card()
            }
            if !doc.furtherQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pour aller plus loin").font(.title3.weight(.bold))
                    BulletList(items: doc.furtherQuestions)
                }
                .padding(.top, 8)
            }
        }
    }
}

struct DecisionsTab: View {
    let doc: Doc
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !doc.allDecisions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Décisions").font(.title3.weight(.bold))
                    BulletList(items: doc.allDecisions)
                }
            }
            if !doc.allActions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Actions").font(.title3.weight(.bold))
                    ForEach(Array(doc.allActions.enumerated()), id: \.offset) { _, a in ActionRow(action: a) }
                }
            }
        }
    }
}

struct CitationsTab: View {
    let doc: Doc
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            if !doc.allQuotes.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Citations").font(.title3.weight(.bold))
                    ForEach(Array(doc.allQuotes.enumerated()), id: \.offset) { _, q in QuoteRow(quote: q) }
                }
            }
            if !doc.allRefs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Références").font(.title3.weight(.bold))
                    ForEach(Array(doc.allRefs.enumerated()), id: \.offset) { _, r in ReferenceRow(ref: r) }
                }
            }
            if !doc.allDefinitions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Glossaire").font(.title3.weight(.bold))
                    ForEach(Array(doc.allDefinitions.enumerated()), id: \.offset) { _, d in DefinitionRow(def: d) }
                }
            }
        }
    }
}

// MARK: - Page d'une partie

struct PartView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var settings: Settings
    let docId: UUID
    let partId: UUID
    @State private var share: ShareItem?
    @State private var working = false

    var body: some View {
        if let doc = store.doc(docId), let i = doc.parts.firstIndex(where: { $0.id == partId }) {
            content(doc, i)
        } else {
            Text("Cette partie n'existe plus.").foregroundStyle(.secondary)
        }
    }

    private func content(_ doc: Doc, _ i: Int) -> some View {
        let p = doc.parts[i]
        let canRewrite = settings.hasKey && p.status != .open && p.status != .summarizing && !(engine.docId == doc.id && engine.isLive)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("PARTIE \(i + 1) · \(Fmt.time(p.start)) – \(Fmt.time(p.end ?? p.start))")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.5)
                Text(p.shownTitle).font(.title.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                if let w = p.writeup {
                    WriteupView(writeup: w, part: p)
                } else if p.status == .summarizing || working {
                    HStack(spacing: 8) { ProgressView(); Text("Rédaction…").foregroundStyle(.secondary) }
                } else {
                    Text(settings.hasKey ? "Résumé non rédigé." : "Ajoute ta clé API dans les réglages pour rédiger le résumé.")
                        .foregroundStyle(.secondary)
                    if canRewrite {
                        Button { rewrite(doc, p) } label: { Label("Rédiger", systemImage: "pencil") }.buttonStyle(.borderedProminent)
                    }
                }
                SourceNotes(part: p).padding(.top, 8)
                PartPager(doc: doc, index: i).padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { UIPasteboard.general.string = markdown(doc, i); engine.show("Partie copiée.") } label: { Label("Copier", systemImage: "doc.on.doc") }
                    Button { share = ShareItem(items: [markdown(doc, i)]) } label: { Label("Partager", systemImage: "square.and.arrow.up") }
                    if canRewrite && p.writeup != nil {
                        Button { rewrite(doc, p) } label: { Label("Rédiger à nouveau", systemImage: "arrow.clockwise") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $share) { item in ShareSheet(items: item.items) }
    }

    private func rewrite(_ doc: Doc, _ p: Part) {
        working = true
        Task { await engine.rewrite(docId: doc.id, partId: p.id); working = false }
    }

    private func markdown(_ doc: Doc, _ i: Int) -> String {
        Files.partMD(doc, i, cat: store.cat(doc.categoryId), includeTranscript: settings.includeTranscript)
    }
}

/// Notes prises en direct et transcription, repliées par défaut.
struct SourceNotes: View {
    let part: Part
    var body: some View {
        let transcript = part.clean.isEmpty ? part.segments : part.clean
        if !part.notes.isEmpty || !transcript.isEmpty {
            DisclosureGroup("Notes et transcription") {
                VStack(alignment: .leading, spacing: 10) {
                    if !part.notes.isEmpty {
                        SectionLabel(text: "Notes").padding(.top, 8)
                        ForEach(Array(part.notes.enumerated()), id: \.offset) { _, n in TimedLine(item: n, dim: false) }
                    }
                    if !transcript.isEmpty {
                        SectionLabel(text: "Transcription").padding(.top, 8)
                        ForEach(Array(transcript.enumerated()), id: \.offset) { _, s in TimedLine(item: s, dim: true) }
                    }
                }
            }
            .font(.subheadline)
            .tint(.secondary)
        }
    }
}

struct TimedLine: View {
    let item: TimedText
    let dim: Bool
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Fmt.time(item.t)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(item.text).font(.subheadline).foregroundStyle(dim ? Color.secondary : Color.primary)
        }
    }
}

/// Partie précédente / suivante.
struct PartPager: View {
    let doc: Doc
    let index: Int
    var body: some View {
        let prev = index > 0 ? doc.parts[index - 1] : nil
        let next = index + 1 < doc.parts.count && doc.parts[index + 1].status != .open ? doc.parts[index + 1] : nil
        HStack(spacing: 12) {
            if let prev {
                NavigationLink(value: LibRoute.part(doc.id, prev.id)) {
                    Label("Précédente", systemImage: "chevron.left").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if let next {
                NavigationLink(value: LibRoute.part(doc.id, next.id)) {
                    HStack { Text("Suivante"); Image(systemName: "chevron.right") }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
    }
}
