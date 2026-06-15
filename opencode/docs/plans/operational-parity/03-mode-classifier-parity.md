# Plano 03 - Classificador de Modo/Tier

## Objetivo

Levar o classificador atual a paridade operacional honesta: ele deve continuar OpenCode-native, mas Algorithm e prompts precisam refletir exatamente como ele funciona. A prioridade nao e voltar para Sonnet obrigatorio; e ter classificacao explicita, testada, observavel e conservadora contra sub-escalacao.

## Estado atual verificado no codigo

O port ja tem classificador implementado:

- `opencode/plugins/lib/mode-classifier.lib.js:1-17` declara interface provider-agnostic e fontes `heuristic`, `override`, `fail-safe`, `llm`.
- `opencode/plugins/lib/mode-classifier.lib.js:37-72` define padroes MINIMAL/NATIVE/ALGORITHM.
- `opencode/plugins/lib/mode-classifier.lib.js:282-353` implementa `classifyPrompt`, override `/e1`-`/e5` e fail-safe ALGORITHM E3.
- `opencode/plugins/pai-hooks.js:389-535` roda o classificador em `chat.message`, persiste em `current-work-<session>.json` e em `mode-classifier.jsonl`.
- `opencode/plugins/pai-hooks.js:488-502` grava telemetry com mode, tier, source, confidence, latency e hash.

O Algorithm ainda descreve outra realidade:

- `PAI/ALGORITHM/v6.3.0.md:73-82` diz Sonnet em `UserPromptSubmit`, sem regex fallback e sem model judgment.
- `PAI/ALGORITHM/v6.3.0.md:97-101` fala timeout de 25s e Sonnet latency.

Baseline original verificado:

- `PromptProcessing.hook.ts` do original roda em `UserPromptSubmit`.
- Ele emitia `additionalContext` com `MODE` e `TIER`.
- O prompt original tinha uma tarefa explicita de classificacao de modo/tier.

## Diferenca operacional

OpenCode nao esta usando o hook Claude Code `UserPromptSubmit`. O port usa `chat.message` e injeta contexto depois via system transform. Isso e aceitavel se:

- classificacao chega antes da resposta substantiva;
- estado persiste por sessao;
- transform injeta a classificacao;
- falhas caem em ALGORITHM E3;
- docs nao prometem Sonnet obrigatorio.

## Desenho OpenCode-native

Manter tres camadas:

1. Override explicito `/e1`-`/e5`.
2. Heuristica local deterministica por padrao.
3. LLM opcional por env, provider-agnostic, sem bloquear uso headless.

Configuracao via env:

- `PAI_CLASSIFIER_USE_LLM=true`;
- `PAI_CLASSIFIER_MODEL=<model>`;
- `PAI_CLASSIFIER_TIMEOUT_MS=<ms>`;
- `PAI_CLASSIFIER_ENDPOINT=<endpoint>` se necessario.

O executor deve tratar a classificacao persistida como input forte, mas ainda pode escalar quando o contexto da conversa torna um "sim" ou "faz" dependente de uma proposta multi-step anterior.

## Plano de implementacao

### Fase 1 - Corrigir a doutrina

Atualizar `PAI/ALGORITHM`:

- trocar "Sonnet at UserPromptSubmit" por "OpenCode classifier at chat.message";
- documentar fontes: `override`, `heuristic`, `llm`, `fail-safe`;
- documentar que heuristica e default por custo/latencia/VPS;
- manter ALGORITHM E3 como fail-safe.

### Fase 2 - Fortalecer fixtures de classificacao

Expandir `opencode/tests/mode-classifier.test.ts` com casos de drift real:

- "yes/do it" apos contexto multi-step: classificacao isolada pode ser baixa, mas precisa flag `context_sensitive` ou ser escalada no executor;
- "me explica X" curto: NATIVE;
- "faz uma auditoria completa" em portugues: ALGORITHM E4/E5;
- "preciso de um plano em arquivos" em portugues: ALGORITHM;
- PAI-affecting work sempre ALGORITHM E3+.

### Fase 3 - Medir divergencia

Adicionar fixtures JSONL com prompts historicos e expected mode/tier:

`opencode/tests/fixtures/mode-classifier-cases.jsonl`

Campos:

- `prompt`;
- `expected_mode`;
- `min_tier`;
- `reason`;
- `language`;
- `context_sensitive`.

### Fase 4 - Melhorar LLM opcional sem virar dependencia

Implementar contrato de provider mais explicito em `classifyPromptWithLLM`:

- timeout duro;
- schema normalization;
- fallback para heuristica;
- telemetry diferenciando `source: llm` e `source: heuristic_after_llm_error`.

## Criterios de aceite

- Algorithm nao contem mais "No regex fallback" como regra absoluta.
- Algorithm nao diz que Sonnet e sempre usado.
- `bun test opencode/tests/mode-classifier.test.ts` cobre portugues e casos PAI-affecting.
- `mode-classifier.jsonl` continua sendo escrito pelo plugin.
- `test-behavioral.sh` valida que `chat.message` chama `classifyPrompt` e que o fail-safe E3 existe.

## Fora de escopo

- Recriar Claude Code `additionalContext` literalmente.
- Tornar LLM obrigatorio para todo prompt.
- Rebaixar o fail-safe para NATIVE quando houver duvida.
