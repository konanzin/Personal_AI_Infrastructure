import 'package:flutter_tts/flutter_tts.dart';

/// Voice rendering abstraction (PULSE_MOBILE_PLAN.md, C3): the engine is a
/// renderer detail, swappable without touching the event pipeline. Default
/// is the Android platform TTS; premium engines (e.g. Gemini TTS) can be
/// added later behind this same interface.
abstract class SpeechEngine {
  Future<void> speak(String text);
  Future<void> stop();
}

class NativeTtsEngine implements SpeechEngine {
  NativeTtsEngine({String language = 'pt-BR', double rate = 0.55})
      : _language = language,
        _rate = rate;

  final String _language;
  final double _rate;
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(_rate);
    // Queue utterances instead of cutting the previous one off mid-sentence.
    await _tts.setQueueMode(1);
    _ready = true;
  }

  @override
  Future<void> speak(String text) async {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return;
    await _ensureReady();
    await _tts.speak(cleaned);
  }

  @override
  Future<void> stop() => _tts.stop();
}
