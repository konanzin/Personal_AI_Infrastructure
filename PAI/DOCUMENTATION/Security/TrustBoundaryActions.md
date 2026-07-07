# PAI OpenCode Trust-Boundary Actions

This is the compact contract for how the OpenCode harness treats tool actions at trust boundaries. Prose in an agent prompt explains intent; frontmatter permissions and the security policy carry authority.

| Action | Risk / leverage | Default handling | Examples |
|---|---:|---|---|
| `allow` | Low risk, local, reversible | Run without asking after normal tool validation | Read repo source, grep docs, edit project tests, run scoped `bun test` |
| `ask` | Medium risk or ambiguous leverage | Ask before proceeding; user intent can authorize it | External-directory reads outside the repo, writes to credentials-adjacent config, deploy/publish/push class commands |
| `deny` | High risk, credential exposure, irreversible blast radius | Block and log; do not ask the model to decide | Private keys, `.env` secrets, OpenCode/Claude/GitHub token stores, installed `PAI_CONFIG.yaml`, catastrophic deletes |
| `escalate` | High leverage but sometimes legitimate | Route to deterministic owner or human approval; no LLM-only release | Arthur credential decisions, corrupt security-policy repair, publishing/deploying, policy version drift |

## Agent boundaries

- Read-only and auditor agents declare `edit: deny` or `edit: ask` in frontmatter; prose-only "read-only" claims are not a boundary.
- Custodian agents may narrate deterministic policy engines, but they do not invent credential state or release secrets.
- Helper-wrapper producers such as Anvil declare `edit: deny` and scope privileged bash to their progress helpers so code flows through the audited external engine they claim to use.
- Every agent in these roles declares `task: deny` unless its job is explicitly to coordinate other agents.

## Policy boundaries

- `PATTERNS.yaml` path tiers are the installed policy contract; `Patterns.example.yaml` and the bundled default must share the same version whenever path rules change.
- The deny floor separates CREDENTIALS from PERSONAL CONTEXT (policy 3.4, Principal's decision 2026-07-06). Credential stores (auth tokens, `PAI_CONFIG.yaml`) stay denied — their legitimate use never requires the model to read them raw. Personal context (`CONTACTS`, `FINANCES`, `HEALTH`, `BUSINESS`, `OUR_STORY`, `voice.env`) is readable: a Life OS assistant that cannot know its Principal is capped where it matters most; what it does with that context is governed by the Principal's prompts, and the egress/secret-content floors still catch anything key-shaped leaving.
- Machine workflow config such as `USER/Config/classifier.json` and `voice.env` (edge-tts voice names, no secrets) stays outside the deny floor; secret-bearing config such as `PAI_CONFIG.yaml` stays denied.
- Security alerts are not "done" when written; `monitor-security-events.ts` is the scheduled consumer that turns bursty alert/block activity into health-check warnings.

## Risk/leverage action matrix

| Action class | Before | After | Risk | Leverage | Boundary |
|---|---|---|---:|---:|---|
| Read repo/project source | Allowed by normal tool permissions | Still allowed | Low | High | `allow` |
| Grep/glob/list docs and code | Allowed | Still allowed | Low | High | `allow` |
| Edit project files/tests | Allowed under project roots | Still allowed; verified by tests/diff | Medium | High | `allow` |
| Run local tests/typechecks | Bash allowed by default | Still allowed under deny floor + sandbox | Low | High | `allow` |
| Anvil helper execution | Prose said helper-only, but permissions did not enforce it | `edit: deny`, `task: deny`, bash scoped to helper/prereq commands | Medium | High | `allow` only through helper |
| Research agents | Prose said research-only/read-only | `edit: deny`, `task: deny`, `webfetch/websearch: allow`, bash asks | Medium | Medium | `allow` read/web, `ask` bash |
| Cato/Arthur auditor/custodian | Prose said read-only/custodian | `edit: deny`, `task: deny`, bash scoped to deterministic helper | High | Medium | scoped `allow`, otherwise `deny` |
| Credential reads | Some stores were reachable by Read despite bash sandbox masking | OpenCode/Claude/GitHub auth stores and `PAI_CONFIG.yaml` are `zeroAccess`; personal-context stores readable since 3.4 | Critical | Low | `deny` (credentials only) |
| Non-secret machine config | Broad `USER/Config/**` deny would have broken `/classifier` | `classifier.json` remains allowed; secret-bearing config denied | Medium | High | `allow` for known non-secret config |
| Publish/deploy/push commands | Mostly normal bash allow plus audit on some destructive variants | Template asks on exact `git push`, release/publish/deploy, external-message CLIs | High | Medium | `ask` |
| Recursive local cleanup | Alert tier logs and runs | Still logs and runs; burst monitor consumes alerts | Medium | High | `alert` + health consumer |
| Catastrophic deletion | Deny floor catches canonical dangerous forms | Still denied with corpus coverage | Critical | None | `deny` |
| Security-policy/template drift | Install check already detected stale policy versions | Version sync test plus install drift check remain gates | High | High | `escalate` |

## Authority leaks closed

- Prose-only read-only agents now have frontmatter permissions; future prose-boundary agents fail `agent-permissions.test.ts` if permission metadata is missing.
- Raw installed credential stores now deny through `zeroAccess`: OpenCode auth, Claude credentials, GitHub CLI token store, and the PAI credential config. (Personal-context stores were denied in 3.3 and deliberately re-opened in 3.4 — see Policy boundaries above.)
- Helper-wrapper code agents no longer have direct edit authority; their code path is the helper they claim to use.
- Publish/deploy/social-code-host mutation commands now ask through the rendered OpenCode bash permission template.
- Security alert telemetry now has a scheduled consumer, not just a JSONL sink.

## Fear-based withholding removed

- Local tests, typechecks, source reads, and project edits remain allow-by-default because they are reversible, observable, and high leverage.
- Dotenv templates and non-secret classifier config stay readable/writable; only secret-bearing config is denied.
- Recursive cleanup of scoped local build artifacts remains alert-and-run rather than deny/ask.
