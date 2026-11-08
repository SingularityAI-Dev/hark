# Status

> Updated: 2026-10-26

## Where we are
hark is installed at `/Applications/hark.app` and in daily use. Polish goes to a native FreeLLMAPI on `localhost:3001` with model `gpt-oss-20b` (Groq), low reasoning effort, Apple's model as backup after 2.5 s and a 10 s ceiling. `main` is at `1a50086`; the one uncommitted change is the request tuning in `Sources/hark/PolishServer.swift`, which is already in the installed build.

## Recent
- 2026-10-21 to 2026-10-26: real waits (`seconds - spoken`) monitored every 10 minutes. Every dictation waited 5.4 s or less, none near the ceiling; the last 11 (24 to 25 October) had a median of 1.57 s and a max of 4.45 s, all served by Groq.
- 2026-10-22: FreeLLMAPI moved out of Docker into a LaunchAgent. Cloudflare Workers AI measured for the Windows build: `@cf/openai/gpt-oss-20b` 3.5 s on a 98-word dictation against 1.1 s for Groq via FreeLLMAPI, so the Mac stays on FreeLLMAPI.
- 2026-10-21: pinned `gpt-oss-20b` with `reasoning_effort: low` and `max_tokens: 4096`. Without them gpt-oss spent its output cap on reasoning and long dictations hit the ceiling; `auto` wandered to upstreams taking 10 s or more.

## Next
- Commit the `PolishServer.swift` change, then update CLAUDE.md and AGENTS.md, which still describe model `auto` and Docker.
- FreeLLMAPI sometimes routes `gpt-oss-20b` to NVIDIA, which hangs to the ceiling. Fix: disable the `nvidia` / `openai/gpt-oss-20b` row via `freellmapi.config.json` and restart; recheck after a catalog refresh.
- Quit Docker Desktop; its container still holds `127.0.0.1:3001`, harmless only because `localhost` resolves to `::1` first.
- Windows build: bake the Cloudflare Workers AI endpoint and token into `windows/build.rs`; never run on Windows yet.
- Explain the 2 to 3.6 s of in-app time beyond server latency; hark's `log.notice` stage timings do not reach `log show`.
- Rerun `make eval` after the formatting change; Apple's backup is too slow on long inputs.
- Recover mode for slurred speech: plan in `~/.claude/plans/we-need-to-improve-enumerated-orbit.md`, not started.
- Still owed: insertion checks in an Electron app and a browser field, microphone picker test, friend's macOS version (needs 26).
- Known limits: paste uses a fixed V key code; "nodes" heard as "notes" is not repaired; a spoken email address can gain a hyphen.
