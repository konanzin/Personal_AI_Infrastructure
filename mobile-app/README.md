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

The previous React Native/Expo workspace is legacy. Do not start new implementation work there unless the project is explicitly re-opened as an archival migration task.

## Current Status

The Flutter app is a functional pre-alpha spine, not an alpha release yet.

- ✅ Flutter app exists at `apps/flutter`
- ✅ Settings store credentials with `flutter_secure_storage`
- ✅ Connection validation uses OpenCode `/global/health`
- ✅ Session list/open/create/rename/delete exists
- ✅ Chat streams OpenCode SSE with Dart native HTTP streaming
- ✅ Active session persists locally with `shared_preferences`
- ✅ Voice input is STT-only and sends the final transcript to chat
- 🚧 Runtime verification is blocked in this shell until Flutter/Dart CLI is installed

## Requirements

- Flutter SDK compatible with the app's `pubspec.yaml`
- Android device or emulator
- OpenCode Server reachable from the device
- Tailscale on the Android device and server host for private remote use

## Quick Start

```bash
cd mobile-app/apps/flutter
flutter pub get
flutter analyze
flutter test
flutter run
```

## OpenCode Server for Tailscale

On the Linux machine that runs OpenCode, expose the server on the tailnet interface:

```bash
OPENCODE_SERVER_PASSWORD='<your-password>' opencode serve --hostname 0.0.0.0 --port 4096
```

Then, in the Flutter app settings, use the Linux server's Tailscale IP or MagicDNS name:

```text
http://<server-tailnet-ip-or-name>:4096
```

Important: `a51` is the Android client in the tailnet. It is not the OpenCode server URL unless you are running OpenCode on the phone, which this app does not do.

## Authentication

OpenCode Server supports Basic Auth when `OPENCODE_SERVER_PASSWORD` is set. The app stores URL, username, and password in Android secure storage. Settings are validated against `/global/health` before saving.

## Voice Scope

Voice in this stage means:

1. Tap microphone.
2. Android SpeechRecognizer captures speech.
3. The final transcript is sent as a normal chat message.

No TTS playback is implemented in this stage.

## Verification

Use these checks once Flutter is available in the environment:

```bash
cd mobile-app/apps/flutter
flutter pub get
flutter analyze
flutter test
```

Then smoke-test on `a51`:

1. Start OpenCode on the Linux host with `--hostname 0.0.0.0 --port 4096`.
2. Confirm the phone and server are online in Tailscale.
3. Fill settings with the server tailnet URL.
4. Test connection.
5. Open an existing session.
6. Send a text prompt.
7. Send a voice prompt.
8. Confirm only the active session receives streamed updates.
9. Trigger a reasoning-capable response and confirm reasoning appears only on that assistant message.

## Related Files

- `apps/flutter/lib/services/opencode_client.dart` — REST + SSE client
- `apps/flutter/lib/providers/opencode_provider.dart` — chat stream, history, reasoning, reconnect
- `apps/flutter/lib/providers/session_provider.dart` — session list and active-session persistence
- `apps/flutter/lib/screens/settings_screen.dart` — settings, auth validation, Tailscale helper
- `apps/flutter/lib/widgets/voice_fab.dart` — STT-only voice button
- `apps/flutter/android/app/src/main/kotlin/com/example/pai_mobile_flutter/MainActivity.kt` — Android SpeechRecognizer bridge

## License

Private — not for distribution.
