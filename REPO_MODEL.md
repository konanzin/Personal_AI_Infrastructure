# Repo Model

This document explains how this repository is organized, what belongs here, and how it relates to upstream PAI.

## Self-Contained

This repo is **self-contained**: everything needed to install and run PAI under OpenCode is in this tree. There are no external build steps, no submodule dependencies, and no requirement that upstream PAI be checked out side-by-side.

## Branch Purpose

| Branch | Purpose |
|--------|---------|
| `main` | Reference snapshot of upstream PAI. Read-only baseline; not the working branch. |
| `opencode` | The working product. This is what you install and run. |

`main` exists so we can diff against upstream and cherry-pick selectively. It is not expected to be deployed or run directly.

## Content Taxonomy

Everything in this repo falls into one of three categories:

### 1. Inherited (Vendored Baseline)

Content imported from the upstream PAI runtime. Treated as read-only reference. We do not edit these files in place; if we need a change, we either patch at install time or reimplement natively.

- `PAI/ALGORITHM/` — Algorithm versions and docs
- `PAI/DOCUMENTATION/` — System architecture, memory, hooks, skills docs
- `skills/*/` — PAI skill definitions (SKILL.md, workflows, references)

These are **not** automatically kept in sync with upstream. They were imported once to establish parity, and future updates are selective and manual.

### 2. Adapted

Upstream concepts reimplemented for OpenCode's native extension points. These are the bridge between PAI's design and OpenCode's runtime.

- `opencode/plugins/pai-hooks.js` — OpenCode plugin adapting PAI hook behavior
- `opencode/plugins/lib/pai-hooks.lib.js` — Plugin library (classifier, guards, sync, observability)
- `opencode/agents/*.md` — OpenCode-native agent definitions
- `opencode/commands/*.md` — Slash commands (`/pai`, `/status`, `/interview`, etc.)
- `opencode/config/opencode.jsonc.template` — OpenCode configuration template
- `opencode/bin/validate-pai-installation.sh` — Structural validation
- `opencode/bin/test-behavioral.sh` — Behavioral validation
- `opencode/bin/test-e2e-runtime.sh` — Runtime E2E validation

These files follow PAI's behavioral contract but are implemented using OpenCode APIs, paths, and conventions.

### 3. Native

Original to this repo. No upstream equivalent. These are the value-adds and operational tooling specific to this OpenCode product.

- AgentGuard / SkillGuard — Pre-execution guard rails for agent/skill invocations
- Explicit Mode/Tier Classifier — Deterministic + optional LLM classification
- ISA ↔ Work-State Sync — Backend-only ISA frontmatter to work.json propagation
- Observability Streams — JSONL telemetry streams (classifier, guards, sessions, failures, traces)
- Notifications contract v1 (`notifications.jsonl`) — speakable, template-deterministic events; the producer side of the presence layer (`opencode/docs/NOTIFICATIONS_STREAM.md`)
- Pulse Broker (`opencode/broker/`) — optional SSE fan-out daemon on port 31337 with identified subscriptions, presence-based routing, upstream-compatible `/notify`, and a desktop renderer with Kokoro TTS
- `build-mobile` lean profile — per-message client agent with calibrated system injection for mobile clients
- Runtime event bridge — adapter mapping OpenCode ≥1.16 bus events to the plugin's named handlers
- `opencode/bin/deploy-plugin.sh` — Hot-deploy plugin without full reinstall
- `opencode/tests/` — Unit and integration test suite (137 tests)
- `setup-github.sh`, `PUSH-GITHUB.sh` — Repo automation helpers

## Upstream Sync Policy

- **Not automatic.** We do not auto-sync with upstream on every release.
- **Selective.** We cherry-pick specific changes (new skills, algorithm updates, documentation fixes) when they provide clear value.
- **Manual.** Sync is a conscious decision: read upstream changelog, evaluate relevance, adapt to OpenCode, test, merge.
- **Main as reference.** `main` can be refreshed from upstream at any time to serve as a diff baseline; `opencode` rebases or merges only when we decide to absorb changes.

See `SYNC.md` for the practical workflow.

## Parity Stance

Initial parity with upstream was a deliberate goal to prove the port. Going forward, the product evolves independently:

- We keep behavioral parity where it matters (Algorithm, skills, agent contracts).
- We diverge where OpenCode offers a better native path.
- We add native features that upstream does not have.
- Parity is measured by validator coverage and real usage, not line-by-line equivalence — and it is measured **against the chosen scope below**, not against everything upstream ships.

Current state: **162/162 checks passing** (81 structural + 70 behavioral + 11 E2E runtime) over the core scope: Algorithm, skills, agents, ISA/work-state sync, security guards, classifier, and observability streams.

## Out of Scope by Design

The following upstream subsystems are deliberately not part of this product today. They are not gaps; they are decisions. Agents and docs are written to degrade gracefully when these are absent (health-checked voice curls, structured `unavailable` fallbacks).

| Subsystem | Upstream role | Why excluded | Future path |
|-----------|---------------|--------------|-------------|
| Pulse daemon runtime | Always-on dashboard/notify server on `localhost:31337` | Heavy, desktop-centric; OpenCode product targets a leaner runtime | Mobile app may assume the notify/observer role |
| Voice (ElevenLabs) | Speaks agent updates on the desktop | Depends on Pulse + paid API | Voice rendering on mobile via TTS, fed by plugin events |
| `PAI/TOOLS/` helpers (ForgeProgress, AnvilProgress, CrossVendorAudit, Arthur engine) | Wrap external vendor CLIs and credential policy | Never published upstream; depend on OpenAI/Moonshot accounts | Agents return structured `unavailable`; helpers can be ported if multi-vendor work is adopted |
| Arbol (cloud execution) | Parallel cloud runs | Docs-only upstream | Re-evaluate if needed |
| Feed / Fabric systems | Content pipelines | Docs-only upstream | Re-evaluate if needed |
| Memory consolidation jobs | Pulse-scheduled learning capture | Requires daemon | Candidate for plugin-side or mobile-triggered jobs |
| Terminal tabs / statusline UI | Kitty-based dashboard | Claude Code/desktop-specific | OpenCode-native or mobile UI instead |
