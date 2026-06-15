# Plano 12 - Observability e DocIntegrity

## Objetivo

Fechar a lacuna entre observabilidade runtime e integridade das promessas documentadas. O port ja tem boa base JSONL; falta transformar isso em contrato e adicionar checks que detectem docs/prompts divergentes antes que o agente acredite em infraestrutura inexistente.

## Estado atual verificado no codigo

Observability atual:

- `opencode/plugins/pai-hooks.js:488-502` grava `mode-classifier.jsonl`.
- `opencode/plugins/pai-hooks.js:856-865` loga security events.
- `opencode/plugins/pai-hooks.js:1327-1342` loga `state_sync`.
- `opencode/plugins/pai-hooks.js:1153-1169` detecta sequencias de falha de tool e emite notificacao.
- `opencode/plugins/lib/pai-hooks.lib.js:176-194` define niveis/eventos de notificacao.
- `opencode/docs/NOTIFICATIONS_STREAM.md` documenta contrato v1.
- `opencode/tests/e2e-runtime` ja tem cenarios runtime.

Gap:

- `DocIntegrity.hook.ts` existia no original, mas nao ha equivalente forte no port.
- Validadores ainda nao verificam que docs/prompts prometem apenas runtime real.
- Schemas JSONL nao sao validados de forma central.

## Diferenca operacional

O original tinha mais hooks dispersos e Pulse visual. O port deve usar observability headless:

- JSONL typed streams;
- tests de schema;
- doc integrity scanner;
- contratos para mobile/broker.

## Desenho OpenCode-native

### Event contracts

Criar schemas simples em:

- `opencode/schemas/mode-classifier-event.schema.json`;
- `opencode/schemas/security-event.schema.json`;
- `opencode/schemas/session-event.schema.json`;
- `opencode/schemas/notification-event.schema.json`.

Sem dependencia pesada se possivel; validar com JS simples em testes.

### DocIntegrity

Implementar como CLI/validator:

- `opencode/bin/validate-doc-integrity.js` ou integrado ao plano 10;
- escaneia promessas de runtime;
- compara com manifestos;
- emite JSON + saida humana.

Runtime pode registrar `doc_integrity` em session end, mas bloqueio deve ser em CI/validator, nao durante toda conversa.

## Plano de implementacao

### Fase 1 - Schemas

Extrair shape real de eventos atuais:

- classification;
- security;
- notification;
- session/state sync;
- tool failure.

Adicionar tests que leem eventos fixtures e validam campos obrigatorios.

### Fase 2 - DocIntegrity CLI

Implementar scanner:

- reutilizar regras do plano 10;
- output `PASS/WARN/FAIL`;
- `--json` para automacao.

### Fase 3 - Integrar com runtime logs

Quando `session.deleted` roda:

- opcionalmente registrar resumo de integrity status cached;
- nao rodar scan completo caro a cada sessao por padrao.

### Fase 4 - Documentar contrato para consumidores

Atualizar:

- `opencode/docs/NOTIFICATIONS_STREAM.md`;
- `opencode/docs/README-OPENCODE.md`;
- docs mobile se necessario.

## Criterios de aceite

- Schemas existem para os principais JSONL.
- Teste prova que eventos emitidos por helpers atuais satisfazem schemas.
- DocIntegrity detecta pelo menos: missing tool, missing hook, missing system prompt, path Claude.
- `bun test` cobre schemas/validator.
- O validator nao depende de dashboard/Pulse live.

## Fora de escopo

- UI de observability.
- Banco de dados para eventos.
- Recriar Pulse dashboard.
