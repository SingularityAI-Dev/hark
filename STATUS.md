# Status

> Updated: 2026-10-20

## Where we are
hark is installed at `/Applications/hark.app` (build of 2026-10-20 15:17, `b721e39`) and in daily use by Rainier: hold or tap Fn, speak, text is pasted at the cursor. Speech runs on the Mac; polish goes to FreeLLMAPI at `localhost:3001` (model `auto`) with Apple's on-device model as a backup after 2.5 s and a hard 10 s ceiling. Remote `SingularityAI-Dev/hark`, `main` at `b721e39`, tree clean.

## Recent
- 2026-10-20 (afternoon): spoken formatting instructions are applied, not typed: "single source, one word, with a capital S" pastes as "SingleSource"; the guard counts joined runs of spoken words as the speaker's own. Server verified in 1 to 2 s; Apple's model unmeasured (it hit the ceiling under load).
- 2026-10-20: real waits after the race build, 12 dictations: median 2.25 s, p75 3.2 s, max 9.3 s (one 23-word case during load average 42); none past the ceiling. Before the race, long dictations waited about 10.5 s.
- 2026-10-20: "bookings, no, applications" swap rule; slowness traced to FreeLLMAPI's free upstreams and fixed with the race plus ceiling (`134fe9a`), eval 23 of 24, median 0.9 s.

## Next
- The Mac's load average sat between 8 and 42 all afternoon (`fseventsd` 56% CPU, `WindowServer` 48%); that inflates every wait and starves Apple's backup model. Find the file-system event source before judging the backup path.
- Windows `.exe` for the friend: blocked on a reachable HTTPS endpoint for FreeLLMAPI (`hark.hub1.ai` cannot work, hub1.ai nameservers are Hostinger parking with no access). Options: Cloudflare quick tunnel (URL changes per restart) or host FreeLLMAPI elsewhere. Never run on Windows.
- Keep `windows/prompt.txt` in sync with `Refiner.swift` (regenerate after any prompt edit).
- Still owed: key release to text latency (median of 10), a screen recording in `docs/`, insertion checks in an Electron app and a browser field, a microphone picker test; friend's macOS version (needs 26).
- Known limits: "That all operation" and "nodes" to "notes" are not repaired; paste uses a fixed V key code; Apple's model drops a genuine "not X" when the recogniser gives no commas; a spoken email address can gain a hyphen ("single source dot co dot za").
