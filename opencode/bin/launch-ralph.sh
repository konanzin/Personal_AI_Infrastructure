#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  PAI Ralph Loop Launcher
#  Executa o port do PAI em background usando open-ralph-wiggum
# ═══════════════════════════════════════════════════════════

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# ─── Paths ────────────────────────────────────────────────
PAI_DIR="${HOME}/.config/opencode/PAI"
PROMPTS_DIR="${PAI_DIR}/prompts"
LOGS_DIR="${PAI_DIR}/logs"
RALPH_STATE="${HOME}/.ralph"

# ─── Config ───────────────────────────────────────────────
MAX_ITERATIONS="${MAX_ITERATIONS:-20}"
COMPLETION_PROMISE="${COMPLETION_PROMISE:-COMPLETE}"
AGENT="${AGENT:-opencode}"
# Model-agnostic default: prefer the per-machine primary (PAI/USER/Config/primary-model),
# else the primary configured in opencode.jsonc. No vendor is hardcoded here.
_pai_default_model() {
    local f="${PAI_DIR}/USER/Config/primary-model"
    if [ -f "$f" ]; then tr -d '[:space:]' < "$f"; return; fi
    grep -m1 '"model":' "${HOME}/.config/opencode/opencode.jsonc" 2>/dev/null \
        | sed -E 's/.*"model"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/'
}
MODEL="${MODEL:-$(_pai_default_model)}"

# ─── Helpers ──────────────────────────────────────────────
log() { echo -e "${BLUE}[PAI-RALPH]${RESET} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }

# ─── Setup ────────────────────────────────────────────────
setup() {
    mkdir -p "$PROMPTS_DIR"
    mkdir -p "$LOGS_DIR"
    mkdir -p "$RALPH_STATE"
}

# ─── Check prerequisites ──────────────────────────────────
check_prerequisites() {
    if ! command -v ralph &>/dev/null; then
        echo "❌ ralph not found. Install: npm install -g @th0rgal/ralph-wiggum"
        exit 1
    fi
    
    if ! command -v opencode &>/dev/null; then
        echo "❌ opencode not found. Install from https://opencode.ai"
        exit 1
    fi
    
    log "Prerequisites OK"
}

# ─── Usage ────────────────────────────────────────────────
usage() {
    cat << EOF
Usage: launch-ralph.sh [OPTIONS] [STORY_ID]

Launch Ralph loop for PAI port stories.

OPTIONS:
  -s, --story ID          Story ID to run (PORT-001, PORT-002, etc.)
  -i, --iterations N      Max iterations (default: 20)
  -m, --model MODEL       Model to use (default: per-machine primary model)
  -a, --agent AGENT       Agent to use: opencode, claude-code, codex (default: opencode)
  -f, --foreground        Run in foreground (default: background)
  -p, --prompt FILE       Custom prompt file
  --status                Check status of running loop
  --stop                  Stop running loop
  -h, --help              Show this help

EXAMPLES:
  launch-ralph.sh -s PORT-001                    # Run PORT-001 in background
  launch-ralph.sh -s PORT-001 -f                 # Run PORT-001 in foreground
  launch-ralph.sh --status                       # Check loop status
  launch-ralph.sh --stop                         # Stop loop
  launch-ralph.sh -s PORT-001 -i 50 -m gpt-5    # Custom model, more iterations

EOF
}

# ─── Find prompt file ─────────────────────────────────────
find_prompt() {
    local story_id="${1:-}"
    
    if [ -n "$story_id" ]; then
        local prompt_file="${PROMPTS_DIR}/${story_id}.md"
        if [ -f "$prompt_file" ]; then
            echo "$prompt_file"
            return 0
        fi
    fi
    
    # Auto-detect next story from prd.json
    local next_story=$(jq -r '.userStories[] | select(.passes == false) | .id' "${PAI_DIR}/prd.json" | head -1)
    if [ -n "$next_story" ]; then
        local prompt_file="${PROMPTS_DIR}/${next_story}.md"
        if [ -f "$prompt_file" ]; then
            echo "$prompt_file"
            return 0
        fi
    fi
    
    return 1
}

# ─── Launch loop ──────────────────────────────────────────
launch_loop() {
    local prompt_file="$1"
    local foreground="${2:-false}"
    
    log "Launching Ralph loop..."
    log "Story: $(basename "$prompt_file" .md)"
    log "Agent: $AGENT"
    log "Model: $MODEL"
    log "Max iterations: $MAX_ITERATIONS"
    log "Prompt file: $prompt_file"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="${LOGS_DIR}/ralph_${timestamp}.log"
    local story_id=$(basename "$prompt_file" .md)
    
    # Update prd.json - mark as started
    if [ -f "${PAI_DIR}/prd.json" ]; then
        local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        jq ".userStories |= map(if .id == \"$story_id\" then .startedAt = \"$ts\" else . end)" "${PAI_DIR}/prd.json" > "${PAI_DIR}/prd.json.tmp"
        mv "${PAI_DIR}/prd.json.tmp" "${PAI_DIR}/prd.json"
    fi
    
    if [ "$foreground" = "true" ]; then
        log "Running in FOREGROUND mode"
        log "Press Ctrl+C to stop"
        echo ""
        
        ralph \
            --file "$prompt_file" \
            --agent "$AGENT" \
            --model "$MODEL" \
            --max-iterations "$MAX_ITERATIONS" \
            --completion-promise "$COMPLETION_PROMISE" \
            --allow-all \
            --no-questions \
            2>&1 | tee "$log_file"
    else
        log "Running in BACKGROUND mode"
        log "Log file: $log_file"
        log "Monitor with: tail -f $log_file"
        log "Stop with: launch-ralph.sh --stop"
        
        nohup ralph \
            --file "$prompt_file" \
            --agent "$AGENT" \
            --model "$MODEL" \
            --max-iterations "$MAX_ITERATIONS" \
            --completion-promise "$COMPLETION_PROMISE" \
            --allow-all \
            --no-questions \
            > "$log_file" 2>&1 &
        
        local pid=$!
        echo $pid > "${LOGS_DIR}/ralph.pid"
        
        log "PID: $pid"
        log ""
        log "Commands:"
        log "  tail -f $log_file     # View live output"
        log "  ralph --status        # Check loop status"
        log "  launch-ralph.sh --stop  # Stop loop"
    fi
}

# ─── Check status ─────────────────────────────────────────
check_status() {
    log "Checking Ralph loop status..."
    
    if [ -f "${LOGS_DIR}/ralph.pid" ]; then
        local pid=$(cat "${LOGS_DIR}/ralph.pid")
        if kill -0 "$pid" 2>/dev/null; then
            log "Loop is RUNNING (PID: $pid)"
        else
            warn "Loop PID file exists but process not running"
            rm -f "${LOGS_DIR}/ralph.pid"
        fi
    else
        log "No active loop found"
    fi
    
    # Also check ralph --status
    if command -v ralph &>/dev/null; then
        echo ""
        ralph --status 2>/dev/null || warn "ralph --status failed"
    fi
}

# ─── Stop loop ────────────────────────────────────────────
stop_loop() {
    log "Stopping Ralph loop..."
    
    if [ -f "${LOGS_DIR}/ralph.pid" ]; then
        local pid=$(cat "${LOGS_DIR}/ralph.pid")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            log "Sent SIGTERM to PID $pid"
            sleep 2
            if kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid"
                log "Sent SIGKILL to PID $pid"
            fi
        fi
        rm -f "${LOGS_DIR}/ralph.pid"
    fi
    
    # Also try ralph's stop mechanism
    pkill -f "ralph.*file.*PORT-" 2>/dev/null || true
    
    success "Loop stopped"
}

# ─── List available stories ───────────────────────────────
list_stories() {
    log "Available stories:"
    
    if [ -f "${PAI_DIR}/prd.json" ]; then
        echo ""
        echo "From prd.json:"
        jq -r '.userStories[] | "  " + (if .passes then "✅" else "⬜" end) + " " + .id + ": " + .title' "${PAI_DIR}/prd.json"
    fi
    
    echo ""
    echo "Prompt files:"
    for f in "${PROMPTS_DIR}"/*.md; do
        if [ -f "$f" ]; then
            echo "  📄 $(basename "$f")"
        fi
    done
}

# ─── Main ─────────────────────────────────────────────────
main() {
    local story_id=""
    local foreground="false"
    local custom_prompt=""
    local action="launch"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--story)
                story_id="$2"
                shift 2
                ;;
            -i|--iterations)
                MAX_ITERATIONS="$2"
                shift 2
                ;;
            -m|--model)
                MODEL="$2"
                shift 2
                ;;
            -a|--agent)
                AGENT="$2"
                shift 2
                ;;
            -f|--foreground)
                foreground="true"
                shift
                ;;
            -p|--prompt)
                custom_prompt="$2"
                shift 2
                ;;
            --status)
                action="status"
                shift
                ;;
            --stop)
                action="stop"
                shift
                ;;
            --list)
                action="list"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                story_id="$1"
                shift
                ;;
        esac
    done
    
    setup
    
    case "$action" in
        status)
            check_status
            ;;
        stop)
            stop_loop
            ;;
        list)
            list_stories
            ;;
        launch)
            check_prerequisites
            
            local prompt_file=""
            
            if [ -n "$custom_prompt" ]; then
                prompt_file="$custom_prompt"
            else
                prompt_file=$(find_prompt "$story_id") || {
                    echo "❌ No prompt file found for story: ${story_id:-auto-detect}"
                    echo "Available prompts:"
                    ls -1 "${PROMPTS_DIR}"/*.md 2>/dev/null || echo "  (none)"
                    exit 1
                }
            fi
            
            launch_loop "$prompt_file" "$foreground"
            ;;
    esac
}

main "$@"
