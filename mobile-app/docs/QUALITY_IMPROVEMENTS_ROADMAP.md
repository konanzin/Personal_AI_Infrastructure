# Mobile App: Quality Improvements Roadmap

Updated: 2026-06-13

## Status (2026-06-13)

Phases 1–4 executed. `flutter analyze` clean; 154 tests passing
(was 57 pre-roadmap, 116 after the first roadmap pass). Honest deltas from the original plan:

- **Phase 2 manual pass** (switch machine mid-stream / kill mid-question on
  the device) still pending — needs the physical device.
- **Phase 3 reducer**: extracted the pure parsing layer
  (`sse_payload_parsing.dart`, fixture-tested) rather than a full
  command-pattern reducer; the state machine stays in the provider
  (~1.8k lines, down from ~2.0k). `chat_screen.dart` is ~1.55k lines (target
  was ~700) — autocomplete, formatting, bootstrap and terminal transport
  were extracted; what remains is mostly build methods. Q&A extraction
  (item 5) not done.
- **Phase 4 i18n**: infra + daily surfaces (chat, input, drawer, sessions,
  settings, lock, workspace/machine pickers, permission/question cards,
  welcome) are in ARB (PT template + EN). Still English-only: machines
  editor, providers screen, terminal screen, events screen (debug),
  bootstrap step labels, and date formatting helpers ("Yesterday", month
  names — should move to `intl` `DateFormat`).
- **Phase 4 lock-screen cancel-vs-failure**: not distinguishable via
  `local_auth` return value; dropped.

## Scope

This roadmap covers code-quality, robustness, UX, and Material 3 alignment work
for the Flutter app in `mobile-app/apps/flutter`. It complements (does not
replace) the feature direction in `REMOTE_MACHINES_AND_WORKSPACES_ROADMAP.md`
and the architecture in `MOBILE_REMOTE_DA_ARCHITECTURE.md`.

Source: full-codebase audit performed 2026-06-10 (services, providers, UI,
tests, Android config).

## Product Decisions Reflected Here

1. **Distribution is personal/sideload for the foreseeable future.** Play
   Store blockers (`applicationId`, release signing) are parked in the
   backlog, not scheduled.
2. **i18n is wanted** (PT-BR + EN via `flutter_localizations` + ARB).
3. **`flutter_ai_toolkit` has been removed.** The app now owns the former
   interface types (`ChatMessage`, `MessageOrigin`, `Attachment`,
   `FileAttachment`) in `lib/models/chat_message.dart`; `LlmProvider` and the
   unused Firebase tree are gone. `js` 0.6.7 still appears as a transitive dep
   of `flutter_secure_storage` 9.x and goes away with the 9→10 upgrade already
   in the backlog.
4. **Material 3 alignment is a goal.** The foundation is already M3
   (`useMaterial3: true`, tonal surface-container roles, 180 `colorScheme.*`
   usages, `FilledButton`, seeded light theme). The work is alignment, not
   migration.
5. **No GitHub CI.** Verification stays local: a check script plus an
   optional git pre-push hook instead of GitHub Actions.

6. **Seed-generated tonal palettes, user-selectable.** (Decided 2026-06-10,
   superseding the earlier "keep OLED-black" lean.) Both light and dark
   themes move to `ColorScheme.fromSeed` with tonal elevation enabled.
   Theme source cascade:

   ```text
   dynamic color (wallpaper)   — if the user enables it
     > user-selected seed      — color picker in Settings, persisted
       > app default seed
   (+ an orthogonal "pure black (OLED)" toggle that overrides dark surfaces)
   ```

   The hand-built OLED-black palette in `theme.dart` is retired as the
   architecture and survives only as the optional pure-black toggle.

---

## Phase 1 — Foundation (cheap, protects everything after it)

**Goal:** automated verification exists; dead/risky dependencies and one-line
security fixes are done.

1. **Local check script** — `scripts/check.sh` running `flutter analyze` +
   `flutter test`, wired as an optional git pre-push hook. `analyze` is
   currently clean, so this is nearly free. (GitHub CI explicitly not wanted.)
2. **Remove `flutter_ai_toolkit`** — create own `ChatMessage`/`Attachment`
   models in `lib/models/` (~80 lines), update the 3 importing files
   (`opencode_provider.dart`, `chat_screen.dart`, `chat_message_tile.dart`),
   drop `extends LlmProvider` (`opencode_provider.dart:51`). Removes the
   discontinued Firebase tree from the lockfile. (Done — note: `js` 0.6.7
   remains as a transitive dep of `flutter_secure_storage` 9.x; it goes away
   with the 9→10 upgrade already in the backlog.)
3. **Small targeted fixes:**
   - ~~3-strike counter increments before the biometric prompt~~ — audit
     false positive. The pre-increment is deliberate
     (`ssh_gate_service.dart:89-90`): without it, force-killing mid-prompt
     would reset the budget. The wipe itself only fires on an explicit
     failed authentication, never from force-kills alone. No change needed.
   - Cleartext restriction: Android's `network_security_config` cannot
     express IP ranges, and the app's normal transport is
     `http://<tailnet-ip>`. Enforced in Dart instead:
     `lib/services/network_policy.dart` blocks plain HTTP/WS to non-private
     hosts at machine save/test and at client build (`client_provider.dart`).
     Manifest keeps cleartext enabled with a comment pointing at the policy.
   - Cap the unbounded event list in `events_screen.dart` (keep last 200).
   - ~~Mask `Authorization` headers in request logging~~ — verified: no code
     path logs headers or credentials today. Preventive only; keep in mind
     when adding logging.

**Exit criteria:** `scripts/check.sh` passes and is documented in the README;
`firebase_vertexai` gone from `pubspec.lock`; the fixes merged with tests
where applicable.

---

## Phase 2 — Concurrency & lifecycle correctness (today's real bugs)

**Goal:** machine/session switching, reconnects, and app kills never corrupt
chat state.

1. **Serialize SSE teardown/setup.** `subscribeToEvents()`
   (`opencode_client.dart:361`) starts a new connection without awaiting
   `unsubscribe()`; `switchSession()` (`opencode_provider.dart:174`) cancels
   non-blockingly and clears buffers while posts may be in flight;
   `_rebuildClient()` (`client_provider.dart:68-89`) swaps the client before
   closing the old one. Fix pattern: await teardown before setup, and tag
   events with the (machineId, sessionId) identity of the stream that
   produced them, dropping mismatches.
2. **Orphan-message fix.** `sendMessageStream()`
   (`opencode_provider.dart:918-939`) appends the LLM placeholder to history
   before the stream starts; on immediate failure an empty bubble remains.
3. **SSH session leak.** `execute()` (`ssh_service.dart:85-117`) skips
   `session.close()` if a stdout/stderr future throws — wrap in
   `try/finally`.
4. **Lifecycle observer leak check.** Verify `_lifecycleObserver` removal and
   no `notifyListeners()` after dispose in `OpenCodeProvider`.
5. **Tests for the riskiest untested state:**
   - `machine_store.dart` — CRUD + legacy credential/defaultDirectory
     migrations (data-loss risk).
   - `connectivity_service.dart` — backoff, jitter, retry ceiling.
   - `client_provider.dart` — rebuild semantics.

**Exit criteria:** a scripted "switch machine mid-stream / kill app
mid-question / reconnect storm" manual pass shows no duplicated, orphaned, or
cross-session messages; new tests cover the three modules above.

---

## Phase 3 — Structure (pay down the two god objects)

**Goal:** the code that breaks most often (SSE protocol handling) is a pure,
tested unit; screens stop holding business logic.

1. **Extract the SSE event reducer.** Move ~500 lines of event
   parsing/reconciliation (`opencode_provider.dart:1017-1508` plus the
   `_extract*` helpers) into a pure `SseEventReducer` service: events in,
   state-mutation commands out. This is the seam most exposed to OpenCode
   API evolution — make it unit-testable with recorded fixtures.
2. **Split `chat_screen.dart` (~1.7k lines)** into ChatScreen (layout),
   autocomplete widget, in-chat search widget, and a view-model for
   formatting helpers (`_guessMime`, token/path formatting).
3. **Extract SSH bootstrap from `machines_screen.dart`** (key provisioning,
   controller install, HTTP wait loop, lines ~292-500) into a
   `MachineBootstrapService` that reports progress as a stream of steps —
   this directly feeds the Phase 4 progress dialog.
4. **Extract PTY/SSH terminal connection logic from `terminal_screen.dart`**
   (WebSocket connect/resume/fallback, lines ~86-387) into a
   `TerminalConnectionService`.
5. **Q&A/permission protocol handling** out of `OpenCodeProvider` into a
   dedicated class (pending questions, persistence of answered questions).

**Exit criteria:** `opencode_provider.dart` and `chat_screen.dart` each under
~700 lines; `SseEventReducer` has fixture-based tests covering every event
type the app handles.

---

## Phase 4 — M3 alignment, i18n, UX polish (one sweep, after the split)

**Goal:** every screen touched exactly once for theming + strings + feedback
states. Deliberately scheduled after Phase 3 so the sweep hits small files,
not god objects.

1. **Seed-based theming (decision 6).** Rework `AppTheme` so light/dark are
   built from a seed via `ColorScheme.fromSeed` (remove the
   `surfaceTintColor: transparent` overrides — tonal elevation on). Add to
   Settings: seed color picker with live preview (persisted in
   `SettingsProvider`, same pattern as `themeMode`), a `dynamic_color`
   toggle (wallpaper colors, takes precedence over the seed), and a "pure
   black (OLED)" toggle overriding dark surfaces. Because `MaterialApp`
   already listens to `SettingsProvider`, changes apply live. This replaces
   the earlier throwaway "theme lab" idea with a permanent feature.
2. **Theme extension with semantic roles.** Add a `ThemeExtension` providing
   `success`, `warning`, `diffAdded`, `diffRemoved`, terminal accent colors —
   *derived from / harmonized with the active seed* (`Color.harmonize` from
   `material_color_utilities`) so user seeds and wallpaper colors never clash
   with the semantic greens/oranges/reds. Eliminate the 62 hardcoded
   `Colors.*` usages (worst offenders: `events_screen` 14,
   `shell_command_bubble` 10, `machines_screen` 10, `file_diff_card` 8,
   `connection_status_indicator` 8). This also makes the light theme
   actually usable.
3. **Component-theme consolidation.** Single `BaseCard`/shape scale for the
   three near-duplicate card styles (permission/question/tool-call), M3 type
   scale for the custom `TextTheme`, consistent radii via theme.
4. **i18n.** `flutter_localizations` + ARB files, PT-BR as template + EN.
   Today's strings are a PT/EN mix ("Peça ao PAI..." vs "Permission
   Required") — the sweep normalizes everything.
5. **Feedback states:**
   - Progress dialog for SSH bootstrap (driven by the Phase 3
     `MachineBootstrapService` step stream — "generating key… installing
     service… waiting for HTTP, attempt 3/10").
   - Keys on chat/sessions/events `ListView`s (`chat_screen.dart:1426` etc.).
   - Specific error/empty states (network vs server vs empty) on sessions
     and chat; distinguish cancel vs failure on the lock screen.
6. **Optional:** `NavigationDrawer` migration.

**Exit criteria:** zero raw `Colors.*` outside the theme layer; all
user-facing strings in ARB; light and dark themes both fully usable and
seed-driven (picker + dynamic color + OLED toggle working); SSH bootstrap
shows step-level progress.

---

## Backlog (intentionally unscheduled)

- **Play Store readiness:** real `applicationId` (note: the voice
  `MethodChannel` name in `MainActivity.kt:15` hardcodes the package and must
  change in lockstep), release keystore + signing config. Do this *before*
  accumulating on-device data that an ID change would orphan, if distribution
  plans change.
- Persist in-flight UI state (`_isStreaming`, pending questions/permissions,
  running tool calls) so an app kill mid-task rehydrates honestly instead of
  desyncing until next reload.
- Widget tests for the top screens; accessibility (Semantics labels,
  live-region announcements for tool-call status).
- Harden `shellEscape` in `git_status_service.dart` (currently only safe
  inside single quotes) or validate workspace paths at input time.
- API-version header / capability probe against OpenCode to fail loudly on
  protocol drift instead of silently dropping unknown events.
- Stricter lint set (`avoid_print`, `always_declare_return_types`, …).
- Dependency refresh wave: `flutter_secure_storage` 9→10,
  `permission_handler` 11→12, `record` 6→7, `flutter_markdown` →
  `flutter_markdown_plus`.

## Sequencing Rationale

- The check script first because it is nearly free and guards every later
  phase.
- Concurrency fixes before refactors: they are the bugs felt in daily use,
  and refactoring untested concurrent code without automated checks is how
  regressions ship.
- Structure before the M3/i18n sweep: touching strings and colors across two
  2k-line files and then splitting them means doing the sweep twice.
- M3 + i18n together: both are "visit every screen once" passes.
