# Baseline de medição — branch `bitter`

Medido em 2026-07-05, árvore = `dori@ef0eb55` + mudanças não-commitadas da rodada de calibração em andamento (frontmatter de permissões dos agentes, TrustBoundaryActions, monitor-security-events). Toda medição pós-workstream compara contra ESTA tabela, no mesmo ambiente.

## Números

| Métrica | Comando | Valor |
|---|---|---|
| Suíte completa | `cd opencode && bun test` | **504 pass / 1 skip / 0 fail** (505 testes, 28 arquivos, 1468 expects) |
| Heurística do classificador — mode | `bun bin/eval-classifier-golden.js --heuristic` | **38/56 (68%)** |
| Heurística do classificador — tier | idem | **17/24 (71%)** |
| Fontes da heurística | idem (`--json`) | heuristic 44 · fail-safe 12 · flaky 0 |

## O que cada workstream NÃO pode mover

- **Piso de segurança:** 100% dos casos `deny` do corpus (`security-corpus.test.ts`, `floor-liveness.test.ts`) continuam negando. Qualquer queda = rollback imediato.
- **Boundary NATIVE/ALGORITHM (O3):** golden do classificador com LLM está em ~98% (ver HARNESS_QUALITY.md). O eval com LLM é on-demand (custa chamadas; rodar com a config de produção do classificador — `bun bin/eval-classifier-golden.js --runs 3`) e só é obrigatório para workstreams que tocam o classificador (W1.2 toca só a PROSA do contexto, não a classificação; medir mesmo assim antes de mesclar em dori).
- **Suíte:** 0 fail se mantém. Testes que assertavam o comportamento antigo (ex.: deny em prosa) são ATUALIZADOS no mesmo commit do workstream, com justificativa no dossiê — nunca silenciosamente.

## Rito de medição por workstream

1. Implementar o workstream em um commit isolado (só os arquivos dele + seus evals de guarda).
2. `bun test` — comparar com esta tabela.
3. Se o workstream toca classificador/routing: rodar o golden heurístico (grátis) e registrar.
4. Anotar o resultado na linha do workstream em `REGISTER.md`.
5. Regrediu → `git revert` do commit único; o dossiê ganha a anotação do porquê.
