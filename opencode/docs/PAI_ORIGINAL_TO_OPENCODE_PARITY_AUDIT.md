# PAI Original -> OpenCode Port Parity Audit

Data original: 2026-06-14
Ultima atualizacao: 2026-06-15

Baseline auditado:

- Original Claude Code: `origin/main:Releases/v5.0.0/.claude` em `2fde1bbe9e8f280cd4998e244b53e3c66f3dc8b9`.
- Port OpenCode: workspace local atual.
- Branch `master`: nao existe neste repo local; `origin/main` e o baseline disponivel.
- Estado instalado verificado apos `opencode/install.sh --repair`: `~/.config/opencode`.

Validacao atual:

- Repo: `bun test` -> 234/234 (inclui seguranca adversarial/fail-closed e os hooks/tools de paridade).
- Repo docs/promises/tools: doc integrity, promise integrity e tools manifest -> PASS.
- Instalado: 226/226 checks (109 structural + 106 behavioral + 11 E2E).
- `opencode/install.sh --check` -> PASS.

## Legenda

| Status | Sentido |
|---|---|
| Equivalente | Mesmo comportamento observavel ou diferenca irrelevante. |
| Adaptado | Diferente de proposito, mas cobre a intencao no modelo OpenCode. |
| Parcial | Existe uma versao, mas com semantica ou cobertura menor. |
| Ausente | Original tinha runtime; port nao tem equivalente funcional. |
| Fora de escopo | Nao portado por decisao explicita/adequada ao produto atual. |
| Opcional | Helper/superficie existe como necessidade de skill, mas nao e core runtime. |

## Resumo Executivo

O core operacional do port agora esta forte. Mobile/broker/notifications, plugin OpenCode, modo/tier, ISA sync, CheckpointPerISC, tools core, Knowledge read/harvest minimo, install hygiene e validadores estao coerentes e testados.

O port **nao** busca paridade linha-a-linha com o PAI original. A decisao correta foi adaptar o runtime para OpenCode e retirar superficies desktop/Claude-Code-specific: Kitty tabs, MenuBar macOS, PAI-Install GUI, Pulse dashboard completo, KV sync, MCP amplo e grande parte dos 86 tools originais.

Estado dos gaps (a maioria fechada nesta rodada de paridade):

1. **Security policy configuravel** — **RESOLVIDO**: politica externalizada em `PAI/USER/SECURITY/PATTERNS.yaml` (cascata + fail-closed), cobertura restaurada do original v3.1.
2. **Runtime hooks secundarios** — **RESOLVIDO em sua maioria**: SmartApprover (trusted fast-path + cache), DocIntegrity/IntegrityCheck (telemetry fail-soft no session-end), RelationshipMemory (captura + `RelationshipReflect`), TelosSummarySync (`tool.execute.after` + `GenerateTelosSummary`), RepeatDetection (Jaccard), RestoreContext (injecao na compactacao) portados.
3. **Platform-blocked** — `ContextReduction` e `ElicitationHandler` exigem ganchos que o OpenCode nao expoe; nao fechaveis hoje.
4. **ISA skill CLIs** — **nao e gap de paridade**: o ISA original e markdown-only; CLIs seriam extensao nova.
5. **Long-tail tools** — `RemoveBg`/`MigrateScan`/`MigrateApprove`/`GenerateTelosSummary`/`LearningPatternSynthesis`/`RelationshipReflect` agora **implementados**; restam helpers de interview/wisdom sob demanda.
6. **Pulse desktop avancado** — dashboard/VoiceServer/MenuBar/Observability UI permanecem fora de escopo; broker e o caminho atual.

## Inventario De/Para por Superficie

| Superficie | Original Claude Code | Port OpenCode atual | Status | Situacao atual |
|---|---|---|---|---|
| Instalar/configurar | `.claude/install.sh`, `settings.json`, `.mcp.json`, `PAI-Install/` GUI/web/Electron | `opencode/install.sh`, `opencode.jsonc.template`, `install-manifest.json`, repair/check headless | Adaptado | Melhor para OpenCode. GUI original fora de escopo. |
| Runtime root | `~/.claude` | `~/.config/opencode` | Adaptado | Instalador migra paths; promise/doc validators bloqueiam promessas ativas a `.claude`. |
| System prompt | `PAI/PAI_SYSTEM_PROMPT.md` como camada constitucional | `PAI/CLAUDE.md`, `PAI/RUNTIME_CONSTITUTION.md`, `experimental.chat.system.transform` | Adaptado | Sem dependencia ativa de Claude Code. |
| CLAUDE.md | Root `.claude/CLAUDE.md` | `PAI/CLAUDE.md` como instructions OpenCode | Adaptado | Nome herdado, conteudo OpenCode-native. |
| Config de permissao | Claude Code permissions em `settings.json` | OpenCode `permission` config + `permission.ask` + security plugin | Adaptado/parcial | Boa cobertura; sem SmartApprover LLM/cache completo. |
| MCP | `.mcp.json` vazio no baseline | Sem MCP obrigatorio | Equivalente | Nada relevante a portar. |
| Hooks | 69 arquivos em `.claude/hooks` | 1 plugin + libs + event bridge | Adaptado/parcial | Core consolidado; varios hooks secundarios nao portados. |
| Mode/tier | `PromptProcessing.hook.ts` UserPromptSubmit, modelo Sonnet | `chat.message` + `mode-classifier.lib.js`; LLM-first por default; erro vira ALGORITHM E3 fail-safe | Adaptado | Mais proximo do original: classificador externo antes do executor; provider/model configuravel. |
| Algorithm | v6.x com promessas de hooks/tools Claude Code | `LATEST=v6.3.2` OpenCode-coerente | Adaptado/parcial | Core ajustado; ISA skill CLIs ainda nao. |
| ISA state | `ISASync.hook.ts`, kitty/status updates | `syncISAToWorkRegistry()` em `tool.execute.after` | Adaptado | Work registry/headless OK; sem Kitty tab. |
| CheckpointPerISC | Hook TS em PostToolUse, allowlist, sidecar | `recordISCCheckpointsFromISA()` no plugin + `Checkpoint.ts` CLI | Adaptado | Allowlist-only, idempotente, rollback preview-only, testado. |
| Agents | 18 agentes | 15 agentes | Adaptado | BrowserAgent/QATester/UIReviewer removidos por decisao. |
| Skills | 45 dirs | 45 originais + `Lib` | Adaptado/parcial | Diretorios batem; algumas skills dependem de helpers opcionais. |
| Commands | `context-search`, `cs`, `pu` | mesmos + comandos OpenCode (`pai`, `status`, `pulse`, `e1`-`e5`, etc.) | Adaptado | Melhor superficie de comando. |
| PAI/TOOLS | 86 arquivos TS/Python/UI | manifest + 10 tools core + 3 opcionais declarados | Parcial | Core coberto; long tail fora/opcional. |
| Memory scaffold | 16 README dirs versionados | runtime dirs criados pelo installer + `PAI/MEMORY/README.md` | Adaptado/parcial | Menos scaffold versionado, mais runtime-created. |
| Knowledge | retrievers/harvesters + docs | `MemoryRetriever`, `KnowledgeGraph`, `SessionHarvester`, `KnowledgeHarvester` | Adaptado | Minimo funcional e testado; synthesis/embeddings deferidos. |
| Learning | Satisfaction/WorkCompletion/harvesters/relationship | ratings/signals/session learning + harvesters conservadores | Parcial | RelationshipMemory e pattern synthesis ausentes. |
| USER | 59 arquivos privados/contextuais | 15 bootstrap files preservadores de privacidade | Parcial/intencional | Reducao correta para release publico/local bootstrap. |
| TELOS | USER/TELOS completo | TELOS bootstrap + direct reads | Parcial | Sem `GenerateTelosSummary`/TelosSummarySync automaticos. |
| Pulse | 311 arquivos dashboard/VoiceServer/MenuBar/Observability | `PULSE.toml`, `PULSE/README.md`, optional `opencode/broker` | Fora de escopo/adaptado | Broker/mobile substitui Pulse desktop completo. |
| Voice | `VoiceCompletion.hook.ts`, `/notify`, ElevenLabs | `pai_notify`, notifications JSONL, broker/renderers | Adaptado | Mais adequado a mobile/headless. |
| Observability | Pulse visual + hook logs | JSONL schemas: classifier, guards, sessions, failures, traces, notifications | Adaptado | Uma das areas mais coerentes. |
| Security | Pipeline modular, SmartApprover, inspectors, containment zones | policy-driven inspectors (`PATTERNS.yaml` + fail-closed), ReadGuard, containment minimo, AgentGuard/SkillGuard | Adaptado | Cobertura de bloqueio/alerta restaurada ao nivel do original; falta apenas LLM approval/cache. |
| KV/cloud sync | `KVSync.hook.ts` | nenhum | Fora de escopo | Cloudflare KV nao faz parte do produto atual. |
| Desktop chrome | Kitty tabs, MenuBar macOS, statusline | nenhum | Fora de escopo | OpenCode/headless/mobile nao deve herdar isso. |
| Validacao | Sem produto OpenCode | install/check, behavioral, E2E, doc/promise/tools manifests | Adaptado | Cobertura forte do runtime atual. |

## De/Para de Hooks

| Hook original | Para no OpenCode | Status | Gap atual |
|---|---|---|---|
| `SecurityPipeline.hook.ts` | `tool.execute.before` + `permission.ask` | Adaptado | Bash/write/read/egress/containment OK; policy externa `PATTERNS.yaml` com cascata e fail-closed. Filosofia "ZERO confirm" do original restaurada (bash so deny/alert). |
| `PromptGuard.hook.ts` | `chat.message` pre-sanitize + `message.updated` post-check | Parcial | Pre-sanitize bloqueia prompt perigoso; post-check e advisory. |
| `PromptProcessing.hook.ts` | `chat.message` classifier | Adaptado | LLM-first por default; usa `opencode run --pure` para evitar recursao de plugin; timeout/erro vira ALGORITHM E3 fail-safe. |
| `RepeatDetection.hook.ts` | `message.updated` Jaccard trigram vs prompt anterior | Adaptado | Algoritmo do original (Jaccard tri/bigrama + estado por sessao); advisory (message.updated nao bloqueia). |
| `SatisfactionCapture.hook.ts` | `message.updated` | Adaptado | Ratings/praise em JSONL. |
| `ContextReduction.hook.sh` | nenhum | Platform-blocked | Exige rewrite de input pre-execucao; OpenCode `tool.execute.before` nao altera args. Sem equivalente de plataforma. |
| `ContentScanner.hook.ts` | `tool.execute.after` web scan | Parcial | Detecta e loga; nao injeta alerta no mesmo formato. |
| SkillGuard HTTP | `inspectSkillInvocation` | Adaptado | Nativo no plugin. |
| AgentGuard HTTP | `inspectAgentSpawn` | Adaptado | Nativo no plugin. |
| `ToolActivityTracker.hook.ts` | `tool.execute.after` | Adaptado | JSONL + ground truth. |
| `ToolFailureTracker.hook.ts` | `tool.execute.after` | Adaptado | `tool-failures.jsonl` + notification threshold. |
| `ISASync.hook.ts` | `syncISAToWorkRegistry()` | Adaptado | Sem Kitty/statusline. |
| `CheckpointPerISC.hook.ts` | `recordISCCheckpointsFromISA()` | Adaptado | Allowlist-only, sidecar, rollback preview. |
| `SmartApprover.hook.ts` | `permission.asked` trusted fast-path + read cache | Adaptado | Port deterministico fiel (o original tambem nao usa LLM aqui); auto-allow de paths confiaveis + cache de read. RulesInspector LLM opcional declarado, nao implementado. |
| `ContainmentGuard.hook.ts` | `inspectWriteContent()` + path tiers da policy | Parcial | Bloqueia segredos fortes e tiers de path (zeroAccess/readOnly/noDelete/confirm) via `PATTERNS.yaml`; sem zones completas LLM. |
| `PreCompact.hook.ts` | `experimental.session.compacting` | Adaptado | Injeta PAI context/recent work. |
| `LoadContext.hook.ts` | `session.created` + system transform | Adaptado | Contexto real via transform. |
| `RestoreContext.hook.ts` | `experimental.session.compacting` (Tier-1 fullFiles + DA identity) | Adaptado | Injecao proativa na compactacao (vs. restauracao reativa pos-compact do original); carrega fullFiles configuraveis + secoes do DA_IDENTITY. |
| `SessionCleanup.hook.ts` | `session.deleted` | Adaptado | Cleanup em delete/event bridge. |
| `WorkCompletionLearning.hook.ts` | `session.deleted` learning + relationship capture | Adaptado | Learning signals + nota B por trabalho; synthesis via `LearningPatternSynthesis.ts`. |
| `RelationshipMemory.hook.ts` | `session.deleted` captura conservadora + `RelationshipReflect.ts` | Adaptado | Nota B por trabalho concluido alimenta reflexao (confidence/milestones) via tool. |
| `TelosSummarySync.hook.ts` | `tool.execute.after` + `GenerateTelosSummary.ts` | Adaptado | Edit em USER/TELOS regenera PRINCIPAL_TELOS.md (fail-soft). |
| `DocIntegrity.hook.ts` | `session.deleted` integrity telemetry | Adaptado | Roda validadores fail-soft quando arquivos PAI mudam (telemetry-only, sem auto-edit). |
| `IntegrityCheck.hook.ts` | fundido em integrity-on-session-end (cooldown) | Adaptado | Cooldown 5min + change-detection via tool-activity; loga em OBSERVABILITY/integrity.jsonl. |
| `UpdateCounts.hook.ts` | `counts.json` basico | Parcial | Sem mesmo painel/metrica original. |
| `LastResponseCache.hook.ts` | `last-response.txt` | Adaptado | Usado para rating/learning. |
| `QuestionAnswered.hook.ts` | nenhum especifico | Ausente | Baixo impacto sem AskUserQuestion UI parity. |
| `SetQuestionTab`, `ResponseTabReset`, `KittyEnvPersist` | nenhum | Fora de escopo | Kitty/desktop-specific. |
| `VoiceCompletion.hook.ts` | `pai_notify` + notifications/broker | Adaptado | Tool explicit > parsing texto final. |
| `KVSync.hook.ts` | nenhum | Fora de escopo | Cloud sync removido. |
| `ConfigAudit.hook.ts` | install/check validators | Parcial | Nao hook runtime. |
| `ElicitationHandler.hook.ts` | nenhum | Platform-blocked | Exige eventos MCP elicitation que o OpenCode nao expoe. Sem equivalente de plataforma. |
| `TaskGovernance`, `TeammateIdle`, `StopFailureHandler` | guardas/traces parciais | Parcial/ausente | Ainda nao replica swarm/session governance original. |

## Agents

| Agente original | Port OpenCode | Status | Observacao |
|---|---|---|---|
| Algorithm | Sim | Parcial | Doutrina ativa coerente com core; ISA CLIs ainda ausentes. |
| Architect | Sim | Adaptado | Presente. |
| Artist | Sim | Parcial | `RemoveBg.ts` opcional; Art workflows devem verificar. |
| Engineer | Sim | Adaptado | Presente. |
| Designer | Sim | Adaptado | Presente. |
| Silas | Sim | Adaptado | Presente. |
| Anvil | Sim | Adaptado/dependencia externa | Tool existe; sem `MOONSHOT_API_KEY` retorna unavailable. |
| Forge | Sim | Adaptado/dependencia externa | Tool existe; sem Codex retorna unavailable. |
| Cato | Sim | Adaptado/dependencia externa | Tool existe; sem Codex retorna skipped. |
| Arthur | Sim | Adaptado | Tool deterministico de politica de credenciais. |
| ClaudeResearcher | Sim | Adaptado | Presente. |
| CodexResearcher | Sim | Adaptado | Presente. |
| GeminiResearcher | Sim | Adaptado | Presente. |
| GrokResearcher | Sim | Adaptado | Presente. |
| PerplexityResearcher | Sim | Adaptado | Presente. |
| BrowserAgent | Removido | Fora de escopo | Substituido por Interceptor/browser workflows. |
| QATester | Removido | Fora de escopo | Substituido por Interceptor/verification flows. |
| UIReviewer | Removido | Fora de escopo | Substituido por Interceptor/design verification flows. |

## Skills

| Area | Original | Port atual | Status | Observacao |
|---|---|---|---|---|
| Diretorios | 45 | 46 (`Lib` novo) | Adaptado | Nomes originais preservados; `Lib` centraliza helpers. |
| Knowledge | dependia de MemoryRetriever/Graph/Harvesters | todos os quatro tools core existem | Adaptado | `contradictions` implementado por tag-overlap para review. |
| ISA | workflows markdown (sem Tools no original) | workflows existem | Equivalente | **Correcao:** o ISA original e markdown-only — nao existem `skills/ISA/Tools/*.ts`. Implementa-los seria extensao nova, nao paridade. |
| Art | workflows + media helpers | `RemoveBg.ts` implementado | Adaptado | Wrapper rembg presente; reporta indisponivel sem binario. |
| Migrate | `MigrateScan/Approve` | ambos implementados | Adaptado | Scan→queue→approve funcional end-to-end. |
| PAIUpgrade | usa sources/transcripts/config helpers herdados | parte ainda herdada | Parcial | Precisa pass dedicado se virar prioridade. |
| Interceptor/Browser/Research/etc. | preservados/adaptados | preservados | Adaptado | Validadores tratam stale installed skills. |

## PAI/TOOLS

Original: 86 arquivos em `PAI/TOOLS` (incluindo UI, Python, package files e long-tail helpers).

Port core implementado:

| Tool | Status | Contrato OpenCode |
|---|---|---|
| `Inference.ts` | Implementado | Adapter provider-agnostic; `unavailable` se sem comando configurado. |
| `ForgeProgress.ts` | Implementado | Wrapper Codex; `unavailable` se Codex indisponivel. |
| `AnvilProgress.ts` | Implementado | Wrapper Moonshot/Kimi; `unavailable` sem key. |
| `CrossVendorAudit.ts` | Implementado | Auditor read-only; `skipped` sem Codex. |
| `Arthur.ts` | Implementado | Narrador deterministico de credential policy. |
| `MemoryRetriever.ts` | Implementado | BM25-lite read-only em Knowledge. |
| `KnowledgeGraph.ts` | Implementado | stats/find/related/traverse. |
| `Checkpoint.ts` | Implementado | list/show/rollback preview/record; sem rollback destrutivo. |
| `SessionHarvester.ts` | Implementado | transcript mining dry-run/review-queue-first; le formato de role do OpenCode. |
| `KnowledgeHarvester.ts` | Implementado | status/validate/index/contradictions/harvest conservador. |
| `GenerateTelosSummary.ts` | Implementado | Compressao heuristica TELOS→PRINCIPAL_TELOS.md; `unavailable` sem fontes core. |
| `LearningPatternSynthesis.ts` | Implementado | Agrega ratings.jsonl em padroes; `unavailable`/`no_data`. |
| `RelationshipReflect.ts` | Implementado | Confidence deltas (OPINIONS) + milestones (OUR_STORY); `unavailable` sem fontes. |
| `RemoveBg.ts` | Implementado | Wrapper rembg; erro claro sem binario. |
| `MigrateScan.ts` | Implementado | Markdown→propostas de migracao classificadas. |
| `MigrateApprove.ts` | Implementado | Review/approve/route com proveniencia. |

Long tail nao portado por grupo:

| Grupo original | Exemplos | Status | Racional |
|---|---|---|---|
| Pulse/monitoring/cost | `CostTracker`, `ComputeGap`, `HealthSnapshot`, `PipelineMonitor`, UI Vite | Fora de escopo/parcial | Broker/headless substitui dashboard/monitor completo. |
| Telos/identity/interview | `DAInterview`, `DAGrowth`, `InterviewScan` | Parcial | `GenerateTelosSummary` portado; interview/growth ainda nao. |
| Learning/wisdom/relationship | `Wisdom*`, synthesis avancado | Parcial | `LearningPatternSynthesis`/`RelationshipReflect` portados; wisdom avancado nao. |
| Media/transcription | `SplitAndTranscribe`, `YouTubeApi`, `AddBg`, banners | Fora/opcional | Skills devem prover fallback ou portar sob demanda. |
| CLI/internal PAI | `pai.ts`, `algorithm.ts`, `IntegrityMaintenance`, `DocCheck` | Adaptado | Validadores/install substituem parte do papel. |

## Memory, Learning, Knowledge

| Funcionalidade | Original | Port atual | Status | Gap |
|---|---|---|---|---|
| Runtime state | WORK/STATE/AUTO scaffolds + hooks | `MEMORY/STATE`, `WORK`, `OBSERVABILITY` runtime-created | Adaptado | Menos scaffolds versionados. |
| Session registry | hooks + files | `work.json`, `current-work-<session>.json` | Adaptado | Headless, testado. |
| Knowledge retrieval | MemoryRetriever/KnowledgeGraph | ambos implementados | Adaptado | BM25/graph local, sem embeddings. |
| Harvest session | `SessionHarvester.ts` | implementado | Adaptado | Review-queue-first; nao autonomo. |
| Harvest knowledge/index | `KnowledgeHarvester.ts` | implementado | Adaptado | Conservative harvest; contradictions por tags. |
| Relationship memory | `RelationshipMemory.hook.ts`, OUR_STORY | ausente | Ausente | Se importar para produto, portar depois. |
| Pattern synthesis | `LearningPatternSynthesis.ts` | ausente | Ausente | Nao core atual. |
| KV sync | Cloudflare KV | ausente | Fora de escopo | Removido do produto atual. |

## Security

| Area | Original | Port atual | Status | Proximo passo se necessario |
|---|---|---|---|---|
| Dangerous bash | SecurityPipeline/PatternInspector | `PATTERNS.yaml` blocked/alert/trusted (cascata + fail-closed) | Adaptado | Cobertura restaurada do v3.1 original: variantes de `rm` (`-fr`, `-r -f`), home/`$HOME`/`~/.config/opencode`/`~/Projects`, `gh repo delete`/`--visibility public`, `dd if=/dev/zero`, `diskutil`. Catastrofico → deny; `rm` recursivo de subpath → alert (corrige over-block de `rm -rf node_modules`). |
| Sensitive writes | path inspectors/containment | tiers da policy (zeroAccess/readOnly/noDelete/confirmWrite) + secret-content | Adaptado | Glob-based; sem false positives de substring. Full containment zones LLM ainda fora. |
| Sensitive reads | SecurityPipeline Read hook | tiers zeroAccess/confirmAccess/alertAccess via policy | Adaptado | Chaves SSH/PEM/credenciais → deny; `.env` → alert. |
| Prompt injection | PromptGuard/PromptInspector | chat pre-sanitize + content scanner | Parcial | LLM semantic layer opcional. |
| Smart approval | SmartApprover LLM/cache | rule-based + native permission prompt | Parcial | `require_approval` agora so para tiers de path (prompt nativo); bash segue "ZERO confirm" do original. Falta cache/LLM. |
| Agent/Skill guard | HTTP hooks | native plugin inspectors | Adaptado | Boa cobertura atual. |
| Egress | EgressInspector | command egress checks + alert tier (`nc`/`socat`/POST/env dump) | Adaptado | Fail-closed sob policy corrompida. |

## Pulse, Voice e Mobile

| Funcionalidade | Original | Port atual | Status |
|---|---|---|---|
| Desktop dashboard | Next/Observability UI | nao portado | Fora de escopo |
| Voice server | VoiceServer/ElevenLabs | broker + renderer/Kokoro/mobile TTS path | Adaptado |
| MenuBar macOS | app/plist/MenuBar | nao portado | Fora de escopo |
| `/notify` | daemon endpoint | legacy-compatible broker endpoint + `pai_notify` | Adaptado |
| Notifications contract | Pulse visual/events | `notifications.jsonl` schema v1 | Adaptado |
| Mobile | nao era foco original | build-mobile profile + broker/renderers | Adaptado/melhorado |

## Install/Validation

| Area | Original | Port atual | Status |
|---|---|---|---|
| Install | `.claude/install.sh` + PAI-Install GUI | `opencode/install.sh`, repair/check, manifest | Adaptado |
| Config drift | manual | generated config compare | Adaptado |
| Stale skills | nao aplicavel | install manifest removes stale generated dirs | Adaptado |
| Promise drift | nao aplicavel | promise/doc/tools validators | Melhor que original |
| Runtime tests | nao OpenCode | unit + behavioral + E2E | Melhor que original |

## Gaps Restantes Priorizados

### P0 - Se quiser fechar comportamento divergente ainda ativo

1. ~~**Security policy externalizada**~~ **FEITO**: `PAI/USER/SECURITY/PATTERNS.yaml` com parser dedicado, cascata (user → bundled default → fail-closed), carve-out anti-lockout para o proprio arquivo, e cobertura adversarial em `security-pipeline.test.ts`. Regressao de cobertura vs original v3.1 corrigida; `require_approval` de bash removido (filosofia "ZERO confirm").
2. **SmartApprover v2**: cache, LLM/policy reasoner, explicacao estruturada.
3. **DocIntegrity runtime**: rodar no equivalente de Stop/session.deleted como telemetry/fail-soft.

As regressoes de seguranca e os hooks/tools secundarios de paridade foram fechados (ver
tabelas De/Para acima). Restam:

### Platform-blocked (sem equivalente no OpenCode hoje)

1. **ContextReduction** — exige rewrite de input pre-execucao; `tool.execute.before` nao altera args.
2. **ElicitationHandler** — exige eventos MCP elicitation que o OpenCode nao expoe.

Reabrir apenas se o OpenCode ganhar esses ganchos. Nao sao gaps de implementacao.

### Extensao (nao existe no original — decisao de produto, nao paridade)

1. `skills/ISA/Tools/*.ts` — o ISA original e markdown-only. Implementar CLIs seria feature nova.

### Opcional / sob demanda

1. SmartApprover RulesInspector LLM (`SECURITY_RULES.md` + classifier) — gancho declarado, fail-open, desligado.
2. DocIntegrity com surgical edits (hoje telemetry-only por decisao conservadora).
3. PAIUpgrade transcript/config helpers; `DAInterview`/`DAGrowth`; wisdom synthesis avancado.

### Fora de Escopo Mantido

- Pulse desktop dashboard completo.
- MenuBar macOS.
- Kitty tab/statusline.
- Cloudflare KV sync.
- PAI-Install GUI/Electron/web.
- Portar todos os 86 tools originais sem demanda concreta.
- Reintroduzir private USER corpus no repo publico/local bootstrap.

## Conclusao

O port OpenCode agora esta coerente no core. O que antes era mais perigoso - prompt/Algorithm prometendo helpers inexistentes, checkpoint ausente, harvesters ausentes e instalacao driftada - foi corrigido e validado.

O proximo foco nao deveria ser mobile nem mais wrappers basicos. A melhor sequencia e:

1. decidir se security configuravel/SmartApprover LLM vale a complexidade;
2. decidir se ISA skill Tools devem virar runtime real;
3. so entao escolher quais helpers long-tail das skills merecem port.
