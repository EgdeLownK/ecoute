import Foundation

// MARK: - Appel à l'API Anthropic

enum ClaudeError: LocalizedError {
    case http(Int, String), unreadable, noKey

    var errorDescription: String? {
        switch self {
        case .http(let code, let msg):
            if code == 401 { return "clé API invalide" }
            if code == 429 { return "limite de requêtes atteinte" }
            return msg.isEmpty ? "erreur API \(code)" : msg
        case .unreadable: return "réponse illisible"
        case .noKey: return "clé API manquante"
        }
    }
}

enum Claude {
    static func call(key: String, model: String, prompt: String, maxTokens: Int) async throws -> [String: Any] {
        guard !key.isEmpty else { throw ClaudeError.noKey }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = ["model": model, "max_tokens": maxTokens,
                                   "messages": [["role": "user", "content": prompt]]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        guard (200..<300).contains(code) else {
            let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? ""
            throw ClaudeError.http(code, msg)
        }
        let text = ((json["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined()
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b else { throw ClaudeError.unreadable }
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(String(text[a...b]).utf8))) as? [String: Any] else {
            throw ClaudeError.unreadable
        }
        return obj
    }
}

// Lecture tolérante du JSON renvoyé
func jStr(_ v: Any?) -> String { ((v as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
func jStrs(_ v: Any?) -> [String] {
    ((v as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
}
func jObjs(_ v: Any?, _ key: String) -> [[String: Any]] {
    ((v as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.filter { !jStr($0[key]).isEmpty }
}

// MARK: - Consignes données à Claude

enum Prompts {
    static let granularity = ["low": "large : seulement les grands changements de thème",
                              "normal": "normale : un changement net de thème",
                              "high": "fine : chaque sous-thème distinct"]

    static func sourceText(_ doc: Doc) -> String { doc.source.isEmpty ? "" : " (source : \(doc.source))" }

    /// Étage 1 : un extrait (~1 min) → texte nettoyé, notes détaillées, citations, références, changement de sujet.
    static func chunk(doc: Doc, part: Part, text: String, granularity: String) -> String {
        let prevNotes = part.notes.suffix(8).map { "- " + $0.text }.joined(separator: "\n")
        let prevClean = part.clean.last.map { String($0.text.suffix(240)) } ?? ""
        return """
        Tu prends des notes en direct pendant l'écoute d'un contenu de type « \(doc.kind.label) »\(sourceText(doc)). Voici un nouvel extrait de transcription automatique : quelques mots peuvent être mal reconnus, il peut y avoir plusieurs voix, et le son peut venir d'un haut-parleur.

        Sujet en cours : \(part.label.isEmpty ? "(début de l'écoute, pas encore de sujet)" : part.label)
        Dernières notes déjà prises :
        \(prevNotes.isEmpty ? "(aucune)" : prevNotes)
        Fin du passage précédent : « \(prevClean.isEmpty ? "…" : prevClean) »

        Extrait à traiter :
        \"\"\"
        \(text)
        \"\"\"

        Consignes :
        1. "texte_propre" : réécris l'extrait fidèlement, avec ponctuation et majuscules ; corrige les mots manifestement mal reconnus d'après le contexte ; retire hésitations et répétitions. Ne résume pas, ne commente pas.
        2. "notes" : notes détaillées, une idée par note, en phrases courtes mais complètes et compréhensibles seules. Garde tout ce qui compte : \(doc.kind.focus). Attribue les propos \(doc.kind.who). Ne répète pas les notes déjà prises. Ignore ce qui ressemble à du bruit (publicité, jingle, conversation parasite, fragment incompréhensible).
        3. "citations" : 0 à 2 phrases marquantes dites presque mot pour mot, avec leur auteur si c'est clair.
        4. "references" : livres, études, personnes, entreprises, œuvres, outils ou liens mentionnés, avec leur type.
        5. Changement de sujet (granularité \(Prompts.granularity[granularity] ?? Prompts.granularity["normal"]!)) : si l'extrait passe à un sujet clairement différent du sujet en cours, découpe-le en plusieurs segments dans l'ordre et mets "nouveau_sujet": true sur le segment qui ouvre le nouveau sujet. Un exemple, une précision ou une courte digression ne sont pas un nouveau sujet. Au début de l'écoute, "nouveau_sujet" vaut false.
        Écris dans la langue de l'extrait. Réponds UNIQUEMENT avec un objet JSON valide :
        {"segments":[{"nouveau_sujet":false,"sujet":"intitulé court du sujet (6 mots max)","texte_propre":"…","notes":["…"],"citations":[{"texte":"…","auteur":"…"}],"references":[{"nom":"…","type":"…"}]}]}
        """
    }

    static let fieldSpec: [String: String] = [
        "a_retenir": "\"a_retenir\":[\"3 à 6 points essentiels, une phrase chacun\"]",
        "citations": "\"citations\":[{\"texte\":\"les citations les plus marquantes parmi celles relevées (5 max)\",\"auteur\":\"…\"}]",
        "references": "\"references\":[{\"nom\":\"…\",\"type\":\"livre | étude | personne | entreprise | œuvre | outil | lien | autre\",\"contexte\":\"pourquoi c'est mentionné\"}]",
        "questions": "\"questions\":[\"questions ouvertes ou pistes pour aller plus loin\"]",
        "decisions": "\"decisions\":[\"décisions prises\"]",
        "actions": "\"actions\":[{\"qui\":\"…\",\"quoi\":\"…\",\"quand\":\"…\"}]",
        "definitions": "\"definitions\":[{\"terme\":\"…\",\"definition\":\"…\"}]"
    ]

    /// Étage 2 : le compte rendu d'une partie, rédigé à partir des notes (pas de la transcription brute).
    static func writeUp(doc: Doc, part: Part) -> (prompt: String, maxTokens: Int)? {
        let material = part.notes.isEmpty ? part.clean.map(\.text).joined(separator: "\n") : part.notes.map { "- " + $0.text }.joined(separator: "\n")
        guard !material.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let units = part.notes.isEmpty ? max(1, material.wordCount / 35) : part.notes.count
        let target = min(1500, max(120, units * 30))
        let quotes = part.quotes.map { "- « \($0.texte) »" + ($0.auteur.isEmpty ? "" : " — \($0.auteur)") }.joined(separator: "\n")
        let refs = part.refs.map { "- \($0.nom)" + ($0.type.isEmpty ? "" : " (\($0.type))") + ($0.contexte.isEmpty ? "" : " : \($0.contexte)") }.joined(separator: "\n")
        let fields = doc.kind.fields.compactMap { fieldSpec[$0] }.joined(separator: ",")
        let prompt = """
        Tu es un excellent rédacteur de comptes rendus. Voici les notes prises en direct pendant l'écoute d'un passage d'un contenu de type « \(doc.kind.label) »\(sourceText(doc))\(part.label.isEmpty ? "" : ", sur le sujet « \(part.label) »").

        Rédige le compte rendu de ce passage :
        - en prose fluide, au présent, en paragraphes (un par idée ou étape du raisonnement), sans listes ;
        - en conservant tous les éléments concrets des notes : chiffres, dates, noms, exemples, anecdotes, enchaînement des arguments. Ne résume pas à l'excès : vise environ \(target) mots, davantage si les notes sont denses ;
        - en attribuant les propos \(doc.kind.who) ;
        - sans rien inventer ni ajouter d'information absente des notes ; omets ce qui est confus plutôt que de deviner.
        Écris dans la langue des notes. Réponds UNIQUEMENT avec un objet JSON valide :
        {"titre":"titre précis du passage (8 mots max)","chapeau":"1 à 2 phrases qui disent l'essentiel","compte_rendu":["paragraphe 1","paragraphe 2","…"],\(fields),"mots_cles":["4 à 8 mots-clés"]}
        Laisse une liste vide quand il n'y a rien.

        Notes :
        \(material)
        \(quotes.isEmpty ? "" : "\nCitations relevées :\n" + quotes + "\n")\(refs.isEmpty ? "" : "\nRéférences mentionnées :\n" + refs + "\n")
        """
        return (prompt, min(8000, 1500 + target * 3))
    }

    static func parseWriteup(_ r: [String: Any], fallbackTitle: String) -> Writeup {
        var w = Writeup()
        w.titre = jStr(r["titre"]).nonEmpty ?? fallbackTitle
        w.chapeau = jStr(r["chapeau"])
        if let arr = r["compte_rendu"] as? [Any] { w.compteRendu = jStrs(arr) }
        else { w.compteRendu = jStr(r["compte_rendu"]).components(separatedBy: "\n\n").compactMap { $0.nonEmpty } }
        w.aRetenir = jStrs(r["a_retenir"])
        w.citations = jObjs(r["citations"], "texte").map { Quote(texte: jStr($0["texte"]), auteur: jStr($0["auteur"])) }
        w.references = jObjs(r["references"], "nom").map { Reference(nom: jStr($0["nom"]), type: jStr($0["type"]), contexte: jStr($0["contexte"])) }
        w.questions = jStrs(r["questions"])
        w.decisions = jStrs(r["decisions"])
        w.actions = jObjs(r["actions"], "quoi").map { ActionItem(qui: jStr($0["qui"]), quoi: jStr($0["quoi"]), quand: jStr($0["quand"])) }
        w.definitions = jObjs(r["definitions"], "terme").map { Definition(terme: jStr($0["terme"]), definition: jStr($0["definition"])) }
        w.motsCles = jStrs(r["mots_cles"])
        return w
    }

    /// Étage 3 : la synthèse de tout l'enregistrement.
    static func synthesis(doc: Doc) -> String? {
        let parts = doc.parts.enumerated().filter { $0.element.writeup != nil }
        guard !parts.isEmpty else { return nil }
        let body = parts.map { item -> String in
            let w = item.element.writeup!
            return "Partie \(item.offset + 1) — \(w.titre)\n\(w.chapeau)\n" + w.aRetenir.map { "- " + $0 }.joined(separator: "\n")
        }.joined(separator: "\n\n")
        return """
        Voici le découpage en parties d'un contenu de type « \(doc.kind.label) »\(sourceText(doc)), avec pour chaque partie son titre, son chapeau et ses points essentiels.
        Écris la synthèse de l'ensemble : ce dont il est question, le fil conducteur et les idées les plus importantes. N'invente rien. Écris dans la langue des parties.
        Réponds UNIQUEMENT avec un objet JSON valide :
        {"titre":"titre de l'enregistrement (10 mots max)","synthese":["1 à 3 paragraphes"],"a_retenir":["5 à 8 points essentiels de l'ensemble"]}

        \(body)
        """
    }

    static func parseSynthesis(_ r: [String: Any]) -> Synthesis {
        let syn: [String] = (r["synthese"] as? [Any]).map { jStrs($0) } ?? [jStr(r["synthese"])].filter { !$0.isEmpty }
        return Synthesis(titre: jStr(r["titre"]), synthese: syn, aRetenir: jStrs(r["a_retenir"]))
    }
}
