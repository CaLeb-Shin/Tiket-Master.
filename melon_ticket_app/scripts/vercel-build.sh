#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_ROOT="${FLUTTER_ROOT:-$HOME/flutter-sdk}"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"

if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  git clone --depth 1 --branch "$FLUTTER_CHANNEL" https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
fi

export PATH="$FLUTTER_ROOT/bin:$PATH"

flutter config --enable-web
flutter --version

cd "$APP_DIR"
flutter pub get
flutter build web --release --pwa-strategy=none
