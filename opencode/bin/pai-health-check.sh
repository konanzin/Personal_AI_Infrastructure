#!/usr/bin/env bash
# pai-health-check.sh — the scheduled CONSUMER that closes the O5 loop
# (docs/HARNESS_QUALITY.md §1: "Degradation is noticed" means a consumer reads
# the signal and an alert fires — not "the JSONL exists" and not "a script
# exists that you could run"). Installed as a systemd user timer by install.sh
# (pai-health.timer, daily); also runnable by hand.
#
# Probes (cheap, no LLM calls — the golden eval stays on-demand because it
# costs tokens):
#   1. bin/monitor-classifier-health.js   exit 0 ok / 1 warn / 2 alert
#   2. install.sh --check                 exit 0 ok / 1 drift
#
# On any non-zero probe: desktop notification (notify-send, if present) and a
# JSONL record appended to PAI/MEMORY/OBSERVABILITY/health-check.jsonl either
# way, so "when did we last actually look?" is itself answerable.
#
# Exit code: the worst probe exit (0 ok / 1 warn-or-drift / 2 alert).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCODE_DIR="$(dirname "$SCRIPT_DIR")"
PAI_DIR="${PAI_DIR:-$HOME/.config/opencode/PAI}"
LOG_DIR="$PAI_DIR/MEMORY/OBSERVABILITY"
LOG_FILE="$LOG_DIR/health-check.jsonl"
mkdir -p "$LOG_DIR"

worst=0
details=""

run_probe() {
    local name="$1"
    shift
    local out rc
    out="$("$@" 2>&1)"
    rc=$?
    if [ "$rc" -gt "$worst" ]; then worst=$rc; fi
    local tail_out
    tail_out="$(printf '%s' "$out" | tail -n 3 | tr '\n' ' ')"
    details="${details}${name}: exit ${rc} — ${tail_out}\n"
    echo "[pai-health] ${name}: exit ${rc}"
}

BUN_BIN="${BUN_BIN:-bun}"
if ! command -v "$BUN_BIN" >/dev/null 2>&1 && [ -x "$HOME/.bun/bin/bun" ]; then
    BUN_BIN="$HOME/.bun/bin/bun"
fi

run_probe "classifier-health" "$BUN_BIN" "$OPENCODE_DIR/bin/monitor-classifier-health.js"
run_probe "install-drift" bash "$OPENCODE_DIR/install.sh" --check

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
status="ok"
if [ "$worst" -eq 1 ]; then status="warn"; fi
if [ "$worst" -ge 2 ]; then status="alert"; fi

if command -v jq >/dev/null 2>&1; then
    jq -cn \
        --arg ts "$timestamp" \
        --arg status "$status" \
        --arg details "$(printf '%b' "$details")" \
        --argjson exit "$worst" \
        '{timestamp: $ts, event: "health_check", status: $status, exit: $exit, details: $details}' \
        >> "$LOG_FILE"
else
    printf '{"timestamp":"%s","event":"health_check","status":"%s","exit":%d}\n' \
        "$timestamp" "$status" "$worst" >> "$LOG_FILE"
fi

if [ "$worst" -gt 0 ] && command -v notify-send >/dev/null 2>&1; then
    urgency="normal"
    [ "$worst" -ge 2 ] && urgency="critical"
    notify-send --urgency="$urgency" --app-name="PAI Health" \
        "PAI harness: ${status^^}" \
        "$(printf '%b' "$details" | head -c 400)" || true
fi

exit "$worst"
