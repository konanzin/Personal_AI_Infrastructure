/// Bootstraps OpenCode on a remote machine over SSH, reporting progress as a
/// stream of steps so the UI can show what a 30–60s setup is actually doing.
///
/// Extracted from `machines_screen.dart`; the screen now only renders the
/// events and persists the outcome (host-key fingerprint, provisioned key).
library;

import '../models/machine.dart';
import 'opencode_client.dart';
import 'ssh_key_service.dart';
import 'ssh_service.dart';

enum BootstrapStep {
  connecting,
  provisioningKey,
  installingPaiEcosystem,
  startingPulseBroker,
  locatingOpenCode,
  installingController,
  startingService,
  waitingForHttp,
}

enum BootstrapFailureKind {
  sshConnectFailed,
  openCodeMissing,
  remoteCommandFailed,
}

sealed class BootstrapEvent {
  const BootstrapEvent();
}

class BootstrapStepEvent extends BootstrapEvent {
  final BootstrapStep step;

  /// Only set for [BootstrapStep.waitingForHttp].
  final int? attempt;
  final int? maxAttempts;

  const BootstrapStepEvent(this.step, {this.attempt, this.maxAttempts});
}

class BootstrapDoneEvent extends BootstrapEvent {
  final BootstrapOutcome outcome;

  const BootstrapDoneEvent(this.outcome);
}

class BootstrapOutcome {
  final bool success;

  /// Diagnostic detail (HTTP check message, exit code text). UI maps
  /// [failure] to a user-facing string; this is supporting detail.
  final String message;
  final BootstrapFailureKind? failure;
  final int? exitCode;

  /// Captured during the SSH connection; the caller persists it as the
  /// machine identity.
  final String? hostKeyFingerprint;

  /// Set when a dedicated key was generated and installed during bootstrap.
  final String? provisionedPrivateKeyPem;

  const BootstrapOutcome({
    required this.success,
    this.message = '',
    this.failure,
    this.exitCode,
    this.hostKeyFingerprint,
    this.provisionedPrivateKeyPem,
  });
}

class MachineBootstrapService {
  final SshService Function() _sshFactory;
  final SshKeyService _keyService;

  MachineBootstrapService({
    SshService Function()? sshFactory,
    SshKeyService? keyService,
  })  : _sshFactory = sshFactory ?? SshService.new,
        _keyService = keyService ?? SshKeyService();

  /// Runs the full bootstrap. Always ends with a [BootstrapDoneEvent].
  Stream<BootstrapEvent> bootstrap({
    required SshConfig ssh,
    required String serverUrl,
    required String serverUsername,
    required String serverPassword,
    required int port,
    String? workdir,
    String keyComment = 'pai-mobile-device',
    int requestTimeoutSeconds = 30,
    int httpRetries = 10,
    Duration httpRetryDelay = const Duration(milliseconds: 750),
  }) async* {
    final sshService = _sshFactory();
    String? fingerprint;
    String? provisionedKey;
    var connected = false;

    try {
      yield const BootstrapStepEvent(BootstrapStep.connecting);
      await sshService.connect(
        host: ssh.host,
        port: ssh.port,
        username: ssh.username,
        privateKeyPem: ssh.privateKey,
        password: ssh.password,
      );
      connected = true;
      fingerprint = sshService.hostKeyFingerprint;

      // Provision a dedicated key now, while we have an authenticated
      // session, so the password never needs to be stored.
      if (ssh.privateKey == null || ssh.privateKey!.isEmpty) {
        yield const BootstrapStepEvent(BootstrapStep.provisioningKey);
        final generated = _keyService.generateEd25519(comment: keyComment);
        await sshService
            .execute(installAuthorizedKeyCommand(generated.authorizedKeysLine));
        provisionedKey = generated.privateKeyPem;
      }

      yield const BootstrapStepEvent(BootstrapStep.installingPaiEcosystem);
      await sshService.execute(installPaiEcosystemCommand());

      yield const BootstrapStepEvent(BootstrapStep.startingPulseBroker);
      await sshService.execute(startPulseBrokerCommand());

      yield const BootstrapStepEvent(BootstrapStep.locatingOpenCode);
      final opencodeBin =
          await sshService.execute(remoteOpenCodeLookupCommand());

      yield const BootstrapStepEvent(BootstrapStep.installingController);
      await sshService.execute(installPaiOpenCodeControllerCommand());

      yield const BootstrapStepEvent(BootstrapStep.startingService);
      await sshService.execute(paiOpenCodeControllerCommand(
        'start',
        opencodeBin: opencodeBin,
        password: serverPassword,
        port: port,
        workdir: workdir,
      ));

      var result = await _checkHttp(
          serverUrl, serverUsername, serverPassword, requestTimeoutSeconds);
      for (var attempt = 1;
          !result.success && attempt <= httpRetries;
          attempt++) {
        yield BootstrapStepEvent(
          BootstrapStep.waitingForHttp,
          attempt: attempt,
          maxAttempts: httpRetries,
        );
        await Future<void>.delayed(httpRetryDelay);
        result = await _checkHttp(
            serverUrl, serverUsername, serverPassword, requestTimeoutSeconds);
      }

      yield BootstrapDoneEvent(BootstrapOutcome(
        success: result.success,
        message: result.message,
        hostKeyFingerprint: fingerprint,
        provisionedPrivateKeyPem: provisionedKey,
      ));
    } on SshCommandException catch (e) {
      final missing = e.command == remoteOpenCodeLookupCommand() &&
          (e.exitCode == 127 || e.stderr.contains('opencode not found'));
      yield BootstrapDoneEvent(BootstrapOutcome(
        success: false,
        message: e.stderr,
        failure: missing
            ? BootstrapFailureKind.openCodeMissing
            : BootstrapFailureKind.remoteCommandFailed,
        exitCode: e.exitCode,
        hostKeyFingerprint: fingerprint,
        provisionedPrivateKeyPem: provisionedKey,
      ));
    } catch (e) {
      yield BootstrapDoneEvent(BootstrapOutcome(
        success: false,
        message: e.toString(),
        failure: connected
            ? BootstrapFailureKind.remoteCommandFailed
            : BootstrapFailureKind.sshConnectFailed,
        hostKeyFingerprint: fingerprint,
        provisionedPrivateKeyPem: provisionedKey,
      ));
    } finally {
      sshService.disconnect();
    }
  }

  /// Updates the PAI setup on an already-provisioned machine — equivalent to
  /// running `opencode/install.sh --update --no-tts-bootstrap` on the server.
  /// Reuses the idempotent ecosystem command, which fetches the latest repo and
  /// runs the installer in update mode (a backup is taken server-side by the
  /// installer).
  ///
  /// Does not restart the OpenCode service: matching `--update` semantics, it
  /// refreshes files on disk; a reconnect/restart is what loads new plugin code.
  /// Always ends with a [BootstrapDoneEvent].
  Stream<BootstrapEvent> updatePai({required SshConfig ssh}) async* {
    final sshService = _sshFactory();
    String? fingerprint;
    var connected = false;

    try {
      yield const BootstrapStepEvent(BootstrapStep.connecting);
      await sshService.connect(
        host: ssh.host,
        port: ssh.port,
        username: ssh.username,
        privateKeyPem: ssh.privateKey,
        password: ssh.password,
        expectedHostKeyFingerprint: ssh.hostKeyFingerprint,
      );
      connected = true;
      fingerprint = sshService.hostKeyFingerprint;

      yield const BootstrapStepEvent(BootstrapStep.installingPaiEcosystem);
      final output = await sshService.execute(installPaiEcosystemCommand());

      yield BootstrapDoneEvent(BootstrapOutcome(
        success: true,
        message: output,
        hostKeyFingerprint: fingerprint,
      ));
    } on SshCommandException catch (e) {
      yield BootstrapDoneEvent(BootstrapOutcome(
        success: false,
        message: e.stderr,
        failure: BootstrapFailureKind.remoteCommandFailed,
        exitCode: e.exitCode,
        hostKeyFingerprint: fingerprint,
      ));
    } catch (e) {
      yield BootstrapDoneEvent(BootstrapOutcome(
        success: false,
        message: e.toString(),
        failure: connected
            ? BootstrapFailureKind.remoteCommandFailed
            : BootstrapFailureKind.sshConnectFailed,
        hostKeyFingerprint: fingerprint,
      ));
    } finally {
      sshService.disconnect();
    }
  }

  Future<ConnectionCheckResult> _checkHttp(
    String baseUrl,
    String username,
    String password,
    int timeoutSeconds,
  ) {
    final client = OpenCodeClient(ClientConfig(
      baseUrl: baseUrl,
      username: username,
      password: password,
      requestTimeoutSeconds: timeoutSeconds,
    ));
    return client.checkConnection().whenComplete(client.close);
  }
}
