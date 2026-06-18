import 'dart:convert';

/// Path of the per-machine prompt-classifier config on the OpenCode server.
/// The PAI hooks plugin reads this file hot (mtime-cached), so writes apply
/// without a server restart. Precedence on the server: env var > this file >
/// hardcoded default.
const classifierConfigPath =
    r'~/.config/opencode/PAI/USER/Config/classifier.json';

/// Merges classifier settings into an existing classifier.json content string.
///
/// Only the provided fields are written; absent ([null]) fields leave any
/// existing value untouched. If [currentJson] is empty, invalid, or not a JSON
/// object, a fresh map is created.
Map<String, dynamic> mergeClassifierConfigJson({
  required String currentJson,
  String? model,
  bool? useLlm,
  int? timeoutMs,
}) {
  Map<String, dynamic> data;
  try {
    final decoded = jsonDecode(currentJson);
    data = decoded is Map<String, dynamic> ? Map.of(decoded) : {};
  } catch (_) {
    data = {};
  }

  if (model != null) data['model'] = model;
  if (useLlm != null) data['useLLM'] = useLlm;
  if (timeoutMs != null) data['timeoutMs'] = timeoutMs;

  return data;
}

/// Parses classifier.json content read from the server into its fields.
///
/// Tolerant of an empty/absent/invalid file (returns nulls), so the caller can
/// treat "no config" as "server uses its built-in default". `useLlm` is only
/// returned when the stored value is an actual boolean.
({String? model, bool? useLlm}) parseClassifierConfigJson(String currentJson) {
  try {
    final decoded = jsonDecode(currentJson);
    if (decoded is Map<String, dynamic>) {
      final model = decoded['model'];
      final useLlm = decoded['useLLM'];
      return (
        model: model is String && model.isNotEmpty ? model : null,
        useLlm: useLlm is bool ? useLlm : null,
      );
    }
  } catch (_) {
    // Empty / not JSON / not an object → treat as no config.
  }
  return (model: null, useLlm: null);
}

/// Builds the SSH command to write [data] to the classifier config file using
/// a heredoc with a unique delimiter to avoid content injection.
String buildClassifierConfigWriteCommand(Map<String, dynamic> data) {
  final json = const JsonEncoder.withIndent('  ').convert(data);
  final ts = DateTime.now().microsecondsSinceEpoch;
  var delimiter = 'PAI_CLASSIFIER_JSON_$ts';

  // In the astronomically unlikely case the JSON contains the delimiter
  while (json.contains(delimiter)) {
    delimiter = '${delimiter}_X';
  }

  return 'mkdir -p ~/.config/opencode/PAI/USER/Config && '
      "cat > $classifierConfigPath <<'$delimiter'\n$json\n$delimiter";
}
