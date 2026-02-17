#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.1}"
FLUTTER_ROOT="${FLUTTER_ROOT:-$HOME/flutter-sdk-$FLUTTER_VERSION}"

if [[ -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  if ! "$FLUTTER_ROOT/bin/flutter" --version 2>/dev/null | grep -q "Flutter $FLUTTER_VERSION"; then
    rm -rf "$FLUTTER_ROOT"
  fi
fi

if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
fi

export PATH="$FLUTTER_ROOT/bin:$PATH"

flutter config --enable-web
flutter --version

cd "$APP_DIR"
flutter pub get
flutter build web --release --pwa-strategy=none
