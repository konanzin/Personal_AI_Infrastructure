import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/client_provider.dart';
import 'providers/opencode_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/session_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';
import 'services/notification_service.dart';
import 'services/permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  runApp(const PaiMobileApp());
}

class PaiMobileApp extends StatelessWidget {
  const PaiMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SettingsProvider()..loadSettings()..loadThemeMode(),
        ),
        ChangeNotifierProvider(
          create: (_) => ClientProvider(),
        ),
        ChangeNotifierProxyProvider<ClientProvider, SessionProvider>(
          create: (_) => SessionProvider()..loadPersistedSession(),
          update: (_, clientProv, prev) {
            prev!.sharedClient = clientProv.client;
            return prev;
          },
        ),
        ChangeNotifierProxyProvider<ClientProvider, OpenCodeProvider>(
          create: (_) => OpenCodeProvider(),
          update: (_, clientProv, prev) {
            if (prev != null && clientProv.client != null && prev.clientOrNull != clientProv.client) {
              prev.updateClient(clientProv.client!);
            }
            return prev!;
          },
        ),
      ],
      child: const _AppShell(),
    );
  }
}

/// Initializes the client provider once settings are loaded, then builds the MaterialApp.
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
  bool _initialized = false;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleNotificationPayload();
    }
  }

  void _handleNotificationPayload() {
    final payload = NotificationService.consumePendingPayload();
    if (payload == null || !payload.startsWith('chat:')) return;
    final sessionId = payload.substring(5);
    final sessionProvider = context.read<SessionProvider>();
    sessionProvider.selectSession(sessionId);
    _navigatorKey.currentState?.pushReplacementNamed('/chat');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final settings = context.read<SettingsProvider>().settings;
      context.read<ClientProvider>().initialize(
        requestTimeoutSeconds: settings.requestTimeoutSeconds,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          PermissionService.requestNotificationPermission(context);
          _handleNotificationPayload();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final settings = settingsProvider.settings;

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'PAI — OpenCode AI',
      debugShowCheckedModeBanner: false,
      themeMode: settingsProvider.themeMode,
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
  }
}

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
