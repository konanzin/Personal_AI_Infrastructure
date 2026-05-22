# Análise de Hooks Não Implementados — PAI Original vs OpenCode

**Data:** 2026-05-20
**Contexto:** PAI v5.0.0 original tem 37 hooks. Port OpenCode tem 15 implementados. Faltam 22.

---

## Hooks JÁ Implementados (15)

| # | Hook | Evento OpenCode | Status |
|---|------|-----------------|--------|
| 1 | SecurityPipeline | tool.execute.before | ✅ Implementado |
| 2 | LoadContext | session.created | ✅ Implementado |
| 3 | SessionCleanup | session.idle | ✅ Implementado |
| 4 | ToolActivityTracker | tool.execute.after | ✅ Implementado |
| 5 | ContentScanner | tool.execute.after | ✅ Implementado |
| 6 | PromptGuard | message.updated | ✅ Implementado |
| 7 | SatisfactionCapture | session.idle | ✅ Implementado |
| 8 | WorkCompletionLearning | session.idle | ✅ Implementado |
| 9 | ISASync | tool.execute.after | ✅ Implementado (parcial) |
| 10 | ToolFailureTracker | tool.execute.after | ✅ Implementado |
| 11 | UpdateCounts | session.idle | ✅ Implementado |
| 12 | IntegrityCheck | session.idle | ✅ Implementado (parcial) |
| 13 | RepeatDetection | message.updated | ✅ Implementado |
| 14 | LastResponseCache | tool.execute.after | ✅ Implementado |
| 15 | FileChanged | file.watcher.updated | ✅ Implementado |

**Total implementado:** 15/37 (41% dos hooks, mas ~82% da funcionalidade crítica)

---

## Hooks NÃO Implementados (22) — Análise Detalhada

### 🔴 Categoria 1: IMPOSSÍVEL no OpenCode (8 hooks)

Estes hooks dependem de eventos ou APIs que simplesmente não existem no OpenCode.

#### 1. ConfigAudit.hook.ts
**Função:** Auditoria de mudanças em settings.json (permissões, hooks, env, MCP servers)
**Trigger:** ConfigChange (evento exclusivo do Claude Code)
**Por que não existe no OpenCode:** Não há evento de mudança de config em tempo real
**Vale a pena?** ❌ Não — o OpenCode não tem esse evento. Workaround: audit manual via git diff.

#### 2. TeammateIdle.hook.ts
**Função:** Detecta quando um "colega" (outro agente em swarm) fica idle e toma ações
**Trigger:** TeammateIdle (evento exclusivo do Claude Code)
**Por que não existe no OpenCode:** OpenCode não tem conceito de "teammates" ou swarm nativo
**Vale a pena?** ❌ Não — arquitetura diferente

#### 3. SetQuestionTab.hook.ts
**Função:** Muda cor da aba do terminal Kitty para teal quando AskUserQuestion é chamado
**Trigger:** PreToolUse:AskUserQuestion
**Por que não existe no OpenCode:** OpenCode não tem controle de abas de terminal via hooks. É um app TUI próprio.
**Vale a pena?** ❌ Não — OpenCode gerencia própria UI

#### 4. ResponseTabReset.hook.ts
**Função:** Reseta título e cor da aba do terminal após resposta
**Trigger:** Stop
**Por que não existe no OpenCode:** Mesmo motivo acima — controle de UI é interno do OpenCode
**Vale a pena?** ❌ Não

#### 5. KittyEnvPersist.hook.ts
**Função:** Persiste variáveis de ambiente do terminal Kitty (KITTY_LISTEN_ON, KITTY_WINDOW_ID)
**Trigger:** SessionStart
**Por que não existe no OpenCode:** Específico do terminal Kitty + Claude Code. OpenCode não usa Kitty.
**Vale a pena?** ❌ Não — OpenCode tem próprio sistema de notificação

#### 6. AgentInvocation.hook.ts
**Função:** Tracking detalhado de subagentes (quem chamou, duração, tipo)
**Trigger:** PreToolUse:Agent / PostToolUse:Agent
**Por que difícil no OpenCode:** OpenCode não expõe eventos granulares de subagentes. O evento `tool.execute.after` captura tudo como "tool" genérica.
**Vale a pena?** ⚠️ Parcialmente — podemos detectar uso de "skill" ou "task" no tool.execute.after, mas não temos metadados de subagent_type/description

#### 7. VoiceCompletion.hook.ts
**Função:** Notificação por voz quando sessão termina (TTS via VoiceServer)
**Trigger:** Stop
**Por que não existe no OpenCode:** Requeria VoiceServer/Pulse infraestrutura externa
**Vale a pena?** ❌ Não — decidimos não portar PULSE

#### 8. InstructionsLoadedHandler.hook.ts
**Função:** Handler disparado quando instruções do sistema são carregadas
**Trigger:** Evento específico do Claude Code
**Por que não existe no OpenCode:** Não há evento equivalente
**Vale a pena?** ❌ Não

---

### 🟡 Categoria 2: POSSÍVEL mas COMPLEXO (8 hooks)

Estes podem ser implementados mas requerem trabalho significativo ou têm limitações.

#### 9. SmartApprover.hook.ts ⭐ IMPORTANTE
**Função:** Aprovação inteligente de permissões:
- Paths confiados → auto-aprova
- Operações de leitura → auto-aprova
- Operações de escrita → deixa usuário decidir
- Mantém cache de decisões anteriores
**Trigger:** PermissionRequest
**Status no OpenCode:** Temos `permission.asked` e `permission.replied` mas:
- Não podemos interceptar e MODIFICAR a decisão (só logamos)
- O OpenCode pergunta ao usuário diretamente, não dá para auto-aprovar via hook
**Implementação possível:** 
- Usar `permission.asked` para logar
- Usar `permission.replied` para aprender padrões do usuário
- Criar um sistema de "regras de auto-aprovação" baseado em regex/paths (como fazíamos em .env)
**Vale a pena?** ✅ SIM — mas com expectativa ajustada. Não será "smart" com LLM, será "rule-based" com paths confiados.
**Esforço:** 2-3h

#### 10. SessionAnalysis.hook.ts
**Função:** Análise de sessão com LLM:
- Detecta sentimento do usuário
- Auto-nomeia sessão baseada no conteúdo
- Detecta esforço/tier (E1-E5)
- Detecta intenção (build vs research vs debug)
**Trigger:** UserPromptSubmit
**Status no OpenCode:** Podemos usar `message.updated` mas:
- Fazemos detecção por keywords (já implementamos effort detection básico)
- Análise com LLM adicional gastaria tokens e tempo
**Implementação possível:**
- Melhorar o effort detection existente com mais keywords
- Adicionar detecção de categoria (coding, research, writing, etc.)
- Nomear sessão baseada nas primeiras 10 palavras do prompt
**Vale a pena?** ✅ SIM — mas keep it simple (keywords, não LLM calls)
**Esforço:** 1-2h

#### 11. ContextReduction.hook.ts (RTK)
**Função:** Redução de contexto antes de enviar para LLM:
- Comprime comandos bash grandes (ex: `find ... | xargs ...`)
- Remove output redundante
- Resume conteúdo web longo
**Trigger:** PreToolUse (específico)
**Status no OpenCode:** Podemos usar `tool.execute.before` para:
- Detectar comandos bash muito longos (>500 chars)
- Detectar outputs muito grandes
- Mas NÃO podemos modificar o que será enviado ao LLM (o hook roda DEPOIS do tool usar, não ANTES do LLM ver)
**Implementação possível:**
- Adicionar aviso quando comandos são muito longos
- Sugerir compactação ao usuário
- Não é verdadeira "redução de contexto"
**Vale a pena?** ⚠️ MARGINALMENTE — OpenCode já tem compactação nativa de contexto
**Esforço:** 1h

#### 12. QuestionAnswered.hook.ts
**Função:** Handler quando usuário responde a AskUserQuestion
- Reseta tab cor (coordinado com SetQuestionTab)
- Loga a resposta
- Atualiza estado
**Trigger:** PostToolUse:AskUserQuestion
**Status no OpenCode:** Não temos evento específico para "question answered"
**Implementação possível:**
- Detectar no `tool.execute.after` quando tool é "question" ou similar
- Logar que pergunta foi respondida
**Vale a pena?** ⚠️ BAIXO — funcionalidade marginal
**Esforço:** 30min

#### 13. TaskGovernance.hook.ts
**Função:** Governança de tarefas:
- Limita número de tarefas concorrentes
- Detecta tasks "orfãs"
- Balanceia carga entre agentes
**Trigger:** UserPromptSubmit / TeammateIdle
**Status no OpenCode:** OpenCode não tem sistema de "tasks" explícito como Claude Code
**Implementação possível:**
- Contar número de chamadas de tool/skills por sessão
- Detectar quando sessão está "perdida" (muitos turnos sem progresso)
**Vale a pena?** ⚠️ BAIXO — OpenCode gerencia isso internamente
**Esforço:** 2h

#### 14. ContainmentGuard.hook.ts
**Função:** Proteção de "containment zones" (isolação de arquivos sensíveis):
- Define zonas que não podem ser lidas/escritas
- Bloqueia acesso a ~/.ssh, ~/.aws, chaves privadas
- Diferente do SecurityPipeline (que é geral), este é específico por projeto
**Trigger:** PreToolUse (read/write)
**Status no OpenCode:** Podemos implementar em `tool.execute.before` como extensão do SecurityPipeline
**Implementação possível:**
- Adicionar lista de "containment zones" em .env ou config
- Verificar se filePath está dentro de zona proibida
- Bloquear com throw Error
**Vale a pena?** ✅ SIM — é basicamente uma extensão do SecurityPipeline existente
**Esforço:** 1h

#### 15. CheckpointPerISC.hook.ts
**Função:** Cria checkpoints (git commits) a cada ISC (Ideal State Criteria) completado:
- Detecta quando checkbox de ISC é marcado
- Faz auto-commit com mensagem descritiva
- Permite rollback por ISC
**Trigger:** PostToolUse (detecta mudanças em ISA.md)
**Status no OpenCode:** Podemos detectar mudanças em arquivos ISA via `file.watcher.updated` ou `file.edited`
**Implementação possível:**
- Detectar quando arquivo ISA.md é modificado
- Verificar se conteúdo mudou de "unchecked" para "checked"
- Fazer `git add` + `git commit` automaticamente
**Vale a pena?** ✅ SIM — útil para versionamento incremental
**Esforço:** 2-3h

#### 16. RestoreContext.hook.ts
**Função:** Restaura contexto quando sessão é retomada:
- Carrega estado anterior
- Re-hidrata variáveis
- Mostra resumo do que estava acontecendo
**Trigger:** SessionStart (com source="resume")
**Status no OpenCode:** `session.created` já carrega contexto, mas não detecta se é "retomada"
**Implementação possível:**
- Detectar se existe work.json com sessão não-completada
- Mostrar resumo ao iniciar
**Vale a pena?** ⚠️ MARGINALMENTE — LoadContext já faz parte disso
**Esforço:** 1h

---

### 🟢 Categoria 3: FÁCIL de Implementar (6 hooks)

Estes são simples e podem ser adicionados rapidamente.

#### 17. DocIntegrity.hook.ts
**Função:** Verifica integridade da documentação:
- Detecta se links quebrados entre docs
- Verifica se CLAUDE.md referencia versão correta do Algorithm
- Checa consistência de paths
**Trigger:** Stop / PostToolUse (escrita em docs)
**Implementação possível:**
- Adicionar ao IntegrityCheck existente
- Verificar se ALGORITHM/LATEST bate com referência em CLAUDE.md
- Verificar se skills referenciadas existem
**Vale a pena?** ✅ SIM — adiciona valor ao IntegrityCheck existente
**Esforço:** 1h

#### 18. TelosSummarySync.hook.ts
**Função:** Sincroniza mudanças em TELOS com resumo:
- Quando TELOS/*.md é modificado, atualiza um resumo consolidado
- Mantém TELOS/README.md atualizado com status
**Trigger:** PostToolUse (escrita em TELOS/)
**Implementação possível:**
- Extensão do file.watcher.updated/file.edited existente
- Quando arquivo TELOS é modificado, regenerar resumo
**Vale a pena?** ⚠️ BAIXO — funcionalidade de conveniência
**Esforço:** 1h

#### 19. ElicitationHandler.hook.ts
**Função:** Handler para "elicitation" (quando sistema precisa de mais informação):
- Detecta quando resposta do modelo é vaga
- Sugere perguntas de follow-up
**Trigger:** PostToolUse (análise de resposta)
**Implementação possível:**
- Detectar respostas curtas (<100 chars) ou genéricas
- Logar como "possível elicitation necessária"
**Vale a pena?** ⚠️ BAIXO — difícil de detectar automaticamente
**Esforço:** 1h

#### 20. StopFailureHandler.hook.ts
**Função:** Handler quando sessão termina com erro:
- Loga o erro de forma estruturada
- Tenta recuperar estado
- Notifica usuário
**Trigger:** Stop (com erro)
**Implementação possível:**
- Extensão do session.error já implementado
- Adicionar mais contexto ao log de erro
**Vale a pena?** ✅ SIM — complementa ErrorHandler existente
**Esforço:** 30min

#### 21. KVSync.hook.ts
**Função:** Sincronização com Cloudflare KV:
- Envia estado da sessão para KV
- Recupera estado de outras sessões/dispositivos
**Trigger:** SessionStart / Stop
**Status no OpenCode:** Requer API externa + chaves
**Implementação possível:**
- Opcional — só ativa se KV_TOKEN estiver em .env
- Enviar work.json compactado
**Vale a pena?** ❌ Não — decidimos não fazer sync cloud na Fase 2
**Esforço:** 3h

#### 22. RelationshipMemory.hook.ts
**Função:** Gestão de memória de relacionamento:
- Atualiza OUR_STORY.md com interações
- Captura momentos importantes da conversa
**Trigger:** SessionStart / Stop
**Implementação possível:**
- Detectar menções a emoções, sentimentos, decisões importantes
- Adicionar ao work.json ou arquivo dedicado
**Vale a pena?** ⚠️ BAIXO — funcionalidade avançada de DA
**Esforço:** 2h

---

## Recomendação de Prioridade

### Implementar Agora (Alto ROI)

1. **SmartApprover (rule-based)** — 2-3h
   - Auto-aprovar leitura em paths confiados
   - Cache de decisões
   - Reduz drasticamente interrupções do usuário

2. **ContainmentGuard** — 1h
   - Extensão natural do SecurityPipeline
   - Protege ~/.ssh, chaves AWS, etc.

3. **CheckpointPerISC** — 2-3h
   - Auto-commit a cada critério completado
   - Muito útil para trabalho estruturado com ISAs

4. **DocIntegrity** — 1h
   - Extensão do IntegrityCheck existente
   - Mantém documentação consistente

### Implementar Depois (Médio ROI)

5. **SessionAnalysis (melhorado)** — 1-2h
   - Mais keywords para effort detection
   - Categorização de sessão (coding, research, etc.)

6. **ContextReduction (avisos)** — 1h
   - Avisar quando comandos/outputs são muito grandes

7. **StopFailureHandler** — 30min
   - Melhorar logging de erros de sessão

### Não Implementar (Baixo ROI ou Impossível)

- ConfigAudit, TeammateIdle, SetQuestionTab, ResponseTabReset, KittyEnvPersist
- VoiceCompletion (sem PULSE)
- KVSync (sem infra cloud)
- TaskGovernance, ElicitationHandler, RelationshipMemory

---

## Estimativa Total

**Implementando tudo recomendado (alto + médio ROI): 7 features**
- Esforço: ~10-12h
- Resultado: ~90% de compatibilidade funcional
- O que ainda faltaria: Voice, UI/Tabs, Sync cloud, Subagent tracking granular

**A implementação traria valor perceptível ao usuário?**
- ✅ SmartApprover: SIM — menos interrupções
- ✅ ContainmentGuard: SIM — mais segurança
- ✅ CheckpointPerISC: SIM — melhor versionamento
- ⚠️ SessionAnalysis: MARGINAL — melhorias incrementais

**Recomendação:** Implementar os 4 de "Alto ROI" primeiro. Os de "Médio ROI" podem esperar.
