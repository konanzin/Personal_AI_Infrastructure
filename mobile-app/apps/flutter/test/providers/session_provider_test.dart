import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/providers/session_provider.dart';
import 'package:pai_mobile_flutter/services/api_errors.dart';
import 'package:pai_mobile_flutter/services/opencode_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSessionClient extends OpenCodeClient {
  _FakeSessionClient(this.onGetSession)
      : super(ClientConfig(
          baseUrl: 'http://localhost:1',
          username: 'u',
          password: 'p',
        ));

  final Future<Map<String, dynamic>> Function(String sessionId) onGetSession;

  @override
  Future<Map<String, dynamic>> getSession(String sessionId) =>
      onGetSession(sessionId);
}

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

  group('verifySessionScope (bijective session rule)', () {
    SessionProvider providerWith(
        Future<Map<String, dynamic>> Function(String) onGetSession) {
      final provider = SessionProvider();
      provider.sharedClient = _FakeSessionClient(onGetSession);
      return provider;
    }

    test('accepts a session in the expected directory', () async {
      final provider =
          providerWith((_) async => {'id': 's1', 'directory': '/repo-a'});
      expect(
        await provider.verifySessionScope('s1', expectedDirectory: '/repo-a'),
        isTrue,
      );
    });

    test('rejects a session from a different directory', () async {
      final provider =
          providerWith((_) async => {'id': 's1', 'directory': '/repo-b'});
      expect(
        await provider.verifySessionScope('s1', expectedDirectory: '/repo-a'),
        isFalse,
      );
    });

    test('ignores trailing slashes when comparing', () async {
      final provider =
          providerWith((_) async => {'id': 's1', 'directory': '/repo-a/'});
      expect(
        await provider.verifySessionScope('s1', expectedDirectory: '/repo-a'),
        isTrue,
      );
    });

    test('rejects a session that no longer exists', () async {
      final provider = providerWith(
          (_) async => throw const NotFoundError(message: 'gone'));
      expect(
        await provider.verifySessionScope('s1', expectedDirectory: '/repo-a'),
        isFalse,
      );
    });

    test('fails open when the server is unreachable', () async {
      final provider = providerWith(
          (_) async => throw const ApiConnectionError(message: 'offline'));
      expect(
        await provider.verifySessionScope('s1', expectedDirectory: '/repo-a'),
        isTrue,
      );
    });

    test('skips verification for non-absolute expected directories', () async {
      final provider =
          providerWith((_) async => {'id': 's1', 'directory': '/repo-b'});
      expect(
        await provider.verifySessionScope('s1', expectedDirectory: '~/repo-a'),
        isTrue,
      );
    });
  });
}
