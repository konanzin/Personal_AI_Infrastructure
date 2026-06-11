import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/models/machine.dart';
import 'package:pai_mobile_flutter/providers/machine_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> storage;

  setUp(() {
    storage = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>();
      switch (call.method) {
        case 'read':
          return storage[args!['key'] as String];
        case 'write':
          storage[args!['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          storage.remove(args!['key'] as String);
          return null;
        case 'readAll':
          return Map<String, String>.from(storage);
        case 'deleteAll':
          storage.clear();
          return null;
        case 'containsKey':
          return storage.containsKey(args!['key'] as String);
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Machine machine(String id, {SshConfig? ssh}) => Machine(
        id: id,
        name: 'Machine $id',
        serverUrl: 'http://100.64.0.$id:4096',
        username: 'user',
        password: 'pass',
        ssh: ssh,
      );

  test('first added machine becomes active', () async {
    final store = MachineStore();
    await store.addMachine(machine('1'));
    await store.addMachine(machine('2'));

    expect(store.activeMachineId, '1');
    expect(store.machines.length, 2);
  });

  test('persisted machines and active id survive a reload', () async {
    final store = MachineStore();
    await store.initialize();
    await store.addMachine(machine('1'));
    await store.addMachine(machine('2'));
    await store.switchMachine('2');

    final reloaded = MachineStore();
    await reloaded.initialize();

    expect(reloaded.machines.length, 2);
    expect(reloaded.activeMachineId, '2');
    expect(reloaded.activeMachine?.serverUrl, 'http://100.64.0.2:4096');
  });

  test('legacy single-machine credentials migrate to a default machine',
      () async {
    storage['server_url'] = 'http://100.64.0.9:4096';
    storage['username'] = 'legacy-user';
    storage['password'] = 'legacy-pass';

    final store = MachineStore();
    await store.initialize();

    expect(store.machines.length, 1);
    expect(store.activeMachine?.id, 'default');
    expect(store.activeMachine?.username, 'legacy-user');
    expect(storage['machines_migrated'], 'true');
  });

  test('lost migrated flag does not wipe an existing machine list', () async {
    // machines_json exists but the migrated flag was lost.
    storage['machines_json'] = jsonEncode([machine('1').toJson()]);

    final store = MachineStore();
    await store.initialize();

    expect(store.machines.length, 1);
    expect(store.machines.single.id, '1');
    // Flag restored so future initializations skip legacy migration.
    expect(storage['machines_migrated'], 'true');
  });

  test('deleteMachine reassigns the active machine', () async {
    final store = MachineStore();
    await store.addMachine(machine('1'));
    await store.addMachine(machine('2'));
    expect(store.activeMachineId, '1');

    await store.deleteMachine('1');

    expect(store.machines.length, 1);
    expect(store.activeMachineId, '2');
  });

  test('deleting the last machine leaves no active machine', () async {
    final store = MachineStore();
    await store.addMachine(machine('1'));
    await store.deleteMachine('1');

    expect(store.machines, isEmpty);
    expect(store.activeMachineId, isNull);
    expect(store.activeMachine, isNull);
  });

  test('clearSshConfig strips SSH but keeps runtime credentials', () async {
    final store = MachineStore();
    await store.addMachine(machine('1',
        ssh: const SshConfig(host: 'h', username: 'u', password: 'pw')));

    await store.clearSshConfig('1');

    final m = store.machines.single;
    expect(m.ssh, isNull);
    expect(m.username, 'user');
    expect(m.password, 'pass');

    // The stripped config is what gets persisted.
    final reloaded = MachineStore();
    await reloaded.initialize();
    expect(reloaded.machines.single.ssh, isNull);
  });

  test('defaultDirectory migrates from SharedPreferences once', () async {
    SharedPreferences.setMockInitialValues(
        {'default_directory': '/home/user/work'});
    storage['machines_json'] = jsonEncode([machine('1').toJson()]);
    storage['machines_migrated'] = 'true';
    storage['active_machine_id'] = '1';

    final store = MachineStore();
    await store.initialize();

    expect(store.activeMachine?.defaultDirectory, '/home/user/work');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('default_directory'), isNull);
  });
}
