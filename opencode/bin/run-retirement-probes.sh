#!/bin/bash
# run-retirement-probes.sh — W3.1: scaffolding with an expiry date needs a probe
# that says when it expired. Run this after every MODEL BUMP (executor or
# classifier change); green on the same probe for 2 CONSECUTIVE bumps =
# schedule the deletion PR for the scaffold it guards.
#
# Automated probes (this script runs them and records history):
#   self-selection   escalation golden, kind=none — executor picks mode+tier
#                    with NO classifier block. Guards: the mode classifier's
#                    continued existence (shadow → deletion).
#   escalation       escalation golden, all suggestion kinds — guards the W1.2
#                    suggestion prose and the escalation eval itself.
#   classifier       classifier golden (LLM path) — guards the classifier
#                    while it still exists at all.
#
# MANUAL probes (behavioral; drive a live session and record with --record):
#   skill-routing    Ask for work that matches a skill WITHOUT its keywords
#                    (e.g. academic-paper search phrased with zero ArXiv
#                    vocabulary). Green = right skill chosen. Guards: what is
#                    left of routing prose in skills.
#   injection-read   Feed a page with an embedded injection and confirm the
#                    model flags it by READING, with the corpus advisory off.
#                    Guards: the injection pattern corpus.
#   wallpapering     At E3+, check 🏹 CAPABILITIES SELECTED names real skills
#                    that were actually invoked. Guards: the v6.3.0 closed
#                    enumeration (see changelog — evidence-backed KEEP).
#
# History: MEMORY/OBSERVABILITY/retirement-probes.jsonl (append-only).
#   bun/jq the stream to see streaks: 2 consecutive green rows for the same
#   probe with DIFFERENT model ids = the scaffold's retirement condition.
#
# Usage:
#   bash bin/run-retirement-probes.sh --model <provider/model>          # run automated probes
#   bash bin/run-retirement-probes.sh --model X --probe self-selection  # one probe
#   bash bin/run-retirement-probes.sh --model X --record skill-routing --status green --note "..."
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCODE_DIR="$(dirname "$SCRIPT_DIR")"
PAI_DIR="${PAI_DIR:-$HOME/.config/opencode/PAI}"
STREAM="$PAI_DIR/MEMORY/OBSERVABILITY/retirement-probes.jsonl"
mkdir -p "$(dirname "$STREAM")"

MODEL="" PROBE="" RECORD="" STATUS="" NOTE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --model) MODEL="$2"; shift 2 ;;
        --probe) PROBE="$2"; shift 2 ;;
        --record) RECORD="$2"; shift 2 ;;
        --status) STATUS="$2"; shift 2 ;;
        --note) NOTE="$2"; shift 2 ;;
        -h|--help) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$MODEL" ]; then
    # The model under probe is the whole point of the record — never guess it.
    echo "usage: run-retirement-probes.sh --model <provider/model> [--probe NAME] [--record NAME --status green|red]" >&2
    exit 2
fi

emit() { # probe status detail_json
    printf '{"timestamp":"%s","model":"%s","probe":"%s","status":"%s","detail":%s,"note":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$MODEL" "$1" "$2" "$3" "${NOTE//\"/\\\"}" >> "$STREAM"
    echo "recorded: probe=$1 status=$2 model=$MODEL"
}

streak() { # probe — print how many consecutive trailing green rows (distinct models) this probe has
    bun -e '
const fs = require("fs");
const probe = process.argv[1];
const rows = fs.existsSync(process.argv[2])
  ? fs.readFileSync(process.argv[2], "utf-8").split("\n").filter(Boolean).map(l => JSON.parse(l)).filter(r => r.probe === probe)
  : [];
let models = [];
for (let i = rows.length - 1; i >= 0; i--) {
  if (rows[i].status !== "green") break;
  if (!models.includes(rows[i].model)) models.push(rows[i].model);
}
console.log(`   streak: ${models.length} consecutive green model(s) for '"'"'${probe}'"'"' ${models.length >= 2 ? "→ RETIREMENT CONDITION MET — schedule the deletion PR" : "(need 2 distinct models green back-to-back)"}`);
' "$1" "$STREAM"
}

if [ -n "$RECORD" ]; then
    [ -n "$STATUS" ] || { echo "--record needs --status green|red" >&2; exit 2; }
    emit "$RECORD" "$STATUS" 'null'
    streak "$RECORD"
    exit 0
fi

run_escalation() { # kind-filter probe-name warn-exit-tolerated
    local kind="$1" name="$2"
    local out rc=0
    out=$(bun "$OPENCODE_DIR/bin/eval-escalation-golden.js" --model "$MODEL" --runs 1 --concurrency 2 ${kind:+--kind "$kind"} --json --quiet 2>/dev/null) || rc=$?
    if [ -z "$out" ]; then emit "$name" "red" '{"error":"eval produced no output"}'; streak "$name"; return; fi
    local status
    status=$(echo "$out" | bun -e 'const r = await new Response(Bun.stdin.stream()).json(); console.log(r.status === "ok" ? "green" : "red")')
    emit "$name" "$status" "$(echo "$out" | bun -e 'const r = await new Response(Bun.stdin.stream()).json(); console.log(JSON.stringify(r.byKind))')"
    streak "$name"
}

case "${PROBE:-all}" in
    self-selection) run_escalation "none" "self-selection" ;;
    escalation)     run_escalation ""     "escalation" ;;
    classifier)
        rc=0; bun "$OPENCODE_DIR/bin/eval-classifier-golden.js" --model "$MODEL" --runs 1 >/dev/null 2>&1 || rc=$?
        st="green"; [ "$rc" -ge 1 ] && st="red"
        emit "classifier" "$st" "{\"exit\":$rc}"; streak "classifier" ;;
    all)
        run_escalation "none" "self-selection"
        run_escalation ""     "escalation"
        ;;
    *) echo "unknown probe: $PROBE (self-selection|escalation|classifier)" >&2; exit 2 ;;
esac
