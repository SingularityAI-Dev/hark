# Jev and typed decision models for hark: research report

Date: 2026-10-14. Question: can Jev, Laya or laya-coreml make hark's dictation cleanup
better or faster, alongside FreeLLMAPI?

## Answer

Not today. A decision model cannot rewrite text, so it cannot replace the polish step. Its
only useful place in hark is a gate that lets clean dictations skip the slow cloud call.
Measured on this Mac, the local Laya gate caught 1 of 4 messy dictations, which would paste
uncorrected text three times out of four. Revisit once history holds a few hundred
dictations to calibrate against.

## What these models are

- **Jev** (TypeSafe AI, early access since 2026-09-15) is a "decision-only" model: it
  takes a state plus typed questions and returns probabilities instead of text. The
  question types are `choice` (pick one declared option), `score` (an ordered scale) and
  `noul` (yes or no with a probability). TypeSafe says it is trained for calibrated
  probabilities. [InfoQ], [OpenRouter explainer]
- **Laya** is the open-weights counterpart: reported as a 421M-parameter ModernBERT-large
  encoder with a typed decision head, supporting the same three question types, with
  English and multilingual checkpoints. [Medium: Laya vs Jev], [DataCamp]
- **laya-coreml** runs Laya on Apple's Neural Engine through Core ML, so it needs no GPU.
  Its README reports 4.98 ms P50 for one short multilingual decision on an M3 Max, and
  2.78x better energy per decision than MLX. Requires macOS 15+ and Python 3.11 to 3.13.
  [laya-coreml]
- **OpenAI Decisions API** (DevDay 2026-09-29, limited preview) does the same job with
  OpenAI's models: choose among finite, developer-defined answers. No published latency.
  [InfoQ DevDay recap]

Most of the coverage is third-party; TypeSafe's speed and "never hallucinates" claims are
not independently verified. [DataCamp]

## Why a decision model cannot do hark's cleanup

Removing a self-correction means producing new text: "book the flight for the fifth, sorry,
the sixth" has to become "book the flight for the sixth". The research literature treats
this as repair detection (a reparandum the speaker means to delete, an optional
interregnum like "sorry", then the repair), and AssemblyAI's 2026 write-up calls
self-corrections and trailing abandonment the two "judgment call" categories of dictation
cleanup. A model that only answers typed questions can flag that a repair exists, not
rewrite around it. [AssemblyAI], [Lease 2006], [Hough and Purver 2014]

## Where it could fit: a gate in front of FreeLLMAPI

The video's use cases 10 and 11 (route each request; put Jev in front of an expensive
agent) map to hark like this: ask "is this transcript messy?" and only send messy ones to
FreeLLMAPI, so clean dictations paste instantly instead of waiting 0.5 to 10 s.

### Measured on this Mac (local Laya via `~/.claude/bin/jev`, port 8100)

Eight transcripts, four clean and four with hesitation or self-correction.

| Question form | Clean judged clean | Messy judged messy | Time per decision |
| --- | --- | --- | --- |
| `noul` "contains hesitation or self-correction?" | 4 of 4 | 0 of 4 (yes-probability 0.19 to 0.35) | about 260 ms |
| `choice` clean / messy | 4 of 4 | 1 of 4 (only the WhatsApp example) | about 260 ms |

Missed: "the fifth sorry the sixth", "marketing actually no send it to the whole team",
and an abandoned-phrase case. A gate that misses those would make hark worse, because the
polish step catches all three (FreeLLMAPI `auto`: 15 of 15 on `make eval`).

laya-coreml would make each decision faster (milliseconds on the Neural Engine), not more
accurate; it is the same model.

## FreeLLMAPI and Jev

FreeLLMAPI's catalog on this install has no Jev or Laya model, so Jev cannot be reached
through it. The two would sit side by side: Laya locally as a gate, FreeLLMAPI for the
rewrite.

## What would change the answer

1. **Calibration with a validation set** (the video's use case 8): a few hundred
   transcripts labelled clean or messy, then tune the decision floor. hark's history
   stores the raw transcript next to the pasted text, so labels can come from whether
   polish changed more than punctuation. History has 35 entries today.
2. **A conservative gate**: route to FreeLLMAPI unless the gate says clean with high
   confidence. With today's model that skips the cloud only for very plain sentences,
   saving little.
3. **Speed without a gate**: FreeLLMAPI's router has a speed-first strategy, and a free
   Cerebras key adds one of the fastest providers. Both are dashboard settings, no code.

## Recommendation

1. Now: switch FreeLLMAPI's routing to its speed strategy and add a Cerebras key. Measure
   with `make eval` and the `seconds` and `spoken` fields in history.
2. At about 300 dictations: build the validation set from history, rerun the Laya gate,
   and add it to hark only if it catches at least 95% of messy dictations.

## Sources

- [InfoQ: TypeSafe AI releases Jev](https://www.infoq.com/news/2026/10/typesafe-ai-jev-released/)
- [OpenRouter: What is Jev?](https://openrouter.ai/blog/insights/what-is-jev/)
- [Medium: Laya vs TypeSafe Jev](https://medium.com/data-science-in-your-pocket/laya-vs-typesafe-jev-ai-8b5dd9ce0176)
- [DataCamp: open-source Jev alternatives](https://www.datacamp.com/blog/top-open-source-jev-alternatives)
- [Trilogy AI: Jev's open rivals](https://trilogyai.substack.com/p/jev-open-decision-models)
- [laya-coreml README](https://github.com/mizorewww/laya-coreml)
- [InfoQ: OpenAI DevDay 2026 recap](https://www.infoq.com/news/2026/10/openai-devday-2026/)
- [AssemblyAI: dictation cleanup](https://assemblyai.com/blog/dictation-cleanup)
- [Lease 2006: disfluency and repair](https://ischool.utexas.edu/ml/papers/lease06-sap.pdf)
- [Strongly incremental repair detection](https://ar5iv.arxiv.org/html/1408.6788)
- [Disfluency detection with a noisy channel and neural language model](https://arxiv.org/pdf/1808.09091)
- Video: "These 19 Jev-Claude use cases are blowing people's minds", package at
  `~/Desktop/These-19-Jev-Claude-use-cases-are-blowing-peoples-minds-with/`
