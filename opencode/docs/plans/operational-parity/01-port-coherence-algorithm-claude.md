# Plano 01 - Port Coherence: CLAUDE.md, Algorithm e Promessas de Runtime

## Objetivo

Alinhar as instrucoes centrais do PAI ao comportamento real do port OpenCode. O resultado esperado e que `PAI/CLAUDE.md`, `PAI/ALGORITHM/*`, `capabilities.md` e docs operacionais nao mandem o agente depender de arquivos, hooks, comandos ou ferramentas ausentes.

## Estado atual verificado no codigo

`PAI/CLAUDE.md` ainda promete superficies Claude Code:

- `PAI/CLAUDE.md:14` diz que regras de modo e subagentes estao em `PAI_SYSTEM_PROMPT.md`.
- `PAI/CLAUDE.md:63` manda usar `bun TOOLS/Inference.ts`.
- `PAI/CLAUDE.md:72` diz que regras constitucionais estao em `PAI/PAI_SYSTEM_PROMPT.md`.
- `PAI/CLAUDE.md:82` diz que esse prompt e carregado via `--append-system-prompt-file`.
- `PAI/CLAUDE.md:104` referencia `Agent(subagent_type="claude-code-guide")`, agente inexistente no port.

`PAI/ALGORITHM/v6.3.0.md` tambem promete runtime ausente ou diferente:

- `PAI/ALGORITHM/v6.3.0.md:73-82` diz que Sonnet decide modo/tier em `UserPromptSubmit`, sem regex fallback e sem julgamento do executor.
- `PAI/ALGORITHM/v6.3.0.md:118` diz que `ISASync.hook.ts` atualiza `work.json` e kitty tab.
- `PAI/ALGORITHM/v6.3.0.md:470` diz que `CheckpointPerISC.hook.ts` auto-commita cada ISC.
- `PAI/ALGORITHM/v6.3.0.md:505-509` chama `~/.config/opencode/PAI/PAI/TOOLS/Inference.ts`, com path duplicado e helper ausente.
- `PAI/ALGORITHM/v6.3.0.md:632-663` repete paths `PAI/PAI/MEMORY`.

O runtime OpenCode real esta em outro lugar:

- `opencode/plugins/pai-hooks.js:153-234` monta o contexto via `experimental.chat.system.transform`.
- `opencode/plugins/pai-hooks.js:389-535` classifica prompts via `chat.message`, heuristica local e LLM opcional.
- `opencode/plugins/pai-hooks.js:1956-1973` documenta o adapter real para OpenCode >=1.16, incluindo `permission.ask` e bus events.

## Diferenca operacional

O original podia ter uma camada constitucional separada e hooks Claude Code registrados em `settings.json`. O port usa:

- `opencode.jsonc` com `instructions`;
- plugin `pai-hooks.js`;
- handlers OpenCode;
- system transform injetado por mensagem;
- estado em `MEMORY/STATE/current-work-<session>.json`.

Hoje as instrucoes centrais misturam as duas arquiteturas. Isso cria o pior tipo de drift: o agente acredita que a infraestrutura existe e age como se ela estivesse carregada.

## Desenho OpenCode-native

Criar uma regra editorial simples:

- `PAI/CLAUDE.md`: contrato operacional do executor OpenCode.
- `PAI/ALGORITHM/vX.Y.Z.md`: doutrina de trabalho, mas apenas com capacidades realmente implementadas ou marcadas como indisponiveis.
- `opencode/plugins/pai-hooks.js`: unica fonte de verdade sobre eventos/hook mapping.
- `opencode/docs/README-OPENCODE.md`: escopo publico do port.

Nada deve dizer "hook X dispara" se X nao existe no plugin ou em helper instalado. Nada deve dizer "use `PAI/TOOLS/Y.ts`" se o arquivo nao existe ou se o agente/skill nao faz fallback explicito.

## Plano de implementacao

### Fase 1 - Inventario mecanico de promessas

Adicionar script/validator que escaneia `PAI/CLAUDE.md`, `PAI/ALGORITHM`, `opencode/agents`, `skills` e docs criticas por:

- `PAI_SYSTEM_PROMPT`;
- `--append-system-prompt-file`;
- `UserPromptSubmit`;
- `CheckpointPerISC`;
- `PAI/PAI/`;
- `TOOLS/*.ts`;
- nomes de hooks Claude Code;
- agentes inexistentes.

Classificar cada match como:

- `implemented`;
- `implemented_differently`;
- `fallback_explicit`;
- `out_of_scope`;
- `must_fix`.

### Fase 2 - Corrigir `PAI/CLAUDE.md`

Editar `PAI/CLAUDE.md` para:

- remover a promessa de `PAI_SYSTEM_PROMPT.md` carregado por flag Claude Code;
- apontar regras de modo para o classifier OpenCode real;
- trocar `TOOLS/Inference.ts` por estado real: `PAI/TOOLS` indisponivel ate o plano 05;
- remover `claude-code-guide` ou trocar por agente/skill existente;
- marcar Pulse desktop/statusline/kitty tabs como legado ou fora de escopo.

### Fase 3 - Bump ou patch do Algorithm

Criar `PAI/ALGORITHM/v6.3.1.md` ou patchar `v6.3.0.md` com changelog claro:

- Classifier: `chat.message` + `mode-classifier.lib.js`; heuristico por padrao; LLM opcional por env.
- Advisor: indisponivel ate `Inference.ts` ou substituto OpenCode-native existir.
- CheckpointPerISC: indisponivel ate plano 04/05 implementar.
- Cato/Forge/Anvil: disponiveis apenas se helpers existem; fallback structured `unavailable`.
- ISA sync: `syncISAToWorkRegistry` atualiza registry/notifications; kitty tab fora de escopo.
- Paths: remover `PAI/PAI`.

### Fase 4 - Alinhar docs de arquitetura

Atualizar docs com alto trafego:

- `opencode/docs/README-OPENCODE.md`;
- `PAI/DOCUMENTATION/PAISystemArchitecture.md`;
- `PAI/DOCUMENTATION/Hooks/HookSystem.md`;
- `PAI/DOCUMENTATION/Security/SecuritySystem.md`;
- `PAI/DOCUMENTATION/Tools/Tools.md`;
- `PAI/DOCUMENTATION/Pulse/PulseSystem.md`.

Regra: docs herdadas podem permanecer como "original/legacy", mas nao como runtime atual.

## Testes e criterios de aceite

Adicionar checks que falham se:

```bash
rg -n "PAI_SYSTEM_PROMPT|--append-system-prompt-file|PAI/PAI/|CheckpointPerISC|UserPromptSubmit" PAI/CLAUDE.md PAI/ALGORITHM opencode/agents
```

retornar promessa ativa sem uma das tags:

- `OpenCode runtime:`;
- `legacy Claude Code:`;
- `out of scope:`;
- `unavailable until:`.

Tambem validar:

- `bun test` em `opencode/`;
- behavioral check para system transform ainda injeta `CLAUDE.md`;
- validator de promessas do plano 10.

## Risco principal

Se corrigir so docs, sem validator, o drift volta. Este plano deve terminar com guard automatizado, nao apenas texto revisado.
