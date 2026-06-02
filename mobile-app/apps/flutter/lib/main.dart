import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/settings_provider.dart';
import 'providers/session_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PaiMobileApp());
}

class PaiMobileApp extends StatelessWidget {
  const PaiMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SettingsProvider()..loadSettings(),
      child: ChangeNotifierProvider(
        create: (_) => SessionProvider()..loadPersistedSession(),
        child: Builder(
          builder: (context) {
            final settings = context.watch<SettingsProvider>().settings;
            
            return MaterialApp(
              title: 'PAI — OpenCode AI',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF3B82F6),
                  brightness: Brightness.light,
                ),
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF3B82F6),
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
              ),
              home: settings.isConfigured 
                  ? const SessionsScreen() 
                  : const _WelcomeScreen(),
              routes: {
                '/settings': (context) => const SettingsScreen(),
                '/sessions': (context) => const SessionsScreen(),
                '/chat': (context) => const ChatScreen(),
              },
            );
          },
        ),
      ),
    );
  }
}

/// Tela inicial quando o app não está configurado
class _WelcomeScreen extends StatelessWidget {
  const _WelcomeScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.psychology,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 32),
              const Text(
                'PAI',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your Personal AI Assistant',
                style: TextStyle(
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/settings'),
                icon: const Icon(Icons.settings),
                label: const Text('Configure Server'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
