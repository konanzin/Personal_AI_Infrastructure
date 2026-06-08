# PAI Mobile Flutter - Checklist

> Atualizado em 2026-06-08. Este checklist descreve o app Flutter atual. `flutter analyze` e `flutter test` passam; o smoke core live no `a51` passou via ADB reverse.

## Implementation Caveats

- Agent responses render in the normal chat flow, without a full assistant bubble.
- User messages still render as bubbles.
- Tool calls and shell commands are rendered as rich timeline blocks with `ToolCallBubble` and `ShellCommandBubble`.
- Tool/shell getters return message-level subsets when message IDs are available.
- File attachments have a provider/client send path, but no validated primary UI flow for selecting and sending files.
- Live `a51` smoke validated rich `bash` tool rendering through `message.part.updated`; native `session.next.shell.*` rendering still needs live evidence if the current server emits those events.

## Features Implemented

### Core Chat

- [x] SSE streaming with triple-path deduplication
- [x] Session filtering by sessionId
- [x] Message ID binding and local-to-server migration
- [x] Reverse chronological message list with date headers
- [x] Markdown rendering with syntax-highlighted code blocks
- [x] Assistant messages without a full response bubble
- [x] User messages with bubbles
- [x] Long-press message context menu (Copy / Revert / Fork)
- [x] Auto-scroll on stream complete

### Sessions

- [x] List sessions with pull-to-refresh
- [x] Create new session
- [x] Open existing session
- [x] Rename session
- [x] Delete session
- [x] Active session highlight
- [x] Relative date formatting

### Reasoning

- [x] Reasoning accumulation per message
- [x] Expandable reasoning block below message
- [x] Reasoning rehydration on history load

### Permissions & Questions

- [x] Permission cards (Deny / Once / Always)
- [x] Question cards (radio / checkbox / custom text)
- [x] Answered questions rendered inline in Markdown at the captured offset
- [x] Answered questions persisted to SecureStorage
- [x] Continuation wait after reply

### Tool Calls & Shell Commands

- [x] Tool call state machine (pending -> running -> completed/error)
- [x] Shell command tracking
- [x] Message-level association for tool calls
- [x] Message-level association for shell commands
- [x] Rich tool call rendering in the main timeline
- [x] Rich shell command rendering in the main timeline
- [x] Tool call rehydration from server history when parts are present
- [x] Shell command rehydration from server history when parts are present
- [x] Hidden internal tools (question, ask, todowrite)

### Stop / Abort

- [x] `POST /session/{id}/abort` endpoint
- [x] Stop button visible during streaming
- [x] `isStreaming` state flag

### Error Surfacing

- [x] ErrorEvent and session.error displayed as MaterialBanner
- [x] Dismiss button to clear errors
- [x] Error messages from failed POST requests surfaced

### Model / Provider Picker

- [x] `GET /provider` lists available models
- [x] Bottom sheet model picker
- [x] Model override per message via `sendMessageAdvanced()`
- [x] Current model shown in AppBar subtitle
- [x] "Default (server)" option to clear override

### Session Info

- [x] `GET /session/{id}` fetches model, cost, tokens, agent, share
- [x] Session info bottom sheet
- [x] Auto-refresh after each response completes

### Attachments

- [x] `sendMessageAdvanced()` with file parts support
- [x] FileAttachment converted to FilePartInput format
- [ ] Primary attachment picker/send UI validated in the chat screen

### Voice

- [x] Android STT via `SpeechRecognizer`
- [x] Final transcript sent to chat
- [ ] TTS intentionally out of scope

## Local Verification

```bash
cd mobile-app/apps/flutter
flutter pub get
flutter analyze
flutter test
```

Latest local result:

- `flutter pub get`: passed
- `flutter analyze`: passed with no issues
- `flutter test`: passed with 6 tests

## Live Verification

Latest live `a51` result:

- [x] Install/run on Android `a51`
- [x] Validate connection/session list over ADB reverse
- [x] Validate text chat over ADB reverse/private route
- [x] Validate Kimi `k2p6` session/model display
- [x] Validate rich `bash` tool rendering
- [x] Validate history rehydration after reopening the session
- [x] Confirm logcat has no send-message timeout/error after the timeout fix

Still needed:

- [ ] Validate STT microphone flow
- [ ] Validate permission/question continuation
- [ ] Validate native rich shell rendering from `session.next.shell.*`, if emitted by the current server
- [ ] Validate reconnect/background behavior
- [ ] Validate or remove the primary attachment picker/send UI
