#!/usr/bin/env bash
set -euo pipefail

echo "Running setup: installing Dart/Flutter deps and installing git hooks..."
flutter pub get
./scripts/install-hooks.sh
echo "Setup complete."
