import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/services/network_policy.dart';

void main() {
  group('isPrivateHost', () {
    test('accepts loopback and localhost', () {
      expect(isPrivateHost('localhost'), isTrue);
      expect(isPrivateHost('127.0.0.1'), isTrue);
      expect(isPrivateHost('::1'), isTrue);
    });

    test('accepts RFC1918 ranges', () {
      expect(isPrivateHost('10.0.0.5'), isTrue);
      expect(isPrivateHost('192.168.1.20'), isTrue);
      expect(isPrivateHost('172.16.0.1'), isTrue);
      expect(isPrivateHost('172.31.255.255'), isTrue);
      expect(isPrivateHost('172.32.0.1'), isFalse);
    });

    test('accepts CGNAT/Tailscale 100.64/10', () {
      expect(isPrivateHost('100.64.0.1'), isTrue);
      expect(isPrivateHost('100.101.102.103'), isTrue);
      expect(isPrivateHost('100.127.255.254'), isTrue);
      expect(isPrivateHost('100.63.0.1'), isFalse);
      expect(isPrivateHost('100.128.0.1'), isFalse);
    });

    test('accepts private-mesh hostnames', () {
      expect(isPrivateHost('machine.tail1234.ts.net'), isTrue);
      expect(isPrivateHost('server.local'), isTrue);
      expect(isPrivateHost('myhost'), isTrue); // MagicDNS short name
    });

    test('rejects public hosts', () {
      expect(isPrivateHost('example.com'), isFalse);
      expect(isPrivateHost('8.8.8.8'), isFalse);
      expect(isPrivateHost('1.1.1.1'), isFalse);
    });

    test('handles private IPv6', () {
      expect(isPrivateHost('fd7a:115c:a1e0::1'), isTrue);
      expect(isPrivateHost('fe80::1'), isTrue);
      expect(isPrivateHost('2001:4860:4860::8888'), isFalse);
    });
  });

  group('cleartextViolation', () {
    test('allows http to private hosts', () {
      expect(cleartextViolation('http://100.64.0.1:4096'), isNull);
      expect(cleartextViolation('http://localhost:4096'), isNull);
      expect(cleartextViolation('http://machine.tail1234.ts.net:4096'), isNull);
    });

    test('blocks http to public hosts', () {
      expect(cleartextViolation('http://example.com:4096'), isNotNull);
      expect(cleartextViolation('http://8.8.8.8'), isNotNull);
    });

    test('allows https anywhere', () {
      expect(cleartextViolation('https://example.com'), isNull);
    });

    test('blocks ws but not wss to public hosts', () {
      expect(cleartextViolation('ws://example.com/pty'), isNotNull);
      expect(cleartextViolation('wss://example.com/pty'), isNull);
    });

    test('ignores empty/unparseable urls', () {
      expect(cleartextViolation(''), isNull);
    });
  });
}
