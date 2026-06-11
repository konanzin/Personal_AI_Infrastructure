/// Pure formatting helpers used by the chat UI.
library;

/// Guesses a MIME type from a file path extension.
String guessMimeType(String path) {
  final ext = path.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'pdf' => 'application/pdf',
    'txt' || 'md' => 'text/plain',
    'json' => 'application/json',
    'dart' => 'text/x-dart',
    _ => 'application/octet-stream',
  };
}

/// Formats the session token-usage map ("in: N, out: N, ...").
String formatTokenUsage(dynamic tokens) {
  if (tokens is Map) {
    final input = tokens['input'] ?? 0;
    final output = tokens['output'] ?? 0;
    final reasoning = tokens['reasoning'] ?? 0;
    final cache = tokens['cache'];
    final cacheRead = cache is Map ? (cache['read'] ?? 0) : 0;
    final parts = <String>['in: $input', 'out: $output'];
    if (reasoning != 0) parts.add('reason: $reasoning');
    if (cacheRead != 0) parts.add('cache: $cacheRead');
    return parts.join(', ');
  }
  return tokens?.toString() ?? '0';
}
