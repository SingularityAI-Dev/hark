# hark

Personal macOS dictation app for Rainier and one friend. Never distributed, never sold.
Native Swift, menu bar only, zero third-party dependencies. See `README.md` for use and
`docs/findings.md` for the Typeless study it was designed from.

## Commands

- `make test`: unit tests (`HarkCore`).
- `make verify`: end-to-end speech check without a microphone.
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

- The live hotkey and microphone path has no automated test, and as of 2026-10-13 had not
  been run by hand either: it needs the Microphone and Accessibility grants first.
- No fallback speech engine for Macs older than macOS 26.
- The paste uses a fixed V key code, so non-QWERTY layouts may paste the wrong key.
