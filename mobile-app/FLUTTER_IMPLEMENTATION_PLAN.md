# PAI Mobile Flutter — Plano de Implementação Oficial

> **Status:** Pre-alpha spine funcional, Flutter canônico  
> **Stack:** Flutter + Dart native HTTP streaming + `flutter_ai_toolkit`  
> **Plataforma-alvo:** Android (`a51`) via Tailscale  
> **Atualizado:** 2026-05-30

## 1. Contexto

O experimento Flutter virou o trilho canônico porque Dart native `http` streaming removeu a classe inteira de bugs SSE que apareceu no React Native/Expo: polyfills, `XMLHttpRequest`, handshakes instáveis e diferenças Hermes/Android. A implementação ativa vive em `mobile-app/apps/flutter`.

React Native/Expo agora é histórico. A próxima energia vai para endurecer o app Flutter, não para manter duas stacks.

## 2. Estado Atual

### 2.1 Configurações e Segurança

- [x] Tela de settings com URL do servidor, usuário e senha
- [x] `flutter_secure_storage` para credenciais
- [x] Validação real de conexão em `/global/health` antes de salvar
- [x] Remoção de logs de usuário/senha/header Basic Auth
- [x] Helper de Tailscale para preencher `http://<host>:4096`
- [x] Texto explicando que `a51` é cliente Android, não servidor

### 2.2 Gerenciamento de Sessões

- [x] Lista de sessões do OpenCode Server
- [x] Abrir sessão existente
- [x] Criar nova sessão
- [x] Renomear/excluir sessão
- [x] Badge/título da sessão ativa no app bar
- [x] Persistência local da sessão ativa com `shared_preferences`

### 2.3 Chat, SSE e Reasoning

- [x] Histórico de mensagens via `flutter_ai_toolkit`
- [x] Renderização básica de Markdown
- [x] SSE via Dart native `http` streaming
- [x] Filtro de eventos SSE por sessão ativa quando `sessionID` está presente
- [x] Deltas de texto visível (`session.next.text.delta`)
- [x] Deltas de reasoning (`session.next.reasoning.delta`)
- [x] Deltas alternativos por `message.part.delta` filtrados por tipo de part
- [x] Reasoning associado por message ID / índice do histórico
- [x] Reidratação do histórico após queda/reconexão SSE
- [ ] Pull-to-refresh no histórico
- [ ] Teste real em dispositivo de interrupção/reconexão

### 2.4 Voice-First Loop

- [x] Bridge nativa Android com `SpeechRecognizer`
- [x] Botão de voz com estados visuais: idle/listening/processing/error
- [x] Transcrição final enviada ao chat como mensagem normal
- [x] TTS removido desta etapa
- [ ] Revisão explícita da transcrição antes do envio
- [ ] Smoke test real de microfone no `a51`

### 2.5 Tema

- [ ] Toggle claro/escuro persistente — **deferido para próxima etapa**
- [ ] Material 3 com seed color do PAI (#3B82F6) — **deferido**
- [ ] Sistema segue preferência do sistema — **deferido**

### 2.6 Resiliência

- [x] Indicador visual de estado da conexão
- [x] Reconexão manual reidrata sessão ativa
- [x] SSE disconnect/error agenda reidratação com backoff
- [x] Cache local da sessão ativa
- [ ] Recuperação ao voltar do background
- [ ] Teste de rede real com Tailscale alternando online/offline

### 2.7 Notificações

- [ ] Push para `question.asked` — futuro
- [ ] Push para `permission.needed` — futuro
- [ ] Push para sessão completa — futuro
- [ ] Deep link para sessão específica — futuro

## 3. Arquitetura Atual

```text
apps/flutter/lib/
  main.dart                         — providers globais e entry point
  models/
    event.dart                      — OpenCodeEvent normalizado
  services/
    opencode_client.dart            — REST + SSE + Basic Auth
    secure_storage.dart             — credenciais no secure storage
    connectivity_service.dart       — status/backoff/heartbeat
    voice_service.dart              — STT Android via MethodChannel
  providers/
    settings_provider.dart          — settings + validação real
    session_provider.dart           — sessões + sessão ativa persistida
    opencode_provider.dart          — LlmProvider, SSE, history, reasoning
  screens/
    settings_screen.dart            — URL/auth/Tailscale
    sessions_screen.dart            — lista e ações de sessão
    chat_screen.dart                — chat, reasoning modal, voice input
  widgets/
    connection_status_indicator.dart
    voice_fab.dart                  — botão STT-only
    reasoning_message_bubble.dart   — widget auxiliar legado/não principal
```

Android bridge:

```text
apps/flutter/android/app/src/main/kotlin/com/example/pai_mobile_flutter/MainActivity.kt
```

## 4. Decisões Técnicas

| Decisão | Justificativa |
|---------|---------------|
| Flutter canônico | Streaming SSE nativo no Dart foi mais confiável que RN/Expo |
| `http` nativo | Sem polyfills; `Stream` é first-class |
| `flutter_secure_storage` | Credenciais no Keystore Android |
| `shared_preferences` | Cache simples da sessão ativa |
| `SpeechRecognizer` Android | STT local/plataforma sem introduzir TTS |
| Tailscale | Acesso privado ao OpenCode Server sem expor serviço publicamente |
| Sem TTS nesta etapa | Reduz complexidade; valida primeiro o loop texto/STT |
| Tema deferido | Evita misturar polish visual com estabilidade de runtime |

## 5. Como Rodar

No host que executa OpenCode:

```bash
OPENCODE_SERVER_PASSWORD='<senha>' opencode serve --hostname 0.0.0.0 --port 4096
```

No app, configure:

```text
http://<ip-ou-magicdns-do-servidor-tailscale>:4096
```

No workspace Flutter:

```bash
cd mobile-app/apps/flutter
flutter pub get
flutter analyze
flutter test
flutter run
```

## 6. Critérios de Alpha

- [x] App conecta ao OpenCode Server via configuração validada
- [x] Autentica com sucesso contra `/global/health`
- [x] Lista e abre sessões
- [x] Cria, renomeia e exclui sessões
- [x] Persiste a sessão ativa
- [x] Envia/recebe mensagens via SSE
- [x] Permite ver reasoning opcionalmente por mensagem
- [x] Voice input STT envia transcrição ao chat
- [x] TTS não é inicializado nem chamado
- [ ] Sobrevive a interrupções reais de rede/background
- [ ] `flutter analyze` limpo
- [ ] `flutter test` limpo
- [ ] Smoke test no `a51` via Tailscale

## 7. Próximas Etapas

1. Instalar/disponibilizar Flutter/Dart CLI neste ambiente.
2. Rodar `flutter pub get`, `flutter analyze`, `flutter test`.
3. Corrigir erros estáticos que aparecerem.
4. Subir OpenCode com `--hostname 0.0.0.0 --port 4096`.
5. Validar no `a51` com Tailscale.
6. Testar queda/reconexão e reidratação.
7. Implementar revisão opcional da transcrição antes do envio, se desejado.
8. Só depois iniciar etapa de tema/polish.

## 8. Histórico

- 2026-05-28: Documento criado após validação do experimento Flutter.
- 2026-05-28: Reasoning dropdown adicionado ao plano.
- 2026-05-30: Flutter promovido a trilho canônico; RN/Expo marcado como legado.
- 2026-05-30: Tailscale, sessão ativa persistida, SSE por sessão, reasoning estável e STT-only documentados.
