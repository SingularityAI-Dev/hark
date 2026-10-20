# hark

Personal macOS dictation app for Rainier and one friend. Never distributed, never sold.
Native Swift, menu bar only, zero third-party dependencies. See `README.md` for use and
`docs/findings.md` for the Typeless study it was designed from.

## Commands

- `make test`: unit tests (`HarkCore`).
- `make verify`: end-to-end speech check without a microphone, including the live path.
- `make install`: build, sign, copy to `/Applications`, relaunch.
- `/Applications/hark.app/Contents/MacOS/hark --doctor`: what this Mac supports.

## Rules

- Keep it light: no Electron, no web views, no bundled models. Footprint on 2026-10-14:
  14 MB at launch, about 36 MB with the hark window open, 33 MB after closing it (SwiftUI
  stays loaded once used; flat over repeated opens). Treat a rise past 60 MB as a regression.
- Nothing leaves the Mac by default. The one exception, chosen by Rainier on 2026-10-14:
  polish may go to an OpenAI-compatible server set in Settings (FreeLLMAPI in Docker at
  localhost:3001, which forwards to free cloud providers). Keep it opt-in per Mac, keep the
  key in the keychain, and keep the instant-cleanup fallback. No accounts, telemetry or
  auto-update.
- Clean-room: nothing copied from Typeless (code, prompts, assets, helper libraries), and
  no calls to its servers. `docs/findings.md` records behaviour only.
- Pure logic goes in `Sources/HarkCore` with tests. Anything touching AppKit, audio, the
  event tap or Apple's models goes in `Sources/hark`.
- Polish is on by default since 2026-10-14 (Shift skips it). `make eval` is the check
  (24 cases). It runs Apple's on-device model unless `HARK_POLISH_URL` and
  `HARK_POLISH_KEY` are set, so set them to measure the server. On 2026-10-20: FreeLLMAPI
  `auto` 22 of 24 and then 17 of 24, the misses being almost all 10 s timeouts (the free
  upstream is slow under load, and a timeout pastes the rule-cleaned text); Apple
  on-device 18 of 24. Apple's model once answered a dictated question instead of cleaning
  it. `TextCleaner.isPlausibleRefinement` is the guard; keep its tests passing.
- Measure before claiming: latency in milliseconds, memory with `footprint`, insertion by
  reading the target document back.

## Known gaps

- Accent mishearings are fixed with the Corrections list, not by changing engine. Measured
  on Rainier's voice on 2026-10-13 ("testing" heard as "tasting"): Apple en-ZA and en-GB
  got 1 of 2, en-US and en-AU 0 of 2, whisper.cpp small.en 0 of 2 and five times slower.
  Adding the word to the dictionary (the recogniser's contextual strings) changed nothing.

- The live path is checked without a microphone by `make verify` (`--stream-file` feeds a
  file through the same code). The hotkey itself and real speech are only checked by hand.
- Apple's analyser never finishes when it was given no audio at all (a key press shorter
  than the first microphone buffer). `AppleTranscriber.finish` returns early in that case
  and puts a deadline on every other finalise; `make verify` covers it. Do not remove
  either without rerunning that check.
- Fn on its own opens the macOS emoji picker. Consuming the Fn event in the event tap,
  at session or HID level, does not stop it (tried 2026-10-13, macOS 26.6). The keyboard
  setting does, and `make install` sets it. The agent that opens the picker
  (`TextInputSwitcher`) caches the setting and ignores SIGTERM, so a plain `defaults write`
  changes nothing until it is killed with -9. A synthetic Fn press never opens the picker,
  so this can only be checked with the physical key.
- No fallback speech engine for Macs older than macOS 26.
- The paste uses a fixed V key code, so non-QWERTY layouts may paste the wrong key.
