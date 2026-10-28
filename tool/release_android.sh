#!/usr/bin/env bash
#
# Zgradi in razdeli novo izdajo zaposlenim prek Firebase App Distribution.
#
#   ./tool/release_android.sh "Kaj je novega v tej izdaji"
#
# Predpogoji (enkratna nastavitev, glej plan.md 4.3):
#   - android/key.properties s podpisnim ključem
#   - firebase login
#   - v Firebase konzoli vključen App Distribution in skupina "zaposleni"

set -euo pipefail

cd "$(dirname "$0")/.."

RELEASE_NOTES="${1:-}"
GROUP="zaposleni"

if [[ ! -f android/key.properties ]]; then
  echo "NAPAKA: android/key.properties ne obstaja."
  echo "Brez podpisnega ključa bi se izdaja podpisala z razvojnim ključem"
  echo "in je zaposleni ne bi mogli nadgraditi. Glej plan.md, razdelek 4.3."
  exit 1
fi

# Številko izdaje (+N v pubspec.yaml) je treba dvigniti pri vsaki izdaji,
# sicer App Distribution novo izdajo obravnava kot isto kot prejšnjo.
VERSION_LINE=$(grep '^version:' pubspec.yaml)
echo "Gradim: $VERSION_LINE"

# Samo arm64 — vsi telefoni zadnjih let. Univerzalni APK je ~75 MB,
# ta pa ~30 MB, kar je občutno hitreje prenesti na terenu.
flutter build apk --release --target-platform android-arm64

APK="build/app/outputs/flutter-apk/app-release.apk"

# Varovalka: preveri, da izdaja NI podpisana z razvojnim ključem.
APKSIGNER=$(ls "$HOME"/Library/Android/sdk/build-tools/*/apksigner 2>/dev/null | tail -1)
if [[ -n "$APKSIGNER" ]]; then
  if "$APKSIGNER" verify --print-certs "$APK" | grep -q "CN=Android Debug"; then
    echo "NAPAKA: izdaja je podpisana z RAZVOJNIM ključem — ne razdeljuj je."
    exit 1
  fi
fi

echo "Nalagam v App Distribution (skupina: $GROUP)..."
firebase appdistribution:distribute "$APK" \
  --app "1:450584317434:android:ed06d60f4f17987ae3e843" \
  --groups "$GROUP" \
  --release-notes "$RELEASE_NOTES"

echo "Končano. Zaposleni dobijo obvestilo po e-pošti."
