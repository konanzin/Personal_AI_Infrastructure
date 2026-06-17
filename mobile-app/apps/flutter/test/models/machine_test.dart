import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/models/machine.dart';

void main() {
  group('stableMachineId', () {
    test('is deterministic for the same host key', () {
      final a = stableMachineId('ssh-ed25519:aabbcc');
      final b = stableMachineId('ssh-ed25519:aabbcc');
      expect(a, b);
      expect(a, startsWith('mach_'));
      expect(a.length, 'mach_'.length + 20);
    });

    test('differs for different host keys', () {
      expect(stableMachineId('ssh-ed25519:aabbcc'),
          isNot(stableMachineId('ssh-ed25519:ddeeff')));
    });
  });

  group('SshConfig', () {
    test('round-trips hostKeyFingerprint through JSON', () {
      const config = SshConfig(
        host: 'h',
        username: 'u',
        password: 'pw',
        hostKeyFingerprint: 'ssh-ed25519:aabbcc',
      );
      final restored = SshConfig.fromJson(config.toJson());
      expect(restored.hostKeyFingerprint, 'ssh-ed25519:aabbcc');
    });

    test('tolerates configs persisted before pinning existed', () {
      final restored = SshConfig.fromJson({
        'host': 'h',
        'port': 22,
        'username': 'u',
        'password': 'pw',
      });
      expect(restored.hostKeyFingerprint, isNull);
    });
  });

  group('Machine', () {
    test('copyWith(ssh: null) clears the SSH config', () {
      const machine = Machine(
        id: 'm1',
        name: 'n',
        serverUrl: 'http://h:4096',
        username: 'u',
        password: 'p',
        ssh: SshConfig(host: 'h', username: 'u', password: 'pw'),
      );
      expect(machine.ssh, isNotNull);
      final cleared = machine.copyWith(ssh: null);
      expect(cleared.ssh, isNull);
      // Other fields survive the clear.
      expect(cleared.serverUrl, 'http://h:4096');
    });

    test('copyWith without ssh keeps the existing SSH config', () {
      const machine = Machine(
        id: 'm1',
        name: 'n',
        serverUrl: 'http://h:4096',
        username: 'u',
        password: 'p',
        ssh: SshConfig(host: 'h', username: 'u', password: 'pw'),
      );
      final renamed = machine.copyWith(name: 'n2');
      expect(renamed.ssh, isNotNull);
      expect(renamed.name, 'n2');
    });

    test('round-trips classifier fields through JSON', () {
      const machine = Machine(
        id: 'm1',
        name: 'n',
        serverUrl: 'http://h:4096',
        username: 'u',
        password: 'p',
        classifierModel: 'openai/gpt-5.5',
        classifierUseLlm: false,
      );
      final restored = Machine.fromJson(machine.toJson());
      expect(restored.classifierModel, 'openai/gpt-5.5');
      expect(restored.classifierUseLlm, false);
    });

    test('omits classifier fields from JSON when null', () {
      const machine = Machine(
        id: 'm1',
        name: 'n',
        serverUrl: 'http://h:4096',
        username: 'u',
        password: 'p',
      );
      final json = machine.toJson();
      expect(json.containsKey('classifierModel'), isFalse);
      expect(json.containsKey('classifierUseLlm'), isFalse);
    });

    test('copyWith(classifierModel: null) clears the value', () {
      const machine = Machine(
        id: 'm1',
        name: 'n',
        serverUrl: 'http://h:4096',
        username: 'u',
        password: 'p',
        classifierModel: 'openai/gpt-5.5',
        classifierUseLlm: true,
      );
      final cleared = machine.copyWith(classifierModel: null);
      expect(cleared.classifierModel, isNull);
      // Untouched field survives.
      expect(cleared.classifierUseLlm, true);
    });

    test('tolerates legacy JSON without classifier fields', () {
      final machine = Machine.fromJson({
        'id': 'm1',
        'name': 'n',
        'serverUrl': 'http://h:4096',
        'username': 'u',
        'password': 'p',
      });
      expect(machine.classifierModel, isNull);
      expect(machine.classifierUseLlm, isNull);
    });

    test('ignores legacy paiAgentUrl in persisted JSON', () {
      final machine = Machine.fromJson({
        'id': 'm1',
        'name': 'n',
        'serverUrl': 'http://h:4096',
        'username': 'u',
        'password': 'p',
        'paiAgentUrl': 'http://h:8080',
      });
      expect(machine.id, 'm1');
      expect(machine.toJson().containsKey('paiAgentUrl'), isFalse);
    });
  });
}
