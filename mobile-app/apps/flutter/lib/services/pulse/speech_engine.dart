import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

const _defaultPortugueseLanguage = 'pt-BR';
const _defaultEnglishLanguage = 'en-US';

/// Voice rendering abstraction (PULSE_MOBILE_PLAN.md, C3): the engine is a
/// renderer detail, swappable without touching the event pipeline. Default
/// is the Android platform TTS; premium engines (e.g. Gemini TTS) can be
/// added later behind this same interface.
abstract class SpeechEngine {
  Future<void> speak(String text, {required String language});
  Future<void> stop();
}

class NativeTtsEngine implements SpeechEngine {
  NativeTtsEngine({
    double rate = 0.55,
    bool preferNetworkVoices = true,
  })  : _rate = rate,
        _preferNetworkVoices = preferNetworkVoices;

  final double _rate;
  final bool _preferNetworkVoices;
  final FlutterTts _tts = FlutterTts();
  final Map<String, PulseTtsVoice> _selectedVoices = {};
  List<PulseTtsVoice>? _voices;
  String? _activeLanguage;
  String? _activeVoiceKey;
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _tts.setSpeechRate(_rate);
    // Queue utterances instead of cutting the previous one off mid-sentence.
    await _tts.setQueueMode(1);
    _ready = true;
  }

  Future<bool> _applyLanguage(String rawLanguage) async {
    final language = normalizePulseTtsLanguage(rawLanguage);
    if (language == null) return false;

    if (_activeLanguage != language) {
      await _tts.stop();
      if (_activeVoiceKey != null) {
        await _tts.clearVoice();
        _activeVoiceKey = null;
      }
      await _tts.setLanguage(language);
      _activeLanguage = language;
    }

    if (!_preferNetworkVoices) return true;

    final voice = await _bestVoiceFor(language);
    if (voice == null) {
      _debugTts('no selectable voice for $language; using setLanguage only');
      return true;
    }
    final voiceKey = '${voice.name}|${voice.locale}';
    if (_activeVoiceKey == voiceKey) return true;

    final result = await _tts.setVoice(voice.toFlutterTtsVoice());
    if (result == 1) {
      _activeVoiceKey = voiceKey;
      _debugTts(
        'selected ${voice.name} ${voice.locale} '
        'network=${voice.networkRequired} installed=${voice.installed}',
      );
    } else {
      _debugTts('setVoice failed for ${voice.name} ${voice.locale}');
      await _tts.clearVoice();
      await _tts.setLanguage(language);
      _activeVoiceKey = null;
    }
    return true;
  }

  Future<PulseTtsVoice?> _bestVoiceFor(String language) async {
    final cached = _selectedVoices[language];
    if (cached != null) return cached;

    final voices = await _loadVoices();
    final selected = selectBestPulseTtsVoice(
      voices,
      language,
      preferNetworkVoices: _preferNetworkVoices,
    );
    if (selected != null) {
      _selectedVoices[language] = selected;
    } else {
      // Voice data may appear after the Android TTS engine finishes updating.
      _voices = null;
    }
    return selected;
  }

  Future<List<PulseTtsVoice>> _loadVoices() async {
    final cached = _voices;
    if (cached != null) return cached;

    try {
      final rawVoices = await _tts.getVoices;
      if (rawVoices is! List) {
        _voices = const [];
        return _voices!;
      }

      final voices = rawVoices
          .map(PulseTtsVoice.fromPluginValue)
          .whereType<PulseTtsVoice>()
          .toList(growable: false);
      _debugTts('loaded ${voices.length} voices');
      _voices = voices;
      return voices;
    } catch (_) {
      _voices = const [];
      return _voices!;
    }
  }

  @override
  Future<void> speak(String text, {required String language}) async {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return;
    await _ensureReady();
    if (!await _applyLanguage(language)) return;
    await _tts.speak(cleaned);
  }

  @override
  Future<void> stop() => _tts.stop();
}

class PulseTtsVoice {
  const PulseTtsVoice({
    required this.name,
    required this.locale,
    required this.networkRequired,
    required this.quality,
    required this.latency,
    required this.features,
  });

  static PulseTtsVoice? fromPluginValue(Object? value) {
    if (value is! Map) return null;
    final map = value.cast<Object?, Object?>();
    final name = map['name']?.toString();
    final locale = normalizePulseTtsLanguage(map['locale']?.toString());
    if (name == null || name.isEmpty || locale == null) {
      return null;
    }

    return PulseTtsVoice(
      name: name,
      locale: locale,
      networkRequired: map['network_required']?.toString() == '1',
      quality: map['quality']?.toString().toLowerCase() ?? 'unknown',
      latency: map['latency']?.toString().toLowerCase() ?? 'unknown',
      features: _parseVoiceFeatures(map['features']?.toString()),
    );
  }

  final String name;
  final String locale;
  final bool networkRequired;
  final String quality;
  final String latency;
  final Set<String> features;

  bool get installed => !features.contains('notInstalled');

  Map<String, String> toFlutterTtsVoice() => {
        'name': name,
        'locale': locale,
      };
}

PulseTtsVoice? selectBestPulseTtsVoice(
  Iterable<PulseTtsVoice> voices,
  String language, {
  bool preferNetworkVoices = true,
}) {
  final target = normalizePulseTtsLanguage(language);
  if (target == null) return null;
  final exact = voices.where((voice) => voice.locale == target).toList();
  final candidates = exact.isNotEmpty
      ? exact
      : voices
          .where(
              (voice) => _languageCode(voice.locale) == _languageCode(target))
          .toList();

  if (candidates.isEmpty) return null;
  final installed = candidates.where((voice) => voice.installed).toList();
  if (installed.isNotEmpty) {
    candidates
      ..clear()
      ..addAll(installed);
  }

  candidates.sort((a, b) {
    final network = _compareBool(
      a.networkRequired && preferNetworkVoices,
      b.networkRequired && preferNetworkVoices,
    );
    if (network != 0) return network;

    final quality =
        _qualityScore(b.quality).compareTo(_qualityScore(a.quality));
    if (quality != 0) return quality;

    final latency =
        _latencyScore(b.latency).compareTo(_latencyScore(a.latency));
    if (latency != 0) return latency;

    return a.name.compareTo(b.name);
  });

  return candidates.first;
}

String? normalizePulseTtsLanguage(String? language) {
  final trimmed = language?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;

  final parts = trimmed.replaceAll('_', '-').split('-');
  final code = parts.first.toLowerCase();
  final region = parts.length > 1 ? parts[1].toUpperCase() : null;

  if (code == 'pt') {
    return region == null ? _defaultPortugueseLanguage : 'pt-$region';
  }
  if (code == 'en') {
    return region == null ? _defaultEnglishLanguage : 'en-$region';
  }
  return null;
}

int _compareBool(bool a, bool b) {
  if (a == b) return 0;
  return a ? -1 : 1;
}

int _qualityScore(String quality) {
  switch (quality) {
    case 'very high':
      return 5;
    case 'high':
      return 4;
    case 'normal':
      return 3;
    case 'low':
      return 2;
    case 'very low':
      return 1;
    default:
      return 0;
  }
}

int _latencyScore(String latency) {
  switch (latency) {
    case 'very low':
      return 5;
    case 'low':
      return 4;
    case 'normal':
      return 3;
    case 'high':
      return 2;
    case 'very high':
      return 1;
    default:
      return 0;
  }
}

String _languageCode(String locale) =>
    normalizePulseTtsLanguage(locale)?.split('-').first ?? '';

Set<String> _parseVoiceFeatures(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  return raw
      .split('\t')
      .map((feature) => feature.trim())
      .where((feature) => feature.isNotEmpty)
      .toSet();
}

void _debugTts(String message) {
  if (kDebugMode) {
    debugPrint('[pulse-tts] $message');
  }
}
