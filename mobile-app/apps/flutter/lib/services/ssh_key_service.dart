import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;

/// A freshly generated SSH keypair, ready to be stored (private PEM) and
/// installed on a server (public authorized_keys line).
class GeneratedSshKey {
  /// OpenSSH-format private key PEM, loadable via [SSHKeyPair.fromPem].
  final String privateKeyPem;

  /// Single-line public key in `authorized_keys` format
  /// (`ssh-ed25519 AAAA... comment`).
  final String authorizedKeysLine;

  const GeneratedSshKey({
    required this.privateKeyPem,
    required this.authorizedKeysLine,
  });
}

/// Generates SSH keypairs on-device so the private key never leaves the phone.
///
/// We reuse dartssh2's own `OpenSSHEd25519KeyPair.toPem()` / public-key
/// encoding for serialization (the OpenSSH container format is fiddly to hand
/// roll), and only use pinenacl — already a transitive dependency of dartssh2 —
/// to produce the raw ed25519 key material.
class SshKeyService {
  /// Generates a new ed25519 keypair. [comment] is appended to the
  /// authorized_keys line so the key is identifiable and revocable on the
  /// server.
  GeneratedSshKey generateEd25519({String comment = 'pai-mobile'}) {
    final signingKey = ed25519.SigningKey.generate();
    // pinenacl stores the secret as seed(32) ++ public(32) == 64 bytes, which
    // is exactly what dartssh2's OpenSSHEd25519KeyPair.sign expects.
    final privateKey = Uint8List.fromList(signingKey.toUint8List());
    final publicKey = Uint8List.fromList(signingKey.verifyKey.toUint8List());

    final keyPair = OpenSSHEd25519KeyPair(publicKey, privateKey, comment);

    final pem = keyPair.toPem();
    final wireBlob = keyPair.toPublicKey().encode();
    final line = 'ssh-ed25519 ${base64.encode(wireBlob)} $comment';

    return GeneratedSshKey(privateKeyPem: pem, authorizedKeysLine: line);
  }
}
