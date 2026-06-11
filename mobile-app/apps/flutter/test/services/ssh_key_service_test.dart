import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/services/ssh_key_service.dart';

void main() {
  final service = SshKeyService();

  group('SshKeyService.generateEd25519', () {
    test('produces a private PEM that dartssh2 can load back', () {
      final key = service.generateEd25519();
      // Round-trip: the PEM we emit must parse as a usable keypair, otherwise
      // SSH auth would fail at connect time.
      final loaded = SSHKeyPair.fromPem(key.privateKeyPem);
      expect(loaded, hasLength(1));
      // The loaded key must be able to sign (exercises the private bytes).
      expect(loaded.first.toPublicKey().encode(), isNotEmpty);
    });

    test('emits a well-formed authorized_keys line with the comment', () {
      final key = service.generateEd25519(comment: 'pai-mobile-test');
      final parts = key.authorizedKeysLine.split(' ');
      expect(parts, hasLength(3));
      expect(parts[0], 'ssh-ed25519');
      expect(parts[1], startsWith('AAAAC3NzaC1lZDI1NTE5')); // ssh-ed25519 prefix
      expect(parts[2], 'pai-mobile-test');
    });

    test('generates a distinct key each call', () {
      final a = service.generateEd25519();
      final b = service.generateEd25519();
      expect(a.privateKeyPem, isNot(b.privateKeyPem));
      expect(a.authorizedKeysLine, isNot(b.authorizedKeysLine));
    });

    test('public line matches the loaded private key', () {
      final key = service.generateEd25519();
      final loaded = SSHKeyPair.fromPem(key.privateKeyPem).first;
      final wire = loaded.toPublicKey().encode();
      // The base64 blob in the authorized_keys line is exactly the wire
      // encoding of the public key.
      final blob = key.authorizedKeysLine.split(' ')[1];
      expect(blob, base64.encode(wire));
    });
  });
}
