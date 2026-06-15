# PAI Configuration

PAI uses directly-edited configuration files. There is no template rendering or code generation step — files are what they are.

## Core Files

| File | Purpose | Git Status |
|------|---------|------------|
| `opencode.jsonc` | OpenCode runtime config — plugin, agents, permissions, instructions | Tracked |
| `CLAUDE.md` | Operational instructions loaded at session start | Tracked |
| `PAI/RUNTIME_CONSTITUTION.md` | Constitutional rules loaded by the OpenCode PAI plugin | Tracked |
| `PAI/USER/Config/PAI_CONFIG.yaml` | Credentials store for private skills (HOMEBRIDGE, etc.) | Gitignored |

## How It Works

**Edit directly.** When you need to change plugin wiring, agents, permissions, or runtime behavior, edit `opencode/config/opencode.jsonc.template` and reinstall/regenerate. When you need to change operational rules or context routing, edit `CLAUDE.md`. When you need to change constitutional rules, edit `PAI/RUNTIME_CONSTITUTION.md`.

Changes to `opencode.jsonc`, `CLAUDE.md`, and `RUNTIME_CONSTITUTION.md` take effect after the OpenCode runtime/plugin reloads.

## Public Releases

The original Shadow Release system (`skills/_PAI/TOOLS/ShadowRelease.ts`) is deferred in the current OpenCode port. Current release hygiene is enforced by the installer, install manifest, promise-integrity validator, doc-integrity validator, and explicit preservation of `PAI/USER`, `PAI/MEMORY`, and `.env`.

See the _PAI skill workflows:

- **CreateShadowRelease** — fresh build at a version: `bun run ShadowRelease.ts --create <version>`
- **UpdateShadowRelease** (`/ur`) — rebuilds at the current version (alias for create; no incremental mode under containment): `bun run ShadowRelease.ts --update`
- **CheckReleaseSecurity** — read-only gate check on existing staging: `bun run ShadowRelease.ts --check [--version <v>]`

The old filter/allowlist system (`release-patterns.yaml`, `template-map.yaml`, `SecurityVerifier.ts`, `IncrementalRelease.ts`, `CheckReleaseSafety.ts`) was retired. Under containment, sensitive-data policy lives in the tool's exclusion list and zone deletion code, not in YAML configs.

## PAI_CONFIG.yaml

This file is a credentials store, not a template source. Private skills (like `_HOMEBRIDGE`) read it directly for API keys and service credentials. It is gitignored and never included in public releases.

## Identity

DA and principal identity values live directly in `settings.json` under `daidentity` and `principal` keys. Hooks read these via `hooks/lib/identity.ts`.
