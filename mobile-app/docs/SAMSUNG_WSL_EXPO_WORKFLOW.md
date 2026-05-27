# Samsung + WSL + Expo + tmux Workflow

This document captures the working device-development loop for PAI Mobile when Android Studio / emulator usage is too heavy and a real Samsung device is used instead.

## Goal

Run the Expo app from WSL, keep the dev server alive reliably, and load the project in Expo Go on a physical Samsung device over USB using `adb reverse`.

## What This Solves

- avoids Android Studio emulator RAM pressure
- uses a real Android 13+ Samsung device for UI testing
- keeps Bun / Expo development inside WSL
- uses Windows `adb` server as the USB bridge

## Requirements

- Samsung phone with **Developer Options** enabled
- **USB Debugging** enabled on the phone
- Expo Go APK installed on device (we used `Exponent-2.31.2.apk`)
- `adb` available on Windows
- `tmux` available in WSL

## One-Time Windows Setup

In **Windows PowerShell**:

```powershell
adb kill-server
adb -a nodaemon server start
```

In another PowerShell window, confirm the device is visible:

```powershell
adb devices
```

Expected result:

```text
RQ8N607VHEK     device
```

### Windows host IP used by WSL

In this setup, the WSL guest reached the Windows adb server through:

```text
192.168.0.9:5037
```

That value may differ on future setups. To inspect Windows IPv4 addresses from WSL:

```bash
powershell.exe -Command "Get-NetIPAddress -AddressFamily IPv4 | Select-Object InterfaceAlias,IPAddress | Format-Table -HideTableHeaders"
```

## WSL adb Bridge

Inside WSL, point the adb client to the Windows adb server:

```bash
export ADB_SERVER_SOCKET=tcp:192.168.0.9:5037
adb devices
```

If you want this persistent for the shell:

```bash
echo 'export ADB_SERVER_SOCKET=tcp:192.168.0.9:5037' >> ~/.bashrc
```

## Install Expo Go APK

From WSL:

```bash
adb install -r "/home/konanzin/Personal_AI_Infrastructure/mobile-app/Exponent-2.31.2.apk"
```

Launch Expo Go:

```bash
adb shell monkey -p host.exp.exponent -c android.intent.category.LAUNCHER 1
```

## Reliable Expo Dev Server Strategy

Running Expo from short-lived WSL shells was unreliable. The stable solution was to keep Expo alive in **tmux**.

### Start persistent Expo in tmux

From WSL:

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

### Why these flags matter

This repository hit known Expo CLI / Bun issues. The stable command was:

```bash
CI=1 bun x expo start --offline --port 8081 --max-workers 1 --clear
```

Notes:

- `CI=1` disables reloads/watch mode but stabilizes the process
- `--offline` avoids dependency-validation crashes in Expo CLI under Bun
- `--max-workers 1` avoided bundling issues seen earlier in this repo
- `--clear` helps shake out stale cache during rapid iteration

## Check Expo Server Health

### Check tmux session exists

```bash
tmux ls | grep pai-mobile-expo
```

### Inspect Expo logs

```bash
tmux capture-pane -pt pai-mobile-expo | tail -n 40
```

### Probe the Android bundle directly

```bash
curl -s -o /dev/null -w "%{http_code}" \
  "http://127.0.0.1:8081/index.bundle?platform=android"
```

Expected result:

```text
200
```

## Open the Project in Expo Go

After the bundle is healthy:

```bash
adb shell am start -a android.intent.action.VIEW -d "exp://127.0.0.1:8081" host.exp.exponent
```

If Expo Go appears stuck on old code, force restart it:

```bash
adb shell am force-stop host.exp.exponent
sleep 2
adb shell am start -a android.intent.action.VIEW -d "exp://127.0.0.1:8081" host.exp.exponent
```

## Screenshot Debugging via adb

When the device shows something unexpected, capture the exact screen:

```bash
adb shell screencap -p /sdcard/pai-screen.png
adb pull /sdcard/pai-screen.png /tmp/opencode/pai-screen.png
adb shell rm /sdcard/pai-screen.png
```

This was useful to confirm that a layout bug was real and not just user description ambiguity.

## Common Failure Modes

### 1. `adb devices` in WSL cannot connect

Cause:
- WSL points to the wrong host IP / wrong `ADB_SERVER_SOCKET`

Fix:
- confirm Windows IP
- export the correct `ADB_SERVER_SOCKET`

### 2. Blue Expo “Something went wrong” screen

Cause:
- Expo dev server died or bundle endpoint stopped responding

Fix:
- confirm tmux session still exists
- probe `/index.bundle?platform=android`
- restart tmux session if needed

### 3. Old code still appears on the phone

Cause:
- stale Expo server or stale Expo Go state

Fix:
- restart the tmux Expo session
- confirm bundle content with direct HTTP fetch
- force-stop and reopen Expo Go

### 4. Expo CLI crashes in normal mode under Bun

Cause:
- known compatibility issues with Expo CLI network/cache code under Bun

Fix:
- use the repository-safe command:

```bash
CI=1 bun x expo start --offline --port 8081 --max-workers 1 --clear
```

## Operational Recommendation

For this repo, prefer:

- **real Samsung device** for day-to-day testing
- **tmux-hosted Expo server** inside WSL
- **Windows adb server** as the USB bridge

Avoid relying on:

- Android Studio emulator for routine iteration
- ephemeral detached shells for the Expo dev server

## Quick Reference

```bash
# 1) point WSL adb at Windows
export ADB_SERVER_SOCKET=tcp:192.168.0.9:5037

# 2) reverse ports
adb reverse tcp:8081 tcp:8081
adb reverse tcp:19000 tcp:19000
adb reverse tcp:19001 tcp:19001

# 3) start Expo persistently
tmux kill-session -t pai-mobile-expo 2>/dev/null || true
tmux new-session -d -s pai-mobile-expo \
  "cd /home/konanzin/Personal_AI_Infrastructure/mobile-app/apps/mobile && \
   CI=1 bun x expo start --offline --port 8081 --max-workers 1 --clear"

# 4) verify bundle
curl -s -o /dev/null -w "%{http_code}" \
  "http://127.0.0.1:8081/index.bundle?platform=android"

# 5) launch app on Samsung
adb shell am force-stop host.exp.exponent
sleep 2
adb shell am start -a android.intent.action.VIEW -d "exp://127.0.0.1:8081" host.exp.exponent
```
