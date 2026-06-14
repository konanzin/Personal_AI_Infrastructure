import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/services/pulse/speech_engine.dart';

PulseTtsVoice voice({
  required String name,
  required String locale,
  bool networkRequired = false,
  String quality = 'normal',
  String latency = 'normal',
  Set<String> features = const {},
}) =>
    PulseTtsVoice(
      name: name,
      locale: locale,
      networkRequired: networkRequired,
      quality: quality,
      latency: latency,
      features: features,
    );

void main() {
  group('selectBestPulseTtsVoice', () {
    test('prefers an online pt-BR voice over a local pt-BR voice', () {
      final selected = selectBestPulseTtsVoice([
        voice(name: 'local', locale: 'pt-BR', quality: 'very high'),
        voice(name: 'online', locale: 'pt-BR', networkRequired: true),
      ], 'pt-BR');

      expect(selected?.name, 'online');
    });

    test('prefers an online en-US voice for English text targets', () {
      final selected = selectBestPulseTtsVoice([
        voice(name: 'pt-online', locale: 'pt-BR', networkRequired: true),
        voice(name: 'en-local', locale: 'en-US'),
        voice(name: 'en-online', locale: 'en-US', networkRequired: true),
      ], 'en-US');

      expect(selected?.name, 'en-online');
    });

    test('prefers higher quality among online voices', () {
      final selected = selectBestPulseTtsVoice([
        voice(
          name: 'normal',
          locale: 'pt-BR',
          networkRequired: true,
          quality: 'normal',
        ),
        voice(
          name: 'very-high',
          locale: 'pt-BR',
          networkRequired: true,
          quality: 'very high',
        ),
      ], 'pt-BR');

      expect(selected?.name, 'very-high');
    });

    test('uses latency as a tie-breaker', () {
      final selected = selectBestPulseTtsVoice([
        voice(
          name: 'slow',
          locale: 'en-US',
          networkRequired: true,
          quality: 'high',
          latency: 'high',
        ),
        voice(
          name: 'fast',
          locale: 'en-US',
          networkRequired: true,
          quality: 'high',
          latency: 'low',
        ),
      ], 'en-US');

      expect(selected?.name, 'fast');
    });

    test('falls back to a local matching voice when no online voice exists',
        () {
      final selected = selectBestPulseTtsVoice([
        voice(name: 'local', locale: 'pt-BR'),
      ], 'pt-BR');

      expect(selected?.name, 'local');
    });

    test('does not select a voice from a different language', () {
      final selected = selectBestPulseTtsVoice([
        voice(name: 'pt-online', locale: 'pt-BR', networkRequired: true),
      ], 'en-US');

      expect(selected, isNull);
    });

    test('falls back to same language when the exact region is unavailable',
        () {
      final selected = selectBestPulseTtsVoice([
        voice(name: 'en-gb-online', locale: 'en-GB', networkRequired: true),
      ], 'en-US');

      expect(selected?.name, 'en-gb-online');
    });

    test('prefers an installed voice over a not installed network voice', () {
      final selected = selectBestPulseTtsVoice([
        voice(
          name: 'missing-network',
          locale: 'en-US',
          networkRequired: true,
          features: {'notInstalled'},
        ),
        voice(name: 'installed-local', locale: 'en-US'),
      ], 'en-US');

      expect(selected?.name, 'installed-local');
    });
  });

  group('normalizePulseTtsLanguage', () {
    test('normalizes Portuguese and English language selectors', () {
      expect(normalizePulseTtsLanguage('pt'), 'pt-BR');
      expect(normalizePulseTtsLanguage('pt_BR'), 'pt-BR');
      expect(normalizePulseTtsLanguage('en'), 'en-US');
      expect(normalizePulseTtsLanguage('en_GB'), 'en-GB');
    });

    test('rejects empty and unsupported language selectors', () {
      expect(normalizePulseTtsLanguage(''), isNull);
      expect(normalizePulseTtsLanguage('es-ES'), isNull);
    });
  });
}
