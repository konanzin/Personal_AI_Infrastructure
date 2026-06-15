# PAI Original -> OpenCode Port Parity Audit

Data original: 2026-06-14
Ultima atualizacao: 2026-06-15

Baseline auditado:

- Original Claude Code: `origin/main:Releases/v5.0.0/.claude` em `2fde1bbe9e8f280cd4998e244b53e3c66f3dc8b9`.
- Port OpenCode: workspace local atual.
- Branch `master`: nao existe neste repo local; `origin/main` e o baseline disponivel.
- Estado instalado verificado apos `opencode/install.sh --repair`: `~/.config/opencode`.

Validacao atual:

- Repo: `bun test` -> 200/200.
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

Os gaps restantes que ainda importam sao menores e mais definidos:

1. **Security policy configuravel**: runtime ainda usa padroes hardcoded; falta `PATTERNS.yaml`/SmartApprover LLM/cacheado se isso for requisito.
2. **Runtime hooks secundarios**: RelationshipMemory, TelosSummarySync, DocIntegrity-on-Stop, ContextReduction, TaskGovernance/TeammateIdle/Elicitation ainda nao tem equivalentes completos.
3. **ISA skill CLIs**: workflows existem como markdown, mas `skills/ISA/Tools/*.ts` continuam ausentes/deferidos.
4. **Helpers opcionais de skills**: `RemoveBg.ts`, `MigrateScan.ts`, `MigrateApprove.ts` ainda sao opcionais; outras ferramentas long tail do original nao foram portadas.
5. **Pulse desktop avancado**: dashboard/VoiceServer/MenuBar/Observability UI do original permanecem fora de escopo; broker opcional e o caminho atual.

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
| Mode/tier | `PromptProcessing.hook.ts` UserPromptSubmit, modelo Sonnet | `chat.message` + `mode-classifier.lib.js`; heuristico default, LLM opcional | Parcial | Diverge em prompts ambiguos; testado e fail-safe E3. |
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
| Security | Pipeline modular, SmartApprover, inspectors, containment zones | rule-based inspectors, ReadGuard, containment minimo, AgentGuard/SkillGuard | Parcial | Falta config externa/LLM approval/cache. |
| KV/cloud sync | `KVSync.hook.ts` | nenhum | Fora de escopo | Cloudflare KV nao faz parte do produto atual. |
| Desktop chrome | Kitty tabs, MenuBar macOS, statusline | nenhum | Fora de escopo | OpenCode/headless/mobile nao deve herdar isso. |
| Validacao | Sem produto OpenCode | install/check, behavioral, E2E, doc/promise/tools manifests | Adaptado | Cobertura forte do runtime atual. |

## De/Para de Hooks

| Hook original | Para no OpenCode | Status | Gap atual |
|---|---|---|---|
| `SecurityPipeline.hook.ts` | `tool.execute.before` + `permission.ask` | Parcial | Bash/write/read/egress/containment minimo OK; policy externa ausente. |
| `PromptGuard.hook.ts` | `chat.message` pre-sanitize + `message.updated` post-check | Parcial | Pre-sanitize bloqueia prompt perigoso; post-check e advisory. |
| `PromptProcessing.hook.ts` | `chat.message` classifier | Parcial | Heuristico default; LLM opcional, nao Sonnet obrigatorio. |
| `RepeatDetection.hook.ts` | trecho em `message.updated` | Parcial | Sinal simples, nao full hook original. |
| `SatisfactionCapture.hook.ts` | `message.updated` | Adaptado | Ratings/praise em JSONL. |
| `ContextReduction.hook.sh` | nenhum | Ausente | OpenCode compaction existe, mas nao ha reducao RTK de tool output. |
| `ContentScanner.hook.ts` | `tool.execute.after` web scan | Parcial | Detecta e loga; nao injeta alerta no mesmo formato. |
| SkillGuard HTTP | `inspectSkillInvocation` | Adaptado | Nativo no plugin. |
| AgentGuard HTTP | `inspectAgentSpawn` | Adaptado | Nativo no plugin. |
| `ToolActivityTracker.hook.ts` | `tool.execute.after` | Adaptado | JSONL + ground truth. |
| `ToolFailureTracker.hook.ts` | `tool.execute.after` | Adaptado | `tool-failures.jsonl` + notification threshold. |
| `ISASync.hook.ts` | `syncISAToWorkRegistry()` | Adaptado | Sem Kitty/statusline. |
| `CheckpointPerISC.hook.ts` | `recordISCCheckpointsFromISA()` | Adaptado | Allowlist-only, sidecar, rollback preview. |
| `SmartApprover.hook.ts` | rule-based `permission.ask` | Parcial | Sem LLM/cache/policy learning. |
| `ContainmentGuard.hook.ts` | `inspectWriteContent()` minimo | Parcial | Bloqueia segredos fortes; sem zones completas/config. |
| `PreCompact.hook.ts` | `experimental.session.compacting` | Adaptado | Injeta PAI context/recent work. |
| `LoadContext.hook.ts` | `session.created` + system transform | Adaptado | Contexto real via transform. |
| `RestoreContext.hook.ts` | recent work/current-work parcial | Parcial | Sem resume detection completa. |
| `SessionCleanup.hook.ts` | `session.deleted` | Adaptado | Cleanup em delete/event bridge. |
| `WorkCompletionLearning.hook.ts` | `session.deleted` learning | Parcial | Basico; sem relationship/pattern synthesis. |
| `RelationshipMemory.hook.ts` | nenhum | Ausente | OUR_STORY/relationship memory nao atualiza automaticamente. |
| `TelosSummarySync.hook.ts` | nenhum | Ausente | TELOS edits nao regeneram summary. |
| `DocIntegrity.hook.ts` | validators manuais/install | Parcial | Nao roda automaticamente no Stop. |
| `IntegrityCheck.hook.ts` | validators shell | Parcial | Forte em install/check; nao runtime Stop. |
| `UpdateCounts.hook.ts` | `counts.json` basico | Parcial | Sem mesmo painel/metrica original. |
| `LastResponseCache.hook.ts` | `last-response.txt` | Adaptado | Usado para rating/learning. |
| `QuestionAnswered.hook.ts` | nenhum especifico | Ausente | Baixo impacto sem AskUserQuestion UI parity. |
| `SetQuestionTab`, `ResponseTabReset`, `KittyEnvPersist` | nenhum | Fora de escopo | Kitty/desktop-specific. |
| `VoiceCompletion.hook.ts` | `pai_notify` + notifications/broker | Adaptado | Tool explicit > parsing texto final. |
| `KVSync.hook.ts` | nenhum | Fora de escopo | Cloud sync removido. |
| `ConfigAudit.hook.ts` | install/check validators | Parcial | Nao hook runtime. |
| `TaskGovernance`, `TeammateIdle`, `ElicitationHandler`, `StopFailureHandler` | guardas/traces parciais | Parcial/ausente | Ainda nao replica swarm/session governance original. |

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
| ISA | workflows markdown + promessa de Tools | workflows existem; Tools CLI ausentes | Parcial | Proximo gap core se ISA automation virar foco. |
| Art | workflows + media helpers | helper `RemoveBg.ts` opcional | Opcional/parcial | Deve checar arquivo antes de chamar. |
| Migrate | `MigrateScan/Approve` | helpers opcionais | Opcional/parcial | Fallback manual necessario. |
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
| `SessionHarvester.ts` | Implementado | transcript mining dry-run/review-queue-first. |
| `KnowledgeHarvester.ts` | Implementado | status/validate/index/contradictions/harvest conservador. |

Opcionais declarados:

| Tool | Status | Consumidor |
|---|---|---|
| `RemoveBg.ts` | Opcional | Art workflows. |
| `MigrateScan.ts` | Opcional | Migrate skill. |
| `MigrateApprove.ts` | Opcional | Migrate skill. |

Long tail nao portado por grupo:

| Grupo original | Exemplos | Status | Racional |
|---|---|---|---|
| Pulse/monitoring/cost | `CostTracker`, `ComputeGap`, `HealthSnapshot`, `PipelineMonitor`, UI Vite | Fora de escopo/parcial | Broker/headless substitui dashboard/monitor completo. |
| Telos/identity/interview | `GenerateTelosSummary`, `DAInterview`, `DAGrowth`, `InterviewScan` | Parcial | TELOS bootstrap existe; automacao nao. |
| Learning/wisdom/relationship | `LearningPatternSynthesis`, `RelationshipReflect`, `Wisdom*` | Parcial/ausente | Knowledge minimo existe; synthesis avancado nao. |
| Media/transcription | `SplitAndTranscribe`, `YouTubeApi`, `AddBg`, banners | Fora/opcional | Skills devem prover fallback ou portar sob demanda. |
| Migration | `MigrateScan`, `MigrateApprove` | Opcional | Declarado, nao core. |
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
| Dangerous bash | SecurityPipeline/PatternInspector | hardcoded block/confirm patterns | Adaptado | Externalizar policy se quiser paridade. |
| Sensitive writes | path inspectors/containment | path guard + secret-content containment minimo | Parcial | Full containment zones. |
| Sensitive reads | SecurityPipeline Read hook | ReadGuard em permission/tool path | Adaptado | Ampliar payload coverage se OpenCode expuser mais shapes. |
| Prompt injection | PromptGuard/PromptInspector | chat pre-sanitize + content scanner | Parcial | LLM semantic layer opcional. |
| Smart approval | SmartApprover LLM/cache | rule-based approval/notification | Parcial | Implementar cache/LLM/policy file. |
| Agent/Skill guard | HTTP hooks | native plugin inspectors | Adaptado | Boa cobertura atual. |
| Egress | EgressInspector | command egress checks | Parcial | Mais protocolos/casos se necessario. |

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

1. **Security policy externalizada**: `PATTERNS.yaml`/rules config + tests; ou declarar oficialmente hardcoded.
2. **SmartApprover v2**: cache, LLM/policy reasoner, explicacao estruturada.
3. **DocIntegrity runtime**: rodar no equivalente de Stop/session.deleted como telemetry/fail-soft.

### P1 - Se ISA automation virar foco

1. Implementar `skills/ISA/Tools/*.ts` para scaffold/check/reconcile/append.
2. Expandir CheckpointPerISC para project ISA com state em `MEMORY/STATE/checkpoints` ja preparado.
3. Testar fluxo end-to-end de ISA skill + checkpoint + work registry.

### P2 - Se LifeOS/memoria profunda virar foco

1. RelationshipMemory / OUR_STORY.
2. LearningPatternSynthesis.
3. TelosSummarySync / GenerateTelosSummary.

### P3 - Se skills long-tail virarem produto

1. `RemoveBg.ts` para Art.
2. `MigrateScan.ts`/`MigrateApprove.ts` para Migrate.
3. PAIUpgrade transcript/config helpers.

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
