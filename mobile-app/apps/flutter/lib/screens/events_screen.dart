import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/chat_event.dart';
import '../services/opencode_client.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  // Configuration — in production, these would come from settings
  final _baseUrlController = TextEditingController(
    text: 'http://localhost:4096', // Uses adb reverse tcp:4096 tcp:4096
  );
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  OpenCodeClient? _client;
  StreamSubscription? _subscription;
  
  bool _isConnected = false;
  bool _isConnecting = false;
  String _status = 'Disconnected';
  
  final List<ChatEvent> _events = [];
  final ScrollController _scrollController = ScrollController();
  
  String? _currentSessionId;
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _disconnect(updateState: false);
    _baseUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _createSession() async {
    if (_client == null) return;
    try {
      final session = await _client!.createSession(title: 'Flutter Test');
      setState(() {
        _currentSessionId = session['id'] as String;
        _status = 'Session: ${_currentSessionId!.substring(0, 8)}...';
      });
      print('[PAI_DEBUG] Created session: ${_currentSessionId}');
    } catch (e) {
      setState(() {
        _status = 'Error creating session: $e';
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_client == null || _currentSessionId == null) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    try {
      await _client!.sendMessage(_currentSessionId!, text);
      _messageController.clear();
      setState(() {
        _status = 'Message sent to ${_currentSessionId!.substring(0, 8)}...';
      });
    } catch (e) {
      setState(() {
        _status = 'Error sending: $e';
      });
    }
  }

  void _disconnect({bool updateState = true}) {
    _subscription?.cancel();
    _subscription = null;
    _client?.unsubscribe();
    _client = null;
    if (updateState && mounted) {
      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _status = 'Disconnected';
      });
    }
  }

  Future<void> _connect() async {
    if (_isConnecting || _isConnected) return;

    setState(() {
      _isConnecting = true;
      _status = 'Connecting...';
      _events.clear();
    });

    final config = ClientConfig(
      baseUrl: _baseUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
    );

    _client = OpenCodeClient(config);

    // Verify auth first
    bool authOk;
    try {
      authOk = await _client!.verifyAuth();
    } catch (e) {
      authOk = false;
      print('[PAI_DEBUG] Auth exception: $e');
    }
    
    if (!authOk) {
      setState(() {
        _isConnecting = false;
        _status = 'Auth failed — check URL/credentials\n(URL: ${config.baseUrl})';
      });
      return;
    }

    // Subscribe to events
    final stream = _client!.subscribeToEvents();
    
    _subscription = stream.listen(
      (event) {
        setState(() {
          _events.add(event);
          if (event is ConnectedEvent) {
            _isConnected = true;
            _isConnecting = false;
            _status = 'Connected';
          } else if (event is DisconnectedEvent) {
            _isConnected = false;
            _status = 'Disconnected';
          } else if (event is ErrorEvent) {
            _status = 'Error: ${event.message}';
          }
        });
        
        // Auto-scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      },
      onError: (error) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _status = 'Stream error: $error';
        });
      },
      onDone: () {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _status = 'Stream closed';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PAI — OpenCode SSE'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Connection form
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _baseUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://localhost:3000',
                    border: OutlineInputBorder(),
                  ),
                  enabled: !_isConnected && !_isConnecting,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          border: OutlineInputBorder(),
                        ),
                        enabled: !_isConnected && !_isConnecting,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                        enabled: !_isConnected && !_isConnecting,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_isConnected || _isConnecting) ? null : _connect,
                        icon: _isConnecting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.link),
                        label: Text(_isConnecting ? 'Connecting...' : 'Connect'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isConnected ? _disconnect : null,
                        icon: const Icon(Icons.link_off),
                        label: const Text('Disconnect'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade100,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Status indicator
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _isConnected
                            ? Colors.green
                            : _isConnecting
                                ? Colors.orange
                                : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _status,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '${_events.length} events',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          // Events list
          Expanded(
            child: _events.isEmpty
                ? const Center(
                    child: Text(
                      'No events yet.\nConnect to see SSE events.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      return _EventCard(event: event);
                    },
                  ),
          ),
          // Session controls
          if (_isConnected)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _createSession,
                          icon: const Icon(Icons.add),
                          label: const Text('New Session'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_currentSessionId != null)
                        Expanded(
                          child: Chip(
                            label: Text(
                              'ID: ${_currentSessionId!.substring(0, 8)}...',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_currentSessionId != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: const InputDecoration(
                              hintText: 'Type a message...',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _sendMessage,
                          icon: const Icon(Icons.send),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final ChatEvent event;

  const _EventCard({required this.event});

  Color _getEventColor() {
    switch (event.type) {
      case 'connected':
        return Colors.green;
      case 'message':
        return Colors.blue;
      case 'status':
        return Colors.orange;
      case 'error':
        return Colors.red;
      case 'disconnected':
        return Colors.grey;
      default:
        return Colors.purple;
    }
  }

  IconData _getEventIcon() {
    switch (event.type) {
      case 'connected':
        return Icons.check_circle;
      case 'message':
        return Icons.message;
      case 'status':
        return Icons.info;
      case 'error':
        return Icons.error;
      case 'disconnected':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  dynamic _getEventPayload() {
    switch (event) {
      case MessageEvent e:
        return e.payload;
      case StatusEvent e:
        return e.payload;
      case ErrorEvent e:
        return {'message': e.message, 'error': e.error?.toString()};
      case TextDeltaEvent e:
        return {'delta': e.delta};
      case ReasoningDeltaEvent e:
        return {'reasoningId': e.reasoningId, 'delta': e.delta};
      case ToolCallCalledEvent e:
        return {'callId': e.callId, 'tool': e.toolName, 'input': e.input};
      case ToolCallSuccessEvent e:
        return {'callId': e.callId, 'content': e.content};
      case PermissionAskedEvent e:
        return {'id': e.request.id, 'permission': e.request.permission};
      case QuestionAskedEvent e:
        return {'id': e.request.id, 'questions': e.request.questions.length};
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload = _getEventPayload();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: Icon(
          _getEventIcon(),
          color: _getEventColor(),
        ),
        title: Text(
          event.type.toUpperCase(),
          style: TextStyle(
            color: _getEventColor(),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: event.sessionId != null
            ? Text('Session: ${event.sessionId}', style: const TextStyle(fontSize: 12))
            : null,
        trailing: event.originalEvent != null
            ? Chip(
                label: Text(
                  event.originalEvent!,
                  style: const TextStyle(fontSize: 10),
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (payload != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      const JsonEncoder.withIndent('  ').convert(payload),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
