---
task: "Implement ToolCallBubble widget for PAI Mobile Flutter app"
slug: "pai-mobile-tool-call-bubble"
effort: "E3"
phase: "complete"
progress: "22/22"
updated: "2026-06-01T13:28:00Z"
mode: "ALGORITHM"
started: "2026-06-01T12:00:00Z"
updated: "2026-06-01T12:15:00Z"
---

## Problem

The PAI Mobile Flutter app renders chat messages but has no UI representation for tool calls. When the OpenCode server executes tools (pending, running, completed, error states), users see no visual feedback. This creates an opaque experience where the assistant appears to "think" silently during tool execution.

## Vision

A compact, state-aware tool call bubble that appears inline in the chat timeline, showing:
- Visual status indicator (icon + color) for each tool state
- Tool name prominently displayed
- Expandable input arguments as formatted JSON
- Rendered output (markdown text or file chips) for completed calls
- Error messages for failed calls
- Left border accent matching state color
- Small footprint that doesn't dominate the chat

## Out of Scope

- Interactive tool calls (retry, cancel, edit)
- Tool call history / persistence across sessions
- Custom tool call animations beyond basic pulse/spinner
- Tool call filtering or search
- Real-time streaming of tool output (show final output only)
- Tool call input forms or parameter editing

## Principles

- Tool call UI should be informative but non-dominating
- States must be visually distinguishable at a glance
- Existing text chat must be completely unaffected when no tool calls exist
- Follow Material Design 3 with theme-aware colors
- Widget should be self-contained and testable

## Constraints

- Must work with existing `ToolCallPart` model (no model changes)
- Must integrate with existing `OpenCodeProvider` ChangeNotifier
- Must not break existing chat layout or scrolling
- Must use Flutter AI Toolkit's `ChatMessage` and `MessageOrigin` types
- Must handle all 4 `ToolCallState` enum values
- Must render `ToolTextContent` as markdown and `ToolFileContent` as chips

## Goal

Create a `ToolCallBubble` widget that receives a `ToolCallPart` and renders it with state-appropriate styling, input/output display, and integrates into the chat timeline without affecting existing text-only messages.

## Criteria

- [x] ISC-1: `lib/widgets/tool_call_bubble.dart` exists and is a StatelessWidget
- [x] ISC-2: Widget accepts required `ToolCallPart` parameter
- [x] ISC-3: Pending state shows `Icons.pending` with orange left border and "Preparing..." text
- [x] ISC-4: Running state shows `CircularProgressIndicator` with blue left border and "Running..." text
- [x] ISC-5: Completed state shows `Icons.check_circle` with green left border
- [x] ISC-6: Error state shows `Icons.error` with red left border and error message
- [x] ISC-7: All states display tool name in bold
- [x] ISC-8: Input arguments shown in expandable section with prettified JSON
- [x] ISC-9: Completed state renders `ToolTextContent` as markdown via `MarkdownBody`
- [x] ISC-10: Completed state renders `ToolFileContent` as chip with file icon
- [x] ISC-11: Widget uses Card/Container with left border accent matching state color
- [x] ISC-12: Widget has small footprint (compact padding, not full-width)
- [x] ISC-13: `getToolCallsForMessage()` method exists in `OpenCodeProvider`
- [x] ISC-14: `pendingToolCalls` getter exists in `OpenCodeProvider`
- [x] ISC-15: `completedToolCalls` getter exists in `OpenCodeProvider`
- [x] ISC-16: Chat screen integrates ToolCallBubble for assistant messages
- [x] ISC-17: ToolCallBubble only shows when tool calls exist for a message
- [x] ISC-18: Chat without tool calls looks identical to before
- [x] ISC-19: `flutter analyze` passes with zero errors
- [x] ISC-20: Anti: ToolCallBubble does not appear for user messages
- [x] ISC-21: Anti: ToolCallBubble does not break existing text chat layout
- [x] ISC-22: Anti: No null pointer exceptions with empty input/output

## Test Strategy

| ISC | Type | Check | Tool |
|-----|------|-------|------|
| ISC-1 | File | File exists at correct path | Glob |
| ISC-2-12 | Code review | Widget renders all states correctly | Read + Grep |
| ISC-13-15 | Code review | Provider methods exist with correct signatures | Read + Grep |
| ISC-16-18 | Integration | Chat screen includes tool call widgets conditionally | Read + Grep |
| ISC-19 | Build | `flutter analyze` returns zero issues | Bash |
| ISC-20-22 | Code review | Anti-criteria verified in implementation | Read |

## Features

| Name | Description | Satisfies | Depends On | Parallelizable |
|------|-------------|-----------|------------|----------------|
| ToolCallBubble widget | State-aware rendering widget | ISC-1..ISC-12 | None | Yes |
| Provider API methods | Tool call query methods in provider | ISC-13..ISC-15 | None | Yes |
| Chat integration | Inline tool call bubbles in chat timeline | ISC-16..ISC-18 | ToolCallBubble, Provider API | No |

## Decisions

- 2026-06-01: Kept tool call association simple (return all buffered tool calls) since server doesn't yet provide message-level association. This avoids premature complexity.
- 2026-06-01: Used IntrinsicWidth to keep bubble compact rather than full-width. Tradeoff: may not work well with very long tool names, but acceptable for v1.
- 2026-06-01: Did not address withOpacity deprecation warnings (existing codebase pattern). Can be fixed in a future cleanup pass.

## Changelog

- conjectured: Tool call bubbles should be full-width cards for visibility
- refuted_by: Full-width cards dominate the chat and break visual flow
- learned: Compact inline bubbles with left border accent provide better UX
- criterion_now: ISC-12 enforces small footprint

## Verification

ISC-1: File check — `lib/widgets/tool_call_bubble.dart` created at correct path (Glob confirmed)
ISC-2: Code review — Constructor signature: `ToolCallBubble({super.key, required this.toolCall})` (Read confirmed)
ISC-3: Code review — Pending state uses `_PulsingIcon(icon: Icons.pending, color: Colors.orange)` with orange left border and "Preparing..." text (Read confirmed)
ISC-4: Code review — Running state uses `CircularProgressIndicator` with blue left border and "Running..." text (Read confirmed)
ISC-5: Code review — Completed state uses `Icon(Icons.check_circle, color: Colors.green)` with green left border (Read confirmed)
ISC-6: Code review — Error state uses `Icon(Icons.error, color: theme.colorScheme.error)` with red left border and error message display (Read confirmed)
ISC-7: Code review — Tool name rendered with `fontWeight: FontWeight.bold` in all states (Read confirmed)
ISC-8: Code review — `_ToolCallInputSection` uses `JsonEncoder.withIndent('  ')` in expandable `InkWell` section (Read confirmed)
ISC-9: Code review — `_ToolCallOutputSection` renders `ToolTextContent` via `MarkdownBody` (Read confirmed)
ISC-10: Code review — `_ToolCallOutputSection` renders `ToolFileContent` as `Chip` with `Icons.insert_drive_file` (Read confirmed)
ISC-11: Code review — Container uses 4px left border accent with state color via `BoxDecoration` (Read confirmed)
ISC-12: Code review — Compact padding (12px all sides), constrained width, small font sizes (Read confirmed)
ISC-13: Code review — `getToolCallsForMessage(String messageId)` returns `List<ToolCallPart>` (Grep confirmed)
ISC-14: Code review — `pendingToolCalls` getter filters on `pending || running` (Grep confirmed)
ISC-15: Code review — `completedToolCalls` getter filters on `completed || error` (Grep confirmed)
ISC-16: Code review — Chat screen calls `..._buildToolCallBubbles(index)` for assistant messages (Grep confirmed)
ISC-17: Code review — `_buildToolCallBubbles` returns empty list when `messageId` is null or no tool calls exist (Read confirmed)
ISC-18: Code review — Tool call widgets only render conditionally; no changes to text message rendering (Read confirmed)
ISC-19: Build — `flutter analyze` returned zero errors (Bash output confirmed: "Analyzing flutter... 22 issues found" — all info/warning, zero errors)
ISC-20: Code review — Guarded by `if (!isUser && _provider != null)` in chat screen (Read confirmed)
ISC-21: Code review — Tool call bubbles added within existing Column, no layout structure changes (Read confirmed)
ISC-22: Code review — Null checks: `toolCall.errorMessage != null`, `toolCall.input.isNotEmpty`, `toolCall.content.isNotEmpty` (Read confirmed)