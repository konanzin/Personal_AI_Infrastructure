import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Serviço que encapsula Speech-to-Text (STT) nativo do Android.
///
/// TTS fica explicitamente fora desta etapa: o serviço só captura voz,
/// transcreve e entrega texto para o chat enviar ao OpenCode.
class VoiceService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.pai_mobile_flutter/voice',
  );

  // Callbacks
  Function(String text)? onSpeechResult;
  Function(String text)? onSpeechPartial;
  Function(String status)? onSpeechStatus;
  Function(String error)? onSpeechError;
  Function(double level)? onSoundLevel;

  bool _isInitialized = false;
  bool _isListening = false;

  VoiceService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Inicializa o reconhecimento de fala
  Future<void> initSpeech() async {
    if (_isInitialized) return;
    
    try {
      await _channel.invokeMethod('initSpeechRecognizer');
      _isInitialized = true;
    } on PlatformException catch (e) {
      debugPrint('Error initializing voice service: ${e.message}');
    }
  }

  /// Inicia o reconhecimento de fala
  /// 
  /// [locale] - Locale para reconhecimento (ex: "pt-BR", "en-US")
  Future<void> startListening({String locale = 'pt-BR'}) async {
    if (!_isInitialized) await initSpeech();
    
    try {
      await _channel.invokeMethod('startListening', {'locale': locale});
      _isListening = true;
    } on PlatformException catch (e) {
      debugPrint('Error starting listening: ${e.message}');
      onSpeechError?.call(e.message ?? 'Unknown error');
    }
  }

  /// Para o reconhecimento de fala
  Future<void> stopListening() async {
    try {
      await _channel.invokeMethod('stopListening');
      _isListening = false;
    } on PlatformException catch (e) {
      debugPrint('Error stopping listening: ${e.message}');
    }
  }

  /// Verifica se está ouvindo
  Future<bool> get isListening async {
    try {
      final result = await _channel.invokeMethod<bool>('isListening');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Handler para chamadas do nativo para o Flutter
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onSpeechResult':
        final text = call.arguments['text'] as String?;
        if (text != null) {
          _isListening = false;
          onSpeechResult?.call(text);
        }
        break;
        
      case 'onSpeechPartial':
        final text = call.arguments['text'] as String?;
        if (text != null) {
          onSpeechPartial?.call(text);
        }
        break;
        
      case 'onSpeechStatus':
        final status = call.arguments['status'] as String?;
        if (status != null) {
          if (status == 'stopped' || status == 'error') {
            _isListening = false;
          }
          onSpeechStatus?.call(status);
        }
        break;
        
      case 'onSpeechError':
        final error = call.arguments['error'] as String?;
        if (error != null) {
          _isListening = false;
          onSpeechError?.call(error);
        }
        break;
        
      case 'onSoundLevel':
        final level = call.arguments['level'] as double?;
        if (level != null) {
          onSoundLevel?.call(level);
        }
        break;
        
      default:
        debugPrint('Unknown method call: ${call.method}');
    }
  }

  /// Libera recursos
  void dispose() {
    stopListening();
    _channel.setMethodCallHandler(null);
  }
}
