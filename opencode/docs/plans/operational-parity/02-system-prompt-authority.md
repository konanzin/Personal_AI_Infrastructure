# Plano 02 - Autoridade Constitucional OpenCode-native

## Objetivo

Restaurar a funcao operacional do antigo `PAI_SYSTEM_PROMPT.md` sem depender do mecanismo Claude Code `--append-system-prompt-file`. O port deve ter uma camada de autoridade clara, carregada pelo OpenCode, verificavel em teste e coerente com `PAI/CLAUDE.md`.

## Estado atual verificado no codigo

No original:

- `git show origin/main:Releases/v5.0.0/.claude/PAI/PAI_SYSTEM_PROMPT.md` retorna 187 linhas.
- O arquivo continha regras constitucionais, seguranca, "confidence requires source", self-healing infrastructure e regras operacionais.
- `origin/main:Releases/v5.0.0/.claude/settings.json` definia o ambiente Claude Code, enquanto o launcher original podia anexar prompt sistemico.

No port:

- `PAI/PAI_SYSTEM_PROMPT.md` nao existe.
- `PAI/CLAUDE.md:14`, `PAI/CLAUDE.md:72` e `PAI/CLAUDE.md:82` ainda dizem que ele existe e e carregado.
- `opencode/config/opencode.jsonc.template:18` carrega `~/.config/opencode/PAI/CLAUDE.md` como instruction.
- `opencode/plugins/pai-hooks.js:197-228` injeta `CLAUDE.md` dentro do system context em runtime.

## Diferenca operacional

Claude Code tinha uma separacao mais forte entre:

- prompt constitucional;
- `CLAUDE.md` operacional;
- hooks configurados em `settings.json`.

OpenCode, neste port, tem:

- `instructions` no config;
- prompt dos agentes primarios;
- `experimental.chat.system.transform`;
- plugin tool definitions.

Se mantivermos o nome `PAI_SYSTEM_PROMPT.md`, ele precisa ser realmente carregado pelo plugin ou pelo config. Se nao for carregado, toda referencia a ele deve sumir.

## Decisao recomendada

Criar uma camada nova chamada `PAI/RUNTIME_CONSTITUTION.md`, nao `PAI_SYSTEM_PROMPT.md`.

Motivo:

- evita fingir paridade com a flag Claude Code;
- deixa explicito que a autoridade vem do runtime OpenCode;
- preserva a funcao constitucional sem herdar billing/OAuth/Claude-specific rules cegamente.

## Desenho OpenCode-native

### Arquivo novo

`PAI/RUNTIME_CONSTITUTION.md`

Conteudo minimo:

- PAI identity and purpose;
- source-grounding/confidence rule;
- external content security protocol;
- operational safety rules that are provider-neutral;
- OpenCode-native memory/infrastructure rule;
- explicit out-of-scope notes for Claude Code-only behaviors.

### Carregamento

Alterar `opencode/plugins/pai-hooks.js`:

- ler `RUNTIME_CONSTITUTION.md` em `buildPAISystemContext`;
- injetar antes de `CLAUDE.md`;
- no lean/mobile profile, injetar uma versao resumida ou os primeiros blocos marcados como `mobile-safe`.

Nao depender de `opencode.jsonc` para carregar esse arquivo diretamente, porque o plugin ja precisa construir contexto por perfil (`build` vs `build-mobile`).

## Plano de implementacao

### Fase 1 - Extrair regras universais

Usar o original como materia-prima, mas nao copiar regras Claude-specific:

- manter: confidence requires source, external content read-only, STOP/REPORT, self-healing infrastructure.
- adaptar: memory paths para `~/.config/opencode/PAI`.
- remover ou reescrever: `claude --bare`, OAuth Anthropic, Claude harness auto-memory, `--append-system-prompt-file`.

### Fase 2 - Carregar no plugin

Editar:

- `opencode/plugins/pai-hooks.js`;
- possivelmente `opencode/plugins/lib/pai-hooks.lib.js` se houver helper de leitura compartilhavel.

Adicionar teste em `opencode/tests/plugin-integration.test.ts`:

- system transform inclui marcador de `RUNTIME_CONSTITUTION`;
- lean profile inclui marcador constitucional minimo;
- se arquivo ausente, plugin nao quebra, mas loga warning e injeta fallback curto.

### Fase 3 - Ajustar config e install

Editar:

- `opencode/install.sh` para copiar `RUNTIME_CONSTITUTION.md`;
- `opencode/bin/validate-pai-installation.sh` para validar existencia e carregamento;
- `opencode/bin/test-behavioral.sh` para procurar marcador no plugin/test fixture.

### Fase 4 - Remover promessas antigas

Trocar referencias a `PAI_SYSTEM_PROMPT.md` por:

- `RUNTIME_CONSTITUTION.md`, quando for regra ativa;
- `legacy Claude Code`, quando for explicacao historica;
- remocao, quando nao agrega.

## Criterios de aceite

- `test -f PAI/RUNTIME_CONSTITUTION.md` passa.
- `rg -n "PAI_SYSTEM_PROMPT|--append-system-prompt-file" PAI opencode skills` retorna apenas mencoes explicitamente marcadas como legado ou nenhuma.
- `opencode/tests/plugin-integration.test.ts` prova que o system transform injeta a constituicao.
- `opencode/bin/validate-pai-installation.sh` falha se o arquivo nao estiver instalado ou se o plugin nao o ler.

## Fora de escopo

- Recriar o launcher Claude Code `pai.ts`.
- Usar `--append-system-prompt-file`.
- Reintroduzir regras de billing Anthropic como regra universal do port OpenCode.
