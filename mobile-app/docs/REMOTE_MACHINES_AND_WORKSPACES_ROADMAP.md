# Mobile App: Remote Machines, Workspaces, Providers And PAI Integration

Updated: 2026-06-09

## Scope

This direction applies only to the mobile app. The canonical implementation remains the Flutter app in `mobile-app/apps/flutter`.

The product should evolve from an OpenCode mobile client into a private mobile control surface for PAI/OpenCode across one or more machines.

## Product Direction

The app should support a user who owns multiple server machines and wants to operate them from mobile over a private network.

The core navigation model should be:

```text
Machine -> Workspace/Directory -> Sessions -> Chat / Terminal / Worktree
```

The app should not force every chat through a project-selection flow. A default general session should exist per machine, backed by the machine home directory, so the user can ask simple questions immediately.

## Verified OpenCode Behavior

OpenCode Server supports directory-scoped operations through a `directory` query parameter.

Verified locally against OpenCode `1.16.2`:

- `GET /find/file?...&directory=/some/path` searches within that directory.
- `POST /session?directory=/some/path` creates a session scoped to that directory.
- `GET /session?directory=/some/path` lists sessions for that directory.
- Created sessions include directory/path metadata.

Current mobile code already has partial directory support:

- `OpenCodeProvider` tracks a current directory.
- Message sending, event subscription, session listing, and file search can receive `directory`.
- `createSession` still needs to pass `directory` to OpenCode.
- The UI still lacks a first-class workspace/directory selection flow.

## Connection Model

Primary production transport should be direct access over the private network, usually Tailscale.

SSH tunnels should not be the central production transport. They are useful, but should remain auxiliary because tunnels are operationally less reliable and add unnecessary moving parts when both devices are already on the same private network.

Preferred transport layers:

- Primary: mobile app connects directly to OpenCode Server at the machine tailnet address.
- Auxiliary: SSH for terminal access, bootstrap, diagnostics, and one-off remote operations.
- Future: a small PAI machine agent can replace fragile SSH-dependent orchestration where richer machine introspection is needed.

## Machine Model

The app should eventually support multiple machines.

Each machine should have:

- Friendly name.
- Network address or MagicDNS name.
- OpenCode server URL/port.
- Authentication metadata.
- Default directory, usually the machine home path.
- Recent/favorite workspaces.
- Provider configuration status.
- Optional SSH configuration for terminal/bootstrap.

The app should treat machine identity as a first-class concept, not just a saved server URL.

## Workspace And Directory UX

Directories should be presented as workspaces, not as a raw required path field.

A workspace should include:

- Friendly display name.
- Absolute server path.
- Short path display, such as `~/Work/Personal_AI_Infrastructure`.
- Owning machine.
- Git branch when available.
- Worktree state when available, such as clean/dirty and changed-file count.
- Recent sessions in that workspace.
- Optional favorite/pin state.

The mobile UI should avoid making a giant file tree the main navigation. That is heavy for mobile and not the normal path for starting a chat.

Preferred UX:

- Machine selector first, when multiple machines exist.
- Workspace switcher in the chat header or session creation flow.
- Recent and favorite workspaces before manual path entry.
- Manual directory entry available for power-user cases.
- Path validation before creating a directory-scoped session.
- Sessions grouped or filterable by workspace.
- Chat header shows current machine, workspace/path, and branch when available.

## Default Session Behavior

Every machine should have a default general chat session.

Recommended behavior:

- Default directory is the machine home directory.
- UI may display it as `~`.
- Internally prefer an absolute path resolved on the server, such as `/home/konanzin`.
- If the user creates a new session without selecting a directory, use the machine default directory.
- If the user selects a directory, create the session with that directory.

This keeps casual chat friction low while still allowing project-specific sessions.

## Session Creation

The immediate implementation target is:

- Add `directory` support to `OpenCodeClient.createSession`.
- Add provider/session-provider flow support for creating sessions in the current or selected directory.
- Add a simple UI affordance to choose a directory when creating a new session.
- Keep directory selection optional.
- Preserve the existing default session behavior for fast chat.

The first version can be simple: manual path entry plus recent workspace reuse. Rich discovery can come later.

## Worktree Visibility

OpenCode gives partial project awareness through directory-scoped sessions and file search.

For richer worktree visibility, the app should not rely only on OpenCode session APIs. Useful mobile worktree data includes:

- Current branch.
- Dirty/clean state.
- Changed-file count.
- Recent commits.
- Current repo root.
- Whether the selected path is inside a git repository.

Implementation options:

- Short term: collect this over SSH when SSH is configured.
- Better long term: expose it through a PAI machine agent.
- Do not block the first directory/session milestone on full worktree visibility.

## Terminal

Terminal access is useful and should be supported, but it is not the primary connection model for chat.

Recommended role:

- Open terminal for the selected machine.
- Prefer terminal starting in the selected workspace directory.
- Use SSH as the likely initial implementation path.
- Keep terminal UX separate from chat, while allowing "open terminal here" from a workspace or chat.

## Provider Management

The mobile app should allow adding providers, not only selecting already configured models.

Provider credentials should be stored on the server machine, not as the mobile app's source of truth.

Expected provider flow:

1. User opens machine settings.
2. User opens Providers.
3. App lists configured providers and available models.
4. User taps Add Provider.
5. User chooses provider type, such as Kimi, OpenAI, Anthropic, OpenRouter, or Custom.
6. User enters required fields, such as API key, base URL, and optional display name.
7. App sends the provider configuration to the selected machine.
8. Machine writes the config to OpenCode-compatible storage or runs the equivalent provider setup flow.
9. App validates the provider and refreshes models.

Important constraint:

- Provider secrets must remain machine-side.
- The app may temporarily hold a key during entry/submission, but should not persist it unnecessarily.
- Any provider-list API response that contains secrets must be sanitized before display or logging.

Current note:

- OpenCode TUI can add providers, so mobile should aim to provide equivalent capability.
- If OpenCode HTTP API lacks a clean provider-write endpoint, the machine-side path can use OpenCode CLI/config orchestration until a better API exists.

## Local App Security

The app should eventually require local unlock because it will control private machines and provider setup.

Roadmap item:

- Add app unlock with password/PIN and biometric unlock.
- Use it before exposing PAI, machine credentials, provider setup, or terminal access.
- Keep server/machine credentials in secure storage.

This is especially relevant once the app can manage providers and open terminals.

## PAI Integration

The app should become integrated with PAI, not remain only an OpenCode session client.

Near-term PAI role:

- Mobile control surface for machine/session/workspace context.
- Chat interface backed by OpenCode.
- Worktree-aware project context.
- Provider and model management per machine.

Future PAI machine agent role:

- Resolve home paths and workspace metadata.
- Discover git repositories.
- Report worktree status.
- Bootstrap or supervise OpenCode Server.
- Provide safer provider-management operations.
- Provide richer terminal/session orchestration without depending on SSH tunnels.

## Implementation Priority

Recommended next sequence:

1. Support `directory` in session creation.
2. Add machine default directory and default general session behavior.
3. Add optional directory selection when creating a session.
4. Show machine/workspace/path in the chat and session UI.
5. Add recent/favorite workspaces.
6. Add basic worktree status for selected workspace.
7. Add multi-machine management.
8. Add provider management from the mobile client, storing secrets on the machine.
9. Add local PIN/biometric unlock.
10. Add SSH terminal as auxiliary machine access.
11. Introduce a PAI machine agent when SSH/config orchestration starts becoming the bottleneck.

## Non-Goals For The Next Milestone

- Do not make SSH tunnels the primary production transport.
- Do not force project selection before every chat.
- Do not build a full mobile file explorer as the first directory UX.
- Do not store provider secrets as long-lived mobile app data.
- Do not block basic directory-scoped sessions on full worktree visibility.

## Open Decisions

- Exact machine profile data model.
- Whether the first workspace selector lives in the session creation screen, chat header, drawer, or a dedicated machine/workspace screen.
- How the app should resolve `~` to an absolute path before creating a session.
- Whether provider setup should initially call OpenCode CLI over SSH or use a machine-side PAI agent.
- Exact unlock policy: app launch only, sensitive actions only, or both.
