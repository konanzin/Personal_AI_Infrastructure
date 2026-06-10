import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../services/secure_storage.dart';

enum LockTimeout {
  immediate(Duration.zero, 'Immediately'),
  oneMinute(Duration(minutes: 1), '1 minute'),
  fiveMinutes(Duration(minutes: 5), '5 minutes'),
  never(Duration(days: 365), 'Never');

  final Duration duration;
  final String label;
  const LockTimeout(this.duration, this.label);
}

class AppLockProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const _lockEnabledKey = 'app_lock_enabled';
  static const _lockTimeoutKey = 'app_lock_timeout';

  // Legacy app-PIN keys. They are deleted during initialization because app
  // lock now uses only the platform authenticator.
  static const _legacyPinHashKey = 'app_lock_pin_hash';
  static const _legacyPinSaltKey = 'app_lock_pin_salt';
  static const _legacyPinLengthKey = 'app_lock_pin_length';
  static const _legacyBiometricEnabledKey = 'app_lock_biometric';

  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isLocked = false;
  bool _lockEnabled = false;
  bool _deviceAuthAvailable = false;
  bool _biometricAvailable = false;
  LockTimeout _lockTimeout = LockTimeout.immediate;
  DateTime? _backgroundedAt;

  bool get isLocked => _isLocked;
  bool get lockEnabled => _lockEnabled;
  bool get deviceAuthAvailable => _deviceAuthAvailable;
  bool get biometricAvailable => _biometricAvailable;
  LockTimeout get lockTimeout => _lockTimeout;

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);

    await _clearLegacyAppPin();

    _lockEnabled = await SecureStorageService.read(_lockEnabledKey) == 'true';

    final timeoutStr = await SecureStorageService.read(_lockTimeoutKey);
    if (timeoutStr != null) {
      _lockTimeout = LockTimeout.values.firstWhere(
        (t) => t.name == timeoutStr,
        orElse: () => LockTimeout.immediate,
      );
    }

    try {
      _deviceAuthAvailable = await _localAuth.isDeviceSupported();
      _biometricAvailable = await _localAuth.canCheckBiometrics;
    } catch (_) {
      _deviceAuthAvailable = false;
      _biometricAvailable = false;
    }

    if (_lockEnabled && !_deviceAuthAvailable) {
      _lockEnabled = false;
      await SecureStorageService.write(_lockEnabledKey, 'false');
    }

    if (_lockEnabled) {
      _isLocked = true;
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_lockEnabled) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_backgroundedAt != null) {
        final elapsed = DateTime.now().difference(_backgroundedAt!);
        if (elapsed >= _lockTimeout.duration) {
          _isLocked = true;
          notifyListeners();
        }
      }
      _backgroundedAt = null;
    }
  }

  Future<bool> authenticate() async {
    if (!_deviceAuthAvailable) return false;
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Unlock PAI',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (ok) {
        _isLocked = false;
        notifyListeners();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> setLockEnabled(bool value) async {
    _lockEnabled = value;
    await SecureStorageService.write(_lockEnabledKey, value.toString());
    _isLocked = value;
    notifyListeners();
  }

  Future<void> setLockTimeout(LockTimeout timeout) async {
    _lockTimeout = timeout;
    await SecureStorageService.write(_lockTimeoutKey, timeout.name);
    notifyListeners();
  }

  Future<void> _clearLegacyAppPin() async {
    await SecureStorageService.delete(_legacyPinHashKey);
    await SecureStorageService.delete(_legacyPinSaltKey);
    await SecureStorageService.delete(_legacyPinLengthKey);
    await SecureStorageService.delete(_legacyBiometricEnabledKey);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
