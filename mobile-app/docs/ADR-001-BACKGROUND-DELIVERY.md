# ADR-001 — Background Delivery Transport for Pulse Notifications

**Status:** Accepted — implemented in Phase C3 (`lib/services/pulse/`, commit 1f5b6c3); remaining follow-ups listed under Consequences §5
**Date:** 2026-06-11
**Context:** Phase B of `PULSE_MOBILE_PLAN.md` — how do broker events reach the phone with the app backgrounded/screen off, on the tailnet, without FCM?

## Decision

**Foreground service with a persistent SSE subscription to the Pulse Broker.**
ntfy/UnifiedPush is NOT adopted (kept as a documented fallback).

## Measurements

Device: Samsung SM-S921B (Galaxy S24), Android 14, debug build.
Method: spike build (`spike/background-delivery` branch) — `flutter_foreground_task` v9 service holding an SSE connection; host emits via broker `POST /notify`; latency = device `SPIKE_RECV` log timestamp − host send timestamp − measured clock offset (±~170ms noise from adb shell spawn).

| Scenario | Transport | Latency |
|---|---|---|
| App foreground, screen on | adb reverse (loopback) | 15ms |
| App background, screen off | adb reverse (loopback) | ~0ms (within noise) |
| **Forced deep Doze** (`deviceidle force-idle`, `battery unplug`) | adb reverse (loopback) | 3ms |
| **Forced deep Doze** | **Wi-Fi (192.168.x LAN)** | **67ms** |
| Extended idle (~30 min, simulated unplugged) | Wi-Fi | **NOT delivered** — see endurance findings |

## Endurance findings (the valuable part)

After ~20-30 min of simulated-unplugged idle, the S24 **turned Wi-Fi off entirely** (`Network is unreachable` from the service's reconnect loop — radio-level, not a Doze TCP freeze). Timeline evidence:

- The foreground service **survived the whole outage** and kept its 3s reconnect loop running (67+ attempts logged) — process death was never the failure mode.
- An event emitted during the blackout was **lost** (no replay in the spike client).
- When Wi-Fi returned, the phone had **re-associated on a different subnet** (192.168.15.x → 192.168.0.x), making the host's LAN IP unroutable — reconnection kept timing out. The failure to recover was an **addressing problem, not a service problem**.

Key observations:

- The established TCP connection held by a foreground service **survives forced deep Doze** even over the radio path, without battery-optimization whitelist. Doze's network blackout did not sever or freeze the already-open SSE stream in these tests.
- The broker's 25s SSE heartbeat doubles as a keep-alive against NAT/Wi-Fi power-save.
- Loopback (adb reverse) results are NOT representative of radio behavior — always validate over Wi-Fi (the 3ms loopback vs 67ms Wi-Fi delta under Doze shows why).

## Caveats / risks accepted

1. **Synthetic Doze**: `force-idle` approximates hours-long natural Doze; maintenance-window behavior over a full night is not yet measured.
2. **USB attached** during tests (battery state faked via `dumpsys battery unplug`) — charging can mask radio power management.
3. **Samsung app hibernation** ("App sleep"/adaptive battery) can kill long-unused apps regardless of FGS. Production mitigations for C3: request battery-optimization exemption (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`), instruct adding the app to Samsung's "never sleeping" list, and make the service auto-restart (`START_STICKY` semantics) + reconnect loop (the spike already reconnects every 3s).
4. **Battery cost** of a persistent LOW-importance FGS + idle SSE was not measured over a workday; expected low (idle TCP + 25s heartbeats), to be confirmed in C3 dogfooding.

## Why not ntfy / UnifiedPush

- Adds a moving part (server + second app or embedded distributor) for no measured latency win.
- Voice (TTS from event payload) integrates naturally in our own service; via ntfy we would still need the app running to speak.
- Revisit only if real-world FGS survival proves unreliable (the fallback integrates at the broker: publish to a topic next to SSE).

## Consequences for Phase C3 (hard requirements, from measurement)

1. **Catch-up on reconnect is mandatory, not optional**: on every (re)connect the client MUST `GET /recent` and reconcile via `dedupe_key` — blackout windows are a fact of life and events must not be silently lost (speak/badge late rather than never).
2. **Broker address must be network-stable**: use the tailnet address (per the architecture direction), never a LAN IP — today's recovery failure was subnet hopping. The host needs tailscale for real-world use; LAN IP is acceptable only for cabled test rigs.
3. The app gains a production-grade background service: identified subscription (`device=phone`, presence updates on foreground/background transitions), reconnect with backoff (the fixed 3s spike loop wastes battery during long outages — back off to ≥60s), `START_STICKY`, boot-start optional.
4. The C3 voice path (SpeechEngine → Android platform TTS) runs from the service process when backgrounded.
5. Follow-ups not yet measured: battery-optimization whitelist effect on the Wi-Fi drop; overnight natural Doze; battery cost over a workday (dogfood in C3).
6. Spike code (`lib/spike/`) is throwaway; C3 reimplements it properly (state handling, settings, localization).
