APP := build/hark.app
BIN := .build/release/hark
FIXTURE := build/fixture.wav

# Sign with a real identity when one exists, so macOS keeps the Microphone and
# Accessibility grants across rebuilds. Falls back to ad-hoc signing ("-"), which works
# but asks for those permissions again after every rebuild.
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $$2; exit}')
SIGN_ID := $(if $(SIGN_ID),$(SIGN_ID),-)

.PHONY: build app install test verify clean

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BIN) $(APP)/Contents/MacOS/hark
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign "$(SIGN_ID)" $(APP)
	@echo "built $(APP), signed with: $(SIGN_ID)"

install: app
	-pkill -x hark
	ditto $(APP) /Applications/hark.app
	open /Applications/hark.app
	@echo "installed /Applications/hark.app and started it"

test:
	swift test

# End-to-end check of the speech path without a microphone: synthesise a sentence,
# transcribe it, and compare the words.
verify: build
	mkdir -p build
	say -o $(FIXTURE) --data-format=LEI16@16000 "Please send the notes to the whole team before Friday."
	@out="$$($(BIN) --transcribe-file $(FIXTURE))"; echo "heard: $$out"; \
	  echo "$$out" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]' | grep -q "please send the notes to the whole team before friday" \
	  && echo "verify: PASS" || { echo "verify: FAIL"; exit 1; }
	$(BIN) --doctor

clean:
	rm -rf .build build
