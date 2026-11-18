import Foundation
import Security
import SwiftUI

// MARK: - Données : catégories et enregistrements (JSON dans le dossier de l'app)

@MainActor
final class Store: ObservableObject {
    @Published var cats: [Category] = []
    @Published var docs: [Doc] = []
    private var saveTask: Task<Void, Never>?

    private var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Ecoute", isDirectory: true)
    }

    init() { load() }

    func load() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dec = JSONDecoder()
        if let d = try? Data(contentsOf: dir.appendingPathComponent("categories.json")),
           let c = try? dec.decode([Category].self, from: d), !c.isEmpty {
            cats = c
        } else {
            cats = Category.defaults
        }
        if let d = try? Data(contentsOf: dir.appendingPathComponent("documents.json")),
           let list = try? dec.decode([Doc].self, from: d) {
            docs = list
        }
        // Une écoute coupée brutalement (app fermée) : on referme proprement les parties restées ouvertes.
        for i in docs.indices {
            docs[i].parts.removeAll { !$0.hasContent }
            for j in docs[i].parts.indices where docs[i].parts[j].status == .open || docs[i].parts[j].status == .summarizing {
                docs[i].parts[j].status = docs[i].parts[j].writeup == nil ? .failed : .done
                if docs[i].parts[j].writeup == nil { docs[i].parts[j].error = "écoute interrompue" }
                if docs[i].parts[j].end == nil { docs[i].parts[j].end = docs[i].parts[j].segments.last?.t ?? docs[i].parts[j].start }
                if docs[i].parts[j].title.isEmpty { docs[i].parts[j].title = docs[i].parts[j].label.nonEmpty ?? "Partie" }
            }
        }
        docs.removeAll { $0.parts.isEmpty }
    }

    func saveSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let enc = JSONEncoder()
        if let d = try? enc.encode(cats) { try? d.write(to: dir.appendingPathComponent("categories.json"), options: .atomic) }
        if let d = try? enc.encode(docs) { try? d.write(to: dir.appendingPathComponent("documents.json"), options: .atomic) }
    }

    func cat(_ id: String) -> Category { cats.first { $0.id == id } ?? cats.first ?? Category.defaults[0] }
    func doc(_ id: UUID) -> Doc? { docs.first { $0.id == id } }
    func docs(in catId: String?) -> [Doc] {
        docs.filter { catId == nil || $0.categoryId == catId }.sorted { $0.updated > $1.updated }
    }

    /// Modifie un document en place.
    func update(_ id: UUID, _ change: (inout Doc) -> Void) {
        guard let i = docs.firstIndex(where: { $0.id == id }) else { return }
        change(&docs[i])
        docs[i].updated = Date()
        saveSoon()
    }

    func insertDoc(_ d: Doc) { docs.insert(d, at: 0); saveSoon() }
    func removeDoc(_ id: UUID) { docs.removeAll { $0.id == id }; saveSoon() }

    func saveCategory(_ c: Category) {
        if let i = cats.firstIndex(where: { $0.id == c.id }) { cats[i] = c } else { cats.append(c) }
        saveSoon()
    }
    func deleteCategory(_ id: String) {
        guard cats.count > 1 else { return }
        cats.removeAll { $0.id == id }
        docs.removeAll { $0.categoryId == id }
        saveSoon()
    }
    func newCategory(name: String, kind: ContentKind, colorHex: String) -> Category {
        var folder = Files.safeName(name), n = 2
        while cats.contains(where: { $0.folder.lowercased() == folder.lowercased() }) { folder = "\(Files.safeName(name)) (\(n))"; n += 1 }
        return Category(id: "c\(Int(Date().timeIntervalSince1970 * 1000))", name: name, colorHex: colorHex, kind: kind, folder: folder)
    }
}

// MARK: - Réglages

@MainActor
final class Settings: ObservableObject {
    private let ud = UserDefaults.standard

    @Published var apiKey: String { didSet { Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines)) } }
    @Published var modelNotes: String { didSet { ud.set(modelNotes, forKey: "modelNotes") } }
    @Published var modelWrite: String { didSet { ud.set(modelWrite, forKey: "modelWrite") } }
    @Published var chunkSeconds: Int { didSet { ud.set(chunkSeconds, forKey: "chunkSeconds") } }
    @Published var topicAuto: Bool { didSet { ud.set(topicAuto, forKey: "topicAuto") } }
    @Published var granularity: String { didSet { ud.set(granularity, forKey: "granularity") } }
    @Published var gapMinutes: Int { didSet { ud.set(gapMinutes, forKey: "gapMinutes") } }
    @Published var includeTranscript: Bool { didSet { ud.set(includeTranscript, forKey: "includeTranscript") } }
    @Published var localeId: String { didSet { ud.set(localeId, forKey: "localeId") } }
    @Published var curCat: String { didSet { ud.set(curCat, forKey: "curCat") } }

    init() {
        apiKey = Keychain.get()
        modelNotes = ud.string(forKey: "modelNotes") ?? "claude-haiku-5-5"
        modelWrite = ud.string(forKey: "modelWrite") ?? "claude-sonnet-5-5"
        chunkSeconds = ud.object(forKey: "chunkSeconds") as? Int ?? 60
        topicAuto = ud.object(forKey: "topicAuto") as? Bool ?? true
        granularity = ud.string(forKey: "granularity") ?? "normal"
        gapMinutes = ud.object(forKey: "gapMinutes") as? Int ?? 3
        includeTranscript = ud.object(forKey: "includeTranscript") as? Bool ?? true
        localeId = ud.string(forKey: "localeId") ?? "fr-FR"
        curCat = ud.string(forKey: "curCat") ?? "podcasts"
    }

    var key: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasKey: Bool { !key.isEmpty }

    static let models: [(String, String)] = [
        ("claude-haiku-5-5", "Claude Haiku 5.5 (rapide)"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
        ("claude-opus-5-5", "Claude Opus 5.5")
    ]
    static let locales: [(String, String)] = [
        ("fr-FR", "Français (France)"), ("fr-CA", "Français (Canada)"), ("en-US", "English (US)"), ("en-GB", "English (UK)"),
        ("es-ES", "Español"), ("de-DE", "Deutsch"), ("it-IT", "Italiano"), ("pt-PT", "Português")
    ]
}

// MARK: - Trousseau (la clé API n'est jamais stockée en clair)

enum Keychain {
    private static let service = "fr.egdelownk.ecoute"
    private static let account = "anthropic-api-key"

    static func get() -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }

    static func set(_ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock   // utilisable écran verrouillé, pendant l'écoute
        SecItemAdd(add as CFDictionary, nil)
    }
}
