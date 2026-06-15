# Plano 07 - Agentes e Skills Alinhados ao Runtime

## Objetivo

Garantir que agentes e skills instalados no OpenCode nao prometam executar fluxos que dependem de helpers ausentes, paths Claude Code ou agentes removidos. Onde a decisao for manter uma capacidade indisponivel, o fallback deve ser explicito e testado.

## Estado atual verificado no codigo

Agentes:

- `find opencode/agents -maxdepth 1 -type f -name '*.md' | wc -l` retorna 15.
- `opencode/bin/validate-pai-installation.sh:433-452` espera esses 15 e garante que `BrowserAgent`, `QATester`, `UIReviewer` estejam ausentes.
- `opencode/bin/validate-pai-installation.sh:457-464` exige `mode: subagent`.

Agentes com helpers ausentes:

- `opencode/agents/Forge.md:46-53` verifica `ForgeProgress.ts` e para com `unavailable`.
- `opencode/agents/Cato.md:21-31` verifica `CrossVendorAudit.ts` e para com `skipped`.
- `opencode/agents/Arthur.md:19-30` verifica `Arthur.ts` e nao inventa decisao.
- `opencode/agents/Anvil.md:53-58` verifica `AnvilProgress.ts` e para com `unavailable`.

Skills:

- `find skills -maxdepth 1 -mindepth 1 -type d | wc -l` retorna 45.
- `skills/AudioEditor/Tools/Analyze.ts:15` importa `../../../PAI/TOOLS/Inference.ts`.
- `skills/Evals/Tools/PAIAgentAdapter.ts:10` importa `../../../PAI/TOOLS/Inference.ts`.
- `skills/Migrate/SKILL.md:60-111` chama `~/.claude/PAI/TOOLS/MigrateScan.ts` e `MigrateApprove.ts`.
- `skills/Knowledge/SKILL.md` chama `KnowledgeGraph.ts`, `MemoryRetriever.ts` e `SessionHarvester.ts`.
- `skills/Art/Workflows/*` ainda chama `~/.claude/PAI/TOOLS/RemoveBg.ts`.

Instalacao observada:

- `~/.config/opencode/skills` tem 48 diretorios, com sobras `interceptor-browser`, `interceptor-macos`, `interceptor-repo`.

## Diferenca operacional

Agentes principais estao melhor que varias skills: eles ja declaram fallback quando helper falta. Algumas skills, porem, importam ou chamam helpers inexistentes diretamente. Isso significa que o runtime pode falhar so quando a skill e usada, apesar do validator geral passar.

## Desenho OpenCode-native

Criar um manifesto de capacidades por agente/skill:

```json
{
  "Forge": {
    "requires": ["PAI/TOOLS/ForgeProgress.ts", "~/.bun/bin/codex"],
    "fallback": "unavailable"
  },
  "Knowledge": {
    "requires": ["PAI/TOOLS/KnowledgeGraph.ts", "PAI/TOOLS/MemoryRetriever.ts"],
    "fallback": "partial_search_only"
  }
}
```

O manifesto deve dirigir:

- validator;
- docs;
- install cleanup;
- decisao de quais tools portar.

## Plano de implementacao

### Fase 1 - Classificar consumidores

Gerar uma tabela:

- agent/skill;
- arquivos que chama;
- helper requerido;
- status do helper;
- fallback existente;
- acao: portar, rebaixar, remover, legacy.

Usar `rg` e testes, nao leitura manual solta:

```bash
rg -n "PAI/TOOLS|TOOLS/|~/.claude|Inference.ts|ForgeProgress|CrossVendorAudit|RemoveBg|MigrateScan|KnowledgeGraph|MemoryRetriever" opencode/agents skills
```

### Fase 2 - Corrigir imports TypeScript quebrados

Priorizar arquivos que importam helpers inexistentes:

- `skills/AudioEditor/Tools/Analyze.ts`;
- `skills/Evals/Tools/PAIAgentAdapter.ts`;
- model-based graders em `skills/Evals/Graders`.

Opcao A: portar `Inference.ts`.

Opcao B: trocar para adapter OpenCode-native e marcar LLM graders indisponiveis sem adapter.

### Fase 3 - Corrigir workflows instruction-only

Para workflows que so citam paths:

- substituir `~/.claude` por path OpenCode no repo ou garantir patch instalado;
- se helper nao existir, adicionar bloco "Capability unavailable until tool X exists";
- remover voice curls obrigatorios se broker nao estiver garantido.

### Fase 4 - Revalidar agentes removidos

Manter:

- `BrowserAgent`;
- `QATester`;
- `UIReviewer`;

como removidos se a decisao continua ser Interceptor/flows. Garantir que nenhum prompt ainda mande invocar esses agentes.

### Fase 5 - Installer cleanup

Integrar com plano 09 para remover skills stale instaladas e validar que a lista instalada e igual ao manifesto.

## Criterios de aceite

- Nenhum arquivo TS em `skills` importa `PAI/TOOLS/*.ts` inexistente.
- Toda chamada textual a `PAI/TOOLS/*.ts` tem helper real ou fallback explicito.
- Nenhuma skill instalada extra fica fora do manifesto.
- Nenhuma referencia operacional a `BrowserAgent`, `QATester` ou `UIReviewer` permanece ativa.
- `validate-pai-installation.sh` falha se skill/agente prometer helper ausente sem fallback.

## Fora de escopo

- Reescrever todas as skills.
- Portar tools opcionais so porque uma workflow antiga menciona.
- Reintroduzir agentes removidos sem uma decisao explicita de produto.
