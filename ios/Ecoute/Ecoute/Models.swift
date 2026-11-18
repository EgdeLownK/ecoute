import Foundation

// MARK: - Types de contenu (modèle de prise de notes)

enum ContentKind: String, Codable, CaseIterable, Identifiable {
    case podcast, livre, reunion, cours, idees

    var id: String { rawValue }

    var label: String {
        switch self {
        case .podcast: return "Podcast / vidéo"
        case .livre: return "Livre audio"
        case .reunion: return "Réunion / appel"
        case .cours: return "Cours / conférence"
        case .idees: return "Idées / notes perso"
        }
    }

    /// À qui attribuer les propos.
    var who: String {
        switch self {
        case .podcast: return "aux intervenants (animateur, invité…), seulement quand c'est clair"
        case .livre: return "à l'auteur, au narrateur ou aux personnages, seulement quand c'est clair"
        case .reunion: return "aux participants, quand c'est clair"
        case .cours: return "à l'enseignant ou à l'orateur"
        case .idees: return "à l'auteur, qui parle seul"
        }
    }

    /// Ce qu'il faut garder dans les notes.
    var focus: String {
        switch self {
        case .podcast:
            return "thèses et idées défendues, arguments et raisonnements, exemples et anecdotes, chiffres et dates, conseils concrets, citations marquantes, références (livres, études, personnes, entreprises, œuvres, outils, liens)"
        case .livre:
            return "pour un essai : idées principales, arguments, exemples, chiffres ; pour un récit : intrigue, personnages, lieux, événements et leur enchaînement ; passages marquants, citations, références"
        case .reunion:
            return "informations échangées, décisions prises, actions (qui fait quoi et pour quand), désaccords, chiffres et dates"
        case .cours:
            return "notions et définitions, explications, exemples, formules, dates et noms importants, plan du cours"
        case .idees:
            return "idées, raisonnements, pistes, questions, décisions et prochaines étapes"
        }
    }

    /// Rubriques du compte rendu.
    var fields: [String] {
        switch self {
        case .podcast, .livre: return ["a_retenir", "citations", "references", "questions"]
        case .reunion: return ["a_retenir", "decisions", "actions", "questions"]
        case .cours: return ["a_retenir", "definitions", "references", "questions"]
        case .idees: return ["a_retenir", "actions", "questions"]
        }
    }
}

// MARK: - Catégories

struct Category: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var colorHex: String
    var kind: ContentKind
    var folder: String

    static let palette = ["#9B7BF0", "#3ECF9A", "#5B9CF5", "#F0B54A", "#E66FB0", "#EF6B6B", "#46C2D6", "#A3C94A"]

    static let defaults: [Category] = [
        Category(id: "podcasts", name: "Podcasts & vidéos", colorHex: "#9B7BF0", kind: .podcast, folder: "Podcasts & vidéos"),
        Category(id: "livres", name: "Livres audio", colorHex: "#46C2D6", kind: .livre, folder: "Livres audio"),
        Category(id: "general", name: "Général", colorHex: "#3ECF9A", kind: .podcast, folder: "Général"),
        Category(id: "reunions", name: "Réunions", colorHex: "#5B9CF5", kind: .reunion, folder: "Réunions"),
        Category(id: "cours", name: "Cours", colorHex: "#F0B54A", kind: .cours, folder: "Cours"),
        Category(id: "idees", name: "Idées", colorHex: "#E66FB0", kind: .idees, folder: "Idées")
    ]
}

// MARK: - Contenu d'un enregistrement

struct TimedText: Codable, Hashable {
    var t: Date
    var text: String
    var raw: Bool = false
}

struct Quote: Codable, Hashable {
    var texte: String
    var auteur: String
}

struct Reference: Codable, Hashable {
    var nom: String
    var type: String
    var contexte: String
}

struct ActionItem: Codable, Hashable {
    var qui: String
    var quoi: String
    var quand: String
}

struct Definition: Codable, Hashable {
    var terme: String
    var definition: String
}

/// Compte rendu rédigé d'une partie.
struct Writeup: Codable, Hashable {
    var titre = ""
    var chapeau = ""
    var compteRendu: [String] = []
    var aRetenir: [String] = []
    var citations: [Quote] = []
    var references: [Reference] = []
    var questions: [String] = []
    var decisions: [String] = []
    var actions: [ActionItem] = []
    var definitions: [Definition] = []
    var motsCles: [String] = []
}

struct Synthesis: Codable, Hashable {
    var titre: String
    var synthese: [String]
    var aRetenir: [String]
}

enum PartStatus: String, Codable {
    case open, summarizing, done, failed
}

/// Une partie = un sujet. C'est un petit fichier ; le document complet n'est jamais assemblé en un seul gros fichier.
struct Part: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date?
    var status: PartStatus = .open
    var label = ""                 // sujet repéré en direct
    var title = ""
    var segments: [TimedText] = [] // transcription brute
    var notes: [TimedText] = []    // notes prises en direct
    var clean: [TimedText] = []    // transcription nettoyée
    var quotes: [Quote] = []
    var refs: [Reference] = []
    var writeup: Writeup?
    var error: String?
    var fileName: String?

    var hasContent: Bool { !segments.isEmpty || !notes.isEmpty || !clean.isEmpty }
    var shownTitle: String { writeup?.titre.nonEmpty ?? title.nonEmpty ?? label.nonEmpty ?? "Partie" }
}

struct Run: Codable, Hashable {
    var start: Date
    var end: Date
}

struct Doc: Codable, Identifiable, Hashable {
    var id = UUID()
    var categoryId: String
    var kind: ContentKind
    var source = ""
    var created: Date
    var updated: Date
    var title = ""
    var folder = ""
    var parts: [Part] = []
    var runs: [Run] = []
    var synthesis: Synthesis?

    var displayTitle: String {
        title.nonEmpty
            ?? parts.first(where: { $0.writeup?.titre.nonEmpty != nil })?.writeup?.titre
            ?? parts.first(where: { !$0.title.isEmpty })?.title
            ?? "Écoute du \(Fmt.short(created)) · \(Fmt.time(created))"
    }
    var duration: TimeInterval { runs.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } }
    var snippet: String {
        synthesis?.synthese.first ?? parts.first(where: { $0.writeup?.chapeau.nonEmpty != nil })?.writeup?.chapeau ?? ""
    }
}

extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    var wordCount: Int { split(whereSeparator: { $0 == " " || $0 == "\n" }).count }
}
