# PAI Mobile

Private Android interface for PAI/OpenCode. This app is the mobile remote for Dori: connect over the private Tailscale network, select an OpenCode session, type or speak a prompt, and stream the assistant response from the OpenCode Server.

## Canonical App

```text
mobile-app/
  apps/
    flutter/                 # Canonical Flutter app
  ISA.md                     # System of record for the mobile app
  FLUTTER_IMPLEMENTATION_PLAN.md
```

## Current Status

The Flutter app is the active mobile product. It is a functional pre-alpha client. Local static and test gates pass. A core live smoke on Android `a51` passed through ADB reverse; full alpha still depends on the remaining live mobile flows listed below.

- Flutter app exists at `apps/flutter`.
- Settings store credentials with `flutter_secure_storage`.
- Connection validation uses OpenCode `/global/health`.
- Session list/open/create/rename/delete exists.
- Chat streams OpenCode SSE with Dart native HTTP streaming.
- Active session persists locally with `shared_preferences`.
- Voice input is STT-only and sends the final transcript to chat.
- Reasoning is associated by message ID/history index and rendered inline.
- Permission and question cards are parsed from SSE and can reply to the server.
- Tool calls and shell commands are associated by assistant message ID and rendered as rich timeline blocks.
- Settings has Tailscale guidance text; it does not currently include a dedicated Tailscale URL helper button.
- `flutter analyze` passes with no issues.
- `flutter test` passes with 6 tests.
- Live `a51` smoke over ADB reverse validated session loading, text streaming, Kimi `k2p6`, rich `bash` tool rendering, and history rehydration.
- Live STT, permission/question continuation, reconnect/background behavior, and the primary attachment UI still need validation.

## Requirements

- Flutter SDK compatible with the app's `pubspec.yaml`.
- Android device or emulator.
- OpenCode Server reachable from the device.
- Tailscale on the Android device and server host for private remote use.

## Quick Start

```bash
cd mobile-app/apps/flutter
flutter pub get
flutter analyze
flutter test
flutter run
```

## OpenCode Server For Tailscale

On the Linux machine that runs OpenCode, expose the server on the tailnet interface:

```bash
OPENCODE_SERVER_PASSWORD='<your-password>' opencode serve --hostname 0.0.0.0 --port 4096
```

Then, in the Flutter app settings, use the Linux server's Tailscale IP or MagicDNS name:

```text
http://<server-tailnet-ip-or-name>:4096
```

Important: `a51` is the Android client in the tailnet. It is not the OpenCode server URL unless OpenCode is running on the phone, which this app does not do.

## Voice Scope

Voice in this stage means:

1. Tap microphone.
2. Android SpeechRecognizer captures speech.
3. The final transcript is sent as a normal chat message.

No TTS playback is implemented in this stage.

## Verification

Latest local verification:

- `flutter pub get`: passed
- `flutter analyze`: passed with no issues
- `flutter test`: passed with 6 tests

Latest live verification:

- Device: Android `a51` / SM-A515F, Android 13.
- Server: OpenCode `1.16.2` with `adb reverse tcp:4096 tcp:4096`.
- Model: `kimi-for-coding/k2p6`.
- Prompt: `Run pwd using shell and reply DONE2`.
- Result: streamed `DONE2`, rendered a rich `bash` block, rehydrated correctly after reopening the session, and produced no send-message timeout/error in logcat.

Remaining live smoke on `a51`:

1. Start OpenCode on the Linux host with `--hostname 0.0.0.0 --port 4096`.
2. Confirm the phone and server are online in Tailscale, or configure `adb reverse tcp:4096 tcp:4096` for local USB smoke.
3. Fill settings with the server tailnet URL, or `http://localhost:4096` when using ADB reverse.
4. Test connection.
5. Send a voice prompt.
6. Trigger permission and question events and confirm the stream continues after replies.
7. Trigger native shell events if the current OpenCode server emits `session.next.shell.*`.
8. Test network drop/reconnect and background/foreground behavior.
9. Validate the primary attachment picker/send UI or remove it from active scope.

## Related Files

- `apps/flutter/lib/services/opencode_client.dart` - REST + SSE client.
- `apps/flutter/lib/providers/opencode_provider.dart` - chat stream, history, reasoning, tool/shell buffers, permissions/questions, reconnect.
- `apps/flutter/lib/providers/session_provider.dart` - session list and active-session persistence.
- `apps/flutter/lib/screens/settings_screen.dart` - settings, auth validation, Tailscale guidance text.
- `apps/flutter/lib/screens/chat_screen.dart` - chat timeline, Markdown/code blocks, inline reasoning, permission/question cards, rich tool/shell blocks, voice input.
- `apps/flutter/lib/widgets/voice_fab.dart` - STT-only voice button.
- `apps/flutter/lib/widgets/tool_call_bubble.dart` - rich tool-call block.
- `apps/flutter/lib/widgets/shell_command_bubble.dart` - rich shell-command block.
