import SwiftUI

/// Onglet « Écoute » : avant GO, le choix de la catégorie ; pendant l'écoute, uniquement le résumé qui se construit.
struct ListenView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var engine: Engine
    @State private var continueMode = false
    @State private var continueId: UUID?
    @State private var source = ""
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch engine.state {
                    case .idle: idle
                    case .preparing: preparing
                    default: live
                    }
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Écoute")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var cat: Category { store.cat(settings.curCat) }

    // MARK: Avant GO

    @ViewBuilder private var idle: some View {
        categoryChips
        goButton
        if !settings.hasKey { keyWarning }
        recordingCard
        backgroundCard
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.cats) { c in
                    Button {
                        settings.curCat = c.id
                        continueId = nil
                    } label: {
                        CategoryChip(cat: c, selected: c.id == cat.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var goButton: some View {
        let color = Color(hex: cat.colorHex)
        return VStack(spacing: 18) {
            Button { go() } label: {
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
            .disabled(continueMode && continueId == nil)
            destinationLine
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var destinationLine: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: cat.colorHex)).frame(width: 8, height: 8)
            Text(cat.name).fontWeight(.semibold)
            Text("›").foregroundStyle(.secondary)
            if continueMode, let id = continueId, let d = store.doc(id) {
                Text("suite de « \(d.displayTitle) »").lineLimit(1)
            } else {
                Text("nouvel enregistrement · \(cat.kind.label)").foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(.subheadline)
    }

    private var keyWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "key.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Clé API manquante").font(.subheadline.weight(.semibold))
                Text("Sans elle, l'app garde seulement la transcription : pas de notes ni de résumé.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Ajouter ma clé") { showSettings = true }.font(.footnote.weight(.semibold))
            }
        }
        .card()
    }

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $continueMode) {
                Text("Nouvel enregistrement").tag(false)
                Text("Continuer").tag(true)
            }
            .pickerStyle(.segmented)
            if continueMode { continueList } else { sourceField }
        }
        .card()
    }

    private var sourceField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Source").font(.subheadline.weight(.semibold))
            TextField("ex. titre du livre, du podcast, de l'épisode…", text: $source)
                .textFieldStyle(.roundedBorder)
            Text("Facultatif : aide Claude à reconnaître les noms. Modèle de notes : \(cat.kind.label).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var continueList: some View {
        let list = store.docs(in: cat.id)
        if list.isEmpty {
            Text("Aucun enregistrement dans \(cat.name) pour l'instant.").font(.footnote).foregroundStyle(.secondary)
        } else {
            Text("Les nouvelles parties s'ajouteront à la suite.").font(.footnote).foregroundStyle(.secondary)
            ForEach(list) { d in
                Button { continueId = d.id } label: { ContinueRow(doc: d, selected: continueId == d.id) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var backgroundCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Écoute en arrière-plan", systemImage: "lock.iphone").font(.subheadline.weight(.semibold))
            Text("Après GO, tu peux verrouiller l'iPhone ou lancer ton livre audio : l'app continue d'écouter sans couper la lecture. Les fichiers sont dans l'app Fichiers › Sur mon iPhone › Écoute.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .card()
    }

    private func go() {
        let src = source
        Task {
            await engine.start(categoryId: cat.id, continueId: continueMode ? continueId : nil, source: src)
            if engine.isLive { source = ""; continueMode = false; continueId = nil }
        }
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
            SectionLabel(text: "Le résumé").padding(.top, 6).padding(.leading, 4)
            partsList(d)
            Text(engine.state == .listening
                 ? "Chaque sujet est résumé dès qu'il se termine. À l'arrêt, l'app rédige la synthèse et ouvre l'enregistrement complet."
                 : "Rédaction des derniers résumés et de la synthèse. L'enregistrement complet va s'ouvrir.")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }

    private func liveHeader(_ d: Doc) -> some View {
        let c = store.cat(d.categoryId)
        let finishing = engine.state == .finalizing || engine.state == .stopping
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if finishing {
                    ProgressView()
                    Text("Finalisation de l'enregistrement…").font(.headline)
                } else {
                    PulseDot()
                    Text("Écoute en cours").font(.headline)
                    Spacer()
                    if let s = engine.startedAt { LiveClock(start: s) }
                }
            }
            Text("\(d.source.isEmpty ? "" : d.source + " · ")\(c.name) · \(d.kind.label)")
                .font(.subheadline).foregroundStyle(.secondary)
            if engine.state == .listening { liveButtons }
            if !settings.hasKey {
                Text("Sans clé API, seule la transcription est gardée.").font(.footnote).foregroundStyle(.orange)
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

struct ContinueRow: View {
    let doc: Doc
    let selected: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("\(doc.parts.count) partie\(doc.parts.count > 1 ? "s" : "") · \(Fmt.relative(doc.updated))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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
                Text("\(Fmt.time(part.start)) – \(Fmt.time(part.end ?? part.start))").font(.caption).foregroundStyle(.secondary)
                Text(part.shownTitle).font(.headline)
                if part.status == .summarizing {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Rédaction du résumé…").font(.footnote).foregroundStyle(.secondary) }
                } else if let w = part.writeup {
                    if !w.chapeau.isEmpty { Text(w.chapeau).font(.subheadline.weight(.medium)) }
                    ForEach(Array(w.aRetenir.enumerated()), id: \.offset) { _, x in
                        HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•"); Text(x).font(.subheadline) }
                    }
                    if !w.compteRendu.isEmpty {
                        DisclosureGroup("Lire le compte rendu", isExpanded: $expanded) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(w.compteRendu.enumerated()), id: \.offset) { _, para in Text(para).font(.subheadline) }
                            }
                            .padding(.top, 6)
                        }
                        .font(.footnote)
                    }
                } else {
                    Text("Résumé non rédigé\(part.error.map { " (\($0))" } ?? "") : il pourra être relancé depuis l'enregistrement.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
                Text(hasKey ? "Le résumé de ce sujet sera rédigé dès qu'il se termine." : "Transcription en cours.")
                    .font(.footnote).foregroundStyle(.secondary)
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
