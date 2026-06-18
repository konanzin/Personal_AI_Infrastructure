import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/services/terminal_keys.dart';

void main() {
  group('applyTerminalModifiers', () {
    test('no modifiers passes data through unchanged', () {
      expect(applyTerminalModifiers('c', ctrl: false, alt: false), 'c');
      expect(applyTerminalModifiers('ls', ctrl: false, alt: false), 'ls');
    });

    test('Ctrl+c yields 0x03 (SIGINT)', () {
      expect(applyTerminalModifiers('c', ctrl: true, alt: false),
          String.fromCharCode(0x03));
    });

    test('Ctrl is case-insensitive (C also yields 0x03)', () {
      expect(applyTerminalModifiers('C', ctrl: true, alt: false),
          String.fromCharCode(0x03));
    });

    test('Ctrl+[ yields ESC (0x1b)', () {
      expect(applyTerminalModifiers('[', ctrl: true, alt: false),
          String.fromCharCode(0x1b));
    });

    test('Ctrl+d yields 0x04 (EOF)', () {
      expect(applyTerminalModifiers('d', ctrl: true, alt: false),
          String.fromCharCode(0x04));
    });

    test('Ctrl on a char outside the control range passes through', () {
      // '1' (0x31) is not in @.._ , so Ctrl is a no-op.
      expect(applyTerminalModifiers('1', ctrl: true, alt: false), '1');
    });

    test('Ctrl on multi-char input is a no-op (only single chars)', () {
      expect(applyTerminalModifiers('ls', ctrl: true, alt: false), 'ls');
    });

    test('Alt prefixes ESC', () {
      expect(applyTerminalModifiers('a', ctrl: false, alt: true),
          '\x1ba');
    });

    test('Ctrl+Alt composes: Ctrl transforms then Alt prefixes ESC', () {
      // Ctrl+c → 0x03, then Alt → ESC + 0x03
      expect(applyTerminalModifiers('c', ctrl: true, alt: true),
          '\x1b${String.fromCharCode(0x03)}');
    });

    test('Alt on a literal slash prefixes ESC', () {
      expect(applyTerminalModifiers('/', ctrl: false, alt: true), '\x1b/');
    });
  });
}
