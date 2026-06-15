# Plano 11 - Pulse, Mobile, Voice e Escopo

## Objetivo

Manter o caminho atual mobile/broker como solucao OpenCode-native, enquanto remove ou rebaixa promessas herdadas do Pulse desktop original. Este plano nao tenta recriar dashboard Next, MenuBar macOS ou VoiceServer antigo.

## Estado atual verificado no codigo

Port atual forte:

- `opencode/plugins/pai-hooks.js:307-362` define tool nativa `pai_notify`.
- `opencode/plugins/pai-hooks.js:186-189` e `:224-228` exigem `pai_notify` nos system contexts.
- `opencode/config/opencode.jsonc.template:20-29` exige `pai_notify` nos agentes primarios.
- `opencode/broker/pulse-broker.ts` implementa broker SSE em porta 31337.
- `opencode/broker/broker-lib.ts` tem routing policy testada.
- `opencode/tests/broker.test.ts` cobre health, subscribe, notify e presence.
- `mobile-app/apps/flutter/lib/services/pulse/pulse_listener_service.dart` consome broker e gerencia focus/presence.

Drift:

- `PAI/PULSE/PULSE.toml:1-24` ainda descreve daemon unificado e dashboard `Observability/out`.
- `PAI/PULSE/PULSE.toml:85`, `:93`, `:166`, `:174` chama tools ausentes.
- Instalacao observada tinha prompt `build-mobile` antigo sem `pai_notify` tool call completo.
- Docs herdadas em `PAI/DOCUMENTATION/Pulse/*` ainda descrevem dashboard/daemon original.

## Diferenca operacional

O original Pulse era uma superficie desktop ampla. O port escolheu corretamente:

- producer JSONL;
- broker opcional;
- mobile/desktop renderer como consumidores;
- `pai_notify` explicito, sem parse de texto final.

O problema nao e falta de port do dashboard. O problema e documentos/configs antigos tratarem o dashboard/jobs/helpers como ativos.

## Desenho OpenCode-native

Definir escopo oficial:

- `notifications.jsonl`: contrato produtor.
- `pai_notify`: fala final explicita.
- `pulse-broker.ts`: runtime opcional de fan-out.
- mobile app: consumidor principal futuro.
- desktop renderer: referencia/dev convenience.

Fora de escopo:

- dashboard Next original;
- MenuBar macOS original;
- VoiceServer antigo;
- jobs cron em `PULSE.toml` que dependem de helpers ausentes.

## Plano de implementacao

### Fase 1 - Reduzir `PULSE.toml`

Substituir ou mover o arquivo atual para `PULSE.legacy.toml`.

Novo `PULSE.toml` deve conter apenas:

- broker opcional;
- path do stream;
- port default;
- renderer hints;
- jobs desabilitados ou removidos se helper ausente.

### Fase 2 - Config/installer

Integrar com plano 09:

- garantir `pai_notify` no config instalado;
- instalar broker files e systemd template;
- validar que broker e opcional, nao criterio de install live.

### Fase 3 - Docs de escopo

Atualizar:

- `opencode/docs/NOTIFICATIONS_STREAM.md`;
- `opencode/docs/README-OPENCODE.md`;
- `PAI/DOCUMENTATION/Pulse/PulseSystem.md` com cabecalho legacy;
- `PAI/PULSE/README.md` se criado.

### Fase 4 - Testes de contrato

Manter e expandir:

- `opencode/tests/notifications.test.ts`;
- `opencode/tests/broker.test.ts`;
- e2e runtime `07-notifications.js`.

Adicionar caso:

- `pai_notify` duplicado dedupa;
- `🎯 COMPLETED` sozinho nao fala;
- legacy `/notify` sem language para speak e rejeitado ou tratado como dashboard-only.

## Criterios de aceite

- `PULSE.toml` nao chama `PAI/TOOLS/*.ts` ausentes.
- Docs deixam claro que Pulse desktop original e legacy/out-of-scope.
- `build` e `build-mobile` instalados exigem `pai_notify`.
- Broker continua opcional: validator checa arquivos, nao processo live.
- Mobile continua enviando `build-mobile` quando servidor define o agente.

## Fora de escopo

- Dashboard Next.
- MenuBar macOS.
- ElevenLabs/VoiceServer original.
- Cron daemon completo.
