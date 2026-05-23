# PAI Mobile — OpenCode Plugin & Message Spec

## 1. Objetivo

Este documento fecha duas superfícies que afetam a implementação desde o começo:

1. o **plugin OpenCode de notificações mobile**
2. a **spec de renderização de mensagens, permissões e eventos** no app

---

## 2. Plugin OpenCode de notificações mobile

## 2.1 Princípio

O plugin deve seguir a filosofia do `opencode-notify`:

- notificar quando o humano precisa voltar
- evitar spam
- deduplicar
- filtrar child sessions por padrão

## 2.2 Responsabilidades

O plugin deve:

1. escutar eventos relevantes do ecossistema OpenCode
2. identificar parent session vs child session
3. filtrar apenas eventos acionáveis
4. deduplicar eventos em janela curta
5. montar payload mobile com `sessionId` e `deepLink`
6. enviar push
7. registrar / atualizar device tokens

## 2.3 Eventos que o plugin deve observar

- `session.idle` / equivalente de sessão pronta
- `session.error`
- `permission.updated` / `permission.asked`
- `question.asked`
- eventos internos de lembrete, se existirem no PAI

## 2.4 Eventos que viram push

### Sim

- `session_complete`
- `session_error`
- `permission_needed`
- `question_asked`
- `scheduled_reminder`

### Não

- streaming parcial
- tool events intermediários
- child session complete por padrão

## 2.5 Dedupe

### Chaves iniciais

- `session_complete`: `session:{id}:complete`
- `session_error`: `session:{id}:error:{fingerprint}`
- `permission_needed`: `permission:{requestId}`
- `question_asked`: `question:{sessionId}:{requestId}`

## 2.6 Payload do push

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

## 2.7 Device registration

O app deve registrar o token de push no plugin.

Payload mínimo sugerido:

```ts
type RegisterDeviceInput = {
  deviceId: string
  platform: "ios" | "android"
  pushToken: string
  appVersion: string
  label?: string
}
```

## 2.8 Storage mínimo do plugin

O plugin deve persistir:

- `deviceId`
- `pushToken`
- `platform`
- `updatedAt`
- relação com principal/ambiente se necessário

Pode ser arquivo simples/JSON ou store leve no começo.

## 2.9 Privacidade

O corpo do push não deve conter conteúdo sensível completo.

Mensagens preferidas:

- "PAI precisa da sua aprovação"
- "Sessão concluída"
- "Nova pergunta do assistant"

---

## 3. Spec de mensagens no app

## 3.1 Objetivo

Antes de implementar a UI de conversa, o app precisa saber renderizar os tipos principais de conteúdo vindos do OpenCode.

## 3.2 Tipos de conteúdo a suportar

### Tipo A — Texto markdown

Renderizar:

- parágrafos
- listas
- headings
- bold/italic
- links

### Tipo B — Code block

Renderizar:

- bloco destacado
- scroll horizontal
- copy action futura

### Tipo C — Tool call

Renderizar como card com:

- nome da tool
- estado (`running`, `completed`, `failed`)
- resumo curto

### Tipo D — Tool result

Renderizar como card/expandable com:

- resultado resumido
- detalhes sob demanda

### Tipo E — Permission request

Renderizar como card de ação com:

- descrição clara do pedido
- botão de aprovar
- botão de negar
- contexto da sessão

### Tipo F — Question asked

Renderizar como card de atenção com:

- pergunta do agente
- resposta rápida
- caminho para abrir a sessão completa

### Tipo G — Error state

Renderizar como card de erro com:

- resumo do erro
- ação sugerida (`retry`, `open session`, `dismiss`)

## 3.3 Regras de UI

1. texto do assistant e tool cards coexistem na timeline
2. permissões nunca ficam escondidas no meio de markdown puro
3. erros e perguntas precisam de destaque visual maior
4. tudo deve continuar legível no modo voz-first

---

## 4. Fluxo de permissão no mobile

## 4.1 Quando o PAI pede permissão

1. plugin envia push `permission_needed`
2. toque abre `pai://session/:sessionId`
3. sessão reidrata
4. card de permissão aparece na timeline
5. usuário aprova ou nega

## 4.2 Decisão de UX

Permissões devem ser respondidas **na tela da sessão**, não em modal desconectado do contexto.

---

## 5. Navegação

## 5.1 Decisão

- **Expo Router**

## 5.1.1 Base de UI/UX

- **Material 3** como sistema base: `https://m3.material.io/get-started`
- componentes, estados, feedback, navegação e acessibilidade devem partir desse sistema
- a identidade visual do PAI entra como camada de customização, não como reinvenção do sistema base

## 5.2 Rotas mínimas

```text
/(app)
  /index                -> home voz-first
  /sessions             -> lista de sessões
  /session/[id]         -> conversa da sessão
  /settings             -> configuração
  /notifications        -> central simples
```

## 5.3 Deep links

```text
pai://session/:id
pai://settings
pai://notifications
```

---

## 6. Recovery da sessão

## 6.1 Decisão

- **reidratação completa** no começo

## 6.2 Regra

Ao abrir ou retomar uma sessão:

1. buscar histórico disponível
2. deduplicar localmente
3. reconstruir a timeline
4. só depois religar SSE se a tela estiver ativa

---

## 7. Pontos que o próximo passo técnico precisa provar

1. SDK STT cloud-first em React Native
2. registro de push token no plugin
3. envio de push via Expo Push Service
4. relação entre evento OpenCode e session parent/child
5. shape real das mensagens retornadas pelo OpenCode para fechar a UI renderer
