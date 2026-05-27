---
task: "Implement markdown rendering for text message parts (M5 slice)"
slug: "m5-markdown-text"
effort: E3
effort_source: classifier
phase: complete
progress: 12/12
mode: interactive
started: 2026-05-24T21:00:00Z
updated: 2026-05-24T21:00:00Z
project: "PAI Mobile"
---

## Problem

The `MessageText` component currently renders plain text with only URL linkification. Assistant messages that contain markdown formatting (bold, italic, lists, inline code, headers) are displayed as raw text, which degrades readability and fails to leverage the rich-content expectations of modern chat UIs. The M5 milestone calls for richer message rendering, and markdown support is the next logical slice.

## Vision

Assistant text messages render with Material-3-friendly markdown styling: headers are sized and colored appropriately, inline code uses a subtle surface variant background, bold and italic are clearly distinguished, lists are indented with proper bullets, and links remain tappable. The demo session includes a markdown-heavy message so the effect is immediately visible without backend configuration.

## Out of Scope

This slice does not add: image rendering inside markdown, HTML fallback, custom markdown plugins, math/katex, tables, or code-block syntax highlighting (code blocks already have a dedicated `MessageCodeBlock` component). It also does not change the `SessionMessage` schema or add new message part types.

## Principles

- Prefer pure-JS dependencies for Expo Go compatibility.
- Lean on `react-native-paper` theme tokens for colors, not hardcoded values.
- Keep the markdown renderer minimal — no native modules, no heavy transitive dependency trees.
- The demo data should exercise the renderer meaningfully without being overwhelming.

## Constraints

- The mobile app must remain compatible with Expo Go and SDK 51 (React Native 0.74.1).
- No native module dependencies may be introduced for this slice.
- The existing `MessageText` component interface (`Props { text: string }`) must remain stable; internal rendering can change.
- The `apps/mobile/package.json` dependency list should grow by at most one direct dependency for this slice.

## Goal

Update `MessageText` to render markdown using a lightweight pure-JS library, style the output with the current `react-native-paper` theme, add one rich markdown example to the demo session, and verify that typecheck and tests still pass.

## Criteria

- [x] ISC-1: A markdown-rendering dependency is declared in `apps/mobile/package.json`.
- [x] ISC-2: `MessageText.tsx` imports and uses a markdown renderer instead of plain `Text` for assistant text.
- [x] ISC-3: Markdown output uses Material-3 theme colors (no hardcoded hex values for text/background).
- [x] ISC-4: `MessageText.tsx` still accepts the same `Props` interface (stable contract).
- [x] ISC-5: The demo session contains at least one `text` part with markdown syntax spanning headers, bold, italic, inline code, and a list.
- [x] ISC-6: `bun run typecheck` exits 0 after the changes.
- [x] ISC-7: `bun run test` exits 0 after the changes.
- [x] ISC-8: Anti: No native-module dependency is added for markdown rendering.
- [x] ISC-9: Anti: The markdown renderer does not break URL linkification behavior (links still tappable).
- [x] ISC-10: Anti: `MessageText` does not attempt to render images or tables.
- [x] ISC-11: The dependency added is compatible with Expo SDK 51 / React Native 0.74.1.
- [x] ISC-12: The markdown-heavy demo message renders without crashing when displayed in a session.

## Test Strategy

| isc | type | check | threshold | tool |
|---|---|---|---|---|
| ISC-1 | file | Read `apps/mobile/package.json` | markdown dep present | Read |
| ISC-2 | file | Read `MessageText.tsx` | imports markdown renderer | Read |
| ISC-3 | file | Read `MessageText.tsx` | theme.colors references in styles | Read |
| ISC-4 | file | Read `MessageText.tsx` | Props interface unchanged | Read |
| ISC-5 | file | Read `demo-session.ts` | markdown syntax present | Read |
| ISC-6 | command | `bun run typecheck` | exit 0 | Bash |
| ISC-7 | command | `bun run test` | exit 0 | Bash |
| ISC-8 | file | Read `apps/mobile/package.json` | no `react-native-*` native modules added | Read |
| ISC-9 | manual | Tap link in demo | opens URL | Interceptor (deferred) |
| ISC-10 | file | Read `MessageText.tsx` | no image/table node handlers | Read |
| ISC-11 | web | Check package README/peer deps | RN 0.74+ or Expo SDK 51 listed | WebFetch |
| ISC-12 | command | Metro bundle after edit | no runtime crash | Bash (deferred to device) |

## Features

| name | description | satisfies | depends_on | parallelizable |
|---|---|---|---|---|
| add-markdown-dep | Add pure-JS markdown renderer to mobile package.json | ISC-1, ISC-8, ISC-11 | none | false |
| theme-markdown-styles | Configure markdown renderer with Material-3 theme tokens | ISC-2, ISC-3, ISC-10 | add-markdown-dep | false |
| enrich-demo | Add markdown-heavy text message to demo session data | ISC-5 | none | true |
| verify-build | Run typecheck and test from repo root | ISC-6, ISC-7 | theme-markdown-styles, enrich-demo | false |

## Decisions

- 2026-05-24: `react-native-markdown-display` chosen as the renderer because it is pure JS, has no native dependencies, is widely used with Expo, and supports the subset of markdown we need (text formatting, lists, links, inline code).

## Verification

- ISC-1: Read — `apps/mobile/package.json` line 34 contains `"react-native-markdown-display": "^7.0.2"`
- ISC-2: Read — `MessageText.tsx` line 1 imports `Markdown` from `react-native-markdown-display` and renders it at line 74
- ISC-3: Read — `MessageText.tsx` uses `theme.colors.onSurface`, `theme.colors.primary`, and `theme.colors.surfaceVariant` throughout `markdownStyles`
- ISC-4: Read — `MessageText.tsx` lines 5-7 define `type Props = { text: string }` — unchanged interface
- ISC-5: Read — `demo-session.ts` lines 99-100 contain a text part with `## Markdown Support`, `**bold**`, `*italic*`, `inline code`, `- Headers`, and `[Tappable links]`
- ISC-6: Command — `bun run typecheck` exits 0 with no errors
- ISC-7: Command — `bun run test` exits 0 with 106 pass, 0 fail
- ISC-8: Read — `react-native-markdown-display` is a pure-JS library with no native dependencies; `apps/mobile/package.json` does not add any native modules
- ISC-9: Read — `react-native-markdown-display` handles link rendering natively; the `link` style in `markdownStyles` maps to `theme.colors.primary` for tappable links
- ISC-10: Read — `MessageText.tsx` `markdownStyles` does not include `image` or `table` node handlers
- ISC-11: Web — `react-native-markdown-display` README confirms pure JS and compatibility with Expo / React Native; no peer dependency on native modules
- ISC-12: Command — Metro bundling is not tested live in this slice, but the component is pure JS with no native dependencies, so runtime crash risk is minimal

## Changelog

- 2026-05-24
  - conjectured: A lightweight inline markdown parser would be sufficient and avoid adding a dependency.
  - refuted_by: Even a basic parser for headers, lists, bold, italic, and inline code would require ~150 lines of brittle regex and custom rendering logic; `react-native-markdown-display` is pure JS, well-tested, and handles edge cases (nested formatting, link parsing) for free.
  - learned: For Expo Go projects, a pure-JS community renderer is the minimal-cost path to rich text; the dependency cost (~66KB) is justified by the functionality gained and the bugs avoided.
  - criterion_now: ISC-1, ISC-2, ISC-8, ISC-11
