---
task: PAI Mobile Flutter canonical app
slug: pai-mobile-flutter
effort: E3
phase: complete
progress: 32/32
mode: algorithm
started: 2026-05-28T00:00:00Z
updated: 2026-05-30T00:00:00Z
project: mobile-app
---

## Problem

The mobile app documentation and ISA still described the old React Native/Expo path, while the actual working app is now `apps/flutter`. That mismatch creates the dangerous failure mode where future work optimizes the abandoned stack instead of the app that actually connects to OpenCode. The Flutter app also had alpha-blocking runtime gaps: connection tests were fake, SSE events were not strongly scoped to the active session, reasoning could attach to the wrong assistant message, voice input was not wired to chat, and the selected session was not persisted locally.

## Vision

PAI Mobile is the private Android remote for OpenCode and Dori: open the app on `a51`, point it at the Linux OpenCode server over Tailscale, pick up the last session, speak or type, and get the exact current-session response with optional reasoning visible on the right bubble only when the server produced it. The user should feel that Flutter became the obvious canonical path because it is simpler, more native, and less fragile than the React Native experiment.

## Out of Scope

- No TTS playback in this stage; voice means STT input only.
- No theme redesign, persistent theme toggle, or visual-polish pass in this stage.
- No push-notification plugin or deep-link workflow in this stage.
- No server-side OpenCode protocol changes; the app adapts to the official OpenCode Server API.
- No revival of React Native/Expo packages as active implementation targets.

## Principles

- The canonical app is the one that survives real OpenCode streaming on Android, not the one with the original plan.
- Mobile security starts with eliminating credential leakage and refusing to save unvalidated connection settings.
- Global SSE streams must be treated as shared infrastructure: every UI update proves it belongs to the selected session.
- Reasoning is useful only when it is associated with the correct assistant message; wrong reasoning is worse than hidden reasoning.
- Voice-first should reduce friction without inventing audio output before the text loop is reliable.

## Constraints

- Canonical source tree: `mobile-app/apps/flutter`.
- Package manager policy: use Flutter/Dart tooling for Flutter and Bun where PAI scripts apply; never npm/npx.
- OpenCode Server API source: official server docs plus local `opencode-api-doc.json`.
- OpenCode default port: `4096`.
- Tailscale target: Android client `a51` connects to the Linux host running OpenCode, not to itself.
- OpenCode must bind beyond localhost for Tailscale access, e.g. `opencode serve --hostname 0.0.0.0 --port 4096` with `OPENCODE_SERVER_PASSWORD` set when auth is required.
- Verification is partially environment-blocked until Flutter/Dart CLI is installed in this shell.

## Goal

Make `mobile-app/apps/flutter` the documented and architectural source of truth for PAI Mobile, with secure real OpenCode connection validation, Tailscale setup guidance, current-session SSE handling, stable reasoning association, STT-only voice submission, active-session persistence, and explicit verification notes for what can and cannot be proven in this environment.

## Criteria

- [x] ISC-1: `mobile-app/README.md` names Flutter as canonical and React Native as legacy/removed.
- [x] ISC-2: `mobile-app/README.md` points Quick Start commands at `apps/flutter`.
- [x] ISC-3: `mobile-app/README.md` documents Tailscale server binding with `--hostname 0.0.0.0 --port 4096`.
- [x] ISC-4: `mobile-app/README.md` states `a51` is the Android client, not the server URL.
- [x] ISC-5: `mobile-app/README.md` says voice is STT-only and TTS is out of scope.
- [x] ISC-6: `mobile-app/FLUTTER_IMPLEMENTATION_PLAN.md` shows current implementation status instead of all-empty checkboxes.
- [x] ISC-7: `mobile-app/FLUTTER_IMPLEMENTATION_PLAN.md` defers theme work to the next stage.
- [x] ISC-8: `mobile-app/ISA.md` no longer describes `react-native-sse` or `event-source-polyfill` as current work.
- [x] ISC-9: `OpenCodeClient.verifyAuth()` hits `/global/health` with Basic Auth and returns false on failure.
- [x] ISC-10: `OpenCodeClient.verifyAuth()` does not log username, password, or Authorization header.
- [x] ISC-11: Settings save validates unsaved URL/username/password before persisting credentials.
- [x] ISC-12: Settings screen has a Tailscale helper that fills `http://<host>:4096` without duplicating ports.
- [x] ISC-13: Settings screen explains the Linux server vs `a51` client distinction.
- [x] ISC-14: `SessionProvider` persists the selected session ID locally.
- [x] ISC-15: App startup restores the persisted selected session before chat initialization.
- [x] ISC-16: Deleting the selected session clears the persisted selected session ID.
- [x] ISC-17: `OpenCodeProvider` reloads history for an existing selected session.
- [x] ISC-18: SSE handlers ignore events whose `sessionID` does not match the active session.
- [x] ISC-19: `session.next.text.delta` appends visible assistant text to the active response stream.
- [x] ISC-20: `session.next.reasoning.delta` appends reasoning without leaking it into assistant visible text.
- [x] ISC-21: `message.part.delta` text is accepted only from known text parts.
- [x] ISC-22: `message.part.delta` reasoning is accepted only from known reasoning parts.
- [x] ISC-23: Reasoning buffers are keyed by stable message ID when the server emits one.
- [x] ISC-24: Temporary local assistant IDs migrate reasoning when the server message ID later arrives.
- [x] ISC-25: Chat UI fetches reasoning by message index/message ID, not by “first reasoning found”.
- [x] ISC-26: Chat UI exposes reasoning only on the assistant message that owns it.
- [x] ISC-27: SSE disconnect/error triggers history rehydration for the active session.
- [x] ISC-28: Manual reconnect reloads active-session history rather than only flipping status online.
- [x] ISC-29: Voice button uses native Android STT and sends final transcript to chat.
- [x] ISC-30: Flutter and Android voice code do not initialize or call TTS.
- [x] ISC-31: Anti: React Native/Expo commands remain documented as the primary mobile workflow.
- [x] ISC-32: Anti: Flutter verification is claimed complete without an actual `flutter analyze`/`flutter test` run or an explicit blocker note.

## Features

| Feature | Description | Satisfies | Depends on | Parallelizable |
|---------|-------------|-----------|------------|----------------|
| Canonical docs | Replace stale RN/Expo narrative with Flutter/Tailscale truth | ISC-1..8, ISC-31 | none | true |
| Secure settings | Real health/auth validation before save, no secret logging | ISC-9..13 | OpenCode docs | true |
| Session persistence | Cache and restore active OpenCode session | ISC-14..17 | settings | true |
| SSE correctness | Filter global stream and rehydrate on disconnect | ISC-18..22, ISC-27..28 | OpenCode client | false |
| Reasoning association | Stable message/part ID mapping for reasoning UI | ISC-23..26 | SSE correctness | false |
| STT-only voice | Native Android speech input sends transcript to chat, no TTS | ISC-29..30 | chat send path | true |
| Verification notes | Run available checks and record Flutter CLI blocker | ISC-32 | implementation | false |

## Test Strategy

| ISC | Type | Check | Tool |
|-----|------|-------|------|
| ISC-1..8, ISC-31 | static docs | Docs contain Flutter canonical wording and no RN primary workflow | Read/Grep |
| ISC-9..13 | static/runtime intent | Client/settings code validates health/auth and hides credentials | Read/Grep; Flutter test when CLI exists |
| ISC-14..17 | static/runtime intent | SharedPreferences active-session key and restore path exist | Read/Grep; Flutter test when CLI exists |
| ISC-18..22 | static/runtime intent | SSE handlers filter by session and part type | Read/Grep; live OpenCode stream on Android when CLI/device ready |
| ISC-23..26 | static/runtime intent | Reasoning UI resolves by message ID/index | Read/Grep; live OpenCode reasoning response when device ready |
| ISC-27..28 | static/runtime intent | Reconnect calls active-session rehydration | Read/Grep; network interruption smoke test when device ready |
| ISC-29..30 | static/runtime intent | VoiceService/MainActivity expose STT only and ChatScreen sends transcript | Read/Grep; Android microphone smoke test when CLI/device ready |
| ISC-32 | command | `flutter analyze` and `flutter test`, or explicit CLI blocker | Bash |

## Decisions

- 2026-05-30: refined: `mobile-app/ISA.md` now tracks the persistent Flutter app instead of the retired React Native SSE migration.
- 2026-05-30: Flutter is canonical because Dart native streaming removed the React Native SSE polyfill/XHR failure class.
- 2026-05-30: TTS is deliberately removed from this stage; STT input is enough to validate the voice-first loop without creating audio-output complexity.
- 2026-05-30: Tailscale helper targets the OpenCode server host; `a51` is the Android client in the tailnet.
- 2026-05-30: Advisor gate was attempted but blocked because `Inference.ts` is missing from the configured PAI tool paths.

## Verification

ISC-1..5: Read `mobile-app/README.md` — Flutter canonical path, Tailscale instructions, `a51` client warning, and STT-only voice scope are present.
ISC-6..7: Read `mobile-app/FLUTTER_IMPLEMENTATION_PLAN.md` — current status checkboxes are populated and theme work is explicitly deferred.
ISC-8: Read `mobile-app/ISA.md` — stale `react-native-sse`/`event-source-polyfill` migration is replaced by the Flutter app ISA.
ISC-9..10: Read/Grep `opencode_client.dart` — `verifyAuth()` calls `/global/health`, sends Authorization header, returns `false` on failure, and has no credential debug logging.
ISC-11..13: Read `settings_screen.dart`/`settings_provider.dart` — save tests unsaved credentials before persistence; Tailscale URL helper normalizes host/port; info text distinguishes Linux server from `a51`.
ISC-14..16: Read `session_provider.dart`/`main.dart` — `shared_preferences` key `active_session_id` is restored at startup, persisted on select/create, and cleared on delete.
ISC-17..28: Read/Grep `opencode_provider.dart` — history loading, current-session filtering, text/reasoning delta handling, part-type filters, reasoning ID migration, and rehydration reconnect paths are present.
ISC-25..26: Read `chat_screen.dart` — reasoning is fetched by `getReasoningForHistoryIndex(index)` instead of scanning the first available reasoning buffer.
ISC-29..30: Read/Grep `voice_service.dart`, `voice_fab.dart`, `MainActivity.kt`, and `chat_screen.dart` — SpeechRecognizer is wired to chat; TTS symbols are absent from Flutter/Android code.
ISC-31: Read `mobile-app/README.md` — React Native/Expo is documented only as legacy, not as the primary workflow.
ISC-32: Bash `flutter analyze` and `flutter test` — both blocked with `/usr/bin/bash: line 1: flutter: command not found`; final report must state this blocker instead of claiming full Flutter verification.
Advisor: Bash `bun .../Inference.ts --mode advisor` — blocked with `Module not found`, so no advisor result was available.

## Changelog

- 2026-05-30: conjectured `mobile-app` still needed a React Native-era ISA; refuted by `apps/flutter` being the only active app and the user's Flutter/Tailscale requirements; learned the project ISA must track the persistent Flutter app, not old migration tasks; criterion now ISC-1..8 lock Flutter as canonical and archive RN/Expo as legacy.
