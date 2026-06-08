# PAI Mobile M5 - Test Guide

> Updated 2026-06-08. This guide tests the real Flutter app in `mobile-app/apps/flutter`. Core live smoke on `a51` passed via ADB reverse; remaining sections should still be run for full M5 closure.

## Automated Verification

Latest local state:

- `flutter pub get`: passed
- `flutter analyze`: passed with no issues
- `flutter test`: passed with 6 tests

Latest live state:

- Android `a51` / SM-A515F installed and ran the debug APK.
- OpenCode `1.16.2` was reached through `adb reverse tcp:4096 tcp:4096`.
- Session `ses_15af8bd98ffeT7zNQWJVKIp4Bc` used `kimi-for-coding/k2p6`.
- Prompt `Run pwd using shell and reply DONE2` streamed `DONE2`, rendered a rich `bash` tool block, and rehydrated after reopening the session.
- Logcat showed no send-message timeout/error after the message timeout fix.

Run:

```bash
cd mobile-app/apps/flutter
flutter pub get
flutter analyze
flutter test
```

## Manual Prerequisites

1. OpenCode Server running on the Linux host:

   ```bash
   OPENCODE_SERVER_PASSWORD='<password>' opencode serve --hostname 0.0.0.0 --port 4096
   ```

2. Android `a51` online in the same tailnet, or ADB reverse configured.

3. App installed on the device:

   ```bash
   cd mobile-app/apps/flutter
   flutter build apk --debug
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

   On this workstation, use Java 17 for the Android build if Java 26 is the default:

   ```bash
   export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
   export PATH="$JAVA_HOME/bin:$PATH"
   flutter build apk --debug
   ```

## Manual Tests

### 1. Text And Markdown

Prompt:

```text
Oi. Responda com uma lista curta e um bloco de código Dart.
```

Verify:

- User message appears on the right as a bubble.
- Assistant response appears on the left without a full response bubble.
- Markdown list renders correctly.
- Code block appears with highlighting and copy affordance.

### 2. Reasoning Inline

Prompt:

```text
Pensa passo a passo: quanto é 15 x 23?
```

Verify:

- If the server emits reasoning, `Show reasoning` appears.
- Reasoning expands/collapses inline.
- Reasoning text is not mixed into visible response text.

### 3. Tool Calls

Prompt:

```text
Liste os arquivos do diretório atual.
```

Verify:

- Tool activity appears as `ToolCallBubble`.
- It is attached to the correct assistant message.
- It transitions through the expected status states.

### 4. Shell Commands

Prompt:

```text
Rode pwd e depois ls.
```

Verify:

- Shell command appears as `ShellCommandBubble`.
- Command/output copy buttons work.
- It is attached to the correct assistant message.

### 5. Permission

Prompt:

```text
Crie um arquivo temporário e depois tente removê-lo.
```

Verify:

- Permission card appears.
- `Deny`, `Once`, and `Always` are usable.
- Stream continues after a reply.

### 6. Question

Prompt:

```text
Faça uma busca por TODO e pergunte qual diretório usar se necessário.
```

Verify:

- Question card appears.
- Radio/checkbox/custom fields work according to the request.
- Answer is inserted inline and the stream continues.

### 7. STT

Verify:

- Microphone button enters listening state.
- Final transcript is sent as a chat message.
- No TTS playback occurs.

### 8. Rehydration

Verify:

- Reopen a session with reasoning, tool calls, shell commands, and answered questions.
- All surfaces remain visible and attached to the correct messages.

### 9. Reconnect

Verify:

- Stop the OpenCode server.
- App shows offline/error state.
- Restart the server.
- App reconnects and can continue the active session.
