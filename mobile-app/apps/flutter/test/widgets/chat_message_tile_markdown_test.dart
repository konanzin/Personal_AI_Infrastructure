import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/models/chat_message.dart';
import 'package:pai_mobile_flutter/widgets/chat_message_tile.dart';
import 'package:pai_mobile_flutter/l10n/app_localizations.dart';

void main() {
  Future<void> pumpTile(WidgetTester tester, String markdown,
      {bool isStreaming = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChatMessageTile(
              message: ChatMessage.llm(),
              historyIndex: 0,
              displayText: markdown,
              isStreaming: isStreaming,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders list followed by fenced dart code block (M5 test 1)',
      (tester) async {
    const markdown = '- Dart\n'
        '- Flutter\n'
        '- Widgets\n'
        '\n'
        '```dart\n'
        "void main() {\n  print('Olá, Dart!');\n}\n"
        '```';
    await pumpTile(tester, markdown);
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.textContaining('Dart'), findsWidgets);
  });

  testWidgets('renders plain code block alone', (tester) async {
    await pumpTile(tester, '```dart\nvoid main() {}\n```');
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('renders code block while streaming', (tester) async {
    await pumpTile(tester, '```dart\nvoid main() {}\n```', isStreaming: true);
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('renders user attachments as chips', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatMessageTile(
            message: ChatMessage.user('see this', [
              FileAttachment(
                name: 'notes.txt',
                mimeType: 'text/plain',
                bytes: Uint8List.fromList([1, 2, 3]),
              ),
            ]),
            historyIndex: 0,
            displayText: 'see this',
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('see this'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
  });

  group('splitFencedCodeBlocks', () {
    test('prose only yields a single text segment', () {
      final segs = splitFencedCodeBlocks('Oi **mundo**');
      expect(segs, hasLength(1));
      expect(segs.single.isCode, isFalse);
    });

    test('prose, code, prose', () {
      final segs = splitFencedCodeBlocks(
          'antes\n\n```dart\nvoid main() {}\n```\n\ndepois');
      expect(segs.map((s) => s.isCode), [false, true, false]);
      expect(segs[1].language, 'dart');
      expect(segs[1].text, 'void main() {}');
      expect(segs[0].text.trim(), 'antes');
      expect(segs[2].text.trim(), 'depois');
    });

    test('unclosed trailing fence becomes code segment (streaming)', () {
      final segs = splitFencedCodeBlocks('texto\n```py\nprint(1)');
      expect(segs.map((s) => s.isCode), [false, true]);
      expect(segs[1].language, 'py');
      expect(segs[1].text, 'print(1)');
    });

    test('indented fence and no language', () {
      final segs = splitFencedCodeBlocks('  ```\nx\n  ```');
      expect(segs.single.isCode, isTrue);
      expect(segs.single.language, isEmpty);
      expect(segs.single.text, 'x');
    });

    test('inline backticks are not fences', () {
      final segs = splitFencedCodeBlocks('use `flutter run` para rodar');
      expect(segs.single.isCode, isFalse);
    });
  });
}
