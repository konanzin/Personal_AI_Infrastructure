# Fase 1 — dossiês dos workstreams

Formato de cada dossiê: **Regressão** (o que existe hoje) · **Proveniência** (de onde veio e por quê) · **Violação** (o teste do modelo-mais-esperto) · **Mudança** (diff proposto) · **Medição** (evals de guarda) · **Rollback**.

---

## W1.1a — `skill_misfire`: hard-deny por keyword ausente

**Regressão.** `inspectSkillInvocation` (`pai-hooks.lib.js`) classifica a invocação de skills de alta especificidade (ArXiv, Remotion…) e, se os args stringificados não contêm nenhuma keyword da lista `HIGH_SPECIFICITY_SKILLS`, retorna misfire com confiança alta → `pai-hooks.js` lança e **bloqueia a skill**. É deny incondicional, default-on, e casa contra um proxy (args stringificados), não contra o prompt real do usuário.

**Proveniência.** Port-added (`bd30b0e`, 2026-05-22, "opencode: add agent and skill guards"). Nenhum incidente registrado; o changelog o descreve como "higiene de orquestração" proativa com "deny threshold intencionalmente alto". O upstream não tem nenhum hook que gate invocação de skill por keyword.

**Violação.** Escolher a skill certa É o julgamento de tool-selection do modelo. Um modelo melhor escolhe skills melhor; a lista de keywords não melhora junto — só produz falsos bloqueios em fraseados novos. Hoje já bloqueia invocações corretas.

**Mudança.** Trocar o throw por warn + evento em `security-events.jsonl` (mesma postura do agent-deny, que já é opt-in via flag). A detecção continua existindo como telemetria.

**Medição.** Novo teste de guarda: skill de alta especificidade invocada com args sem keyword mágica **não** lança (asserta warn). Testes existentes que assertam o throw são invertidos no mesmo commit. `bun test` = 0 fail.

**Rollback.** Revert do commit único.

---

## W1.1b — inspectPrompt: deny + reescrita do prompt do usuário

**Regressão.** No caminho `chat.message`, um hit de severidade block nos regexes (`INJECTION_PATTERNS`, `SECURITY_DISABLE_PATTERNS`, `EVASION_PATTERNS`, exfiltração em duas fases) retorna `action:'deny'` e **sobrescreve `part.text`** com um refusal boilerplate. Os caminhos irmãos (`message.updated`, `inspectContent`) já são alert-only.

**Proveniência.** O corpus é port quase literal do `PromptInspector.ts` do upstream. Mas o upstream (PromptGuard.hook.ts) só bloqueia ou injeta warning em `additionalContext` — **a reescrita do texto do usuário é invenção do port**. A separação deny/alert entre prompt-do-usuário e conteúdo-externo está codificada em `TrustBoundaryActions.md`.

**Violação.** Regex decidindo se o texto do usuário é malicioso é julgamento determinístico substituindo compreensão de leitura — a tarefa em que o modelo mais melhora a cada geração. Falso positivo aqui destrói input legítimo (qualquer discussão SOBRE prompt injection dispara). O modelo nunca vê o texto original para julgar por si.

**Mudança.** Severidade block → `action:'alert'` + anotação para o modelo (contexto adicional, espelhando o upstream), **sem tocar em `part.text`**. Corpus permanece como pré-filtro de telemetria. Piso de AÇÃO (bash deny, secret-write, egress) intocado.

**Medição.** Guardas novas: (a) prompt benigno contendo literalmente "ignore previous instructions" chega intacto ao modelo (não reescrito, não negado) e gera alert logado; (b) `rm -rf /` e egress de chave viva **continuam negados** (corpus de segurança 100%). Testes que assertavam deny em prosa são atualizados no mesmo commit.

**Rollback.** Revert do commit; os regexes não mudam, só a ação.

---

## W1.2 — "honor above self-selection": o classificador manda no modelo

**Regressão.** `formatClassificationContext` (`mode-classifier.lib.js`) injeta a classificação com instrução de obedecê-la acima da própria avaliação do modelo ("if this seems wrong… still follow it"), e o `opencode.jsonc.template` recomenda tratá-la como autoritativa. Isso contradiz o bloco "You Decide" que o próprio harness injeta.

**Proveniência.** Doutrina upstream v6.0.0/v6.3.0: reação ao incidente real de sub-escalação de abr/2026 (pergunta E4 respondida em NATIVE de 1 parágrafo) — com o modelo daquela época. O port restaurou a forma no `26ff48b`/v6.3.2.

**Violação.** O caso canônico de regra-compensando-modelo-fraco sem condição de aposentadoria: um segundo modelo (mais fraco!) + regex sobrepondo o julgamento do modelo primário que já leu o prompt inteiro. Modelo melhor = classificação externa pior em termos relativos, e ela continua mandando.

**Mudança.** (a) A classificação vira sugestão explícita ("suggested: E3 — you may override based on your own read"); (b) `/e1`–`/e5` do usuário PERMANECE autoritativo (é instrução do Principal, não palpite); (c) template para de recomendar obediência e o flag de deny por confiança.

**Medição.** Golden heurístico não pode mudar (não tocamos classificação, só a prosa do contexto): re-rodar `--heuristic` e comparar 38/56·17/24. Golden com LLM (Kimi, `--runs 3`) antes de mesclar em dori — boundary O3 não pode cair de ~98%. Testes de prosa atualizados no commit.

**Rollback.** Revert de prosa, trivial.

---

## W1.3 — Research skill: contradição 4-vs-2 agentes

**Regressão.** Frontmatter/trigger dizem 4 agentes no modo Standard; Quick Reference, Gotchas e exemplo dizem 2; `StandardResearch.md` emite STATUS "2 agents" enquanto spawna 4.

**Proveniência.** O hábito de contagens hardcoded é herdado do upstream (SpawnParallelAgents "Launch 5 agents…"); a contradição em si nasceu de edições divergentes no port.

**Violação/Correção.** Bug de correção, ship imediato. A fonte única do roster (deletar as tabelas duplicadas) é W2.5.

**Medição.** Grep de consistência no arquivo; sem impacto em testes.

**Rollback.** n/a (correção pura).

---

## W1.4 — Blocos "Legacy Pulse" de notificação de voz

**Regressão.** ~30 skills carregam um bloco curl "Optional Legacy Pulse Progress Notification" cujo próprio texto diz que `pai_notify` já cobre a voz de conclusão.

**Proveniência.** Herdado — o curl 31337 existe em 138 arquivos do upstream. O `pai_notify` (que o substituiu) é adaptação do port por falta do voice hook do Claude Code.

**Violação.** Boilerplate morto competindo por atenção em toda invocação de skill; contrato duplicado sem fonte.

**Mudança.** Deletar os blocos Legacy. A variante obrigatória (5 skills) fica para W2.6 (mover para o runtime).

**Medição.** `bun test` (nada asserta os blocos); smoke manual de uma skill confirmando que `pai_notify`/hook ainda notifica.

**Rollback.** Git revert; blocos eram advisory (`|| true`), remoção não quebra execução.

---

## W1.5 — Pins literais de modelo nos validators

**Regressão.** `validate-pai-installation.sh:497` e `test-behavioral.sh:181-182` grep-am o literal `deepseek-v4-flash-free`.

**Proveniência.** O pin foi default de custo (free tier, `26ff48b`); o runtime já foi despinado (`da5e90a`, `c1d1df1`) — os validators ficaram para trás.

**Violação.** Validator asserta um snapshot do passado; trocar o default (já possível) quebra a validação sem nada estar errado.

**Mudança.** Assertar a propriedade, não o valor: `resolveClassifierConfig({},{})` retorna model string não-vazia e o default é centralizado em `mode-classifier.lib.js`.

**Medição.** Rodar os dois validators antes/depois; `bun test` 0 fail.

**Rollback.** Trivial.

---

## W1.6 — Heurísticas de "qualidade" de conteúdo web

**Regressão.** `pai-hooks.js:1592-1624`: substring `404`/`error` e limiares `<50`/`<200` chars geram warnings de qualidade sobre resultados de webfetch/websearch.

**Proveniência.** Port-added; o ContentScanner upstream só faz injection-scan.

**Violação.** O leitor do conteúdo é o modelo — detectar página de erro/conteúdo incompleto é compreensão de leitura. Substring "error" numa página legítima dispara falso warning.

**Mudança.** Deletar as heurísticas; se quiser observabilidade, logar fatos de transporte (HTTP status, tamanho bruto). O injection-scan alert-only do mesmo caminho fica intocado.

**Medição.** `bun test`; guarda de não-regressão: injection-scan continua emitindo alerts no corpus.

**Rollback.** Trivial.

---

## W1.7 — skills/CLAUDE.md: guardrail de incidente único

**Regressão.** Mandato duro "MUST invoke CreateSkill para TODO trabalho de skill", com cerimônia de STOP e cláusula "ler o workflow à mão NÃO é compliance", citando `feedback_invoke_blogging_skill_never_handroll.md`.

**Proveniência.** Herdado verbatim do upstream. O arquivo de incidente citado **nunca foi vendorado** — a regra vive aqui sem sua base de evidência.

**Violação.** Um incidente (de outro sistema, com outro modelo) generalizado em regra permanente e absoluta. Modelo melhor não hand-rolla skills; a cerimônia só queima atenção.

**Mudança.** Reduzir a: convenções de estrutura vivem em CreateSkill + mandato estreito apenas no caso irreversível (promoção private→public exige o audit de Release Readiness). Re-endurecer só se a falha for reproduzida (e aí registrada aqui).

**Medição.** `bun test`; nenhum teste asserta a prosa.

**Rollback.** Trivial.

---

## W1.8 — Rating implícito fabricado

**Regressão.** `detectPositivePraise` casa um léxico de elogio e grava `rating: 8, confidence: 0.95` no journal de aprendizado — precisão fabricada sobre um palpite de keyword.

**Proveniência.** Mecanismo herdado (`SatisfactionCapture.hook.ts` upstream, "Positive praise → fast-path rating 8"); a constante nunca teve incidente. O loop já foi julgado risco de Goodhart e mantido read-only (`0aa61df`).

**Violação.** Sentimento por léxico é julgamento de linguagem congelado (e monolíngue por lista); o número 8 polui o dataset com falsa precisão.

**Mudança.** Manter `parseExplicitRating` (`/rate N` é contrato estruturado legítimo). No branch implícito: registrar evento qualitativo (`praise_detected`) sem score numérico fabricado. Substituto real (campo de satisfação emitido pelo modelo) é W3.2.

**Medição.** `bun test`; teste de guarda: elogio detectado gera evento sem `rating`.

**Rollback.** Trivial; blast radius é journal advisory.
