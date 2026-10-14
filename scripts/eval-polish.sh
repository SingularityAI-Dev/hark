#!/bin/bash
# Runs each transcript in polish-cases.tsv through `hark --refine` (rule cleanup plus the
# on-device model, with the plausibility guard) and checks words that must survive and
# words that must be gone. Prints each result and a pass count; exits 1 on any failure.
bin="${1:-.build/release/hark}"
cases="$(dirname "$0")/polish-cases.tsv"
pass=0; total=0
while IFS=$'\t' read -r raw keep drop; do
  [[ -z "$raw" || "$raw" == \#* ]] && continue
  total=$((total + 1))
  out="$("$bin" --refine "$raw" 2>/tmp/hark-eval-time)"
  ms="$(grep -o '[0-9]* ms' /tmp/hark-eval-time)"
  lower="$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]')"
  problems=""
  IFS='|' read -ra words <<< "$keep"
  for w in "${words[@]}"; do
    [[ -n "$w" && "$lower" != *"$(printf '%s' "$w" | tr '[:upper:]' '[:lower:]')"* ]] && problems+=" missing '$w'"
  done
  IFS='|' read -ra words <<< "$drop"
  for w in "${words[@]}"; do
    [[ -n "$w" && "$lower" == *"$(printf '%s' "$w" | tr '[:upper:]' '[:lower:]')"* ]] && problems+=" kept '$w'"
  done
  if [[ -z "$problems" ]]; then pass=$((pass + 1)); echo "PASS ($ms) $out"; else echo "FAIL ($ms) $out  ->$problems"; fi
done < "$cases"
echo "polish eval: $pass of $total passed"
[[ $pass -eq $total ]]
