# PAI Security System v4.0

> **legacy/reference material** — This directory documents the original Claude Code security system. The current OpenCode port enforces security in the PAI plugin and validates it with the OpenCode test suite.

## Active OpenCode Security Contract

Active files:

- `~/.config/opencode/plugins/pai-hooks.js`
- `~/.config/opencode/plugins/lib/pai-hooks.lib.js`
- `opencode/tests/security-pipeline.test.ts`
- `opencode/tests/plugin-integration.test.ts`

Current OpenCode enforcement:

1. `chat.message` pre-sanitizes blocked user prompts before model processing.
2. `tool.execute.before` blocks catastrophic bash commands and pipe-to-shell execution.
3. `tool.execute.before` blocks zero-access writes and sensitive read paths such as `/etc/shadow`.
4. `tool.execute.before` requires approval/logging for credential-bearing reads such as `.env`, `.npmrc`, cloud credentials, and SSH private keys.
5. Bash reads of credential files, such as `cat .env`, require approval.
6. High-confidence secret material, such as private keys or real API-key assignments, is blocked from being written outside protected PAI zones.
7. `permission.asked`/`permission.ask` mirrors the same rule-based decisions for bash/read/write permission prompts and emits `permission_needed` notifications when user approval is required.
8. `tool.execute.after` logs tool failures and scans fetched/web content for prompt-injection signals; this scan is advisory because content is already in context.

Not implemented in the OpenCode port:

- LLM-based SmartApprover.
- Editable Observatory security dashboard.
- Full external `patterns.yaml` policy loader.

## Original Claude Code System

1. **SecurityPipeline hook** (PreToolUse) — InspectorPipeline with PatternInspector(100), EgressInspector(90), RulesInspector(50). Hard-blocks catastrophic bash commands and credential access via `exit(2)`. The only component that can prevent a tool call from executing.
2. **ContentScanner hook** (PostToolUse) — InjectionInspector scans WebFetch/WebSearch output for prompt injection patterns. Injects warnings, logs detections. Cannot block (PostToolUse limitation).
3. **SmartApprover hook** (PermissionRequest) — trusted workspace paths auto-approve; non-trusted paths classified as read (auto-approve) or write (prompt user) via haiku.
4. **PromptGuard hook** (UserPromptSubmit) — two-tier user prompt scanning: heuristic pre-filter (<1ms), then haiku semantic analysis (~1-2s) on flagged prompts. Detects exfiltration intent and prompt injection before Claude processes them.
5. **SkillGuard** — Pulse HTTP route (`localhost:31337/hooks/skill-guard`). Blocks 1 false-positive skill. Minor.
6. **AgentGuard** — Pulse HTTP route (`localhost:31337/hooks/agent-guard`). Warns on foreground agents. Does not block.
7. **Security protocol** — Unified security instructions loaded at startup (AI self-enforcement + hook enforcement).

See `ARCHITECTURE.md` for honest details on what each component does and does not do.

## Public Files (this directory)

| File | What it is |
|------|-----------|
| `ARCHITECTURE.md` | How the system actually works, including limitations |
| `HOOKS.md` | What hooks run, what they enforce, what they don't |
| `PROMPTINJECTION.md` | Generic framework overview (public) |
| `COMMANDINJECTION.md` | Generic framework overview (public) |
| `patterns.example.yaml` | Fallback pattern template (only used if USER file missing) |

## Private Files (USER/SECURITY/)

| File | What it is |
|------|-----------|
| `PAISECURITYSYSTEM.md` | Unified security protocol loaded at startup (all components) |
| `patterns.yaml` | Active security patterns — the actual rules SecurityPipeline enforces |
| `SECURITY_RULES.md` | User-written natural language rules evaluated by RulesInspector via LLM |
| `COMMANDINJECTION.md` | Code safety reference (not auto-loaded, manual reference via CONTEXT_ROUTING) |
| `QUICKREF.md` | What's blocked, logged, and not protected |
| `PROJECTRULES.md` | Project-specific rules (currently empty) |

## Observatory Security Page

The PAI Observatory dashboard includes a dedicated security page at `localhost:31337/security` that provides a visual interface for managing the security system:

- **PATTERNS.yaml editor** — view and edit active security patterns enforced by SecurityPipeline
- **SECURITY_RULES.md editor** — view and edit natural language rules evaluated by RulesInspector
- **Event viewer** — inspect security events and hook activity
- **Hook inspector** — review hook execution details and results

**Deployment:** The Observatory is a Next.js static export. Pulse serves it via a symlink: `Pulse/dashboard/out -> Observability/out`. To deploy changes: `bun run build` in the Observability directory, then `launchctl stop com.pai.pulse && launchctl start com.pai.pulse`.
