# PAI Mobile - M5 Status

> Estado atualizado em 2026-06-13 contra o código Flutter em `mobile-app/apps/flutter`.

## Resultado

M5 deixou de ser um plano de implementação e agora é uma milestone quase fechada em código. O app Flutter implementa streaming SSE, timeline de chat, reasoning inline, code blocks, permission/question cards, tool calls, shell commands, stop/abort, model picker, session info, todos, slash commands, revert, fork, share e STT. A trilha Pulse de notificações em background/TTS já existe em código, mas é tratada como validação separada do fechamento M5.

O smoke core real no Android `a51` passou via ADB reverse contra OpenCode. O fechamento rigoroso de M5 ainda depende dos fluxos live restantes: STT, permission/question continuando stream, reconexão/background de chat e attachments.

## Entregue

- Eventos SSE tipados em `lib/models/chat_event.dart`.
- Parsing de `session.next.text.*`, `session.next.reasoning.*`, `message.part.*`, `session.next.tool.*`, `session.next.shell.*`, `permission.*`, `question.*`, `todo.updated`, `session.error` e conexão.
- Markdown com code blocks syntax-highlighted.
- Reasoning inline expansível por mensagem.
- Permission cards com `Deny`, `Once`, `Always`.
- Question cards com radio/checkbox/campo custom.
- Respostas de questions persistidas e exibidas inline.
- Tool calls associados por assistant `messageID` e renderizados via `ToolCallBubble`.
- Shell commands associados por assistant `messageID` e renderizados via `ShellCommandBubble`.
- Migração de IDs locais para IDs reais do servidor.
- Reidratação de tool/shell a partir do histórico quando o servidor fornece as parts.
- Smoke core no `a51`: conexão, lista de sessões, text streaming, Kimi `k2p6`, rich `bash` tool block e reidratação de histórico.
- `flutter analyze` limpo.
- `flutter test` passando com 154 testes.

## Ainda Pendente

- Smoke live de STT no `a51`.
- Validação live de permission/question continuando o stream depois da resposta.
- Validação live de reconexão/background/foreground.
- Validação live de `session.next.shell.*` se o servidor atual emitir esse tipo de evento.
- Validação ou remoção da UI principal de attachments.
- Validação live separada de Pulse background/TTS no target phone com broker ativo.
- Helper dedicado para URL Tailscale, se necessário.

## Critérios de Fechamento M5

- [x] M5-1: Eventos SSE tipados existem.
- [x] M5-2: Code blocks renderizam com highlighting/copy.
- [x] M5-3: Reasoning aparece inline, não em modal.
- [x] M5-4: Date headers aparecem na timeline.
- [x] M5-5: Permission cards aparecem e respondem.
- [x] M5-6: Question cards aparecem e respondem/rejeitam.
- [x] M5-7: Tool calls são parseados e visíveis.
- [x] M5-8: Shell commands são parseados e visíveis.
- [x] M5-9: Tool calls são associados ao message ID correto.
- [x] M5-10: Shell commands são associados ao message ID correto.
- [x] M5-11: UI rica de tool/shell está integrada.
- [x] M5-12: `flutter analyze` passa sem issues.
- [x] M5-13: Smoke core no `a51` confirma conexão, text streaming, rich `bash` tool block e reidratação.
- [ ] M5-14: Smoke live no `a51` confirma todos os fluxos M5 restantes.

## Verificação Local Mais Recente

- `flutter pub get`: passou.
- `flutter analyze`: passou, sem issues.
- `flutter test`: passou, 154 testes.

## Próximo Passo

Rodar os fluxos restantes de `apps/flutter/TEST_GUIDE.md` no Android `a51`: STT, permission/question, reconexão/background de chat, shell nativo se emitido pelo servidor, Pulse background/TTS com broker ativo e attachment picker/send.
