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

  group('OpenCode controller commands', () {
    test('installs lifecycle controller script', () {
      final command = installPaiOpenCodeControllerCommand();

      expect(command, contains(r'$HOME/.local/bin/pai-opencode'));
      expect(command, contains('chmod 700'));
      expect(command, contains('start|stop|restart|status'));
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
}
