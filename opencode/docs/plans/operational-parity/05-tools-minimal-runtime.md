# Plano 05 - Subset Minimo de PAI/TOOLS

Status: executado em 2026-06-15.

Resultado atual:

- `PAI/TOOLS/manifest.json` criado como contrato canonico.
- Implementados: `Inference.ts`, `ForgeProgress.ts`, `AnvilProgress.ts`, `CrossVendorAudit.ts`, `Arthur.ts`, `MemoryRetriever.ts`, `KnowledgeGraph.ts`.
- Inicialmente deferidos no manifest: `Checkpoint.ts`, `SessionHarvester.ts`, `KnowledgeHarvester.ts`. Em 2026-06-15 eles foram promovidos para `implemented` com testes e smokes.
- Opcionais no manifest: `RemoveBg.ts`, `MigrateScan.ts`, `MigrateApprove.ts`.
- Validadores atualizados: `validate-tools-manifest.js`, `validate-promise-integrity.sh`, `validate-pai-installation.sh`, `test-behavioral.sh`, `install.sh --check`.

## Objetivo

Decidir e implementar o menor conjunto de `PAI/TOOLS` necessario para paridade operacional do port OpenCode. O diretorio nao pode continuar vazio se Algorithm, agentes e skills continuam prometendo helpers.

## Estado verificado antes da execucao

Port antes deste plano:

- `find PAI/TOOLS -maxdepth 3 -type f | wc -l` retorna `0`.
- `opencode/install.sh:131` cria o diretorio `TOOLS`, mas nao instala helpers se o repo nao os tiver.
- `opencode/bin/validate-pai-installation.sh:536-540` valida apenas que o diretorio existe.
- `opencode/bin/test-behavioral.sh:540-548` exclui `*/TOOLS/*` das promessas de path.

Baseline original:

- `git ls-tree -r --name-only origin/main:Releases/v5.0.0/.claude/PAI/TOOLS | wc -l` retorna `86`.
- Entre os helpers reais estavam `Inference.ts`, `Checkpoint.ts`, `ForgeProgress.ts`, `AnvilProgress.ts`, `CrossVendorAudit.ts`, `Arthur.ts`, `MemoryRetriever.ts`, `KnowledgeGraph.ts`, `SessionHarvester.ts`, `KnowledgeHarvester.ts`, `RemoveBg.ts`, `MigrateScan.ts`, `MigrateApprove.ts`.

Consumidores atuais:

- `opencode/agents/Forge.md:46-53` exige `ForgeProgress.ts`, com fallback `unavailable`.
- `opencode/agents/Cato.md:21-31` exige `CrossVendorAudit.ts`, com fallback `skipped`.
- `opencode/agents/Arthur.md:19-30` exige `Arthur.ts`, sem inventar decisoes.
- `opencode/agents/Anvil.md:53-58` exige `AnvilProgress.ts`, com fallback `unavailable`.
- `skills/AudioEditor/Tools/Analyze.ts:15` importa `../../../PAI/TOOLS/Inference.ts`.
- `skills/Evals/Tools/PAIAgentAdapter.ts:10` importa `../../../PAI/TOOLS/Inference.ts`.
- `skills/Migrate/SKILL.md:60-111` chama `~/.claude/PAI/TOOLS/MigrateScan.ts` e `MigrateApprove.ts`.
- `skills/Knowledge/SKILL.md` referencia `KnowledgeGraph.ts`, `MemoryRetriever.ts` e `SessionHarvester.ts`.
- `PAI/PULSE/PULSE.toml:85`, `:93`, `:166`, `:174` chama helpers ausentes.

## Decisao de escopo

Nao portar todos os 86 arquivos de uma vez. Criar tres camadas:

### Camada A - Necessaria para promessas centrais

- `Inference.ts` ou substituto OpenCode-native.
- `Checkpoint.ts`.
- `ForgeProgress.ts`.
- `AnvilProgress.ts`.
- `CrossVendorAudit.ts`.
- `Arthur.ts`.

### Camada B - Necessaria para memoria/knowledge se a skill continuar ativa

- `MemoryRetriever.ts`.
- `KnowledgeGraph.ts`.
- `SessionHarvester.ts`.
- `KnowledgeHarvester.ts`.

### Camada C - Opcional / skill-specific

- `RemoveBg.ts`.
- `MigrateScan.ts`.
- `MigrateApprove.ts`.
- `CostTracker.ts`.
- `StalenessReview.ts`.
- `ComputeGap.ts`.

## Desenho OpenCode-native

Cada helper portado deve:

- usar paths `~/.config/opencode/PAI`, nao `~/.claude`;
- nao depender de Claude Code hook APIs;
- aceitar `--json` onde fizer sentido;
- escrever logs em `MEMORY/OBSERVABILITY` ou `MEMORY/WORK`;
- ter smoke tests;
- ter erro estruturado se dependencia externa estiver ausente.

Para `Inference.ts`, preferir uma interface provider-agnostic:

- `fast`, `standard`, `smart`, `advisor`;
- provider configuravel;
- sem assumir `claude` OAuth como unico caminho;
- se usar CLI externo, sanitizar env e timeout explicitamente.

## Plano de implementacao

### Fase 1 - Manifesto de tools

Criado `PAI/TOOLS/manifest.json` com status `implemented`, `deferred` e `optional`.

O validator do plano 10 agora delega a verificacao de tools para `validate-tools-manifest.js`.

### Fase 2 - Portar Camada A

Implementado como wrappers OpenCode-native, sem copiar acoplamento Claude Code:

- `Inference.ts`: adapter provider-agnostic via `PAI_INFERENCE_CMD`/`OPENCODE_INFERENCE_CMD`; structured `unavailable` se nao configurado.
- `ForgeProgress.ts`: wrapper para `codex exec --json`, com event/final files e structured `unavailable`.
- `AnvilProgress.ts`: wrapper Moonshot/Kimi, com structured `unavailable` sem `MOONSHOT_API_KEY`.
- `CrossVendorAudit.ts`: orquestrador read-only via Codex, com `skipped` quando indisponivel.
- `Arthur.ts`: narrador deterministico de politica de credenciais, sem decisao LLM e sem emitir segredos.

`Checkpoint.ts` foi implementado depois desta fase inicial: `list/show/rollback/record`, com rollback preview-only e commits allowlist-only.

### Fase 3 - Portar Camada B ou rebaixar Knowledge

Estado atual:

- `MemoryRetriever.ts` read-only implementado.
- `KnowledgeGraph.ts` read-only implementado.
- `SessionHarvester.ts` implementado com `--dry-run`, `--mine`, `--sessions-dir` e fila de revisao.
- `KnowledgeHarvester.ts` implementado com `status`, `validate`, `index` e `harvest`.

Harvesting virou prioridade nesta sessao e foi implementado com escopo conservador:

- `SessionHarvester.ts` nao escreve direto em KNOWLEDGE consolidado; `--mine` escreve candidatos em `_harvest-queue/`;
- `KnowledgeHarvester.ts harvest` consome fila/work/research, atualiza indexes e estado;
- testes cobrem no-session, dry-run, queue, status, index, validate e harvest.

### Fase 4 - Camada C por demanda

Para Art/Migrate/Pulse jobs:

- ou portar helpers;
- ou mover docs/workflows para `legacy`;
- ou adicionar fallback claro "helper not installed".

## Criterios de aceite

- `PAI/TOOLS/manifest.json` existe e e validado.
- Para cada helper `required`, arquivo existe e tem teste ou smoke.
- Para cada helper `missing`, todos os consumidores tem fallback explicito.
- `validate-pai-installation.sh` nao passa apenas por diretorio: valida manifest/status.
- `test-behavioral.sh` nao exclui `TOOLS` sem checar fallback.

## Risco principal

Portar `Inference.ts` literalmente pode reintroduzir acoplamento Anthropic/Claude Code. Esse helper deve ser desenhado como adapter OpenCode/provider-agnostic, mesmo que o primeiro provider seja Claude-like.
