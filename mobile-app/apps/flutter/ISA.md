---
task: "PAI Mobile Flutter current implementation state"
slug: "pai-mobile-flutter-current"
effort: "E3"
phase: "verify"
progress: "17/22"
updated: "2026-06-08T02:30:00Z"
mode: "ALGORITHM"
---

# PAI Mobile Flutter Current State

## Problem

The Flutter app now has the M5 surfaces wired in code. Local analyzer/test health is clean. Core live Android behavior was validated on `a51` through ADB reverse, but several mobile flows still need direct live evidence.

## Current Implementation

- `ToolCallBubble` is implemented in `lib/widgets/tool_call_bubble.dart`.
- `ShellCommandBubble` is implemented in `lib/widgets/shell_command_bubble.dart`.
- `chat_screen.dart` renders user messages as bubbles and assistant messages in the normal flow without a full assistant bubble.
- Assistant Markdown still handles text, lists, inline code, blockquotes, and code blocks.
- `_buildDisplayText()` only inserts answered question summaries; tool/shell snippets are no longer inserted as Markdown.
- Tool calls render as rich timeline blocks via `ToolCallBubble`.
- Shell commands render as rich timeline blocks via `ShellCommandBubble`.
- `OpenCodeProvider` parses tool, shell, permission, question, text, reasoning, message, status, and connection events.
- Tool calls and shell commands are associated by assistant `messageID`.
- Local assistant message IDs are migrated when server IDs arrive.
- History loading populates tool/shell buffers and message-level associations when parts are present.
- `flutter_markdown_plus` is the direct Markdown widget dependency.

## Criteria

- [x] ISC-1: `lib/widgets/tool_call_bubble.dart` exists.
- [x] ISC-2: `ToolCallBubble` handles pending/running/completed/error states.
- [x] ISC-3: `lib/widgets/shell_command_bubble.dart` exists.
- [x] ISC-4: `ShellCommandBubble` renders command/output with copy affordances.
- [x] ISC-5: `OpenCodeProvider` parses tool events.
- [x] ISC-6: `OpenCodeProvider` parses shell events.
- [x] ISC-7: Main chat renders rich tool activity.
- [x] ISC-8: Main chat renders rich shell activity.
- [x] ISC-9: Permission cards are integrated into the main chat UI.
- [x] ISC-10: Question cards are integrated into the main chat UI.
- [x] ISC-11: Reasoning is integrated inline.
- [x] ISC-12: Code blocks are integrated into Markdown rendering.
- [x] ISC-13: `flutter test` passes.
- [x] ISC-14: `flutter analyze` is clean.
- [x] ISC-15: Tool calls are filtered by owning message ID.
- [x] ISC-16: Shell commands are filtered by owning message ID.
- [x] ISC-17: Live Android smoke test verifies rich tool rendering.
- [ ] ISC-18: Live Android smoke test verifies rich shell rendering.
- [ ] ISC-19: Live Android smoke test verifies permission/question continuation.
- [ ] ISC-20: Live Android smoke test verifies STT.
- [ ] ISC-21: Live Android smoke test verifies reconnect/background behavior.
- [ ] ISC-22: Attachment picker/send UI is either validated or removed from active scope.

## Verification

- `flutter pub get`: passed.
- `flutter analyze`: passed with no issues.
- `flutter test`: passed with 6 tests.
- Added tests cover SSE event parsing and provider tool/shell message association.
- Live `a51` smoke through `adb reverse tcp:4096 tcp:4096` passed for session loading, text streaming, Kimi `k2p6`, rich `bash` tool rendering, and history rehydration.
- The current OpenCode server emitted the `bash` execution as `message.part.updated` tool parts; no live `session.next.shell.*` event was observed in this smoke.

## Next Steps

1. Validate STT on `a51`.
2. Validate permission/question continuation on `a51`.
3. Validate reconnect/background behavior on `a51`.
4. Validate native shell-event rendering if the current OpenCode server emits `session.next.shell.*`.
5. Validate attachment UI or remove it from active scope.
