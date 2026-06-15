# Plano 09 - Installer, Config e Higiene do Estado Instalado

Status: executado. O instalador atual copia `PAI/TOOLS` com manifest/helpers, arquiva artefatos gerados stale e valida contratos de runtime em `--check`.

## Objetivo

Garantir que instalar ou atualizar o port produza um estado em `~/.config/opencode` que reflita o repo atual, sem sobras antigas e sem drift de config. A instalacao deve ser reparavel, auditavel e segura para dados de usuario.

## Estado verificado antes da execucao

Installer atual:

- `opencode/install.sh:128-138` cria diretorios.
- `opencode/install.sh:142-157` instala plugin e libs.
- `opencode/install.sh:161-175` remove agentes aposentados e copia agentes atuais.
- `opencode/install.sh:188-206` copia skills, mas nao remove skills stale.
- `opencode/install.sh:218-235` copiava PAI core, incluindo `TOOLS` vazio.
- `opencode/install.sh:315-337` patcha paths `~/.claude/` nas copias instaladas.
- `opencode/install.sh:349-354` gera config e transforma plugin path para absoluto.

Config template atual:

- `opencode/config/opencode.jsonc.template:20-29` define `build` e `build-mobile` com exigencia de `pai_notify`.
- `opencode/config/opencode.jsonc.template:31-87` define permissoes OpenCode.
- `opencode/config/opencode.jsonc.template:88-120` registra comandos.

Estado instalado observado:

- `~/.config/opencode/skills` tem 48 diretorios; repo tem 45.
- Extras: `interceptor-browser`, `interceptor-macos`, `interceptor-repo`.
- `~/.config/opencode/opencode.jsonc` observado so tinha `pai_notify` no `build-mobile` antigo como `COMPLETED`, nao no formato atual do template.

## Diferenca operacional

O repo pode estar correto, mas o usuario roda uma instalacao parcialmente antiga. Isso distorce todos os testes manuais. O installer precisa conseguir dizer:

- o que esta gerado;
- o que e dado do usuario;
- o que e sobra antiga;
- o que foi preservado de proposito.

## Desenho OpenCode-native

Adicionar um modelo de instalacao declarativo:

- `opencode/install-manifest.json`: lista agentes, skills, comandos, plugins, PAI core files esperados.
- `install.sh --check`: nao altera, so compara.
- `install.sh --repair`: remove sobras geradas conhecidas e regenera config.
- `install.sh --preserve-user`: default para `PAI/USER`, `PAI/MEMORY`, `.env`.

## Plano de implementacao

### Fase 1 - Manifesto de artefatos instalados

Gerar ou manter:

```json
{
  "agents": ["Algorithm.md", "Anvil.md"],
  "retired_agents": ["BrowserAgent.md", "QATester.md", "UIReviewer.md"],
  "skills": ["ISA", "Telos"],
  "retired_skills": ["interceptor-browser", "interceptor-macos", "interceptor-repo"],
  "commands": ["context-search.md", "cs.md", "pu.md"]
}
```

### Fase 2 - Cleanup de skills stale

Antes de copiar skills:

- comparar dirs instalados com manifesto;
- mover sobras para backup ou remover se forem retired conhecidos;
- nunca remover dirs user-owned sem manifest/backup.

### Fase 3 - Config drift detection

No validator:

- comparar prompt de `build` e `build-mobile` instalado contra template normalizado;
- verificar `pai_notify` nos dois agentes primarios;
- verificar plugin path absoluto unico;
- verificar comandos esperados.

### Fase 4 - Paths patch mais abrangente

Hoje patch pega `.claude/` e `".claude"`. Expandir checks para:

- `~/.claude` sem slash;
- `$HOME/.claude`;
- `${HOME}/.claude`;
- imports relativos quebrados para `PAI/TOOLS` inexistente.

Nao necessariamente patchar tudo no repo; mas instalado deve passar.

### Fase 5 - Relatorio pos-install

Ao final, imprimir:

- agentes instalados/removidos;
- skills instaladas/removidas;
- config regenerated;
- warnings de helpers ausentes;
- proximo comando de validate.

## Criterios de aceite

- Reinstalar remove ou arquiva `interceptor-browser`, `interceptor-macos`, `interceptor-repo`.
- `~/.config/opencode/opencode.jsonc` contem `pai_notify` nos prompts `build` e `build-mobile`.
- Validator falha se config instalada divergir do template em campos gerados.
- Dados `PAI/USER`, `PAI/MEMORY` e `.env` sao preservados.
- `install.sh --check` retorna non-zero quando ha drift.

## Fora de escopo

- Gerenciar secrets reais.
- Apagar dados de usuario.
- Sincronizar config de outros OpenCode profiles nao gerados pelo PAI.
