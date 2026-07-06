# Drift Register — scaffolding com data de validade

Inventário de toda heurística/gambiarra que compensa fraqueza de modelo. Regra: **compensação sem linha aqui é defeito em review.** Origem: auditoria Bitter Lesson de 2026-07-05 (27 violações confirmadas, 30 rejeitadas como arquitetura legítima). Relatório completo: artifact `bitter-lesson-audit` (claude.ai/code/artifact/916e156c-d95d-47f1-90ef-5f6bbc66245c).

## O gate de 3 perguntas (para TODO componente novo)

1. Qual falha real, nomeável, este componente resolve?
2. Um modelo mais capaz o tornaria desnecessário? Se sim, qual probe detecta isso?
3. Ele é removível em horas (uma fonte, um commit)?

"Não" em qualquer uma = não mescla, exceto se for exceção enumerada: piso de segurança, budget de recurso, schema/contrato, pin de reprodutibilidade, guarda de irreversibilidade.

## Fase 1 (dossiês em PHASE1.md)

| ID | Mecanismo | Local | Proveniência | Mudança | Status |
|---|---|---|---|---|---|
| W1.1a | `skill_misfire` hard-deny por keyword | `pai-hooks.lib.js` (inspectSkillInvocation) | **port-added**, especulativo (sem incidente) | deny → warn/log | pendente |
| W1.1b | inspectPrompt deny + rewrite do prompt | `pai-hooks.lib.js` ~1129-1266, `pai-hooks.js` chat.message | corpus herdado do upstream (`PromptInspector.ts`); **rewrite é port-added** | deny/rewrite → alert; corpus vira telemetria | pendente |
| W1.2 | "honor above self-selection" do classificador | `mode-classifier.lib.js` formatClassificationContext; `opencode.jsonc.template` | doutrina upstream v6.3.0 (incidente de sub-escalação, abr/2026) | classificação vira sugestão; `/eN` do usuário segue autoritativo | pendente |
| W1.3 | Contradição 4-vs-2 agentes na Research | `skills/Research/SKILL.md` + `StandardResearch.md` | contagens hardcoded herdadas; contradição introduzida no port | reconciliar números (fonte única vem em W2.5) | pendente |
| W1.4 | Blocos "Legacy Pulse" de voz (~30 skills) | `skills/*/SKILL.md` | herdado do upstream (curl 31337 em 138 arquivos lá) | deletar (o próprio texto se declara superado por `pai_notify`) | pendente |
| W1.5 | Pin `deepseek-v4-flash-free` em validators | `validate-pai-installation.sh:497`, `test-behavioral.sh:181` | acomodação de custo (free tier), já despinada no runtime | validar "existe default centralizado", não o nome literal | pendente |
| W1.6 | Heurísticas 404/length de qualidade web | `pai-hooks.js:1592-1624` | **port-added** (upstream só faz injection-scan) | deletar; logar só fatos de transporte | pendente |
| W1.7 | Guardrail MUST-invoke-CreateSkill | `skills/CLAUDE.md` | herdado; cita incidente upstream cujo arquivo nunca foi vendorado | reduzir a convenção + mandato estreito no caso irreversível (private→public) | pendente |
| W1.8 | Rating implícito fabricado (rating=8/conf 0.95) | `pai-hooks.lib.js` detectPositivePraise | mecanismo herdado (`SatisfactionCapture.hook.ts`); constante sem incidente | remover score fabricado; manter `parseExplicitRating` | pendente |

## Mantidos deliberadamente (não são dívida — NÃO "consertar")

Piso determinístico de bash/secrets/egress e sandbox bwrap (incidente `rm -rf $HOME`, 2026-05-20); tier `alert` do corpus de padrões (é log, não decisão); scanner de injection em conteúdo externo (alert-only, defesa contra circularidade); pins de reprodutibilidade dos audits cross-vendor; fallback heurístico offline do classificador (camada 2, não primária). Racional completo: §5 do relatório.

## Probes de aposentadoria (W3.1 — a construir)

A cada bump de modelo, rodar e comparar: (a) roteamento de skill/agente correto SEM keywords mágicas; (b) detecção de injection por leitura do modelo vs corpus; (c) self-selection de modo/tier vs golden set. Probe verde por 2 bumps consecutivos = PR de deleção agendado. Host natural: `pai-health.timer` + skill HarnessCalibration.
