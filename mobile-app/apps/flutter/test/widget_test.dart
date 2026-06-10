import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pai_mobile_flutter/main.dart';

void main() {
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      // Return empty credentials so the app shows the welcome screen.
      return null;
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  testWidgets('App renders welcome screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PaiMobileApp());
    await tester.pumpAndSettle();

    // Verify that the welcome screen content is present.
    expect(find.text('PAI'), findsOneWidget);
    expect(find.text('Your Personal AI Assistant'), findsOneWidget);
    expect(find.text('Set Up Machine'), findsOneWidget);
  });
}
