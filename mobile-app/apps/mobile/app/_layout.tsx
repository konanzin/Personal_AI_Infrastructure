import '../src/polyfills';
import { Stack, usePathname } from 'expo-router';
import { PaperProvider } from 'react-native-paper';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { useEffect } from 'react';
import { paiLightTheme, paiDarkTheme } from '../src/theme';
import { useAppStore, useSettingsStore } from '../src/stores';

function AppProviders({ children }: { children: React.ReactNode }) {
  const themeMode = useAppStore((s) => s.themeMode);
  const setActiveRoute = useAppStore((s) => s.setActiveRoute);
  const loadSettings = useSettingsStore((s) => s.loadFromPersistence);
  const themePreference = useSettingsStore((s) => s.themePreference);
  const initializeTheme = useAppStore((s) => s.initializeTheme);
  const isHydrated = useSettingsStore((s) => s.isHydrated);
  const pathname = usePathname();

  useEffect(() => {
    loadSettings();
  }, [loadSettings]);

  useEffect(() => {
    if (isHydrated) {
      initializeTheme(themePreference);
    }
  }, [themePreference, initializeTheme, isHydrated]);

  useEffect(() => {
    setActiveRoute(pathname || '/');
  }, [pathname, setActiveRoute]);

  const activeTheme = themeMode === 'dark' ? paiDarkTheme : paiLightTheme;

  return (
    <SafeAreaProvider>
      <PaperProvider theme={activeTheme}>
        <StatusBar style={themeMode === 'dark' ? 'light' : 'dark'} />
        {children}
      </PaperProvider>
    </SafeAreaProvider>
  );
}

export default function RootLayout() {
  return (
    <AppProviders>
      <Stack>
        <Stack.Screen
          name="index"
          options={{
            title: 'PAI',
            headerShown: true,
          }}
        />
        <Stack.Screen
          name="sessions"
          options={{
            title: 'Sessions',
            headerShown: true,
          }}
        />
        <Stack.Screen
          name="session/[id]"
          options={{
            title: 'Session',
            headerShown: true,
          }}
        />
        <Stack.Screen
          name="settings"
          options={{
            title: 'Settings',
            headerShown: true,
          }}
        />
        <Stack.Screen
          name="notifications"
          options={{
            title: 'Notifications',
            headerShown: true,
          }}
        />
      </Stack>
    </AppProviders>
  );
}
