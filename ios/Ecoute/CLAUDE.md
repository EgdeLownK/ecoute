# Écoute — mémoire du projet (à lire avant toute modification)

App iPhone qui écoute ce que l'utilisateur écoute (livre audio, podcast, vidéo, réunion), en arrière-plan,
et produit un **compte rendu rédigé de qualité**, découpé par sujet.
Propriétaire : Killian, non-développeur. Il valide sur iPhone via TestFlight et ne tape pas de commandes.

## Règles de travail

- Lire **tous** les fichiers Swift avant de modifier quoi que ce soit : le projet est petit (environ 2 400 lignes, 12 fichiers).
- Ne jamais défaire une décision listée plus bas sans le demander à Killian.
- Toutes les chaînes visibles sont en **français**, en tutoiement, avec des phrases courtes et sans jargon technique.
- Après une modification, vérifier que le projet compile (cible Ecoute, « Any iOS Device »).
- Expliquer les changements à Killian en mots simples, sans commandes à taper.

## Ce que fait chaque fichier (dossier `Ecoute/`)

| Fichier | Rôle |
|---|---|
| `EcouteApp.swift` | Point d'entrée, `AppNav` (onglet actif, navigation de la bibliothèque) et `TabView` à 2 onglets. Ouvre le document terminé (`finishedDocId`). |
| `Engine.swift` | Le cœur : états `idle / preparing / listening / stopping / finalizing`, tampon de phrases, envoi des morceaux à Claude, clôture des parties, synthèse, écriture des fichiers. |
| `Transcriber.swift` | Transcription **sur l'iPhone** avec `SpeechAnalyzer` / `SpeechTranscriber` (iOS 26), micro via `AVAudioEngine`. Gère les interruptions et les changements d'audio. Seuls les résultats finaux sont gardés. |
| `Claude.swift` | Appel à l'API Anthropic et tous les **prompts** (`Prompts.chunk`, `writeUp`, `synthesis`), plus leur lecture JSON. |
| `Models.swift` | `ContentKind` (podcast, livre, réunion, cours, idées), `Category`, `Doc`, `Part`, `Writeup`, `Synthesis`. |
| `Store.swift` | Sauvegarde JSON (Application Support), `Settings` (UserDefaults) et `Keychain` (clé API). |
| `Files.swift` | Écriture des fichiers Markdown dans Documents, visibles dans l'app Fichiers. |
| `ListenView.swift` | Onglet **Écoute** : catégories (+ pour ajouter, réglette pour gérer, appui long pour modifier/supprimer), GO, titre facultatif, « Reprendre » (3 dernières écoutes de la catégorie, un tap = reprise). Puis vue « direct » où le résumé se construit. |
| `LibraryView.swift` | Onglet **Bibliothèque** : catégories en tuiles, récents, « Idées à retenir », recherche dans tout le contenu (titres, idées, leçons). Navigation par `LibRoute` (catégorie, enregistrement, partie). |
| `DocView.swift` | Page d'un enregistrement avec onglets **Résumé / À retenir / Leçons (ou Décisions) / Citations**, et `PartView` : une page par partie (précédente/suivante). Actions dans le menu ⋯. |
| `SettingsView.swift` | Réglages, `CategoriesList` (ajouter, modifier, corbeille visible) et `CategoryEditor`. |
| `Components.swift` | Composants partagés : `.card()`, `CategoryChip`, `PulseDot`, `ListeningBars`, `WriteupView`, `BannerView`, `ShareSheet`, `Color(hex:)`. |

## Le parcours d'une écoute

1. Le micro est transcrit sur l'iPhone, phrase par phrase.
2. Toutes les ~60 s (`chunkSeconds`, ou dès 320 mots), le morceau part chez **Claude Haiku** (`modelNotes`).
   Claude renvoie du texte nettoyé, des notes détaillées, des citations, des références et `nouveau_sujet`.
3. Quand le sujet change (ou au bouton « Nouvelle partie »), la partie est rédigée par **Claude Sonnet** (`modelWrite`)
   à partir de ses notes, en **fiche courte et structurée** : titre, chapeau, à retenir (3-5 points),
   `sections` (2 à 5 intertitres + paragraphe de 2-4 phrases, ~12 mots par note, 80 à 450 mots), puis rubriques.
4. À l'arrêt, une synthèse est rédigée : paragraphe court (80 mots max), à retenir (5-8), **leçons** avec mise en pratique,
   pistes pour aller plus loin. Puis les fichiers sont écrits et le document s'ouvre.

## Décisions prises (ne pas défaire sans demander)

- **La qualité du document final passe avant la vitesse.** Pas de flux de texte en continu à l'écran : on montre le résumé qui se construit.
- **Notes prises en direct toutes les ~60 s**, pour ne pas perdre de détails. Pas de résumé unique à la fin.
- **Un enregistrement = un dossier** : `00 - Sommaire.md` (synthèse + liens), fiches thématiques numérotées
  (`À retenir`, `Leçons` ou `Décisions et actions`, `Citations et références`, `Glossaire`, seulement s'il y a de la matière)
  et un sous-dossier `Parties/` avec **un fichier par partie**. Jamais un gros fichier unique.
- Format (choix de Killian, 22/11) : **court, organisé, structuré**. Fiches avec intertitres plutôt qu'un long compte rendu en prose.
- **L'interface s'explique d'elle-même** : pas d'encadrés ni de phrases d'explication. Icônes, libellés courts, états clairs.
- La bibliothèque doit donner l'impression d'une **bibliothèque de connaissances** (idées, leçons), pas d'une liste d'enregistrements.
- **2 onglets** seulement : Écoute et Bibliothèque. Les réglages sont derrière ⚙️.
- **Claude est obligatoire** (clé API de Killian, stockée dans le trousseau). Pas de compte ni de mot de passe dans l'app.
- La transcription reste **sur l'iPhone**. Seul le texte part chez Claude, jamais l'audio.
- L'écoute doit continuer **écran verrouillé et dans une autre app**, sans couper le son en cours :
  session audio `.playAndRecord` + `.mixWithOthers`, mode d'arrière-plan « Audio » dans Info.plist.
  Ne pas cocher d'autres modes d'arrière-plan (l'envoi TestFlight échouerait).
- iOS 26 minimum, iPhone uniquement, portrait.

## Interface (règles visuelles)

- SwiftUI natif, couleurs système (`secondarySystemGroupedBackground`…), mode sombre automatique.
- Cartes : coins arrondis de 18, style `.continuous`, marge intérieure de 16 (`.card()`).
- Chaque catégorie a sa couleur (`colorHex`). Elle sert de pastille, de puce sélectionnée et d'accent du bouton GO.
- Bouton GO : gros, arrondi, police `.rounded` épaisse. C'est l'action principale de l'accueil.
- Textes longs (compte rendu) : `.body`, interligne de 4, lisibilité avant tout.
- Prévoir les états vides, les erreurs (clé manquante, pas de réseau) et l'accessibilité (Dynamic Type, VoiceOver).

## Envoi d'une nouvelle version sur l'iPhone

- Double-cliquer **`Envoyer sur TestFlight.command`** dans le Finder (dossier `ios/Ecoute`).
  Le script archive, signe et envoie. Le numéro de build est automatique (date et heure).
- Signature : Debug en automatique, **Release en manuel** avec le certificat « Apple Distribution »
  et le profil **« Nown app store »** (équipe 4RD599TFA2). Il n'y a aucun iPhone enregistré sur le compte :
  ne pas repasser Release en signature automatique.
- L'abonnement Apple Developer expire le 16/12/2026. Sans renouvellement, TestFlight cessera de fonctionner.

## Autre partie du dépôt

À la racine : `index.html`, l'ancienne version web (GitHub Pages). Elle a été abandonnée pour l'écoute en arrière-plan,
qui est impossible dans Safari. Elle reste utile comme référence des prompts et du rendu.
