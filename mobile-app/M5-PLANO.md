# PAI Mobile — Plano M5: Timeline, Renderização e Permissões

> Baseado no código Flutter real. Ignora documentação desatualizada (React Native/Expo).

---

## 1. Contexto

O app Flutter atual tem chat funcional com streaming SSE, markdown básico, reasoning em modal (não inline), e apenas permissão de microfone. A API do OpenCode expõe schemas ricos para tool calls, shell commands, permissions e questions — mas o app não parseia nenhum desses eventos além de texto puro.

**Este plano fecha o gap entre a API real e a UI do app.**

---

## 2. Estado Atual (Baseline)

### O que já existe
- Chat com streaming SSE funcional (`chat_screen.dart`, 614 linhas)
- Markdown básico via `flutter_markdown`
- Reasoning armazenado em `Map<String, StringBuffer>` (exibido em modal)
- Timestamps por mensagem
- `flutter_ai_toolkit` como abstração de mensagens
- Conexão SSE com event normalization básico

### O que está faltando
- ❌ Tool calls: zero parse, zero UI
- ❌ Shell commands: zero
- ❌ Permission cards: zero
- ❌ Question cards: zero
- ❌ Reasoning inline (modal atual = ruim UX)
- ❌ Code blocks: sem syntax highlight, sem copy button
- ❌ Agrupamento de mensagens por data
- ❌ Typing indicator
- ❌ Anexos/arquivos

---

## 3. Estrutura da API OpenCode (do `opencode-api-doc.json`)

### Eventos SSE relevantes

| Evento | Descrição | Status no app |
|---|---|---|
| `session.next.text.delta/ended` | Texto do assistant | ✅ Funcional |
| `session.next.reasoning.delta/ended` | Reasoning do agente | ✅ Armazenado, modal |
| `session.next.tool.input.started/delta/ended` | Input da tool call | ❌ Ignorado |
| `session.next.tool.called` | Tool chamada | ❌ Ignorado |
| `session.next.tool.progress` | Progresso da tool | ❌ Ignorado |
| `session.next.tool.success/failed` | Resultado da tool | ❌ Ignorado |
| `session.next.shell.started/ended` | Comando shell | ❌ Ignorado |
| `permission.asked` | Agente pede permissão | ❌ Ignorado |
| `permission.replied` | Resposta da permissão | ❌ Ignorado |
| `question.asked` | Agente faz pergunta | ❌ Ignorado |
| `question.replied/rejected` | Resposta/rejeição | ❌ Ignorado |

### Schemas de message parts

```
SessionMessageAssistant
  ├── content: array<Part>
  │     ├── SessionMessageAssistantText (type: "text")
  │     ├── SessionMessageAssistantReasoning (type: "reasoning")
  │     └── SessionMessageAssistantTool (type: "tool")
  │           └── state: pending | running | completed | error
```

---

## 4. Blocos de Implementação

### Bloco 1: Modelos Tipados + Code Blocks
**Dependências:** nenhuma | **Tempo:** ~2-3h

#### 1.1 Substituir `event.dart` por modelos tipados
**Arquivos:** `lib/models/chat_event.dart`, `lib/models/message_part.dart`

```dart
// chat_event.dart
abstract class ChatEvent {
  final String type;
  final String? sessionId;
  
  ChatEvent({required this.type, this.sessionId});
}

class MessageEvent extends ChatEvent {
  final String messageId;
  final List<MessagePart> parts;
  
  MessageEvent({required this.messageId, required this.parts, super.sessionId}) 
    : super(type: 'message');
}

class ToolCallEvent extends ChatEvent {
  final String callId;
  final String toolName;
  final ToolCallState state;
  
  ToolCallEvent({...}) : super(type: 'tool_call');
}

class PermissionAskedEvent extends ChatEvent {
  final PermissionRequest request;
  
  PermissionAskedEvent({required this.request, super.sessionId})
    : super(type: 'permission_asked');
}

class QuestionAskedEvent extends ChatEvent {
  final QuestionRequest request;
  
  QuestionAskedEvent({required this.request, super.sessionId})
    : super(type: 'question_asked');
}

class StatusEvent extends ChatEvent { ... }
class ErrorEvent extends ChatEvent { ... }
```

```dart
// message_part.dart
abstract class MessagePart {
  String get type;
}

class TextPart implements MessagePart {
  final String text;
  @override String get type => 'text';
  TextPart({required this.text});
}

class ReasoningPart implements MessagePart {
  final String id;
  final String text;
  @override String get type => 'reasoning';
  ReasoningPart({required this.id, required this.text});
}

class ToolCallPart implements MessagePart {
  final String id;
  final String name;
  final ToolCallState state;
  final Map<String, dynamic> input;
  final List<ToolContent> content;
  @override String get type => 'tool';
  ToolCallPart({...});
}

class ShellPart implements MessagePart {
  final String callId;
  final String command;
  final String output;
  @override String get type => 'shell';
  ShellPart({...});
}
```

#### 1.2 Melhorar code blocks no markdown
**Arquivos:** `pubspec.yaml`, `lib/widgets/code_block_widget.dart`

```yaml
# pubspec.yaml
dependencies:
  # ...existing...
  flutter_highlight: ^0.7.0  # ou code_text_field
```

```dart
// code_block_widget.dart
class CodeBlockWidget extends StatelessWidget {
  final String code;
  final String? language;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        children: [
          // Header com linguagem e botão copy
          Row(
            children: [
              Text(language ?? 'text', style: TextStyle(fontSize: 12)),
              IconButton(
                icon: Icon(Icons.copy),
                onPressed: () => _copyToClipboard(code),
              ),
            ],
          ),
          // Code com syntax highlighting
          HighlightView(
            code,
            language: language ?? 'plaintext',
            theme: githubTheme,
          ),
        ],
      ),
    );
  }
}
```

**Modificar `chat_screen.dart`:** Override element builder do `MarkdownBody` para interceptar `pre`/`code` e renderizar `CodeBlockWidget`.

#### 1.3 Atualizar provider
**Arquivo:** `lib/providers/opencode_provider.dart`

- Trocar `_reasoningBuffers: Map<String, StringBuffer>` por `Map<String, ReasoningPart>`
- Adicionar `Map<String, ToolCallPart> _toolCallBuffers`
- Adicionar `Map<String, PermissionRequest> _pendingPermissions`
- Adicionar `Map<String, QuestionRequest> _pendingQuestions`
- Preparar estrutura para typed events

---

### Bloco 2: Timeline + Reasoning Inline + Typing
**Dependências:** Bloco 1 | **Tempo:** ~2h

#### 2.1 Reasoning inline expansível
**Arquivo:** `lib/widgets/reasoning_message_bubble.dart` (reviver dead code)

- O widget já existe mas não é usado
- Integrar na `chat_screen.dart` substituindo o modal bottom sheet
- Usar o modelo tipado `ReasoningPart` do Bloco 1
- Estados: collapsed (mostra ícone `psychology` + "Show reasoning") → expanded (mostra texto completo)

#### 2.2 Agrupar mensagens por data
**Arquivos:** `lib/widgets/date_header.dart`, `lib/screens/chat_screen.dart`

```dart
// date_header.dart
class DateHeader extends StatelessWidget {
  final DateTime date;
  
  @override
  Widget build(BuildContext context) {
    final label = _formatDate(date); // "Hoje", "Ontem", "15 de Março"
    return Center(
      child: Chip(label: Text(label)),
    );
  }
}
```

- Pré-processar `history` em `List<ChatSection>` antes do `ListView.builder`
- `ChatSection` = data + lista de mensagens
- Renderizar `DateHeader` como primeiro item de cada seção

#### 2.3 Typing indicator
**Arquivo:** `lib/widgets/typing_indicator.dart`

- Bubble animada com 3 pontinhos pulsando
- Mostrar quando `connectionState == streaming` e ainda não chegou primeiro token
- Remover no primeiro `text.delta` ou após timeout

---

### Bloco 3: Tool Calls
**Dependências:** Bloco 1 | **Tempo:** ~4-6h

#### 3.1 Parsear eventos SSE de tool calls
**Arquivo:** `lib/services/opencode_client.dart`

Adicionar ao event normalization:

```dart
// Novos eventos a reconhecer
'session.next.tool.input.started' → ToolCallInputStarted
'session.next.tool.input.delta'   → ToolCallInputDelta  
'session.next.tool.input.ended'   → ToolCallInputEnded
'session.next.tool.called'        → ToolCallCalled
'session.next.tool.progress'      → ToolCallProgress
'session.next.tool.success'       → ToolCallSuccess
'session.next.tool.failed'        → ToolCallFailed
```

#### 3.2 Modelar tool calls no provider
**Arquivo:** `lib/providers/opencode_provider.dart`

```dart
// Buffers para tool calls em streaming
final Map<String, ToolCallPart> _toolCallBuffers = {};

// Máquina de estados
// pending → running → completed|error

void _handleToolCallEvent(ToolCallEvent event) {
  switch (event.state) {
    case ToolCallState.pending:
      _toolCallBuffers[event.callId] = ToolCallPart(
        id: event.callId,
        name: event.toolName,
        state: ToolCallState.pending,
        input: {},
        content: [],
      );
    case ToolCallState.running:
      _toolCallBuffers[event.callId]?.state = ToolCallState.running;
      // Acumular deltas de input
    case ToolCallState.completed:
      _toolCallBuffers[event.callId]?.state = ToolCallState.completed;
      _toolCallBuffers[event.callId]?.content = event.content;
    case ToolCallState.error:
      _toolCallBuffers[event.callId]?.state = ToolCallState.error;
  }
  notifyListeners();
}
```

#### 3.3 Criar widgets
**Arquivos:** `lib/widgets/tool_call_bubble.dart`, `lib/widgets/tool_result_widget.dart`

```dart
// tool_call_bubble.dart
class ToolCallBubble extends StatelessWidget {
  final ToolCallPart toolCall;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _statusColor),
        color: _statusColor.withOpacity(0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: ícone + nome da tool + status
          Row(
            children: [
              _statusIcon,
              SizedBox(width: 8),
              Text(toolCall.name, style: TextStyle(fontWeight: FontWeight.w600)),
              Spacer(),
              _statusChip,
            ],
          ),
          // Input (collapsible)
          if (toolCall.input.isNotEmpty)
            ExpansionTile(
              title: Text('Arguments', style: TextStyle(fontSize: 12)),
              children: [
                // JSON pretty-printed
                Text(JsonEncoder.withIndent('  ').convert(toolCall.input)),
              ],
            ),
          // Resultado
          if (toolCall.state == ToolCallState.completed)
            ToolResultWidget(content: toolCall.content),
          // Erro
          if (toolCall.state == ToolCallState.error)
            Text('Error: ${toolCall.error}', style: TextStyle(color: Colors.red)),
        ],
      ),
    );
  }
}
```

```dart
// tool_result_widget.dart
class ToolResultWidget extends StatelessWidget {
  final List<ToolContent> content;
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: content.map((item) {
        switch (item.type) {
          case 'text':
            return MarkdownBody(data: item.text);
          case 'file':
            return FileAttachmentChip(
              name: item.name,
              mimeType: item.mime,
              uri: item.uri,
            );
          default:
            return Text('Unknown content type: ${item.type}');
        }
      }).toList(),
    );
  }
}
```

#### 3.4 Integrar no chat
**Arquivo:** `lib/screens/chat_screen.dart`

- Detectar mensagens do assistant que contêm tool calls
- Inserir `ToolCallBubble` inline na timeline
- Associar tool call ao messageId correto

---

### Bloco 4: Permission Cards (Agente pedindo autorização)
**Dependências:** Bloco 1 | **Tempo:** ~3h

#### 4.1 Parsear eventos SSE
**Arquivo:** `lib/services/opencode_client.dart`

```dart
// Novos eventos
'permission.asked'   → PermissionAskedEvent
'permission.replied' → PermissionRepliedEvent
```

#### 4.2 Modelar no provider
**Arquivo:** `lib/providers/opencode_provider.dart`

```dart
// PermissionRequest do schema da API
class PermissionRequest {
  final String id;              // ^per
  final String sessionID;
  final String permission;      // "edit", "bash", "write", etc.
  final List<String> patterns;  // glob patterns
  final Map<String, dynamic> metadata;
  final List<String> always;
  final ToolReference? tool;    // messageID + callID
}

// Buffer
final Map<String, PermissionRequest> _pendingPermissions = {};

// API para responder
Future<void> replyToPermission(String requestId, PermissionReply reply) async {
  await client.post('/session/$currentSessionId/permission/$requestId/reply', 
    body: {'reply': reply.value}); // "once" | "always" | "reject"
}
```

#### 4.3 Widget `PermissionCard`
**Arquivo:** `lib/widgets/permission_card.dart`

```dart
class PermissionCard extends StatelessWidget {
  final PermissionRequest request;
  final Function(PermissionReply) onReply;
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.shield, color: Theme.of(context).colorScheme.error),
                SizedBox(width: 8),
                Text(
                  'Permission Required',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 12),
            // Descrição
            Text('PAI wants to execute:'),
            SizedBox(height: 4),
            Text(
              request.permission,
              style: TextStyle(
                fontFamily: 'monospace',
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
            // Patterns afetados
            if (request.patterns.isNotEmpty) ...[
              SizedBox(height: 8),
              Text('Patterns:', style: TextStyle(fontSize: 12)),
              ...request.patterns.map((p) => Chip(
                label: Text(p, style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
              )),
            ],
            SizedBox(height: 16),
            // Botões de ação
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onReply(PermissionReply.once),
                    child: Text('Allow Once'),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => onReply(PermissionReply.always),
                    child: Text('Always'),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: () => onReply(PermissionReply.reject),
                    child: Text('Deny', style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

#### 4.4 Integrar no chat
**Arquivo:** `lib/screens/chat_screen.dart`

- Inserir `PermissionCard` inline na timeline quando `_pendingPermissions` não vazio
- A sessão do agente pausa até usuário responder (o backend aguarda)
- Estado após resposta: checkmark verde (allowed) ou X vermelho (denied)

---

### Bloco 5: Question Cards (Agente fazendo perguntas)
**Dependências:** Bloco 1 | **Tempo:** ~3h

#### 5.1 Parsear eventos SSE
**Arquivo:** `lib/services/opencode_client.dart`

```dart
// Novos eventos
'question.asked'    → QuestionAskedEvent
'question.replied'  → QuestionRepliedEvent
'question.rejected' → QuestionRejectedEvent
```

#### 5.2 Modelar no provider
**Arquivo:** `lib/providers/opencode_provider.dart`

```dart
// QuestionRequest do schema da API
class QuestionRequest {
  final String id;                  // ^que
  final String sessionID;
  final List<QuestionInfo> questions;
  final QuestionTool? tool;         // messageID + callID
}

class QuestionInfo {
  final String question;            // pergunta completa
  final String header;              // label curto (max 30 chars)
  final List<QuestionOption> options;
  final bool multiple;              // multi-select?
  final bool custom;                // permite resposta custom?
}

class QuestionOption {
  final String label;               // 1-5 palavras
  final String description;         // explicação
}

// Buffer
final Map<String, QuestionRequest> _pendingQuestions = {};

// API para responder
Future<void> replyToQuestion(String requestId, List<List<String>> answers) async {
  await client.post('/session/$currentSessionId/question/$requestId/reply',
    body: {'answers': answers});
}

Future<void> rejectQuestion(String requestId) async {
  await client.post('/session/$currentSessionId/question/$requestId/reject');
}
```

#### 5.3 Widget `QuestionCard`
**Arquivo:** `lib/widgets/question_card.dart`

```dart
class QuestionCard extends StatefulWidget {
  final QuestionRequest request;
  final Function(List<List<String>>) onReply;
  final Function() onReject;
  
  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  // Estado de seleção
  Map<int, Set<String>> selectedOptions = {};
  Map<int, String> customAnswers = {};
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.help_outline, color: Theme.of(context).colorScheme.primary),
                SizedBox(width: 8),
                Text(
                  'Question',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 16),
            // Perguntas
            ...widget.request.questions.asMap().entries.map((entry) {
              final index = entry.key;
              final question = entry.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header da pergunta
                  Text(
                    question.header,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(question.question),
                  SizedBox(height: 8),
                  // Opções
                  if (question.multiple)
                    ...question.options.map((opt) => CheckboxListTile(
                      title: Text(opt.label),
                      subtitle: Text(opt.description, style: TextStyle(fontSize: 12)),
                      value: selectedOptions[index]?.contains(opt.label) ?? false,
                      onChanged: (checked) => setState(() {
                        selectedOptions[index] ??= {};
                        if (checked!) {
                          selectedOptions[index]!.add(opt.label);
                        } else {
                          selectedOptions[index]!.remove(opt.label);
                        }
                      }),
                    ))
                  else
                    ...question.options.map((opt) => RadioListTile<String>(
                      title: Text(opt.label),
                      subtitle: Text(opt.description, style: TextStyle(fontSize: 12)),
                      value: opt.label,
                      groupValue: selectedOptions[index]?.firstOrNull,
                      onChanged: (value) => setState(() {
                        selectedOptions[index] = {value!};
                      }),
                    )),
                  // Campo custom se permitido
                  if (question.custom)
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Your answer...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => customAnswers[index] = value,
                    ),
                  SizedBox(height: 16),
                ],
              );
            }),
            // Botões de ação
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onReject,
                    child: Text('Cancel'),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      // Montar respostas
                      final answers = widget.request.questions.asMap().entries.map((entry) {
                        final index = entry.key;
                        final selected = selectedOptions[index]?.toList() ?? [];
                        if (entry.value.custom && customAnswers[index]?.isNotEmpty == true) {
                          return [...selected, customAnswers[index]!];
                        }
                        return selected;
                      }).toList();
                      widget.onReply(answers);
                    },
                    child: Text('Answer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

#### 5.4 Integrar no chat
**Arquivo:** `lib/screens/chat_screen.dart`

- Inserir `QuestionCard` inline na timeline
- Sessão pausa até usuário responder ou cancelar
- Estado após resposta: resumo da resposta dada (collapsible)

---

### Bloco 6: Shell Commands + Device Permissions + Attachments
**Dependências:** Bloco 1-5 | **Tempo:** ~2h

#### 6.1 Shell command rendering
**Arquivo:** `lib/widgets/shell_command_bubble.dart`

```dart
class ShellCommandBubble extends StatelessWidget {
  final ShellPart shell;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.black87,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Comando
          Row(
            children: [
              Icon(Icons.terminal, size: 14, color: Colors.green),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '\$ ${shell.command}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.green,
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy, size: 16, color: Colors.grey),
                onPressed: () => _copyToClipboard(shell.command),
              ),
            ],
          ),
          Divider(color: Colors.grey.shade800),
          // Output
          Container(
            constraints: BoxConstraints(maxHeight: 300),
            child: SingleChildScrollView(
              child: Text(
                shell.output,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.grey.shade300,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

#### 6.2 Permissões de dispositivo expandidas
**Arquivo:** `lib/services/permission_service.dart`

```dart
class PermissionService {
  // ...existing microphone...
  
  Future<PermissionStatus> requestCameraPermission() async {
    return await Permission.camera.request();
  }
  
  Future<PermissionStatus> requestPhotosPermission() async {
    return await Permission.photos.request();
  }
  
  Future<PermissionStatus> requestNotificationPermission() async {
    return await Permission.notification.request();
  }
  
  void showRationale(BuildContext context, String permission, VoidCallback onRequest) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$permission Permission'),
        content: Text('This permission is needed to...'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(onPressed: () {
            Navigator.pop(context);
            onRequest();
          }, child: Text('Allow')),
        ],
      ),
    );
  }
}
```

#### 6.3 File attachment rendering mínimo
**Arquivo:** `lib/widgets/file_attachment_chip.dart`

```dart
class FileAttachmentChip extends StatelessWidget {
  final String name;
  final String mimeType;
  final String? uri;
  
  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(_iconForMime(mimeType)),
      label: Text(name),
      deleteIcon: uri != null ? Icon(Icons.open_in_new) : null,
      onDeleted: uri != null ? () => _openFile(uri!) : null,
    );
  }
}
```

---

## 5. Ordem de Execução

```
Bloco 1: Modelos + Code Blocks     → Foundation
     ↓
Bloco 2: Timeline + Reasoning      → UX Chat
     ↓
Bloco 3: Tool Calls                → Core
     ↓
Bloco 4: Permission Cards          ← NOVO (bloqueante)
     ↓
Bloco 5: Question Cards            ← NOVO (bloqueante)
     ↓
Bloco 6: Shell + Perms + Anexos    → Polish
```

Cada bloco é **mergeável independentemente**. Prioridade: Bloco 1 → Bloco 4/5 (bloqueantes) → Bloco 3 → Bloco 2 → Bloco 6.

---

## 6. Estimativas Atualizadas

| Bloco | Descrição | Tempo Estimado |
|---|---|---|
| **1** | Modelos tipados + code blocks | ~2-3h |
| **2** | Timeline + reasoning inline + typing | ~2h |
| **3** | Tool calls (parse + model + widgets + integração) | ~4-6h |
| **4** | Permission cards | ~3h |
| **5** | Question cards | ~3h |
| **6** | Shell + device permissions + anexos | ~2h |
| **Total** | | **~16-19h** |

---

## 7. Critérios de Pronto do M5

- [ ] Code blocks têm syntax highlighting e botão de copy
- [ ] Reasoning aparece inline (expand/collapse) na mensagem do assistant
- [ ] Mensagens agrupadas por data com headers
- [ ] Tool calls renderizam com estados (pending/running/completed/error)
- [ ] **Permission cards aparecem inline com botões Allow Once/Always/Deny**
- [ ] **Question cards aparecem inline com opções de múltipla escolha e campo custom**
- [ ] Shell commands renderizam com comando + output
- [ ] Permissões de câmera/fotos/notificações implementadas
- [ ] Nenhum `dynamic` remanescente nos eventos SSE
- [ ] Usuário consegue aprovar/rejeitar ações do agente no mobile
- [ ] Usuário consegue responder perguntas do agente no mobile

---

## 8. Riscos e Mitigação

| Risco | Impacto | Mitigação |
|---|---|---|
| Schema da API mudar | Alto | Isolar parse em `opencode_client.dart`; tipos compartilhados em `models/` |
| Tool calls complexas | Médio | Começar com estado binário (running/completed); progresso vem depois |
| Permissions múltiplas simultâneas | Médio | Queue de permissions no provider; responder uma por vez |
| Questions com muitas opções | Baixo | Scroll interno no card; limitar altura máxima |
| Syntax highlighting pesado | Baixo | Lazy load do highlight; cache de temas |

---

*Plano criado com base no código real do app Flutter e no schema da API OpenCode (`opencode-api-doc.json`).*
