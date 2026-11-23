#!/bin/zsh
# Builds NotchCue and wraps it into build/NotchCue.app (needed for mic/speech permissions).
# Optional: export NOTCHCUE_SIGN_ID="NotchCue Dev" to sign with a stable identity.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/NotchCue"

APP=build/NotchCue.app
# Start from an empty bundle so nothing stale from an earlier build gets signed.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchCue"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Bundle fonts (any depth under Resources/Fonts) flat, plus their licence files.
mkdir -p "$APP/Contents/Resources/Fonts"
if [[ -d Resources/Fonts ]]; then
  find Resources/Fonts -type f \( -name '*.otf' -o -name '*.ttf' -o -iname 'OFL*' -o -iname 'LICENSE*' \) \
    -exec cp {} "$APP/Contents/Resources/Fonts/" \;
fi

codesign --force --sign "${NOTCHCUE_SIGN_ID:--}" "$APP"
echo "Built $APP"
