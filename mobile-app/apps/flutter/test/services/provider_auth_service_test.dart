import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/services/provider_auth_service.dart';

void main() {
  group('mergeProviderAuthJson', () {
    test('creates entry from empty JSON', () {
      final result = mergeProviderAuthJson(
        currentJson: '{}',
        providerId: 'openai',
        apiKey: 'sk-test',
      );

      expect(result, {
        'openai': {'type': 'api', 'key': 'sk-test'},
      });
    });

    test('creates entry from invalid JSON', () {
      final result = mergeProviderAuthJson(
        currentJson: 'not json at all',
        providerId: 'anthropic',
        apiKey: 'sk-ant-test',
      );

      expect(result, {
        'anthropic': {'type': 'api', 'key': 'sk-ant-test'},
      });
    });

    test('creates entry from empty string', () {
      final result = mergeProviderAuthJson(
        currentJson: '',
        providerId: 'openai',
        apiKey: 'sk-test',
      );

      expect(result, {
        'openai': {'type': 'api', 'key': 'sk-test'},
      });
    });

    test('updates existing provider', () {
      final existing = jsonEncode({
        'openai': {'type': 'api', 'key': 'old-key'},
      });

      final result = mergeProviderAuthJson(
        currentJson: existing,
        providerId: 'openai',
        apiKey: 'new-key',
      );

      expect(result['openai'], {'type': 'api', 'key': 'new-key'});
    });

    test('preserves other providers when adding new one', () {
      final existing = jsonEncode({
        'openai': {'type': 'api', 'key': 'sk-openai'},
        'google': {'type': 'api', 'key': 'google-key'},
      });

      final result = mergeProviderAuthJson(
        currentJson: existing,
        providerId: 'anthropic',
        apiKey: 'sk-ant',
      );

      expect(result.length, 3);
      expect(result['openai'], {'type': 'api', 'key': 'sk-openai'});
      expect(result['google'], {'type': 'api', 'key': 'google-key'});
      expect(result['anthropic'], {'type': 'api', 'key': 'sk-ant'});
    });

    test('type is always "api", regardless of provider name', () {
      for (final name in ['openai', 'anthropic', 'google', 'openrouter', 'custom-thing']) {
        final result = mergeProviderAuthJson(
          currentJson: '{}',
          providerId: name,
          apiKey: 'test-key',
        );
        expect(result[name]['type'], 'api',
            reason: 'type for $name should be "api"');
      }
    });

    test('handles JSON array (non-object) as empty', () {
      final result = mergeProviderAuthJson(
        currentJson: '["not","an","object"]',
        providerId: 'openai',
        apiKey: 'sk-test',
      );

      expect(result, {
        'openai': {'type': 'api', 'key': 'sk-test'},
      });
    });
  });

  group('buildAuthJsonWriteCommand', () {
    test('produces heredoc with unique delimiter', () {
      final authData = {'openai': {'type': 'api', 'key': 'sk-test'}};
      final cmd = buildAuthJsonWriteCommand(authData);

      expect(cmd, contains('mkdir -p ~/.local/share/opencode'));
      expect(cmd, contains('cat > ~/.local/share/opencode/auth.json'));
      expect(cmd, contains('PAI_AUTH_JSON_'));
      expect(cmd, contains('"openai"'));
      expect(cmd, contains('"type": "api"'));
    });

    test('delimiter does not appear in JSON content', () {
      final authData = {'openai': {'type': 'api', 'key': 'sk-test'}};
      final cmd = buildAuthJsonWriteCommand(authData);

      // Extract delimiter from the heredoc syntax
      final match = RegExp(r"<<'(.+?)'").firstMatch(cmd);
      expect(match, isNotNull);
      final delimiter = match!.group(1)!;

      // The JSON content between the delimiters should not contain the delimiter
      final jsonContent = const JsonEncoder.withIndent('  ').convert(authData);
      expect(jsonContent.contains(delimiter), isFalse);
    });
  });
}
