import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:pai_mobile_flutter/services/ssh_gate_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake local_auth platform so the gate can be tested headlessly.
class _FakePlatform extends LocalAuthPlatform {
  _FakePlatform({required this.supported, required this.results});

  bool supported;
  List<bool> results; // consumed per authenticate() call
  int calls = 0;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    final r = results[calls.clamp(0, results.length - 1)];
    calls++;
    return r;
  }

  @override
  Future<bool> deviceSupportsBiometrics() async => supported;

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async => [];

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> stopAuthentication() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // In-memory mock for flutter_secure_storage so the failure counter
    // persists within a test run.
    final secure = <String, String>{};
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'read':
          return secure[args!['key']];
        case 'write':
          secure[args!['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          secure.remove(args!['key']);
          return null;
        case 'containsKey':
          return secure.containsKey(args!['key']);
        case 'readAll':
          return Map<String, String>.from(secure);
        case 'deleteAll':
          secure.clear();
          return null;
        default:
          return null;
      }
    });
    SshGateService.lock('m1');
  });

  SshGateService gateWith(_FakePlatform p) {
    LocalAuthPlatform.instance = p;
    return SshGateService(localAuth: LocalAuthentication());
  }

  test('unavailable when device has no lock', () async {
    final gate = gateWith(_FakePlatform(supported: false, results: [false]));
    final r = await gate.authorize(machineId: 'm1');
    expect(r.outcome, SshGateOutcome.unavailable);
  });

  test('authorized on success and unlocks the session window', () async {
    final gate = gateWith(_FakePlatform(supported: true, results: [true]));
    final r = await gate.authorize(machineId: 'm1');
    expect(r.outcome, SshGateOutcome.authorized);
    expect(SshGateService.isUnlocked('m1'), isTrue);
  });

  test('three consecutive failures escalate to wiped', () async {
    final gate =
        gateWith(_FakePlatform(supported: true, results: [false, false, false]));
    final r1 = await gate.authorize(machineId: 'm1');
    expect(r1.outcome, SshGateOutcome.failed);
    expect(r1.attemptsRemaining, 2);
    final r2 = await gate.authorize(machineId: 'm1');
    expect(r2.outcome, SshGateOutcome.failed);
    expect(r2.attemptsRemaining, 1);
    final r3 = await gate.authorize(machineId: 'm1');
    expect(r3.outcome, SshGateOutcome.wiped);
    // Counter cleared after wipe.
    expect(await SshGateService.failureCount('m1'), 0);
  });

  test('a success resets the failure budget', () async {
    final gate = gateWith(
        _FakePlatform(supported: true, results: [false, true]));
    expect((await gate.authorize(machineId: 'm1')).outcome,
        SshGateOutcome.failed);
    expect((await gate.authorize(machineId: 'm1')).outcome,
        SshGateOutcome.authorized);
    expect(await SshGateService.failureCount('m1'), 0);
  });
}
