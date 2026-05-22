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
- Observability Streams — Six JSONL telemetry streams (classifier, guards, sessions, failures, traces)
- `opencode/bin/deploy-plugin.sh` — Hot-deploy plugin without full reinstall
- `opencode/tests/` — Unit and integration test suite (107 tests)
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
- Parity is measured by validator coverage and real usage, not line-by-line equivalence.

Current state: **142/142 checks passing** (75 structural + 57 behavioral + 10 E2E runtime). Parity estimate: **~90-95%**.
