# Handoff: SSE Live-Ready Investigation — Linux Continuation

> **Status:** Investigation paused — moving to Linux native environment  
> **Last updated:** 2026-05-27 15:15 UTC  
> **Branch:** `mobile-app` (work in progress, uncommitted changes tracked below)

---

## Executive Summary

After extensive investigation on Samsung/Android + Expo Go + WSL2, the SSE handshake failure persists with `readyState=0` and `handshakeTimeout`. We have eliminated library bugs (`react-native-sse` replaced with `event-source-polyfill`) and XHR constants issues (polyfilled). The remaining hypothesis is that **`adb reverse` does not support persistent SSE connections** on Samsung/Android, even though it works for REST request/response.

**Decision:** Move development to Linux native to eliminate WSL2 NAT and `adb reverse` complexity.

---

## 1. What Works

| Component | Evidence | Status |
|-----------|----------|--------|
| Backend health check | `curl -u opencode:pai-mobile http://127.0.0.1:4096/global/health` → 200 | ✅ |
| Backend SSE endpoint | `curl -u opencode:pai-mobile http://127.0.0.1:4096/event` → streams events | ✅ |
| REST API (list sessions) | App loads session list from backend | ✅ |
| Expo Go loads bundle | `curl http://127.0.0.1:8081/index.bundle?platform=android` → 200 | ✅ |
| `event-source-polyfill` import | Polyfills XHR constants, hides fetch, loads without errors | ✅ |
| TypeScript compilation | `bun run typecheck` → 0 errors | ✅ |
| Unit tests | `bun run test` → 237 pass / 0 fail | ✅ |

---

## 2. What Does NOT Work

| Symptom | Evidence | Root Cause (Best Hypothesis) |
|---------|----------|------------------------------|
| SSE `open` event never fires | Logs show `readyState=0` for 10+ seconds, then `handshakeTimeout` | `adb reverse tcp:4096 tcp:4096` fails for persistent connections; works for REST but not SSE streaming |
| `event-source-polyfill` receives no data | `debugState` shows `readyState=0` indefinitely | Same as above — XHR connects but no bytes flow through adb reverse |
| Manual XHR probe also stuck | `xhrProbe` logs show `readyState=0` with no progression | Confirms infrastructure issue, not library bug |

### Decisive Log Evidence

```text
[PAI_MOBILE_TRACE] TRANSPORT | subscriptionCreated | url=http://localhost:4096/event readyState=0
[PAI_MOBILE_TRACE] TRANSPORT | debugState | url=http://localhost:4096/event readyState=0 isOpen=false count=1
... (counts 2-10, all readyState=0) ...
[PAI_MOBILE_TRACE] TRANSPORT | handshakeTimeout | url=http://localhost:4096/event timeoutMs=5000
[PAI_MOBILE_TRACE] TRANSPORT | error | message=No activity within 45000ms. Reconnecting.
```

---

## 3. Investigation Timeline

| Date | Milestone | Finding |
|------|-----------|---------|
| May 25 | Message ingestion bug | Real backend returns `{ info, parts }`; mapper expected legacy `{ type, text, content }`. Fixed. |
| May 25 | SSE churn bug | `isAwaitingReply` in SSE effect deps caused unsubscribe/resubscribe loop. Fixed. |
| May 26 | Observability slice (1.1) | Added 24 `[PAI_MOBILE_TRACE]` log points across transport lifecycle. |
| May 26 | EventSource migration | Replaced `fetch` + `ReadableStream` with `react-native-sse` (XHR-based) because Samsung/Android fetch polyfill hangs on streaming. |
| May 27 | XHR constants hypothesis | Discovered `XMLHttpRequest.DONE` is `undefined` in Expo Go/Hermes. Applied polyfill. |
| May 27 | `react-native-sse` research | Confirmed lib is NOT market standard; 12 open issues for Expo/Android. Migrated to `event-source-polyfill`. |
| May 27 | `event-source-polyfill` integration | Forced XHR transport by hiding `fetch` from global scope. Polyfilled XHR constants before import. |
| May 27 | adb reverse hypothesis | Discovered that `adb reverse` works for REST but likely buffers/closes persistent SSE connections. |

---

## 4. Current Code State

### Files Modified (compared to `c8df0ba`)

#### New Files

1. **`packages/opencode-mobile-client/src/event-source-wrapper.ts`**
   - Polyfills `XMLHttpRequest` constants (`UNSENT` through `DONE`) BEFORE importing `event-source-polyfill`
   - Hides `globalThis.fetch` and `globalThis.Response` to force XHRTransport
   - Exports `EventSourcePolyfill` wrapper

2. **`apps/mobile/src/polyfills.ts`**
   - Backup polyfill for XHR constants (loaded in `_layout.tsx`)
   - May be redundant now that wrapper handles it, but harmless

#### Modified Files

3. **`packages/opencode-mobile-client/src/index.ts`**
   - Import changed from `react-native-sse` to `./event-source-wrapper`
   - `subscribeToEvents` uses `EventSourcePolyfill` with `withCredentials: false`
   - Added diagnostic XHR probe (lines 993-1011) — sends manual XHR to compare behavior
   - Added `debugInterval` that logs `readyState` every second for 10 seconds
   - Removed per-event-type listeners (event-source-polyfill handles event names from SSE `event:` field)
   - Comment updated to document why `event-source-polyfill` is used

4. **`packages/opencode-mobile-client/src/index.test.ts`**
   - Mock updated from `react-native-sse` to `./event-source-wrapper`
   - All 237 tests pass

5. **`packages/opencode-mobile-client/package.json`**
   - Removed `react-native-sse` dependency
   - Added `event-source-polyfill: ^1.0.31`
   - Added `@types/event-source-polyfill: ^1.0.5` (dev)

6. **`apps/mobile/app/_layout.tsx`**
   - Added `import '../src/polyfills'` as first line

#### Dependencies (node_modules)

- `event-source-polyfill@1.0.31` installed
- `react-native-sse@1.1.0` still in lockfile (not actively used)

---

## 5. Next Steps on Linux

### 5.1 Environment Setup

```bash
# Install dependencies
sudo apt update
sudo apt install -y adb tmux curl
# Install bun (curl -fsSL https://bun.sh/install | bash)
# Install opencode CLI

# Clone repo
git clone <repo-url>
cd mobile-app

# Install packages
bun install
```

### 5.2 Run Backend

```bash
opencode serve --port 4096 --hostname 0.0.0.0
```

Verify:
```bash
curl -u "opencode:pai-mobile" http://127.0.0.1:4096/global/health
# Expected: 200
```

### 5.3 Discover Network IP

```bash
hostname -I | awk '{print $1}'
# Use this IP in the app settings (e.g., http://192.168.0.X:4096)
```

### 5.4 Run Expo Dev Server

```bash
cd apps/mobile
bun x expo start --offline --port 8081 --clear
```

### 5.5 Configure Samsung

1. Open Expo Go on Samsung
2. Scan QR or enter `exp://<linux-ip>:8081`
3. Open app → Settings
4. Set Server URL to `http://<linux-ip>:4096`
5. Username: `opencode`
6. Password: `pai-mobile`
7. **Tap Save**
8. Open a session

### 5.6 Verify SSE

Watch for these logs:
```bash
adb logcat -v threadtime -s ReactNativeJS | grep "PAI_MOBILE_TRACE"
```

**Expected success sequence:**
```text
transport:subscribeToEvents
transport:subscriptionCreated
transport:connected          ← MUST appear within ~1-2s
transport:frame              ← events streaming
```

**If still failing:**
- Check `debugState` logs — does `readyState` progress from 0 → 1 → 2 → 3?
- Check `xhrProbe` logs — does manual XHR receive data?
- If both fail → firewall/network issue
- If XHR works but EventSource doesn't → library issue (check `event-source-polyfill` version)

---

## 6. Cleanup Before Production

After SSE works, remove diagnostic code:

1. **`packages/opencode-mobile-client/src/index.ts`**
   - Remove XHR probe (lines ~993-1011)
   - Remove `debugInterval` (lines ~1027-1041)
   - Remove `debugCount` variable
   - Remove `readyState` and `withCredentials` from `subscriptionCreated` log

2. **`packages/opencode-mobile-client/src/event-source-wrapper.ts`**
   - May keep as-is; it's defensive and harmless
   - Alternatively, simplify by removing fetch-hiding if not needed on Linux

3. **`apps/mobile/src/polyfills.ts`**
   - May remove if `event-source-wrapper.ts` handles everything

---

## 7. Key Insights for Next Agent

1. **The bug is NOT in the app code.** It is an infrastructure issue with `adb reverse` + SSE on Samsung/Android.
2. **`react-native-sse` is broken for Expo Go.** Replaced with `event-source-polyfill` (market standard, 1.49M downloads/week).
3. **XHR constants must be polyfilled BEFORE `event-source-polyfill` imports.** The wrapper file handles this.
4. **React Native's `fetch` does not support streaming.** We hide it from the polyfill to force XHRTransport.
5. **On Linux, use the machine's network IP directly** — no `adb reverse` needed for the backend.
6. **Always tap "Save" in Settings** — "Test Connection" does not persist the URL.

---

## 8. Relevant Commands

```bash
# Backend
curl -u "opencode:pai-mobile" http://127.0.0.1:4096/global/health

# SSE endpoint test
curl -u "opencode:pai-mobile" -D - http://127.0.0.1:4096/event

# Bundle health
curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:8081/index.bundle?platform=android"

# Device logs
adb logcat -v threadtime -s ReactNativeJS | grep "PAI_MOBILE_TRACE"

# Screenshot
adb shell screencap -p /sdcard/screen.png && adb pull /sdcard/screen.png /tmp/screen.png
```

---

*Resume from here. Good luck on Linux — the hard part (library migration) is done. The rest is network configuration.*
