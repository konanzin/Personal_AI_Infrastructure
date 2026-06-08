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
    return FileChange(
      path: json['path'] as String? ?? json['file'] as String? ?? 'unknown',
      diff: json['diff'] as String?,
      type: type,
    );
  }
}

enum FileChangeType { edited, created, deleted, diff }
