#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_SRC="$ROOT_DIR/scripts/pre-commit"
HOOK_DEST="$ROOT_DIR/.git/hooks/pre-commit"

if [ ! -f "$HOOK_SRC" ]; then
  echo "Hook source not found: $HOOK_SRC"
  exit 1
fi

cp "$HOOK_SRC" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
echo "Pre-commit hook installed to $HOOK_DEST"
