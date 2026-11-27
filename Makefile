.PHONY: help setup check build release
help:
	@printf '%s\n' 'setup: restore locked Flutter dependencies' 'check: Dart format and analysis' \
		'build: debug universal APK' 'release: signed ARMv7/ARM64/x86_64 APKs + release.json + SHA256SUMS'
setup:
	flutter --no-version-check pub get --enforce-lockfile
check: setup
	dart format --output=none --set-exit-if-changed lib
	flutter --no-version-check analyze --no-pub
build: setup
	sh scripts/build-apk.sh debug
release: setup
	sh scripts/build-apk.sh release
