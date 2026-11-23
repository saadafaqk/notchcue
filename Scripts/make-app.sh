#!/bin/zsh
# Builds NotchCue and wraps it into build/NotchCue.app (needed for mic/speech permissions).
# Optional: export NOTCHCUE_SIGN_ID="NotchCue Dev" to sign with a stable identity.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/NotchCue"

APP=build/NotchCue.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchCue"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -d Resources/Fonts ]] && [[ -n "$(ls -A Resources/Fonts 2>/dev/null)" ]]; then
  mkdir -p "$APP/Contents/Resources/Fonts"
  cp Resources/Fonts/* "$APP/Contents/Resources/Fonts/"
fi

codesign --force --sign "${NOTCHCUE_SIGN_ID:--}" "$APP"
echo "Built $APP"
