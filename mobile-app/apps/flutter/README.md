# PAI Mobile Flutter

Canonical Flutter Android client for PAI/OpenCode.

This app connects to an OpenCode Server, lists sessions, opens a chat timeline, streams SSE responses, supports STT voice input, and renders reasoning, permissions, questions, tool calls, and shell commands.

## Current Status

The app is functional pre-alpha. Local static and unit/widget gates are clean. A core live Android smoke on `a51` passed through ADB reverse; the remaining live gaps are listed below.

- `flutter pub get`: passes
- `flutter analyze`: passes with no issues
- `flutter test`: passes with 6 tests
- Live `a51` smoke via ADB reverse: connection/session list/text streaming/rich `bash` tool/history rehydration passed

Known remaining gaps:

- Attachment send path exists, but the primary attachment picker/send UI still needs live validation.
- Settings has Tailscale guidance text, but no dedicated Tailscale URL helper button.
- Voice is STT-only; no TTS exists in this stage.
- Live STT, permission/question continuation, native shell-event rendering, and reconnect/background behavior still need validation.

## Run

```bash
cd mobile-app/apps/flutter
flutter pub get
flutter analyze
flutter test
flutter run
```

For private network use, run OpenCode on the Linux host:

```bash
OPENCODE_SERVER_PASSWORD='<password>' opencode serve --hostname 0.0.0.0 --port 4096
```

Then configure the app with the server's Tailscale IP or MagicDNS URL:

```text
http://<server-tailnet-ip-or-name>:4096
```

`a51` is the Android client. It is not the server URL unless OpenCode is actually running on the phone.

## Code Map

```text
lib/
  main.dart                         # app entry point and global providers
  models/
    chat_event.dart                 # typed OpenCode SSE events
    event.dart                      # older normalized event model still present
    message_part.dart               # text/reasoning/tool/shell part models
  providers/
    settings_provider.dart          # settings + connection validation
    session_provider.dart           # sessions + active-session persistence
    opencode_provider.dart          # chat/SSE/history/reasoning/tool/shell/question/permission state
  screens/
    settings_screen.dart            # server/auth settings
    sessions_screen.dart            # session list and actions
    chat_screen.dart                # primary chat UI
    events_screen.dart              # SSE debug screen
  services/
    opencode_client.dart            # REST + SSE client
    secure_storage.dart             # credential storage
    connectivity_service.dart       # heartbeat/reconnect status
    voice_service.dart              # Android STT MethodChannel
    permission_service.dart         # device permissions helper
  widgets/
    code_block_widget.dart
    connection_status_indicator.dart
    date_header.dart
    permission_card.dart
    question_card.dart
    reasoning_message_bubble.dart
    shell_command_bubble.dart       # rich shell command block
    tool_call_bubble.dart           # rich tool call block
    voice_fab.dart
```

Android STT bridge:

```text
android/app/src/main/kotlin/com/example/pai_mobile_flutter/MainActivity.kt
```

## Verification Notes

Latest verified environment:

- Flutter 3.44.0
- Dart 3.12.0

Latest command results:

- `flutter pub get`: passed
- `flutter analyze`: passed with no issues
- `flutter test`: passed with 6 tests

Latest live result:

- Android `a51` / SM-A515F connected through `adb reverse tcp:4096 tcp:4096`.
- OpenCode health returned `{"healthy":true,"version":"1.16.2"}`.
- The created session used `kimi-for-coding/k2p6`.
- Prompt `Run pwd using shell and reply DONE2` streamed `DONE2`, rendered a rich `bash` tool block, and rehydrated correctly after reopening the session.
- Logcat had no `TimeoutException` or send-message error after the message timeout fix.

The next engineering gate is the remaining live smoke coverage: STT, permission/question continuation, reconnect/background behavior, native shell events if emitted by the current server, and attachment picker/send validation.
