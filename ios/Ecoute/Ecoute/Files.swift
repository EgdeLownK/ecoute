import Foundation

/// Fichiers Markdown, visibles dans l'app Fichiers : Sur mon iPhone › Écoute › Catégorie › Enregistrement
///   00 - Sommaire.md   (synthèse + liens vers les parties)
///   01 - Sujet.md, 02 - Sujet suivant.md…
/// Le document complet n'est jamais assemblé en un seul gros fichier.
enum Files {
    static let sommaire = "00 - Sommaire.md"

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

    // MARK: Contenu

    static func navLine(_ doc: Doc, _ i: Int) -> String {
        var items: [String] = []
        if i > 0 { items.append(link("← Partie précédente", doc.parts[i - 1].fileName ?? partFileName(doc.parts[i - 1], index: i - 1))) }
        items.append(link("Sommaire", sommaire))
        if i + 1 < doc.parts.count, doc.parts[i + 1].status != .open, let next = doc.parts[i + 1].fileName {
            items.append(link("Partie suivante →", next))
        }
        return items.joined(separator: " · ")
    }

    static func writeupMD(_ w: Writeup, _ p: Part, _ h: String) -> String {
        func cell(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ") }
        var md = ""
        if !w.compteRendu.isEmpty { md += "\n\(h) Compte rendu\n\n" + w.compteRendu.joined(separator: "\n\n") + "\n" }
        if !w.aRetenir.isEmpty { md += "\n\(h) À retenir\n\n" + w.aRetenir.map { "- " + $0 }.joined(separator: "\n") + "\n" }
        if !w.decisions.isEmpty { md += "\n\(h) Décisions\n\n" + w.decisions.map { "- " + $0 }.joined(separator: "\n") + "\n" }
        if !w.actions.isEmpty {
            md += "\n\(h) Actions\n\n| Qui | Quoi | Quand |\n|---|---|---|\n"
            md += w.actions.map { "| \(cell($0.qui.nonEmpty ?? "—")) | \(cell($0.quoi)) | \(cell($0.quand.nonEmpty ?? "—")) |" }.joined(separator: "\n") + "\n"
        }
        if !w.definitions.isEmpty { md += "\n\(h) Définitions\n\n" + w.definitions.map { "- **\($0.terme)** : \($0.definition)" }.joined(separator: "\n") + "\n" }
        let quotes = w.citations.isEmpty ? p.quotes : w.citations
        if !quotes.isEmpty { md += "\n\(h) Citations\n\n" + quotes.map { "> « \($0.texte) »" + ($0.auteur.isEmpty ? "" : " — \($0.auteur)") }.joined(separator: "\n\n") + "\n" }
        let refs = w.references.isEmpty ? p.refs : w.references
        if !refs.isEmpty {
            md += "\n\(h) Références citées\n\n| Référence | Type | Contexte |\n|---|---|---|\n"
            md += refs.map { "| \(cell($0.nom)) | \(cell($0.type.nonEmpty ?? "—")) | \(cell($0.contexte.nonEmpty ?? "—")) |" }.joined(separator: "\n") + "\n"
        }
        if !w.questions.isEmpty { md += "\n\(h) Questions et pistes\n\n" + w.questions.map { "- " + $0 }.joined(separator: "\n") + "\n" }
        return md
    }

    static func partMD(_ doc: Doc, _ i: Int, cat: Category, includeTranscript: Bool) -> String {
        let p = doc.parts[i], n = i + 1, end = p.end ?? p.start, w = p.writeup
        let kw = w?.motsCles ?? []
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "'") + "\"" }
        var md = "---\n"
        md += "document: \(q(doc.displayTitle))\ncategorie: \(q(cat.name))\ntype: \(q(doc.kind.label))\n"
        if !doc.source.isEmpty { md += "source: \(q(doc.source))\n" }
        md += "partie: \(n)\ntitre: \(q(p.shownTitle))\ndate: \(Fmt.iso(p.start))\ndebut: \"\(Fmt.time(p.start))\"\nfin: \"\(Fmt.time(end))\"\n"
        md += "mots_cles: [\(kw.map(q).joined(separator: ", "))]\n---\n\n"
        md += "# \(n). \(p.shownTitle)\n\n"
        if let c = w?.chapeau, !c.isEmpty { md += "> \(c)\n\n" }
        md += "_\(cat.name) › \(doc.displayTitle)\(doc.source.isEmpty ? "" : " · " + doc.source) · partie \(n) · \(Fmt.time(p.start)) → \(Fmt.time(end))_\n\n\(navLine(doc, i))\n"
        if let w { md += writeupMD(w, p, "##") }
        else { md += "\n_Compte rendu pas encore rédigé\(p.error.map { " (\($0))" } ?? "")._\n" }
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

    static func indexMD(_ doc: Doc, cat: Category) -> String {
        let done = doc.parts.enumerated().filter { $0.element.status != .open }
        let last = done.last?.element.end ?? doc.created
        var md = "---\ndocument: \"\(doc.displayTitle.replacingOccurrences(of: "\"", with: "'"))\"\ncategorie: \"\(cat.name)\"\ntype: \"\(doc.kind.label)\"\n"
        if !doc.source.isEmpty { md += "source: \"\(doc.source.replacingOccurrences(of: "\"", with: "'"))\"\n" }
        md += "cree: \(Fmt.iso(doc.created))\nparties: \(done.count)\n---\n\n"
        md += "# \(doc.displayTitle)\n\n_\(cat.name) · \(doc.kind.label)\(doc.source.isEmpty ? "" : " · " + doc.source) · \(Fmt.long(doc.created)) · \(done.count) partie\(done.count > 1 ? "s" : "") · \(Fmt.time(doc.created)) → \(Fmt.time(last))_\n"
        if let s = doc.synthesis {
            if !s.synthese.isEmpty { md += "\n## Synthèse\n\n" + s.synthese.joined(separator: "\n\n") + "\n" }
            if !s.aRetenir.isEmpty { md += "\n## À retenir\n\n" + s.aRetenir.map { "- " + $0 }.joined(separator: "\n") + "\n" }
        }
        md += "\n## Parties\n\nUne partie par sujet abordé. Ce sommaire les relie sans jamais les rassembler en un seul gros fichier.\n\n"
        for (i, p) in done {
            let one = p.writeup?.chapeau.nonEmpty ?? ""
            md += "\(i + 1). \(link(p.shownTitle, p.fileName ?? partFileName(p, index: i))) — \(Fmt.time(p.start)) → \(Fmt.time(p.end ?? p.start))" + (one.isEmpty ? "" : "  \n   \(one)") + "\n"
        }
        var refs: [(Reference, Int)] = []
        for (i, p) in doc.parts.enumerated() {
            let list = (p.writeup?.references.isEmpty == false) ? p.writeup!.references : p.refs
            for r in list where !refs.contains(where: { $0.0.nom.lowercased() == r.nom.lowercased() }) { refs.append((r, i + 1)) }
        }
        if !refs.isEmpty {
            md += "\n## Références citées\n\n| Référence | Type | Partie |\n|---|---|---|\n"
            md += refs.map { "| \($0.0.nom.replacingOccurrences(of: "|", with: "/")) | \($0.0.type.nonEmpty ?? "—") | \($0.1) |" }.joined(separator: "\n") + "\n"
        }
        return md
    }

    // MARK: Écriture

    /// Écrit (ou réécrit) le sommaire et toutes les parties terminées. Renvoie les fichiers écrits.
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
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for i in doc.parts.indices where doc.parts[i].status != .open && doc.parts[i].hasContent {
            if doc.parts[i].fileName == nil { doc.parts[i].fileName = partFileName(doc.parts[i], index: i) }
        }
        let index = dir.appendingPathComponent(sommaire)
        try? indexMD(doc, cat: cat).write(to: index, atomically: true, encoding: .utf8)
        urls.append(index)
        for i in doc.parts.indices where doc.parts[i].status != .open && doc.parts[i].hasContent {
            let url = dir.appendingPathComponent(doc.parts[i].fileName!)
            try? partMD(doc, i, cat: cat, includeTranscript: includeTranscript).write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
        }
        return urls
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
