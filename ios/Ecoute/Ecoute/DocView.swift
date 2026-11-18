import SwiftUI
import UIKit

/// Page d'un enregistrement : le document final, à lire comme un article.
struct DocView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: AppNav
    @Environment(\.dismiss) private var dismiss
    let docId: UUID
    @State private var share: ShareItem?
    @State private var confirmDelete = false
    @State private var working: Set<UUID> = []

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
        let shown = visibleParts(doc, isLive: isLive)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(doc, c, isLive: isLive)
                    synthesis(doc)
                    toc(shown, proxy: proxy)
                    ForEach(shown, id: \.element.id) { item in
                        Divider()
                        partSection(doc, item.element, number: item.offset + 1)
                            .id(item.element.id)
                            .padding(.vertical, 24)
                    }
                    footer(doc, c, isLive: isLive)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { item in ShareSheet(items: item.items) }
        .confirmationDialog("Supprimer cet enregistrement ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer de l'app", role: .destructive) { store.removeDoc(doc.id); dismiss() }
            if let url = Files.folderURL(doc, cat: c) {
                Button("Supprimer aussi les fichiers", role: .destructive) {
                    try? FileManager.default.removeItem(at: url)
                    store.removeDoc(doc.id)
                    dismiss()
                }
            }
        } message: {
            Text("Les fichiers .md restent dans l'app Fichiers, sauf si tu choisis de les supprimer aussi.")
        }
    }

    private func visibleParts(_ doc: Doc, isLive: Bool) -> [(offset: Int, element: Part)] {
        let lastIndex = doc.parts.count - 1
        return Array(doc.parts.enumerated()).filter { item in
            item.element.hasContent && !(isLive && engine.isLive && item.offset == lastIndex)
        }
    }

    private func missingCount(_ doc: Doc) -> Int {
        doc.parts.filter { $0.writeup == nil && $0.hasContent && $0.status != .open && $0.status != .summarizing }.count
    }

    private func metaLine(_ doc: Doc) -> String {
        let n = doc.parts.count
        let dur = doc.duration > 60 ? " · " + Fmt.duration(doc.duration) : ""
        return "\(Fmt.long(doc.created))\(dur) · \(n) partie\(n > 1 ? "s" : "")"
    }

    @ViewBuilder
    private func header(_ doc: Doc, _ c: Category, isLive: Bool) -> some View {
        let missing = missingCount(doc)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(Color(hex: c.colorHex)).frame(width: 9, height: 9)
                Text("\(c.name) · \(doc.kind.label)").font(.footnote).foregroundStyle(.secondary)
            }
            Text(doc.displayTitle).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                if !doc.source.isEmpty { Text(doc.source).font(.subheadline.weight(.semibold)) }
                Text(metaLine(doc)).font(.subheadline).foregroundStyle(.secondary)
            }
            if isLive {
                Label(engine.state == .finalizing ? "Finalisation en cours…" : "Écoute en cours", systemImage: "record.circle")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.red)
            } else if missing > 0 && settings.hasKey {
                Button { Task { await engine.rewriteMissing(docId: doc.id) } } label: {
                    Label("\(missing) partie\(missing > 1 ? "s" : "") à rédiger — Rédiger maintenant", systemImage: "pencil")
                }
                .font(.footnote.weight(.semibold)).tint(.orange)
            }
            HStack(spacing: 10) {
                if isLive {
                    Button { nav.tab = .listen } label: { Label("Voir l'écoute", systemImage: "waveform") }
                        .buttonStyle(.borderedProminent).tint(.red)
                } else {
                    Button { continueListening(doc) } label: { Label("Continuer l'écoute", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                }
                Button { exportFiles(doc) } label: { Label("Exporter", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private func synthesis(_ doc: Doc) -> some View {
        if let s = doc.synthesis, !(s.synthese.isEmpty && s.aRetenir.isEmpty) {
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Synthèse").font(.title2.weight(.bold))
                ForEach(Array(s.synthese.enumerated()), id: \.offset) { _, p in
                    Text(p).lineSpacing(4)
                }
                if !s.aRetenir.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "À retenir")
                        ForEach(Array(s.aRetenir.enumerated()), id: \.offset) { _, x in
                            HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•"); Text(x) }
                        }
                    }
                    .card()
                }
            }
            .padding(.vertical, 22)
        }
    }

    @ViewBuilder
    private func toc(_ shown: [(offset: Int, element: Part)], proxy: ScrollViewProxy) -> some View {
        if shown.count > 1 {
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text("Sommaire").font(.title2.weight(.bold)).padding(.bottom, 8)
                ForEach(shown, id: \.element.id) { item in
                    Button {
                        withAnimation { proxy.scrollTo(item.element.id, anchor: .top) }
                    } label: {
                        HStack(spacing: 12) {
                            NumberBadge(n: item.offset + 1)
                            Text(item.element.shownTitle).multilineTextAlignment(.leading)
                            Spacer()
                            Text(Fmt.time(item.element.start)).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 22)
        }
    }

    @ViewBuilder
    private func footer(_ doc: Doc, _ c: Category, isLive: Bool) -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 14) {
            Text(doc.folder.isEmpty ? "Stocké dans l'app." : "Fichiers : Fichiers › Sur mon iPhone › Écoute › \(c.folder) › \(doc.folder)")
                .font(.footnote).foregroundStyle(.secondary)
            if !isLive {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Supprimer l'enregistrement", systemImage: "trash") }
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 22)
    }

    @ViewBuilder
    private func partSection(_ doc: Doc, _ p: Part, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PARTIE \(number) · \(Fmt.time(p.start)) – \(Fmt.time(p.end ?? p.start))").font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.5)
            Text(p.shownTitle).font(.title2.weight(.bold))
            if let w = p.writeup {
                WriteupView(writeup: w, part: p)
            } else if p.status == .summarizing || working.contains(p.id) {
                HStack(spacing: 8) { ProgressView(); Text("Rédaction du résumé…").foregroundStyle(.secondary) }
            } else {
                Text(settings.hasKey ? "Résumé non rédigé\(p.error.map { " (\($0))" } ?? "")." : "Pas de résumé : ajoute une clé API Anthropic dans les réglages pour le rédiger.")
                    .foregroundStyle(.secondary)
            }
            let transcript = p.clean.isEmpty ? p.segments : p.clean
            if !p.notes.isEmpty || !transcript.isEmpty {
                DisclosureGroup("Notes et transcription") {
                    VStack(alignment: .leading, spacing: 10) {
                        if !p.notes.isEmpty {
                            SectionLabel(text: "Notes prises pendant l'écoute").padding(.top, 8)
                            ForEach(Array(p.notes.enumerated()), id: \.offset) { _, n in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(Fmt.time(n.t)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    Text(n.text).font(.subheadline)
                                }
                            }
                        }
                        if !transcript.isEmpty {
                            SectionLabel(text: "Transcription").padding(.top, 8)
                            ForEach(Array(transcript.enumerated()), id: \.offset) { _, s in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(Fmt.time(s.t)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    Text(s.text).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .font(.subheadline)
            }
            HStack(spacing: 20) {
                Button("Copier") { UIPasteboard.general.string = markdown(doc, p); engine.show("Partie copiée.") }
                Button("Partager") { share = ShareItem(items: [markdown(doc, p)]) }
                if settings.hasKey && p.status != .open && p.status != .summarizing && !(engine.docId == doc.id && engine.isLive) {
                    Button(p.writeup == nil ? "Rédiger" : "Rédiger à nouveau") {
                        working.insert(p.id)
                        Task { await engine.rewrite(docId: doc.id, partId: p.id); working.remove(p.id) }
                    }
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.top, 4)
        }
    }

    private func markdown(_ doc: Doc, _ p: Part) -> String {
        guard let i = doc.parts.firstIndex(where: { $0.id == p.id }) else { return "" }
        return Files.partMD(doc, i, cat: store.cat(doc.categoryId), includeTranscript: settings.includeTranscript)
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
