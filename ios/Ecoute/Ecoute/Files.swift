import Foundation

/// Fichiers Markdown, visibles dans l'app Fichiers : Sur mon iPhone › Écoute › Catégorie › Enregistrement
///   00 - Sommaire.md              synthèse courte + liens
///   01 - À retenir.md             l'essentiel, puis partie par partie
///   02 - Leçons.md                leçons et mise en pratique, pistes (ou « Décisions et actions » pour une réunion)
///   03 - Citations et références.md, 04 - Glossaire.md (s'il y a de la matière)
///   Parties/01 - Sujet.md, 02 - Sujet suivant.md…
/// Le document complet n'est jamais assemblé en un seul gros fichier.
enum Files {
    static let sommaire = "00 - Sommaire.md"
    static let partsDir = "Parties"

    static var root: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "\\/:*?\"<>|#^[]")
        let cleaned = s.components(separatedBy: bad).joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let cut = String(cleaned.prefix(60)).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? "Sans titre" : cut
    }

    static func folderName(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "yyyy-MM-dd HH'h'mm"
        return f.string(from: d)
    }

    static func partFileName(_ part: Part, index: Int) -> String {
        String(format: "%02d", index + 1) + " - " + safeName(part.shownTitle) + ".md"
    }

    static func link(_ label: String, _ file: String) -> String {
        "[\(label)](\(file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file))"
    }

    static func bullets(_ items: [String]) -> String { items.map { "- " + $0 }.joined(separator: "\n") + "\n" }
    static func cell(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ") }
    static func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "'") + "\"" }

    // MARK: Une partie (dans le sous-dossier Parties)

    static func navLine(_ doc: Doc, _ i: Int) -> String {
        var items: [String] = []
        if i > 0 { items.append(link("← Partie précédente", doc.parts[i - 1].fileName ?? partFileName(doc.parts[i - 1], index: i - 1))) }
        items.append(link("Sommaire", "../" + sommaire))
        if i + 1 < doc.parts.count, doc.parts[i + 1].status != .open, let next = doc.parts[i + 1].fileName {
            items.append(link("Partie suivante →", next))
        }
        return items.joined(separator: " · ")
    }

    static func writeupMD(_ w: Writeup, _ p: Part, _ h: String) -> String {
        var md = ""
        if !w.aRetenir.isEmpty { md += "\n\(h) À retenir\n\n" + bullets(w.aRetenir) }
        if !w.shownSections.isEmpty {
            for s in w.shownSections { md += "\n\(h) \(s.intertitre.nonEmpty ?? "Développement")\n\n\(s.texte)\n" }
        } else if !w.compteRendu.isEmpty {
            md += "\n\(h) Compte rendu\n\n" + w.compteRendu.joined(separator: "\n\n") + "\n"
        }
        if !w.decisions.isEmpty { md += "\n\(h) Décisions\n\n" + bullets(w.decisions) }
        if !w.actions.isEmpty { md += "\n\(h) Actions\n\n" + actionsTable(w.actions) }
        if !w.definitions.isEmpty { md += "\n\(h) Définitions\n\n" + w.definitions.map { "- **\($0.terme)** : \($0.definition)" }.joined(separator: "\n") + "\n" }
        let quotes = w.citations.isEmpty ? p.quotes : w.citations
        if !quotes.isEmpty { md += "\n\(h) Citations\n\n" + quotesMD(quotes) }
        let refs = w.references.isEmpty ? p.refs : w.references
        if !refs.isEmpty { md += "\n\(h) Références citées\n\n" + refsTable(refs) }
        if !w.questions.isEmpty { md += "\n\(h) Questions et pistes\n\n" + bullets(w.questions) }
        return md
    }

    static func actionsTable(_ a: [ActionItem]) -> String {
        "| Qui | Quoi | Quand |\n|---|---|---|\n"
            + a.map { "| \(cell($0.qui.nonEmpty ?? "—")) | \(cell($0.quoi)) | \(cell($0.quand.nonEmpty ?? "—")) |" }.joined(separator: "\n") + "\n"
    }
    static func quotesMD(_ quotes: [Quote]) -> String {
        quotes.map { "> « \($0.texte) »" + ($0.auteur.isEmpty ? "" : " — \($0.auteur)") }.joined(separator: "\n\n") + "\n"
    }
    static func refsTable(_ refs: [Reference]) -> String {
        "| Référence | Type | Contexte |\n|---|---|---|\n"
            + refs.map { "| \(cell($0.nom)) | \(cell($0.type.nonEmpty ?? "—")) | \(cell($0.contexte.nonEmpty ?? "—")) |" }.joined(separator: "\n") + "\n"
    }

    static func partMD(_ doc: Doc, _ i: Int, cat: Category, includeTranscript: Bool) -> String {
        let p = doc.parts[i], n = i + 1, end = p.end ?? p.start, w = p.writeup
        let kw = w?.motsCles ?? []
        var md = "---\n"
        md += "document: \(q(doc.displayTitle))\ncategorie: \(q(cat.name))\ntype: \(q(doc.kind.label))\n"
        if !doc.source.isEmpty { md += "source: \(q(doc.source))\n" }
        md += "partie: \(n)\ntitre: \(q(p.shownTitle))\ndate: \(Fmt.iso(p.start))\ndebut: \"\(Fmt.time(p.start))\"\nfin: \"\(Fmt.time(end))\"\n"
        md += "mots_cles: [\(kw.map(q).joined(separator: ", "))]\n---\n\n"
        md += "# \(n). \(p.shownTitle)\n\n"
        if let c = w?.chapeau, !c.isEmpty { md += "> \(c)\n\n" }
        md += "_\(cat.name) › \(doc.displayTitle) · partie \(n) · \(Fmt.time(p.start)) → \(Fmt.time(end))_\n\n\(navLine(doc, i))\n"
        if let w { md += writeupMD(w, p, "##") }
        else { md += "\n_Résumé pas encore rédigé\(p.error.map { " (\($0))" } ?? "")._\n" }
        if !kw.isEmpty { md += "\n**Mots-clés :** " + kw.joined(separator: ", ") + "\n" }
        if !p.notes.isEmpty {
            md += "\n<details>\n<summary>Notes prises pendant l'écoute (\(p.notes.count))</summary>\n\n"
            md += p.notes.map { "- **\(Fmt.time($0.t))** \($0.text)" }.joined(separator: "\n") + "\n\n</details>\n"
        }
        let tr = p.clean.isEmpty ? p.segments : p.clean
        if !tr.isEmpty && (includeTranscript || w == nil) {
            let body = tr.map { "**\(Fmt.time($0.t))** \($0.text)" }.joined(separator: "\n\n")
            md += w == nil ? "\n## Transcription\n\n\(body)\n" : "\n<details>\n<summary>Transcription</summary>\n\n\(body)\n\n</details>\n"
        }
        return md + "\n---\n\n\(navLine(doc, i))\n"
    }

    // MARK: Fichiers thématiques (à la racine du dossier)

    /// Titre et contenu de chaque fichier thématique qui a de la matière, dans l'ordre.
    static func extras(_ doc: Doc) -> [(title: String, body: String)] {
        var out: [(title: String, body: String)] = []
        let done = doc.parts.enumerated().filter { $0.element.writeup != nil }

        if doc.hasKeyPoints {
            var b = ""
            if let g = doc.synthesis?.aRetenir, !g.isEmpty { b += "## L'essentiel\n\n" + bullets(g) }
            let byPart = done.filter { !($0.element.writeup?.aRetenir ?? []).isEmpty }
            if !byPart.isEmpty {
                b += "\n## Partie par partie\n"
                for (i, p) in byPart {
                    b += "\n### \(i + 1). " + link(p.shownTitle, partsDir + "/" + (p.fileName ?? partFileName(p, index: i))) + "\n\n" + bullets(p.writeup!.aRetenir)
                }
            }
            out.append(("À retenir", b))
        }

        if doc.kind == .reunion {
            if !doc.allDecisions.isEmpty || !doc.allActions.isEmpty {
                var b = ""
                if !doc.allDecisions.isEmpty { b += "## Décisions\n\n" + bullets(doc.allDecisions) }
                if !doc.allActions.isEmpty { b += "\n## Actions\n\n" + actionsTable(doc.allActions) }
                out.append(("Décisions et actions", b))
            }
        } else if !doc.lessons.isEmpty || !doc.furtherQuestions.isEmpty {
            var b = ""
            for (k, l) in doc.lessons.enumerated() {
                b += "## \(k + 1). \(l.lecon)\n\n" + (l.application.isEmpty ? "" : "**Comment l'appliquer :** \(l.application)\n\n")
            }
            if !doc.furtherQuestions.isEmpty { b += "## Pour aller plus loin\n\n" + bullets(doc.furtherQuestions) }
            out.append(("Leçons", b))
        }

        if !doc.allQuotes.isEmpty || !doc.allRefs.isEmpty {
            var b = ""
            if !doc.allQuotes.isEmpty { b += "## Citations\n\n" + quotesMD(doc.allQuotes) }
            if !doc.allRefs.isEmpty { b += "\n## Références\n\n" + refsTable(doc.allRefs) }
            out.append(("Citations et références", b))
        }

        if !doc.allDefinitions.isEmpty {
            out.append(("Glossaire", doc.allDefinitions.map { "- **\($0.terme)** : \($0.definition)" }.joined(separator: "\n") + "\n"))
        }
        return out
    }

    static func extraFileName(_ k: Int, _ title: String) -> String { String(format: "%02d", k + 1) + " - " + title + ".md" }

    static func extraMD(_ doc: Doc, cat: Category, title: String, body: String) -> String {
        "---\ndocument: \(q(doc.displayTitle))\ncategorie: \(q(cat.name))\n---\n\n# \(title)\n\n_\(cat.name) › \(doc.displayTitle)_ · \(link("Sommaire", sommaire))\n\n" + body
    }

    static func indexMD(_ doc: Doc, cat: Category) -> String {
        let done = doc.parts.enumerated().filter { $0.element.status != .open }
        let last = done.last?.element.end ?? doc.created
        var md = "---\ndocument: \(q(doc.displayTitle))\ncategorie: \(q(cat.name))\ntype: \(q(doc.kind.label))\n"
        if !doc.source.isEmpty { md += "source: \(q(doc.source))\n" }
        md += "cree: \(Fmt.iso(doc.created))\nparties: \(done.count)\n---\n\n"
        md += "# \(doc.displayTitle)\n\n_\(cat.name)\(doc.source.isEmpty ? "" : " · " + doc.source) · \(Fmt.long(doc.created)) · \(Fmt.time(doc.created)) → \(Fmt.time(last))_\n"
        if let s = doc.synthesis, !s.synthese.isEmpty { md += "\n## Synthèse\n\n" + s.synthese.joined(separator: "\n\n") + "\n" }
        let ex = extras(doc)
        if !ex.isEmpty {
            md += "\n## Fiches\n\n" + ex.enumerated().map { "- " + link($0.element.title, extraFileName($0.offset, $0.element.title)) }.joined(separator: "\n") + "\n"
        }
        md += "\n## Parties\n\n"
        for (i, p) in done {
            let one = p.writeup?.chapeau.nonEmpty ?? ""
            md += "\(i + 1). \(link(p.shownTitle, partsDir + "/" + (p.fileName ?? partFileName(p, index: i)))) — \(Fmt.time(p.start)) → \(Fmt.time(p.end ?? p.start))" + (one.isEmpty ? "" : "  \n   \(one)") + "\n"
        }
        return md
    }

    // MARK: Écriture

    /// Écrit (ou réécrit) le sommaire, les fiches thématiques et toutes les parties terminées.
    /// Les anciens fichiers .md du dossier qui ne correspondent plus à rien sont retirés. Renvoie les fichiers écrits.
    @discardableResult
    static func write(_ doc: inout Doc, cat: Category, includeTranscript: Bool) -> [URL] {
        let fm = FileManager.default
        let catDir = root.appendingPathComponent(cat.folder, isDirectory: true)
        try? fm.createDirectory(at: catDir, withIntermediateDirectories: true)
        if doc.folder.isEmpty {
            var name = folderName(doc.created), n = 2
            while fm.fileExists(atPath: catDir.appendingPathComponent(name).path) { name = "\(folderName(doc.created)) (\(n))"; n += 1 }
            doc.folder = name
        }
        let dir = catDir.appendingPathComponent(doc.folder, isDirectory: true)
        let partsURL = dir.appendingPathComponent(partsDir, isDirectory: true)
        try? fm.createDirectory(at: partsURL, withIntermediateDirectories: true)
        for i in doc.parts.indices where doc.parts[i].status != .open && doc.parts[i].hasContent {
            if doc.parts[i].fileName == nil { doc.parts[i].fileName = partFileName(doc.parts[i], index: i) }
        }

        var urls: [URL] = []
        var keepTop: Set<String> = [sommaire]
        var keepParts: Set<String> = []
        let index = dir.appendingPathComponent(sommaire)
        try? indexMD(doc, cat: cat).write(to: index, atomically: true, encoding: .utf8)
        urls.append(index)
        for (k, e) in extras(doc).enumerated() {
            let name = extraFileName(k, e.title)
            let url = dir.appendingPathComponent(name)
            try? extraMD(doc, cat: cat, title: e.title, body: e.body).write(to: url, atomically: true, encoding: .utf8)
            keepTop.insert(name)
            urls.append(url)
        }
        for i in doc.parts.indices where doc.parts[i].status != .open && doc.parts[i].hasContent {
            let name = doc.parts[i].fileName!
            let url = partsURL.appendingPathComponent(name)
            try? partMD(doc, i, cat: cat, includeTranscript: includeTranscript).write(to: url, atomically: true, encoding: .utf8)
            keepParts.insert(name)
            urls.append(url)
        }
        removeStale(in: dir, keep: keepTop)
        removeStale(in: partsURL, keep: keepParts)
        return urls
    }

    private static func removeStale(in dir: URL, keep: Set<String>) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in items where url.pathExtension.lowercased() == "md" && !keep.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
    }

    static func folderURL(_ doc: Doc, cat: Category) -> URL? {
        doc.folder.isEmpty ? nil : root.appendingPathComponent(cat.folder, isDirectory: true).appendingPathComponent(doc.folder, isDirectory: true)
    }
}

// MARK: - Formats de date

enum Fmt {
    private static let fr = Locale(identifier: "fr_FR")
    private static func f(_ pattern: String) -> DateFormatter {
        let d = DateFormatter(); d.locale = fr; d.dateFormat = pattern; return d
    }
    private static let tF = f("HH:mm"), shortF = f("d MMM"), shortYF = f("d MMM yyyy"), longF = f("EEEE d MMMM yyyy"), isoF = f("yyyy-MM-dd")

    static func time(_ d: Date) -> String { tF.string(from: d) }
    static func short(_ d: Date) -> String { shortF.string(from: d) }
    static func iso(_ d: Date) -> String { isoF.string(from: d) }
    static func long(_ d: Date) -> String { let s = longF.string(from: d); return s.prefix(1).uppercased() + s.dropFirst() }
    static func relative(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Aujourd'hui, \(time(d))" }
        if cal.isDateInYesterday(d) { return "Hier, \(time(d))" }
        return cal.isDate(d, equalTo: Date(), toGranularity: .year) ? shortF.string(from: d) : shortYF.string(from: d)
    }
    static func duration(_ s: TimeInterval) -> String {
        let m = Int((s / 60).rounded())
        if m < 1 { return "< 1 min" }
        return m < 60 ? "\(m) min" : "\(m / 60) h \(String(format: "%02d", m % 60))"
    }
    static func clock(_ s: TimeInterval) -> String {
        let t = max(0, Int(s)), h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}
