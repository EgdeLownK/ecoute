import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: Settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Clé API Anthropic") {
                    SecureField("sk-ant-…", text: $settings.apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }

                Section {
                    NavigationLink { CategoriesList() } label: {
                        HStack {
                            Label("Catégories", systemImage: "square.grid.2x2")
                            Spacer()
                            Text("\(store.cats.count)").foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Prise de notes") {
                    Picker("Notes en direct", selection: $settings.modelNotes) {
                        ForEach(Settings.models, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Picker("Résumés", selection: $settings.modelWrite) {
                        ForEach(Settings.models, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Stepper("Notes toutes les \(settings.chunkSeconds) s", value: $settings.chunkSeconds, in: 30...180, step: 15)
                    Toggle("Garder la transcription", isOn: $settings.includeTranscript)
                }

                Section("Découpage en parties") {
                    Toggle("Nouvelle partie à chaque sujet", isOn: $settings.topicAuto)
                    Picker("Sensibilité", selection: $settings.granularity) {
                        Text("Grands thèmes").tag("low")
                        Text("Normale").tag("normal")
                        Text("Chaque sous-thème").tag("high")
                    }
                    Stepper(settings.gapMinutes == 0 ? "Pas de coupure sur silence" : "Coupure après \(settings.gapMinutes) min de silence",
                            value: $settings.gapMinutes, in: 0...30)
                }

                Section("Transcription") {
                    Picker("Langue parlée", selection: $settings.localeId) {
                        ForEach(Settings.locales, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }
}

/// Gestion des catégories en feuille (depuis l'accueil).
struct CategoriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            CategoriesList()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }
}

/// Liste des catégories : ajouter, modifier (toucher la ligne), supprimer (corbeille).
struct CategoriesList: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: Settings
    @State private var editing: Category?
    @State private var creating = false
    @State private var deleting: Category?

    var body: some View {
        List {
            Section {
                Button { creating = true } label: {
                    Label("Ajouter une catégorie", systemImage: "plus.circle.fill").font(.body.weight(.semibold))
                }
            }
            Section {
                ForEach(store.cats) { c in
                    HStack(spacing: 12) {
                        Button { editing = c } label: {
                            HStack(spacing: 12) {
                                Image(systemName: c.kind.icon).font(.subheadline).foregroundStyle(Color(hex: c.colorHex))
                                    .frame(width: 32, height: 32)
                                    .background(Color(hex: c.colorHex).opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name).foregroundStyle(.primary)
                                    let n = store.docs(in: c.id).count
                                    Text("\(c.kind.label) · \(n) écoute\(n > 1 ? "s" : "")").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if store.cats.count > 1 {
                            Button { deleting = c } label: { Image(systemName: "trash").foregroundStyle(.red) }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Supprimer \(c.name)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Catégories")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { c in CategoryEditor(original: c) }
        .sheet(isPresented: $creating) { CategoryEditor(original: nil) }
        .confirmationDialog(deleting.map { "Supprimer « \($0.name) » ?" } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { c in
            Button("Supprimer", role: .destructive) {
                store.deleteCategory(c.id)
                if settings.curCat == c.id { settings.curCat = store.cats.first?.id ?? "" }
                deleting = nil
            }
        } message: { c in
            let n = store.docs(in: c.id).count
            Text(n == 0 ? "La catégorie est vide." : "\(n) écoute\(n > 1 ? "s" : "") ser\(n > 1 ? "ont" : "a") retirée\(n > 1 ? "s" : "") de l'app.")
        }
    }
}

struct CategoryEditor: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: Settings
    @Environment(\.dismiss) private var dismiss
    let original: Category?
    @State private var name = ""
    @State private var kind: ContentKind = .podcast
    @State private var color = Category.palette[0]
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: $name)
                Picker("Type", selection: $kind) {
                    ForEach(ContentKind.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                }
                Section("Couleur") {
                    HStack(spacing: 12) {
                        ForEach(Category.palette, id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: color == hex ? 2.5 : 0))
                                .onTapGesture { color = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if original != nil, store.cats.count > 1 {
                    Section {
                        Button("Supprimer la catégorie", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(original == nil ? "Nouvelle catégorie" : "Catégorie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(original == nil ? "Créer" : "Enregistrer") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Supprimer cette catégorie ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let o = original { store.deleteCategory(o.id); if settings.curCat == o.id { settings.curCat = store.cats.first?.id ?? "" } }
                    dismiss()
                }
            }
            .onAppear {
                if let o = original { name = o.name; kind = o.kind; color = o.colorHex }
                else { color = Category.palette[store.cats.count % Category.palette.count] }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if var o = original {
            o.name = n; o.kind = kind; o.colorHex = color
            store.saveCategory(o)
        } else {
            let c = store.newCategory(name: n, kind: kind, colorHex: color)
            store.saveCategory(c)
            settings.curCat = c.id
        }
        dismiss()
    }
}
