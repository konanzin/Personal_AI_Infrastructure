import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/services/telos_identity_service.dart';

void main() {
  group('parsePrincipalName', () {
    test('extracts the name from the quick-reference line', () {
      const md = '''
# Principal Identity — User

## Quick Reference

- **Name:** Rodrigo Ferreira
- **Timezone:** America/Sao_Paulo
''';
      expect(parsePrincipalName(md), 'Rodrigo Ferreira');
    });

    test('bootstrap placeholder "User" is treated as no name', () {
      expect(parsePrincipalName('- **Name:** User'), isNull);
      expect(parsePrincipalName('- **Name:** user'), isNull);
    });

    test('unfilled interview placeholder is treated as no name', () {
      expect(parsePrincipalName('- **Name:** (interview)'), isNull);
    });

    test('missing line or empty content returns null', () {
      expect(parsePrincipalName(''), isNull);
      expect(parsePrincipalName('no name field here'), isNull);
    });

    test('tolerates extra whitespace', () {
      expect(parsePrincipalName('-   **Name:**   Dori  '), 'Dori');
    });
  });

  group('firstNameOf', () {
    test('returns the first whitespace-separated token', () {
      expect(firstNameOf('Rodrigo Ferreira'), 'Rodrigo');
      expect(firstNameOf('  Dori  '), 'Dori');
      expect(firstNameOf('Madonna'), 'Madonna');
    });
  });
}
