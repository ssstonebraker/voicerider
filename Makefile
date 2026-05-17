# VoiceRider — build & bundle
#
# Targets:
#   make            → build .app bundle
#   make run        → build + launch
#   make test       → run unit tests (no permissions required)
#   make verify     → build with zero warnings + run tests (pre-commit gate)
#   make verify-strict → opt-in: -strict-concurrency=complete (informational, R4-F33)
#   make reset-tcc  → revoke all TCC permissions for com.voicerider
#   make clean      → remove .build/ and VoiceRider.app

APP        := VoiceRider.app
BIN        := .build/release/VoiceRider
BUNDLE     := $(APP)/Contents
IDENTIFIER := com.voicerider

SWIFT_FILES := $(wildcard Sources/VoiceRider/*.swift)

.PHONY: all run test verify verify-strict reset-tcc clean

all: $(APP)

$(BIN): $(SWIFT_FILES) Package.swift
	swift build -c release

# Render Resources/Info.plist from the template using $VOICERIDER_LAN_HOST
# (or the value in .env.local). Gitignored so your LAN host doesn't leak.
Resources/Info.plist: Resources/Info.plist.template scripts/render-info-plist.sh .env.local.example
	./scripts/render-info-plist.sh

# F14: dropped `--deep`. Single Mach-O bundle has no nested signed code.
$(APP): $(BIN) Resources/Info.plist Resources/AppIcon.icns Resources/RecordingOverlay.pdf
	rm -rf $(APP)
	mkdir -p $(BUNDLE)/MacOS $(BUNDLE)/Resources
	cp $(BIN) $(BUNDLE)/MacOS/VoiceRider
	cp Resources/Info.plist $(BUNDLE)/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE)/Resources/
	cp Resources/RecordingOverlay.pdf $(BUNDLE)/Resources/
	codesign --force --sign - --identifier $(IDENTIFIER) $(APP)
	@echo
	@echo "Built $(APP) (identifier: $(IDENTIFIER))"

run: $(APP)
	open $(APP)

test:
	swift test

# §C.14 #5 verdict: yes, add `make verify`. Build with -c release; fail
# if any compiler warning slipped through; then run tests.
verify:
	@set -e; \
	  TMP=$$(mktemp); \
	  swift build -c release 2>&1 | tee $$TMP; \
	  if grep -E '^(.*: )?warning:' $$TMP >/dev/null; then \
	    echo "verify: refusing — release build emitted warnings"; \
	    rm -f $$TMP; exit 1; \
	  fi; \
	  rm -f $$TMP
	swift test
	@echo "verify: OK"

# R4-F33: opt-in informational check. Apple's AVFoundation /
# CoreFoundation imports are not Sendable-clean, so this is expected to
# emit warnings under macOS 13. Tracked for v0.2.0 adoption.
verify-strict:
	@echo "verify-strict: building with -strict-concurrency=complete (informational)"
	@swift build -c release -Xswiftc -strict-concurrency=complete 2>&1 | tee /tmp/voice-strict.log; \
	  COUNT=$$(grep -cE '^(.*: )?warning:' /tmp/voice-strict.log || true); \
	  echo "verify-strict: $$COUNT warning(s) under strict concurrency"
	@echo "verify-strict: done (informational, not gating for v1.x)"

reset-tcc:
	-tccutil reset Accessibility   $(IDENTIFIER)
	-tccutil reset ListenEvent     $(IDENTIFIER)
	-tccutil reset Microphone      $(IDENTIFIER)
	@echo "TCC permissions reset for $(IDENTIFIER)"

clean:
	rm -rf .build $(APP)
