import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';

import '../models/chat_event.dart';
import '../models/message_part.dart';
import '../services/connectivity_service.dart';
import '../services/opencode_client.dart';

/// Provider que integra o OpenCode Server com o Flutter AI Toolkit.
/// 
/// Implementa a interface LlmProvider, convertendo entre:
/// - ChatMessage (AI Toolkit) ↔ OpenCode API/SSE
/// 
/// Suporta:
/// - Streaming de respostas via SSE
/// - Histórico de mensagens
/// - Tool calls (futuro)
class OpenCodeProvider extends LlmProvider with ChangeNotifier {
  final OpenCodeClient client;
  String? _currentSessionId;
  StreamSubscription? _sseSubscription;
  
  final List<ChatMessage> _history = [];
  
  /// Mapa de messageID -> reasoning text
  final Map<String, StringBuffer> _reasoningBuffers = {};

  /// Mapa de messageID -> timestamp
  final Map<String, DateTime> _messageTimestamps = {};

  /// MessageIDs na mesma ordem de [_history]. Valores locais temporários
  /// são substituídos quando o servidor emite o ID real via SSE.
  final List<String?> _historyMessageIds = [];

  /// Mapa de partID -> messageID para associar deltas ao balão correto.
  final Map<String, String> _partMessageIds = {};

  /// Mapa de callID -> ToolCallPart para tool calls em progresso.
  final Map<String, ToolCallPart> _toolCallBuffers = {};

  /// Mapa de requestID -> PermissionRequest para permissões pendentes.
  final Map<String, PermissionRequest> _pendingPermissions = {};

  /// Mapa de requestID -> QuestionRequest para perguntas pendentes.
  final Map<String, QuestionRequest> _pendingQuestions = {};

  /// Mapa de callID -> ShellPart para shell commands.
  final Map<String, ShellPart> _shellBuffers = {};

  int _localMessageCounter = 0;
  
  /// ID da última mensagem do usuário enviada (para filtrar deltas de volta)
  String? _lastUserMessageId;
  
  /// Serviço de conectividade
  final ConnectivityService _connectivity = ConnectivityService();
  
  OpenCodeProvider({
    required this.client,
    String? sessionId,
    Iterable<ChatMessage>? history,
  }) : _currentSessionId = sessionId {
    if (history != null) {
      _history.addAll(history);
      _historyMessageIds.addAll(List<String?>.filled(_history.length, null));
    }
    _connectivity.addListener(_onConnectionStateChanged);
    _connectivity.startMonitoring();
  }
  
  /// ID da sessão atual do OpenCode
  String? get currentSessionId => _currentSessionId;
  
  /// Retorna o reasoning de uma mensagem específica
  String? getReasoningForMessage(String messageId) {
    final buffer = _reasoningBuffers[messageId];
    if (buffer == null || buffer.isEmpty) return null;
    return buffer.toString();
  }
  
  /// Retorna todas as mensagens que têm reasoning
  Iterable<String> get messagesWithReasoning => _reasoningBuffers.keys;

  /// Retorna o timestamp de uma mensagem pelo ID
  DateTime? getMessageTimestamp(String messageId) {
    return _messageTimestamps[messageId];
  }

  /// Retorna a lista de messageIDs na ordem do histórico
  List<String> get messageIds => List.unmodifiable(_historyMessageIds.whereType<String>());

  /// Retorna o messageID associado ao índice visual do histórico.
  String? getMessageIdAt(int index) {
    if (index < 0 || index >= _historyMessageIds.length) return null;
    return _historyMessageIds[index];
  }

  /// Retorna o reasoning associado ao índice visual do histórico.
  String? getReasoningForHistoryIndex(int index) {
    final messageId = getMessageIdAt(index);
    if (messageId == null) return null;
    return getReasoningForMessage(messageId);
  }

  /// Returns all tool calls associated with a message
  ///
  /// For now, returns all buffered tool calls since the server
  /// does not yet provide message-level association.
  List<ToolCallPart> getToolCallsForMessage(String messageId) {
    return _toolCallBuffers.values.toList();
  }

  /// Returns all pending or running tool calls
  Iterable<ToolCallPart> get pendingToolCalls =>
      _toolCallBuffers.values.where(
        (t) => t.state == ToolCallState.pending || t.state == ToolCallState.running,
      );

  /// Returns all completed or error tool calls
  Iterable<ToolCallPart> get completedToolCalls =>
      _toolCallBuffers.values.where(
        (t) => t.state == ToolCallState.completed || t.state == ToolCallState.error,
      );

  /// Estado da conexão
  ConnectionStatus get connectionState => _connectivity.state;
  
  /// Se está online
  bool get isOnline => _connectivity.isOnline;
  
  /// Se está tentando reconectar
  bool get isConnecting => _connectivity.isConnecting;

  /// Todas as permissões pendentes
  Map<String, PermissionRequest> get pendingPermissions => Map.unmodifiable(_pendingPermissions);

  /// Todas as perguntas pendentes
  Map<String, QuestionRequest> get pendingQuestions => Map.unmodifiable(_pendingQuestions);

  /// Todos os shell commands
  Map<String, ShellPart> get shellCommands => Map.unmodifiable(_shellBuffers);

  /// Retorna shell commands associados a uma mensagem
  List<ShellPart> getShellCommandsForMessage(String messageId) {
    return _shellBuffers.values.toList();
  }

  /// Responde a uma solicitação de permissão
  Future<void> replyToPermission(String requestId, PermissionReply reply) async {
    final request = _pendingPermissions[requestId];
    if (request == null) return;

    final replyValue = switch (reply) {
      PermissionReply.once => 'once',
      PermissionReply.always => 'always',
      PermissionReply.reject => 'reject',
    };

    await client.post(
      '/session/$currentSessionId/permission/$requestId/reply',
      body: jsonEncode({'reply': replyValue}),
    );

    _pendingPermissions.remove(requestId);
    notifyListeners();
    
    // Reabre SSE para capturar continuação da resposta
    _reopenSSEForContinuation();
  }

  /// Responde a uma pergunta
  Future<void> replyToQuestion(String requestId, List<List<String>> answers) async {
    final request = _pendingQuestions[requestId];
    if (request == null) {
      debugPrint('[PAI_SSE] replyToQuestion: request not found for id=$requestId');
      return;
    }

    debugPrint('[PAI_SSE] replyToQuestion: posting reply for requestId=$requestId');
    try {
      final response = await client.post(
        '/session/$currentSessionId/question/$requestId/reply',
        body: jsonEncode({'answers': answers}),
      );
      debugPrint('[PAI_SSE] replyToQuestion: POST success, status=${response.statusCode}');
    } catch (e) {
      debugPrint('[PAI_SSE] replyToQuestion: POST failed: $e');
      return;
    }

    _pendingQuestions.remove(requestId);
    notifyListeners();
    
    // Reabre SSE para capturar continuação da resposta
    _reopenSSEForContinuation();
  }

  /// Rejeita uma pergunta
  Future<void> rejectQuestion(String requestId) async {
    final request = _pendingQuestions[requestId];
    if (request == null) return;

    await client.post(
      '/session/$currentSessionId/question/$requestId/reject',
    );

    _pendingQuestions.remove(requestId);
    notifyListeners();
  }
  
  /// Carrega o histórico de mensagens de uma sessão existente
  Future<void> loadHistory() async {
    if (_currentSessionId == null) return;
    
    try {
      final messages = await client.getSessionMessages(_currentSessionId!);
      
      _history.clear();
      _reasoningBuffers.clear();
      _messageTimestamps.clear();
      _historyMessageIds.clear();
      _partMessageIds.clear();
      
      for (final msg in messages) {
        if (msg is! Map) continue;
        final info = msg['info'] as Map<String, dynamic>?;
        final role = info?['role'] as String?;
        final messageId = info?['id'] as String?;
        final parts = msg['parts'] as List<dynamic>?;
        
        if (role == null || parts == null) continue;
        
        // Extrai timestamp do servidor
        final timestamp = _parseTimestamp(info?['time'] ?? info?['created']);
        
        // Extrai texto e reasoning das parts
        final textBuffer = StringBuffer();
        final reasoningBuffer = StringBuffer();
        
        for (final part in parts) {
          if (part is! Map) continue;

          final partType = part['type'] as String?;
          final partText = part['text'] as String?;
          final partId = part['id'] as String?;

          if (partId != null && messageId != null) {
            _partMessageIds[partId] = messageId;
          }
          
          if (partType == 'text' && partText != null) {
            textBuffer.write(partText);
          } else if (partType == 'reasoning' && partText != null) {
            reasoningBuffer.write(partText);
          }
        }
        
        final messageText = textBuffer.toString();
        if (messageText.isEmpty) continue;
        
        // Cria ChatMessage
        if (role == 'user') {
          _history.add(ChatMessage.user(messageText, const []));
          _historyMessageIds.add(messageId);
        } else if (role == 'assistant') {
          _history.add(ChatMessage.llm()..append(messageText));
          _historyMessageIds.add(messageId);
          
          // Salva reasoning se existir
          if (reasoningBuffer.isNotEmpty && messageId != null) {
            _reasoningBuffers[messageId] = reasoningBuffer;
          }
        } else {
          continue;
        }

        if (timestamp != null && messageId != null) {
          _messageTimestamps[messageId] = timestamp;
        }
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading history: $e');
    }
  }
  
  /// Cria uma nova sessão no OpenCode
  Future<void> createSession({String? title}) async {
    final session = await client.createSession(title: title);
    _currentSessionId = session['id'] as String?;
    _history.clear();
    _reasoningBuffers.clear();
    _messageTimestamps.clear();
    _historyMessageIds.clear();
    _partMessageIds.clear();
    notifyListeners();
  }
  
  /// Seleciona uma sessão existente
  void setSession(String sessionId, {Iterable<ChatMessage>? history}) {
    _currentSessionId = sessionId;
    _history.clear();
    _historyMessageIds.clear();
    _reasoningBuffers.clear();
    _messageTimestamps.clear();
    _partMessageIds.clear();
    if (history != null) {
      _history.addAll(history);
      _historyMessageIds.addAll(List<String?>.filled(_history.length, null));
    }
    notifyListeners();
  }
  
  /// Callback para mudanças de estado de conexão
  void _onConnectionStateChanged(ConnectionStatus state) {
    notifyListeners();
  }
  
  /// Força reconexão manual
  Future<void> reconnect() async {
    _connectivity.cancelReconnect();
    await _rehydrateCurrentSession();
  }

  @override
  Stream<String> generateStream(
    String prompt, {
    Iterable<Attachment> attachments = const [],
  }) async* {
    // Se não tem sessão, cria uma nova
    if (_currentSessionId == null) {
      await createSession();
    }
    
    if (_currentSessionId == null) {
      throw Exception('Failed to create session');
    }
    
    // Primeiro conecta ao SSE para não perder eventos
    final responseStream = _listenForResponse();
    
    // Depois envia a mensagem (fire and forget)
    client.sendMessage(_currentSessionId!, prompt).catchError((e) {
      debugPrint('[PAI_SSE] Error sending message: $e');
    });
    
    // Repassa chunks do SSE
    await for (final chunk in responseStream) {
      yield chunk;
    }
  }

  @override
  Stream<String> sendMessageStream(
    String prompt, {
    Iterable<Attachment> attachments = const [],
  }) {
    debugPrint('[PAI_VOICE] sendMessageStream called with: "$prompt", attachments: ${attachments.length}');
    
    // Adiciona mensagem do usuário ao histórico
    final userMessage = ChatMessage.user(prompt, attachments);
    final llmMessage = ChatMessage.llm();
    _history.addAll([userMessage, llmMessage]);
    _historyMessageIds.addAll([null, null]);
    notifyListeners();
    
    // Gera resposta e mapeia para atualizar histórico
    final response = generateStream(prompt, attachments: attachments);
    
    return response.map((chunk) {
      debugPrint('[PAI_SSE] Chunk received in stream: "${chunk.substring(0, chunk.length > 30 ? 30 : chunk.length)}..." | Current text length: ${llmMessage.text?.length ?? 0}');
      llmMessage.append(chunk);
      notifyListeners();
      return chunk;
    });
  }
  
  /// Escuta eventos SSE e extrai texto da resposta
  Stream<String> _listenForResponse() {
    // Fecha qualquer conexão SSE anterior
    _sseSubscription?.cancel();
    _sseSubscription = null;
    client.unsubscribe();
    
    final controller = StreamController<String>(
      onCancel: () {
        // Fecha a conexão SSE quando o stream é cancelado
        _sseSubscription?.cancel();
        _sseSubscription = null;
        client.unsubscribe();
      },
    );
    bool responseEnded = false;
    
    // Rastreia partIDs por tipo para filtrar apenas texto da resposta
    final textPartIds = <String>{};
    final reasoningPartIds = <String>{};
    
    String? activeAssistantMessageId = _latestAssistantMessageId();

    void closeResponse() {
      if (responseEnded) return;
      responseEnded = true;
      _sseSubscription?.cancel();
      _sseSubscription = null;
      if (!controller.isClosed) controller.close();
    }

    void appendReasoning(String reasoning, {String? messageId}) {
      if (reasoning.isEmpty) return;
      final targetId = messageId ?? activeAssistantMessageId ?? _ensureAssistantMessageId();
      activeAssistantMessageId = targetId;
      _reasoningBuffers.putIfAbsent(targetId, () => StringBuffer());
      _reasoningBuffers[targetId]!.write(reasoning);
      notifyListeners();
    }
    
    // Marca como conectando
    _connectivity.markOnline();
    
    // Inscreve no SSE
    final stream = client.subscribeToEvents();
    _sseSubscription = stream.listen(
      (event) {
        // Heartbeat - qualquer evento indica conexão ativa
        _connectivity.heartbeat();

        debugPrint('[PAI_SSE] Event received: ${event.runtimeType} | type: ${event.type} | sessionId: ${event.sessionId}');

        if (!_belongsToCurrentSession(event)) {
          debugPrint('[PAI_SSE] Event ignored - wrong session');
          return;
        }

        switch (event) {
          // Message metadata updates
          case MessageEvent e:
            final info = _extractMessageUpdateInfo(e.payload);
            final messageId = info?['id'] as String?;
            final role = info?['role'] as String?;
            final timestamp = _parseTimestamp(info?['time'] ?? info?['created']);

            if (messageId != null && role != null) {
              if (role == 'assistant') {
                _bindMessageId(messageId, MessageOrigin.llm, timestamp: timestamp);
                activeAssistantMessageId = messageId;
              } else if (role == 'user') {
                _bindMessageId(messageId, MessageOrigin.user, timestamp: timestamp);
                _lastUserMessageId = messageId;
                debugPrint('[PAI_SSE] Stored last user message ID: $messageId');
              }
            }

            // Handle message.part.updated inside payload
            final partInfo = _extractPartInfo(e.payload);
            if (partInfo != null) {
              final partId = partInfo['id'] as String?;
              final partType = partInfo['type'] as String?;
              final partMessageId = partInfo['messageID'] as String?;
              
              if (partId != null && partType != null) {
                if (partMessageId != null) {
                  _partMessageIds[partId] = partMessageId;
                }

                if (partType == 'text') {
                  textPartIds.add(partId);
                  // Processa texto de message.part.updated apenas se for da resposta do assistente
                  final partText = partInfo['text'] as String?;
                  if (partText != null && partText.isNotEmpty) {
                    // Verifica se é mensagem do usuário (eco)
                    final isUserMessage = partMessageId != null && partMessageId == _lastUserMessageId;
                    if (isUserMessage) {
                      debugPrint('[PAI_SSE] Ignoring user message echo: ${partText.substring(0, partText.length > 30 ? 30 : partText.length)}...');
                    } else {
                      debugPrint('[PAI_SSE] ✓ Text from assistant message.part.updated: ${partText.substring(0, partText.length > 50 ? 50 : partText.length)}...');
                      controller.add(partText);
                      debugPrint('[PAI_SSE] ✓ Added to controller, length: ${partText.length}');
                    }
                  }
                } else if (partType == 'reasoning') {
                  reasoningPartIds.add(partId);
                  if (partMessageId != null) {
                    activeAssistantMessageId = partMessageId;
                    _bindMessageId(partMessageId, MessageOrigin.llm);
                    _reasoningBuffers.putIfAbsent(partMessageId, () => StringBuffer());
                  }
                }
              }
            }

            // Handle message.part.delta inside payload
            final text = _extractMessagePartDelta(e.payload, textPartIds, reasoningPartIds);
            if (text != null && text.isNotEmpty) {
              debugPrint('[PAI_SSE] ✓ Text delta extracted: ${text.substring(0, text.length > 50 ? 50 : text.length)}...');
              controller.add(text);
              debugPrint('[PAI_SSE] ✓ Added text delta to controller');
            } else {
              debugPrint('[PAI_SSE] ✗ No text delta extracted (textPartIds: ${textPartIds.length}, reasoningPartIds: ${reasoningPartIds.length})');
            }
            
            final reasoning = _extractReasoningDelta(e.payload, reasoningPartIds);
            if (reasoning != null && reasoning.isNotEmpty) {
              final msgId = _extractMessageIdFromDelta(e.payload) ??
                  _extractMessageIdFromPartDelta(e.payload);
              debugPrint('[PAI_SSE] Reasoning delta: ${reasoning.substring(0, reasoning.length > 50 ? 50 : reasoning.length)}...');
              appendReasoning(reasoning, messageId: msgId);
            }
            break;

          // Text streaming
          case TextDeltaEvent e:
            if (e.delta.isNotEmpty) {
              debugPrint('[PAI_SSE] ✓ TextDeltaEvent: ${e.delta.substring(0, e.delta.length > 50 ? 50 : e.delta.length)}...');
              controller.add(e.delta);
              debugPrint('[PAI_SSE] ✓ Added TextDeltaEvent to controller');
            } else {
              debugPrint('[PAI_SSE] ✗ TextDeltaEvent with empty delta');
            }
            break;

          case TextEndedEvent _:
            // Não fecha se há interações pendentes
            if (_pendingQuestions.isNotEmpty || _pendingPermissions.isNotEmpty) {
              debugPrint('[PAI_SSE] TextEnded but pending questions/permissions - keeping stream open');
            } else {
              debugPrint('[PAI_SSE] TextEnded, no pending interactions - closing response stream');
              closeResponse();
            }
            break;

          // Reasoning streaming
          case ReasoningDeltaEvent e:
            if (e.delta.isNotEmpty) {
              debugPrint('[PAI_SSE] ReasoningDeltaEvent: ${e.delta.substring(0, e.delta.length > 50 ? 50 : e.delta.length)}...');
              appendReasoning(e.delta, messageId: e.reasoningId);
            }
            break;

          case ReasoningEndedEvent _:
            // Reasoning completo - já foi acumulado nos deltas
            break;

          // Tool calls
          case ToolCallInputStartedEvent e:
            _toolCallBuffers[e.callId] = ToolCallPart(
              id: e.callId,
              name: e.toolName,
              state: ToolCallState.pending,
            );
            notifyListeners();
            break;

          case ToolCallCalledEvent e:
            final tool = _toolCallBuffers[e.callId];
            if (tool != null) {
              tool.state = ToolCallState.running;
              tool.input.addAll(e.input);
            } else {
              _toolCallBuffers[e.callId] = ToolCallPart(
                id: e.callId,
                name: e.toolName,
                state: ToolCallState.running,
                input: e.input,
              );
            }
            notifyListeners();
            break;

          case ToolCallSuccessEvent e:
            final tool = _toolCallBuffers[e.callId];
            if (tool != null) {
              tool.state = ToolCallState.completed;
              tool.content = parseToolContent(e.content);
            } else {
              _toolCallBuffers[e.callId] = ToolCallPart(
                id: e.callId,
                name: 'unknown',
                state: ToolCallState.completed,
                content: parseToolContent(e.content),
              );
            }
            notifyListeners();
            break;

          case ToolCallFailedEvent e:
            final tool = _toolCallBuffers[e.callId];
            if (tool != null) {
              tool.state = ToolCallState.error;
              tool.errorMessage = e.errorMessage;
            } else {
              _toolCallBuffers[e.callId] = ToolCallPart(
                id: e.callId,
                name: 'unknown',
                state: ToolCallState.error,
                errorMessage: e.errorMessage,
              );
            }
            notifyListeners();
            break;

          // Shell commands
          case ShellStartedEvent e:
            // Shell iniciado - armazena comando
            _shellBuffers[e.callId] = ShellPart(
              callId: e.callId,
              command: e.command,
              output: '',
            );
            notifyListeners();
            break;

          case ShellEndedEvent e:
            // Shell finalizado - atualiza com output
            final shell = _shellBuffers[e.callId];
            if (shell != null) {
              _shellBuffers[e.callId] = ShellPart(
                callId: e.callId,
                command: shell.command,
                output: e.output,
              );
            } else {
              _shellBuffers[e.callId] = ShellPart(
                callId: e.callId,
                command: '',
                output: e.output,
              );
            }
            notifyListeners();
            break;

          // Permissions
          case PermissionAskedEvent e:
            _pendingPermissions[e.request.id] = e.request;
            notifyListeners();
            break;

          case PermissionRepliedEvent e:
            _pendingPermissions.remove(e.requestId);
            notifyListeners();
            break;

          // Questions
          case QuestionAskedEvent e:
            _pendingQuestions[e.request.id] = e.request;
            notifyListeners();
            break;

          case QuestionRepliedEvent e:
            _pendingQuestions.remove(e.requestId);
            notifyListeners();
            break;

          case QuestionRejectedEvent e:
            _pendingQuestions.remove(e.requestId);
            notifyListeners();
            break;

          // Status events
          case StatusEvent e:
            final isIdle = _isIdleStatus(e.payload);
            if (isIdle && !responseEnded) {
              // Não fecha se há interações pendentes (perguntas/permissions)
              // O agente pode continuar após o usuário responder
              if (_pendingQuestions.isNotEmpty || _pendingPermissions.isNotEmpty) {
                debugPrint('[PAI_SSE] Status idle but pending questions/permissions exist - keeping stream open');
              } else {
                debugPrint('[PAI_SSE] Status idle, no pending interactions - closing response stream');
                closeResponse();
              }
            }
            break;

          // Connection events
          case ConnectedEvent _:
            // Already handled by markOnline
            break;

          case DisconnectedEvent _:
            if (!responseEnded) {
              _connectivity.markOffline();
              _connectivity.startReconnect(() {
                _rehydrateCurrentSession();
              });
            }
            break;

          case ErrorEvent e:
            debugPrint('[PAI_SSE] Error: ${e.message}');
            break;

          default:
            debugPrint('[PAI_SSE] Unhandled event: ${event.runtimeType}');
        }
      },
      onError: (error) {
        _connectivity.markError();
        if (!controller.isClosed) {
          controller.addError(error);
          controller.close();
        }
        // Tenta reconectar automaticamente
        _connectivity.startReconnect(() {
          _rehydrateCurrentSession();
        });
      },
      onDone: () {
        if (!responseEnded) {
          _connectivity.markOffline();
          _connectivity.startReconnect(() {
            _rehydrateCurrentSession();
          });
        }
        if (!controller.isClosed && !responseEnded) {
          controller.close();
        }
      },
    );
    
    return controller.stream;
  }

  bool _belongsToCurrentSession(ChatEvent event) {
    if (_currentSessionId == null) return true;
    if (event.sessionId != null) {
      final belongs = event.sessionId == _currentSessionId;
      if (!belongs) {
        debugPrint('[PAI_SSE] Session filter: event sessionId=${event.sessionId} != current=$_currentSessionId');
      }
      return belongs;
    }
    // For MessageEvent and StatusEvent, try extracting from payload
    if (event is MessageEvent) {
      final sessionId = _extractSessionId(event.payload);
      if (sessionId != null) {
        final belongs = sessionId == _currentSessionId;
        if (!belongs) {
          debugPrint('[PAI_SSE] Session filter: extracted sessionId=$sessionId != current=$_currentSessionId');
        }
        return belongs;
      }
    } else if (event is StatusEvent) {
      final sessionId = _extractSessionId(event.payload);
      if (sessionId != null) {
        final belongs = sessionId == _currentSessionId;
        if (!belongs) {
          debugPrint('[PAI_SSE] Session filter: extracted sessionId=$sessionId != current=$_currentSessionId');
        }
        return belongs;
      }
    }
    return true;
  }

  String? _extractSessionId(dynamic data) {
    final map = _asMap(data);
    if (map == null) return null;
    final props = map['properties'];
    if (props is Map) {
      final direct = props['sessionID'];
      if (direct is String) return direct;
      final info = props['info'];
      if (info is Map && info['sessionID'] is String) return info['sessionID'] as String;
      final part = props['part'];
      if (part is Map && part['sessionID'] is String) return part['sessionID'] as String;
      final message = props['message'];
      if (message is Map && message['sessionID'] is String) return message['sessionID'] as String;
      final session = props['session'];
      if (session is Map && session['id'] is String) return session['id'] as String;
    }
    if (map['sessionID'] is String) return map['sessionID'] as String;
    if (map['sessionId'] is String) return map['sessionId'] as String;
    return null;
  }

  Map<String, dynamic>? _asMap(dynamic data) {
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      return _parseTimestamp(value['created'] ?? value['updated']);
    }
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    if (value is String) {
      final asInt = int.tryParse(value);
      if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
      return DateTime.tryParse(value);
    }
    return null;
  }

  Map<String, dynamic>? _extractMessageUpdateInfo(dynamic data) {
    final map = _asMap(data);
    if (map == null) return null;
    final props = map['properties'];
    if (props is Map) {
      final info = props['info'];
      if (info is Map) return Map<String, dynamic>.from(info);
      final message = props['message'];
      if (message is Map) return Map<String, dynamic>.from(message);
    }
    final info = map['info'];
    if (info is Map) return Map<String, dynamic>.from(info);
    return null;
  }

  void _bindMessageId(
    String messageId,
    MessageOrigin origin, {
    DateTime? timestamp,
  }) {
    final existingIndex = _historyMessageIds.indexOf(messageId);
    if (existingIndex >= 0) {
      if (timestamp != null) _messageTimestamps[messageId] = timestamp;
      return;
    }

    for (var i = _history.length - 1; i >= 0; i--) {
      if (_history[i].origin != origin) continue;
      final existingId = _historyMessageIds[i];
      if (existingId != null && !existingId.startsWith('local-')) continue;

      _historyMessageIds[i] = messageId;
      if (existingId != null && existingId != messageId) {
        final oldReasoning = _reasoningBuffers.remove(existingId);
        if (oldReasoning != null && oldReasoning.isNotEmpty) {
          _reasoningBuffers.putIfAbsent(messageId, () => StringBuffer());
          _reasoningBuffers[messageId]!.write(oldReasoning.toString());
        }
      }
      if (timestamp != null) _messageTimestamps[messageId] = timestamp;
      notifyListeners();
      return;
    }

    if (timestamp != null) _messageTimestamps[messageId] = timestamp;
  }

  String? _latestAssistantMessageId() {
    for (var i = _history.length - 1; i >= 0; i--) {
      if (_history[i].origin == MessageOrigin.llm) return _historyMessageIds[i];
    }
    return null;
  }

  String _ensureAssistantMessageId() {
    final latest = _latestAssistantMessageId();
    if (latest != null) return latest;

    for (var i = _history.length - 1; i >= 0; i--) {
      if (_history[i].origin == MessageOrigin.llm) {
        final localId = 'local-assistant-${++_localMessageCounter}';
        _historyMessageIds[i] = localId;
        return localId;
      }
    }

    final localId = 'local-assistant-${++_localMessageCounter}';
    _history.add(ChatMessage.llm());
    _historyMessageIds.add(localId);
    return localId;
  }
  
  /// Extrai reasoning de eventos message.part.delta
  String? _extractReasoningDelta(dynamic data, Set<String> reasoningPartIds) {
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    if (data is! Map) return null;
    
    final props = data['properties'] as Map?;
    if (props != null) {
      final partId = props['partID'] as String?;
      final field = props['field'] as String?;
      final delta = props['delta'];
      
      // Só extrai se for um part de reasoning conhecido e field for "text"
      if (partId != null && reasoningPartIds.contains(partId) && field == 'text') {
        if (delta is String) {
          return delta;
        } else if (delta is Map) {
          final textDelta = delta['text'] as String?;
          if (textDelta != null && textDelta.isNotEmpty) {
            return textDelta;
          }
        }
      }
    }
    
    return null;
  }
  
  /// Extrai messageID do evento message.part.delta
  String? _extractMessageIdFromDelta(dynamic data) {
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    if (data is! Map) return null;
    
    final props = data['properties'] as Map?;
    if (props != null) {
      return props['messageID'] as String?;
    }
    return null;
  }

  String? _extractMessageIdFromPartDelta(dynamic data) {
    final map = _asMap(data);
    if (map == null) return null;
    final props = map['properties'];
    if (props is Map) {
      final partId = props['partID'] as String?;
      if (partId != null) return _partMessageIds[partId];
    }
    return null;
  }
  
  /// Extrai informações da part de eventos message.part.updated
  Map<String, dynamic>? _extractPartInfo(dynamic data) {
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    if (data is! Map) return null;
    
    final props = data['properties'] as Map?;
    if (props != null) {
      final part = props['part'] as Map?;
      if (part != null) {
        return {
          'id': part['id'],
          'type': part['type'],
          'text': part['text'],
          'messageID': part['messageID'] ?? part['messageId'],
        };
      }
    }
    
    return null;
  }
  
  /// Extrai texto de eventos message.part.delta
  /// Formato: { properties: { partID: "...", field: "text", delta: "texto" } }
  /// Processa qualquer delta com field="text" como texto visível,
  /// ignorando deltas da mensagem do usuário (eco) e de reasoning.
  String? _extractMessagePartDelta(dynamic data, Set<String> textPartIds, Set<String> reasoningPartIds) {
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    if (data is! Map) return null;
    
    final props = data['properties'] as Map?;
    if (props != null) {
      final partId = props['partID'] as String?;
      final field = props['field'] as String?;
      final delta = props['delta'];
      final msgId = props['messageID'] as String?;
      
      // Ignora eco da mensagem do usuário
      if (msgId != null && msgId == _lastUserMessageId) {
        debugPrint('[PAI_SSE] Ignoring user message echo delta for msgId: $msgId');
        return null;
      }
      
      // Ignora reasoning parts (vão pelo caminho separado)
      if (partId != null && reasoningPartIds.contains(partId)) {
        return null;
      }
      
      // Qualquer campo field="text" é tratado como texto visível da resposta
      if (field == 'text') {
        String? textDelta;
        if (delta is String) {
          textDelta = delta;
        } else if (delta is Map) {
          textDelta = delta['text'] as String?;
        }
        if (textDelta != null && textDelta.isNotEmpty) {
          if (partId != null && !textPartIds.contains(partId)) {
            textPartIds.add(partId);
            debugPrint('[PAI_SSE] Auto-registered text partId: $partId');
          }
          return textDelta;
        }
      }
    }
    
    return null;
  }
  
  /// Verifica se status indica fim da resposta
  bool _isIdleStatus(dynamic data) {
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return false;
      }
    }
    if (data is! Map) return false;
    
    final props = data['properties'] as Map?;
    if (props != null) {
      final status = props['status'];
      if (status is String) return status == 'idle';
      if (status is Map) return status['type'] == 'idle';
    }
    
    final status = data['status'];
    if (status is String) return status == 'idle';
    if (status is Map) return status['type'] == 'idle';
    
    return false;
  }

  @override
  Iterable<ChatMessage> get history => _history;

  @override
  set history(Iterable<ChatMessage> history) {
    _history.clear();
    _history.addAll(history);
    _historyMessageIds.clear();
    _historyMessageIds.addAll(List<String?>.filled(_history.length, null));
    notifyListeners();
  }
  
  /// Recarrega histórico após question/permission para obter resposta completa.
  void _reopenSSEForContinuation() {
    debugPrint('[PAI_SSE] Reloading history after question/permission');
    
    // Recarrega o histórico da sessão para pegar a nova mensagem do agente
    loadHistory().then((_) {
      debugPrint('[PAI_SSE] History reloaded after question/permission');
    }).catchError((e) {
      debugPrint('[PAI_SSE] Failed to reload history: $e');
    });
  }

  /// Reidrata o histórico depois de queda/reconexão do SSE.
  Future<void> _rehydrateCurrentSession() async {
    debugPrint('[PAI_CONNECTIVITY] Rehydrating current session...');

    _sseSubscription?.cancel();
    _sseSubscription = null;
    client.unsubscribe();

    if (_currentSessionId == null) {
      _connectivity.markOnline();
      return;
    }

    try {
      await loadHistory();
      _connectivity.markOnline();
    } catch (e) {
      debugPrint('[PAI_CONNECTIVITY] Rehydrate failed: $e');
      _connectivity.markError();
      _connectivity.startReconnect(() {
        _rehydrateCurrentSession();
      });
    }
  }

  @override
  void dispose() {
    _connectivity.removeListener(_onConnectionStateChanged);
    _connectivity.dispose();
    _sseSubscription?.cancel();
    client.unsubscribe();
    super.dispose();
  }
}
