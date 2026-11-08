#!/usr/bin/env python3
"""Reproducible numbers for the learning and accuracy design.

Reads hark's history (and optionally its traces, learned entries and read-back counts)
and prints the counts the design measures against. Standard library only; run by hand,
never bundled with the app.

    scripts/history-report.py <history.jsonl> --clean-binary <path>
        [--current-binary <path>] [--traces polish.jsonl] [--learned learned.json]
        [--readback readback-counts.json] [--candidates]

--clean-binary is the pinned pre-Phase-1 build, so the rules-path count stays comparable
over time. --current-binary is today's build, used for the re-cleaned `#` count and for
`--repairs`. Optional inputs are reported only when given.
"""

import argparse
import collections
import json
import re
import statistics
import subprocess
import sys
from datetime import datetime

BUCKETS = [("under 3", 0, 3), ("3 to 39", 3, 40), ("40 to 99", 40, 100), ("100 or more", 100, 10**9)]
HESITATION = re.compile(r"#(?:u+h+m*|u+m+|e+r+m*|h+m+|m+h+m+|a+h+m*)\b", re.IGNORECASE)
HASH_WORD = re.compile(r"#\w+")
CUES = {"wait", "sorry", "no", "actually", "mean", "scratch", "rather", "correction"}
LIST_LEADS = ("the following", "these things", "a list of", "first,", "first ")
CHAT_APPS = ("com.google.Chrome", "com.anthropic.claudefordesktop", "net.whatsapp.WhatsApp")


def load_jsonl(path):
    rows = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return rows


def words(text):
    return re.sub(r"[^a-z0-9' ]", " ", text.lower()).split()


def bucket(count):
    for name, low, high in BUCKETS:
        if low <= count < high:
            return name
    return BUCKETS[-1][0]


def run(binary, *args):
    result = subprocess.run([binary, *args], capture_output=True, text=True, timeout=60)
    return result.stdout.strip(), result.returncode


def when(entry):
    return datetime.fromisoformat(entry["date"].replace("Z", "+00:00"))


def percentile(values, share):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(share * len(ordered)))]


def report_basics(entries, clean_binary):
    print(f"entries: {len(entries)}, {entries[0]['date'][:10]} to {entries[-1]['date'][:10]}")
    totals, rules = collections.Counter(), collections.Counter()
    waits = []
    for entry in entries:
        name = bucket(len(entry["raw"].split()))
        totals[name] += 1
        cleaned, _ = run(clean_binary, "--clean", entry["raw"])
        if cleaned == entry["text"].strip():
            rules[name] += 1
        if entry.get("spoken") is not None:
            waits.append(entry["seconds"] - entry["spoken"])
    print("\nrules-path pastes (pasted text equals the pinned rule cleaner's output; an upper bound):")
    for name, _, _ in BUCKETS:
        print(f"  {name:12} {rules[name]:4} of {totals[name]}")
    print(f"  total        {sum(rules.values()):4} of {len(entries)}")
    if waits:
        print(f"\nwaits (seconds - spoken): median {statistics.median(waits):.2f} s, "
              f"75th {percentile(waits, 0.75):.2f} s, max {max(waits):.2f} s")


def report_tokens(entries, current_binary):
    raw = sum(len(HESITATION.findall(entry["raw"])) for entry in entries)
    pasted = sum(len(HASH_WORD.findall(entry["text"])) for entry in entries)
    print(f"\nhesitation # tokens: {raw} in raw text; {pasted} #-words in pasted text")
    if current_binary:
        left = 0
        for entry in entries:
            if HESITATION.search(entry["raw"]):
                cleaned, _ = run(current_binary, "--clean", entry["raw"])
                left += len(re.findall(r"#(?!\d)\w+", cleaned))
        print(f"  #-words left after re-cleaning raw text with the current build: {left}")


def report_redictations(entries):
    pairs = 0
    for first, second in zip(entries, entries[1:]):
        if first.get("app") != second.get("app"):
            continue
        if (when(second) - when(first)).total_seconds() > 90:
            continue
        a, b = set(words(first["raw"])), set(words(second["raw"]))
        long_a, long_b = len(first["raw"].split()), len(second["raw"].split())
        similar = abs(long_a - long_b) <= max(3, long_a // 4)
        if similar and len(a) >= 3 and len(b) >= 3 and len(a & b) / min(len(a), len(b)) >= 0.7:
            pairs += 1
    print("\nre-dictation pairs (same app, within 90 s, 70% or more word overlap, similar length): "
          f"{pairs}")


def report_traces(entries, traces):
    by_id = collections.defaultdict(list)
    for trace in traces:
        by_id[trace.get("entryID")].append(trace)
    lengths = {entry["id"]: len(entry["raw"].split()) for entry in entries if "id" in entry}
    reasons, winners = collections.Counter(), collections.Counter()
    deadline = collections.Counter()
    traced = collections.Counter()
    orphans = 0
    main_lines = [t for t in traces if not t.get("late")]
    for trace in main_lines:
        winners[trace.get("winner")] += 1
        if trace.get("orphanInFlight"):
            orphans += 1
        name = bucket(lengths.get(trace.get("entryID"), 0))
        traced[name] += 1
        if trace.get("skipped"):
            reasons["skipped: " + trace["skipped"]] += 1
        for contender in trace.get("contenders", []):
            outcome = contender.get("outcome")
            if outcome == "deadline":
                deadline[name] += 1
            if trace.get("winner") == "rules" and outcome not in ("answered", "notStarted"):
                detail = contender.get("detail") or ""
                reasons[f"{contender.get('name')}: {outcome} {detail}".strip()] += 1
    print(f"\ntraces: {len(main_lines)} dictations, {len(traces) - len(main_lines)} late lines")
    print("  winners: " + ", ".join(f"{k} {v}" for k, v in winners.most_common()))
    print(f"  orphan request in flight: {orphans} of {len(main_lines)}")
    print("  deadline hits by length: " + ", ".join(
        f"{name} {deadline[name]} of {traced[name]}" for name, _, _ in BUCKETS if traced[name]))
    print("  fallback reasons:")
    for reason, count in reasons.most_common(12):
        print(f"    {count:4}  {reason}")


def report_readback(path):
    with open(path, encoding="utf-8") as handle:
        counts = json.load(handle)
    apps = counts.get("apps", {})
    print(f"\nread-back counts since {counts.get('since')}:")
    gate = 0
    for app, outcomes in sorted(apps.items()):
        print(f"  {app}: " + ", ".join(f"{k} {v}" for k, v in sorted(outcomes.items())))
        if app.startswith(CHAT_APPS):
            gate += outcomes.get("changed1or2", 0)
    print(f"  step 2 gate (Chrome, Claude, WhatsApp 'changed1or2'): {gate} (needs 10)")


def report_learned(path, entries, traces):
    with open(path, encoding="utf-8") as handle:
        store = json.load(handle)
    learned = store.get("entries", [])
    removed = sum(1 for item in learned if item.get("state") == "removed")
    print(f"\nlearned entries: {len(learned)}, removed by the speaker: {removed}")
    hint_only = [item for item in learned if item.get("heardIsWord") and item.get("state") == "active"]
    polished = {t.get("entryID") for t in traces if not t.get("late") and t.get("winner") != "rules"}
    seen = fixed = 0
    for entry in entries:
        if entry.get("id") not in polished:
            continue
        raw = set(words(entry["raw"]))
        pasted = entry["text"].lower()
        for item in hint_only:
            if item["heard"].lower() in raw:
                seen += 1
                fixed += item["meant"].lower() in pasted
    if seen:
        print(f"  hint-only entries: meant form reached the paste in {fixed} of {seen} polished pastes")


def report_repairs(entries, current_binary):
    print("\nrepair-rule firings (label each as repair or list):")
    for entry in entries:
        output, code = run(current_binary, "--repairs", entry["raw"])
        if code != 0:
            print("  the current build has no --repairs yet")
            return
        for line in output.splitlines():
            print(f"  {entry['date'][:16]}  {line}")


def report_candidates(entries, dictionary):
    picks = collections.defaultdict(list)
    names = collections.Counter(
        word for entry in entries for word in set(re.findall(r"\b[A-Z][a-z]{2,}\b", entry["raw"])))
    for entry in entries:
        raw, text = entry["raw"], entry["text"]
        raw_words, text_words = words(raw), words(text)
        if CUES & set(raw_words):
            picks["repair"].append(entry)
        if any(lead in raw.lower() for lead in LIST_LEADS):
            picks["list"].append(entry)
        if len(raw_words) == len(text_words) and sum(a != b for a, b in zip(raw_words, text_words)) == 1:
            picks["misheard"].append(entry)
        if len(set(text_words) - set(raw_words)) >= 3:
            picks["voice"].append(entry)
        if any(names[w] >= 2 and w not in dictionary and w.lower() not in CUES
               for w in re.findall(r"\b[A-Z][a-z]{2,}\b", raw)):
            picks["name"].append(entry)
    print("\ncandidates for labelling (up to 24 per type):")
    for kind in ("repair", "list", "misheard", "voice", "name"):
        print(f"\n## {kind}")
        for entry in picks[kind][-24:]:
            print(f"{entry['raw']}\t\t\t{kind}\t")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("history")
    parser.add_argument("--clean-binary", required=True)
    parser.add_argument("--current-binary")
    parser.add_argument("--traces")
    parser.add_argument("--learned")
    parser.add_argument("--readback")
    parser.add_argument("--candidates", action="store_true")
    parser.add_argument("--dictionary", default="", help="comma-separated Dictionary terms")
    args = parser.parse_args()

    entries = load_jsonl(args.history)
    if not entries:
        sys.exit("no history entries")
    traces = load_jsonl(args.traces) if args.traces else []

    report_basics(entries, args.clean_binary)
    report_tokens(entries, args.current_binary)
    report_redictations(entries)
    if args.traces:
        report_traces(entries, traces)
    if args.readback:
        report_readback(args.readback)
    if args.learned:
        report_learned(args.learned, entries, traces)
    if args.current_binary:
        report_repairs(entries, args.current_binary)
    if args.candidates:
        report_candidates(entries, set(filter(None, args.dictionary.split(","))))


if __name__ == "__main__":
    main()
