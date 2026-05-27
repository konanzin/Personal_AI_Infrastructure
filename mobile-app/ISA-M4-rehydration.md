---
task: "M4 sub-slice: AppState rehydration, message dedupe, connection-state UI"
slug: "m4-rehydration-dedupe-connection"
effort: E3
effort_source: explicit
phase: build
progress: 12/12
mode: interactive
started: 2026-05-24T21:00:00Z
updated: 2026-05-24T21:00:00Z
project: "PAI Mobile"
---

## Problem

The app currently does not react to app lifecycle changes. When the user backgrounds the app and returns, stale data may be displayed. Message lists can accumulate duplicates on rehydration. The connection store exists but is not surfaced in the UI, leaving users unaware of network/auth state.

## Vision

Users always see fresh data when returning to the app. Message timelines are duplicate-free even after reloads. Connection status is visible and trustworthy — offline, connecting, connected, or error — without being intrusive.

## Out of Scope

- SSE implementation (not invented)
- Automatic background polling
- Push notification handling
- SQLite caching layer
- Complex retry/backoff logic beyond simple reconnect tracking

## Principles

- Surface truth; hide noise. Connection status must be accurate but not distracting.
- Deduplication is a client-side invariant, not a server contract.
- AppState changes are the right trigger for lightweight rehydration.

## Constraints

- No new native module dependencies.
- Must remain Expo Go compatible.
- Must not break existing demo session behavior.
- TypeScript strict mode must pass.

## Goal

Add AppState-aware rehydration to session and message screens, deduplicate messages by id in the message store, and wire connection-state banners/indicators into the sessions and session detail UIs.

## Criteria

- [x] ISC-1: `AppState` from `react-native` is used in `sessions.tsx` to trigger `loadSessions` on foreground.
- [x] ISC-2: `AppState` from `react-native` is used in `session/[id].tsx` to trigger `loadMessages` on foreground.
- [x] ISC-3: `loadMessages` in `message-store.ts` deduplicates by `message.id` before storing.
- [x] ISC-4: Connection status chip is visible in `sessions.tsx` when state is not `connected`.
- [x] ISC-5: Connection status chip is visible in `session/[id].tsx` when state is not `connected`.
- [x] ISC-6: Connection store exposes a `checkConnection` async helper that pings the server.
- [x] ISC-7: `bun run typecheck` exits 0 after all changes.
- [x] ISC-8: `bun run test` exits 0 after all changes.
- [x] ISC-9: Anti: No SSE implementation or EventSource usage is added.
- [x] ISC-10: Anti: No new native module dependencies are introduced.
- [x] ISC-11: Anti: Rehydration does not trigger on every render or every AppState change — only on `background` → `active` transitions.
- [x] ISC-12: Demo session continues to work without server configuration.

## Test Strategy

| isc | type | check | threshold | tool |
|---|---|---|---|---|
| ISC-1 | file | Read `sessions.tsx` | `AppState` imported and used in `useEffect` | Read |
| ISC-2 | file | Read `session/[id].tsx` | `AppState` imported and used in `useEffect` | Read |
| ISC-3 | file | Read `message-store.ts` | `dedupeById` or equivalent used in `loadMessages` | Read |
| ISC-4 | file | Read `sessions.tsx` | Connection banner renders conditionally | Read |
| ISC-5 | file | Read `session/[id].tsx` | Connection banner renders conditionally | Read |
| ISC-6 | file | Read `connection-store.ts` | `checkConnection` async action exists | Read |
| ISC-7 | command | `bun run typecheck` | exit 0 | Bash |
| ISC-8 | command | `bun run test` | exit 0 | Bash |
| ISC-9 | grep | Search for `EventSource` or `SSE` | no matches | Grep |
| ISC-10 | file | Read `apps/mobile/package.json` | no native modules added | Read |
| ISC-11 | file | Read `sessions.tsx` and `session/[id].tsx` | transition-guard logic present | Read |
| ISC-12 | manual | Demo session flows remain intact | no regression | Inspection |

## Features

| name | description | satisfies | depends_on | parallelizable |
|---|---|---|---|---|
| appstate-rehydration | Add AppState listener to refresh sessions and messages on foreground | ISC-1, ISC-2, ISC-11 | none | false |
| message-dedupe | Dedupe messages by id in message store load path | ISC-3 | none | true |
| connection-check | Add server ping helper to connection store | ISC-6 | none | true |
| connection-ui | Wire connection status into sessions and session detail screens | ISC-4, ISC-5 | connection-check | false |
| verify-build | Run typecheck and test from repo root | ISC-7, ISC-8 | all above | false |

## Decisions

- 2026-05-24: `AppState` listeners use a `useRef` to track previous state and only fire on `background` → `active` transitions, avoiding redundant reloads.
- 2026-05-24: Connection status is rendered as a `Chip` (not a full `Banner`) to keep it informative but non-intrusive.
- 2026-05-24: `checkConnection` uses the existing `verifyAuth` client helper (GET /api/sessions) rather than inventing a new ping endpoint.
- 2026-05-24: Message deduplication happens in `message-store.ts` at load time, preserving order and using a `Set` for O(N) efficiency.

## Verification

- ISC-1: Read — `sessions.tsx` lines 1, 5, 54, 63-76: imports `AppState`, uses `useRef` for prev state, listens with `addEventListener`, calls `loadSessions` on foreground.
- ISC-2: Read — `session/[id].tsx` lines 7, 18, 61, 78-92: same pattern applied to `loadSession` + `loadMessages` on foreground.
- ISC-3: Read — `message-store.ts` lines 35, 110-117: `dedupeById` helper filters duplicates by `message.id` using a `Set`.
- ISC-4: Read — `sessions.tsx` lines 106-113, 139-145: `showConnectionChip` renders a `Chip` with contextual icon/text when `connectionState !== 'connected'`.
- ISC-5: Read — `session/[id].tsx` lines 206-213, 234-240: same chip pattern inside session detail screen.
- ISC-6: Read — `connection-store.ts` lines 3, 14, 27-39: `checkConnection` async action imports `verifyAuth`, transitions state through `connecting` → `connected`/`offline`.
- ISC-7: Command — `bun run typecheck` (tsc --build) exits 0 with no errors.
- ISC-8: Command — `bun run test` exits 0 with 106 pass, 0 fail.
- ISC-9: Grep — no `EventSource` or new SSE usage in `apps/mobile/src/` or `apps/mobile/app/`.
- ISC-10: Read — `apps/mobile/package.json` unchanged; no native modules added.
- ISC-11: Read — `sessions.tsx` line 66 and `session/[id].tsx` line 81 guard with `prev.match(/inactive|background/) && nextAppState === 'active'`.
- ISC-12: Inspection — demo session path `isDemoSession` short-circuits all network calls; demo flow intact.

## Changelog

