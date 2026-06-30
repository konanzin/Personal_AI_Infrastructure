#!/usr/bin/env bash
# Manage the local PAI Edge TTS voice preference.

set -euo pipefail

OPENCODE_DIR="${OPENCODE_DIR:-${HOME}/.config/opencode}"
PAI_DIR="${PAI_DIR:-${OPENCODE_DIR}/PAI}"
CONFIG_FILE="${PAI_VOICE_CONFIG:-${PAI_EDGE_TTS_CONFIG:-${PAI_DIR}/USER/Config/voice.env}}"
VENV_PYTHON="${OPENCODE_DIR}/tts-venv/bin/python"

usage() {
    cat <<'EOF'
Usage:
  voice-config.sh list [language]
  voice-config.sh show
  voice-config.sh on
  voice-config.sh off
  voice-config.sh set <voice> [language]
  voice-config.sh test [text]

Examples:
  voice-config.sh list pt-BR
  voice-config.sh off
  voice-config.sh on
  voice-config.sh set pt-BR-AntonioNeural
  voice-config.sh test "Teste de voz do PAI"
EOF
}

normalize_language() {
    local language="${1:-pt-BR}"
    language="${language/_/-}"
    local region
    case "$language" in
        pt) echo "pt-BR" ;;
        en) echo "en-US" ;;
        pt-*) region="${language#pt-}"; echo "pt-${region^^}" ;;
        en-*) region="${language#en-}"; echo "en-${region^^}" ;;
        *) echo "$language" ;;
    esac
}

env_key_for_language() {
    normalize_language "$1" | tr '[:lower:]' '[:upper:]' | sed -E 's/[^A-Z0-9]+/_/g'
}

edge_command() {
    if [ -x "$VENV_PYTHON" ] && "$VENV_PYTHON" -c 'import edge_tts' >/dev/null 2>&1; then
        printf '%s\n' "$VENV_PYTHON|-m|edge_tts"
        return 0
    fi

    if command -v edge-tts >/dev/null 2>&1; then
        printf '%s\n' "$(command -v edge-tts)"
        return 0
    fi

    local python
    for python in python3 python; do
        if command -v "$python" >/dev/null 2>&1 && "$python" -c 'import edge_tts' >/dev/null 2>&1; then
            printf '%s\n' "$python|-m|edge_tts"
            return 0
        fi
    done

    return 1
}

run_edge() {
    local spec
    if ! spec="$(edge_command)"; then
        echo "Edge TTS is not installed. Run opencode/install.sh without --no-bootstrap." >&2
        return 1
    fi

    local -a cmd=()
    IFS='|' read -r -a cmd <<< "$spec"
    "${cmd[@]}" "$@"
}

list_voices() {
    local language
    language="$(normalize_language "${1:-${PAI_EDGE_TTS_LANGUAGE:-${PAI_VOICE_LANGUAGE:-pt-BR}}}")"

    run_edge --list-voices | awk -v language="$language" '
        $1 ~ "^" language "-" {
            n += 1
            printf "%2d. %s", n, $1
            for (i = 2; i <= NF; i += 1) printf " %s", $i
            printf "\n"
        }
        END { if (n == 0) exit 2 }
    '
}

voice_exists() {
    local voice="$1"
    run_edge --list-voices | awk -v voice="$voice" '$1 == voice { found = 1 } END { exit found ? 0 : 1 }'
}

derive_language() {
    local voice="$1"
    if [[ "$voice" =~ ^[a-z][a-z]-[A-Z][A-Z]- ]]; then
        echo "${voice:0:5}"
    else
        normalize_language "${2:-pt-BR}"
    fi
}

set_config_value() {
    local key="$1"
    local value="$2"
    local tmp

    mkdir -p "$(dirname "$CONFIG_FILE")"
    tmp="$(mktemp)"
    if [ -f "$CONFIG_FILE" ]; then
        grep -v -E "^${key}=" "$CONFIG_FILE" > "$tmp" || true
    fi
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv "$tmp" "$CONFIG_FILE"
}

get_config_value() {
    local key="$1"
    [ -f "$CONFIG_FILE" ] || return 1
    local line
    line="$(grep -E "^(export[[:space:]]+)?${key}=" "$CONFIG_FILE" | tail -n1)"
    [ -n "$line" ] || return 1
    local value="${line#*=}"
    value="${value%\"}"; value="${value#\"}"
    value="${value%\'}"; value="${value#\'}"
    printf '%s' "$value"
}

show_config() {
    echo "Voice config: $CONFIG_FILE"
    if [ -f "$CONFIG_FILE" ]; then
        grep -E '^(PAI_EDGE_TTS_|PAI_VOICE_)' "$CONFIG_FILE" || true
    else
        echo "No saved voice config yet."
        echo "Default pt-BR voice: pt-BR-FranciscaNeural"
        echo "Default en-US voice: en-US-AvaNeural"
    fi
}

set_voice_enabled() {
    local enabled="$1"
    set_config_value "PAI_VOICE_ENABLED" "$enabled"
    if [ "$enabled" = "true" ]; then
        echo "Voice feedback enabled"
    else
        echo "Voice feedback disabled"
    fi
    echo "Config: $CONFIG_FILE"
}

set_voice() {
    local voice="${1:-}"
    local language="${2:-}"
    if [ -z "$voice" ]; then
        echo "Missing voice name." >&2
        usage >&2
        return 1
    fi

    if ! voice_exists "$voice"; then
        echo "Voice not found: $voice" >&2
        echo "Run: $0 list ${language:-pt-BR}" >&2
        return 1
    fi

    language="$(derive_language "$voice" "${language:-pt-BR}")"
    local key
    key="PAI_EDGE_TTS_VOICE_$(env_key_for_language "$language")"

    set_config_value "PAI_EDGE_TTS_LANGUAGE" "$language"
    set_config_value "$key" "$voice"

    echo "Saved $key=$voice"
    echo "Config: $CONFIG_FILE"
    echo "Restart the desktop renderer to apply this voice."
}

test_voice() {
    local text="${*:-Teste de voz do PAI}"
    if [ ! -f "$PAI_DIR/broker/edge-tts-speaker.ts" ]; then
        echo "Missing speaker: $PAI_DIR/broker/edge-tts-speaker.ts" >&2
        return 1
    fi

    # Resolve the language we'll demo so a fresh `test` (before any voice is
    # saved) speaks in the helper's pt-BR default instead of the speaker's
    # neutral en-US fallback. Saved config and env still take precedence.
    local language
    language="$(get_config_value PAI_EDGE_TTS_LANGUAGE || true)"
    language="${language:-${PAI_EDGE_TTS_LANGUAGE:-${PAI_VOICE_LANGUAGE:-pt-BR}}}"
    language="$(normalize_language "$language")"

    # Emit a single valid JSON line so the speaker selects the voice by
    # language; escape backslashes/quotes and flatten newlines.
    text="${text//$'\n'/ }"
    text="${text//\\/\\\\}"
    text="${text//\"/\\\"}"
    printf '{"text":"%s","language":"%s"}\n' "$text" "$language" \
        | PAI_EDGE_TTS_CONFIG="$CONFIG_FILE" bun "$PAI_DIR/broker/edge-tts-speaker.ts"
}

cmd="${1:-help}"
shift || true

case "$cmd" in
    list) list_voices "${1:-}" ;;
    show) show_config ;;
    on) set_voice_enabled true ;;
    off) set_voice_enabled false ;;
    set) set_voice "$@" ;;
    test) test_voice "$@" ;;
    help|-h|--help) usage ;;
    *)
        echo "Unknown command: $cmd" >&2
        usage >&2
        exit 1
        ;;
esac
