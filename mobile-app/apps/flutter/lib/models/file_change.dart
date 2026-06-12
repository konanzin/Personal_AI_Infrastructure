/// Represents a file change event from the server (session.diff or file.edited).
class FileChange {
  final String path;
  final String? diff;
  final FileChangeType type;

  const FileChange({
    required this.path,
    this.diff,
    this.type = FileChangeType.edited,
  });

  factory FileChange.fromJson(Map<String, dynamic> json, FileChangeType type) {
    // OpenCode <= 1.16 envia {path, diff}; 1.17+ usa SnapshotFileDiff
    // ({file, patch, status, ...}). Aceita ambos sem cast estrito.
    final path = json['path'] ?? json['file'];
    final diff = json['diff'] ?? json['patch'];
    return FileChange(
      path: path is String ? path : 'unknown',
      diff: diff is String ? diff : null,
      type: type,
    );
  }

  /// Expande as properties de um evento em 1+ mudanças de arquivo.
  /// No schema 1.17+ `session.diff` traz `diff` como lista de
  /// SnapshotFileDiff; no antigo as properties são a própria mudança.
  static List<FileChange> listFromEventProperties(
      Map<String, dynamic> props, FileChangeType type) {
    final diff = props['diff'];
    if (diff is List) {
      return [
        for (final item in diff)
          if (item is Map<String, dynamic>) FileChange.fromJson(item, type),
      ];
    }
    return [FileChange.fromJson(props, type)];
  }
}

enum FileChangeType { edited, created, deleted, diff }
