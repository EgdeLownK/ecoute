import SwiftUI

/// Onglet « Bibliothèque » : les catégories en rayons, les écoutes récentes et les idées à retenir.
struct LibraryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: Engine
    @EnvironmentObject var nav: AppNav
    @State private var search = ""

    var body: some View {
        NavigationStack(path: $nav.libraryPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if store.docs.isEmpty {
                        EmptyLibrary()
                    } else if !query.isEmpty {
                        SearchResults(query: query)
                    } else {
                        shelves
                        recent
                        ideas
                    }
                }
                .padding(16)
                .padding(.bottom, engine.isLive ? 90 : 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Bibliothèque")
            .searchable(text: $search, prompt: "Titres, idées, leçons…")
            .navigationDestination(for: LibRoute.self) { route in
                switch route {
                case .category(let id): CategoryShelfView(catId: id)
                case .doc(let id): DocView(docId: id)
                case .part(let d, let p): PartView(docId: d, partId: p)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if engine.isLive { LiveBar() }
        }
    }

    private var query: String { search.trimmingCharacters(in: .whitespaces).lowercased() }

    private var shelves: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Catégories").font(.title3.weight(.bold))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(store.cats) { c in
                    NavigationLink(value: LibRoute.category(c.id)) {
                        CategoryTile(cat: c, count: store.docs(in: c.id).count)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Récents").font(.title3.weight(.bold))
            ForEach(Array(store.docs(in: nil).prefix(5))) { d in
                NavigationLink(value: LibRoute.doc(d.id)) { DocCard(doc: d, showCategory: true) }
                    .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var ideas: some View {
        let items = recentIdeas
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Idées à retenir").font(.title3.weight(.bold))
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    NavigationLink(value: LibRoute.doc(item.doc.id)) { IdeaCard(text: item.text, doc: item.doc) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// Deux idées par écoute, pour les quatre écoutes les plus récentes.
    private var recentIdeas: [(text: String, doc: Doc)] {
        store.docs(in: nil).prefix(4).flatMap { d in d.highlights.prefix(2).map { (text: $0, doc: d) } }
    }
}

// MARK: - Rayon d'une catégorie

struct CategoryShelfView: View {
    @EnvironmentObject var store: Store
    let catId: String

    var body: some View {
        let c = store.cat(catId)
        let list = store.docs(in: catId)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if list.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray").font(.largeTitle).foregroundStyle(.tertiary)
                        Text("Aucune écoute").font(.headline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 80)
                } else {
                    ForEach(list) { d in
                        NavigationLink(value: LibRoute.doc(d.id)) { DocCard(doc: d, showCategory: false) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(c.name)
    }
}

// MARK: - Recherche dans tout le contenu

struct SearchResults: View {
    @EnvironmentObject var store: Store
    let query: String

    var body: some View {
        let docs = store.docs(in: nil).filter { $0.searchText.contains(query) }
        let ideas: [(text: String, doc: Doc)] = store.docs(in: nil).flatMap { d in
            (d.highlights + d.lessons.map(\.lecon)).filter { $0.lowercased().contains(query) }.map { (text: $0, doc: d) }
        }
        VStack(alignment: .leading, spacing: 24) {
            if docs.isEmpty && ideas.isEmpty {
                Text("Aucun résultat").font(.headline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 60)
            }
            if !docs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Écoutes").font(.title3.weight(.bold))
                    ForEach(docs) { d in
                        NavigationLink(value: LibRoute.doc(d.id)) { DocCard(doc: d, showCategory: true) }.buttonStyle(.plain)
                    }
                }
            }
            if !ideas.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Idées").font(.title3.weight(.bold))
                    ForEach(Array(ideas.prefix(20).enumerated()), id: \.offset) { _, item in
                        NavigationLink(value: LibRoute.doc(item.doc.id)) { IdeaCard(text: item.text, doc: item.doc) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct EmptyLibrary: View {
    @EnvironmentObject var nav: AppNav
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical").font(.system(size: 44)).foregroundStyle(.tertiary)
            Text("Ta bibliothèque est vide").font(.headline)
            Button { nav.tab = .listen } label: { Label("Lancer une écoute", systemImage: "mic.fill") }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 90)
    }
}

// MARK: - Cartes

struct CategoryTile: View {
    let cat: Category
    let count: Int
    var body: some View {
        let color = Color(hex: cat.colorHex)
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: cat.kind.icon)
                .font(.headline).foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Spacer(minLength: 0)
            Text(cat.name).font(.headline).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
            Text(count == 0 ? "Vide" : "\(count) écoute\(count > 1 ? "s" : "")").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(count == 0 ? 0.6 : 1)
    }
}

struct DocCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: Engine
    let doc: Doc
    let showCategory: Bool

    var body: some View {
        let c = store.cat(doc.categoryId)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if showCategory {
                    Text(c.name.uppercased()).font(.caption2.weight(.bold)).kerning(0.5).foregroundStyle(Color(hex: c.colorHex))
                }
                Text(doc.displayTitle).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                if !doc.snippet.isEmpty {
                    Text(doc.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                }
                Text(meta).font(.caption).foregroundStyle(.tertiary)
                if engine.docId == doc.id {
                    Label(engine.state == .finalizing ? "Finalisation…" : "En cours", systemImage: "record.circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 4)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
    }

    private var meta: String {
        var bits = [Fmt.relative(doc.updated)]
        if doc.duration > 60 { bits.append(Fmt.duration(doc.duration)) }
        bits.append("\(doc.parts.count) partie\(doc.parts.count > 1 ? "s" : "")")
        return bits.joined(separator: " · ")
    }
}

struct IdeaCard: View {
    @EnvironmentObject var store: Store
    let text: String
    let doc: Doc
    var body: some View {
        let color = Color(hex: store.cat(doc.categoryId).colorHex)
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.body).foregroundStyle(.primary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Text(doc.displayTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Mini-barre « écoute en cours » visible depuis la bibliothèque.
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
            .accessibilityLabel("Arrêter l'écoute")
        }
        .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.red.opacity(0.35)))
        .padding(.horizontal, 12).padding(.bottom, 6)
        .onTapGesture { nav.tab = .listen }
    }

    private var sub: String {
        guard let d = engine.doc, let p = d.parts.last else { return "" }
        return "Partie \(d.parts.count)\(p.label.isEmpty ? "" : " · " + p.label)"
    }
}
