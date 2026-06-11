import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/models/machine.dart';
import 'package:pai_mobile_flutter/providers/client_provider.dart';

void main() {
  Machine machine(
    String id, {
    String serverUrl = 'http://100.64.0.1:4096',
    int timeoutSeconds = 30,
  }) =>
      Machine(
        id: id,
        name: 'Machine $id',
        serverUrl: serverUrl,
        username: 'user',
        password: 'pass',
        requestTimeoutSeconds: timeoutSeconds,
      );

  test('initializeFromMachine builds a client for a private URL', () {
    final provider = ClientProvider();
    provider.initializeFromMachine(machine('1'));

    expect(provider.isConfigured, isTrue);
    expect(provider.client, isNotNull);
    provider.dispose();
  });

  test('refuses to build a client for plain http to a public host', () {
    final provider = ClientProvider();
    provider.initializeFromMachine(
        machine('1', serverUrl: 'http://example.com:4096'));

    expect(provider.isConfigured, isFalse);
    expect(provider.client, isNull);
    provider.dispose();
  });

  test('unchanged machine does not rebuild the client', () {
    final provider = ClientProvider();
    provider.initializeFromMachine(machine('1'));
    final first = provider.client;

    provider.initializeFromMachine(machine('1'));

    expect(identical(provider.client, first), isTrue);
    provider.dispose();
  });

  test('switching machines rebuilds the client', () {
    final provider = ClientProvider();
    provider.initializeFromMachine(machine('1'));
    final first = provider.client;

    provider.initializeFromMachine(
        machine('2', serverUrl: 'http://100.64.0.2:4096'));

    expect(provider.client, isNotNull);
    expect(identical(provider.client, first), isFalse);
    provider.dispose();
  });

  test('updateTimeout rebuilds the client with the new timeout', () {
    final provider = ClientProvider();
    provider.initializeFromMachine(machine('1', timeoutSeconds: 30));
    final first = provider.client;

    provider.updateTimeout(60);

    expect(provider.client, isNotNull);
    expect(identical(provider.client, first), isFalse);
    expect(provider.client!.config.requestTimeoutSeconds, 60);
    provider.dispose();
  });

  test('same timeout does not rebuild', () {
    final provider = ClientProvider();
    provider.initializeFromMachine(machine('1', timeoutSeconds: 30));
    final first = provider.client;

    provider.updateTimeout(30);

    expect(identical(provider.client, first), isTrue);
    provider.dispose();
  });
}
