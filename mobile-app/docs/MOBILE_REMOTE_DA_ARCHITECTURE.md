# Mobile Remote DA Architecture

Updated: 2026-06-10

## Executive Decision

The robust target architecture is not "mobile talks directly to a public
OpenCode server". The target should be:

```text
Android app
  -> private tailnet route
  -> per-machine PAI Machine Agent
  -> localhost-only OpenCode server
  -> OpenCode sessions, PTYs, files, projects, providers
```

The mobile app remains the only user-facing control surface. Each remote
machine runs a small, user-level daemon that supervises OpenCode, exposes a
stable machine API, enforces policy, and proxies OpenCode. OpenCode itself
should bind to localhost by default and should not be reachable directly from
the LAN or public internet.

The current SSH bootstrap is a good bridge, but it should become an onboarding
and recovery channel, not the main runtime architecture.

## What The Current App Already Has

The current Flutter app is already close to the product shape:

- `MachineStore` persists multiple machines in secure storage.
- `Machine` has OpenCode URL/auth, default directory, optional SSH, and an
  optional PAI agent URL.
- `ClientProvider` owns one active OpenCode HTTP/SSE client.
- `OpenCodeProvider` owns chat streaming, history, questions, permissions,
  shell/tool parts, current session, and current directory.
- `SessionProvider` lists sessions and now scopes active session persistence by
  machine plus directory.
- `WorkspaceProvider` keeps recent/favorite workspaces.
- `TerminalScreen` already has direct SSH PTY support.
- `MachineCapabilityService` already models the intended fallback order:
  PAI Agent first, SSH second, graceful degradation third.
- `PaiAgentClient` already sketches an agent API for health, workspaces,
  git status, OpenCode lifecycle, system info, and provider setup.

The architectural gap is that OpenCode is still the public runtime endpoint for
the app, and SSH scripts are currently doing orchestration that belongs in a
real machine control plane.

## Requirements Reframed As Architecture Constraints

1. Bijective access to sessions across machines

   A session cannot be represented only by `sessionID`. The canonical identity
   must be:

   ```text
   machineID + workspaceID + opencodeSessionID
   ```

   The app should never restore or open a session without verifying that it
   belongs to the selected machine and directory/workspace.

2. Privacy

   OpenCode should not be exposed publicly. The service should be private by
   construction:

   - Tailscale/tailnet transport for remote access.
   - Tailscale policy denies by default and only allows the mobile/user to the
     machine agent.
   - OpenCode binds to `127.0.0.1`.
   - Public Tailscale Funnel must stay off for this service.
   - If Tailscale Serve is used, proxy only from tailnet HTTPS to localhost.

3. Directory control

   Directory is not a UI hint. It is part of the session contract:

   ```text
   workspaceID = hash(machineID + canonicalRealPath)
   ```

   Every session, file operation, PTY, command, and event subscription must be
   scoped to a canonical directory resolved on the remote machine.

4. Multiple machines

   Machines need stable identities independent of display name or URL. The
   target `machineID` should be derived from the PAI Machine Agent public key
   or installation fingerprint, not from `DateTime.now()`.

5. Shell support

   Terminal support should eventually use OpenCode PTY endpoints when possible,
   because that keeps shell, workspace, audit, and auth under the same control
   plane. Direct SSH PTY remains useful for recovery and for machines where the
   agent/OpenCode path is unavailable.

6. Mobile-only operation

   A machine cannot be controlled before any trust path exists. The minimum
   unavoidable bootstrap is one of:

   - Tailscale SSH or normal SSH credentials.
   - A provider/cloud API that can run a bootstrap command.
   - Physical/local pairing.

   After that first trust path, the mobile app can install and update the
   machine agent without the user logging into the server manually.

7. Security for a privileged DA

   The daemon must be treated as high impact. It should not run as root, should
   not store provider secrets on mobile, should enforce per-client auth, should
   keep an audit log, and should require explicit user approval for dangerous
   actions.

## Recommended Target Architecture

### Component Diagram

```text
┌────────────────────────────────────────────────────────────────┐
│ Android app                                                     │
│                                                                │
│ Machine registry                                                │
│ Workspace registry                                              │
│ Session router                                                  │
│ Chat UI                                                         │
│ Terminal UI                                                     │
│ Local secure storage + biometric/PIN gate                       │
└───────────────┬────────────────────────────────────────────────┘
                │ HTTPS over tailnet, signed app requests
                │
┌───────────────▼────────────────────────────────────────────────┐
│ Tailscale tailnet                                               │
│                                                                │
│ Grants/ACLs: mobile/user -> tag:pai-machine only on agent port  │
│ Optional Tailscale Serve: tailnet HTTPS -> localhost agent      │
└───────────────┬────────────────────────────────────────────────┘
                │
┌───────────────▼────────────────────────────────────────────────┐
│ Remote machine                                                  │
│                                                                │
│ PAI Machine Agent, user-level service                           │
│ - machine identity and pairing                                  │
│ - OpenCode supervision                                          │
│ - session/workspace catalog                                     │
│ - policy enforcement                                            │
│ - OpenCode reverse proxy                                        │
│ - PTY proxy                                                     │
│ - git/file/provider helpers                                     │
│ - audit log                                                     │
│                                                                │
│ localhost-only OpenCode server                                  │
│ - REST/SSE                                                      │
│ - session API                                                   │
│ - event stream                                                  │
│ - file/project/find APIs                                        │
│ - PTY websocket APIs                                            │
└────────────────────────────────────────────────────────────────┘
```

### Runtime Ports

Preferred:

```text
OpenCode:
  bind: 127.0.0.1:4096
  auth: random machine-local password generated by PAI Agent
  exposed to mobile: never directly

PAI Machine Agent:
  bind option A: 127.0.0.1:18181, exposed by Tailscale Serve HTTPS
  bind option B: <tailscale-ip>:18181, firewall restricted to tailscale0
  auth: Tailscale policy plus application-level client signatures
```

Current bridge:

```text
OpenCode:
  bind: 0.0.0.0:4096
  exposed only inside tailnet
  protected by OPENCODE_SERVER_PASSWORD
```

This bridge is acceptable short term, but target architecture should remove
direct OpenCode exposure.

## Machine Identity And Pairing

### Machine ID

Use a stable cryptographic identity:

```text
machineID = "mach_" + base32(blake3(agentPublicKey))[0:26]
```

The current timestamp-based machine IDs are fine for prototype storage, but not
strong enough as durable remote identities.

### Mobile Client ID

On first app install:

```text
clientKey = Ed25519 keypair in Android Keystore
clientID = "mob_" + base32(blake3(clientPublicKey))[0:26]
```

The private key should not be exportable from the app sandbox. Every sensitive
request is signed:

```text
signatureInput =
  method + "\n" +
  path + "\n" +
  timestamp + "\n" +
  nonce + "\n" +
  sha256(body)
```

The agent rejects stale timestamps and replayed nonces.

### Pairing Flow

1. User enters SSH/Tailscale SSH details or selects an already reachable host.
2. App connects over SSH.
3. App uploads or installs the signed PAI Machine Agent package.
4. Agent generates its keypair and prints a pairing challenge.
5. App sends its `clientPublicKey`.
6. Agent stores the client in `~/.config/pai-mobile/clients.json`.
7. Agent returns `machinePublicKey`, capabilities, and endpoint.
8. App stores the machine fingerprint and endpoint.
9. Future access uses tailnet HTTPS plus request signatures.

The bootstrap credential should not be needed for normal operation after this,
but it can remain as an explicit recovery option.

## Session Model

### Canonical Types

```text
MachineRef
  machineID
  displayName
  tailnetName
  agentEndpoint
  opencodeVersion
  capabilities

WorkspaceRef
  workspaceID
  machineID
  path
  realPath
  displayName
  repoRoot
  gitBranch
  allowed

RemoteSessionRef
  machineID
  workspaceID
  opencodeSessionID
  title
  createdAt
  updatedAt
  state
```

### Bijective Session Rule

The app should maintain this invariant:

```text
local active session key:
  activeSession:{machineID}:{workspaceID} -> opencodeSessionID

remote verification:
  GET /session/{opencodeSessionID}
  must return directory == WorkspaceRef.realPath
```

If the directory does not match, the app must refuse to attach and show a
recovery option.

### Listing Sessions

The app should list sessions through the agent:

```text
GET /v1/workspaces/{workspaceID}/sessions
```

The agent internally calls OpenCode:

```text
GET /session?directory=<realPath>
```

Then it returns normalized refs with machine/workspace already attached.

## Directory And Workspace Control

The mobile app should never trust a raw path string as final. The agent resolves
paths on the machine:

```text
POST /v1/paths/resolve
{
  "input": "~/Work/Personal_AI_Infrastructure"
}

returns:
{
  "path": "~/Work/Personal_AI_Infrastructure",
  "realPath": "/home/konanzin/Work/Personal_AI_Infrastructure",
  "exists": true,
  "isDirectory": true,
  "repoRoot": "/home/konanzin/Work/Personal_AI_Infrastructure",
  "allowed": true
}
```

Policy should support `allowedRoots`:

```json
{
  "allowedRoots": [
    "/home/konanzin",
    "/srv/pai-workspaces"
  ],
  "blockedPaths": [
    "/home/konanzin/.ssh",
    "/home/konanzin/.config/opencode/auth.json"
  ]
}
```

This does not make shell impossible outside those roots, but it lets the app
make project/session/file operations explicit and auditable.

## OpenCode Lifecycle

The agent should own OpenCode lifecycle:

```text
GET  /v1/opencode/status
POST /v1/opencode/start
POST /v1/opencode/stop
POST /v1/opencode/restart
POST /v1/opencode/upgrade
GET  /v1/opencode/logs?tail=200
```

Implementation rules:

- Find `opencode` with `command -v opencode` plus known absolute paths.
- Do not mutate global PATH.
- Start one OpenCode server per machine unless OpenCode proves it cannot safely
  handle multi-directory sessions.
- Bind OpenCode to `127.0.0.1`.
- Generate and rotate a random OpenCode server password.
- Store PID, logs, and generated auth in the agent state directory.
- Prefer systemd user service when available.
- Fall back to a supervised child process only when systemd user service is not
  available.
- Never use a loose `nohup` process as the steady-state runtime.

## Shell / Termius-Style Support

There are three shell modes.

### Mode 1: OpenCode PTY, Preferred Runtime

Use OpenCode PTY endpoints:

```text
POST /pty?directory=<realPath>
POST /pty/{ptyID}/connect-token
WS   /pty/{ptyID}/connect
```

The app gets:

- Terminal tabs per machine/workspace.
- Resume/reconnect to active PTYs.
- Shared auth and audit path.
- Same directory model as chat.

### Mode 2: Agent PTY Proxy

If OpenCode PTY is unavailable or incompatible, the PAI Agent exposes its own
PTY websocket:

```text
POST /v1/workspaces/{workspaceID}/pty
WS   /v1/pty/{ptyID}/connect
```

The agent spawns the user's login shell in the workspace directory.

### Mode 3: Direct SSH PTY, Recovery

The existing `TerminalScreen` path remains useful for recovery:

- Agent unavailable.
- OpenCode unavailable.
- First bootstrap.
- Emergency debugging.

This should be visually labeled as "SSH recovery terminal", not as the default
runtime shell.

## Security Model

### Trust Boundaries

```text
Boundary 1: Android device
  Risk: stolen phone, compromised app data, debug builds

Boundary 2: Tailnet
  Risk: overly broad ACLs/grants, shared devices, Funnel accidentally enabled

Boundary 3: Machine Agent
  Risk: remote command execution surface, provider secret handling

Boundary 4: OpenCode
  Risk: AI tool execution, shell commands, file modification, prompt injection

Boundary 5: Workspace
  Risk: repo secrets, .env files, SSH keys, production credentials
```

### Mandatory Controls

- App lock with biometric/PIN before opening terminal, provider setup, machine
  settings, or approving dangerous permissions.
- Android secure storage for machine tokens and bootstrap credentials.
- No provider API keys persisted as long-lived mobile data.
- Agent runs as the normal user, not root.
- Agent config directory `0700`; secret files `0600`.
- OpenCode listens on localhost.
- Agent authenticates every request.
- Agent keeps a redacted append-only audit log.
- Tailnet policy allows only the app/user to the agent port and, optionally,
  SSH for bootstrap.
- Funnel stays disabled for these services.
- OpenCode permission and question flows remain human-visible in the mobile UI.
- "Always approve" permissions require local unlock and must be scoped by
  machine/workspace/tool, not global.

### Stronger Controls

- Signed agent releases, verified before install/update.
- Agent binary hash pinned by mobile release.
- Remote policy file signed by mobile client.
- Request signatures with nonce replay protection.
- Short-lived session tokens for SSE and PTY websockets.
- Idle timeout for terminal sessions.
- Optional "read-only workspace" mode that disables write/shell capabilities.
- Tailscale Serve identity headers if the agent is behind Serve, while keeping
  the agent bound to localhost.

## Tailscale Policy

Use Tailscale as private network and identity layer, not as the only auth layer.

Conceptual policy:

```json
{
  "tagOwners": {
    "tag:pai-machine": ["autogroup:admin"]
  },
  "grants": [
    {
      "src": ["group:pai-mobile"],
      "dst": ["tag:pai-machine"],
      "ip": ["tcp:443"]
    },
    {
      "src": ["group:pai-mobile"],
      "dst": ["tag:pai-machine"],
      "ip": ["tcp:22"]
    }
  ],
  "ssh": [
    {
      "action": "accept",
      "src": ["group:pai-mobile"],
      "dst": ["tag:pai-machine"],
      "users": ["autogroup:nonroot"]
    }
  ]
}
```

The actual syntax may need adjustment to the tailnet's current policy style, but
the principle is strict: the phone/user can reach only the machine agent and the
bootstrap SSH path. Direct OpenCode port access should disappear after the agent
proxy exists.

## API Shape For PAI Machine Agent

Minimal v1:

```text
GET  /v1/health
GET  /v1/capabilities
GET  /v1/machine

POST /v1/paths/resolve
GET  /v1/workspaces
POST /v1/workspaces
GET  /v1/workspaces/{workspaceID}/git-status

GET  /v1/opencode/status
POST /v1/opencode/start
POST /v1/opencode/stop
GET  /v1/opencode/logs

GET  /v1/workspaces/{workspaceID}/sessions
POST /v1/workspaces/{workspaceID}/sessions
GET  /v1/sessions/{sessionID}
POST /v1/sessions/{sessionID}/message
GET  /v1/sessions/{sessionID}/events

GET  /v1/workspaces/{workspaceID}/files
GET  /v1/workspaces/{workspaceID}/file-content
GET  /v1/workspaces/{workspaceID}/find-files

GET  /v1/workspaces/{workspaceID}/ptys
POST /v1/workspaces/{workspaceID}/ptys
POST /v1/ptys/{ptyID}/connect-token
WS   /v1/ptys/{ptyID}/connect

GET  /v1/providers
POST /v1/providers

GET  /v1/audit
```

The first implementation can proxy most OpenCode endpoints rather than
reimplementing them. The value of the agent is identity, lifecycle, policy,
normalization, and safe bootstrapping.

## Options Considered

### Option A: Direct OpenCode Over Tailnet

```text
mobile -> http://machine:4096 -> OpenCode
```

Pros:

- Fastest path from the current app.
- Uses existing OpenCode REST/SSE client.
- Minimal remote footprint.

Cons:

- OpenCode becomes the exposed runtime service.
- Lifecycle remains fragile without a supervisor.
- OpenCode Basic Auth is too coarse for a privileged remote-control product.
- Hard to add policy, audit, provider setup, or robust shell.

Verdict:

Good as short-term bridge. Not robust enough as final architecture.

### Option B: SSH-Only, Agentless Runtime

```text
mobile -> SSH -> shell commands, port forwards, opencode starts
```

Pros:

- No resident daemon.
- Works on machines with only SSH.
- Easy to reason about for bootstrap.

Cons:

- Poor mobile reliability.
- Hard to resume sessions and PTYs.
- Harder to audit and enforce policy cleanly.
- SSH credentials stay on mobile as a runtime dependency.
- Process supervision becomes ad hoc.

Verdict:

Useful for bootstrap and recovery, not for the primary product.

### Option C: PAI Machine Agent, Recommended

```text
mobile -> tailnet -> agent -> localhost OpenCode
```

Pros:

- Strongest privacy boundary.
- Clean lifecycle and health model.
- First-class machine/workspace/session identity.
- Natural home for shell, providers, git status, logs, and policy.
- Supports multiple machines cleanly.
- Mobile remains the control surface after initial pairing.

Cons:

- Requires building and maintaining a daemon.
- Requires signed install/update story.
- More initial architecture work.

Verdict:

This is the robust target.

### Option D: Central Cloud/Broker

```text
mobile -> broker -> machine agents
```

Pros:

- Easier push notifications and NAT traversal outside tailnet.
- Central inventory.

Cons:

- Adds a third-party trust point.
- Weaker privacy story.
- More infrastructure.
- Not needed while Tailscale solves private reachability.

Verdict:

Avoid for now. Add only later for optional notifications or fleet sync, never
as the required path for shell/code access.

## Implementation Roadmap

### Phase 0: Harden Current Bridge

- Keep current SSH bootstrap.
- Start OpenCode via controlled script, not `nohup`.
- Generate a random OpenCode password per machine instead of default text.
- Bind to the Tailscale IP or enforce host firewall on port `4096`.
- Persist active sessions by `machineID + directory`.
- Validate directory before session restore.
- Keep direct SSH terminal as recovery.

### Phase 1: Build Minimal PAI Machine Agent

- Static Go or Rust binary.
- User-level install under `~/.local/bin/pai-machine-agent`.
- Config under `~/.config/pai-mobile`.
- State under `~/.local/state/pai-mobile`.
- Systemd user service when available.
- Endpoints: health, capabilities, path resolve, OpenCode status/start/stop,
  session list/create proxy.
- Agent supervises OpenCode bound to `127.0.0.1`.

### Phase 2: Route Chat Through Agent

- Add `PaiAgentOpenCodeClient` in Flutter.
- Preserve existing `OpenCodeClient` as fallback.
- Agent proxies REST and SSE to localhost OpenCode.
- App no longer needs direct OpenCode URL in normal mode.
- Machine settings move from "OpenCode Server URL" to "Machine endpoint".

### Phase 3: Workspace And Session Authority

- Agent owns workspace registry.
- App uses `WorkspaceRef`, not raw directory strings.
- Session lists come from `GET /v1/workspaces/{workspaceID}/sessions`.
- Session restore verifies remote ownership before switching.
- UI becomes `Machine -> Workspace -> Sessions -> Chat/Terminal`.

### Phase 4: Shell

- Implement OpenCode PTY websocket in Flutter.
- Add terminal tabs keyed by machine/workspace/pty.
- Keep direct SSH terminal as recovery.
- Add local unlock before opening terminal.
- Add idle timeout and disconnect controls.

### Phase 5: Security Hardening

- Ed25519 request signatures.
- Nonce replay cache.
- Signed agent updates.
- Audit log UI.
- Per-workspace policy.
- Provider setup through agent with secret redaction.
- Tailscale policy tests documented.

## Practical Next Recommendation

The next code milestone should not be "more SSH script". It should be:

1. Introduce a `RemoteControlClient` abstraction in Flutter.
2. Keep `OpenCodeClient` as one implementation.
3. Add `PaiAgentClient` as the target implementation.
4. Build a tiny first PAI Machine Agent with only:
   - `/health`
   - `/capabilities`
   - `/paths/resolve`
   - `/opencode/status`
   - `/opencode/start`
   - `/sessions?workspace=...`
5. Change machine setup so "Setup via SSH" installs/updates that agent.
6. Change the normal chat path to prefer the agent when available.

That sequence gives us a robust target without freezing current development.

## References

- OpenCode Server docs: https://opencode.ai/docs/server/
- OpenCode CLI docs: https://opencode.ai/docs/cli/
- OpenCode SDK docs: https://opencode.ai/docs/sdk/
- Tailscale SSH docs: https://tailscale.com/docs/features/tailscale-ssh
- Tailscale access control docs: https://tailscale.com/docs/features/access-control/acls
- Tailscale policy syntax: https://tailscale.com/docs/reference/syntax/policy-file
- Tailscale Serve docs: https://tailscale.com/docs/features/tailscale-serve
- Local OpenCode OpenAPI snapshot: `opencode-api-doc.json`
- Current mobile roadmap: `mobile-app/docs/REMOTE_MACHINES_AND_WORKSPACES_ROADMAP.md`
