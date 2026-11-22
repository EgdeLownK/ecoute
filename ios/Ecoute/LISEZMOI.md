# Écoute — app iPhone

App iPhone (SwiftUI, iOS 26 ou plus récent) qui écoute en arrière-plan, transcrit sur l'iPhone avec le moteur d'Apple,
puis prend des notes, découpe par sujet et rédige un compte rendu par partie avec Claude (clé API Anthropic).

- Écoute écran verrouillé ou dans une autre app, sans couper le livre audio ou le podcast en cours de lecture.
- Fichiers Markdown dans l'app Fichiers : Sur mon iPhone › Écoute › Catégorie › Enregistrement
  (00 - Sommaire.md + une fiche par partie).
- Clé API rangée dans le trousseau de l'iPhone.

## Installer sans câble, via TestFlight (compte Apple Developer payant)

### Une seule fois

1. Installe **Xcode** (gratuit) depuis le Mac App Store, ouvre-le et accepte les composants iOS.
2. Xcode › Réglages › **Comptes** › **+** › Apple ID : connecte-toi avec le compte Apple Developer.
3. Ouvre **Ecoute.xcodeproj**. Clique sur **Ecoute** (icône bleue en haut à gauche) › cible **Ecoute** ›
   **Signing & Capabilities** › **Team** : choisis ton équipe (ton nom, *pas* « Personal Team »).
   Si l'identifiant `fr.egdelownk.ecoute` est refusé, remplace-le, par exemple par `fr.tonprenom.ecoute`.
4. Sur [appstoreconnect.apple.com](https://appstoreconnect.apple.com) › **Apps** › **+** › **Nouvelle app** :
   plateforme iOS, nom « Écoute » (ou « Écoute notes » si le nom est pris), langue Français,
   identifiant de lot = celui de l'étape 3, SKU = `ecoute1`. Accès complet.
5. Sur l'iPhone, installe l'app **TestFlight** depuis l'App Store.

### Envoyer une version (le plus simple)

Dans le Finder, ouvre le dossier `ios/Ecoute` et double-clique sur **Envoyer sur TestFlight.command**.
Une fenêtre s'ouvre, archive l'app puis l'envoie. Le numéro de build se met tout seul.
La première fois, si macOS bloque le fichier : clic droit › **Ouvrir** › **Ouvrir**.

### Envoyer une version depuis Xcode

1. En haut de Xcode, choisis la destination **Any iOS Device (arm64)**.
2. Menu **Product › Archive**. Attends la fin (quelques minutes la première fois).
3. La fenêtre Organizer s'ouvre : **Distribute App** › **TestFlight Internal Only** › **Distribute**.
4. Attends 5 à 30 minutes que la version passe « Prête à tester » dans App Store Connect › ton app › **TestFlight**.
5. Toujours dans TestFlight › **Test interne** › **+** : crée un groupe, ajoute-toi comme testeur (ton adresse du compte).
6. Sur l'iPhone, ouvre **TestFlight** (ou le mail d'invitation) › **Installer**.

Pour une nouvelle version : onglet **General** › Identity › **Build**, passe à 2, puis 3, 4…, et refais Product › Archive. TestFlight propose la mise à jour tout seul.
Une version TestFlight reste installable 90 jours.

### Dans l'app

⚙️ › colle ta clé API Anthropic, choisis la catégorie, appuie sur **GO** et accepte le micro et la reconnaissance vocale.

## Installer avec un câble (compte gratuit)

1. Étapes 1 à 3 ci-dessus, avec « Ton nom (Personal Team) » comme Team.
2. Branche l'iPhone, déverrouille-le et touche **Faire confiance**.
3. Sur l'iPhone : Réglages › Confidentialité et sécurité › **Mode développeur** › activer, puis redémarrer.
4. Dans Xcode, choisis ton iPhone comme destination, puis **▶** (Cmd + R).
5. Si l'iPhone affiche « Développeur non approuvé » : Réglages › Général › VPN et gestion de l'appareil ›
   ton identifiant › **Faire confiance**.

Avec un compte gratuit, il faut réinstaller environ tous les 7 jours.
