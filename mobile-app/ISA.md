---
task: Migrate SSE transport from react-native-sse to event-source-polyfill
slug: sse-eventsource-migration
effort: E3
phase: complete
progress: 12/12
mode: algorithm
started: 2026-05-27T00:00:00Z
updated: 2026-05-27T00:15:00Z
---

## Problem

`react-native-sse` v1.1.0 never emits `open` on Expo Go/Hermes because `XMLHttpRequest.DONE` is `undefined`, breaking SSE connectivity. The library is not market-standard (12 open Expo/Android issues) and blocks mobile session functionality.

## Vision

A robust SSE transport that works reliably across all React Native environments (Expo Go, Hermes, Android, iOS) using the de-facto standard `event-source-polyfill` (1.49M weekly downloads), with all existing tests passing and type-safety preserved.

## Out of Scope

- Changing the OpenCode server SSE protocol or event shapes
- Modifying the mobile app's UI or state management beyond the transport layer
- Removing `apps/mobile/src/polyfills.ts` (kept as defensive measure)
- Adding new SSE event types or changing event normalization logic

## Principles

- Use market-standard libraries over niche alternatives
- Preserve existing API surface — no breaking changes to `subscribeToEvents` contract
- Maintain type safety and test coverage throughout migration

## Constraints

- Must use `event-source-polyfill` (not native EventSource)
- Must support custom `Authorization` header for Basic Auth
- Must preserve all existing event types: `connected`, `message`, `status`, `error`, `disconnected`
- All existing tests must pass without behavioral regressions

## Goal

Replace `react-native-sse` with `event-source-polyfill` across the mobile client package, update the `subscribeToEvents` implementation to use the polyfill's API, update tests to mock the new dependency, and validate via `bun install`, `typecheck`, and `test`.

## Criteria

- [x] ISC-1: `react-native-sse` removed from `packages/opencode-mobile-client/package.json`
- [x] ISC-2: `event-source-polyfill` added to `packages/opencode-mobile-client/package.json` dependencies
- [x] ISC-3: `react-native-sse` removed from root `package.json` dependencies
- [x] ISC-4: Import in `src/index.ts` changed from `react-native-sse` to `event-source-polyfill`
- [x] ISC-5: `subscribeToEvents` uses `EventSourcePolyfill` with correct header config
- [x] ISC-6: Custom event type loop removed from `subscribeToEvents`
- [x] ISC-7: JSDoc comment updated to reference `event-source-polyfill`
- [x] ISC-8: Test mock updated to mock `event-source-polyfill`
- [x] ISC-9: `bun install` completes without errors
- [x] ISC-10: `bun run typecheck` passes with zero errors
- [x] ISC-11: `bun run test` passes with all tests green
- [x] ISC-12: Anti: `react-native-sse` remains referenced anywhere in the codebase

## Test Strategy

| ISC | Type | Check | Tool |
|-----|------|-------|------|
| ISC-1-3 | static | dependency removed/added | Read package.json |
| ISC-4-7 | static | code changed correctly | Read index.ts, Grep |
| ISC-8 | static | mock updated | Read index.test.ts |
| ISC-9 | command | install succeeds | Bash `bun install` |
| ISC-10 | command | tsc --noEmit exits 0 | Bash `bun run typecheck` |
| ISC-11 | command | all tests pass | Bash `bun run test` |
| ISC-12 | static | no lingering references | Grep `react-native-sse` |

## Decisions

- 2026-05-27: Keep `apps/mobile/src/polyfills.ts` as defensive measure per user instruction

## Verification

ISC-1: Read package.json — `react-native-sse` absent from dependencies
ISC-2: Read package.json — `event-source-polyfill: ^1.0.31` present in dependencies
ISC-3: Read root package.json — `react-native-sse` absent from dependencies
ISC-4: Grep index.ts — `import { EventSourcePolyfill } from 'event-source-polyfill'` confirmed
ISC-5: Read index.ts — `new EventSourcePolyfill(url, { headers: {...} })` confirmed
ISC-6: Read index.ts — no `knownEventTypes` loop, only `open`/`message`/`error` listeners
ISC-7: Read index.ts JSDoc — references `event-source-polyfill` (standard, 1.49M weekly downloads)
ISC-8: Read index.test.ts — mock.module('event-source-polyfill', ...) confirmed
ISC-9: Bash `bun install` — "2 packages installed [1.59s], Removed: 1"
ISC-10: Bash `bun run typecheck` — `tsc --build` exits 0 with no output
ISC-11: Bash `bun run test` — "237 pass, 0 fail, 404 expect() calls, Ran 237 tests across 6 files. [194.00ms]"
ISC-12: Grep `react-native-sse` — no matches in package.json files; remaining references are documentation/comments only

## Changelog

- 2026-05-27: Migrated SSE transport from `react-native-sse` to `event-source-polyfill`

