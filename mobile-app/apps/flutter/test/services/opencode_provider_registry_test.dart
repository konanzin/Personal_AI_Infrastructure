import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/services/opencode_client.dart';

void main() {
  group('OpenCodeProviderRegistry.modelIds', () {
    test('extracts provider/model from {providers:[{id, models:{}}]} shape', () {
      const registry = OpenCodeProviderRegistry({
        'providers': [
          {
            'id': 'kimi-for-coding',
            'models': {'k2p6': {}, 'k2p7': {}},
          },
          {
            'id': 'openai',
            'models': {'gpt-5.5': {}},
          },
        ],
      });
      expect(registry.modelIds, [
        'kimi-for-coding/k2p6',
        'kimi-for-coding/k2p7',
        'openai/gpt-5.5',
      ]);
    });

    test('handles models as a List of ids', () {
      const registry = OpenCodeProviderRegistry({
        'providers': [
          {
            'id': 'opencode',
            'models': ['big-pickle', 'deepseek-v4-flash-free'],
          },
        ],
      });
      expect(registry.modelIds,
          ['opencode/big-pickle', 'opencode/deepseek-v4-flash-free']);
    });

    test('handles models as a List of {id|name} objects', () {
      const registry = OpenCodeProviderRegistry({
        'providers': [
          {
            'id': 'p',
            'models': [
              {'id': 'm1'},
              {'name': 'm2'},
            ],
          },
        ],
      });
      expect(registry.modelIds, ['p/m1', 'p/m2']);
    });

    test('handles the flat id->data fallback shape', () {
      const registry = OpenCodeProviderRegistry({
        'openai': {
          'models': {'gpt-5.5': {}},
        },
      });
      expect(registry.modelIds, ['openai/gpt-5.5']);
    });

    test('result is sorted and de-duplicated', () {
      const registry = OpenCodeProviderRegistry({
        'providers': [
          {
            'id': 'z',
            'models': ['b', 'a'],
          },
          {
            'id': 'a',
            'models': ['a'],
          },
        ],
      });
      expect(registry.modelIds, ['a/a', 'z/a', 'z/b']);
    });

    test('skips providers without id and empty model sets', () {
      const registry = OpenCodeProviderRegistry({
        'providers': [
          {'models': {'orphan': {}}}, // no id → skipped
          {'id': 'p', 'models': {}},
        ],
      });
      expect(registry.modelIds, isEmpty);
    });

    test('empty registry → empty list', () {
      expect(const OpenCodeProviderRegistry({}).modelIds, isEmpty);
    });
  });
}
