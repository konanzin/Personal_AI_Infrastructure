import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/workspace.dart';

/// Manages recent and favorite workspaces per machine.
///
/// Persistence keys are scoped by machineId to avoid cross-machine pollution.
class WorkspaceProvider extends ChangeNotifier {
  static const _maxRecent = 20;

  final Map<String, List<Workspace>> _recentsByMachine = {};
  final Map<String, Set<String>> _favoritesByMachine = {};
  bool _loaded = false;

  List<Workspace> getRecents(String machineId) {
    return List.unmodifiable(_recentsByMachine[machineId] ?? []);
  }

  List<Workspace> getFavorites(String machineId) {
    final recents = _recentsByMachine[machineId] ?? [];
    final favPaths = _favoritesByMachine[machineId] ?? {};
    return recents
        .where((w) => favPaths.contains(w.path))
        .map((w) => w.copyWith(isFavorite: true))
        .toList();
  }

  Future<void> loadForMachine(String machineId) async {
    if (_loaded && _recentsByMachine.containsKey(machineId)) return;
    final prefs = await SharedPreferences.getInstance();

    final recentJson = prefs.getString('workspaces_${machineId}_recent');
    if (recentJson != null) {
      final list = jsonDecode(recentJson) as List<dynamic>;
      _recentsByMachine[machineId] = list
          .map((e) => Workspace.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    final favJson = prefs.getStringList('workspaces_${machineId}_favorites');
    if (favJson != null) {
      _favoritesByMachine[machineId] = favJson.toSet();
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> addRecent(String machineId, Workspace workspace) async {
    final list = _recentsByMachine.putIfAbsent(machineId, () => []);
    list.removeWhere((w) => w.path == workspace.path);
    list.insert(0, workspace.copyWith(lastUsed: DateTime.now()));
    if (list.length > _maxRecent) {
      list.removeRange(_maxRecent, list.length);
    }
    await _persistRecents(machineId);
    notifyListeners();
  }

  Future<void> toggleFavorite(String machineId, String path) async {
    final favs = _favoritesByMachine.putIfAbsent(machineId, () => {});
    if (favs.contains(path)) {
      favs.remove(path);
    } else {
      favs.add(path);
    }
    await _persistFavorites(machineId);
    notifyListeners();
  }

  bool isFavorite(String machineId, String path) {
    return _favoritesByMachine[machineId]?.contains(path) ?? false;
  }

  Future<void> _persistRecents(String machineId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _recentsByMachine[machineId] ?? [];
    final json = jsonEncode(list.map((w) => w.toJson()).toList());
    await prefs.setString('workspaces_${machineId}_recent', json);
  }

  Future<void> _persistFavorites(String machineId) async {
    final prefs = await SharedPreferences.getInstance();
    final favs = _favoritesByMachine[machineId]?.toList() ?? [];
    await prefs.setStringList('workspaces_${machineId}_favorites', favs);
  }
}
