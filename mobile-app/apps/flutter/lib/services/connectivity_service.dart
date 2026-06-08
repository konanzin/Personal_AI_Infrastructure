import 'dart:async';
import 'dart:math';

/// Estados possíveis da conexão
enum ConnectionStatus {
  online,      // Conectado e funcionando
  offline,     // Sem conexão
  connecting,  // Tentando reconectar
  error,       // Erro na conexão
}

/// Serviço de monitoramento de conectividade com reconexão automática
class ConnectivityService {
  ConnectionStatus _state = ConnectionStatus.offline;
  
  int _retryCount = 0;
  static const Duration baseRetryDelay = Duration(seconds: 1);
  static const Duration maxRetryDelay = Duration(seconds: 30);
  
  Timer? _retryTimer;
  Timer? _heartbeatTimer;
  
  // Callbacks
  final List<Function(ConnectionStatus)> _listeners = [];
  
  // Heartbeat
  DateTime? _lastHeartbeat;
  static const Duration heartbeatTimeout = Duration(seconds: 30);
  static const Duration heartbeatInterval = Duration(seconds: 15);
  
  ConnectionStatus get state => _state;
  
  bool get isOnline => _state == ConnectionStatus.online;
  bool get isOffline => _state == ConnectionStatus.offline;
  bool get isConnecting => _state == ConnectionStatus.connecting;
  
  /// Adiciona listener para mudanças de estado
  void addListener(Function(ConnectionStatus) listener) {
    _listeners.add(listener);
  }
  
  void removeListener(Function(ConnectionStatus) listener) {
    _listeners.remove(listener);
  }
  
  /// Notifica todos os listeners
  void _notifyListeners() {
    for (final listener in List<Function(ConnectionStatus)>.from(_listeners)) {
      listener(_state);
    }
  }
  
  /// Atualiza estado e notifica
  void _setState(ConnectionStatus newState) {
    if (_state != newState) {
      _state = newState;
      _notifyListeners();
    }
  }
  
  /// Inicia monitoramento
  void startMonitoring() {
    _startHeartbeat();
  }
  
  /// Para monitoramento
  void stopMonitoring() {
    _retryTimer?.cancel();
    _heartbeatTimer?.cancel();
    _retryTimer = null;
    _heartbeatTimer = null;
  }
  
  /// Registra heartbeat (chamado quando recebe evento SSE)
  void heartbeat() {
    _lastHeartbeat = DateTime.now();
    if (_state != ConnectionStatus.online) {
      _setState(ConnectionStatus.online);
      _retryCount = 0; // Reseta contador de retry
    }
  }
  
  /// Inicia timer de heartbeat
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      _checkHeartbeat();
    });
  }
  
  /// Verifica se heartbeat está dentro do timeout
  void _checkHeartbeat() {
    if (_lastHeartbeat == null) return;
    
    final elapsed = DateTime.now().difference(_lastHeartbeat!);
    if (elapsed > heartbeatTimeout && _state == ConnectionStatus.online) {
      _setState(ConnectionStatus.offline);
    }
  }
  
  /// Marca como offline e inicia reconexão
  void markOffline() {
    _setState(ConnectionStatus.offline);
  }
  
  /// Marca como erro
  void markError() {
    _setState(ConnectionStatus.error);
  }
  
  /// Inicia reconexão com backoff exponencial
  void startReconnect(Function() onReconnect) {
    _setState(ConnectionStatus.connecting);
    
    // Calcula delay com jitter
    final delay = _calculateRetryDelay();
    
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryCount++;
      onReconnect();
    });
  }
  
  /// Calcula delay de retry com backoff exponencial + jitter
  Duration _calculateRetryDelay() {
    // Retry backoff: 1s, 2s, 4s, 8s, 16s, 30s, 30s...
    final exponential = baseRetryDelay * pow(2, _retryCount);
    final clamped = exponential > maxRetryDelay ? maxRetryDelay : exponential;
    
    // Jitter: adiciona aleatoriedade de ±25%
    final jitter = Random().nextDouble() * 0.5 - 0.25;
    final jittered = clamped * (1 + jitter);
    
    return Duration(milliseconds: jittered.inMilliseconds);
  }
  
  /// Cancela reconexão pendente
  void cancelReconnect() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
  
  /// Reseta estado para online (usado após reconexão bem-sucedida)
  void markOnline() {
    _retryCount = 0;
    _lastHeartbeat = DateTime.now();
    _setState(ConnectionStatus.online);
  }
  
  /// Libera recursos
  void dispose() {
    stopMonitoring();
    _listeners.clear();
  }
}
