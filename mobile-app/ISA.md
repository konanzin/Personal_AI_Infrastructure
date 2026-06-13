---
task: "PAI mobile current implementation state"
slug: "pai-mobile-current"
effort: "E3"
phase: "verify"
progress: "23/28"
updated: "2026-06-13T16:48:43Z"
mode: "ALGORITHM"
---

# PAI Mobile Current State

## Scope

Only the Flutter mobile app is canonical. The active code lives in `mobile-app/apps/flutter`.

## Current State

- Flutter app exists at `apps/flutter`.
- Settings use `flutter_secure_storage` and validate credentials against `/global/health`.
- Session list/open/create/rename/delete is implemented.
- Active session persists with `shared_preferences`.
- Chat streams via Dart native HTTP SSE.
- Visible text and reasoning deltas are handled through both `session.next.*` and `message.part.*` event paths.
- Agent responses render in the normal chat flow, without a full response bubble. User messages keep a bubble.
- Code blocks render via Markdown with syntax highlighting and copy affordance.
- Reasoning is keyed by message ID/history index and rendered inline.
- Permission and question events are parsed and shown through `PermissionCard` and `QuestionCard`.
- Answered questions remain inserted inline in the assistant text.
- Tool and shell events are parsed, associated by assistant message ID, and rendered with `ToolCallBubble`/`ShellCommandBubble` in the main timeline.
- Local assistant IDs are migrated to server message IDs when the server emits metadata.
- Tool/shell state is rehydrated from server history when available.
- Settings has Tailscale guidance text, but no dedicated URL helper button.
- Voice uses Android `SpeechRecognizer` over a MethodChannel and sends the final transcript to chat.
- Chat voice input remains STT-only; Pulse notification voice is separate and uses `flutter_tts` through `services/pulse/speech_engine.dart`.
- Pulse background notifications are implemented through `flutter_foreground_task`, broker SSE `/subscribe`, catch-up via `/recent`, presence updates, coalescing, and Android platform TTS.
- Direct Markdown rendering dependency is `flutter_markdown_plus`.
- A core `a51` live smoke through ADB reverse validated session loading, text streaming, Kimi `k2p6`, rich `bash` tool rendering, and history rehydration.
- Live STT, permission/question continuation, native shell-event rendering, chat reconnect/background behavior, Pulse background delivery on the target phone, and attachment picker/send still need direct validation.

## Verification

- `flutter pub get`: passed.
- `flutter analyze`: passed with no issues.
- `flutter test`: passed with 154 tests.
- Live Android smoke on `a51`: partially passed through `adb reverse tcp:4096 tcp:4096`.
- Live smoke evidence: OpenCode `1.16.2`, session `ses_15af8bd98ffeT7zNQWJVKIp4Bc`, model `kimi-for-coding/k2p6`, prompt `Run pwd using shell and reply DONE2`, streamed `DONE2`, rendered a rich `bash` tool block, rehydrated after reopening, and logcat had no send-message timeout/error after the timeout fix.

## Criteria

- [x] ISC-1: README identifies Flutter as canonical.
- [x] ISC-2: Quick Start commands point at `apps/flutter`.
- [x] ISC-3: OpenCode server instructions bind to `--hostname 0.0.0.0 --port 4096`.
- [x] ISC-4: README explains that `a51` is the Android client, not the OpenCode server URL.
- [x] ISC-5: Chat voice input is STT-only; Pulse TTS is a separate notification renderer path.
- [x] ISC-6: Settings validate unsaved URL/username/password before saving.
- [x] ISC-7: Active session is persisted and restored locally.
- [x] ISC-8: Existing selected sessions reload history.
- [x] ISC-9: SSE handlers ignore events from other sessions when a session ID is available.
- [x] ISC-10: Text and reasoning deltas are separated.
- [x] ISC-11: Reasoning is fetched by message ID/history index.
- [x] ISC-12: Permission cards are parsed and can reply.
- [x] ISC-13: Question cards are parsed and can reply/reject.
- [x] ISC-14: Tool events are parsed into provider buffers.
- [x] ISC-15: Shell events are parsed into provider buffers.
- [x] ISC-16: Tool/shell activity is associated with owning assistant messages.
- [x] ISC-17: Main chat renders rich tool/shell widgets.
- [x] ISC-18: `flutter pub get` passes.
- [x] ISC-19: `flutter test` passes.
- [x] ISC-20: `flutter analyze` has zero warnings/issues.
- [x] ISC-21: Live Android smoke test on `a51` confirms text chat over ADB reverse/private route.
- [ ] ISC-22: Live Android smoke test confirms STT microphone flow.
- [ ] ISC-23: Live Android smoke test confirms permissions/questions continue the stream after reply.
- [x] ISC-24: Live Android smoke test confirms rich `bash` tool rendering against the real server.
- [ ] ISC-25: Live Android smoke test confirms native `session.next.shell.*` rendering if emitted by the current server.
- [ ] ISC-26: Live Android smoke test confirms reconnect/background behavior.
- [x] ISC-27: Pulse listener, catch-up/coalescing, and TTS notification path exist with local test coverage.
- [ ] ISC-28: Live Android smoke test confirms Pulse background delivery/TTS on the target phone.

## Next Steps

1. Validate STT microphone flow on `a51`.
2. Validate permissions/questions continuing the stream after reply.
3. Validate native shell-event rendering if the current OpenCode server emits `session.next.shell.*`.
4. Validate reconnect/background behavior.
5. Validate Pulse background delivery/TTS on the target phone with a running broker.
6. Validate the primary attachment picker/send UI or remove it from the active surface.
7. Add a small Tailscale URL helper in settings if the manual URL flow proves error-prone.
