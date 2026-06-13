import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'providers/app_lock_provider.dart';
import 'providers/client_provider.dart';
import 'providers/machine_store.dart';
import 'providers/opencode_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/session_provider.dart';
import 'providers/workspace_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/machines_screen.dart';
import 'screens/providers_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/terminal_screen.dart';
import 'services/notification_service.dart';
import 'services/pulse/pulse_listener_service.dart';
import 'services/permission_service.dart';
import 'theme.dart';

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
          create: (_) => SettingsProvider()
            ..loadSettings()
            ..loadThemeMode()
            ..loadThemeAppearance()
            ..loadShowThinking()
            ..loadVoiceSettings()
            ..loadPulseSettings(),
        ),
        ChangeNotifierProvider(
          create: (_) => MachineStore()..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => WorkspaceProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => AppLockProvider()..initialize(),
        ),
        ChangeNotifierProxyProvider<MachineStore, ClientProvider>(
          create: (_) => ClientProvider(),
          update: (_, machineStore, prev) {
            final machine = machineStore.activeMachine;
            if (machine != null) {
              prev!.initializeFromMachine(machine);
              PulseRuntime.serverUrl = machine.serverUrl;
              PulseRuntime.sync();
            }
            return prev!;
          },
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
            if (prev != null &&
                clientProv.client != null &&
                prev.clientOrNull != clientProv.client) {
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
    // Persist under the active machine+directory scope; an unscoped select
    // writes to the legacy key, which the chat restore never reads back.
    sessionProvider.selectSession(
      sessionId,
      machineId: context.read<MachineStore>().activeMachineId,
      directory: context.read<OpenCodeProvider>().directory,
    );
    _navigatorKey.currentState?.pushReplacementNamed('/chat');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
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
    final machineStore = context.watch<MachineStore>();
    final hasMachine = machineStore.activeMachine != null;
    final isConfigured = hasMachine || settingsProvider.settings.isConfigured;

    return DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
      final useDynamic = settingsProvider.useDynamicColor;
      return MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'PAI — OpenCode AI',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('pt'), Locale('en')],
        themeMode: settingsProvider.themeMode,
        theme: AppTheme.light(
          seed: settingsProvider.seedColor,
          dynamicScheme: useDynamic ? lightDynamic : null,
          variant: settingsProvider.schemeVariant,
        ),
        darkTheme: AppTheme.dark(
          seed: settingsProvider.seedColor,
          dynamicScheme: useDynamic ? darkDynamic : null,
          pureBlack: settingsProvider.pureBlack,
          variant: settingsProvider.schemeVariant,
        ),
        home: isConfigured ? const ChatScreen() : const _WelcomeScreen(),
        routes: {
          '/settings': (context) => const SettingsScreen(),
          '/chat': (context) => const ChatScreen(),
          '/machines': (context) => const MachinesScreen(),
          '/providers': (context) => const ProvidersScreen(),
          '/terminal': (context) => const TerminalScreen(),
        },
        // Render the lock as an overlay above the Navigator so it covers EVERY
        // route (settings, terminal, providers…), not just the home route.
        builder: (context, child) {
          return Stack(
            children: [
              if (child != null) child,
              Consumer<AppLockProvider>(
                builder: (context, lock, _) => lock.isLocked
                    ? const LockScreen()
                    : const SizedBox.shrink(),
              ),
            ],
          );
        },
      );
    });
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
                AppLocalizations.of(context)!.welcomeSubtitle,
                style: TextStyle(
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/machines'),
                icon: const Icon(Icons.settings),
                label: Text(AppLocalizations.of(context)!.setUpMachine),
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
