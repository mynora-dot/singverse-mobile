.PHONY: help setup check build release native-check audio-test release-check
help:
	@printf '%s\n' 'setup: restore locked Flutter dependencies' 'check: Dart format/analyze/tests and Android unit tests' 'build: debug universal APK' 'release: signed universal APK + release.json + SHA256SUMS' 'audio-test: isolated Android instrumentation (requires device)'
setup:
	flutter --no-version-check pub get --enforce-lockfile
check: setup
	dart format --output=none --set-exit-if-changed lib test integration_test
	flutter --no-version-check analyze --no-pub
	flutter --no-version-check test --no-pub
	$(MAKE) native-check release-check
release-check:
	python3 -m unittest discover -s scripts/tests -p 'test_*.py'
native-check:
	cd android && ./gradlew :app:testDebugUnitTest
build: setup
	sh scripts/build-apk.sh debug
release: setup
	sh scripts/build-apk.sh release
audio-test:
	cd android && ORG_GRADLE_PROJECT_singverseE2e=true ./gradlew :app:connectedDebugAndroidTest
