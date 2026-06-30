import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/services/ssh_service.dart';

void main() {
  group('remoteOpenCodeLookupCommand', () {
    test('checks command lookup and known install paths without exporting PATH',
        () {
      final command = remoteOpenCodeLookupCommand();

      expect(command, startsWith('sh -lc '));
      expect(command, isNot(contains('export PATH=')));
      expect(command, contains('command -v opencode'));
      expect(command, contains(r'$HOME/.opencode/bin'));
      expect(command, contains(r'$HOME/.local/bin'));
      expect(command, contains(r'$HOME/.bun/bin'));
    });
  });

  group('PAI ecosystem bootstrap commands', () {
    test('installs or updates the remote PAI ecosystem', () {
      final command = installPaiEcosystemCommand();

      expect(command, startsWith('sh -lc '));
      expect(command, contains(paiDefaultRepositoryUrl));
      expect(command, contains(paiDefaultRepositoryBranch));
      expect(command, contains('PAI-opencode'));
      expect(
          command, isNot(contains(r'repo_branch="${PAI_REPO_BRANCH:-main}"')));
      expect(command, isNot(contains(r'$HOME/Personal_AI_Infrastructure')));
      expect(command,
          contains(r'${repo_branch}:refs/remotes/origin/${repo_branch}'));
      expect(command, contains('opencode/install.sh'));
      expect(command, contains('--update'));
      expect(command, contains('--no-tts-bootstrap'));
      expect(command, contains('pulse-broker.ts'));
      expect(command, contains('apt-get install'));
    });

    test('starts Pulse Broker and verifies health', () {
      final command = startPulseBrokerCommand();

      expect(command, startsWith('sh -lc '));
      expect(command, contains('pulse-broker.service'));
      expect(command, contains('pulse-broker.ts'));
      expect(command, contains(r'http://127.0.0.1:$port/health'));
      expect(command, contains('systemctl --user enable --now'));
      expect(command, contains('setsid'));
    });
  });

  group('OpenCode controller script', () {
    test('installs lifecycle controller script', () {
      final command = installPaiOpenCodeControllerCommand();

      expect(command, contains(r'$HOME/.local/bin/pai-opencode'));
      expect(command, contains('chmod 700'));
      expect(command, contains('start|stop|restart|status'));
    });

    test('prefers systemd user service supervision', () {
      expect(paiOpenCodeControllerScript, contains('systemctl --user'));
      expect(paiOpenCodeControllerScript, contains('Restart=always'));
      expect(paiOpenCodeControllerScript, contains('EnvironmentFile='));
      expect(paiOpenCodeControllerScript, contains('WantedBy=default.target'));
      expect(paiOpenCodeControllerScript, contains('enable-linger'));
      expect(paiOpenCodeControllerScript, contains('journalctl --user'));
    });

    test('never binds to all interfaces by default', () {
      expect(paiOpenCodeControllerScript, isNot(contains('0.0.0.0')));
      // Bind resolution order: explicit > SSH connection address > tailscale
      // IP > loopback.
      expect(paiOpenCodeControllerScript, contains(r'${SSH_CONNECTION:-}'));
      expect(paiOpenCodeControllerScript, contains('tailscale ip -4'));
      expect(paiOpenCodeControllerScript, contains('host="127.0.0.1"'));
    });

    test('builds start command with scoped environment', () {
      final command = paiOpenCodeControllerCommand(
        'start',
        opencodeBin: '/home/user/.opencode/bin/opencode',
        password: "pa'i",
        port: 4096,
        workdir: '/repo',
      );

      expect(command,
          contains("OPENCODE_BIN='/home/user/.opencode/bin/opencode'"));
      expect(command, contains(r"OPENCODE_PASSWORD='pa'\''i'"));
      expect(command, contains("OPENCODE_PORT='4096'"));
      expect(command, contains("OPENCODE_WORKDIR='/repo'"));
      expect(command, contains(r'$HOME/.local/bin/pai-opencode'));
      expect(command, endsWith("'start'"));
    });
  });

  group('formatHostKeyFingerprint', () {
    test('formats type and hex digest', () {
      final fingerprint = Uint8List.fromList([0x00, 0x1a, 0xff, 0x42]);
      expect(formatHostKeyFingerprint('ssh-ed25519', fingerprint),
          'ssh-ed25519:001aff42');
    });
  });
}
