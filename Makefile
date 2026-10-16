APP := build/hark.app
BIN := .build/release/hark
FIXTURE := build/fixture.wav
EMPTY := build/empty.wav
EXPECTED := please send the notes to the whole team before friday

# Sign with a real identity when one exists, so macOS keeps the Microphone and
# Accessibility grants across rebuilds. Falls back to ad-hoc signing ("-"), which works
# but asks for those permissions again after every rebuild.
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $$2; exit}')
SIGN_ID := $(if $(SIGN_ID),$(SIGN_ID),-)

.PHONY: build app install test verify eval clean

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/hark
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign "$(SIGN_ID)" $(APP)
	@echo "built $(APP), signed with: $(SIGN_ID)"

# Fn pressed on its own opens the macOS emoji picker, which then also swallows the pasted
# text. The keyboard setting "Press globe key to: Do Nothing" is the only thing that stops
# it. The agent that opens the picker caches the setting and ignores a polite quit, so it
# is killed outright; macOS starts a fresh one on the next Fn press.
install: app
	-pkill -x hark
	ditto $(APP) /Applications/hark.app
	defaults write com.apple.HIToolbox AppleFnUsageType -int 0
	-killall -9 TextInputSwitcher 2>/dev/null
	open /Applications/hark.app
	@echo "installed /Applications/hark.app and started it"

test:
	swift test

# End-to-end check of the speech path without a microphone: synthesise a sentence,
# transcribe it as a file and through the path live dictation uses, and compare the words.
# The last check feeds a recording with no audio in it, which once hung forever; perl's
# alarm kills it after 15 seconds if that ever comes back.
verify: build
	mkdir -p build
	say -o $(FIXTURE) --data-format=LEI16@16000 "Please send the notes to the whole team before Friday."
	printf 'RIFF\044\000\000\000WAVEfmt \020\000\000\000\001\000\001\000\200\076\000\000\000\175\000\000\002\000\020\000data\000\000\000\000' > $(EMPTY)
	@for mode in --transcribe-file --stream-file; do \
	  out="$$($(BIN) $$mode $(FIXTURE))"; echo "$$mode heard: $$out"; \
	  echo "$$out" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]' | grep -q "$(EXPECTED)" \
	  && echo "verify $$mode: PASS" || { echo "verify $$mode: FAIL"; exit 1; }; \
	done
	@perl -e 'alarm 15; exec @ARGV' $(BIN) --stream-file $(EMPTY) \
	  && echo "verify no-audio: PASS" || { echo "verify no-audio: FAIL"; exit 1; }
	$(BIN) --doctor

# Hesitation and self-correction cases through the on-device model. Needs Apple
# Intelligence; output can shift between macOS releases, so rerun it after updates.
eval: build
	./scripts/eval-polish.sh $(BIN)

clean:
	rm -rf .build build
