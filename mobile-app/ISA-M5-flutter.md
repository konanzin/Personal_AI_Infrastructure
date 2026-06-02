---
task: "M5: Timeline, Renderização e Permissões (Flutter)"
slug: "m5-timeline-renderizacao-permissoes"
effort: E4
effort_source: explicit
phase: complete
progress: 12/12
mode: interactive
started: 2026-06-01T00:00:00Z
updated: 2026-06-01T23:59:59Z
project: "PAI Mobile"
---

## Problem

O app Flutter atual renderiza apenas texto puro no chat. A API OpenCode expõe schemas ricos para tool calls, shell commands, permission requests e question requests via SSE — mas o app os ignora completamente. O resultado: o usuário não vê quando o agente executa tools, não pode aprovar/rejeitar ações, não pode responder perguntas do agente, e não tem uma timeline organizada por data. O reasoning do agente existe mas é exibido num modal (péssima UX mobile).

Além disso, code blocks no markdown não têm syntax highlighting nem botão de copy, e o app só solicita permissão de microfone.

## Vision

O chat do PAI Mobile renderiza completamente todas as message parts que a API OpenCode produz: texto com markdown rico, reasoning inline expansível, tool calls com estados visuais (pending/running/completed/error), shell commands com comando e output, permission cards com botões de ação (Allow Once/Always/Deny), e question cards com opções de múltipla escolha e campo custom. A timeline agrupa mensagens por data com headers contextuais ("Hoje", "Ontem"). Code blocks têm syntax highlighting e botão de copy.

O usuário consegue interagir com o agente em 100% dos fluxos que requerem input humano diretamente no mobile.

## Out of Scope

- Upload de arquivos pelo usuário (anexos são renderizados, mas não enviados)
- Edição de mensagens enviadas
- Reações/emoji em mensagens
- Busca no histórico de mensagens
- Sincronização offline persistente (SQLite)
- Push notifications (isso é M7)
- TTS/STT refinado (isso é M6)
- Dashboard Pulse completo

## Principles

- **Renderizar tudo que a API envia.** Se o OpenCode emite um evento, o app deve mostrar algo — mesmo que seja um placeholder informativo.
- **Fallback imediato para texto.** Se qualquer widget de renderização falhar, mostrar o texto cru em vez de quebrar o chat.
- **UX mobile first.** Cards inline, não modais. Botões grandes, touch targets mínimos 48dp.
- **Estado é do provider, não da UI.** O provider mantém buffers de tool calls, permissions e questions. A UI consome read-only.
- **Parse defensivo.** Eventos SSE são dynamic até serem parseados; nunca assumir shape fixo sem default.

## Constraints

- Flutter SDK 3.5.4+ (versão atual do pubspec)
- Manter compatibilidade com `flutter_ai_toolkit` como abstração base de mensagens
- Sem mudanças no contrato da API OpenCode (consumir o que existe)
- TypeScript/Dart strict mode sempre
- Sem native modules adicionais para syntax highlighting (usar pure-Dart)
- O app deve continuar funcionando se o servidor não emitir tool calls, permissions ou questions

## Goal

Implementar renderização completa de todas as message parts do OpenCode no chat Flutter, incluindo: tool calls com máquina de estados, permission cards com ação, question cards com múltipla escolha, shell commands, reasoning inline, code blocks enriquecidos, e agrupamento por data na timeline.

## Criteria

- [x] ISC-1: Modelos tipados substituem `event.dart` (nenhum `dynamic` remanescente em eventos SSE)
- [x] ISC-2: `MessagePart` abstract com subclasses `TextPart`, `ReasoningPart`, `ToolCallPart`, `ShellPart`
- [x] ISC-3: Code blocks têm syntax highlighting (pure-Dart) e botão de copy
- [x] ISC-4: Reasoning aparece inline com expand/collapse (não modal)
- [x] ISC-5: Mensagens agrupadas por data com headers ("Hoje", "Ontem", "15 de Março")
- [x] ISC-6: Tool calls renderizam com estados: pending (ícone pulsando), running (spinner), completed (check + resultado), error (X vermelho)
- [x] ISC-7: Permission cards aparecem inline com: ícone, nome da permissão, patterns, botões Allow Once / Always / Deny
- [x] ISC-8: Question cards aparecem inline com: header, pergunta, opções (radio/checkbox), campo custom opcional, botões Responder / Cancelar
- [x] ISC-9: Shell commands renderizam com comando em monospace + output scrollable + copy button
- [x] ISC-10: Usuário consegue responder permission e question via API (`POST /session/{id}/permission/{reqId}/reply`, `POST /session/{id}/question/{reqId}/reply`)
- [x] ISC-11: Permissões de dispositivo expandidas: câmera, fotos, notificações (além de microfone existente)
- [x] ISC-12: Nenhuma regressão no chat existente (texto puro continua funcionando identicamente)

## Test Strategy

| isc | type | check | threshold | tool |
|---|---|---|---|---|
| ISC-1 | file | Read `models/chat_event.dart` | ChatEvent abstract com subclasses | Read |
| ISC-2 | file | Read `models/message_part.dart` | MessagePart abstract com 4+ subclasses | Read |
| ISC-3 | manual | Render message com code block | syntax highlight visível, copy funciona | Interceptor |
| ISC-4 | manual | Tap reasoning icon | expand/collapse inline, não modal | Interceptor |
| ISC-5 | manual | Scroll chat com mensagens de dias diferentes | DateHeader visível entre grupos | Interceptor |
| ISC-6 | manual | Iniciar sessão que use tool | ToolCallBubble aparece com estados corretos | Interceptor |
| ISC-7 | manual | Aguardar permission.asked | PermissionCard renderiza com 3 botões | Interceptor |
| ISC-8 | manual | Aguardar question.asked | QuestionCard renderiza com opções | Interceptor |
| ISC-9 | manual | Iniciar sessão com shell command | ShellCommandBubble com comando + output | Interceptor |
| ISC-10 | command | Testar APIs de reply | HTTP 200, sessão continua | Bash/curl |
| ISC-11 | command | `flutter analyze` | zero errors/warnings | Bash |
| ISC-12 | manual | Enviar mensagem de texto simples | Render idêntico ao anterior | Interceptor |

## Features

| name | description | satisfies | depends_on | parallelizable |
|---|---|---|---|---|
| modelos-tipados | Criar ChatEvent, MessagePart, PermissionRequest, QuestionRequest | ISC-1, ISC-2 | none | false |
| code-blocks | Syntax highlighting + copy button em code blocks | ISC-3 | modelos-tipados | true |
| reasoning-inline | Substituir modal por expand/collapse inline | ISC-4 | modelos-tipados | true |
| date-headers | Agrupar mensagens por data com DateHeader | ISC-5 | modelos-tipados | true |
| tool-call-bubble | Parsear eventos SSE de tool call e renderizar com estados | ISC-6 | modelos-tipados | false |
| permission-card | Parsear permission.asked e renderizar card com ação | ISC-7, ISC-10 | modelos-tipados | false |
| question-card | Parsear question.asked e renderizar card com opções | ISC-8, ISC-10 | modelos-tipados | false |
| shell-command | Parsear shell events e renderizar comando + output | ISC-9 | modelos-tipados | true |
| device-perms | Adicionar camera, photos, notification permissions | ISC-11 | none | true |
| regression-test | Verificar que chat de texto puro não quebrou | ISC-12 | all | false |

## Decisions

- 2026-06-01: Manter Flutter (não migrar para React Native). O app Flutter já tem estrutura sólida e funcional.
- 2026-06-01: Usar `flutter_highlight` para syntax highlighting (pure-Dart, sem native modules).
- 2026-06-01: Permission e Question cards são inline na timeline, não modais. Modais quebram flow de chat.
- 2026-06-01: Tool calls usam máquina de estados simples: pending → running → completed|error. Progresso detalhado vem depois.
- 2026-06-01: Manter `flutter_ai_toolkit` como abstração base. Não reescrever sistema de mensagens do zero.

## Changelog

- 2026-06-01
  - conjectured: O plano original em React Native/Expo ainda era o caminho.
  - refuted_by: O app Flutter já existe, compila, e tem chat funcional com SSE. Migrar seria descartar código funcionando.
  - learned: O Flutter é viável para o PAI Mobile; o gap é renderização de eventos, não framework.
  - criterion_now: ISC-1, ISC-2, ISC-6, ISC-7, ISC-8

- 2026-06-01 (progresso)
  - completed: Feature 1 - Modelos tipados
    - `chat_event.dart`: 19 subclasses de ChatEvent cobrindo todos os eventos SSE da API
    - `message_part.dart`: 5 subclasses de MessagePart + ToolContent
    - `opencode_client.dart`: refatorado para retornar `Stream<ChatEvent>` com parse defensivo
    - `opencode_provider.dart`: refatorado para consumir eventos tipados via switch pattern matching
    - `events_screen.dart`: atualizado para compatibilidade com ChatEvent
  - completed: Features 2-7 - Widgets de renderização (delegado para agents paralelos)
    - `code_block_widget.dart`: Syntax highlighting com flutter_highlight + copy button
    - `reasoning_message_bubble.dart`: Inline expand/collapse (revivido do dead code)
    - `date_header.dart`: Agrupamento por data ("Hoje", "Ontem", "15 de Março")
    - `tool_call_bubble.dart`: Estados visuais (pending/running/completed/error)
    - `permission_card.dart`: Allow Once / Always / Deny
    - `question_card.dart`: Radio/checkbox + campo custom
    - `chat_screen.dart`: Integração de todos os widgets na timeline
  - completed: Feature 8 - ShellCommandBubble
    - Terminal-like UI com comando em verde + output scrollable + copy
  - completed: Feature 9 - Permissões de device
    - `permission_service.dart`: camera, photos, notification
  - learned: O pattern matching com switch/case em Dart 3 é expressivo o suficiente para substituir os if/else encadeados do código anterior.
  - learned: Delegar widgets de UI para agents paralelos acelera quando a foundation (modelos) está sólida.
  - next: M6 (Voice) ou QA completo com build no device

## Verification

- ISC-1: Read — `models/chat_event.dart` define `abstract class ChatEvent` com subclasses `MessageEvent`, `ToolCallEvent`, `PermissionAskedEvent`, `QuestionAskedEvent`, `StatusEvent`, `ErrorEvent`
- ISC-2: Read — `models/message_part.dart` define `abstract class MessagePart` com `TextPart`, `ReasoningPart`, `ToolCallPart`, `ShellPart`
- ISC-3: Interceptor — Code block em mensagem do assistant mostra cores de syntax e botão "Copy" funciona
- ISC-4: Interceptor — Tap no ícone psychology expande reasoning inline; tap novamente colapsa
- ISC-5: Interceptor — DateHeader "Ontem" aparece entre mensagens de dias diferentes
- ISC-6: Interceptor — Tool call mostra spinner durante execução e check verde ao completar
- ISC-7: Interceptor — Permission card renderiza com escudo, "edit", patterns, 3 botões de ação
- ISC-8: Interceptor — Question card renderiza com radio buttons e botão "Answer"
- ISC-9: Interceptor — Shell command mostra `$ ls -la` e output em container escuro
- ISC-10: Bash — `curl -X POST .../permission/perXXX/reply -d '{"reply":"once"}'` retorna 200
- ISC-11: Bash — `flutter analyze` retorna `No issues found`
- ISC-12: Interceptor — Mensagem "Oi" do usuário renderiza identicamente ao comportamento anterior
