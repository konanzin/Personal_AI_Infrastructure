# PAI 5.0.0 for OpenCode

> **Personal AI Infrastructure (PAI)** ported from Claude Code to OpenCode.
> Multi-provider, open-source, vendor-independent Life OS.

## What Was Ported

PAI v5.0.0 is a complete port of the Personal AI Infrastructure from Anthropic's Claude Code to the open-source OpenCode CLI. The port preserves 100% of PAI's core functionality while eliminating vendor lock-in.

### Key Changes

| Component | Claude Code | OpenCode |
|-----------|-------------|----------|
| **Runtime** | Proprietary CLI | Open-source multi-provider |
| **Config** | `~/.claude/settings.json` | `~/.config/opencode/opencode.jsonc` |
| **Hooks** | 38 TypeScript hooks | 8 JavaScript plugins |
| **Agents** | Embedded in settings | Individual `.md` files |
| **Model** | Claude only | Kimi, Anthropic, OpenAI, Google |
| **Skills** | `~/.claude/skills/` | `~/.config/opencode/skills/` |

### Architecture Overview

```
~/.config/opencode/
├── opencode.jsonc          # Main configuration
├── plugins/
│   ├── pai-hooks.js        # Main PAI plugin (8 event handlers)
│   └── pai-hooks.lib.js    # Shared utilities
├── agents/                 # 18 individual agent definitions
│   ├── Algorithm.md
│   ├── Engineer.md
│   └── ...
├── commands/               # Custom slash commands
│   ├── context-search.md
│   ├── cs.md
│   └── pu.md
└── PAI/                    # PAI core directory
    ├── CLAUDE.md           # Operational instructions
    ├── ALGORITHM/          # Algorithm workflows
    ├── DOCUMENTATION/      # System docs
    ├── MEMORY/             # State, work, research, learning
    ├── PULSE/              # Dashboard & monitoring
    ├── TOOLS/              # Utility scripts
    ├── TEMPLATES/          # ISA templates
    ├── USER/               # Principal data
    │   ├── TELOS/
│   │   ├── PRINCIPAL_IDENTITY.md
    │   └── DA_IDENTITY.md
    └── bin/
        ├── install-pai-opencode.sh
        ├── validate-pai-installation.sh
        └── launch-ralph.sh
```

## Prerequisites

- **git** — For cloning/updating PAI
- **opencode** — The OpenCode CLI ([opencode.ai](https://opencode.ai))
- **bun** — Optional but recommended ([bun.sh](https://bun.sh))

Verify prerequisites:

```bash
git --version
opencode --version
bun --version  # optional
```

## Installation

### Quick Install

```bash
# 1. Clone the PAI repository
git clone https://github.com/danielmiessler/Personal_AI_Infrastructure.git /tmp/pai

# 2. Run the idempotent installer
bash /tmp/pai/PAI/bin/install-pai-opencode.sh
```

The installer:
1. Checks prerequisites (git, opencode)
2. Backs up existing `~/.config/opencode/`
3. Creates directory structure
4. Copies PAI files to `~/.config/opencode/PAI/`
5. Installs plugins to `~/.config/opencode/plugins/`
6. Installs agents to `~/.config/opencode/agents/`
7. Configures `opencode.jsonc`
8. Creates backward-compat symlink `~/.claude/` → `~/.config/opencode/PAI`

### Manual Install

If you prefer manual installation:

```bash
# Create directories
mkdir -p ~/.config/opencode/{plugins,agents,commands,skills}
mkdir -p ~/.config/opencode/PAI/{ALGORITHM,DOCUMENTATION,MEMORY/{STATE,WORK,RESEARCH,LEARNING},PULSE,TOOLS,TEMPLATES,USER/{TELOS,Config},bin,logs}

# Copy PAI core files
cp -r /path/to/pai/PAI/* ~/.config/opencode/PAI/
cp /path/to/pai/plugins/* ~/.config/opencode/plugins/
cp /path/to/pai/agents/* ~/.config/opencode/agents/

# Create symlink for backward compatibility
ln -s ~/.config/opencode/PAI ~/.claude
```

### Verify Installation

```bash
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

Expected output: `64/64 checkpoints passed (100%)`

## Quick Start Guide

### 1. First Launch

```bash
opencode
```

PAI loads automatically via the plugin system. You will see the PAI banner and status.

### 2. Check Status

```bash
opencode /status
```

Shows: PAI version, context usage, active work, available agents.

### 3. Run Your First Algorithm

```bash
opencode /pai "Plan my week"
```

This executes the full PAI Algorithm workflow.

### 4. Interview (Optional)

```bash
opencode /interview
```

Captures your TELOS, goals, and identity for personalized assistance.

## Available Commands

PAI registers these slash commands in OpenCode:

| Command | Description | Example |
|---------|-------------|---------|
| `/pai` | Execute PAI Algorithm workflow | `/pai "Refactor auth module"` |
| `/status` | Show PAI status line | `/status` |
| `/interview` | Run TELOS interview | `/interview` |
| `/pulse` | Check Pulse dashboard | `/pulse` |
| `/context` | Show context usage | `/context` |
| `/rate` | Rate session satisfaction (1-10) | `/rate 9` |
| `/e1` | Standard effort, fast path | `/e1 "Fix typo"` |
| `/e2` | Extended effort | `/e2 "Add feature"` |
| `/e3` | Advanced effort | `/e3 "Refactor module"` |
| `/e4` | Deep effort | `/e4 "Architecture review"` |
| `/e5` | Comprehensive effort | `/e5 "Full system audit"` |

### Effort Levels Explained

- **E1** — Simple tasks, one file, quick fixes
- **E2** — Multi-file changes, standard complexity
- **E3** — Complex tasks, requires planning, may spawn Forge
- **E4** — Deep investigation, architecture decisions
- **E5** — Comprehensive analysis, full system context

## Architecture Overview

### Plugin System

The main plugin (`pai-hooks.js`) registers 8 event handlers:

| Event | Handler | Purpose |
|-------|---------|---------|
| `tool.execute.before` | SecurityInspector | Pre-execution security scan |
| `session.created` | loadContext | Load PAI context files |
| `session.idle` | cleanupSession | Session cleanup |
| `tool.execute.after` | trackToolActivity | Log tool usage |
| `tool.execute.after` | scanContent | Content validation |
| `message.updated` | guardPrompt | Prompt injection guard |
| `session.idle` | captureSatisfaction | Satisfaction tracking |
| `session.idle` | learnFromWork | Learning capture |

### Agent System

18 agents are defined as individual `.md` files in `~/.config/opencode/agents/`:

- **Algorithm** — ISC and algorithm workflows
- **Engineer** — Principal engineer (Marcus Webb)
- **Forge** — OpenAI-family code producer
- **Anvil** — Moonshot-family code producer
- **Architect** — System design specialist
- **Designer** — UX/UI specialist
- **Cato** — Cross-vendor ISA auditor
- **Silas** — Offensive security specialist
- **ClaudeResearcher** — Academic researcher
- **GeminiResearcher** — Multi-perspective researcher
- **GrokResearcher** — Contrarian analyst
- **PerplexityResearcher** — Investigative analyst
- **CodexResearcher** — Technical archaeologist
- **Artist** — Visual content creator
- **Arthur** — Credential custodian
- **BrowserAgent** — Browser automation
- **QATester** — QA validation
- **UIReviewer** — UI review

### Memory System

```
PAI/MEMORY/
├── STATE/        # Session registry, work tracking
├── WORK/         # Active and completed work
├── RESEARCH/     # Research artifacts
├── LEARNING/     # Feedback and learnings
└── KNOWLEDGE/    # Knowledge archive (People, Companies, Ideas, Research)
```

### Algorithm System

The PAI Algorithm is a structured problem-solving workflow:

1. **OBSERVE** — Gather context, load ISA
2. **THINK** — Analyze, plan approach
3. **EXECUTE** — Implement with appropriate agents
4. **VERIFY** — Validate against ISC
5. **LEARN** — Capture insights

Algorithm versions are stored in `PAI/ALGORITHM/`.

## Configuration

### opencode.jsonc

Main configuration at `~/.config/opencode/opencode.jsonc`:

```json
{
  "model": "kimi-for-coding/k2p6",
  "default_agent": "build",
  "plugin": ["./plugins/pai-hooks.js"],
  "skills": {
    "paths": ["~/.config/opencode/skills"]
  }
}
```

### PAI Metadata

- `PAI/.version.json` — Version info
- `PAI/.preferences.json` — User preferences
- `PAI/.techstack.json` — Technical preferences
- `PAI/.observability.json` — Monitoring config
- `PAI/.notifications.json` — Notification routing

### Environment Variables

Create `~/.config/opencode/PAI/.env`:

```bash
# Optional: API keys for specific tools
ANTHROPIC_API_KEY=your_key
OPENAI_API_KEY=your_key
# PAI_DIR is set automatically by the plugin
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed troubleshooting.

Quick checks:

```bash
# Verify installation
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh

# Check opencode config
opencode config list

# View plugin logs
tail -f ~/.config/opencode/PAI/logs/tool-activity.jsonl
```

## Updating PAI

```bash
# Update PAI core
cd ~/.config/opencode/PAI
git pull origin main

# Re-run installer to update plugins/agents
bash ~/.config/opencode/PAI/bin/install-pai-opencode.sh

# Validate
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

## Support

- **Issues**: [github.com/anomalyco/opencode/issues](https://github.com/anomalyco/opencode/issues)
- **Documentation**: `PAI/DOCUMENTATION/`
- **Algorithm**: Run `/pai "How do I..."`

---

*PAI 5.0.0 — OpenCode Port | 64/64 checkpoints validated*
