import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/models/machine.dart';
import 'package:pai_mobile_flutter/services/machine_bootstrap_service.dart';
import 'package:pai_mobile_flutter/services/ssh_service.dart';

class _FakeSsh extends SshService {
  final List<String> executed = [];
  bool connected = false;
  bool disconnected = false;
  Object? connectError;
  Object? Function(String command)? executeError;

  @override
  Future<void> connect({
    required String host,
    int port = 22,
    required String username,
    String? privateKeyPem,
    String? password,
    String? expectedHostKeyFingerprint,
  }) async {
    if (connectError != null) throw connectError!;
    connected = true;
  }

  @override
  String? get hostKeyFingerprint => connected ? 'ssh-ed25519:fp' : null;

  @override
  Future<String> execute(String command) async {
    final error = executeError?.call(command);
    if (error != null) throw error;
    executed.add(command);
    if (command == remoteOpenCodeLookupCommand()) {
      return '/usr/local/bin/opencode';
    }
    return '';
  }

  @override
  void disconnect() {
    disconnected = true;
  }
}

void main() {
  const sshConfig = SshConfig(host: 'h', username: 'u', password: 'pw');

  MachineBootstrapService service(_FakeSsh ssh) =>
      MachineBootstrapService(sshFactory: () => ssh);

  Stream<BootstrapEvent> run(_FakeSsh ssh, {SshConfig config = sshConfig}) =>
      service(ssh).bootstrap(
        ssh: config,
        serverUrl: 'http://localhost:1',
        serverUsername: 'opencode',
        serverPassword: 'secret',
        port: 4096,
        requestTimeoutSeconds: 1,
        httpRetries: 0,
      );

  test('emits steps in order and ends with a done event', () async {
    final ssh = _FakeSsh();
    final events = await run(ssh).toList();

    final steps = events
        .whereType<BootstrapStepEvent>()
        .map((e) => e.step)
        .toList();
    expect(
        steps,
        containsAllInOrder([
          BootstrapStep.connecting,
          BootstrapStep.provisioningKey,
          BootstrapStep.locatingOpenCode,
          BootstrapStep.installingController,
          BootstrapStep.startingService,
        ]));
    expect(events.last, isA<BootstrapDoneEvent>());
    expect(ssh.disconnected, isTrue);
  });

  test('password-only config provisions a dedicated key', () async {
    final ssh = _FakeSsh();
    final events = await run(ssh).toList();

    final done = events.last as BootstrapDoneEvent;
    expect(done.outcome.provisionedPrivateKeyPem, isNotNull);
    expect(done.outcome.hostKeyFingerprint, 'ssh-ed25519:fp');
    expect(ssh.executed.any((c) => c.contains('authorized_keys')), isTrue);
  });

  test('existing key skips provisioning', () async {
    final ssh = _FakeSsh();
    const withKey = SshConfig(
        host: 'h', username: 'u', privateKey: '-----BEGIN PRIVATE KEY-----');
    final events = await run(ssh, config: withKey).toList();

    final steps = events
        .whereType<BootstrapStepEvent>()
        .map((e) => e.step)
        .toList();
    expect(steps, isNot(contains(BootstrapStep.provisioningKey)));
    final done = events.last as BootstrapDoneEvent;
    expect(done.outcome.provisionedPrivateKeyPem, isNull);
  });

  test('exit 127 maps to openCodeMissing', () async {
    final ssh = _FakeSsh()
      ..executeError = (command) =>
          command == remoteOpenCodeLookupCommand()
              ? SshCommandException(command, 127, '')
              : null;

    final events = await run(ssh).toList();

    final done = events.last as BootstrapDoneEvent;
    expect(done.outcome.success, isFalse);
    expect(done.outcome.failure, BootstrapFailureKind.openCodeMissing);
    expect(ssh.disconnected, isTrue);
  });

  test('connect failure maps to sshConnectFailed', () async {
    final ssh = _FakeSsh()..connectError = Exception('refused');

    final events = await run(ssh).toList();

    final done = events.last as BootstrapDoneEvent;
    expect(done.outcome.success, isFalse);
    expect(done.outcome.failure, BootstrapFailureKind.sshConnectFailed);
  });
}
