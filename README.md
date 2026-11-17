# Écoute & Résumé

Application web en un seul fichier (`index.html`) : écoute en continu, filtre le bruit ambiant et les voix lointaines, découpe automatiquement par sujet et produit un résumé structuré pour chaque partie.

- Catégories avec un type de contenu (podcast / vidéo, réunion, cours, idées) qui choisit le modèle de notes
- Prise de notes en trois étages avec Claude (clé API Anthropic stockée uniquement dans le navigateur) :
  1. toutes les ~60 s, l'extrait transcrit devient du texte nettoyé + des notes détaillées + citations + références, et Claude repère les changements de sujet ;
  2. à chaque changement de sujet, la partie est rédigée en compte rendu à partir des notes (pas de la transcription brute) ;
  3. à l'arrêt, une synthèse du document est ajoutée au sommaire
- Un document = un dossier : `00 - Sommaire.md` + une partie par sujet (compte rendu, à retenir, citations, références, notes et transcription repliées)
- Sur ordinateur (Chrome / Edge) : écriture directe dans un dossier choisi ; ailleurs : export .md / .zip

Fonctionne dans Chrome, Edge et Safari (pas Firefox). Le micro nécessite une adresse en https, fournie par GitHub Pages.
