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

- Keep it light: no Electron, no web views, no bundled models. Idle footprint was 15 MB on
  2026-10-13; treat a rise past 60 MB as a regression.
- Everything stays on the Mac. No network calls, accounts, telemetry or auto-update.
- Clean-room: nothing copied from Typeless (code, prompts, assets, helper libraries), and
  no calls to its servers. `docs/findings.md` records behaviour only.
- Pure logic goes in `Sources/HarkCore` with tests. Anything touching AppKit, audio, the
  event tap or Apple's models goes in `Sources/hark`.
- The language model is opt-in ("polish"). Do not make it the default path without
  re-measuring: 4 to 8 seconds for 50 words on an M1, and it once answered a dictated
  question instead of cleaning it. `TextCleaner.isPlausibleRefinement` is the guard; keep
  its tests passing.
- Measure before claiming: latency in milliseconds, memory with `footprint`, insertion by
  reading the target document back.

## Known gaps

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
