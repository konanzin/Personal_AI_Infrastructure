import 'package:local_auth/local_auth.dart';

import 'secure_storage.dart';

/// Result of an SSH authorization attempt.
enum SshGateOutcome {
  /// User authenticated; SSH use may proceed.
  authorized,

  /// Authentication failed but the budget is not exhausted yet.
  failed,

  /// Budget exhausted (3 failures) — the caller must wipe the SSH config.
  wiped,

  /// Device has no screen lock / biometric enrolled. SSH use is blocked until
  /// the user sets one up (app requirement).
  unavailable,
}

class SshGateResult {
  final SshGateOutcome outcome;

  /// Attempts left before the wipe (only meaningful for [SshGateOutcome.failed]).
  final int attemptsRemaining;

  const SshGateResult(this.outcome, {this.attemptsRemaining = 0});
}

/// Gates every use of a stored SSH credential behind the phone's own
/// authenticator (biometric or device PIN/pattern/password). After
/// [maxFailures] consecutive failures the credential must be wiped, so a
/// stolen phone can't be brute-forced into a working SSH session.
class SshGateService {
  static const int maxFailures = 3;

  /// After a successful authentication, SSH stays unlocked for this window so
  /// quick reconnects and background reads (git status) don't re-prompt.
  static const Duration unlockWindow = Duration(minutes: 5);

  /// In-memory only: cleared on app kill, never persisted.
  static final Map<String, DateTime> _unlockedUntil = {};

  final LocalAuthentication _localAuth;

  SshGateService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  static String _counterKey(String machineId) => 'ssh_gate_fails_$machineId';

  /// Whether SSH is currently unlocked for [machineId] (within the window).
  /// Background SSH use (git status) should check this and skip silently when
  /// false, rather than triggering an unexpected prompt.
  static bool isUnlocked(String machineId) {
    final until = _unlockedUntil[machineId];
    return until != null && until.isAfter(DateTime.now());
  }

  /// Drops any active unlock (e.g. on logout/lock).
  static void lock(String machineId) => _unlockedUntil.remove(machineId);

  /// Current consecutive-failure count for [machineId].
  static Future<int> failureCount(String machineId) async {
    final raw = await SecureStorageService.read(_counterKey(machineId));
    return int.tryParse(raw ?? '0') ?? 0;
  }

  /// Clears the failure counter (e.g. after re-provisioning).
  static Future<void> reset(String machineId) =>
      SecureStorageService.delete(_counterKey(machineId));

  Future<SshGateResult> authorize({required String machineId}) async {
    // Still within the grace window — no prompt needed.
    if (isUnlocked(machineId)) {
      return const SshGateResult(SshGateOutcome.authorized);
    }

    bool supported;
    try {
      supported = await _localAuth.isDeviceSupported();
    } catch (_) {
      supported = false;
    }
    if (!supported) {
      return const SshGateResult(SshGateOutcome.unavailable);
    }

    final prior = await failureCount(machineId);
    // Increment BEFORE the prompt: a force-kill mid-prompt then must not be
    // able to reset the budget by relaunching the app.
    final attempt = prior + 1;
    await SecureStorageService.write(_counterKey(machineId), '$attempt');

    bool ok;
    try {
      ok = await _localAuth.authenticate(
        localizedReason: 'Authenticate to use SSH for this machine',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      ok = false;
    }

    if (ok) {
      await SecureStorageService.delete(_counterKey(machineId));
      _unlockedUntil[machineId] = DateTime.now().add(unlockWindow);
      return const SshGateResult(SshGateOutcome.authorized);
    }

    if (attempt >= maxFailures) {
      await SecureStorageService.delete(_counterKey(machineId));
      return const SshGateResult(SshGateOutcome.wiped);
    }
    return SshGateResult(
      SshGateOutcome.failed,
      attemptsRemaining: maxFailures - attempt,
    );
  }
}
