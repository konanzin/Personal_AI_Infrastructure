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

The model itself decides the mode for each prompt based on the injected rules. There is no external classifier process, no subprocess spawn, and no deterministic regex gate.

`/pai` remains as an explicit manual shortcut, but it is not the primary path.

## Plugin Responsibilities

`pai-hooks.js` adapts PAI hook behavior to OpenCode events:

- `session.created`: initialize PAI session state and summarize context availability
- `chat.message`: pre-sanitize blocked prompt-injection attempts before they reach the model
- `experimental.chat.system.transform`: inject default PAI runtime context and mode-classification rules for every normal prompt
- `tool.execute.before`: inspect risky commands, writes, and egress
- `tool.execute.after`: log tool activity and scan fetched content
- `message.updated`: capture ratings/praise and run post-message prompt checks
- `session.idle`: update idle timestamp only
- `session.deleted`: run cleanup, archive, and work-learning behavior where metadata exists

## Known Platform Gaps

- Claude Code's Sonnet-based `UserPromptSubmit` classifier is approximated with deterministic classification in the OpenCode plugin unless/until we port the inference call.
- Prompt blocking before the model sees the message is handled through `chat.message` prompt replacement for denied prompts; this should be tested against live OpenCode behavior after each OpenCode upgrade.
- Claude Code's persistent statusline/sidebar is represented as commands and logs.

## Validation

```bash
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

The validator checks structure and known failure modes. It is not a full behavioral test suite.
