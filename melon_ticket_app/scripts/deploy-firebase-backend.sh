#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${1:-melon-ticket-mvp-2026}"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$APP_DIR"

firebase deploy \
  --project "$PROJECT_ID" \
  --only firestore:rules,firestore:indexes,functions
