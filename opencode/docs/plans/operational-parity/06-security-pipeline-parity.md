# Plano 06 - Seguranca: SecurityPipeline, Read Guard, SmartApprover e Patterns

Status: parcialmente executado em 2026-06-15.

Implementado:

- `inspectReadPath(filePath)` em `opencode/plugins/lib/pai-hooks.lib.js`.
- `inspectWriteContent(filePath, content)` para containment minimo de segredo de alta confianca.
- Bash confirm para leituras de arquivos de credenciais (`cat .env`, `grep .env`, chaves SSH etc.).
- Integracao em `tool.execute.before` para `read`, `glob`, `grep`, `write`, `edit`, `multiedit` e `bash`.
- Integracao em `permission.asked`/`permission.ask` para bash/read/write com deny ou `permission_needed`.
- Testes unitarios, integracao de plugin, behavioral e E2E.

Ainda fora/deferido:

- Loader externo completo de `patterns.yaml`/`patterns.jsonc`.
- SmartApprover LLM/cacheado.
- UI/CRUD de seguranca.

## Objetivo

Fechar o gap de seguranca mais importante do port: a protecao atual e boa para bash/write/edit, mas nao e equivalente ao original em `Read`, SmartApprover, patterns configuraveis e containment.

## Estado atual verificado no codigo

Baseline original:

- `origin/main:Releases/v5.0.0/.claude/settings.json:85-134` registra `SecurityPipeline` tambem para `Read`.
- `SmartApprover.hook.ts` original classifica `Read`, `Glob`, `Grep` como read e `Write/Edit/MultiEdit` como write.
- `ContainmentGuard.hook.ts` original bloqueia writes de identidade fora das zonas permitidas.
- Docs originais mencionam `USER/SECURITY/PATTERNS.yaml`.

Port atual:

- `opencode/plugins/lib/pai-hooks.lib.js:259-284` tem padroes hardcoded para bash bloqueado/confirmado.
- `opencode/plugins/lib/pai-hooks.lib.js:292-318` tem paths sensiveis para write/delete.
- `opencode/plugins/lib/pai-hooks.lib.js:361-404` implementa `inspectBashCommand`.
- `opencode/plugins/lib/pai-hooks.lib.js:406-430` implementa `inspectWritePath`.
- `opencode/plugins/pai-hooks.js:807-925` aplica checks para bash, write/edit/multiedit e delete via bash.
- `opencode/config/opencode.jsonc.template:31-45` permite leituras em varios roots, mas isso e config permissiva, nao inspector semantico.
- `rg` por `tool === 'read'`/`inspectRead` nao encontra enforcement equivalente no plugin.

## Diferenca operacional

O port bloqueia comandos perigosos e writes sensiveis, mas nao inspeciona leituras sensiveis no mesmo nivel. Isso importa porque leitura de segredos e exfiltracao podem acontecer sem write.

Tambem ha diferenca de governanca:

- original tinha patterns configuraveis;
- port usa constantes hardcoded;
- original tinha SmartApprover/caches;
- port tem `permission.asked`, mas ainda nao e um SmartApprover completo.

## Desenho OpenCode-native

### ReadGuard

Adicionar `inspectReadPath(filePath)` em `pai-hooks.lib.js`.

Politica inicial:

- deny: `/etc/shadow`, private key material, credential stores explicitos;
- require approval: `.env`, `.npmrc`, `.pypirc`, cloud credentials, SSH private keys, PAI user credentials;
- allow: repo files e PAI docs comuns.

### SmartApprover rule-based

Implementar em `permission.asked`/`permission.ask`:

- auto-allow reads claramente reversiveis e workspace-local;
- require approval para writes, shell perigoso e paths sensiveis;
- deny para zero-access;
- sem LLM no caminho critico.

### Patterns configuraveis

Adicionar config simples:

- preferencia: `PAI/USER/SECURITY/patterns.jsonc` ou yaml se o repo ja tiver parser confiavel;
- fallback hardcoded atual se arquivo ausente;
- validator garante que config malformada nao derruba plugin.

### Containment minimo

Adicionar write scanner para impedir vazamento de identidade/secrets para fora de zonas publicas quando o arquivo destino estiver fora de `PAI/USER`, `PAI/MEMORY`, `.env` protegido etc.

## Plano de implementacao

### Fase 1 - ReadGuard

Editar:

- `opencode/plugins/lib/pai-hooks.lib.js`;
- `opencode/plugins/pai-hooks.js`;
- `opencode/tests/security-pipeline.test.ts`;
- `opencode/tests/plugin-integration.test.ts`.

Casos:

- read `/etc/shadow` -> deny;
- read `~/.ssh/id_ed25519` -> require approval ou deny;
- read repo source file -> allow;
- read `.env` -> require approval.

### Fase 2 - SmartApprover

Completar `permission.asked`:

- normalizar tool names OpenCode (`read`, `bash`, `write`, `edit`, etc.);
- classificar read/write;
- emitir `permission_needed` notification quando exigir usuario;
- logar em `security-events.jsonl`.

### Fase 3 - Patterns externos

Implementar loader:

- `loadSecurityPolicy()`;
- merge hardcoded defaults + user overrides;
- schema minimo;
- telemetry quando policy nao carrega.

### Fase 4 - Containment minimo

Adicionar inspector:

- detectar strings sensiveis conhecidas;
- bloquear write para paths fora de zonas permitidas;
- comecar por deny apenas para padroes de alta confianca.

## Criterios de aceite

- Teste prova que `read` sensivel e interceptado.
- Teste prova que write atual continua bloqueando `/etc/passwd`.
- Teste prova que bash `curl | bash` continua bloqueado.
- `permission.ask` continua aliasado para `permission.asked`.
- Security policy malformada gera warning e fallback, nao crash.
- Docs de Security nao prometem dashboard/CRUD se isso nao for implementado.

## Fora de escopo

- UI de edicao de patterns.
- LLM semantic security no caminho de permissao.
- Auto-approve agressivo que reduza controle do usuario em operacoes irreversiveis.
