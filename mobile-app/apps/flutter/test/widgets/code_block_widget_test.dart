import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/widgets/code_block_widget.dart';

void main() {
  Future<Container> pumpAndGetRoot(
      WidgetTester tester, ThemeData theme) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: CodeBlockWidget(code: 'void main() {}', language: 'dart'),
        ),
      ),
    );
    return tester.widget<Container>(
      find
          .descendant(
            of: find.byType(CodeBlockWidget),
            matching: find.byType(Container),
          )
          .first,
    );
  }

  testWidgets('uses light highlight background in light theme',
      (tester) async {
    final root = await pumpAndGetRoot(tester, ThemeData.light());
    final decoration = root.decoration! as BoxDecoration;
    expect(decoration.color, atomOneLightTheme['root']!.backgroundColor);
  });

  testWidgets('uses dark highlight background in dark theme', (tester) async {
    final root = await pumpAndGetRoot(tester, ThemeData.dark());
    final decoration = root.decoration! as BoxDecoration;
    expect(decoration.color, atomOneDarkTheme['root']!.backgroundColor);
  });
}
