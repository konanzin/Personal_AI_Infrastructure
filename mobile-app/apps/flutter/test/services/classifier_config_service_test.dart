import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/services/classifier_config_service.dart';

void main() {
  group('mergeClassifierConfigJson', () {
    test('creates entry from empty JSON', () {
      final result = mergeClassifierConfigJson(
        currentJson: '{}',
        model: 'openai/gpt-5.5',
        useLlm: true,
        timeoutMs: 8000,
      );

      expect(result, {
        'model': 'openai/gpt-5.5',
        'useLLM': true,
        'timeoutMs': 8000,
      });
    });

    test('creates entry from invalid JSON', () {
      final result = mergeClassifierConfigJson(
        currentJson: 'not json at all',
        model: 'anthropic/claude-opus',
      );

      expect(result, {'model': 'anthropic/claude-opus'});
    });

    test('creates entry from empty string', () {
      final result = mergeClassifierConfigJson(
        currentJson: '',
        useLlm: false,
      );

      expect(result, {'useLLM': false});
    });

    test('only provided fields are written; null leaves existing untouched', () {
      final existing = jsonEncode({
        'model': 'old/model',
        'useLLM': true,
        'timeoutMs': 25000,
      });

      final result = mergeClassifierConfigJson(
        currentJson: existing,
        model: 'new/model',
        // useLlm and timeoutMs omitted → preserved
      );

      expect(result['model'], 'new/model');
      expect(result['useLLM'], true);
      expect(result['timeoutMs'], 25000);
    });

    test('preserves unrelated keys already in the file', () {
      final existing = jsonEncode({
        'model': 'old/model',
        'somethingElse': 'keep-me',
      });

      final result = mergeClassifierConfigJson(
        currentJson: existing,
        useLlm: false,
      );

      expect(result['model'], 'old/model');
      expect(result['somethingElse'], 'keep-me');
      expect(result['useLLM'], false);
    });

    test('handles JSON array (non-object) as empty', () {
      final result = mergeClassifierConfigJson(
        currentJson: '["not","an","object"]',
        model: 'openai/gpt-5.5',
      );

      expect(result, {'model': 'openai/gpt-5.5'});
    });

    test('no fields provided → empty map (preserves nothing new)', () {
      final result = mergeClassifierConfigJson(currentJson: '{}');
      expect(result, isEmpty);
    });
  });

  group('parseClassifierConfigJson', () {
    test('reads model and useLLM from a populated file', () {
      final result = parseClassifierConfigJson(
          '{"model":"kimi-for-coding/k2p6","useLLM":true}');
      expect(result.model, 'kimi-for-coding/k2p6');
      expect(result.useLlm, true);
    });

    test('empty / absent file → nulls (server default)', () {
      expect(parseClassifierConfigJson('').model, isNull);
      expect(parseClassifierConfigJson('').useLlm, isNull);
    });

    test('invalid JSON → nulls', () {
      final result = parseClassifierConfigJson('not json');
      expect(result.model, isNull);
      expect(result.useLlm, isNull);
    });

    test('non-object JSON (array) → nulls', () {
      expect(parseClassifierConfigJson('[1,2,3]').model, isNull);
    });

    test('empty model string treated as null', () {
      expect(parseClassifierConfigJson('{"model":""}').model, isNull);
    });

    test('non-boolean useLLM treated as null', () {
      expect(parseClassifierConfigJson('{"useLLM":"true"}').useLlm, isNull);
    });

    test('partial file: model only', () {
      final result = parseClassifierConfigJson('{"model":"openai/gpt-5.5"}');
      expect(result.model, 'openai/gpt-5.5');
      expect(result.useLlm, isNull);
    });
  });

  group('buildClassifierConfigWriteCommand', () {
    test('produces heredoc targeting the classifier config path', () {
      final cmd = buildClassifierConfigWriteCommand({
        'model': 'openai/gpt-5.5',
        'useLLM': true,
      });

      expect(cmd, contains('mkdir -p ~/.config/opencode/PAI/USER/Config'));
      expect(cmd, contains('cat > $classifierConfigPath'));
      expect(cmd, contains('PAI_CLASSIFIER_JSON_'));
      expect(cmd, contains('"model": "openai/gpt-5.5"'));
      expect(cmd, contains('"useLLM": true'));
    });

    test('delimiter does not appear in JSON content', () {
      final data = {'model': 'openai/gpt-5.5', 'useLLM': true};
      final cmd = buildClassifierConfigWriteCommand(data);

      final match = RegExp(r"<<'(.+?)'").firstMatch(cmd);
      expect(match, isNotNull);
      final delimiter = match!.group(1)!;

      final jsonContent = const JsonEncoder.withIndent('  ').convert(data);
      expect(jsonContent.contains(delimiter), isFalse);
    });
  });
}
