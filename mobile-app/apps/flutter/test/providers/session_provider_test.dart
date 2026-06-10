import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/providers/session_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists active session by machine and directory scope', () async {
    final provider = SessionProvider();

    await provider.selectSession(
      'session-a',
      machineId: 'machine-1',
      directory: '/repo-a',
    );

    final sameScope = SessionProvider();
    await sameScope.loadPersistedSession(
      machineId: 'machine-1',
      directory: '/repo-a',
    );
    expect(sameScope.currentSessionId, 'session-a');

    final otherDirectory = SessionProvider();
    await otherDirectory.loadPersistedSession(
      machineId: 'machine-1',
      directory: '/repo-b',
    );
    expect(otherDirectory.currentSessionId, isNull);

    final otherMachine = SessionProvider();
    await otherMachine.loadPersistedSession(
      machineId: 'machine-2',
      directory: '/repo-a',
    );
    expect(otherMachine.currentSessionId, isNull);
  });
}
