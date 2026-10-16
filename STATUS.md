# Status

> Updated: 2026-10-13

## Where we are
hark is installed at `/Applications/hark.app` and in daily-use shape for Rainier: hold or tap Fn, speak, text is pasted at the cursor. Speech and cleanup run on the Mac, nothing is paid for and nothing leaves the machine. The private remote `SingularityAI-Dev/talk-is-nice` is at `2e71c44` (the app is still named hark).

## Recent
- Confirmed by Rainier with real speech on 2026-10-13: dictation, tap to toggle hands-free, muting of other audio, no emoji picker on Fn.
- Accent mishearing measured on his voice ("testing" heard as "tasting"): Apple en-ZA and en-GB 1 of 2, en-US and en-AU 0 of 2, whisper.cpp small.en 0 of 2 and about five times slower; the dictionary changed nothing. Decision: keep en-ZA and fix mishearings with the Corrections list.
- `tasting = testing` is stored in his app settings. Confirmed by Rainier on a live dictation on 2026-10-13.

## Next
- Find out whether the friend's Mac runs macOS 26; there is no fallback speech engine below it.
- Prove `make install`'s globe key step on a fresh Mac (on this one the option was set through HIToolbox's own setter, then the agent was killed).
- Still owed from the original plan: key release to text latency (median of 10), a screen recording in `docs/`, insertion checks in an Electron app and a browser field, a microphone picker test.
- Known limit: the paste uses a fixed V key code, so non-QWERTY layouts may paste the wrong key.
