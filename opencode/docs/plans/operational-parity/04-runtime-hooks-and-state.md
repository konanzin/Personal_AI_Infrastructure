# Plano 04 - Hooks, Estado e Checkpoints no Plugin OpenCode

## Objetivo

Fechar as diferencas de runtime mais importantes entre hooks Claude Code e o plugin OpenCode, sem tentar portar 69 arquivos de hook literalmente. O resultado deve ser uma matriz de responsabilidades implementadas no plugin, com testes que provem o comportamento.

## Estado atual verificado no codigo

Baseline original em `settings.json`:

- `origin/main:Releases/v5.0.0/.claude/settings.json:85-134` registra `SecurityPipeline` em Bash, Write, Edit, MultiEdit e Read.
- `settings.json:136-150` usa guardas HTTP para Skill e Agent.
- `settings.json:163-220` registra `ContentScanner`, `TelosSummarySync` e `ToolActivityTracker`.
- Hooks reais existem no baseline: `CheckpointPerISC.hook.ts`, `ISASync.hook.ts`, `DocIntegrity.hook.ts`, `SmartApprover.hook.ts`, etc.

Port atual:

- `opencode/plugins/pai-hooks.js:8-20` lista handlers F0-F9.
- `opencode/plugins/pai-hooks.js:1956-1973` explica que lifecycle/message updates chegam via bus `event`, e `permission.ask` aliasa `permission.asked`.
- `opencode/plugins/pai-hooks.js:1323-1347` sincroniza ISA em `tool.execute.after`.
- `opencode/plugins/lib/pai-hooks.lib.js:1167-1265` implementa `syncISAToWorkRegistry`.
- `opencode/plugins/pai-hooks.js:1367-1373` reconhece limitacao: `message.updated` e pos-processamento, nao equivalente a `UserPromptSubmit`.

Gap principal:

- `CheckpointPerISC` era prometido pelo Algorithm e agora existe no plugin OpenCode como rotina pos-write/edit sobre ISA.
- `DocIntegrity` e citado como responsabilidade original, mas nao ha equivalente forte.
- Alguns hooks originais foram corretamente aposentados, mas isso nao esta declarado com uma matriz runtime-vs-legacy no codigo/testes.

## Desenho OpenCode-native

Usar um unico plugin como orquestrador:

- `chat.message`: pre-prompt guard e classifier.
- `experimental.chat.system.transform`: contexto PAI.
- `tool.execute.before`: security, agent/skill guard, read/write guards.
- `tool.execute.after`: tool activity, content scanning, ISA sync, checkpoint trigger.
- `message.updated`: satisfaction e post-detection, com limitacao documentada.
- `session.created/deleted/idle/compacting`: lifecycle, recovery, cleanup, learnings.
- `permission.ask`: permission guard/smart approver.

## Plano de implementacao

### Fase 1 - Matriz executavel de hooks

Criar `opencode/plugins/hook-capabilities.json` ou export JS:

```json
{
  "SecurityPipeline": {"status":"implemented", "handler":"tool.execute.before"},
  "CheckpointPerISC": {"status":"implemented", "handler":"tool.execute.after"},
  "DocIntegrity": {"status":"missing", "handler":null}
}
```

O validator deve ler essa matriz e impedir que docs prometam status diferente.

### Fase 2 - CheckpointPerISC OpenCode-native

Implementar no plugin, nao como hook TS separado:

- detectar `tool.execute.after` em `write/edit/multiedit`;
- se `isISAArtifactPath(filePath)`, comparar criterios `[ ] -> [x]`;
- ler allowlist `~/.config/opencode/PAI/checkpoint-repos.txt`;
- para cada repo allowlisted com diff, criar commit `ISC-{N} ({slug}): {description}`;
- usar sidecar `MEMORY/WORK/{slug}/.checkpoint-state.json`;
- nunca executar rollback destrutivo; rollback fica no plano 05 via `Checkpoint.ts`.

Status executado em 2026-06-15:

- `recordISCCheckpointsFromISA()` implementado em `opencode/plugins/lib/pai-hooks.lib.js`;
- `tool.execute.after` chama checkpoint apos `syncISAToWorkRegistry()`;
- allowlist ausente retorna `skipped`, sem falhar a sessao;
- sidecar idempotente impede commit duplicado por ISC;
- `Checkpoint.ts rollback` permanece preview-only.

### Fase 3 - Compaction/recovery

Revisar `experimental.session.compacting`:

- garantir que injeta estado atual de `current-work-<session>.json`;
- incluir ultima ISA sync;
- incluir path do ISA quando conhecido.

### Fase 4 - DocIntegrity runtime minimo

Implementar um check headless:

- em `session.deleted` ou `opencode/bin/test-behavioral.sh`, rodar promise scanner do plano 10;
- registrar `doc_integrity` em `MEMORY/OBSERVABILITY/session-events.jsonl`;
- falhar validator, nao bloquear conversa em runtime normal.

## Testes e criterios de aceite

Adicionar testes unitarios/E2E:

- editar ISA marcando ISC `[x]` cria um commit em repo allowlisted e atualiza sidecar;
- re-editar mesmo ISC nao cria commit duplicado;
- repo fora da allowlist nao recebe commit;
- allowlist ausente nao comita e nao falha a sessao;
- rollback nao e executado pelo hook;
- `hook-capabilities` bate com handlers reais exportados pelo plugin.

Rodar:

```bash
cd opencode && bun test
opencode/bin/test-behavioral.sh
```

## Fora de escopo

- Portar kitty tabs/statusline.
- Portar todos os hooks Claude Code um a um.
- Auto-commitar repos nao allowlisted.
