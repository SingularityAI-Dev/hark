# Changelog

> Last 20 changes. Full history in git.

- 2026-10-14: Polish on by default and smarter: drops what you take back and half-finished phrases; optional OpenAI-compatible polish server (FreeLLMAPI `auto`: 15 of 15 on `make eval`); instant cleanup removes repeated phrases, "ah" and filler "you know"; gentle synthesised start and finish chimes; new menu bar icon
- 2026-10-14: hark window (menu > Open hark…): Home stats with period picker, streaks and a words-per-day grid; searchable History with retention setting; Dictionary page. History now records speaking time for words per minute
- 2026-10-14: README reworked with animated diagrams in `docs/assets/`
- 2026-10-13: Corrections list added (Settings > Corrections, `heard = meant` per line), applied to the raw transcript before cleanup; `--stream-file` passes the dictionary through (`2e71c44`)
- 2026-10-13: Tap Fn (under 0.35 s) now locks hands-free, next press finishes; hold still works (`804cc31`)
- 2026-10-13: Other audio is muted while dictating and restored afterwards, with a Settings toggle (`804cc31`)
- 2026-10-13: Fixed a permanent "Cleaning up" hang after a key press shorter than the first microphone buffer; every finalise now has a 10 s deadline (`804cc31`)
- 2026-10-13: `make install` sets the macOS globe key to Do Nothing and restarts `TextInputSwitcher`, so Fn no longer opens the emoji picker (`804cc31`)
- 2026-10-13: Timing-only logging under subsystem `dev.hark.app` (`804cc31`)
- 2026-10-13: First version: menu bar dictation app on Apple's on-device speech recogniser, rule-based cleanup, opt-in model polish (`2ee4fda`)
