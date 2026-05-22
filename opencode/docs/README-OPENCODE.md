# PAI for OpenCode Architecture

PAI for OpenCode installs PAI into OpenCode's native extension points instead of depending on Claude Code paths or settings.

## Layout

```text
~/.config/opencode/
├── opencode.jsonc
├── plugins/
│   ├── pai-hooks.js
│   └── lib/
│       └── pai-hooks.lib.js
├── agents/
│   └── *.md
├── commands/
│   └── *.md
├── skills/
│   └── */SKILL.md
└── PAI/
    ├── ALGORITHM/
    ├── DOCUMENTATION/
    ├── MEMORY/
    ├── PULSE/
    ├── TOOLS/
    ├── TEMPLATES/
    ├── USER/
    └── bin/
```

## Native OpenCode Surfaces

- Config: `opencode/config/opencode.jsonc.template`
- Plugin: `opencode/plugins/pai-hooks.js`
- Plugin library: `opencode/plugins/lib/pai-hooks.lib.js`
- Agents: `opencode/agents/*.md`
- Commands: `opencode/commands/*.md` plus command entries in config
- Validator: `opencode/bin/validate-pai-installation.sh`

## Default PAI Behavior

Normal OpenCode prompts behave like PAI prompts without requiring `/pai`.

The port does this through two native surfaces:

- `agent.build.prompt` in `opencode.jsonc.template` makes the default primary agent a PAI-aware assistant.
- `experimental.chat.system.transform` in `pai-hooks.js` injects PAI runtime context, identity/TELOS excerpts, recent work, and mode/tier classification rules into the system context.

The port now uses a **two-tier classification approach**:

1. **Explicit Classifier** (`mode-classifier.lib.js`): runs on every top-level prompt via the `chat.message` hook, producing a structured `{ MODE, TIER, REASON, SOURCE }` result. This is persisted to session state and injected into the system context.
2. **Model-native fallback**: the injected system context still includes mode rules, but the model is instructed to honor the explicit classification when present. Self-selection is now fallback/backup behavior, not the primary path.

The classifier is **provider-agnostic** with two tiers:

1. **Heuristic classifier** (default): deterministic, zero cost, zero latency. Runs locally without external dependencies.
2. **LLM classifier** (optional): can be enabled via environment variables to use any model available via `opencode run`. Default target model is `opencode/deepseek-v4-flash-free` (free tier, ~4-5s response). Falls back to heuristic on any error or timeout.

Configuration via environment variables:
```bash
PAI_CLASSIFIER_USE_LLM=true              # Enable LLM classifier
PAI_CLASSIFIER_MODEL=opencode/deepseek-v4-flash-free  # Model name (default)
PAI_CLASSIFIER_TIMEOUT_MS=8000           # Timeout (default: 8s)
```

The LLM classifier uses `opencode run --model <model>` internally and includes LRU caching (100 entries, 5min TTL) to avoid redundant calls for identical prompts. Default model is `opencode/deepseek-v4-flash-free` (~4-5s response time).

**Fail-safe:** any classifier error or low-confidence result defaults to `ALGORITHM E3`. Under-escalation is worse than over-escalation in PAI doctrine.

`/pai` remains as an explicit manual shortcut, but it is not the primary path.

## Plugin Responsibilities

`pai-hooks.js` adapts PAI hook behavior to OpenCode events:

- `session.created`: initialize PAI session state and summarize context availability
- `chat.message`: **classify mode/tier explicitly** AND **pre-sanitize blocked prompts before they reach the model** (replaces denied content with security warning)
- `experimental.chat.system.transform`: **inject full PAI runtime context, identity/TELOS excerpts, and mode-classification rules into every system prompt**
- `experimental.session.compacting`: **preserve PAI context and recent work across context window resets**
- `permission.asked`: block dangerous commands at the permission level with explicit notification
- `tool.execute.before`: inspect risky commands, writes, and egress
- `tool.execute.after`: log tool activity and scan fetched content
- `message.updated`: capture ratings/praise and run post-message prompt checks
- `session.idle`: update idle timestamp only
- `session.deleted`: run cleanup, archive, and work-learning behavior where metadata exists

## Known Platform Gaps

- ~~Claude Code's Sonnet-based `UserPromptSubmit` classifier is not yet ported~~ — **RESTORED in v2.6.0** via explicit heuristic classifier with provider-agnostic interface. LLM-backed classification is a future enhancement.
- Claude Code's persistent statusline/sidebar is represented as commands and logs.
- Voice remains external-only via Pulse notifications.

## Validation

Structural validation (70 checks):
```bash
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

Behavioral validation (22 checks):
```bash
bash ~/.config/opencode/PAI/bin/test-behavioral.sh
```

Current score: **107/107 passing** (75 structural + 32 behavioral). Parity estimate: **~87-92%**.
