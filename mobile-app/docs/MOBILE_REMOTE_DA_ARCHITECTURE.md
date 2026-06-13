# Mobile Remote DA Architecture

Updated: 2026-06-13

## Executive Decision

The target architecture is a **two-plane design** built entirely from
standard, vendor-neutral components. There is no custom daemon on the remote
machines.

```text
┌──────────────────────────────────────────────────────────────────┐
│ Android app  (only control surface)                              │
│   Machine registry · Session router · Chat · Terminal · Lock     │
│   machineID = SSH host-key fingerprint                           │
└────────┬─────────────────────────────────────────┬───────────────┘
         │ RUNTIME PLANE (hot path)                │ CONTROL PLANE (cold path)
         │ HTTP REST · SSE · PTY WebSocket         │ SSH
         ▼                                         ▼
┌──────────────────────────────────────────────────────────────────┐
│ Private overlay network — deny-by-default, device identity       │
│ (Tailscale today; any WireGuard mesh works — app sees URLs only) │
└────────┬─────────────────────────────────────────┬───────────────┘
         ▼                                         ▼
┌──────────────────────────────────────────────────────────────────┐
│ Remote machine                                                   │
│   sshd (stock) ─ bootstrap · recovery · lifecycle                │
│   systemd --user ─ pai-opencode.service (Restart=always)         │
│      └─ OpenCode bound to a private address (never 0.0.0.0)      │
│           sessions · SSE · files · PTY WS · random password      │
└──────────────────────────────────────────────────────────────────┘
```

- **Runtime plane** (used constantly): the app talks directly to OpenCode's
  REST/SSE/PTY-WebSocket API. No middleman touches the hot path.
- **Control plane** (used rarely): SSH performs bootstrap, lifecycle
  (`pai-opencode start|stop|restart|status|logs`), and emergency recovery.

A previous revision of this document proposed a per-machine "PAI Machine
Agent" daemon that would supervise and reverse-proxy OpenCode. That proposal
is **rejected** for now — see "Considered and Rejected" below for the
reasoning and the explicit triggers that would reopen it.

## Why This Shape

1. **Failure independence.** Chat/terminal and repair are separate paths. If
   OpenCode wedges, SSH still works and can fix it. A daemon that is both
   proxy and lifecycle manager loses runtime *and* remote repair when it has
   a bug.
2. **Every component is battle-tested third-party code.** sshd, systemd,
   WireGuard, OpenCode. There is no daemon to build, sign, distribute, or
   update, and no custom protocol to maintain.
3. **No middleman on the hot path.** The SSE transport hardening already
   shipped in the client keeps paying off. A homemade proxy in front of
   SSE/WebSockets would reintroduce buffering/backpressure/reconnect bugs and
   force the proxy to track OpenCode's still-evolving API.
4. **Most agnostic option.** Every layer is swappable: Tailscale → plain
   WireGuard or Netbird (the app only sees a URL and an SSH host); systemd →
   launchd on macOS. SSH is universal.
5. **Security matches the threat model.** Single user on a
   device-authenticated, encrypted private mesh. The layers that matter:
   network encryption + device identity (overlay network), no public bind
   (loopback/private-interface binding), random per-machine password, app
   lock + Android Keystore on the phone, pinned SSH host keys.

## Requirements As Architecture Constraints

1. **Bijective access to sessions across machines.**

   A session is identified by `machineID + directory + opencodeSessionID`.
   The app never attaches a restored session without verifying — via
   `GET /session/{id}` — that it still exists and that its `directory`
   matches the selected workspace. On mismatch it refuses, clears the stale
   pointer, and starts fresh.

   Implemented in `SessionProvider.verifySessionScope` and the chat restore
   flow.

2. **Privacy.**

   OpenCode is never bound to `0.0.0.0`. The bootstrap controller resolves
   the bind address in this order:

   ```text
   explicit OPENCODE_HOST
     > the address the SSH connection arrived on ($SSH_CONNECTION)
     > the Tailscale IPv4 address
     > 127.0.0.1
   ```

   The `$SSH_CONNECTION` rule is the agnostic core: the server binds exactly
   the interface the phone already reaches — tailnet, WireGuard, or LAN —
   without naming any vendor. Auth is a random per-machine password
   generated on setup (never a guessable default).

3. **Directory control.**

   Directory is part of the session contract. Session, file, and PTY
   operations are scoped with `?directory=`, which OpenCode supports across
   its API (verified against the OpenAPI snapshot and live server 1.16.2).

4. **Multiple machines with stable identities.**

   `machineID = "mach_" + sha256(sshHostKeyFingerprint)[0:20]`. The host key
   is captured during machine setup (dartssh2 reports it during key
   exchange), so the same machine maps to the same ID across app reinstalls
   and regardless of which address was used to reach it. The fingerprint is
   also **pinned**: routine SSH connections (terminal recovery, git status)
   refuse to proceed if the host key changes; re-running "Test SSH" in the
   machine editor explicitly trusts a new key.

5. **Shell support.**

   Three modes, in order of preference:

   - **OpenCode PTY (runtime plane, default).** `POST /pty?directory=`,
     `POST /pty/{id}/connect-token` (requires the `x-opencode-ticket: 1`
     header), then WebSocket `GET /pty/{id}/connect?ticket=...`. Text frames
     carry terminal I/O; binary frames prefixed with `0x00` carry control
     JSON (`{"cursor": N}`). Reconnecting with `?cursor=` resumes output
     instead of replaying. Resize via `PUT /pty/{id}` with
     `{size:{rows,cols}}`. PTYs survive app restarts and are reattached.
   - **SSH recovery shell (control plane).** Visually labeled "SSH
     recovery" in the terminal UI. Used when OpenCode is unreachable, on
     first bootstrap, and for emergency debugging.

6. **Mobile-only operation.**

   The minimum unavoidable bootstrap is one SSH credential (key or
   password). After bootstrap, normal operation uses only the runtime plane;
   SSH remains configured for lifecycle and recovery.

## OpenCode Lifecycle

The control plane installs `~/.local/bin/pai-opencode` over SSH
(`installPaiOpenCodeControllerCommand` in `ssh_service.dart`). The
controller:

- Prefers a **systemd user service** (`pai-opencode.service`):
  `Restart=always`, `RestartSec=2`, journald logs, `loginctl enable-linger`
  so the server survives logout and reboots.
- Stores the password in `~/.local/state/pai-mobile/opencode.env` (0600),
  referenced via `EnvironmentFile=`.
- Falls back to a supervised detached process with a PID file only when a
  user systemd is unavailable (macOS, containers); set
  `PAI_OPENCODE_NO_SYSTEMD=1` to force the fallback.
- Migrates old installs: any stray `opencode serve` holding the port (e.g.
  from the previous setsid-based controller) is stopped before the unit
  starts.
- Subcommands: `start | stop | restart | status | logs [n]`.

## Security Model

### Trust Boundaries

```text
Boundary 1: Android device      — stolen phone, compromised app data
Boundary 2: Private network     — overly broad ACLs, accidental exposure
Boundary 3: OpenCode            — AI tool execution, prompt injection
Boundary 4: Workspace           — repo secrets, .env files, SSH keys
```

(The "machine agent" boundary no longer exists — that surface was removed by
not building it.)

### Controls

- App lock (biometric/PIN) gates the app; secrets live in Android secure
  storage.
- OpenCode binds to a private address; password is random per machine.
- SSH host keys are pinned after first contact (TOFU); mismatches block with
  a clear recovery path.
- Overlay-network policy should allow only the user's devices to reach the
  machine (Tailscale ACLs or WireGuard peer config). Keep Funnel/public
  exposure off.
- OpenCode permission and question flows remain human-visible in the mobile
  UI.

## Considered and Rejected

### PAI Machine Agent (custom daemon + reverse proxy)

Rejected because, for a single-user system on a private mesh, it duplicates
sshd + systemd + the overlay network at the cost of building, signing, and
maintaining the highest-privilege component in the stack, and it puts custom
code on the streaming hot path. Request signing (Ed25519, nonce caches) adds
ceremony, not protection, on an already device-authenticated encrypted
transport.

**Triggers that would reopen this decision:**

1. Push notifications are needed when long tasks finish (a thin *status*
   endpoint could be added — never a runtime proxy).
2. A second user/client needs scoped access to a machine.
3. A target machine cannot join any overlay network.

### Central cloud/broker

Rejected: adds a third-party trust point and weakens the privacy story while
the overlay network already solves reachability.

## Current Implementation Status (2026-06-13)

- [x] Bootstrap installs systemd user unit; private bind resolution; random
      per-machine password (`ssh_service.dart`, `machines_screen.dart`).
- [x] Stable machine IDs from SSH host-key fingerprints; host-key pinning
      (`machine.dart`, `ssh_service.dart`).
- [x] Bijective session verification on restore
      (`session_provider.dart`, `chat_screen.dart`).
- [x] OpenCode PTY WebSocket terminal with resume; SSH demoted to labeled
      recovery mode (`terminal_screen.dart`, `opencode_client.dart`).
- [x] PaiAgentClient stub and dead capability service removed.
- [x] Pulse listener service implemented in the app: foreground service,
      identified broker SSE subscription, `/recent` catch-up, presence,
      coalescing, and Android platform TTS (`lib/services/pulse/`).
- [ ] Idle timeout / local unlock specifically for the terminal screen.
- [ ] Documented Tailscale ACL / WireGuard peer policy examples.
- [ ] Long-running battery/overnight validation for Pulse background delivery
      on the target phone.

## References

- OpenCode Server docs: https://opencode.ai/docs/server/
- OpenCode SDK docs: https://opencode.ai/docs/sdk/
- Local OpenCode OpenAPI snapshot: `opencode-api-doc.json`
- Tailscale access control docs: https://tailscale.com/docs/features/access-control/acls
- Current mobile roadmap: `mobile-app/docs/REMOTE_MACHINES_AND_WORKSPACES_ROADMAP.md`
