#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mode=${1:-debug}
case "$mode" in debug|release) ;; *) echo "Expected debug or release" >&2; exit 1;; esac
if [ "$mode" = release ]; then
  version=$(python3 scripts/build_version.py --required)
else
  version=$(python3 scripts/build_version.py)
fi
export SINGVERSE_VERSION="$version"
code=$(python3 -c 'import sys; major,minor,patch=map(int,sys.argv[1].split(".")); print(max(1,major*1000000+minor*1000+patch))' "$version")
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
