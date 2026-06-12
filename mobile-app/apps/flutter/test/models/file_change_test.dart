import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/models/file_change.dart';

void main() {
  group('FileChange.fromJson', () {
    test('parses legacy {path, diff} shape', () {
      final change = FileChange.fromJson(
        {'path': 'lib/main.dart', 'diff': '--- a\n+++ b'},
        FileChangeType.edited,
      );
      expect(change.path, 'lib/main.dart');
      expect(change.diff, '--- a\n+++ b');
    });

    test('parses 1.17+ SnapshotFileDiff {file, patch} shape', () {
      final change = FileChange.fromJson(
        {
          'file': 'lib/main.dart',
          'patch': '--- a\n+++ b',
          'additions': 1,
          'deletions': 0,
          'status': 'modified',
        },
        FileChangeType.diff,
      );
      expect(change.path, 'lib/main.dart');
      expect(change.diff, '--- a\n+++ b');
    });

    test('does not throw on unexpected field types', () {
      final change = FileChange.fromJson(
        {'path': 42, 'diff': <dynamic>[]},
        FileChangeType.edited,
      );
      expect(change.path, 'unknown');
      expect(change.diff, isNull);
    });
  });

  group('FileChange.listFromEventProperties', () {
    test('expands 1.17+ session.diff list payload', () {
      final changes = FileChange.listFromEventProperties(
        {
          'sessionID': 'ses_123',
          'diff': [
            {'file': 'a.dart', 'patch': 'pa', 'additions': 1, 'deletions': 0},
            {'file': 'b.dart', 'patch': 'pb', 'additions': 0, 'deletions': 2},
            'garbage-entry',
          ],
        },
        FileChangeType.diff,
      );
      expect(changes, hasLength(2));
      expect(changes[0].path, 'a.dart');
      expect(changes[0].diff, 'pa');
      expect(changes[1].path, 'b.dart');
      expect(changes[1].diff, 'pb');
    });

    test('falls back to single change for legacy payload', () {
      final changes = FileChange.listFromEventProperties(
        {'path': 'c.dart', 'diff': 'pc'},
        FileChangeType.edited,
      );
      expect(changes, hasLength(1));
      expect(changes.single.path, 'c.dart');
      expect(changes.single.diff, 'pc');
    });
  });
}
