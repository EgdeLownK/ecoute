#!/bin/zsh
# Double-clic dans le Finder : archive l'app et l'envoie sur TestFlight.
# Le numéro de build est automatique (date et heure), rien à changer à la main.

cd "$(dirname "$0")" || exit 1

TEAM="4RD599TFA2"
PROFILE="Nown app store"
BUNDLE="fr.egdelownk.ecoute"
BUILD="$(date +%Y%m%d.%H%M)"
WORK="$(mktemp -d /tmp/ecoute-envoi.XXXXXX)"
ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/Ecoute $BUILD.xcarchive"

fin() {
  echo
  if [ "$1" = "ok" ]; then
    echo "✅ C'est envoyé. La version $BUILD apparaîtra dans TestFlight d'ici 5 à 30 minutes."
  else
    echo "❌ $1"
    echo "   Copie les lignes rouges au-dessus et envoie-les à Claude."
  fi
  echo
  read -k 1 "?Appuie sur une touche pour fermer cette fenêtre…"
  exit 0
}

echo "📦 1/2 — Archivage de l'app (build $BUILD)… ça prend 1 à 3 minutes."
xcodebuild -project Ecoute.xcodeproj -scheme Ecoute -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" -quiet archive \
  || fin "L'archivage a échoué."

cat > "$WORK/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key><dict><key>$BUNDLE</key><string>$PROFILE</string></dict>
  <key>testFlightInternalTestingOnly</key><true/>
</dict></plist>
EOF

echo "🚀 2/2 — Envoi vers App Store Connect…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$WORK/export.plist" -exportPath "$WORK/export" \
  -allowProvisioningUpdates 2>&1 | grep -E "error|Error|Upload succeeded|EXPORT" \
  ; [ "${pipestatus[1]}" -eq 0 ] || fin "L'envoi a échoué."

fin ok
