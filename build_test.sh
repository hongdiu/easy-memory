#!/usr/bin/env bash
set -euo pipefail

echo "=== flutter pub get ==="
flutter pub get

echo "=== flutter analyze ==="
flutter analyze

echo "=== flutter test ==="
flutter test