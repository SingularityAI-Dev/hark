# Status

> Updated: 2026-11-09

## Where we are
Phase 1 of the learning and accuracy design (`docs/designs/hark-learning-and-accuracy.md`) is built and installed from branch `learning-and-accuracy` (HEAD `60d8ff5`, not pushed): every dictation writes a polish trace to `polish.jsonl` ("Why this text?" in History), and hark counts per app whether a paste can be read back (`readback-counts.json`, no text stored). Two fresh-context reviews done; 50 tests pass, `make verify` 3 of 3, footprint 15 MB. Learning from edits is being redesigned with EGM because Terminal turned out to expose pasted text.

## Recent
- 2026-11-09: first read-back test in Terminal detected a one-word edit (brine to Bryne), contradicting the design's assumption that Terminal gives no signal. Rainier presses Enter straight after a fix, so the next read-back found the line gone. EGM brainstorm brief for learning from edits written (`concepts_brief.md`, repo root, untracked); hypothesis confirmed, Goldfish review not yet run.
- 2026-11-08: design approved after EGM brainstorm, draft and 9-stage Goldfish review; baseline in `~/hark-baseline/` (pinned binary, frozen history of 531 entries, `report-before.txt`).
- 2026-11-08: history replay: up to 241 of 531 pastes were rule cleanup only (polish fell back), 49 pasted words carry a leaked `#`, 0 re-dictations; the "all 3 / all 4" repair reached the model and was kept.

## Next
- Learning from edits: resume EGM brainstorm Step 2 (Goldfish review) on `concepts_brief.md`, then `egm-draft` and `egm-review`, then build. Hypothesis: read back on Enter as well as Fn; search the field's recent text; save fixes to the Dictionary; non-words replaced, real words hinted then replaced after a second identical fix; skip shell-prompt lines and code.
- Let Phase 1 traces run two weeks, then `scripts/history-report.py --traces` sets the Goal 2 fallback target.
- Phase 3 (token strip, repair rule, edit guard, labelled eval) can be built any time.
- Check whether the per-dictation keychain read explains the 2 to 3.6 s of unexplained in-app time (compare `seconds - spoken` with trace times).
- Before any push to `SingularityAI-Dev/hark`: the design and review files name third parties (Ruen, Elsa) and quote dictations.
- Still open from October: disable FreeLLMAPI's NVIDIA gpt-oss-20b row; quit Docker Desktop; Windows build endpoint; CLAUDE.md and AGENTS.md still describe model `auto` and Docker.
