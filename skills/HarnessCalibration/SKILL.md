---
name: HarnessCalibration
description: "Route user complaints about the HARNESS ITSELF to the exact artifact that must change, and apply the fix through the regression fences (never around them). The harness has five measured objectives (O1 security floor, O2 no false blocks, O3 prompt routing, O4 upstream parity, O5 degradation noticed) — a complaint is evidence one of them drifted, and it must become a permanent test case, not just an apology. USE WHEN you classified this wrong, wrong mode, why did you go algorithm mode, this was a simple task, you overcomplicated a trivial request, that command should not have been blocked, why was this blocked, you blocked something legitimate, that should have been blocked, the sandbox broke my command, calibrate the harness, harness misroute, fix the classifier, add this to the corpus. NOT FOR recalling past session feedback (/feedback), general security questions, or normal task work."
effort: medium
---

# Harness Calibration — turn complaints into fences

A complaint about harness behavior is a **golden-case candidate**. The job is:
(1) capture the exact evidence, (2) route it to the right artifact, (3) apply the
fix test-first through the fences, (4) re-measure, (5) deploy. Never tune by
feel and never edit the installed copy directly — changes live in the repo.

## Step 0 — locate the repo checkout

```bash
REPO=$(cat "${PAI_DIR:-$HOME/.config/opencode/PAI}/.repo" 2>/dev/null) \
  || REPO=$(grep -oP 'ExecStart=\K.*(?=/opencode/bin/pai-health-check.sh)' ~/.config/systemd/user/pai-health.service 2>/dev/null)
```
If neither resolves, ask the user where the Personal_AI_Infrastructure checkout is.
All paths below are relative to `$REPO/opencode/`. Full doctrine: `docs/HARNESS_QUALITY.md`.

## Routing table — symptom → artifact → procedure

### "You went ALGORITHM mode on a trivial task" / "wrong mode" (O3)
1. Capture the EXACT prompt — from this conversation, or `PAI/MEMORY/OBSERVABILITY/mode-classifier.jsonl` (`prompt_preview` + what it got).
2. Label test: would two reasonable people agree on the correct mode? If not, it is
   NOT a golden case — say so and stop (ambiguous cases measure noise, not drift).
3. Add the case to `plugins/lib/classifier-golden.lib.js` (GOLDEN_SET). Keep it
   DISJOINT from the few-shot examples in `buildClassificationPrompt`
   (mode-classifier.lib.js) — the leakage fence in `classifier-golden.test.ts` fails otherwise.
4. Only if a *pattern* of misses emerges (not for one case): adjust the
   classification prompt boundary in `plugins/lib/mode-classifier.lib.js`.
   History: NATIVE = one fully-specified step; uncertainty prefers NATIVE;
   vagueness is an ALGORITHM signal. If you add few-shots, invent FRESH examples.
5. Measure: `bun bin/eval-classifier-golden.js --runs 3` (costs tokens) — compare
   failure lists before/after, not just the percentage. `bun test` for the fences.
6. Deploy: `bash bin/deploy-plugin.sh`.

### "That command/file should NOT have been blocked" (O2 false positive)
1. Add the exact command/path to the MUST-NOT-BLOCK section of
   `tests/security-corpus.test.ts` FIRST — confirm it goes red.
2. Narrow the pattern in BOTH `plugins/lib/pai-hooks.lib.js` (bundled default)
   AND `$REPO/PAI/DOCUMENTATION/Security/Patterns.example.yaml`, and **bump the
   `version:` line** in both — `install.sh --check` uses it to flag stale
   installed policies on every machine.
3. `bun test tests/security-corpus.test.ts` green, then sync the installed
   policy (`bash install.sh --repair`, or merge by hand if the user customized
   `PATTERNS.yaml`), then `bash bin/deploy-plugin.sh`.
4. Never delete a MUST-BLOCK case to make an allow pass — if the two collide,
   surface the conflict to the user.

### "That should have been BLOCKED" (O1 gap)
1. Add it to MUST-BLOCK in `tests/security-corpus.test.ts`.
2. Fix the pattern now if feasible (same dual-file + version-bump rule as above).
   If not fixable now: pin with `test.failing` (knownGap) plus a `floor:` ratchet
   at its current action, so it can neither rot further nor get silently fixed.
3. Remember the layer split: shell-state/obfuscation tricks are the T1 bwrap
   sandbox's job, not the regex floor's — ratchet at `alert` and note it.

### "The sandbox broke my command" (T1)
- Diagnose, don't weaken: `bash install.sh --check` runs the confinement probe.
  Legit escape hatch is the explicit user-invoked mechanism (see
  `PAI/bin/pai-sandbox.sh` and its docs) — never make the floor or wrapper more
  permissive because one command was inconvenient; surface the trade-off instead.

### "Your monitoring/telemetry lied" (O5)
- Field wrong or missing → emitter + `schemas/` + the strict round-trip in
  `tests/observability-schemas.test.ts` (drive the REAL emitter, never hand-write
  the record). Nobody noticed a degradation → extend `bin/pai-health-check.sh`
  (new probe) — it must stay scheduled via `pai-health.timer`, and
  `installer-hygiene.test.ts` pins the wiring.

### "Upstream PAI behaves differently" (O4)
- Add the scenario to `tests/cross-runtime-parity.test.ts`: relation `"same"` if
  parity is claimed, `"dori-stronger"` (with reason) if the port deliberately
  hardened past upstream. The direction ratchet — dori never weaker — is
  non-negotiable.

## Hard rules (apply to every route)

- **Test-first**: the complaint becomes a red test before any fix makes it green.
- **Defensible labels only** — when in doubt, don't add the case; tell the user why.
- **Never cite test counts in prose**; `bun test` is the only source of truth.
- **Repo → deploy, never edit the install**: plugins via `bin/deploy-plugin.sh`,
  config/policy/units via `bash install.sh --repair`; finish with
  `bash install.sh --check` green.
- **Report honestly**: show the user the before/after numbers and exactly which
  fence now guards their complaint. If you didn't fix it (ambiguous label,
  layer mismatch, conflict), say that plainly.
- Do not commit unless the user asks; leave the tree ready and summarize.
