# Plano 10 - Validators de Promessa vs Runtime

Status: executado. O validator atual tambem chama `validate-tools-manifest.js`, entao `PAI/TOOLS` vazio ou helpers implementados ausentes nao passam mais.

## Objetivo

Transformar os validadores em prova de coerencia operacional, nao so prova de estrutura. Eles devem falhar quando prompt, agente, skill ou doc promete arquivo/hook/tool/comando que o runtime nao fornece.

## Estado verificado antes da execucao

`opencode/bin/test-behavioral.sh`:

- `:513-516` checa apenas agentes contra `~/.claude/`.
- `:518-519` checa `PAI/PAI/` em `CLAUDE.md`.
- `:540-548` exclui `*/TOOLS/*` e `*/MEMORY/*` de promessas de path.
- `:554-560` so escaneia paths em agentes.

`opencode/bin/validate-pai-installation.sh`:

- `:536-540` valida so que `TOOLS/` existe.
- `:586-606` valida Pulse scaffold e broker files.
- `:610-618` procura apenas `.claude/`, nao todas as formas de `~/.claude`.

Testes atuais bons, mas de escopo limitado:

- `opencode/tests/mode-classifier.test.ts` cobre classifier.
- `opencode/tests/isa-work-sync.test.ts` cobre ISA sync.
- `opencode/tests/security-pipeline.test.ts` cobre bash/write/guards.
- `opencode/tests/e2e-runtime/*` ja tem cenarios runtime.

## Diferenca operacional

O port pode passar com:

- `PAI/TOOLS` vazio;
- docs prometendo helpers ausentes;
- Algorithm prometendo hook ausente;
- skills importando `Inference.ts` ausente;
- config instalada sem `pai_notify`.

Isso gera falso senso de completude.

## Desenho OpenCode-native

Criar um validator novo:

`opencode/bin/validate-promise-integrity.sh`

Responsabilidade:

- scan de promessas runtime;
- correlacao com manifestos;
- saida clara por severidade;
- integracao com `validate-pai-installation.sh`.

## Plano de implementacao

### Fase 1 - Manifestos

Consumir manifestos dos planos:

- `PAI/TOOLS/manifest.json`;
- `opencode/plugins/hook-capabilities.json`;
- `opencode/install-manifest.json`;
- talvez `opencode/docs/plans/operational-parity/00-index.md` apenas como referencia, nao runtime.

### Fase 2 - Scanners

Scanner A - Paths Claude:

- `.claude/`;
- `~/.claude`;
- `$HOME/.claude`;
- `${HOME}/.claude`;
- path duplicado `PAI/PAI`.

Scanner B - Tools:

- detectar `PAI/TOOLS/<Name>` e `TOOLS/<Name>`;
- se `<Name>` nao existe, exigir fallback explicito no mesmo arquivo ou manifesto.

Scanner C - Hooks:

- detectar nomes de hooks originais;
- validar se aparecem em `hook-capabilities.json`;
- se missing, exigir texto `legacy`, `out of scope` ou `unavailable`.

Scanner D - Agents/commands:

- detectar `Agent(subagent_type="...")`;
- validar arquivo em `opencode/agents`;
- detectar comandos `/foo`;
- validar em `opencode.jsonc.template`.

Scanner E - Config instalada:

- comparar campos gerados essenciais em `~/.config/opencode/opencode.jsonc`;
- `pai_notify` em `build` e `build-mobile`;
- plugin path unico.

### Fase 3 - Severidade

Classificar:

- `FAIL`: prompt/agente/skill operacional chama helper ausente sem fallback.
- `FAIL`: config instalada sem plugin ou sem primary agents.
- `WARN`: doc historica menciona superficie legacy.
- `INFO`: legado explicitamente marcado.

### Fase 4 - Integracao

Adicionar ao final de:

- `opencode/bin/validate-pai-installation.sh`;
- `opencode/bin/test-behavioral.sh`;
- install smoke workflow.

## Criterios de aceite

Criar fixtures que provem:

- um arquivo com `PAI/TOOLS/Missing.ts` sem fallback falha;
- o mesmo com `unavailable until Missing.ts exists` passa com warn/info;
- `~/.claude` sem slash e detectado;
- `PAI_SYSTEM_PROMPT.md` prometido sem arquivo/carregamento falha;
- `CheckpointPerISC.hook.ts` prometido sem `hook-capabilities` falha;
- config instalada sem `pai_notify` falha.

## Fora de escopo

- Resolver os gaps detectados. O validator deve detectar; os outros planos corrigem.
- Escanear dados pessoais em `PAI/USER` para conteudo, exceto paths/promessas operacionais.
