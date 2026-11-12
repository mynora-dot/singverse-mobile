#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
version=$(cat VERSION)
code=$(python3 -c 'import sys; sys.path.insert(0,"scripts"); from importlib.machinery import SourceFileLoader; print(SourceFileLoader("release","scripts/prepare-release.py").load_module().version_code(sys.argv[1]))' "$version")
mode=${1:-debug}
case "$mode" in debug|release) ;; *) echo "Expected debug or release" >&2; exit 1;; esac
# Flutter regenerates the native plugin registrant for the selected build mode
# only when pub is enabled. Keep dev-only integration_test out of release APKs.
lock_snapshot=$(mktemp)
cp pubspec.lock "$lock_snapshot"
trap 'rm -f "$lock_snapshot"' EXIT HUP INT TERM
flutter --no-version-check build apk --"$mode" --build-name "$version" --build-number "$code"
if ! cmp -s "$lock_snapshot" pubspec.lock; then
  echo 'Build changed pubspec.lock; restore and review locked dependencies' >&2
  exit 1
fi
if [ "$mode" = release ]; then
  python3 scripts/prepare-release.py --platform mobile --apk build/app/outputs/flutter-apk/app-release.apk --output build/mobile-release
fi
