# PAI Mobile Flutter — Feature Checklist & Test Guide

## Features Implemented

### Core Chat
- [x] SSE streaming with triple-path deduplication
- [x] Session filtering by sessionId
- [x] Message ID binding (local → server)
- [x] Reverse chronological message list with date headers
- [x] Markdown rendering with syntax-highlighted code blocks
- [x] Long-press message context menu (Copy / Revert / Fork)
- [x] Auto-scroll on stream complete

### Sessions
- [x] List sessions with pull-to-refresh
- [x] Create new session
- [x] Open existing session
- [x] Rename session (long-press)
- [x] Delete session (long-press with confirmation)
- [x] Active session highlight
- [x] Relative date formatting

### Reasoning
- [x] Reasoning accumulation per message (including from tool-only messages)
- [x] Expandable reasoning bubble below message
- [x] Reasoning rehydration on history load

### Permissions & Questions
- [x] Permission cards (Deny / Once / Always)
- [x] Question cards (radio / checkbox / custom text)
- [x] Answered questions rendered inline in markdown (highlighted, at correct offset)
- [x] Answered questions persisted to SecureStorage
- [x] Continuation wait after reply (30s timeout)

### Tool Calls & Shell Commands
- [x] Tool call state machine (pending → running → completed/error)
- [x] Shell command tracking
- [x] Inline rendering in markdown with unicode status indicators (⏳/✓/✗)
- [x] Command text displayed for bash tool calls
- [x] Chronological ordering for multiple tool calls at same offset
- [x] Tool call rehydration from server history
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
- [x] `GET /provider` lists all available models
- [x] Bottom sheet model picker (via menu "...")
- [x] Model override per message via `sendMessageAdvanced()`
- [x] Current model shown in AppBar subtitle
- [x] "Default (server)" option to clear override

### Session Info
- [x] `GET /session/{id}` fetches model, cost, tokens, agent, share
- [x] Session info bottom sheet (via menu "...")
- [x] Auto-refresh after each response completes

### Attachments
- [x] `sendMessageAdvanced()` with file parts support
- [x] FileAttachment converted to FilePartInput format

### Todos
- [x] `GET /session/{id}/todo` fetches session todos
- [x] Todo viewer bottom sheet (via menu "...")
- [x] Auto-refresh on `todo.updated` SSE event
- [x] Status icons (completed/in_progress/pending)

### Revert / Unrevert
- [x] `POST /session/{id}/revert` with messageID
- [x] `POST /session/{id}/unrevert`
- [x] "Revert changes" in message context menu (long-press)

### Slash Commands
- [x] `/command` intercepted in text input
- [x] `POST /session/{id}/command` execution
- [x] Success/error snackbar feedback

### Session Fork
- [x] `POST /session/{id}/fork` with messageID
- [x] "Fork from here" in message context menu (long-press)
- [x] Navigates to new forked session

### Session Share
- [x] `POST /session/{id}/share` create share link
- [x] `DELETE /session/{id}/share` remove share link
- [x] Accessible via menu "..."

### SSE Event Handling
- [x] session.next.text.delta / ended
- [x] session.next.reasoning.delta / ended
- [x] session.next.tool.input.started / called / success / failed
- [x] session.next.shell.started / ended
- [x] permission.asked / replied
- [x] question.asked / replied / rejected
- [x] message.updated / message.part.updated / message.part.delta
- [x] session.status / session.idle / session.error
- [x] session.created / updated / deleted / compacted / diff
- [x] session.next.step.started / ended / failed
- [x] session.next.agent.switched / model.switched
- [x] session.next.compaction.started / delta / ended
- [x] todo.updated
- [x] file.edited / file.watcher.updated
- [x] server.connected / disconnected
- [x] error

### Voice (STT)
- [x] Android MethodChannel speech recognition
- [x] Voice FAB with visual states
- [x] Speech-to-text → send message

### Connectivity
- [x] Heartbeat monitoring (30s timeout)
- [x] Auto-reconnect with exponential backoff
- [x] Connection status indicator in AppBar
- [x] History rehydration on reconnect

### Settings
- [x] Server URL, username, password configuration
- [x] Connection test before save
- [x] SecureStorage persistence

### History Rehydration
- [x] Text messages from server
- [x] Tool calls parsed from `type: tool` parts
- [x] Reasoning merged from tool-only messages
- [x] Answered questions from local SecureStorage
- [x] Timestamps preserved

---

## Test Guide

### Pre-requisites

1. ADB tunnel to the OpenCode server:
   ```bash
   adb reverse tcp:4096 tcp:4096
   ```

2. OpenCode server running:
   ```bash
   OPENCODE_SERVER_PASSWORD=pai-mobile opencode serve
   ```

3. App installed on device:
   ```bash
   cd mobile-app/apps/flutter
   flutter build apk --debug
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

### Test Cases

#### 1. Stop Button (Abort)
1. Open a session and send a message that will generate a long response (e.g. "Explique em detalhes a história completa da computação")
2. **Verify**: A "Stop" button appears below the chat during streaming
3. Tap "Stop"
4. **Verify**: Generation stops, Stop button disappears, message shows what was generated so far

#### 2. Error Banner
1. Stop the OpenCode server while a session is open
2. Send a message
3. **Verify**: A red error banner appears at the top with a "Dismiss" button
4. Tap "Dismiss"
5. **Verify**: Banner disappears

#### 3. Model Picker
1. Open a chat session
2. Tap the "..." menu in the AppBar → "Change Model"
3. **Verify**: Bottom sheet shows list of available models from the server
4. Select a model
5. **Verify**: AppBar subtitle shows the selected model with "(override)"
6. Send a message
7. **Verify**: Response uses the selected model (check session info)
8. Open model picker again → select "Default (server)"
9. **Verify**: Override is removed

#### 4. Session Info
1. Open a session that has received at least one response
2. Tap "..." → "Session Info"
3. **Verify**: Bottom sheet shows Model, Provider, Agent, Cost, Tokens, ID

#### 5. Todos
1. Open a session and ask the agent to create a todo list (e.g. "Crie uma lista de tarefas para um projeto web")
2. Tap "..." → "View Todos"
3. **Verify**: Bottom sheet shows the task list with status icons (pending/in_progress/completed)

#### 6. Slash Commands
1. In the chat input, type `/compact` and tap send
2. **Verify**: Snackbar shows "Command /compact executed" (or error if not applicable)
3. Type `/help` and send
4. **Verify**: Command executes or shows meaningful error

#### 7. Message Context Menu (Revert / Fork)
1. Open a session where the agent made file changes
2. Long-press on an assistant message
3. **Verify**: Bottom sheet shows "Copy", "Revert changes", "Fork from here"
4. Tap "Fork from here"
5. **Verify**: New session is created, app navigates to it
6. Go back, long-press another message → "Revert changes"
7. **Verify**: Snackbar shows "Reverted" or "Revert failed"

#### 8. Share Session
1. Open a session
2. Tap "..." → "Share Session"
3. **Verify**: Snackbar shows share confirmation
4. Open "Session Info" to see the share link

#### 9. Tool Calls with Status Indicators
1. Ask the agent to perform tasks that use tools (e.g. "Rode o comando pwd e depois ls")
2. **Verify**: Tool calls appear inline with ⏳ while running, ✓ when completed
3. **Verify**: Bash commands show `$ pwd ✓` format

#### 10. Rehydration
1. Open a session with previous tool calls and responses
2. Force-close the app (`adb shell am force-stop com.example.pai_mobile_flutter`)
3. Reopen the app and navigate to the same session
4. **Verify**: Tool calls, text, reasoning, and answered questions are all rendered correctly

#### 11. Permission & Question Flow
1. Trigger a permission request (agent needs to write/execute something)
2. **Verify**: Permission card appears with Deny / Once / Always
3. Reply to permission
4. **Verify**: Agent continues, no extra bubbles
5. Trigger a question (agent needs to ask user for input)
6. **Verify**: Question card appears, answer is inline in markdown after answering

#### 12. Connectivity
1. Break the ADB tunnel: `adb reverse --remove tcp:4096`
2. **Verify**: Connection indicator turns red/orange
3. Restore tunnel: `adb reverse tcp:4096 tcp:4096`
4. **Verify**: Auto-reconnects, indicator turns green
5. **Verify**: History is rehydrated

#### 13. Voice Input
1. Tap the microphone FAB
2. Grant microphone permission if prompted
3. Speak a message
4. **Verify**: Text appears in input field and is sent

#### 14. Settings
1. Go to Settings (gear icon on session list)
2. Change server URL to invalid
3. Tap "Test Connection"
4. **Verify**: Error feedback
5. Restore correct URL → Test → Save
6. **Verify**: Returns to session list

### Quick Smoke Test (all features in 5 minutes)

1. Open app → session list loads ✓
2. Create new chat → chat screen opens ✓
3. Send "rode pwd" → tool call shows `$ pwd ✓`, response appears ✓
4. Stop button appears during streaming ✓
5. Long-press assistant message → Copy/Revert/Fork menu ✓
6. "..." menu → Session Info → shows model and ID ✓
7. "..." menu → Change Model → model list appears ✓
8. Type `/help` → slash command feedback ✓
9. Back to session list → session appears with title ✓
10. Force-close and reopen → rehydration works ✓
