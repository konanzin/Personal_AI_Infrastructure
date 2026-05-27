# Handoff: Samsung/Expo Go SSE Live-Ready Bug Investigation

> **Status:** Open — hypothesis validated by code inspection, awaiting device-level confirmation  
> **Last updated:** 2026-05-27 06:39 UTC (screenshot: `/tmp/opencode/pai-screen-liveready.png`)  
> **Branch/Commit:** `mobile-app` @ `c8df0ba` (no uncommitted changes to SSE code)

---

## 1. Current Symptom Summary

On a physical **Samsung Android 13** device running the app via **Expo Go**, the session screen:

- Shows **both** a persistent `Reconnecting…` chip and a `Connecting live updates…` chip simultaneously.
- **Disables the Send button** because `liveReady` never transitions to `true`.
- Never reaches the `connected` SSE state, so no live events are processed and no assistant replies stream in.
- Screenshot evidence: `/tmp/opencode/pai-screen-liveready.png` (May 27 06:39).

Earlier symptom (pre-fix): after sending "hi", a `SYSTEM` bubble rendered literal `[]` and the reconnect chip persisted. That was **root-caused and fixed** (see timeline), but the underlying SSE handshake failure remains.

---

## 2. Confirmed Infrastructure Facts

| Fact | Evidence |
|------|----------|
| Transport uses `react-native-sse` v1.1.0 | `packages/opencode-mobile-client/src/index.ts:37` |
| Transport is **XHR-based**, not `fetch+ReadableStream` | Comment at `index.ts:978` — RN fetch polyfill on Samsung/Android hangs silently on streaming bodies |
| Handshake timeout is **5 s** | `SSE_HANDSHAKE_TIMEOUT_MS = 5000` at `index.ts:982` |
| `open` event handler exists and calls `markConnected()` | `index.ts:1033` |
| `handshakeTimeout` logs `open-never-fired-check-xhr-constants` if `open` never fires | `index.ts:1082` |
| `isAwaitingReply` **was removed** from SSE effect deps | `apps/mobile/app/session/[id].tsx:329` — no longer causes churn |
| Send is blocked when `!liveReady` | `apps/mobile/app/session/[id].tsx:473` |
| Effect deps are stable (`config?.baseUrl`, `id`, `isDemoSession`, etc.) | `apps/mobile/app/session/[id].tsx:329` |

---

## 3. Investigation Timeline / Key Findings

| Date | Milestone | Finding |
|------|-----------|---------|
| **May 25** | Message-ingestion bug | Real backend returns `{ info, parts }`; mapper expected legacy `{ type, text, content }`. Caused `SYSTEM` bubble with `[]`. **Fixed.** |
| **May 25** | SSE churn bug | `isAwaitingReply` in SSE effect deps caused unsubscribe/resubscribe on every state flip. **Fixed.** |
| **May 26** | Observability slice (1.1) | Added 24 `[PAI_MOBILE_TRACE]` log points across transport lifecycle, screen lifecycle, send path, and fallback timer. |
| **May 26** | EventSource migration | Replaced `fetch` + `ReadableStream` reader with `react-native-sse` (XHR-based) because Samsung/Android `fetch` polyfill does not expose streaming bodies. |
| **May 27** | Live-ready repro | Screenshot shows both chips persistent. Send disabled. No `connected` state reached. |

**Critical code observation:** `react-native-sse` internally compares `xhr.readyState` against `XMLHttpRequest.DONE` (constant `4`). In some Expo Go / Hermes environments on Android, the `XMLHttpRequest` constructor exists but its static constants (`OPENED`, `HEADERS_RECEIVED`, `LOADING`, `DONE`) are **undefined**. When the library checks `xhr.readyState === XMLHttpRequest.DONE`, the comparison becomes `xhr.readyState === undefined`, which is always false, so the `open` event is never emitted.

---

## 4. Exact Decisive Log Evidence

The following log line is the smoking gun when the bug reproduces on the Samsung device:

```text
[PAI_MOBILE_TRACE] transport:handshakeTimeout | { url: "…/event", timeoutMs: 5000, note: "open-never-fired-check-xhr-constants" }
```

**What to grep for in `adb logcat`:**

```bash
adb logcat -d | grep -E "PAI_MOBILE_TRACE.*transport:(handshakeTimeout|connected|error|frame)"
```

**Expected healthy sequence (from simulator or iOS):**

```text
transport:subscribeToEvents
transport:subscriptionCreated
transport:connected          ← must appear within ~1 s
```

**Observed broken sequence (Samsung/Expo Go hypothesis):**

```text
transport:subscribeToEvents
transport:subscriptionCreated
… (silence for 5 s) …
transport:handshakeTimeout   ← note: "open-never-fired-check-xhr-constants"
```

If you see `handshakeTimeout` **without** a preceding `connected`, the XHR-constants hypothesis is confirmed.

---

## 5. Current Hypothesis

### `react-native-sse` / XHR Constants Handshake Failure in Expo Go Android

**Mechanism:**

1. `react-native-sse` creates an `XMLHttpRequest` and polls `xhr.readyState`.
2. It expects `readyState === 4` (`XMLHttpRequest.DONE`) to fire the `open` event.
3. In Expo Go on Samsung/Android (Hermes), `XMLHttpRequest.DONE` is `undefined`.
4. The comparison `readyState === undefined` is always false.
5. The `open` event never fires → `isOpen` stays false → `handshakeTimeout` fires.
6. The screen never leaves `liveReady === false` → send is blocked → user cannot interact.

**Why this matters:** This is a **library-environment incompatibility**, not an app logic bug. Our code already defensively handles the missing `open` event via `handshakeTimeout`, but we need a polyfill or library patch to actually make SSE work.

---

## 6. Recommended Next Action

1. **Confirm the hypothesis on-device** (see validation commands below).
2. If `handshakeTimeout` appears without `connected`, apply one of:
   - **Option A:** Patch `react-native-sse` to use numeric literals (`4` instead of `XMLHttpRequest.DONE`).
   - **Option B:** Polyfill `XMLHttpRequest` constants in the app bootstrap (`apps/mobile/app/_layout.tsx` or a new `polyfills.ts`):
     ```ts
     if (typeof XMLHttpRequest !== 'undefined' && XMLHttpRequest.DONE === undefined) {
       XMLHttpRequest.UNSENT = 0;
       XMLHttpRequest.OPENED = 1;
       XMLHttpRequest.HEADERS_RECEIVED = 2;
       XMLHttpRequest.LOADING = 3;
       XMLHttpRequest.DONE = 4;
     }
     ```
   - **Option C:** Evaluate `event-source-polyfill` or a custom XHR-based SSE client that uses numeric literals.
3. Re-test on Samsung device after patch.
4. If hypothesis is **refuted** (i.e. `connected` does fire but `liveReady` still stays false), investigate `setLiveReady` / `setHasBeenLiveReady` race in the screen handler (`[id].tsx:212`).

---

## 7. Exact Validation Commands

### A. Start the dev server (WSL)

```bash
export ADB_SERVER_SOCKET=tcp:192.168.0.9:5037
adb reverse tcp:8081 tcp:8081
adb reverse tcp:19000 tcp:19000
adb reverse tcp:19001 tcp:19001

tmux kill-session -t pai-mobile-expo 2>/dev/null || true
tmux new-session -d -s pai-mobile-expo \
  "cd /home/konanzin/Personal_AI_Infrastructure/mobile-app/apps/mobile && \
   CI=1 bun x expo start --offline --port 8081 --max-workers 1 --clear"
```

### B. Launch on Samsung device

```bash
adb shell am force-stop host.exp.exponent
sleep 2
adb shell am start -a android.intent.action.VIEW -d "exp://127.0.0.1:8081" host.exp.exponent
```

### C. Capture logcat during repro

```bash
adb logcat -c  # clear buffer
# … tap into a real session and wait 10 s …
adb logcat -d | grep "PAI_MOBILE_TRACE" > /tmp/sse-repro-$(date +%Y%m%d-%H%M%S).log
```

### D. Screenshot the device

```bash
adb shell screencap -p /sdcard/pai-screen.png
adb pull /sdcard/pai-screen.png /tmp/opencode/pai-screen-$(date +%Y%m%d-%H%M%S).png
adb shell rm /sdcard/pai-screen.png
```

### E. Quick bundle health check

```bash
curl -s -o /dev/null -w "%{http_code}" \
  "http://127.0.0.1:8081/index.bundle?platform=android"
# Expected: 200
```

### F. Run unit tests (regression guard)

```bash
cd /home/konanzin/Personal_AI_Infrastructure/mobile-app
bun run typecheck
bun run test
```

---

## 8. Quick Reference: Relevant Source Locations

| Concern | File | Lines |
|---------|------|-------|
| SSE transport (EventSource wrapper) | `packages/opencode-mobile-client/src/index.ts` | 974–1100 |
| Handshake timeout | `packages/opencode-mobile-client/src/index.ts` | 1082 |
| Screen SSE effect | `apps/mobile/app/session/[id].tsx` | 142–344 |
| Live-ready gate (blocks send) | `apps/mobile/app/session/[id].tsx` | 473 |
| Connection chips UI | `apps/mobile/app/session/[id].tsx` | 580–648 |
| Handle send + traces | `apps/mobile/app/session/[id].tsx` | 457–520 |

---

## 9. Artifacts

| Path | Description |
|------|-------------|
| `/tmp/opencode/pai-screen-liveready.png` | **Latest repro** (May 27 06:39) — shows persistent chips |
| `/tmp/opencode/pai-screen-issue.png` | Earlier repro (May 25 21:54) — shows `[]` system bubble + reconnect |
| `/tmp/opencode/pai-screen-latest.png` | Post-ingestion-fix (May 26 07:51) — messages map but no live streaming |
| `/tmp/opencode/pai-mobile-expo.log` | Expo server stdout (not device logcat) |
| `docs/SAMSUNG_WSL_EXPO_WORKFLOW.md` | Full device setup instructions |

---

*Resume checklist: run validation commands A→F, grep for `handshakeTimeout`, decide between Option A/B/C.*
