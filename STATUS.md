# Status

> Updated: 2026-10-20

## Where we are
hark is installed at `/Applications/hark.app` (build of 2026-10-20 13:33) and in daily use by Rainier: hold or tap Fn, speak, text is pasted at the cursor. Speech runs on the Mac; polish goes to FreeLLMAPI at `localhost:3001` (model `auto`) with Apple's on-device model as a backup and a hard 10 s ceiling. The remote is `SingularityAI-Dev/hark` (moved from `talk-is-nice`), `main` at `134fe9a`, tree clean.

## Recent
- 2026-10-20: slowness traced to FreeLLMAPI's free upstreams (10 s waits on most long dictations, one upstream held a connection 34 s). Fix: server gets 2.5 s alone, then Apple's model runs beside it, first plausible answer pasted, 10 s ceiling. `make eval` against the server: 23 of 24, median 0.9 s, p75 1.9 s.
- 2026-10-20: "bookings, no, applications" was pasted unchanged by every model (read "no" as "not"); prompt rule plus examples fix it on FreeLLMAPI and on-device.
- 2026-10-16 to 10-18: misheard-word repair, short-phrase polish, spoken lists as bullets, app icon, history copy button; Windows port under `windows/` (Rust) that cross-compiles but has not run on Windows.

## Next
- Watch real waits (`history.jsonl`, `seconds - spoken`); a session cron checks every 10 min. Apple's backup path was only timed under load average 8, so its speed under normal load is unproven.
- Windows `.exe` for the friend: blocked on a reachable HTTPS endpoint for FreeLLMAPI. `hark.hub1.ai` cannot work (hub1.ai nameservers are Hostinger parking, no access). Options: Cloudflare quick tunnel (URL changes per restart, needs a rebuild each time) or host FreeLLMAPI elsewhere. Then the friend runs it; nobody here can.
- Keep `windows/prompt.txt` in sync with `Refiner.swift` by hand (regenerate with the extraction script in the session notes).
- Still owed from the original plan: key release to text latency (median of 10), a screen recording in `docs/`, insertion checks in an Electron app and a browser field, a microphone picker test; friend's macOS version (needs 26).
- Known limits: "That all operation" is not repaired (no context); "nodes" to "notes" is not repaired (real word); paste uses a fixed V key code (non-QWERTY layouts); Apple's model drops a genuine "not X" when the recogniser gives no commas.
