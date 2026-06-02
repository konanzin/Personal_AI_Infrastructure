import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Serviço para gerenciar permissões do app
class PermissionService {
  /// Solicita permissão de microfone
  static Future<bool> requestMicrophonePermission(BuildContext context) async {
    // Verifica status atual
    var status = await Permission.microphone.status;
    
    if (status.isGranted) {
      return true;
    }
    
    if (status.isDenied) {
      // Solicita permissão
      status = await Permission.microphone.request();
      
      if (status.isGranted) {
        return true;
      }
    }
    
    if (status.isPermanentlyDenied) {
      // Usuário negou permanentemente, mostra diálogo para ir às configurações
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permissão Necessária'),
            content: const Text(
              'O app precisa de acesso ao microfone para reconhecimento de voz. '
              'Por favor, habilite a permissão nas configurações do app.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: const Text('Abrir Configurações'),
              ),
            ],
          ),
        );
      }
    }
    
    return false;
  }
  
  /// Verifica se tem permissão de microfone
  static Future<bool> hasMicrophonePermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// Solicita permissão de câmera
  static Future<bool> requestCameraPermission(BuildContext context) async {
    return await _requestPermission(
      context,
      permission: Permission.camera,
      title: 'Permissão de Câmera',
      message: 'O app precisa de acesso à câmera para capturar imagens.',
    );
  }

  /// Solicita permissão de fotos
  static Future<bool> requestPhotosPermission(BuildContext context) async {
    return await _requestPermission(
      context,
      permission: Permission.photos,
      title: 'Permissão de Fotos',
      message: 'O app precisa de acesso às fotos para anexar imagens.',
    );
  }

  /// Solicita permissão de notificações
  static Future<bool> requestNotificationPermission(BuildContext context) async {
    return await _requestPermission(
      context,
      permission: Permission.notification,
      title: 'Permissão de Notificações',
      message: 'O app precisa de permissão para enviar notificações push.',
    );
  }

  /// Helper genérico para solicitar permissões
  static Future<bool> _requestPermission(
    BuildContext context, {
    required Permission permission,
    required String title,
    required String message,
  }) async {
    var status = await permission.status;

    if (status.isGranted) {
      return true;
    }

    if (status.isDenied) {
      status = await permission.request();
      if (status.isGranted) {
        return true;
      }
    }

    if (status.isPermanentlyDenied) {
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text('$message Por favor, habilite a permissão nas configurações do app.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: const Text('Abrir Configurações'),
              ),
            ],
          ),
        );
      }
    }

    return false;
  }
}