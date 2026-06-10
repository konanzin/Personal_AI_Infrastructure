const _sentinel = Object();

class SshConfig {
  final String host;
  final int port;
  final String username;
  final String? privateKey;
  final String? password;

  const SshConfig({
    required this.host,
    this.port = 22,
    required this.username,
    this.privateKey,
    this.password,
  });

  factory SshConfig.fromJson(Map<String, dynamic> json) {
    return SshConfig(
      host: json['host'] as String,
      port: json['port'] as int? ?? 22,
      username: json['username'] as String,
      privateKey: json['privateKey'] as String?,
      password: json['password'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        if (privateKey != null) 'privateKey': privateKey,
        if (password != null) 'password': password,
      };

  SshConfig copyWith({
    String? host,
    int? port,
    String? username,
    Object? privateKey = _sentinel,
    Object? password = _sentinel,
  }) {
    return SshConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      privateKey: privateKey == _sentinel
          ? this.privateKey
          : privateKey as String?,
      password: password == _sentinel ? this.password : password as String?,
    );
  }
}

class Machine {
  final String id;
  final String name;
  final String serverUrl;
  final String username;
  final String password;
  final int requestTimeoutSeconds;
  final String? defaultDirectory;
  final SshConfig? ssh;
  final String? paiAgentUrl;
  final DateTime? lastConnected;

  const Machine({
    required this.id,
    required this.name,
    required this.serverUrl,
    required this.username,
    required this.password,
    this.requestTimeoutSeconds = 30,
    this.defaultDirectory,
    this.ssh,
    this.paiAgentUrl,
    this.lastConnected,
  });

  factory Machine.fromJson(Map<String, dynamic> json) {
    return Machine(
      id: json['id'] as String,
      name: json['name'] as String,
      serverUrl: json['serverUrl'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      requestTimeoutSeconds: json['requestTimeoutSeconds'] as int? ?? 30,
      defaultDirectory: json['defaultDirectory'] as String?,
      ssh: json['ssh'] != null
          ? SshConfig.fromJson(json['ssh'] as Map<String, dynamic>)
          : null,
      paiAgentUrl: json['paiAgentUrl'] as String?,
      lastConnected: json['lastConnected'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastConnected'] as int)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'serverUrl': serverUrl,
        'username': username,
        'password': password,
        'requestTimeoutSeconds': requestTimeoutSeconds,
        if (defaultDirectory != null) 'defaultDirectory': defaultDirectory,
        if (ssh != null) 'ssh': ssh!.toJson(),
        if (paiAgentUrl != null) 'paiAgentUrl': paiAgentUrl,
        if (lastConnected != null)
          'lastConnected': lastConnected!.millisecondsSinceEpoch,
      };

  Machine copyWith({
    String? id,
    String? name,
    String? serverUrl,
    String? username,
    String? password,
    int? requestTimeoutSeconds,
    Object? defaultDirectory = _sentinel,
    SshConfig? ssh,
    Object? paiAgentUrl = _sentinel,
    DateTime? lastConnected,
  }) {
    return Machine(
      id: id ?? this.id,
      name: name ?? this.name,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      requestTimeoutSeconds:
          requestTimeoutSeconds ?? this.requestTimeoutSeconds,
      defaultDirectory: defaultDirectory == _sentinel
          ? this.defaultDirectory
          : defaultDirectory as String?,
      ssh: ssh ?? this.ssh,
      paiAgentUrl: paiAgentUrl == _sentinel
          ? this.paiAgentUrl
          : paiAgentUrl as String?,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }
}
