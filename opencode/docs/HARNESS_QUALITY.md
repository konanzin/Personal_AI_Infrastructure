# Harness Quality — what "better" means, and how we catch it getting worse

This is the north-star for the Dori (PAI-on-OpenCode) harness. It exists because
"more green tests" and "higher parity %" are **proxies**, and this harness has a
documented history of a proxy staying green while the real thing was dead
(`b6ec6a8f`: the security floor read the wrong arg field and silently never ran in
production, while every unit test passed). This doc names the real objectives, the
metric that actually measures each, the proxies that have drifted, and the
regression fences that now catch drift before it's felt.

---

## 1. What "better" actually means

The harness has exactly five jobs. Each has a **real objective** (what you care
about) and a **true metric** (what actually measures it). Where the metric we were
watching is only a proxy, that's called out.

| # | Real objective | True metric | Proxy we were watching |
|---|----------------|-------------|------------------------|
| O1 | **Dangerous actions cannot cause harm, in the shape the runtime really delivers.** | Catch-rate over a phrasing-diverse dangerous corpus, asserted *through the hook* under every arg shape. | "N canonical strings deny" as pure-function calls; "hooks present" greps. |
| O2 | **Legitimate work is never blocked.** | False-positive rate over a corpus seeded from *real* command history. | Nothing — this was never measured. |
| O3 | **A prompt is routed to the mode/tier that produces the best answer.** | Classification correctness on the path production actually runs (LLM path, `useLLM=true` by default). | Heuristic-path unit tests + a `<10ms` latency test; the production LLM path had zero behavioral coverage. |
| O4 | **The port behaves like upstream PAI where it claims parity.** | Same input → same observable outcome on both runtimes, executed. | A hand-graded De/Para table + a `~95%` estimate + conflicting test counts. |
| O5 | **Degradation is noticed.** | A consumer reads the signal and a threshold/alert fires. | "We write the JSONL" — streams are emitted and schema-checked but nobody reads them. |

**"Better" = O1 catch-rate up with O2 false-positive-rate flat-or-down; O3 correct on
the production path; O4 verified by execution not by table; O5 signals with a live
consumer.** Anything that moves a proxy in the table's right column without moving
the left column is drift, not improvement.

---

## 2. Proxy-drift register (verified 2026-07-03)

Each row was confirmed by executing the real code, not by reading it. "Fence" is the
test that now turns red if the gap is fixed (so it gets promoted) or if a regression
re-opens it.

### Security floor — content gaps (O1) — **FIXED 2026-07-04**

All four rows below were fixed in the policy (bundled default + `Patterns.example.yaml`
+ the installed user copy, which had gone stale). All 13 `test.failing` fences flipped
red on cue and were promoted to permanent fences; the corpus also gained 11 adversarial
phrasings (sudo, quoting, `bash -c`, split flags) that now deny.

| Was | Fix | Fence |
|-----|-----|-------|
| `rm -rf /*`, `rm -rf /home/*`, `rm -rf ~/*` only **alert** (log + run). | Terminator class now accepts a trailing `*` and closing quotes; `/home/<user>` trees and top-level system dirs (`/etc`, `/usr/*`, …) added. | `security-corpus.test.ts` → MUST-BLOCK bash (permanent). |
| `find / -delete`, `find ~ -delete`, `shred`, `git clean -xfd` all **allow**. | `find -delete` denies when rooted at `/`, `~`, `$HOME`, or a whole home (deeper roots stay legitimate); `shred` denies as a command; `git clean` denies with `-x`+force, and plain force-clean gets a new alert-tier audit line. | `security-corpus.test.ts` → MUST-BLOCK bash (permanent). |
| `/etc/ssl/private/*.key` reads **allow**. | `/etc/ssl/private/**` added to `zeroAccess`. | `security-corpus.test.ts` → MUST-BLOCK read (permanent). |
| `~/.ssh/authorized_keys` write **allow**. | `~/.ssh/authorized_keys*` added to `readOnly` (reads stay legal — the file is public keys; writing it is an SSH backdoor). | `security-corpus.test.ts` → MUST-BLOCK write (permanent). |

**Remaining known gaps (by design of a regex floor):** `cd / && rm -rf .` and
`echo / | xargs rm -rf` — the target lives in shell state/pipes a string inspector
cannot see. Both are ratcheted at their `alert` floor in the corpus; the **T1 bwrap
sandbox is the layer that actually stops them**.

**Drift found while fixing:** the installed `PATTERNS.yaml` was a *stale* copy of the
template (predated the miner/reverse-shell adds) — `install.sh` seeds it only when
absent, so template improvements never reach existing installs. **Fenced same day:**
the policy `version:` line is now the drift signal (`3.2-opencode`; bump it in
`Patterns.example.yaml` + the bundled default whenever patterns change) and
`install.sh --check` fails with "Security policy STALE" when the installed version
differs from the template's — customized installs keep their edits and merge.
Red-path pinned in `installer-hygiene.test.ts`; the live install was refreshed
(backup at `PATTERNS.yaml.bak-20260704`).

### Security floor — false positives (O2) — **FIXED 2026-07-04**

| Was | Fix | Fence |
|-----|-----|-------|
| `cat app.env.example`, `cat foo.env`, `grep KEY .env.sample`, `cat myapp.env` all **deny**. | Pattern narrowed: the token must *start* a path segment with `.env`, and template suffixes (`.example`/`.sample`/`.template`/`.dist`) are exempt. Real dotenv files (`.env`, `.env.local`, `config/.env.production`) still deny. | `security-corpus.test.ts` → MUST-NOT-BLOCK bash (permanent), which now asserts O2 precisely: `deny`/`require_approval` fail, `alert` passes (it logs and runs). |
| The `.env` fix only covered the *bash* guard — the Read/Write path tier still zero-accessed `**/.env.*`, so `Read .env.sample` stayed blocked while the docs said templates pass (caught in review). | Path globs now support `!` exemptions; zeroAccess exempts `.env` template suffixes, matching the bash guard. The corruption guard counts only non-exemption entries. **Scope (second review round):** the first implementation nullified the whole tier on an exemption match, so `/etc/ssl/private/.env.example` escaped `/etc/ssl/private/**` — a template-*named* file inside a protected dir bypassed zeroAccess. Exemptions now pierce only FLOATING (`**/`-prefixed) globs; directory-anchored protections are absolute. | `security-corpus.test.ts` → MUST-BLOCK/MUST-NOT-BLOCK read: `.env`/`.env.production` deny, templates pass, **and** `/etc/ssl/private/.env.example` + `~/.gnupg/sub/.env.example` deny (anti-bypass fences). |
| `git clean -n -xfd` (dry-run preview) **denied** — the new `-x`+force deny didn't exempt `-n`/`--dry-run` (caught in review). | Deny pattern exempts `-n`/`--dry-run` up front; previews land on the force-clean alert tier (log + run). | `security-corpus.test.ts` → MUST-NOT-BLOCK bash: three dry-run variants. |

### Fail-direction (O1)

| Drift | Reality | Fence |
|-------|---------|-------|
| An unexpected exception inside an inspector **fails open** — the command runs. | The outer `catch` in `tool.execute.before` (pai-hooks.js ~1340) re-throws only messages containing a `*BLOCKED` token; anything else is logged and swallowed. | `floor-liveness.test.ts` → "Fail-direction on inspector crash": a **real fault-injection** `test.failing` — a throwing getter on `args.command` raises a non-`BLOCKED` error inside the hook; today the hook does not reject (fail-open, documented) and the test flips red the moment the catch is hardened to fail closed. |
| `require_approval` on the bash path is dead code but telemetry logs "Prompted for approval". | `inspectBashCommand`/`inspectEgress` never return `require_approval` (no bash confirm tier by doctrine), so the branch is unreachable; the misleading log line only matters if a future inspector starts returning it. | Documented; no fence (unreachable today). Re-open O5 if a confirm tier is added. |

### Sandbox liveness (O1)

| Drift | Reality | Mitigation |
|-------|---------|------------|
| T1 bwrap sandbox **fails open silently** when bwrap is absent or args arrive on `input.args`. | Wrap is gated on `output?.args && shouldSandboxCommand && sandboxAvailable`; a missing bwrap (e.g. the A51/S24 mobile rigs) means every command runs unconfined with no log line saying so. | **Closed at install time:** `install.sh` now bootstraps `bubblewrap` across apt/pacman/dnf/zypper/apk, and `verify_sandbox` runs a real confinement probe post-install (write to `$HOME` from `/tmp` must be refused) and prints a `T1 sandbox:` status. `--check` **re-runs the real confinement probe** (not just presence), so a present-but-degraded bwrap — e.g. user namespaces disabled — is caught too; `PAI_SANDBOX=off` reports it as an operator override. `installer-hygiene.test.ts` pins the wiring. The deny-floor still fires regardless, so this remains defence-in-depth. |

### Classifier (O3)

| Drift | Reality | Mitigation |
|-------|---------|------------|
| Production runs the **LLM classifier** (`useLLM` defaults `true`), but only the heuristic/timeout escape hatches are tested. | A drift in `opencode run --pure` output format would make `parseLLMResponse` silently downgrade every prompt to heuristic/fail-safe. | **Monitored (2026-07-03):** `bin/monitor-classifier-health.js` reads `mode-classifier.jsonl` and returns ok/warn/alert on the share that degraded off the LLM path (exit 0/1/2 for cron/CI). Intent is resolved **per event** (`use_llm` recorded on each row — by both the main and fail-safe emitters — and **required** by the schema, so the round-trip goes red if an emitter ever drops it; the analyzer still tolerates its absence on legacy rows) so a later config change can't retroactively mislabel history. Required two telemetry-honesty fixes below. |
| The monitor proves the LLM path is *alive*; nothing proved it is *right*. "Share on intended path" is itself a proxy for O3 — a model swap classifying everything ALGORITHM-E3 would look healthy. | **Measured (2026-07-04):** `bin/eval-classifier-golden.js` + `plugins/lib/classifier-golden.lib.js` drive a golden set through `classifyPromptWithLLM` — the function production calls. On-demand (costs tokens); exit 0/1/2. **Hardened same day:** set expanded 22 → 50 cases mined from *real* `mode-classifier.jsonl` usage (bilingual PT-BR/EN — real traffic is, the original set wasn't), and `--runs N` majority-vote added so one nondeterministic sample can't flap the status (ties break toward escalation, i.e. against us; the classifier's 5-min LRU is bypassed via `noCache` or repeats would replay run 1). `classifier-golden.test.ts` pins set shape + scorer + `aggregateRuns` and prints a free heuristic baseline every `bun test`. | **Before → after (both at `--runs 3`, `openai/gpt-5.4-mini-fast`):** the original prompt scored **78% mode (39/50), WARN** — all 11 failures the same class, trivial fully-specified edits → ALGORITHM-E1, in both languages, only 1/50 flaky (systematic, not noise; the prompt literally defined NATIVE as lookups-only and said "when uncertain → ALGORITHM E3"). Prompt fixed 2026-07-04: NATIVE includes one fully-specified steps, uncertainty between NATIVE/ALGORITHM prefers NATIVE (escalation is recoverable; ceremony is a guaranteed tax — the *error* fail-safe stays ALGORITHM E3), few-shots added. Re-measured: **98% mode (49/50) / 100% tier → OK**, zero regression on the ALGORITHM cases. **Second review round (same day):** the fix's few-shot examples overlapped the golden set — some verbatim — so those cases graded copying, not classifying (train/test leakage: this project's own thesis reappearing inside its own tooling). Decontaminated (fresh disjoint few-shots), fenced permanently (`classifier-golden.test.ts` rebuilds the instructions and fails if any golden prompt reappears in them), and 6 **escalation-risk probes** added (short vague imperatives — "fix the login bug", "o build tá quebrado, arruma" — that must stay ALGORITHM, measuring the under-escalation side the NATIVE bias could introduce). Honest re-measurement on the clean 56-case set: **98.2% mode (55/56) / 100% tier → OK, 0 flaky, all probes passed** — the improvement was the policy, not the leakage, and now that's proven rather than assumed. Sole miss: one genuinely borderline PT-BR case. Re-run after any classifier/model/prompt change. |

### Observability (O5)

| Drift | Reality | Mitigation |
|-------|---------|------------|
| `security-events.jsonl`, `mode-classifier.jsonl`, `agent-guard.jsonl`, `skill-guard.jsonl`, `subagent-trace.jsonl`, `session-events.jsonl` are **write-only**. | No runtime process reads them; no threshold, no alert. Low-satisfaction ratings write a LEARNING file that only ever gets line-counted. Schema tests validate hand-written literals, not emitter output. | **Consumers built:** `mode-classifier.jsonl` feeds `monitor-classifier-health.js`; the low-rating archive feeds `recall-feedback.js` / `/feedback` (on-demand, read-only); all six streams round-trip through a strict emitter-vs-schema test (§4.3) so field drift fails a test. **Scheduled (2026-07-04):** `bin/pai-health-check.sh` runs daily via `pai-health.timer` (systemd user timer, installed + enabled by `install.sh`, presence fenced by `--check` and `installer-hygiene.test.ts`): classifier health + install drift, `notify-send` on warn/alert, audit trail in `MEMORY/OBSERVABILITY/health-check.jsonl` — "did anyone look?" is now itself logged. Remaining gap: no alerting on security/guard *bursts* (`security-events.jsonl` still has no threshold consumer). |

### Telemetry honesty (O5) — fixed 2026-07-03 while building the classifier monitor

| Was | Reality | Fix |
|-----|---------|-----|
| `fallback` recorded as `source === 'fail-safe'` only. | When the LLM path *threw*, the code fell back to the heuristic (`source:'heuristic'`) and logged `fallback:false` — so the flag meant to signal "the classifier degraded" stayed false on the most common degradation. A lying proxy. | `pai-hooks.js`: `fallback` now also true when `useLLM && source === 'heuristic'`. |
| Meta-commands (`/status`, `/voice`, …) logged as `source:'fail-safe'`. | `classifyPaiMetaCommand` returns `source:'command'`, but `normalizeClassification`'s `validSources` omitted `'command'`, coercing every legit meta-command to `fail-safe` — inflating any failure-rate signal with normal config traffic. | `mode-classifier.lib.js`: added `'command'` to `validSources`. |

### Reporting integrity (O4)

| Drift | Reality | Mitigation |
|-------|---------|------------|
| Docs cite `137` / `232` / `257` / `234` / `226` / `200` / `162` tests as proof of quality. | **None match** what `bun test` reports. | Treat `bun test` output as the only source of truth; stop hardcoding counts in prose. (An earlier revision of THIS row hardcoded a count as "authoritative" — it went stale within a day, proving the point. This doc now cites no number anywhere.) |
| "Parity" = a hand-graded table + `~95%` estimate. | No scenario is executed on both Claude Code PAI and the OpenCode port and compared. The former `hooks-parity.test.ts` was 5 pure-helper unit tests that compare nothing against upstream. | **Renamed** to `hooks-helpers.test.ts` (2026-07-04) so the name stops implying a measurement that doesn't exist. **Executed harness built (2026-07-04):** `cross-runtime-parity.test.ts` extracts main's v5.0.0 `SecurityPipeline.hook.ts` from git, drives it over its real contract (stdin JSON → exit 2/`permissionDecision`), and diffs against the port's inspectors per scenario. First measurement: 4/6 exact agreement; 2 documented divergences where dori is deliberately STRONGER (`authorized_keys` write, `.env` read — the 2026-07-04 floor fixes upstream lacks), each fenced in both directions (dori must deny; when upstream catches up the test goes red → promote to "same") plus a direction ratchet on every scenario (dori never weaker than upstream). Coverage is 6 curated scenarios — grow the table; classifier/session-event parity still unexecuted. |

---

## 3. Regression fences (run these)

```bash
cd opencode
bun test tests/security-corpus.test.ts   # O1 catch-rate + O2 false-positive-rate, with live scoreboard
bun test tests/floor-liveness.test.ts     # O1 anti-b6ec6a8f: floor fires under BOTH arg shapes, all tools
bun test                                  # full suite — the only authoritative test count
bun bin/eval-classifier-golden.js         # O3 correctness on the PRODUCTION LLM path (on-demand, costs tokens)
bun bin/monitor-classifier-health.js      # O3/O5 liveness of the LLM path from the live stream
```

**How the `knownGap` fences work (self-healing):** a confirmed gap is pinned with
Bun's `test.failing`, so the assertion of *correct* behavior fails today and the
suite stays green (the gap is documented and counted, not hidden). The moment the
floor is fixed, that assertion passes and Bun reports **"marked as failing but it
passed — remove `.failing`"**, forcing whoever fixed it to promote the case into a
permanent fence. **This mechanism fired for real on 2026-07-04**: all 13 pinned gaps
were fixed in the policy, all 13 fences flipped red on cue, and all were promoted to
permanent tests in the same change. But `test.failing` only detects the *fix* — so
each gap that has a better-than-worst state today also carries a **ratchet**: a
normal (non-`failing`) test asserting the action has not dropped below its documented
`floor` (e.g. the remaining shell-state gaps `cd / && rm -rf .` and
`echo / | xargs rm -rf` must stay at least `alert` — if they degrade to `allow`, that
real test goes red now, not silently). Gaps already at rock bottom (`allow`) need no
ratchet. Together the pair catches drift in **both** directions. You cannot silently
improve *or* regress the floor without this file reacting. The scoreboard block
prints catch-rate and false-positive-rate every run so both numbers are visible at a
glance — note the denominator is a **curated corpus**, so the numbers measure coverage
of the listed phrasings, not a statistical rate over all commands. `floor-liveness.test.ts`
covers `bash`/`read`/`write`/`edit`/`multiedit` under both arg shapes — every tool the
real write/read floor routes.

---

## 4. Health checks still to build (close the O5 loop)

These are the gaps a test file can't cover because they're about *noticing at
runtime*, not about a pure function:

1. ~~**Sandbox-active health check**~~ — **DONE (2026-07-03).** `install.sh`
   bootstraps `bubblewrap` and `verify_sandbox` proves confinement post-install with a
   `$HOME`-write probe; `--check` re-asserts it; `installer-hygiene.test.ts` pins the
   wiring. Remaining nice-to-have: a runtime WARN log line the first time a bash
   command runs unwrapped in a session (the install/`--check` gates cover provisioning,
   this would cover mid-session drift).
2. ~~**Classifier fallback-rate monitor**~~ — **DONE (2026-07-03).**
   `bin/monitor-classifier-health.js` + `plugins/lib/classifier-health.lib.js`
   (unit-tested in `classifier-health.test.ts`). Run it on a schedule:
   `bun opencode/bin/monitor-classifier-health.js` (exit 1=warn, 2=alert), e.g. via
   `/loop` or a cron routine. On the live stream it currently reports **WARN** (15%
   fail-safe) — some of which was the meta-command miscoding fixed above, so re-check
   after the next batch of real classifications.
3. ~~**Emitter-vs-schema round-trip**~~ — **DONE (2026-07-03).**
   `observability-schemas.test.ts` now drives the real emitters/hooks in a subprocess
   (`tests/helpers/emit-observability-events.mjs`, PAI_DIR→tmp) and validates the
   on-disk records with a STRICT validator that flags any undeclared key. All six
   streams (security, notification, session, mode_classification, tool_failure,
   subagent_trace) round-trip; guard-the-guard tests prove strict mode catches a
   renamed or dropped field. Schema and emitter can no longer drift silently.
4. ~~**Low-rating loop**~~ — **DONE (2026-07-04), on-demand only.** `bin/recall-feedback.js`
   + `plugins/lib/feedback-recall.lib.js` (tested in `feedback-recall.test.ts`) read the
   low-rating archive back and surface recent comments + recurring themes. Exposed as the
   `/feedback` command. **Deliberately read-only:** it does NOT auto-inject into any prompt
   and never mutates config/rules/memory — feedback influences a session only when you ask
   for it. (We explicitly rejected auto-injection and self-modifying-harness options as
   Goodhart risks; see the git discussion.)

All four O5 loops are now closed — and since 2026-07-04 they have a **scheduled
consumer**: `pai-health.timer` (daily) runs `bin/pai-health-check.sh`, which executes
the classifier health monitor and `install.sh --check`, fires `notify-send` on
warn/alert, and appends every look to `MEMORY/OBSERVABILITY/health-check.jsonl`.
The timer's presence is itself fenced (`--check` fails when it's not scheduled;
wiring pinned in `installer-hygiene.test.ts`) — "runnable but unscheduled" reads
as drift, not as done. The golden eval stays on-demand (it costs tokens); run it
after any classifier/model/prompt change.

Remaining optional hardening: threshold alerting on security/guard *bursts*
(`security-events.jsonl` has a schema fence but no consumer), and a mid-session
"ran unwrapped" WARN line for the sandbox.
