import 'dart:convert';

const providerAuthJsonPath = r'~/.local/share/opencode/auth.json';

/// Merges a provider entry into an existing auth.json content string.
///
/// Returns the merged map. The `type` field is always `"api"` per the
/// OpenCode auth.json format validated in the spike.
///
/// If [currentJson] is empty, invalid, or not a JSON object, a fresh
/// map is created.
Map<String, dynamic> mergeProviderAuthJson({
  required String currentJson,
  required String providerId,
  required String apiKey,
}) {
  Map<String, dynamic> authData;
  try {
    final decoded = jsonDecode(currentJson);
    authData = decoded is Map<String, dynamic> ? Map.of(decoded) : {};
  } catch (_) {
    authData = {};
  }

  authData[providerId] = {
    'type': 'api',
    'key': apiKey,
  };

  return authData;
}

/// Builds the SSH command to write [authData] to the auth.json file
/// using a heredoc with a unique delimiter to avoid content injection.
String buildAuthJsonWriteCommand(Map<String, dynamic> authData) {
  final json = const JsonEncoder.withIndent('  ').convert(authData);
  final ts = DateTime.now().microsecondsSinceEpoch;
  var delimiter = 'PAI_AUTH_JSON_$ts';

  // In the astronomically unlikely case the JSON contains the delimiter
  while (json.contains(delimiter)) {
    delimiter = '${delimiter}_X';
  }

  return 'mkdir -p ~/.local/share/opencode && '
      "cat > $providerAuthJsonPath <<'$delimiter'\n$json\n$delimiter";
}
