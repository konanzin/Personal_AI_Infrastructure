# PAI Mobile — Plano Técnico Completo

## 1. Objetivo

Este documento transforma a visão, as decisões arquiteturais e as specs já fechadas em um plano técnico completo de desenvolvimento do PAI Mobile.

Ele cobre:

- estratégia de repositório
- arquitetura de pacotes
- milestones de desenvolvimento
- workstreams paralelos
- gates técnicos
- critérios de pronto
- testes
- build/release
- riscos e mitigação
- backlog inicial e ordem de execução

Este plano assume explicitamente que o objetivo é **fazer a arquitetura certa desde o início**, e não construir uma versão simplificada destinada a ser descartada.

---

## 2. Decisão de repositório

## 2.1 Decisão final

**Monorepo.**

Não vamos separar o projeto em dois repositórios distintos neste momento.

## 2.2 Racional

Esta é a escolha correta porque:

1. o app mobile, o plugin OpenCode de notificações e os contratos compartilhados evoluem juntos
2. o projeto é pessoal, privado e com churn relativamente controlado
3. versões podem ser fixadas com facilidade
4. shared types/contracts evitam drift entre app e plugin
5. o overhead operacional de dois repositórios não se paga neste contexto

## 2.3 O que significa “monorepo” aqui

Não significa jogar tudo no mesmo diretório.

Significa um único repositório com pacotes internos bem definidos.

## 2.4 Estrutura alvo do workspace

```text
mobile-app/
  docs/
    PLAN.md
    EXECUTION.md
    OPENCODE_PLUGIN_SPEC.md
    TECHNICAL_PLAN.md

  package.json
  pnpm-workspace.yaml
  tsconfig.base.json

  apps/
    mobile/
      app/
      src/
      assets/
      package.json
      app.json
      eas.json

  packages/
    opencode-mobile-plugin/
      src/
      package.json

    opencode-mobile-client/
      src/
      package.json

    shared-types/
      src/
      package.json

    shared-schemas/
      src/
      package.json

    ui-system/
      src/
      package.json

    audio-elevenlabs/
      src/
      package.json

    test-utils/
      src/
      package.json
```

## 2.5 O que não faremos agora

Não vamos separar em:

- repo do app
- repo do plugin

Essa extração só faria sentido se o plugin passasse a ter vida independente, público externo ou ciclo de release próprio.

---

## 3. Arquitetura técnica macro

## 3.1 Componentes principais

### A. Mobile App

Responsável por:

- interface voz-first
- chat e sessões
- renderização de mensagens
- captura de áudio
- playback de áudio
- estado local
- deep linking
- recebimento de notificações

### B. OpenCode Server

Continua sendo:

- fonte única de verdade
- orquestrador das sessões
- executor do agente
- origem dos eventos

### C. Plugin OpenCode de notificações mobile

Responsável por:

- observar eventos relevantes
- filtrar parent sessions
- deduplicar
- registrar devices/tokens
- enviar push

### D. Provedor de áudio

**ElevenLabs** será o provedor principal para:

- STT
- TTS

### E. Canal de rede

**Tailscale** é a fundação de conectividade privada.

---

## 4. Stack técnica consolidada

## 4.1 App mobile

- React Native
- Expo
- Expo Router
- TypeScript strict
- Material 3 como base de UI/UX

## 4.2 Estado e persistência

- Zustand
- expo-secure-store
- SQLite local (`expo-sqlite`) para dados persistentes estruturados

## 4.3 Rede

- `fetch` para REST
- SSE no foreground
- reidratação completa para recovery

## 4.4 Notificações

- expo-notifications no app
- Expo Push Service na primeira implementação
- plugin OpenCode como originador da notificação

## 4.5 Áudio

- ElevenLabs STT
- ElevenLabs TTS
- biblioteca de captura/playback de áudio compatível com Expo
- fallback local técnico quando necessário

## 4.6 Testes

- Vitest/Jest para unit tests
- React Native Testing Library
- Maestro para E2E mobile

---

## 5. Pacotes do monorepo

## 5.1 `apps/mobile`

O aplicativo executável.

Contém:

- rotas do Expo Router
- telas
- composição dos stores
- integração com notificações nativas
- shell geral do app

## 5.2 `packages/opencode-mobile-plugin`

Plugin do ecossistema OpenCode responsável por:

- observar eventos
- registrar devices
- deduplicar
- enviar push
- montar payloads deep-linkable

## 5.3 `packages/opencode-mobile-client`

Client interno da API do OpenCode Server para o app.

Responsável por:

- auth
- sessões
- mensagens
- SSE
- recovery/reidratação
- permissões

## 5.4 `packages/shared-types`

Tipos TypeScript compartilhados entre app e plugin:

- notification payloads
- message part types
- session metadata
- permission action types

## 5.5 `packages/shared-schemas`

Schemas de validação e parse:

- payload de notificação
- registro de device
- payload de recovery
- contratos da UI de mensagem

## 5.6 `packages/ui-system`

Sistema de UI sobre Material 3:

- tokens
- wrappers de componentes
- tema light/dark
- padrões visuais do PAI

## 5.7 `packages/audio-elevenlabs`

Camada de abstração de áudio:

- STT client
- TTS client
- controles de latência/fallback
- contratos de streaming/estado

## 5.8 `packages/test-utils`

Utilitários para:

- mocks de mensagens
- fixtures de sessão
- payloads de notificação
- testes de integração e E2E

---

## 6. Ordem macro de desenvolvimento

O projeto será desenvolvido em **10 milestones principais**.

Cada milestone produz algo utilizável e fecha um conjunto de riscos.

---

## 7. Milestone M0 — Workspace & Bootstrap

## Objetivo

Criar a fundação do monorepo e provar que o app sobe corretamente com Expo Router e Material 3.

## Entregáveis

1. monorepo criado dentro de `mobile-app/`
2. `pnpm-workspace.yaml` funcional
3. app Expo inicial sobe em iOS e Android
4. Expo Router configurado
5. Material 3 aplicado no shell do app
6. estrutura de pacotes criada
7. TypeScript strict habilitado

## Subtarefas

### Workspace
- criar `package.json` root
- configurar workspaces
- criar scripts root (`dev`, `typecheck`, `test`, `lint`)

### App bootstrap
- criar `apps/mobile`
- configurar Expo Router
- criar shell inicial com rotas mínimas

### UI base
- instalar e configurar sistema Material 3
- definir tema base PAI
- criar `AppShell`, `ScreenContainer`, `TopBar`, `BottomNav`

### Estrutura de pacotes
- criar packages vazios com `package.json`
- configurar path resolution entre workspaces

## Gate de saída

- `pnpm install` funciona no workspace
- `pnpm --filter mobile start` sobe sem erro
- app roda em simulador iOS e Android
- dark/light mode funcional

---

## 8. Milestone M1 — Contratos & Arquitetura interna

## Objetivo

Fechar os contratos do sistema antes de implementar a lógica pesada.

## Entregáveis

1. contratos de mensagens
2. contratos de notificações
3. contratos de permissões
4. contratos de sessões
5. contratos de device registration
6. contratos de partes de mensagem renderizáveis

## Subtarefas

### Shared types
- definir `SessionSummary`
- definir `SessionMessage`
- definir `MessagePart`
- definir `PermissionRequest`
- definir `NotificationPayload`

### Shared schemas
- schemas de validação para cada payload importante
- parser defensivo para payload vindo do plugin/OpenCode

### Message rendering contract
- fechar tipos suportados pela timeline
- fechar estados de tool call/result
- fechar estados de permission card

## Gate de saída

- app e plugin conseguem importar tipos/schemas do mesmo lugar
- spec de renderização está documentada e não ambígua
- mudanças de contrato exigem alteração em pacote compartilhado, não em código duplicado

---

## 9. Milestone M2 — Navegação, App State e Settings

## Objetivo

Construir a espinha dorsal da experiência do app.

## Entregáveis

1. rotas principais implementadas
2. `appStore`, `settingsStore`, `connectionStore` funcionais
3. secure storage funcionando
4. tela de configuração funcional
5. suporte a deep links base

## Rotas mínimas

- `/` → home voz-first
- `/sessions`
- `/session/[id]`
- `/settings`
- `/notifications`

## Stores a implementar

### `appStore`
- tema atual
- rota ativa
- sessão ativa para UI
- permissões do dispositivo já concedidas

### `settingsStore`
- server URL
- username/password
- preferências visuais
- preferências de notificação/áudio

### `connectionStore`
- offline
- connecting
- connected
- reconnecting
- streaming
- stale
- authFailed

## Gate de saída

- usuário consegue configurar servidor e credenciais
- deep links base resolvem corretamente
- estado persiste entre fechamentos do app

---

## 10. Milestone M3 — OpenCode Client & Sessões

## Objetivo

Construir o client unificado para conversar com o OpenCode Server.

## Entregáveis

1. `packages/opencode-mobile-client` funcional
2. auth funcionando
3. listar sessões
4. abrir sessão
5. criar sessão
6. buscar mensagens da sessão

## Subtarefas

### Client API
- wrapper de auth
- wrapper de sessões
- wrapper de mensagens
- wrapper de permissões

### Session store
- lista de sessões
- metadata resumida
- criação/seleção/reidratação

### Message store
- mensagens por sessão
- drafts
- ordenação
- dedupe

## Gate de saída

- app consegue abrir e navegar por sessões reais
- message store é alimentada por dados reais do OpenCode
- nenhum tipo compartilhado foi duplicado localmente

---

## 11. Milestone M4 — SSE Foreground & Reidratação Completa

## Objetivo

Fechar a arquitetura híbrida de eventos na prática.

## Entregáveis

1. SSE funcional em foreground
2. reconexão automática
3. reidratação completa ao abrir/retomar sessão
4. deduplicação local após reidratação
5. restauração após app voltar do background

## Estratégia implementada

### Quando a sessão está aberta e ativa
- SSE ligado
- append incremental na timeline

### Quando o app volta do background
- desligar suposições sobre continuidade
- buscar estado completo da sessão
- deduplicar localmente
- religar SSE se a tela continuar ativa

## Casos a provar

1. queda de rede
2. retorno da rede
3. app minimizado e reaberto
4. servidor reiniciado
5. sessão longa com muito histórico

## Gate de saída

- foreground streaming consistente
- reidratação completa sem corromper timeline
- sem mensagens duplicadas em cenários comuns

---

## 12. Milestone M5 — Timeline, Renderização e Permissões

## Objetivo

Construir a interface de conversa completa.

## Entregáveis

1. timeline de mensagens
2. markdown rendering
3. code blocks
4. tool call cards
5. tool result cards
6. permission cards
7. question cards
8. error cards

## Componentes esperados

- `MessageText`
- `MessageCodeBlock`
- `ToolCallCard`
- `ToolResultCard`
- `PermissionRequestCard`
- `QuestionCard`
- `MessageErrorCard`

## Fluxo de permissão

1. sessão contém card de permissão
2. usuário aprova/nega na própria timeline
3. ação volta ao OpenCode
4. UI atualiza status localmente

## Gate de saída

- todos os tipos de conteúdo definidos na spec têm renderer correspondente
- permissões não aparecem como texto cru
- a conversa fica compreensível sem precisar “adivinhar” tool states

---

## 13. Milestone M6 — Áudio: STT/TTS com ElevenLabs

## Objetivo

Construir o loop voz-first real.

## Entregáveis

1. captura de áudio
2. envio para STT ElevenLabs
3. retorno de transcrição para revisão
4. envio da mensagem revisada ao backend
5. TTS ElevenLabs da resposta
6. interrupção/cancelamento
7. fallback técnico local documentado

## Máquina de estados de voz

- `idle`
- `listening`
- `transcribing`
- `reviewing`
- `sending`
- `speaking`
- `cancelled`
- `error`

## Casos obrigatórios

### Input
- usuário fala e para
- usuário fala e cancela
- áudio falha
- transcrição volta vazia

### Output
- TTS toca normalmente
- usuário interrompe playback
- rede falha antes do TTS terminar

## Gate de saída

- o app já parece um assistant de voz, não só um chat com microfone
- fallback para texto existe em qualquer falha de voz

---

## 14. Milestone M7 — Plugin OpenCode de Notificações

## Objetivo

Construir a parte server-side das notificações mobile diretamente no ecossistema OpenCode.

## Entregáveis

1. pacote `opencode-mobile-plugin`
2. observação de eventos relevantes
3. filtragem parent session
4. dedupe
5. registro de device token
6. envio para Expo Push Service
7. payload com deep link

## Subtarefas

### Registry
- registrar device token
- atualizar token
- invalidar token
- associar `deviceId`, `platform`, `pushToken`, `updatedAt`

### Event filtering
- session complete
- session error
- permission needed
- question asked
- scheduled reminder

### Delivery
- enviar payload mínimo
- evitar texto sensível no corpo
- classificar prioridade

## Gate de saída

- o plugin dispara push real para um dispositivo registrado
- eventos não disparam spam
- dedupe impede duplicações óbvias

---

## 15. Milestone M8 — Deep Linking, Notification UX e Reentrada

## Objetivo

Fechar o loop da notificação até a sessão correta.

## Entregáveis

1. abrir app via deep link
2. abrir sessão correta
3. reidratar automaticamente
4. destacar o contexto relevante
5. central simples de notificações no app

## Fluxos obrigatórios

### Session complete
notificação → abrir sessão → ver resposta final

### Permission needed
notificação → abrir sessão → responder permissão

### Question asked
notificação → abrir sessão → responder pergunta

## Gate de saída

- tocar uma notificação sempre leva ao contexto correto
- a sessão abre pronta para ação, não apenas em tela genérica

---

## 16. Milestone M9 — Resiliência, Segurança e Observabilidade

## Objetivo

Tornar o sistema robusto no uso real.

## Entregáveis

1. retry/backoff consistente
2. tratamento de auth failure
3. tratamento de TTS/STT failure
4. logs estruturados
5. métricas de latência
6. documentação do risco aceito de Basic Auth sobre tailnet

## Itens obrigatórios

### Segurança
- secure storage real
- minimização de dados em logs
- risco aceito documentado para Basic Auth

### Observabilidade
- logs por fluxo crítico
- medição de latência STT
- medição de latência TTS
- medição de latência push
- medição de tempo de reidratação

### Resiliência
- drafts preservados
- retry manual
- reconnect automático
- erro claro para usuário

## Gate de saída

- falhas deixam de quebrar o fluxo silenciosamente
- há evidência observável do que deu errado

---

## 17. Milestone M10 — QA, Build e Release Privado

## Objetivo

Fechar a distribuição e o nível de qualidade de uso pessoal contínuo.

## Entregáveis

1. builds privados iOS/Android
2. CI de lint/typecheck/test
3. smoke tests de sessão/voz/notificação
4. checklist de release
5. documentação operacional

## Build/release

### iOS
- EAS Build
- TestFlight privado

### Android
- EAS Build ou build interno equivalente
- distribuição privada

## Gate de saída

- build instalável em iOS e Android
- smoke tests passam
- fluxo completo voz → sessão → push → reentrada funciona

---

## 18. Workstreams paralelos

Depois de M3, o desenvolvimento pode paralelizar melhor em 4 trilhas:

### Trilha A — App shell e stores
- navegação
- settings
- theming
- app state

### Trilha B — OpenCode client e sync
- sessões
- mensagens
- SSE
- reidratação

### Trilha C — Voice pipeline
- captura de áudio
- STT
- TTS
- UX de voz

### Trilha D — Plugin de notificações
- registry de devices
- filtros
- push
- deep links

---

## 19. Estratégia de testes

## 19.1 Unit tests

Cobrir:

- parsers de payload
- dedupe de notificações
- reducers/stores
- mapping de message parts

## 19.2 Integration tests

Cobrir:

- client OpenCode
- reidratação de sessão
- registro de device token
- plugin → payload → app handling

## 19.3 E2E tests

Cobrir:

1. configurar servidor
2. abrir sessão
3. enviar mensagem de texto
4. receber resposta
5. fluxo de voz
6. push que abre sessão correta
7. permissão do agente respondida pelo mobile

## 19.4 Manual validation obrigatória

Em dispositivo físico:

- iPhone
- Android real

Não confiar apenas em simulador.

---

## 20. Ordem de implementação detalhada

## Bloco 1 — Foundation

1. criar monorepo
2. subir Expo Router
3. subir Material 3
4. configurar root scripts
5. criar `ui-system`

## Bloco 2 — Contracts

6. criar `shared-types`
7. criar `shared-schemas`
8. fechar `MessagePart`
9. fechar `NotificationPayload`
10. fechar `PermissionRequest`

## Bloco 3 — App state

11. criar stores
12. secure storage
13. config screen
14. app shell

## Bloco 4 — OpenCode client

15. auth client
16. sessions client
17. messages client
18. SSE client

## Bloco 5 — Session sync

19. list sessions
20. open session
21. rehydrate session
22. dedupe messages
23. reconnect behavior

## Bloco 6 — Message UI

24. timeline
25. markdown
26. code blocks
27. tool cards
28. permission cards
29. question cards

## Bloco 7 — Voice

30. capture audio
31. STT ElevenLabs
32. review step
33. send to OpenCode
34. TTS ElevenLabs
35. interrupt/cancel

## Bloco 8 — Notifications

36. plugin scaffold
37. device registration
38. event filtering
39. dedupe
40. Expo push send
41. app receive notification
42. deep link open session

## Bloco 9 — Hardening

43. retry/backoff
44. auth failure UX
45. logs/metrics
46. privacy review
47. failure fallback review

## Bloco 10 — Release

48. CI
49. E2E smoke
50. build profiles
51. private install pipeline

---

## 21. Decisões adicionais fechadas por este plano

## 21.1 Router

- **Expo Router**

## 21.2 UI System

- **Material 3 como base**
- branding PAI por cima, não reescrever sistema inteiro

## 21.3 Recovery

- **reidratação completa**

## 21.4 Notifications

- **plugin-first** dentro do ecossistema OpenCode

## 21.5 Repo strategy

- **monorepo**

---

## 22. O que ainda precisa ser provado tecnicamente

Mesmo com a direção fechada, estes pontos ainda precisam de validação prática:

1. SDK exato do ElevenLabs em React Native / Expo
2. shape real dos eventos e mensagens do OpenCode
3. mecanismo exato de plugin para registry + push
4. custo/latência real do pipeline STT/TTS
5. comportamento de SSE no app em uso real

Esses pontos não estão “em aberto” conceitualmente.  
Eles só precisam ser provados na implementação.

---

## 23. Recomendação operacional final

O desenvolvimento deve começar imediatamente por:

1. **M0**
2. **M1**
3. **M2**

Sem tentar pular para notificações ou voz antes que:

- o workspace esteja sólido
- os contratos estejam sólidos
- o client OpenCode esteja sólido
- a reidratação completa esteja sólida

O que diferencia este plano de um “MVP simplificado” não é construir tudo de uma vez.  
É construir **na arquitetura certa, na ordem certa**.
