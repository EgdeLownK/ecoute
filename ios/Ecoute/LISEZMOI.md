# Écoute — app iPhone

App iPhone (SwiftUI, iOS 26 ou plus récent) qui écoute en arrière-plan, transcrit sur l'iPhone avec le moteur d'Apple,
puis prend des notes, découpe par sujet et rédige un compte rendu par partie avec Claude (clé API Anthropic).

- Écoute écran verrouillé ou dans une autre app, sans couper le livre audio ou le podcast en cours de lecture.
- Fichiers Markdown dans l'app Fichiers : Sur mon iPhone › Écoute › Catégorie › Enregistrement
  (00 - Sommaire.md + une fiche par partie).
- Clé API rangée dans le trousseau de l'iPhone.

## Installer sur ton iPhone

1. Installe **Xcode** (gratuit) depuis le Mac App Store, ouvre-le une fois et accepte l'installation des composants iOS.
2. Ouvre **Ecoute.xcodeproj** (double-clic).
3. Xcode › Réglages › Comptes › **+** › Apple ID : connecte-toi avec ton identifiant Apple habituel.
4. Dans Xcode, clique sur **Ecoute** (icône bleue en haut à gauche) › cible **Ecoute** › onglet **Signing & Capabilities** ›
   **Team** : choisis « Ton nom (Personal Team) ».
   Si Xcode dit que l'identifiant « fr.egdelownk.ecoute » n'est pas disponible, remplace-le par exemple par « fr.tonprenom.ecoute ».
5. Branche l'iPhone au Mac avec un câble, déverrouille-le et touche **Faire confiance**.
6. Sur l'iPhone : Réglages › Confidentialité et sécurité › **Mode développeur** › activer, puis redémarrer.
7. Dans Xcode, en haut, choisis ton iPhone comme destination, puis clique sur **▶** (ou Cmd + R).
8. Si l'iPhone affiche « Développeur non approuvé » : Réglages › Général › VPN et gestion de l'appareil ›
   ton identifiant › **Faire confiance**, puis relance l'app.
9. Dans l'app : ⚙️ › colle ta clé API Anthropic, choisis la catégorie, appuie sur **GO** et accepte le micro.

Avec un compte Apple gratuit, l'app doit être réinstallée environ tous les 7 jours : rebranche l'iPhone et reclique sur ▶.
