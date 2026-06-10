import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';

import '../models/chat_event.dart';
import '../models/file_change.dart';
import '../models/message_part.dart';

import '../services/api_errors.dart';
import '../services/notification_service.dart';
import '../services/connectivity_service.dart';
import '../services/opencode_client.dart';
import '../services/secure_storage.dart';

/// Dados de uma pergunta já respondida pelo usuário.
class AnsweredQuestionData {
  final QuestionRequest request;
  final List<List<String>> answers;
  final String? associatedMessageId;
  final int textInsertOffset;

  const AnsweredQuestionData({
    required this.request,
    required this.answers,
    this.associatedMessageId,
    this.textInsertOffset = 0,
  });
}

/// Provider que integra o OpenCode Server com o Flutter AI Toolkit.
/// 
/// Implementa a interface LlmProvider, convertendo entre:
/// - ChatMessage (AI Toolkit) ↔ OpenCode API/SSE
/// 
/// Suporta:
/// - Streaming de respostas via SSE
/// - Histórico de mensagens
/// - Tool calls (futuro)
class _LifecycleObserver with WidgetsBindingObserver {
  bool isInForeground = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    isInForeground = state == AppLifecycleState.resumed;
  }
}

class OpenCodeProvider extends LlmProvider with ChangeNotifier {
  OpenCodeClient? _client;
  OpenCodeClient? get clientOrNull => _client;
  OpenCodeClient get client => _client!;
  final _lifecycleObserver = _LifecycleObserver();
  bool get _isInForeground => _lifecycleObserver.isInForeground;
  String? _currentSessionId;
  String? _directory;
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

  /// Perguntas já respondidas, para exibição inline na mensagem do assistente.
  final Map<String, AnsweredQuestionData> _answeredQuestions = {};

  /// Mapa de callID -> ShellPart para shell commands.
  final Map<String, ShellPart> _shellBuffers = {};

  /// Mapa de callID -> messageID para associar tool/shell calls à mensagem correta.
  final Map<String, String> _callMessageIds = {};

  /// File changes indexed by messageID (from session.diff / file.edited events).
  final Map<String, List<FileChange>> _fileChanges = {};

  int _localMessageCounter = 0;

  /// Flag que impede o fechamento prematuro do stream SSE após
  /// responder a uma question/permission. Resetada quando novos deltas
  /// de texto chegam, indicando que a continuação começou.
  bool _awaitingContinuation = false;
  Timer? _continuationTimer;

  /// Throttled notifyListeners for streaming — ~20fps to avoid rebuild storms.
  Timer? _notifyThrottle;
  bool _notifyPending = false;

  void _throttledNotify() {
    _notifyPending = true;
    if (_notifyThrottle != null) return;
    _notifyThrottle = Timer(const Duration(milliseconds: 50), () {
      _notifyThrottle = null;
      if (_notifyPending) {
        _notifyPending = false;
        notifyListeners();
      }
    });
  }

  /// Contagem de caracteres já emitidos no stream da resposta atual.
  /// Usado para posicionar Q&A inline no texto.
  int _streamedTextLength = 0;
  
  /// ID da última mensagem do usuário enviada (para filtrar deltas de volta)
  String? _lastUserMessageId;
  
  /// Whether the agent is currently streaming a response.
  bool _isStreaming = false;

  /// Latest error message from SSE, cleared on next successful event.
  String? _lastError;

  /// Session details cached from server (model, cost, tokens, etc.)
  Map<String, dynamic>? _sessionInfo;

  /// Todos for the current session.
  List<Map<String, dynamic>> _todos = [];

  /// Model override for next message (providerID, modelID).
  Map<String, String>? _modelOverride;
  
  /// Serviço de conectividade
  final ConnectivityService _connectivity = ConnectivityService();
  
  OpenCodeProvider({
    OpenCodeClient? client,
    String? sessionId,
    Iterable<ChatMessage>? history,
  }) : _client = client, _currentSessionId = sessionId {
    if (history != null) {
      _history.addAll(history);
      _historyMessageIds.addAll(List<String?>.filled(_history.length, null));
    }
    _connectivity.addListener(_onConnectionStateChanged);
    _connectivity.startMonitoring();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  /// Updates the HTTP client (called when credentials/timeout change).
  void updateClient(OpenCodeClient newClient) {
    _sseSubscription?.cancel();
    if (_client != newClient) {
      _client?.close();
    }
    _client = newClient;
    notifyListeners();
  }

  /// Switches to a different session, reloading history.
  Future<void> switchSession(String? sessionId) async {
    if (sessionId == _currentSessionId) return;
    _sseSubscription?.cancel();
    _client?.unsubscribe();
    _currentSessionId = sessionId;
    _clearBuffers();
    if (sessionId != null) {
      await loadHistory();
    }
    notifyListeners();
  }

  void _clearBuffers() {
    _history.clear();
    _historyMessageIds.clear();
    _reasoningBuffers.clear();
    _toolCallBuffers.clear();
    _shellBuffers.clear();
    _callMessageIds.clear();
    _fileChanges.clear();
    _pendingPermissions.clear();
    _pendingQuestions.clear();
    _answeredQuestions.clear();
    _messageTimestamps.clear();
    _partMessageIds.clear();
    _streamedTextLength = 0;
    _isStreaming = false;
    _lastError = null;
    _sessionInfo = null;
    _modelOverride = null;
    _todos = [];
  }
  
  /// ID da sessão atual do OpenCode
  String? get currentSessionId => _currentSessionId;
  String? get directory => _directory;
  set directory(String? d) {
    _directory = d;
    notifyListeners();
  }
  
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

  /// Returns tool calls associated with a specific message.
  List<ToolCallPart> getToolCallsForMessage(String messageId) {
    final ids = _callMessageIds.entries
        .where((e) => e.value == messageId)
        .map((e) => e.key)
        .toSet();
    if (ids.isEmpty) return const [];
    return _toolCallBuffers.entries
        .where((e) => ids.contains(e.key))
        .map((e) => e.value)
        .toList();
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

  /// Perguntas já respondidas para exibição inline
  List<AnsweredQuestionData> getAnsweredQuestionsForMessage(String messageId) {
    return _answeredQuestions.values
        .where((aq) => aq.associatedMessageId == messageId)
        .toList();
  }

  /// Todos os shell commands
  Map<String, ShellPart> get shellCommands => Map.unmodifiable(_shellBuffers);

  /// Returns shell commands associated with a specific message.
  List<ShellPart> getShellCommandsForMessage(String messageId) {
    final ids = _callMessageIds.entries
        .where((e) => e.value == messageId)
        .map((e) => e.key)
        .toSet();
    if (ids.isEmpty) return const [];
    return _shellBuffers.entries
        .where((e) => ids.contains(e.key))
        .map((e) => e.value)
        .toList();
  }

  /// Returns file changes associated with a specific message.
  List<FileChange> getFileChangesForMessage(String messageId) {
    return _fileChanges[messageId] ?? const [];
  }

  /// Whether the agent is currently streaming.
  bool get isStreaming => _isStreaming;

  /// Latest error message from SSE (null if no error).
  String? get lastError => _lastError;

  /// Clears the last error.
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  /// Cached session info from server.
  Map<String, dynamic>? get sessionInfo => _sessionInfo;

  /// Current session's todos.
  List<Map<String, dynamic>> get todos => List.unmodifiable(_todos);

  /// Model override for next message.
  Map<String, String>? get modelOverride => _modelOverride;
  set modelOverride(Map<String, String>? value) {
    _modelOverride = value;
    notifyListeners();
  }

  /// Abort the currently running generation.
  Future<void> abortSession() async {
    if (_currentSessionId == null) return;
    try {
      await client.abortSession(_currentSessionId!);
      _isStreaming = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[PAI_SSE] Abort failed: $e');
    }
  }

  /// Load session details (model, cost, tokens).
  Future<void> loadSessionInfo() async {
    if (_currentSessionId == null) return;
    try {
      _sessionInfo = await client.getSession(_currentSessionId!);
      if (_sessionInfo?['directory'] is String) {
        _directory = _sessionInfo!['directory'] as String;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[PAI_SSE] Failed to load session info: $e');
    }
  }

  /// Load todos for the current session.
  Future<void> loadTodos() async {
    if (_currentSessionId == null) return;
    try {
      final raw = await client.getSessionTodos(_currentSessionId!);
      _todos = raw.whereType<Map<String, dynamic>>().toList();
      notifyListeners();
    } catch (e) {
      debugPrint('[PAI_SSE] Failed to load todos: $e');
    }
  }

  /// Fork session at a message.
  Future<String?> forkSession(String messageId) async {
    if (_currentSessionId == null) return null;
    try {
      final result = await client.forkSession(_currentSessionId!, messageId);
      return result['id'] as String?;
    } catch (e) {
      debugPrint('[PAI_SSE] Fork failed: $e');
      return null;
    }
  }

  /// Share session (create share link).
  Future<String?> shareSession() async {
    if (_currentSessionId == null) return null;
    try {
      final result = await client.shareSession(_currentSessionId!);
      _sessionInfo = result;
      notifyListeners();
      return result['share'] as String?;
    } catch (e) {
      debugPrint('[PAI_SSE] Share failed: $e');
      return null;
    }
  }

  /// Unshare session (remove share link).
  Future<void> unshareSession() async {
    if (_currentSessionId == null) return;
    try {
      await client.unshareSession(_currentSessionId!);
      _sessionInfo?.remove('share');
      notifyListeners();
    } catch (e) {
      debugPrint('[PAI_SSE] Unshare failed: $e');
    }
  }

  /// Revert a message (undo file changes).
  Future<bool> revertMessage(String messageId) async {
    if (_currentSessionId == null) return false;
    try {
      await client.revertMessage(_currentSessionId!, messageId);
      return true;
    } catch (e) {
      debugPrint('[PAI_SSE] Revert failed: $e');
      return false;
    }
  }

  /// Unrevert messages.
  Future<bool> unrevertSession() async {
    if (_currentSessionId == null) return false;
    try {
      await client.unrevertSession(_currentSessionId!);
      return true;
    } catch (e) {
      debugPrint('[PAI_SSE] Unrevert failed: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> summarizeSession() async {
    if (_currentSessionId == null) return null;
    final info = _sessionInfo;
    final rawModel = info?['model'];
    final modelId = rawModel is Map ? rawModel['id']?.toString() : null;
    final providerId = rawModel is Map ? rawModel['providerID']?.toString() : null;
    if (modelId == null || providerId == null) return null;
    try {
      return await client.summarizeSession(
        _currentSessionId!,
        modelId: modelId,
        providerId: providerId,
      );
    } catch (e) {
      debugPrint('[PAI] Summarize failed: $e');
      _lastError = e.toString();
      notifyListeners();
      return null;
    }
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

    // Update state immediately — don't block on HTTP.
    _pendingPermissions.remove(requestId);
    _isStreaming = true;
    _startContinuationWait();
    notifyListeners();

    // Fire POST in background — SSE delivers the continuation.
    unawaited((() async {
      try {
        await client.post(
          '/permission/$requestId/reply',
          body: jsonEncode({'reply': replyValue}),
        );
      } catch (e) {
        debugPrint('[PAI_SSE] replyToPermission: POST failed (non-blocking): $e');
      }
    })());
  }

  /// Responde a uma pergunta
  Future<void> replyToQuestion(String requestId, List<List<String>> answers) async {
    final request = _pendingQuestions[requestId];
    if (request == null) {
      debugPrint('[PAI_SSE] replyToQuestion: request not found for id=$requestId');
      return;
    }

    // Persist answer and update state immediately — don't wait for HTTP response.
    _answeredQuestions[requestId] = AnsweredQuestionData(
      request: request,
      answers: answers,
      associatedMessageId: _latestAssistantMessageId(),
      textInsertOffset: _streamedTextLength,
    );

    _pendingQuestions.remove(requestId);
    _isStreaming = true;
    _startContinuationWait();
    _persistAnsweredQuestions();
    notifyListeners();

    // Fire POST in background — SSE will deliver the agent's continuation.
    debugPrint('[PAI_SSE] replyToQuestion: posting reply for requestId=$requestId');
    client.post(
      '/question/$requestId/reply',
      body: jsonEncode({'answers': answers}),
    ).then((response) {
      debugPrint('[PAI_SSE] replyToQuestion: POST success, status=${response.statusCode}');
    }).catchError((e) {
      debugPrint('[PAI_SSE] replyToQuestion: POST failed (non-blocking): $e');
    });
  }

  /// Rejeita uma pergunta
  Future<void> rejectQuestion(String requestId) async {
    final request = _pendingQuestions[requestId];
    if (request == null) return;

    await client.post(
      '/question/$requestId/reject',
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
      _answeredQuestions.clear();
      _toolCallBuffers.clear();
      _shellBuffers.clear();
      _callMessageIds.clear();
      _fileChanges.clear();

      // Tool calls and reasoning from tool-only assistant messages are
      // associated with the NEXT text-bearing assistant message.
      var pendingToolCalls = <ToolCallPart>[];
      var pendingReasoning = StringBuffer();
      var pendingAnsweredQuestions = <(String, AnsweredQuestionData)>[];
      
      for (final msg in messages) {
        if (msg is! Map) continue;
        final info = msg['info'] as Map<String, dynamic>?;
        final role = info?['role'] as String?;
        final messageId = info?['id'] as String?;
        final parts = msg['parts'] as List<dynamic>?;
        
        if (role == null || parts == null) continue;
        
        final timestamp = _parseTimestamp(info?['time'] ?? info?['created']);
        
        final textBuffer = StringBuffer();
        final reasoningBuffer = StringBuffer();
        final msgToolCalls = <ToolCallPart>[];
        
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
          } else if (partType == 'tool') {
            final toolName = part['tool'] as String? ?? 'unknown';
            final callId = part['callID'] as String? ?? partId ?? '';
            final stateMap = part['state'] as Map?;
            final status = stateMap?['status'] as String?;
            final toolState = switch (status) {
              'completed' => ToolCallState.completed,
              'running' => ToolCallState.running,
              'error' || 'failed' => ToolCallState.error,
              _ => ToolCallState.pending,
            };
            final input = stateMap?['input'] is Map
                ? Map<String, dynamic>.from(stateMap!['input'] as Map)
                : <String, dynamic>{};
            msgToolCalls.add(ToolCallPart(
              id: callId,
              name: toolName,
              state: toolState,
              input: input,
              textInsertOffset: 0,
            ));

            // Reconstruct answered questions from completed question tools
            if (toolName == 'question' && status == 'completed' && stateMap != null) {
              final qInput = stateMap['input'] as Map?;
              final qOutput = stateMap['output'] as String?;
              if (qInput != null && qOutput != null) {
                final questionsRaw = qInput['questions'] as List? ?? [];
                final questions = questionsRaw.map((q) {
                  if (q is! Map) return const QuestionInfo(question: '', header: '', options: [], multiple: false, custom: false);
                  final opts = (q['options'] as List? ?? []).map((o) {
                    if (o is! Map) return const QuestionOption(label: '', description: '');
                    return QuestionOption(
                      label: o['label']?.toString() ?? '',
                      description: o['description']?.toString() ?? '',
                    );
                  }).toList();
                  return QuestionInfo(
                    question: q['question']?.toString() ?? '',
                    header: q['header']?.toString() ?? '',
                    options: opts,
                    multiple: q['multiple'] == true,
                    custom: q['custom'] == true,
                  );
                }).toList();

                // Parse answers from output string
                final answers = <List<String>>[];
                final answerMatch = RegExp(r'"([^"]+)"="([^"]+)"').allMatches(qOutput);
                for (final match in answerMatch) {
                  answers.add([match.group(2) ?? '']);
                }
                if (answers.isEmpty && qOutput.isNotEmpty) {
                  answers.add([qOutput]);
                }

                _answeredQuestions[callId] = AnsweredQuestionData(
                  request: QuestionRequest(
                    id: callId,
                    sessionID: _currentSessionId ?? '',
                    questions: questions,
                  ),
                  answers: answers,
                  associatedMessageId: null,
                  textInsertOffset: 0,
                );
                pendingAnsweredQuestions.add((callId, _answeredQuestions[callId]!));
              }
            }
          }
        }
        
        final messageText = textBuffer.toString();

        if (role == 'user') {
          _flushPendingToolCalls(pendingToolCalls);
          pendingToolCalls = [];
          pendingReasoning = StringBuffer();
          _history.add(ChatMessage.user(messageText, const []));
          _historyMessageIds.add(messageId);
        } else if (role == 'assistant') {
          if (messageText.isEmpty && msgToolCalls.isEmpty) {
            // Truly empty message — skip
            if (reasoningBuffer.isNotEmpty) {
              pendingReasoning.write(reasoningBuffer);
            }
            continue;
          }

          if (messageText.isEmpty) {
            // Tool-only message: render as its own entry (matches TUI)
            _history.add(ChatMessage.llm());
            _historyMessageIds.add(messageId);

            for (final tc in pendingToolCalls) {
              _toolCallBuffers[tc.id] = tc;
              if (messageId != null) _callMessageIds[tc.id] = messageId;
            }
            for (final tc in msgToolCalls) {
              _toolCallBuffers[tc.id] = tc;
              if (messageId != null) _callMessageIds[tc.id] = messageId;
            }
            for (final (callId, aq) in pendingAnsweredQuestions) {
              _answeredQuestions[callId] = AnsweredQuestionData(
                request: aq.request,
                answers: aq.answers,
                associatedMessageId: messageId,
                textInsertOffset: aq.textInsertOffset,
              );
            }
            pendingAnsweredQuestions = [];
            pendingToolCalls = [];

            if (pendingReasoning.isNotEmpty || reasoningBuffer.isNotEmpty) {
              if (messageId != null) {
                final merged = StringBuffer();
                if (pendingReasoning.isNotEmpty) merged.write(pendingReasoning);
                if (reasoningBuffer.isNotEmpty) merged.write(reasoningBuffer);
                _reasoningBuffers[messageId] = merged;
              }
            }
            pendingReasoning = StringBuffer();
          } else {
            // Text message
            _history.add(ChatMessage.llm()..append(messageText));
            _historyMessageIds.add(messageId);

            // Merge pending reasoning with this message's reasoning
            if (pendingReasoning.isNotEmpty || reasoningBuffer.isNotEmpty) {
              if (messageId != null) {
                final merged = StringBuffer();
                if (pendingReasoning.isNotEmpty) merged.write(pendingReasoning);
                if (reasoningBuffer.isNotEmpty) merged.write(reasoningBuffer);
                _reasoningBuffers[messageId] = merged;
              }
            }

            for (final tc in pendingToolCalls) {
              _toolCallBuffers[tc.id] = tc;
              if (messageId != null) _callMessageIds[tc.id] = messageId;
            }
            for (final tc in msgToolCalls) {
              _toolCallBuffers[tc.id] = tc;
              if (messageId != null) _callMessageIds[tc.id] = messageId;
            }
            // Assign pending answered questions to this text message
            for (final (callId, aq) in pendingAnsweredQuestions) {
              _answeredQuestions[callId] = AnsweredQuestionData(
                request: aq.request,
                answers: aq.answers,
                associatedMessageId: messageId,
                textInsertOffset: aq.textInsertOffset,
              );
            }
            pendingAnsweredQuestions = [];
            pendingToolCalls = [];
            pendingReasoning = StringBuffer();
          }
        } else {
          continue;
        }

        if (timestamp != null && messageId != null) {
          _messageTimestamps[messageId] = timestamp;
        }
      }

      _flushPendingToolCalls(pendingToolCalls);

      // Flush any remaining pending answered questions to the last assistant msg
      if (pendingAnsweredQuestions.isNotEmpty) {
        final lastAssistantId = _latestAssistantMessageId();
        for (final (callId, aq) in pendingAnsweredQuestions) {
          _answeredQuestions[callId] = AnsweredQuestionData(
            request: aq.request,
            answers: aq.answers,
            associatedMessageId: lastAssistantId,
            textInsertOffset: aq.textInsertOffset,
          );
        }
      }

      await _loadPersistedAnsweredQuestions();
      notifyListeners();

      // Load session metadata and todos in background
      loadSessionInfo();
      loadTodos();
      _connectivity.markOnline();
    } catch (e) {
      debugPrint('Error loading history: $e');
      _lastError = 'Failed to load history: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Flushes any pending tool calls into the buffers even when there's
  /// no subsequent text message to associate them with. Associates them
  /// with the last assistant message if one exists.
  void _flushPendingToolCalls(List<ToolCallPart> pending) {
    if (pending.isEmpty) return;
    String? lastAssistantMsgId;
    for (int i = _historyMessageIds.length - 1; i >= 0; i--) {
      if (_historyMessageIds[i] != null &&
          i < _history.length &&
          _history.elementAt(i).origin != MessageOrigin.user) {
        lastAssistantMsgId = _historyMessageIds[i];
        break;
      }
    }
    for (final tc in pending) {
      _toolCallBuffers[tc.id] = tc;
      if (lastAssistantMsgId != null) {
        _callMessageIds[tc.id] = lastAssistantMsgId;
      }
    }
  }
  
  /// Cria uma nova sessão no OpenCode, usando _directory corrente.
  Future<void> createSession({String? title}) async {
    final Map<String, dynamic> session;
    try {
      session = await client.createSession(
        title: title,
        directory: _directory,
      );
    } catch (e) {
      debugPrint(
        '[PAI_SESSION] createSession failed '
        'directory=${_directory ?? '(default)'} error=$e',
      );
      rethrow;
    }
    _currentSessionId = session['id'] as String?;
    if (session['directory'] is String) {
      _directory = session['directory'] as String;
    }
    _history.clear();
    _reasoningBuffers.clear();
    _messageTimestamps.clear();
    _historyMessageIds.clear();
    _partMessageIds.clear();
    _answeredQuestions.clear();
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
    _answeredQuestions.clear();
    if (history != null) {
      _history.addAll(history);
      _historyMessageIds.addAll(List<String?>.filled(_history.length, null));
    }
    notifyListeners();
  }

  /// Clears all session state without creating a new one (lazy creation).
  void clearSession() {
    _currentSessionId = null;
    _clearBuffers();
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
    
    final responseStream = _listenForResponse();
    
    // Build message parts
    final parts = <Map<String, dynamic>>[
      {'type': 'text', 'text': prompt},
    ];
    for (final att in attachments) {
      if (att is FileAttachment) {
        final b64 = base64Encode(att.bytes);
        final dataUri = 'data:${att.mimeType};base64,$b64';
        parts.add({
          'type': 'file',
          'url': dataUri,
          'mime': att.mimeType,
          'filename': att.name,
        });
      }
    }

    // Fire message in background — response arrives via SSE.
    final model = _modelOverride;
    _sendInBackground(parts, model);
    
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
      llmMessage.append(chunk);
      _throttledNotify();
      return chunk;
    });
  }
  
  static final _rng = math.Random();

  /// Sends the message in the background. Does NOT await completion —
  /// the server response (agent output) arrives via SSE.
  /// Retries on transient errors with exponential backoff.
  void _sendInBackground(
    List<Map<String, dynamic>> parts,
    Map<String, String>? model, {
    int maxRetries = 0,
  }) {
    _doSend(parts, model, maxRetries: maxRetries);
  }

  Future<void> _doSend(
    List<Map<String, dynamic>> parts,
    Map<String, String>? model, {
    int maxRetries = 0,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      final userMessageIdBeforeSend = _lastUserMessageId;
      try {
        if (model != null || parts.length > 1) {
          await client.sendMessageAdvanced(
            _currentSessionId!,
            parts: parts,
            model: model,
            directory: _directory,
          );
        } else {
          final textPart = parts.first['text'] as String;
          await client.sendMessage(_currentSessionId!, textPart, directory: _directory);
        }
        return;
      } catch (e) {
        debugPrint('[PAI_SSE] Send attempt ${attempt + 1} failed: $e');

        final serverAcceptedMessage = _lastUserMessageId != null &&
            _lastUserMessageId != userMessageIdBeforeSend;
        if (serverAcceptedMessage &&
            (e is ApiTimeoutError || e is ApiConnectionError)) {
          debugPrint(
            '[PAI_SSE] Send failed after server accepted message; not retrying',
          );
          return;
        }

        // Message POSTs are not idempotent. Retrying transport-level failures
        // can create duplicate user messages when the server accepted the first
        // request but the HTTP response timed out or disconnected.
        final retryableError = e is ApiError &&
                e is! ApiTimeoutError &&
                e is! ApiConnectionError &&
                e.isRetryable
            ? e
            : null;
        if (retryableError == null || attempt >= maxRetries) {
          _lastError = e.toString();
          _isStreaming = false;
          notifyListeners();
          return;
        }

        Duration delay;
        if (retryableError.retryAfter != null) {
          delay = retryableError.retryAfter!;
        } else {
          final base = math.min(0.5 * math.pow(2, attempt), 8.0);
          final jitter = 0.75 + _rng.nextDouble() * 0.25;
          delay = Duration(milliseconds: (base * jitter * 1000).round());
        }
        await Future.delayed(delay);
      }
    }
  }

  /// Escuta eventos SSE e extrai texto da resposta
  Stream<String> _listenForResponse() {
    // Fecha qualquer conexão SSE anterior
    _sseSubscription?.cancel();
    _sseSubscription = null;
    client.unsubscribe();
    _streamedTextLength = 0;
    
    _isStreaming = true;
    _lastError = null;
    notifyListeners();

    final controller = StreamController<String>(
      onCancel: () {
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

    // O servidor pode enviar o mesmo texto por até 3 caminhos SSE:
    //   1. session.next.text.delta → TextDeltaEvent  (streaming direto)
    //   2. message.part.delta     → MessageEvent      (delta low-level)
    //   3. message.part.updated   → MessageEvent      (snapshot completo)
    // Para evitar duplicação, o primeiro caminho delta (1 ou 2) que chegar
    // é eleito e os demais são ignorados. O caminho 3 (snapshot) nunca é
    // usado para texto pois sempre duplica o conteúdo dos deltas.
    //   null = ainda não decidido, true = TextDeltaEvent, false = message.part.delta
    bool? activeTextPath;

    void closeResponse() {
      if (responseEnded) return;
      responseEnded = true;
      _isStreaming = false;
      _sseSubscription?.cancel();
      _sseSubscription = null;
      if (!controller.isClosed) controller.close();
      loadSessionInfo();
      // Reload history to get accurate tool states from server
      unawaited(loadHistory().catchError((e) {
        debugPrint('[PAI_SSE] closeResponse loadHistory failed: $e');
      }));
    }

    void appendReasoning(String reasoning, {String? messageId}) {
      if (reasoning.isEmpty) return;
      final targetId = messageId ?? activeAssistantMessageId ?? _ensureAssistantMessageId();
      activeAssistantMessageId = targetId;
      _reasoningBuffers.putIfAbsent(targetId, () => StringBuffer());
      _reasoningBuffers[targetId]!.write(reasoning);
      _throttledNotify();
    }
    
    // Marca como conectando
    _connectivity.markOnline();
    
    // Inscreve no SSE
    final stream = client.subscribeToEvents(directory: _directory);
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
            final rawId = info?['id'];
            final messageId = rawId is String ? rawId : null;
            final rawRole = info?['role'];
            final role = rawRole is String ? rawRole : null;
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
              final rawPartId = partInfo['id'];
              final partId = rawPartId is String ? rawPartId : null;
              final rawPartType = partInfo['type'];
              final partType = rawPartType is String ? rawPartType : null;
              final rawPartMsgId = partInfo['messageID'];
              final partMessageId = rawPartMsgId is String ? rawPartMsgId : null;
              
              if (partId != null && partType != null) {
                if (partMessageId != null) {
                  _partMessageIds[partId] = partMessageId;
                }

                if (partType == 'text') {
                  textPartIds.add(partId);
                } else if (partType == 'reasoning') {
                  reasoningPartIds.add(partId);
                  if (partMessageId != null) {
                    activeAssistantMessageId = partMessageId;
                    _bindMessageId(partMessageId, MessageOrigin.llm);
                    _reasoningBuffers.putIfAbsent(partMessageId, () => StringBuffer());
                  }
                } else if (partType == 'tool') {
                  final toolName = partInfo['tool'] as String? ?? 'unknown';
                  final callId = partInfo['callID'] as String? ?? partId;
                  final stateMap = partInfo['state'] as Map<String, dynamic>?;
                  final status = stateMap?['status'] as String?;
                  final toolState = switch (status) {
                    'completed' => ToolCallState.completed,
                    'running' => ToolCallState.running,
                    'error' || 'failed' => ToolCallState.error,
                    _ => ToolCallState.pending,
                  };
                  final input = (stateMap?['input'] as Map<String, dynamic>?) ?? {};
                  final existing = _toolCallBuffers[callId];
                  if (existing != null) {
                    existing.state = toolState;
                    if (input.isNotEmpty) existing.input.addAll(input);
                  } else {
                    _toolCallBuffers[callId] = ToolCallPart(
                      id: callId,
                      name: toolName,
                      state: toolState,
                      input: Map<String, dynamic>.from(input),
                      textInsertOffset: _streamedTextLength,
                    );
                  }
                  _throttledNotify();
                }
              }
            }

            // Handle message.part.delta inside payload
            final text = _extractMessagePartDelta(e.payload, textPartIds, reasoningPartIds);
            if (text != null && text.isNotEmpty) {
              if (_awaitingContinuation) activeTextPath = null;
              activeTextPath ??= false;
              if (activeTextPath == false) {
                _endContinuationWait();
                controller.add(text);
                _streamedTextLength += text.length;
              }
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
              if (_awaitingContinuation) activeTextPath = null;
              activeTextPath ??= true;
              if (activeTextPath == true) {
                _endContinuationWait();
                controller.add(e.delta);
                _streamedTextLength += e.delta.length;
              }
            }
            break;

          case TextEndedEvent _:
            if (_pendingQuestions.isNotEmpty || _pendingPermissions.isNotEmpty || _awaitingContinuation) {
              debugPrint('[PAI_SSE] TextEnded but pending interactions or awaiting continuation - keeping stream open');
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
              textInsertOffset: _streamedTextLength,
            );
            if (activeAssistantMessageId != null) {
              _callMessageIds[e.callId] = activeAssistantMessageId!;
            }
            _throttledNotify();
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
                textInsertOffset: _streamedTextLength,
              );
            }
            _throttledNotify();
            break;

          case ToolCallInputDeltaEvent e:
            final tool = _toolCallBuffers[e.callId];
            if (tool != null) {
              final current = tool.input['_inputStream'] as String? ?? '';
              tool.input['_inputStream'] = current + e.delta;
            }
            break;

          case ToolCallInputEndedEvent e:
            final tool = _toolCallBuffers[e.callId];
            if (tool != null) {
              tool.input.remove('_inputStream');
              try {
                final parsed = json.decode(e.text) as Map<String, dynamic>;
                tool.input.addAll(parsed);
              } catch (_) {
                tool.input['_rawInput'] = e.text;
              }
              _throttledNotify();
            }
            break;

          case ToolCallProgressEvent e:
            final tool = _toolCallBuffers[e.callId];
            if (tool != null) {
              tool.input['_progress'] = e.structured;
              _throttledNotify();
            }
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
                textInsertOffset: _streamedTextLength,
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
                textInsertOffset: _streamedTextLength,
              );
            }
            notifyListeners();
            break;

          // Shell commands
          case ShellStartedEvent e:
            _shellBuffers[e.callId] = ShellPart(
              callId: e.callId,
              command: e.command,
              output: '',
              textInsertOffset: _streamedTextLength,
            );
            if (activeAssistantMessageId != null) {
              _callMessageIds[e.callId] = activeAssistantMessageId!;
            }
            _throttledNotify();
            break;

          case ShellEndedEvent e:
            final shell = _shellBuffers[e.callId];
            if (shell != null) {
              _shellBuffers[e.callId] = ShellPart(
                callId: e.callId,
                command: shell.command,
                output: e.output,
                textInsertOffset: shell.textInsertOffset,
              );
            } else {
              _shellBuffers[e.callId] = ShellPart(
                callId: e.callId,
                command: '',
                output: e.output,
                textInsertOffset: _streamedTextLength,
              );
            }
            notifyListeners();
            break;

          // Permissions
          case PermissionAskedEvent e:
            _pendingPermissions[e.request.id] = e.request;
            _isStreaming = false;
            notifyListeners();
            if (!_isInForeground && _currentSessionId != null) {
              NotificationService.showPermissionNeeded(
                sessionId: _currentSessionId!,
                permissionName: e.request.permission,
              );
            }
            break;

          case PermissionRepliedEvent e:
            _pendingPermissions.remove(e.requestId);
            notifyListeners();
            break;

          // Questions
          case QuestionAskedEvent e:
            _pendingQuestions[e.request.id] = e.request;
            _isStreaming = false;
            notifyListeners();
            if (!_isInForeground && _currentSessionId != null) {
              final firstQ = e.request.questions.isNotEmpty
                  ? e.request.questions.first.question
                  : null;
              NotificationService.showQuestionAsked(
                sessionId: _currentSessionId!,
                questionText: firstQ,
              );
            }
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
            if (e.originalEvent == 'session.error') {
              final props = e.payload['properties'] as Map<String, dynamic>?;
              final errMsg = props?['error']?.toString() ?? 'Session error';
              _lastError = errMsg;
              _isStreaming = false;
              notifyListeners();
            }
            if (e.originalEvent == 'todo.updated') {
              loadTodos();
            }
            if (e.originalEvent == 'session.next.model.switched' ||
                e.originalEvent == 'session.next.agent.switched') {
              loadSessionInfo();
            }
            if (e.originalEvent == 'session.diff' || e.originalEvent == 'file.edited') {
              final msgId = activeAssistantMessageId;
              if (msgId != null) {
                final props = e.payload['properties'] as Map<String, dynamic>? ?? e.payload;
                final changeType = e.originalEvent == 'session.diff'
                    ? FileChangeType.diff
                    : FileChangeType.edited;
                _fileChanges.putIfAbsent(msgId, () => []);
                _fileChanges[msgId]!.add(FileChange.fromJson(props, changeType));
                _throttledNotify();
              }
            }
            final isIdle = _isIdleStatus(e.payload);
            if (isIdle && !responseEnded) {
              if (_pendingQuestions.isNotEmpty || _pendingPermissions.isNotEmpty) {
                debugPrint('[PAI_SSE] Status idle but pending interactions - keeping stream open');
              } else {
                debugPrint('[PAI_SSE] Status idle - closing response stream');
                _endContinuationWait();
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
            _lastError = e.message ?? 'Unknown error';
            notifyListeners();
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
        final result = <String, dynamic>{
          'id': part['id'],
          'type': part['type'],
          'text': part['text'],
          'messageID': part['messageID'] ?? part['messageId'],
        };
        if (part['tool'] != null) result['tool'] = part['tool'];
        if (part['callID'] != null) result['callID'] = part['callID'];
        if (part['state'] is Map) {
          result['state'] = Map<String, dynamic>.from(part['state'] as Map);
        }
        return result;
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
  
  void _startContinuationWait() {
    _awaitingContinuation = true;
    _continuationTimer?.cancel();
    _continuationTimer = null;
  }

  void _endContinuationWait() {
    if (!_awaitingContinuation) return;
    debugPrint('[PAI_SSE] Continuation received - ending wait');
    _awaitingContinuation = false;
    _continuationTimer?.cancel();
    _continuationTimer = null;
  }

  Future<void> _persistAnsweredQuestions() async {
    if (_currentSessionId == null) return;
    final data = _answeredQuestions.map((k, v) => MapEntry(k, {
      'answers': v.answers,
      'msgId': v.associatedMessageId,
      'offset': v.textInsertOffset,
      'questions': v.request.questions.map((q) => {
        'question': q.question,
        'header': q.header,
        'options': q.options.map((o) => {'label': o.label, 'description': o.description}).toList(),
        'multiple': q.multiple,
        'custom': q.custom,
      }).toList(),
      'sessionID': v.request.sessionID,
    }));
    await SecureStorageService.write(
      'answered_$_currentSessionId',
      jsonEncode(data),
    );
  }

  Future<void> _loadPersistedAnsweredQuestions() async {
    if (_currentSessionId == null) return;
    final raw = await SecureStorageService.read('answered_$_currentSessionId');
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in map.entries) {
        final v = entry.value as Map<String, dynamic>;
        final questionsJson = v['questions'] as List<dynamic>? ?? [];
        final questions = questionsJson.map((q) {
          final qMap = q as Map<String, dynamic>;
          final optionsJson = qMap['options'] as List<dynamic>? ?? [];
          return QuestionInfo(
            question: qMap['question'] as String? ?? '',
            header: qMap['header'] as String? ?? '',
            options: optionsJson.map((o) {
              final oMap = o as Map<String, dynamic>;
              return QuestionOption(
                label: oMap['label'] as String? ?? '',
                description: oMap['description'] as String? ?? '',
              );
            }).toList(),
            multiple: qMap['multiple'] as bool? ?? false,
            custom: qMap['custom'] as bool? ?? false,
          );
        }).toList();

        final answersRaw = v['answers'] as List<dynamic>? ?? [];
        final answers = answersRaw
            .map((a) => (a as List<dynamic>).cast<String>())
            .toList();

        _answeredQuestions[entry.key] = AnsweredQuestionData(
          request: QuestionRequest(
            id: entry.key,
            sessionID: v['sessionID'] as String? ?? '',
            questions: questions,
          ),
          answers: answers,
          associatedMessageId: v['msgId'] as String?,
          textInsertOffset: v['offset'] as int? ?? 0,
        );
      }
    } catch (e) {
      debugPrint('[PAI_SSE] Failed to load persisted answered questions: $e');
    }
  }

  /// Reidrata o histórico depois de queda/reconexão do SSE.
  Future<void> _rehydrateCurrentSession() async {
    debugPrint('[PAI_CONNECTIVITY] Rehydrating current session...');

    _sseSubscription?.cancel();
    _sseSubscription = null;
    _client?.unsubscribe();

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
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _connectivity.removeListener(_onConnectionStateChanged);
    _connectivity.dispose();
    _sseSubscription?.cancel();
    _continuationTimer?.cancel();
    _notifyThrottle?.cancel();
    _client?.unsubscribe();
    super.dispose();
  }
}
