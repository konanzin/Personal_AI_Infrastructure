# PAI Mobile — Documento de Execução Inicial

## 1. Objetivo deste documento

Este documento pega o `PLAN.md` e transforma a direção geral em decisões executáveis para o começo do desenvolvimento.

Ele resolve explicitamente os gaps mais perigosos antes de começar a codar:

- estratégia de eventos em mobile
- modelagem de notificações
- arquitetura de estado
- estratégia de erros e fallback
- decisão de TTS
- ordem revisada das fases

---

## 2. Decisões fechadas neste momento

### 2.1 Produto

- O app continua sendo um **remote privado do PAI**
- **Voz-first** continua sendo a identidade principal
- **Chat continua obrigatório** como modo complementar de visibilidade e granularidade

### 2.2 Rede e backend

- O **OpenCode Server** continua sendo a única fonte de verdade
- O app continua operando em rede privada via **Tailscale**
- Não haverá backend paralelo de agentes/memória/lógica do PAI

### 2.3 Áudio

- **TTS entra desde o início**
- **STT será cloud-first**, usando ElevenLabs
- **TTS também prioriza ElevenLabs** como provedor principal de voz
- motivação: consolidar áudio em um único provedor, com melhor tradeoff entre custo mensal, operação e qualidade do que manter infraestrutura própria 24/7
- O fluxo de voz inicial será:
  - capturar fala
  - transcrever
  - enviar ao backend
  - receber resposta
  - exibir no chat
  - ler a resposta em voz alta

### 2.4 Notificações

- A filosofia será inspirada pelo `opencode-notify`: **notificar quando o humano precisa voltar, não a cada micro-evento**
- Não vamos transformar qualquer evento do OpenCode em push
- As notificações serão filtradas, deduplicadas e correlacionadas por sessão

### 2.5 UI/UX

- A base visual e de interação parte de **Material 3**: `https://m3.material.io/get-started`
- O app pode adaptar branding e identidade do PAI por cima, mas o sistema base de componentes, estados e acessibilidade será Material 3

---

## 3. Decisão arquitetural de eventos

## 3.1 Problema

SSE puro em mobile é frágil para:

- background
- troca de rede
- resume
- reconexão
- continuidade de sessão

Logo, o app não pode depender de “uma conexão SSE sempre viva” como fundamento único da experiência.

## 3.2 Decisão

Vamos usar uma estratégia **híbrida**:

### Foreground

- **SSE** para streaming e eventos em tempo real enquanto o app está aberto

### Background / Resume

- **reidratação completa da sessão** ao voltar para foreground ou reabrir uma sessão
- deduplicação local entre conteúdo já renderizado e conteúdo reidratado

### Notificações

- **push** será entregue por um plugin do ecossistema OpenCode responsável por observar eventos relevantes e encaminhar notificações mobile

## 3.3 Conclusão prática

O modelo final não é “SSE vs polling”.  
É:

- **SSE para experiência ao vivo**
- **reidratação completa ao voltar**
- **push para reentrada quando o app não está ativo**

---

## 4. Modelo de notificações

## 4.1 Referência: `opencode-notify`

O projeto `opencode-notify` traz uma filosofia correta que devemos reaproveitar:

1. **notificar só eventos significativos**
2. **evitar spam**
3. **filtrar child sessions por padrão**
4. **deduplicar eventos próximos**
5. **tratar “AI precisa de você” como prioridade maior**

Ele opera escutando eventos do OpenCode e decidindo o que merece notificação.  
Nós vamos usar o mesmo princípio, mas com entrega para mobile.

## 4.2 Eventos que devem virar notificação mobile

### Sim

1. **session complete / ready for review**
2. **session error**
3. **permission needed**
4. **question asked**
5. **scheduled reminder** (quando vier do próprio PAI)

### Não

- tokens intermediários
- micro-updates de tool
- subtask complete por padrão
- qualquer evento sem ação clara do usuário

## 4.3 Regra de priorização

### Alta prioridade

- permission needed
- question asked
- session error

### Média prioridade

- session complete

### Controlada / opcional

- reminders agendados

## 4.4 Arquitetura proposta

```text
OpenCode Server
   └─ Plugin de notificações mobile
       ├─ observa eventos/sse do ecossistema OpenCode
       ├─ filtra eventos relevantes
       ├─ deduplica
       ├─ enriquece payload com sessionId/deepLink
       ├─ mantém registry mínimo de devices/tokens
       └─ envia push para iOS/Android

Mobile App
   ├─ foreground: consome SSE diretamente
   ├─ background: recebe push do plugin
   └─ ao abrir pelo push: navega para a sessão correta
```

## 4.5 O que é o plugin de notificações mobile

Uma extensão do ecossistema OpenCode, escrita como plugin, e **não um backend paralelo de agentes**.  
Ele não contém lógica do DA. Ele só faz:

- subscribe nos eventos do OpenCode
- filtro
- dedupe
- roteamento de push

### Responsabilidades do plugin

1. manter conexão com o stream/eventos do OpenCode Server
2. transformar eventos brutos em eventos de notificação
3. deduplicar por `sessionId`, `requestId`, `questionId`, etc.
4. enviar push ao device correto
5. persistir mínimo necessário para retry e observabilidade
6. expor forma controlada de registrar/atualizar device tokens

## 4.6 Payload de notificação

Payload recomendado:

```ts
type MobileNotificationPayload = {
  type: "session_complete" | "session_error" | "permission_needed" | "question_asked" | "scheduled_reminder"
  sessionId?: string
  requestId?: string
  title: string
  body: string
  deepLink: string
  dedupeKey: string
  timestamp: string
  priority: "high" | "medium"
}
```

Exemplo de `deepLink`:

```text
pai://session/abc123
```

## 4.7 Dedupe

Inspirado no `opencode-notify`, o plugin deve deduplicar eventos em janelas curtas.

Exemplos:

- `question_asked`: dedupe por `sessionId + question/requestId`
- `permission_needed`: dedupe por `requestId`
- `session_complete`: dedupe por `sessionId`
- `session_error`: dedupe por `sessionId + error fingerprint`

## 4.8 Child sessions

Regra inicial:

- **somente parent session gera notificação por padrão**
- child sessions só entram depois, se houver necessidade explícita

Isso reduz ruído.

## 4.9 Entrega técnica do push

Para a primeira implementação, a opção mais pragmática é:

- **Expo Notifications no app**
- plugin enviando para **Expo Push Service**

Depois, se quiser reduzir dependência intermediária, o plugin pode evoluir para APNs/FCM diretos.

## 4.10 Observação de privacidade

Mesmo em app privado, push em iOS/Android passa por infraestrutura do sistema operacional.  
Portanto:

- conteúdo sensível deve ser minimizado no corpo da notificação
- preferir mensagens como:
  - “PAI precisa da sua aprovação”
  - “Sessão concluída”
  - “Nova pergunta do assistant”
- detalhes completos ficam dentro do app após abrir a sessão

---

## 5. Decisão de TTS

## 5.1 Decisão

**TTS entra desde o começo.**

Sem isso, “voz-first” vira apenas “input por voz”. Isso empobrece a experiência.

## 5.2 Implementação inicial

Para o alpha:

- usar **ElevenLabs como TTS principal**
- manter **`expo-speech`** apenas como fallback técnico local se necessário

### Vantagens

- consistência entre STT/TTS no mesmo provedor
- voz mais alinhável à identidade do DA
- reduz fragmentação de decisões de áudio

### Limites aceitos no alpha

- dependência de serviço externo para áudio
- necessidade de tratar latência e falha de rede com fallback claro

## 5.3 Evolução futura

Depois do alpha:

- avaliar TTS remoto com voz própria do DA
- cache de áudio gerado
- interrupção/ducking mais refinados

---

## 6. Decisão de STT

## 6.1 Objetivo

Precisamos de uma opção que permita iteração rápida e boa experiência em pt-BR.

## 6.2 Recomendação inicial

### Direção fechada

1. **STT cloud-first com ElevenLabs em React Native**
2. o app captura áudio e envia para transcrição no provedor escolhido
3. o resultado volta como texto para revisão/envio

### O spike agora deve validar

- SDK real escolhido
- fluxo de autenticação/chaves
- latência ponta a ponta
- qualidade em pt-BR
- comportamento em iOS e Android

## 6.3 Critérios do spike

- qualidade de transcrição em pt-BR
- latência
- estabilidade em iOS
- estabilidade em Android
- UX de permissões

O resultado do spike deve fechar a escolha da biblioteca antes do loop de voz completo.

---

## 7. Arquitetura de estado

Vamos organizar o estado em domínios claros.  
A recomendação é **Zustand** com stores separadas por responsabilidade.

```text
src/state/
  connectionStore.ts
  sessionStore.ts
  messageStore.ts
  voiceStore.ts
  settingsStore.ts
  notificationStore.ts
```

## 7.1 `connectionStore`

Responsável por:

- `offline`
- `connecting`
- `connected`
- `streaming`
- `stale`
- `authFailed`
- `lastEventId` opcional para telemetria/local state, sem depender dele para recovery
- `lastConnectedAt`
- `reconnecting`

## 7.2 `sessionStore`

Responsável por:

- lista de sessões
- metadata resumida (`title`, `updatedAt`, `lastMessagePreview`, `messageCount`)
- criação / seleção / reidratação

## 7.3 `messageStore`

Responsável por:

- mensagens por sessão
- estado de streaming atual
- append incremental da resposta
- ordenação
- dedupe
- drafts locais

## 7.4 `voiceStore`

Responsável por:

- `idle`
- `listening`
- `transcribing`
- `reviewing`
- `sending`
- `speaking`
- `cancelled`
- `error`

Também controla:

- transcrição temporária
- erro de permissão
- cancelamento/interrupção de fala

## 7.5 `settingsStore`

Responsável por:

- server URL
- usuário/senha
- preferências de tema
- preferências de áudio/notificações

## 7.6 `notificationStore`

Responsável por:

- device token de push
- lista de notificações pendentes
- deep link pendente
- dedupe local defensivo

## 7.7 `appStore`

Responsável por:

- tema atual
- rota/tela ativa
- sessão ativa para navegação/UI
- permissões já solicitadas no dispositivo

---

## 8. Estratégia de erros e fallback

## 8.1 Conexão falhou

### Comportamento

- retry com backoff exponencial curto
- mostrar estado visível de reconexão
- permitir retry manual

## 8.2 Auth falhou

### Comportamento

- marcar `authFailed`
- interromper novas tentativas automáticas agressivas
- manter usuário na tela de configuração/conexão
- nunca limpar credenciais silenciosamente

## 8.3 SSE caiu

### Comportamento

- atualizar `connectionStore` para `stale`
- tentar reconectar
- ao voltar, reidratar a sessão completa

## 8.4 Voz falhou

### Casos

- permissão negada
- transcrição vazia
- erro de engine

### Comportamento

- mensagem clara
- fallback imediato para digitação
- manter o rascunho/transcrição parcial quando possível

## 8.5 Mensagem não enviada

### Comportamento

- manter texto em draft
- permitir reenvio manual
- não perder input do usuário

## 8.6 TTS falhou

### Comportamento

- resposta continua visível em texto
- falha de áudio não derruba o fluxo da sessão

---

## 9. Deep linking

Deep linking entra desde o começo da arquitetura de notificações.

## 9.1 Formato inicial

```text
pai://session/:sessionId
pai://settings
pai://notifications
```

## 9.2 Regra principal

Ao tocar uma notificação:

- o app abre
- resolve o deep link
- navega para a sessão correta
- reidrata a sessão se necessário

---

## 10. Fases revisadas

## Fase 0 — Discovery técnico e decisões irreversíveis

Objetivo: matar incertezas estruturais cedo.

Entregáveis:

1. prova de conexão com OpenCode Server via Tailscale
2. spike de SSE + reconexão + recovery
3. decisão final da estratégia híbrida de eventos
4. spike de STT cloud-first em pt-BR
5. prova de TTS com ElevenLabs
6. desenho do plugin de notificações mobile
7. decisão de navegação: **Expo Router**
8. spec completa de renderização de mensagens e permissões

## Fase 1 — Spine funcional

Entregáveis:

1. bootstrap Expo
2. settings + secure storage
3. client API unificado
4. lista/abertura/criação de sessões
5. chat funcional básico

## Fase 2 — Resiliência mínima

Entregáveis:

1. reconexão
2. reidratação completa da sessão
3. restauração após background
4. drafts e fallback mínimo de erro
5. deep linking básico

## Fase 3 — Voice-first loop

Entregáveis:

1. captura de voz
2. transcrição
3. revisão opcional
4. envio ao backend
5. TTS da resposta
6. estados visuais completos

## Fase 4 — Notificações e sistema utilizável

Entregáveis:

1. plugin de notificações mobile funcional
2. push para eventos relevantes
3. abertura na sessão correta via notificação
4. polish básico iOS/Android

---

## 11. Backlog técnico inicial

## 11.1 Primeiro bloco

1. scaffold do projeto Expo TypeScript com **Expo Router**
2. definir estrutura de pastas
3. instalar `zustand`, `expo-secure-store`, `expo-notifications` e dependências do SDK ElevenLabs
4. implementar `settingsStore`, `connectionStore` e `appStore`
5. criar tela de configuração e teste de conectividade

## 11.2 Segundo bloco

1. modelar client API
2. implementar sessões
3. implementar tela de chat
4. testar SSE em foreground
5. implementar reidratação completa e dedupe local

## 11.3 Terceiro bloco

1. protótipo do plugin de notificações mobile
2. filtro de eventos relevantes
3. schema de payload mobile
4. deep link `pai://session/:id`
5. registro de device token + push de teste ponta a ponta

## 11.4 Quarto bloco

1. spike STT com ElevenLabs / serviço equivalente
2. fluxo de voz com revisão
3. TTS com ElevenLabs
4. interrupção e cancelamento

---

## 12. Resumo executivo para o dev

Este projeto agora tem as seguintes definições operacionais:

1. **STT/TTS priorizam ElevenLabs desde o começo**
2. **áudio fica concentrado em um único provedor principal**
3. **eventos em mobile serão híbridos**: SSE no foreground + reidratação completa ao voltar + push via plugin
4. **notificações serão modeladas com a filosofia do `opencode-notify`**: só eventos relevantes, parent session por padrão, dedupe e deep link
5. **as notificações serão implementadas plugin-first dentro do ecossistema OpenCode**
6. **a ordem correta das fases mudou**: resiliência mínima vem antes do loop completo de voz
7. **o estado será separado por domínios claros**: app, conexão, sessão, mensagens, voz, settings, notificações
8. **fallback e erro são parte da arquitetura inicial**, não refinamento tardio
9. **a base de UI/UX será Material 3**, adaptada à identidade do PAI

O objetivo agora não é “só começar a codar”.  
É começar com as apostas irreversíveis já modeladas corretamente.

> Desdobramento operacional completo: `mobile-app/TECHNICAL_PLAN.md`.
