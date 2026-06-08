# PAI Mobile Flutter - Implementation Status

> Status: functional pre-alpha. Local gates are clean; core live Android smoke passed via ADB reverse. Full alpha still depends on the remaining live flows.

## Scope

The active implementation lives in `mobile-app/apps/flutter`. The target platform is Android `a51`, normally over Tailscale; ADB reverse is the local USB smoke path.

## Implemented

### Settings And Security

- [x] Settings screen with server URL, username, and password.
- [x] `flutter_secure_storage` for credentials.
- [x] Real connection validation against `/global/health` before saving.
- [x] No user/password/Basic Auth header logs.
- [x] Tailscale/MagicDNS guidance text.
- [ ] Dedicated helper to fill/normalize `http://<host>:4096`.

### Sessions

- [x] List OpenCode sessions.
- [x] Open existing sessions.
- [x] Create sessions.
- [x] Rename/delete sessions.
- [x] Active session badge/title in the app bar.
- [x] Local active-session persistence with `shared_preferences`.

### Chat, SSE, And Reasoning

- [x] History through `flutter_ai_toolkit`.
- [x] Assistant messages render in normal flow without a full assistant bubble.
- [x] User messages render as bubbles.
- [x] Markdown rendering through `flutter_markdown_plus`.
- [x] SSE via Dart native `http` streaming.
- [x] SSE filtering by active session when `sessionID` is present.
- [x] Visible text deltas from `session.next.text.delta`.
- [x] Reasoning deltas from `session.next.reasoning.delta`.
- [x] Alternative `message.part.delta` paths filtered by part type.
- [x] Reasoning associated by message ID/history index.
- [x] Inline expandable reasoning below the assistant message.
- [x] Code blocks with syntax highlighting and copy button.
- [x] Date headers in the timeline.
- [x] History rehydration after reconnect.
- [ ] Pull-to-refresh in chat history.
- [x] Real device smoke for text streaming and history rehydration.
- [ ] Real device test for interruption/reconnect.

### Tooling, Permissions, And Questions

- [x] Typed SSE event models in `models/chat_event.dart`.
- [x] `ToolCallPart` and `ShellPart` in `models/message_part.dart`.
- [x] Provider parses `session.next.tool.*`.
- [x] Provider parses `session.next.shell.*`.
- [x] Provider parses `permission.asked/replied`.
- [x] Provider parses `question.asked/replied/rejected`.
- [x] `PermissionCard` renders pending requests with `Deny`, `Once`, `Always`.
- [x] `QuestionCard` renders radio/checkbox/custom text.
- [x] Answered questions appear inline in the assistant text.
- [x] Tool calls are associated by owning assistant `messageID`.
- [x] Shell commands are associated by owning assistant `messageID`.
- [x] `ToolCallBubble` is integrated into the main timeline.
- [x] `ShellCommandBubble` is integrated into the main timeline.
- [x] Live `a51` smoke verifies rich `bash` tool rendering against OpenCode.
- [ ] Live `a51` smoke verifies native `session.next.shell.*` rendering if emitted by the current server.

### Voice

- [x] Native Android bridge with `SpeechRecognizer`.
- [x] Voice button states: idle/listening/processing/error.
- [x] Final transcript sent to chat as a normal message.
- [x] TTS is out of scope.
- [ ] Optional transcript review before send.
- [ ] Real microphone smoke test on `a51`.

### Resilience

- [x] Visual connection-state indicator.
- [x] Manual reconnect rehydrates active session.
- [x] SSE disconnect/error schedules rehydration with backoff.
- [x] Active session cached locally.
- [x] Reopening a live `a51` session rehydrates the streamed text and `bash` tool block.
- [ ] Recovery validation after background/foreground.
- [ ] Real network test over Tailscale online/offline transitions.

## Architecture

```text
apps/flutter/lib/
  main.dart
  models/
    chat_event.dart
    event.dart
    message_part.dart
  services/
    opencode_client.dart
    secure_storage.dart
    connectivity_service.dart
    voice_service.dart
  providers/
    settings_provider.dart
    session_provider.dart
    opencode_provider.dart
  screens/
    settings_screen.dart
    sessions_screen.dart
    chat_screen.dart
    events_screen.dart
  widgets/
    code_block_widget.dart
    connection_status_indicator.dart
    date_header.dart
    permission_card.dart
    question_card.dart
    reasoning_message_bubble.dart
    tool_call_bubble.dart
    shell_command_bubble.dart
    voice_fab.dart
```

Android bridge:

```text
apps/flutter/android/app/src/main/kotlin/com/example/pai_mobile_flutter/MainActivity.kt
```

## How To Run

On the OpenCode host:

```bash
OPENCODE_SERVER_PASSWORD='<password>' opencode serve --hostname 0.0.0.0 --port 4096
```

In the Flutter app, configure:

```text
http://<server-tailscale-ip-or-magicdns>:4096
```

In the Flutter workspace:

```bash
cd mobile-app/apps/flutter
flutter pub get
flutter analyze
flutter test
flutter run
```

## Alpha Criteria

- [x] App connects to OpenCode Server through validated settings.
- [x] Auth validates against `/global/health`.
- [x] Sessions can be listed/opened/created/renamed/deleted.
- [x] Active session persists.
- [x] Messages stream over SSE.
- [x] Reasoning can be viewed per message.
- [x] STT sends transcript to chat.
- [x] TTS is not initialized or called.
- [x] Permission/question cards work in provider/UI.
- [x] Tool/shell render as rich timeline blocks.
- [x] Tool/shell are associated by message ID.
- [x] `flutter analyze` passes.
- [x] `flutter test` passes.
- [x] Core `a51` smoke via ADB reverse validates connection, text streaming, Kimi `k2p6`, rich `bash` tool rendering, and history rehydration.
- [ ] Survives real network/background interruptions.
- [ ] Remaining live smoke on `a51`: STT, permission/question continuation, native shell event if emitted, reconnect/background, and attachment picker/send.

## Next Steps

1. Smoke-test STT microphone on `a51`.
2. Validate permission/question continuation on `a51`.
3. Test network drop/reconnect and background/foreground behavior.
4. Validate native shell-event rendering if the current OpenCode server emits `session.next.shell.*`.
5. Validate or remove the primary attachment picker/send UI.

## History

- 2026-05-28: Document created after initial Flutter validation.
- 2026-05-30: Flutter promoted to the canonical mobile track.
- 2026-06-07: Documentation cleanup removed obsolete mobile paths.
- 2026-06-08: Local gates are clean; rich tool/shell timeline and message-level association are implemented.
- 2026-06-08: Core `a51` smoke via ADB reverse passed for connection, text streaming, Kimi `k2p6`, rich `bash` tool rendering, and history rehydration.
