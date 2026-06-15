# Planos de Paridade Operacional OpenCode

Data: 2026-06-14

Este conjunto de planos transforma a auditoria `PAI_ORIGINAL_TO_OPENCODE_PARITY_AUDIT.md` em frentes de implementacao. O objetivo nao e copiar Claude Code literalmente. O objetivo e paridade operacional: quando o PAI promete uma capacidade, ela deve existir no OpenCode de forma nativa, testavel e honesta.

## Metodo

Cada plano parte de evidencia de codigo, nao de documentacao declarativa:

- Baseline original: `origin/main:Releases/v5.0.0/.claude`.
- Port atual: branch local `dori`.
- Estado instalado observado: `~/.config/opencode`.
- Evidencia local usada: `PAI/CLAUDE.md`, `PAI/ALGORITHM/v6.3.0.md`, `opencode/plugins/pai-hooks.js`, `opencode/plugins/lib/*.js`, `opencode/config/opencode.jsonc.template`, `opencode/install.sh`, `opencode/bin/*`, `opencode/agents`, `skills`, `PAI/PULSE/PULSE.toml`.

Comandos-chave verificados durante a preparacao:

```bash
find PAI/TOOLS -maxdepth 3 -type f | wc -l
find PAI/MEMORY -maxdepth 3 -type f | wc -l
find opencode/agents -maxdepth 1 -type f -name '*.md' | wc -l
find skills -maxdepth 1 -mindepth 1 -type d | wc -l
git ls-tree -r --name-only origin/main:Releases/v5.0.0/.claude/PAI/TOOLS | wc -l
git show origin/main:Releases/v5.0.0/.claude/settings.json
```

Resultados relevantes:

- `PAI/TOOLS`: manifest + 10 helpers implementados no port atual; 86 arquivos no original.
- `PAI/MEMORY`: 0 arquivos versionados no port; diretorios sao criados em runtime/installer.
- Agentes OpenCode: 15.
- Skills do repo: 46 diretorios.
- Skills instaladas apos repair: 46 diretorios, sem sobras geradas.

## Principio de implementacao

Para cada ponto:

1. Se a capacidade e essencial para comportamento do PAI, implementar no plugin/config/testes OpenCode.
2. Se a capacidade era acoplada a Claude Code ou Pulse desktop, adaptar para evento/plugin/config OpenCode ou declarar fora de escopo.
3. Se a capacidade nao sera implementada agora, remover ou rebaixar qualquer prompt/doc/agente que a trate como disponivel.
4. O validator deve falhar quando uma promessa operacional aponta para arquivo, hook, tool ou evento inexistente.

## Arquivos

P0 - Coerencia de promessas:

- `01-port-coherence-algorithm-claude.md`
- `02-system-prompt-authority.md`
- `10-validators-promise-integrity.md`

P1 - Runtime operacional:

- `03-mode-classifier-parity.md`
- `04-runtime-hooks-and-state.md`
- `05-tools-minimal-runtime.md`
- `06-security-pipeline-parity.md`

P2 - Superficies consumidoras:

- `07-agents-skills-runtime-alignment.md`
- `08-memory-knowledge-runtime.md`
- `09-installer-config-hygiene.md`

P3 - Escopo e observability:

- `11-pulse-mobile-scope.md`
- `12-observability-doc-integrity.md`

## Ordem recomendada

1. Fazer o Port Coherence Pass (`01`, `02`, `10`) para parar de prometer o que nao existe.
2. Implementar seguranca e hooks stateful (`04`, `06`), porque afetam confianca do runtime.
3. Decidir o subset minimo de `PAI/TOOLS` (`05`), porque isso destrava Algorithm, agentes e skills.
4. Alinhar agentes/skills e memoria (`07`, `08`).
5. Fechar installer/config e drift instalado (`09`).
6. Limpar escopo Pulse/mobile e observability/doc integrity (`11`, `12`).

## Definicao de pronto para o conjunto

- Cada promessa em prompt/agente/skill/doc tem uma das tres situacoes: implementada, fallback explicito, ou marcada fora de escopo.
- `bun test` em `opencode/` continua verde.
- `opencode/bin/test-behavioral.sh` e `opencode/bin/validate-pai-installation.sh` cobrem promessas criticas, nao apenas existencia de diretorios.
- Instalar de novo em `~/.config/opencode` nao deixa skills/agentes/config stale.
