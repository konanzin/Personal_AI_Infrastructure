---
task: "Slice 1.1 — Add SSE lifecycle and send/fallback path observability"
slug: mobile-app-slice1.1-observability
effort: E5
effort_source: explicit
phase: complete
progress: 24/24
mode: ALGORITHM
started: 2026-05-26T00:00:00Z
updated: 2026-05-26T00:00:00Z
project: mobile-app
---

## Problem

Dynamic Samsung test with prompt `hi` produced ONLY the `[PAI_MOBILE_TRACE] RENDER | session-screen:last-assistant` log. No SSE, mapper, or store logs appeared, meaning we cannot determine whether live SSE events are reaching the JS screen at all. Slice 1 added mapper/store/render traces but did not instrument the subscription lifecycle or the send/fallback path.

## Vision

A single `adb logcat` run during the Samsung `hi` repro reveals the exact path every SSE frame takes from fetch → reader → buildOpenCodeEvent → screen handler → store, and the exact send/fallback timer decisions. If events are silently dropped, the log shows where. If events never arrive, the log shows the transport state.

## Out of Scope

- Fixing any behavioral bug (this is instrumentation only; fixes deferred to Slice 1.2)
- Adding permanent metrics or analytics
- Changing the SSE transport implementation
- Changing the message mapping logic
- Adding new UI components or changing MessageBubble
- Optimistic UI changes

## Principles

- Temporary instrumentation must be easy to disable (single boolean flip)
- Logs must be compact; never dump full payloads
- Reuse existing `[PAI_MOBILE_TRACE]` logger and conventions
- Instrumentation must not alter control flow

## Constraints

- `bun run typecheck` and `bun run test` must pass
- Existing legacy message tests must not regress
- `subscribeToEvents` signature unchanged
- Demo session behavior unchanged
- Only console.log instrumentation — no state changes

## Goal

Add targeted `[PAI_MOBILE_TRACE]` logging at four boundaries: session-screen SSE lifecycle, client transport fetch/reader lifecycle, send/fallback timer lifecycle, and screen mount identity, so the next Samsung repro reveals whether live events reach the JS layer.

## Criteria

- [x] ISC-1: Session screen logs when SSE effect starts subscription attempt
- [x] ISC-2: Session screen logs config/baseUrl/sessionId summary at subscribe time
- [x] ISC-3: Session screen logs when `subscribeToEvents()` returns subscription object
- [x] ISC-4: Session screen logs when cleanup runs/unsubscribe happens
- [x] ISC-5: Session screen logs when appState gate prevents subscription
- [x] ISC-6: Session screen logs when demo/config/id guard prevents subscription
- [x] ISC-7: Client transport logs fetch start to /event
- [x] ISC-8: Client transport logs response status
- [x] ISC-9: Client transport logs connected event emitted
- [x] ISC-10: Client transport logs each raw SSE event frame completion before `buildOpenCodeEvent` (compact summary)
- [x] ISC-11: Client transport logs reader done
- [x] ISC-12: Client transport logs caught error (AbortError vs non-AbortError)
- [x] ISC-13: Client transport logs disconnected emitted in finally
- [x] ISC-14: Send path logs `handleSend` called with sessionId/textLen/isDemo/sseConnected/isAwaitingReply
- [x] ISC-15: Send path logs `send()` start/success/failure
- [x] ISC-16: Send path logs when fallback timer is scheduled
- [x] ISC-17: Send path logs when fallback timer fires
- [x] ISC-18: Send path logs when fallback timer is cancelled/cleared
- [x] ISC-19: Screen logs active id, isDemoSession, config present, sseConnected, connectionState on mount
- [x] ISC-20: Screen logs the same identity tuple when `id` changes
- [x] ISC-21: `bun run typecheck` passes with zero errors
- [x] ISC-22: `bun run test` passes all tests
- [x] ISC-23: Anti: no full payload dumps in any log line
- [x] ISC-24: Anti: no control flow changes beyond console.log

## Test Strategy

| ISC | Type | Check | Tool |
|-----|------|-------|------|
| 1-6 | inspection | Trace calls present in `[id].tsx` SSE effect | code review + grep |
| 7-13 | inspection | Trace calls present in `index.ts` subscribeToEvents | code review + grep |
| 14-18 | inspection | Trace calls present in `[id].tsx` handleSend and timer | code review + grep |
| 19-20 | inspection | Trace calls present in `[id].tsx` mount/useEffect | code review + grep |
| 21 | static | TypeScript strict mode | bun run typecheck |
| 22 | unit | Full suite green | bun run test |
| 23-24 | inspection | No payload dumps, no control flow changes | code review |

## Features

| Name | Description | Satisfies | Depends on | Parallelizable |
|------|-------------|-----------|------------|----------------|
| sse-lifecycle-logs | Add logs to session screen SSE effect | ISC-1..6, ISC-19..20 | — | no |
| transport-lifecycle-logs | Add logs to subscribeToEvents fetch/reader | ISC-7..13 | — | no |
| send-fallback-logs | Add logs to handleSend and fallback timer | ISC-14..18 | — | no |
| validation | Typecheck + test pass | ISC-21..22 | all above | no |

## Decisions

- 2026-05-26: Used direct `logTransport` in client package rather than importing `mobileTrace` to avoid cross-package dependency. Both use identical `[PAI_MOBILE_TRACE]` prefix.
- 2026-05-26: Identity effect uses `// eslint-disable-next-line react-hooks/exhaustive-deps` to avoid logging on every render (config object is recreated each render).
- 2026-05-26: Store `send` logs placed directly in `message-store.ts` rather than wrapping in `handleSend`, ensuring `send:start/success/failure` captures the actual async boundary.

## Verification

ISC-1: `session-screen:sse-effect-start` log present at top of SSE effect in `[id].tsx:142`. Verified by grep.
ISC-2: `session-screen:sse-subscribe` logs config.baseUrl and username at subscribe time in `[id].tsx:167`. Verified by grep.
ISC-3: `session-screen:sse-subscribed` logs after `subscribeToEvents()` returns in `[id].tsx:311`. Verified by grep.
ISC-4: `session-screen:sse-cleanup` logs in effect cleanup in `[id].tsx:314`. Verified by grep.
ISC-5: `session-screen:sse-appstate-block` logs when appState gate prevents subscription in `[id].tsx:160`. Verified by grep.
ISC-6: `session-screen:sse-guard-block` logs when demo/config/id guard prevents subscription in `[id].tsx:150`. Verified by grep.
ISC-7: `transport:fetch-start` log present in `subscribeToEvents` before fetch in `index.ts:994`. Verified by grep.
ISC-8: `transport:response-status` logs status and ok flag in `index.ts:1004`. Verified by grep.
ISC-9: `transport:connected` log emitted before `onEvent({ type: 'connected' })` in `index.ts:1011`. Verified by grep.
ISC-10: `transport:frame` logs each raw SSE event frame with event name and data length before `buildOpenCodeEvent` in `index.ts:1043` and `index.ts:1064`. Verified by grep.
ISC-11: `transport:reader-done` log present when reader.read() returns done in `index.ts:1031`. Verified by grep.
ISC-12: `transport:error` logs `isAbort`, `name`, and `message` in catch block in `index.ts:1070`. Verified by grep.
ISC-13: `transport:disconnected` log present in finally block in `index.ts:1075`. Verified by grep.
ISC-14: `session-screen:handleSend` logs sessionId, textLen, isDemo, sseConnected, isAwaitingReply, isSending in `[id].tsx:449`. Verified by grep.
ISC-15: `store:send:start`, `store:send:success`, `store:send:failure` logs present in `message-store.ts:92,113,117`. Verified by grep.
ISC-16: `session-screen:fallback-schedule` logs delayMs when timer scheduled in `[id].tsx:511`. Verified by grep.
ISC-17: `session-screen:fallback-fire` logs when timer callback executes in `[id].tsx:513`. Verified by grep.
ISC-18: `session-screen:fallback-cancel` logs on reschedule (`[id].tsx:508`) and unmount (`[id].tsx:526`). Verified by grep.
ISC-19: `session-screen:identity` logs on mount with id, isDemoSession, configPresent, sseConnected, connectionState in `[id].tsx:347`. Verified by grep.
ISC-20: Same identity effect triggers when `id` changes (dependency array is `[id]`). Verified by code review.
ISC-21: `bun run typecheck` passes with zero errors. Verified by command execution.
ISC-22: `bun run test` passes 221/221 tests across 6 files. Verified by command execution.
ISC-23: All logs use compact summaries (dataLen, partCount, textLen) — no full payload dumps. Verified by code review.
ISC-24: No control flow changes beyond console.log — all `if` branches, returns, and state updates preserved. Verified by diff review.

## Changelog

- 2026-05-26: Conjectured that adding `config` to the identity effect dependency array would keep logs fresh. Refuted by: `buildConfig` returns a new object every render, causing infinite log spam. Learned: object identity from inline function calls is not stable for effect deps. Criterion now: never put inline-built objects in effect dependency arrays for telemetry.
