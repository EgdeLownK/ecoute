import SwiftUI

/// Onglet « Écoute » : avant GO, le choix de la catégorie ; pendant l'écoute, uniquement le résumé qui se construit.
struct ListenView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var engine: Engine
    @State private var source = ""
    @State private var showSettings = false
    @State private var showCategories = false
    @State private var editingCat: Category?
    @State private var creatingCat = false
    @State private var deletingCat: Category?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch engine.state {
                    case .idle: idle
                    case .preparing: preparing
                    default: live
                    }
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Écoute")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Réglages")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showCategories) { CategoriesSheet() }
            .sheet(item: $editingCat) { c in CategoryEditor(original: c) }
            .sheet(isPresented: $creatingCat) { CategoryEditor(original: nil) }
            .confirmationDialog(deletingCat.map { "Supprimer « \($0.name) » ?" } ?? "",
                                isPresented: Binding(get: { deletingCat != nil }, set: { if !$0 { deletingCat = nil } }),
                                titleVisibility: .visible, presenting: deletingCat) { c in
                Button("Supprimer", role: .destructive) { deleteCategory(c) }
            } message: { c in
                let n = store.docs(in: c.id).count
                Text(n == 0 ? "La catégorie est vide." : "\(n) écoute\(n > 1 ? "s" : "") ser\(n > 1 ? "ont" : "a") retirée\(n > 1 ? "s" : "") de l'app.")
            }
        }
    }

    private var cat: Category { store.cat(settings.curCat) }

    // MARK: Avant GO

    @ViewBuilder private var idle: some View {
        categoryChips
        goButton
        sourceField
        if !settings.hasKey {
            Button { showSettings = true } label: { Label("Ajouter ta clé API", systemImage: "key.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).tint(.orange).controlSize(.large)
        }
        resumeSection
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.cats) { c in
                    Button { settings.curCat = c.id } label: { CategoryChip(cat: c, selected: c.id == cat.id) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { editingCat = c } label: { Label("Modifier", systemImage: "pencil") }
                            if store.cats.count > 1 {
                                Button(role: .destructive) { deletingCat = c } label: { Label("Supprimer", systemImage: "trash") }
                            }
                        }
                }
                Button { creatingCat = true } label: {
                    Image(systemName: "plus").font(.subheadline.weight(.bold))
                        .frame(width: 38, height: 38)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajouter une catégorie")
                Button { showCategories = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.subheadline.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Gérer les catégories")
            }
            .padding(.vertical, 2)
        }
    }

    private var goButton: some View {
        let color = Color(hex: cat.colorHex)
        return Button { go(continueId: nil) } label: {
            ZStack {
                Circle().stroke(color.opacity(0.25), lineWidth: 10).frame(width: 214, height: 214)
                Circle()
                    .fill(RadialGradient(colors: [color.opacity(0.75), color], center: .topLeading, startRadius: 10, endRadius: 220))
                    .frame(width: 190, height: 190)
                    .shadow(color: color.opacity(0.45), radius: 22, y: 10)
                Text("GO")
                    .font(.system(size: 58, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.02, green: 0.07, blue: 0.05))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lancer l'écoute dans \(cat.name)")
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var sourceField: some View {
        HStack(spacing: 10) {
            Image(systemName: cat.kind.icon).foregroundStyle(Color(hex: cat.colorHex))
            TextField("Titre (facultatif)", text: $source)
                .submitLabel(.done)
            if !source.isEmpty {
                Button { source = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Effacer le titre")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private var resumeSection: some View {
        let list = Array(store.docs(in: cat.id).prefix(3))
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Reprendre").font(.title3.weight(.bold)).padding(.top, 8)
                ForEach(list) { d in
                    Button { go(continueId: d.id) } label: { ResumeRow(doc: d, color: Color(hex: cat.colorHex)) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func go(continueId: UUID?) {
        let src = source
        Task {
            await engine.start(categoryId: cat.id, continueId: continueId, source: src)
            if engine.isLive { source = "" }
        }
    }

    private func deleteCategory(_ c: Category) {
        store.deleteCategory(c.id)
        if settings.curCat == c.id { settings.curCat = store.cats.first?.id ?? "" }
        deletingCat = nil
    }

    // MARK: Préparation

    private var preparing: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(engine.preparingText).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: Pendant l'écoute

    @ViewBuilder private var live: some View {
        if let d = engine.doc {
            liveHeader(d)
            Text("Résumé").font(.title3.weight(.bold)).padding(.top, 6)
            partsList(d)
        }
    }

    private func liveHeader(_ d: Doc) -> some View {
        let c = store.cat(d.categoryId)
        let finishing = engine.state == .finalizing || engine.state == .stopping
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if finishing {
                    ProgressView()
                    Text("Finalisation…").font(.headline)
                } else {
                    PulseDot()
                    Text("En écoute").font(.headline)
                    Spacer()
                    if let s = engine.startedAt { LiveClock(start: s) }
                }
            }
            Text("\(d.source.isEmpty ? "" : d.source + " · ")\(c.name)")
                .font(.subheadline).foregroundStyle(.secondary)
            if engine.state == .listening { liveButtons }
            if !settings.hasKey {
                Text("Sans clé API : transcription seule.").font(.footnote).foregroundStyle(.orange)
            } else if let p = engine.lastProblem {
                Text(p).font(.footnote).foregroundStyle(.orange)
            }
        }
        .card()
    }

    private var liveButtons: some View {
        HStack(spacing: 10) {
            Button { engine.newPart() } label: {
                Label("Nouvelle partie", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large)
            Button { Task { await engine.stop() } } label: {
                Label("Arrêter", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
        }
    }

    @ViewBuilder
    private func partsList(_ d: Doc) -> some View {
        let currentIndex = engine.state == .listening ? d.parts.count - 1 : -1
        ForEach(Array(d.parts.enumerated()), id: \.element.id) { item in
            if item.offset == currentIndex {
                CurrentPartCard(part: item.element, number: item.offset + 1, hasKey: settings.hasKey)
            } else if item.element.hasContent {
                PartSummaryCard(part: item.element, number: item.offset + 1)
            }
        }
    }
}

struct LiveClock: View {
    let start: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(Fmt.clock(ctx.date.timeIntervalSince(start))).font(.headline.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

struct ResumeRow: View {
    let doc: Doc
    let color: Color
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(doc.displayTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                Text("\(doc.parts.count) partie\(doc.parts.count > 1 ? "s" : "") · \(Fmt.relative(doc.updated))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle.fill").font(.title).foregroundStyle(color)
        }
        .card()
        .contentShape(Rectangle())
        .accessibilityLabel("Reprendre « \(doc.displayTitle) »")
    }
}

struct PartSummaryCard: View {
    let part: Part
    let number: Int
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            NumberBadge(n: number)
            VStack(alignment: .leading, spacing: 8) {
                Text(part.shownTitle).font(.headline)
                if part.status == .summarizing {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Rédaction…").font(.footnote).foregroundStyle(.secondary) }
                } else if let w = part.writeup {
                    if !w.chapeau.isEmpty { Text(w.chapeau).font(.subheadline.weight(.medium)) }
                    if !w.aRetenir.isEmpty { BulletList(items: w.aRetenir, font: .subheadline) }
                    if !w.shownSections.isEmpty {
                        DisclosureGroup("Détail", isExpanded: $expanded) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(w.shownSections.enumerated()), id: \.offset) { _, s in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.intertitre).font(.subheadline.weight(.semibold))
                                        Text(s.texte).font(.subheadline)
                                    }
                                }
                            }
                            .padding(.top, 6)
                        }
                        .font(.footnote)
                    }
                } else {
                    Text("Résumé non rédigé").font(.footnote).foregroundStyle(.orange)
                }
                Text("\(Fmt.time(part.start)) – \(Fmt.time(part.end ?? part.start))").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .card()
    }
}

struct CurrentPartCard: View {
    let part: Part
    let number: Int
    let hasKey: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            NumberBadge(n: number)
            VStack(alignment: .leading, spacing: 8) {
                Text(part.segments.first.map { "depuis \(Fmt.time($0.t))" } ?? "en attente de parole").font(.caption).foregroundStyle(.secondary)
                Text(part.label.nonEmpty ?? (part.segments.isEmpty ? "À l'écoute…" : "Sujet en cours…")).font(.headline)
                ListeningBars()
            }
        }
        .card(dashed: true)
    }
}

struct NumberBadge: View {
    let n: Int
    var body: some View {
        Text("\(n)").font(.footnote.weight(.bold)).monospacedDigit()
            .frame(width: 30, height: 30)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
