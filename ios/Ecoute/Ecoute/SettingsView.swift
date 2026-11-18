import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: Settings
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Category?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $settings.apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Notes en direct", selection: $settings.modelNotes) {
                        ForEach(Settings.models, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Picker("Comptes rendus et synthèse", selection: $settings.modelWrite) {
                        ForEach(Settings.models, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Stepper("Notes toutes les \(settings.chunkSeconds) s", value: $settings.chunkSeconds, in: 30...180, step: 15)
                    Toggle("Transcription dans chaque partie", isOn: $settings.includeTranscript)
                } header: {
                    Text("Prise de notes (Claude)")
                } footer: {
                    Text("La clé API est rangée dans le trousseau de l'iPhone. Sans elle, l'app garde seulement la transcription.")
                }

                Section("Découpage en parties") {
                    Toggle("Nouvelle partie à chaque changement de sujet", isOn: $settings.topicAuto)
                    Picker("Sensibilité", selection: $settings.granularity) {
                        Text("Faible : grands thèmes").tag("low")
                        Text("Normale").tag("normal")
                        Text("Forte : chaque sous-thème").tag("high")
                    }
                    Stepper(settings.gapMinutes == 0 ? "Pas de coupure sur silence" : "Nouvelle partie après \(settings.gapMinutes) min de silence",
                            value: $settings.gapMinutes, in: 0...30)
                }

                Section {
                    Picker("Langue parlée", selection: $settings.localeId) {
                        ForEach(Settings.locales, id: \.0) { Text($0.1).tag($0.0) }
                    }
                } header: {
                    Text("Transcription")
                } footer: {
                    Text("La transcription est faite sur l'iPhone par Apple. Au premier usage d'une langue, iOS peut télécharger son modèle.")
                }

                Section {
                    ForEach(store.cats) { c in
                        Button { editing = c } label: {
                            HStack(spacing: 10) {
                                Circle().fill(Color(hex: c.colorHex)).frame(width: 10, height: 10)
                                Text(c.name).foregroundStyle(.primary)
                                Spacer()
                                Text(c.kind.label).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button { creating = true } label: { Label("Nouvelle catégorie", systemImage: "plus") }
                } header: {
                    Text("Catégories")
                } footer: {
                    Text("Le type choisit le modèle de prise de notes. Fichiers : app Fichiers › Sur mon iPhone › Écoute.")
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .sheet(item: $editing) { c in CategoryEditor(original: c) }
            .sheet(isPresented: $creating) { CategoryEditor(original: nil) }
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
                TextField("Nom (ex. Livres audio, Cours de droit…)", text: $name)
                Picker("Type de contenu", selection: $kind) {
                    ForEach(ContentKind.allCases) { Text($0.label).tag($0) }
                }
                Section("Couleur") {
                    HStack(spacing: 12) {
                        ForEach(Category.palette, id: \.self) { hex in
                            Circle().fill(Color(hex: hex)).frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: color == hex ? 2.5 : 0))
                                .onTapGesture { color = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let o = original, store.cats.count > 1 {
                    Section {
                        Button("Supprimer la catégorie", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Ses enregistrements sont retirés de l'app. Les fichiers déjà écrits restent dans l'app Fichiers (dossier « \(o.folder) »).")
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
