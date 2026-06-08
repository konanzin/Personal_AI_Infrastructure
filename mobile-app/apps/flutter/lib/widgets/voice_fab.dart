import 'package:flutter/material.dart';

import '../services/permission_service.dart';
import '../services/voice_service.dart';

/// Estados do botão de voz
enum VoiceState {
  idle,      // Botão pronto para iniciar
  listening, // Ouvindo fala do usuário
  processing,// Processando/transcrevendo
  error,     // Erro ocorrido
}

/// Botão flutuante de voz com estados animados
class VoiceFab extends StatefulWidget {
  final VoiceService voiceService;
  final Function(String text)? onSpeechResult;
  final VoidCallback? onStartListening;
  final VoidCallback? onStopListening;

  const VoiceFab({
    super.key,
    required this.voiceService,
    this.onSpeechResult,
    this.onStartListening,
    this.onStopListening,
  });

  @override
  State<VoiceFab> createState() => _VoiceFabState();
}

class _VoiceFabState extends State<VoiceFab> with SingleTickerProviderStateMixin {
  VoiceState _state = VoiceState.idle;
  String? _partialText;
  String? _errorMessage;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    // Configura callbacks do voice service
    widget.voiceService.onSpeechStatus = _handleSpeechStatus;
    widget.voiceService.onSpeechResult = _handleSpeechResult;
    widget.voiceService.onSpeechPartial = _handleSpeechPartial;
    widget.voiceService.onSpeechError = _handleSpeechError;
  }

  void _handleSpeechStatus(String status) {
    setState(() {
      switch (status) {
        case 'listening':
          _state = VoiceState.listening;
          _animationController.repeat();
          break;
        case 'started':
          _state = VoiceState.listening;
          break;
        case 'stopped':
          _state = VoiceState.processing;
          _animationController.stop();
          break;
        case 'error':
          _state = VoiceState.error;
          _animationController.stop();
          break;
      }
    });
  }

  void _handleSpeechResult(String text) {
    setState(() {
      _state = VoiceState.idle;
      _partialText = null;
    });
    widget.onSpeechResult?.call(text);
  }

  void _handleSpeechPartial(String text) {
    setState(() {
      _partialText = text;
    });
  }

  void _handleSpeechError(String error) {
    setState(() {
      _state = VoiceState.error;
      _errorMessage = error;
    });
    
    // Limpa erro após 3 segundos
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _state = VoiceState.idle;
          _errorMessage = null;
        });
      }
    });
  }

  Future<void> _toggleListening() async {
    if (_state == VoiceState.listening) {
      // Para de ouvir
      await widget.voiceService.stopListening();
      widget.onStopListening?.call();
    } else {
      // Verifica permissão antes de iniciar
      final hasPermission = await PermissionService.requestMicrophonePermission(context);
      if (!hasPermission) {
        setState(() {
          _state = VoiceState.error;
          _errorMessage = 'Permissão de microfone necessária';
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _state = VoiceState.idle;
              _errorMessage = null;
            });
          }
        });
        return;
      }
      
      // Começa a ouvir
      setState(() {
        _state = VoiceState.listening;
        _partialText = null;
        _errorMessage = null;
      });
      widget.onStartListening?.call();
      await widget.voiceService.startListening(locale: 'pt-BR');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Texto parcial ou erro
        if (_partialText != null || _errorMessage != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _errorMessage != null 
                  ? theme.colorScheme.errorContainer 
                  : theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _errorMessage ?? _partialText ?? '',
              style: TextStyle(
                color: _errorMessage != null 
                    ? theme.colorScheme.onErrorContainer 
                    : theme.colorScheme.onPrimaryContainer,
                fontSize: 14,
              ),
            ),
          ),
        
        // Botão principal
        GestureDetector(
          onTap: _toggleListening,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _state == VoiceState.listening ? 80 : 64,
            height: _state == VoiceState.listening ? 80 : 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getButtonColor(theme),
              boxShadow: _state == VoiceState.listening
                  ? [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _getIcon(theme),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _getButtonColor(ThemeData theme) {
    switch (_state) {
      case VoiceState.idle:
        return theme.colorScheme.primary;
      case VoiceState.listening:
        return theme.colorScheme.error;
      case VoiceState.processing:
        return theme.colorScheme.secondary;
      case VoiceState.error:
        return theme.colorScheme.errorContainer;
    }
  }

  Widget _getIcon(ThemeData theme) {
    final iconColor = theme.colorScheme.onPrimary;
    
    switch (_state) {
      case VoiceState.idle:
        return Icon(Icons.mic, color: iconColor, size: 32, key: const ValueKey('mic'));
      case VoiceState.listening:
        return Icon(Icons.mic, color: iconColor, size: 36, key: const ValueKey('listening'));
      case VoiceState.processing:
        return SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            color: iconColor,
            strokeWidth: 3,
          ),
        );
      case VoiceState.error:
        return Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer, size: 32, key: const ValueKey('error'));
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
