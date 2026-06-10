import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/machine.dart';
import '../services/secure_storage.dart';

/// Manages the list of configured machines and the active machine.
///
/// Handles migration from legacy single-machine credentials, CRUD operations,
/// and active machine selection. ClientProvider depends on this via ProxyProvider.
class MachineStore extends ChangeNotifier {
  static const _storageKey = 'machines_json';
  static const _activeKey = 'active_machine_id';
  static const _migratedKey = 'machines_migrated';

  List<Machine> _machines = [];
  String? _activeMachineId;

  List<Machine> get machines => List.unmodifiable(_machines);
  String? get activeMachineId => _activeMachineId;

  Machine? get activeMachine {
    for (final m in _machines) {
      if (m.id == _activeMachineId) return m;
    }
    return null;
  }

  Future<void> initialize() async {
    final migrated = await SecureStorageService.read(_migratedKey);
    if (migrated == 'true') {
      await _loadFromSecureStorage();
    } else {
      await _migrateFromLegacy();
    }

    // Migrate defaultDirectory from SharedPreferences if needed
    await _migrateDefaultDirectory();

    notifyListeners();
  }

  // ── CRUD ──────────────────────────────────────────────────────────────

  Future<void> addMachine(Machine machine) async {
    _machines.add(machine);
    if (_machines.length == 1) {
      _activeMachineId = machine.id;
    }
    await _saveToSecureStorage();
    notifyListeners();
  }

  Future<void> updateActiveMachine(Machine updated) async {
    final idx = _machines.indexWhere((m) => m.id == updated.id);
    if (idx >= 0) {
      _machines[idx] = updated;
    } else {
      _machines.add(updated);
      _activeMachineId = updated.id;
    }
    await _saveToSecureStorage();
    notifyListeners();
  }

  Future<void> deleteMachine(String id) async {
    _machines.removeWhere((m) => m.id == id);
    if (_activeMachineId == id) {
      _activeMachineId = _machines.isNotEmpty ? _machines.first.id : null;
    }
    await _saveToSecureStorage();
    notifyListeners();
  }

  Future<void> switchMachine(String id) async {
    if (_activeMachineId == id) return;
    _activeMachineId = id;
    await SecureStorageService.write(_activeKey, id);
    notifyListeners();
  }

  // ── Private ───────────────────────────────────────────────────────────

  Future<void> _loadFromSecureStorage() async {
    final json = await SecureStorageService.read(_storageKey);
    final activeId = await SecureStorageService.read(_activeKey);

    if (json != null) {
      final list = jsonDecode(json) as List<dynamic>;
      _machines =
          list.map((e) => Machine.fromJson(e as Map<String, dynamic>)).toList();
    }

    if (activeId != null) {
      _activeMachineId = activeId;
    } else if (_machines.isNotEmpty) {
      _activeMachineId = _machines.first.id;
    }
  }

  Future<void> _migrateFromLegacy() async {
    final credentials = await SecureStorageService.loadCredentials();
    final serverUrl = credentials['serverUrl'];
    final username = credentials['username'];
    final password = credentials['password'];

    if (serverUrl != null && username != null && password != null) {
      final machine = Machine(
        id: 'default',
        name: 'Default',
        serverUrl: serverUrl,
        username: username,
        password: password,
      );
      _machines = [machine];
      _activeMachineId = machine.id;
    }

    await _saveToSecureStorage();
    await SecureStorageService.write(_migratedKey, 'true');
  }

  /// Migrates defaultDirectory from SharedPreferences to Machine.defaultDirectory.
  Future<void> _migrateDefaultDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultDir = prefs.getString('default_directory');
    if (defaultDir == null) return;

    final machine = activeMachine;
    if (machine != null && machine.defaultDirectory == null) {
      final idx = _machines.indexWhere((m) => m.id == machine.id);
      if (idx >= 0) {
        _machines[idx] = machine.copyWith(defaultDirectory: defaultDir);
        await _saveToSecureStorage();
      }
    }
    await prefs.remove('default_directory');
  }

  Future<void> _saveToSecureStorage() async {
    final json = jsonEncode(_machines.map((m) => m.toJson()).toList());
    await SecureStorageService.write(_storageKey, json);
    if (_activeMachineId != null) {
      await SecureStorageService.write(_activeKey, _activeMachineId!);
    }
  }
}
