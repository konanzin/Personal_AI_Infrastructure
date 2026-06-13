import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/l10n/app_localizations.dart';
import 'package:pai_mobile_flutter/models/machine.dart';
import 'package:pai_mobile_flutter/providers/client_provider.dart';
import 'package:pai_mobile_flutter/providers/machine_store.dart';
import 'package:pai_mobile_flutter/screens/providers_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> storage;

  setUp(() {
    storage = {};
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>();
      switch (call.method) {
        case 'read':
          return storage[args!['key'] as String];
        case 'write':
          storage[args!['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          storage.remove(args!['key'] as String);
          return null;
        case 'readAll':
          return Map<String, String>.from(storage);
        case 'deleteAll':
          storage.clear();
          return null;
        case 'containsKey':
          return storage.containsKey(args!['key'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  testWidgets('provider dialog confirms before discarding unsaved input',
      (tester) async {
    final machineStore = MachineStore();
    await machineStore.addMachine(
      const Machine(
        id: 'ssh-machine',
        name: 'SSH Machine',
        serverUrl: 'http://100.64.0.10:4096',
        username: 'opencode',
        password: 'test-pass',
        ssh: SshConfig(
          host: '100.64.0.10',
          username: 'opencode',
          privateKey: 'test-key',
        ),
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MachineStore>.value(value: machineStore),
          ChangeNotifierProvider<ClientProvider>(
            create: (_) => ClientProvider(),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProvidersScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Add Provider'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'sk-test');
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.text('This provider has unsaved changes.'), findsOneWidget);

    await tester.tap(find.text('Continue editing'));
    await tester.pumpAndSettle();
    expect(find.text('Add Provider'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Add Provider'), findsNothing);
  });
}
