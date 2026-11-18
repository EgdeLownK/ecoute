import SwiftUI

/// Onglet « Enregistrements » : une ligne par enregistrement, puis la page de lecture du document final.
struct LibraryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var nav: AppNav
    @State private var filter: String?
    @State private var search = ""

    var body: some View {
        NavigationStack(path: $nav.libraryPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button { filter = nil } label: {
                                Text("Tous").font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(filter == nil ? Color.primary.opacity(0.12) : Color(.secondarySystemGroupedBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            ForEach(store.cats) { c in
                                Button { filter = c.id } label: { CategoryChip(cat: c, selected: filter == c.id) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    let list = items
                    if list.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "waveform").font(.largeTitle).foregroundStyle(.secondary)
                            Text(search.isEmpty ? "Aucun enregistrement\(filter.map { " dans " + store.cat($0).name } ?? "")." : "Aucun enregistrement ne correspond à ta recherche.")
                                .font(.headline)
                            if search.isEmpty {
                                Text("Lance une écoute depuis l'onglet Écoute : l'enregistrement apparaîtra ici une fois terminé.")
                                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 50).padding(.horizontal, 20)
                    } else {
                        ForEach(list) { d in
                            NavigationLink(value: d.id) { RecordRow(doc: d, showCategory: filter == nil) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, engine.isLive ? 90 : 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Enregistrements")
            .searchable(text: $search, prompt: "Rechercher")
            .navigationDestination(for: UUID.self) { id in DocView(docId: id) }
        }
        .safeAreaInset(edge: .bottom) {
            if engine.isLive { LiveBar() }
        }
    }

    private var items: [Doc] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        return store.docs(in: filter).filter { d in
            q.isEmpty || ([d.displayTitle, d.source] + d.parts.map(\.shownTitle)).joined(separator: " ").lowercased().contains(q)
        }
    }
}

struct RecordRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var settings: Settings
    let doc: Doc
    let showCategory: Bool

    var body: some View {
        let c = store.cat(doc.categoryId)
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: c.colorHex)).frame(width: 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(doc.displayTitle).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                Text(meta(c)).font(.caption).foregroundStyle(.secondary)
                if !doc.source.isEmpty { Text(doc.source).font(.footnote).italic().foregroundStyle(.secondary) }
                if !doc.snippet.isEmpty { Text(doc.snippet).font(.subheadline).lineLimit(2).foregroundStyle(.primary) }
                if let s = state { s }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 4)
        }
        .padding(.vertical, 14).padding(.trailing, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }

    private func meta(_ c: Category) -> String {
        var parts: [String] = []
        if showCategory { parts.append(c.name) }
        parts.append(Fmt.relative(doc.updated))
        if doc.duration > 60 { parts.append(Fmt.duration(doc.duration)) }
        parts.append("\(doc.parts.count) partie\(doc.parts.count > 1 ? "s" : "")")
        return parts.joined(separator: " · ")
    }

    private var state: AnyView? {
        if engine.docId == doc.id {
            return AnyView(Label(engine.state == .finalizing ? "Finalisation…" : "En cours d'écoute", systemImage: "record.circle").font(.caption.weight(.semibold)).foregroundStyle(.red))
        }
        if doc.parts.contains(where: { $0.status == .summarizing }) {
            return AnyView(HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Rédaction…") }.font(.caption.weight(.semibold)).foregroundStyle(.secondary))
        }
        let missing = doc.parts.filter { $0.writeup == nil && $0.hasContent }.count
        if missing > 0 && settings.hasKey {
            return AnyView(Text("\(missing) partie\(missing > 1 ? "s" : "") à rédiger").font(.caption.weight(.semibold)).foregroundStyle(.orange))
        }
        return nil
    }
}

/// Mini-barre « écoute en cours » visible depuis Enregistrements.
struct LiveBar: View {
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: AppNav

    var body: some View {
        HStack(spacing: 12) {
            PulseDot()
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.doc?.source.nonEmpty ?? engine.doc.map { store.cat($0.categoryId).name } ?? "Écoute").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let s = engine.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in Text(Fmt.clock(ctx.date.timeIntervalSince(s))).font(.subheadline.monospacedDigit().weight(.semibold)) }
            }
            Button { Task { await engine.stop() } } label: {
                Image(systemName: "stop.fill").font(.footnote).foregroundStyle(.white).frame(width: 38, height: 38).background(Color.red, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.red.opacity(0.35)))
        .padding(.horizontal, 12).padding(.bottom, 6)
        .onTapGesture { nav.tab = .listen }
    }

    private var sub: String {
        guard let d = engine.doc, let p = d.parts.last else { return "" }
        let done = d.parts.filter { $0.writeup != nil }.count
        return "Partie \(d.parts.count)\(p.label.isEmpty ? "" : " · " + p.label)\(done > 0 ? " · \(done) résumé\(done > 1 ? "s" : "") prêt\(done > 1 ? "s" : "")" : "")"
    }
}
