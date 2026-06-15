# Plano 08 - Memory e Knowledge Runtime

## Objetivo

Definir e implementar a camada minima de memoria/knowledge que o port OpenCode deve suportar agora. O sistema ja tem estado de sessao e learning basico; o gap e a memoria longa/retrieval/knowledge graph prometida por Algorithm e skills.

## Estado atual verificado no codigo

Repo atual:

- `find PAI/MEMORY -maxdepth 3 -type f | wc -l` retorna `0`.
- `opencode/install.sh:131` cria `MEMORY/{STATE,WORK,KNOWLEDGE,LEARNING,RESEARCH}`.
- `opencode/bin/validate-pai-installation.sh:106-142` valida diretorios de memory.

Runtime ja implementado:

- `opencode/plugins/pai-hooks.js:452-458` persiste classificacao por sessao.
- `opencode/plugins/pai-hooks.js:624-690` cria/atualiza `work.json` e `current-work-<session>.json`.
- `opencode/plugins/lib/pai-hooks.lib.js:999-1008` le/escreve `work.json`.
- `opencode/plugins/lib/pai-hooks.lib.js:1167-1265` sincroniza ISA para registry.
- `opencode/plugins/pai-hooks.js:1438-1490` captura ratings/praise e learning signals.

Promessas ainda nao cobertas:

- `skills/Knowledge/SKILL.md` promete Knowledge Archive com `KnowledgeGraph.ts`, `MemoryRetriever.ts`, `SessionHarvester.ts`.
- `PAI/ALGORITHM/v6.3.0.md:347` manda buscar `MEMORY/KNOWLEDGE` quando houver trabalho previo provavel.
- `PAI/DOCUMENTATION/Memory/MemorySystem.md` descreve retrievers/harvesters que nao existem no port.

## Diferenca operacional

O port tem memoria operacional de sessao. Ele nao tem memoria semantica forte equivalente ao original:

- sem BM25/semantic retrieval;
- sem graph traversal;
- sem harvest de sessoes;
- sem consolidation jobs funcionais.

Isso e aceitavel se declarado, mas nao se Knowledge skill e Algorithm continuarem tratando como disponivel.

## Desenho OpenCode-native

Separar memoria em tres niveis:

### Nivel 1 - Runtime state

Ja existe:

- `MEMORY/STATE/work.json`;
- `current-work-<session>.json`;
- observability JSONL;
- learning signals basicos.

### Nivel 2 - Knowledge read-only

Implementar primeiro:

- `PAI/TOOLS/MemoryRetriever.ts`: busca lexical/BM25-lite em `MEMORY/KNOWLEDGE`;
- `PAI/TOOLS/KnowledgeGraph.ts`: stats, related, traverse, find;
- sem LLM obrigatorio.

### Nivel 3 - Harvest/consolidation

Depois:

- `SessionHarvester.ts`;
- `KnowledgeHarvester.ts`;
- `LearningPatternSynthesis.ts`.

## Plano de implementacao

### Fase 1 - Manifesto de memoria

Criar `PAI/MEMORY/README.md` ou `PAI/MEMORY/manifest.json` explicando:

- quais diretorios sao runtime-created;
- quais arquivos sao opcionais;
- quais tools consomem cada area.

### Fase 2 - Read-only retrieval

Implementar `MemoryRetriever.ts`:

- input: query, `--top`, `--budget`, `--raw`;
- fontes: markdown em `MEMORY/KNOWLEDGE`, talvez `MEMORY/LEARNING`;
- output: texto/JSON;
- sem writes.

Implementar `KnowledgeGraph.ts`:

- parse frontmatter `related`, wikilinks, tags;
- comandos `stats`, `find`, `related`, `traverse`;
- output JSON opcional.

### Fase 3 - Integrar Algorithm/Knowledge skill

Atualizar:

- `skills/Knowledge/SKILL.md`;
- `PAI/ALGORITHM/v6.3.x.md`;
- docs de memory.

Regra: se retrieval nao achar arquivo ou knowledge vazio, retornar "empty archive", nao falhar.

### Fase 4 - Harvesters

Somente apos read-only estar estavel:

- `SessionHarvester.ts --recent N --dry-run`;
- `KnowledgeHarvester.ts index`;
- testes com fixtures.

Status executado em 2026-06-15:

- `SessionHarvester.ts` implementado com `--recent`, `--all`, `--session`, `--sessions-dir`, `--dry-run`, `--mine` e `--json`;
- `KnowledgeHarvester.ts` implementado com `status`, `validate`, `index` e `harvest`;
- `--mine` escreve apenas candidatos em `KNOWLEDGE/_harvest-queue/`;
- `harvest` consome fila/work/research de forma limitada e atualiza indexes;
- testes em `opencode/tests/harvester-tools.test.ts`.

## Criterios de aceite

- `MemoryRetriever.ts` e `KnowledgeGraph.ts` existem ou Knowledge skill declara capacidade parcial.
- Testes cobrem knowledge vazio, note com frontmatter e note com wikilink.
- Algorithm nao promete consolidation/harvest automatico fora do contrato atual dos tools.
- `PULSE.toml` nao agenda jobs que chamam helpers ausentes.

## Fora de escopo

- Cloud KV sync.
- LLM compression obrigatoria.
- Dashboard/wikis visuais.
- Migrar dados pessoais reais para o repo.
