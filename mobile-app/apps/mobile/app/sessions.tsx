import { View, StyleSheet, FlatList, AppState, RefreshControl } from 'react-native';
import { Text, List, FAB, useTheme, Banner, ActivityIndicator, Chip } from 'react-native-paper';
import { useRouter } from 'expo-router';
import { Stack } from 'expo-router';
import { useEffect, useCallback, useMemo, useRef } from 'react';
import { useSessionStore, useSettingsStore, useMessageStore, useAppStore, useConnectionStore } from '../src/stores';
import type { ClientConfig } from '@pai/opencode-mobile-client';
import type { SessionSummary, SessionMessage } from '@pai/shared-types';
import { DEMO_SESSION_ID } from '../src/demo/demo-session';
import { buildPreviewFromMessages } from '../src/lib/session-preview';

function buildConfig(settings: {
  serverUrl: string;
  username: string;
  password: string;
}): ClientConfig | null {
  const url = settings.serverUrl.trim();
  if (!url || !settings.username || !settings.password) {
    return null;
  }
  return {
    baseUrl: url,
    username: settings.username,
    password: settings.password,
  };
}

function mergeSessionWithMessages(
  summary: SessionSummary,
  messages: SessionMessage[] | undefined
): SessionSummary {
  if (!messages || messages.length === 0) {
    return summary;
  }
  const { preview, count } = buildPreviewFromMessages(messages);
  return {
    ...summary,
    lastMessagePreview: preview,
    messageCount: count,
  };
}

export default function SessionsScreen() {
  const theme = useTheme();
  const router = useRouter();
  const settings = useSettingsStore();
  const { sessions, isLoading, isRefreshing, error, isConfigured, loadSessions, refreshSessions, clearError, createNewSession } =
    useSessionStore();
  const { messagesBySession } = useMessageStore();
  const activeSessionId = useAppStore((s) => s.activeSessionId);

  const config = settings.isHydrated ? buildConfig(settings) : null;
  const { state: connectionState, checkConnection } = useConnectionStore();
  const appStateRef = useRef(AppState.currentState);

  useEffect(() => {
    if (config) {
      loadSessions(config);
      checkConnection(config);
    }
  }, [config?.baseUrl, config?.username, config?.password]);

  useEffect(() => {
    const subscription = AppState.addEventListener('change', (nextAppState) => {
      const prev = appStateRef.current;
      const becameActive = prev.match(/inactive|background/) && nextAppState === 'active';
      appStateRef.current = nextAppState;

      if (becameActive && config) {
        loadSessions(config);
        checkConnection(config);
      }
    });

    return () => subscription.remove();
  }, [config, loadSessions, checkConnection]);

  const handlePress = useCallback(
    (id: string) => {
      router.push(`/session/${id}`);
    },
    [router]
  );

  const handleRefresh = useCallback(async () => {
    if (!config) return;
    await refreshSessions(config);
    await checkConnection(config);
  }, [config, refreshSessions, checkConnection]);

  const handleNewSession = useCallback(async () => {
    if (!settings.isHydrated) {
      return;
    }

    if (!config) {
      router.push('/settings');
      return;
    }
    const session = await createNewSession(config, 'New Session');
    if (session) {
      router.push(`/session/${session.id}`);
    }
  }, [config, router, createNewSession, settings.isHydrated]);

  const visibleSessions: SessionSummary[] = useMemo(() => {
    if (!settings.isHydrated || !config) {
      return [];
    }
    return sessions.map((s) => mergeSessionWithMessages(s, messagesBySession[s.id]));
  }, [config, sessions, messagesBySession, settings.isHydrated]);

  const showLoadError = !!settings.loadError;
  const showConfigureBanner = settings.isHydrated && !config && !showLoadError;
  const showErrorBanner = !!error;
  const showConnectionChip = config && connectionState !== 'connected';

  const connectionChipProps =
    connectionState === 'connecting'
      ? { icon: 'wifi-sync' as const, text: 'Connecting…' }
      : connectionState === 'offline'
        ? { icon: 'wifi-off' as const, text: 'Offline' }
        : { icon: 'wifi-off' as const, text: 'Connection issue' };

  return (
    <>
      <Stack.Screen options={{ title: 'Sessions' }} />
      <View style={[styles.container, { backgroundColor: theme.colors.background }]}>
        {showLoadError && settings.loadError && (
          <Banner
            visible={true}
            actions={[
              {
                label: 'Dismiss',
                onPress: () => useSettingsStore.getState().setLoadError(null),
              },
              {
                label: 'Retry',
                onPress: () => useSettingsStore.getState().loadFromPersistence(),
              },
            ]}
            icon="alert-circle"
          >
            {settings.loadError}
          </Banner>
        )}

        {showConfigureBanner && (
          <Banner
            visible={true}
            actions={[
              {
                label: 'Go to Settings',
                onPress: () => router.push('/settings'),
              },
              {
                label: 'Open Demo',
                onPress: () => router.push(`/session/${DEMO_SESSION_ID}`),
              },
            ]}
            icon="server-off"
          >
            Server not configured. You can open a local demo session now, or add server URL and
            credentials in Settings for live sessions.
          </Banner>
        )}

        {showConnectionChip && (
          <View style={styles.connectionRow}>
            <Chip icon={connectionChipProps.icon} style={styles.connectionChip}>
              {connectionChipProps.text}
            </Chip>
          </View>
        )}

        {showErrorBanner && (
          <Banner
            visible={true}
            actions={[
              {
                label: 'Dismiss',
                onPress: clearError,
              },
              {
                label: 'Retry',
                onPress: () => config && loadSessions(config),
              },
            ]}
            icon="alert-circle"
          >
            {error}
          </Banner>
        )}

        {isLoading && (
          <View style={styles.loading}>
            <ActivityIndicator animating={true} size="large" />
          </View>
        )}

        <FlatList
          data={visibleSessions}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => {
            const isActive = item.id === activeSessionId;
            return (
              <List.Item
                title={item.title}
                description={
                  item.lastMessagePreview ??
                  (item.messageCount !== undefined ? `${item.messageCount} messages` : undefined)
                }
                left={(props) => (
                  <List.Icon {...props} icon={isActive ? 'chat-processing' : 'chat'} />
                )}
                onPress={() => handlePress(item.id)}
                style={{
                  backgroundColor: isActive
                    ? theme.colors.primaryContainer
                    : theme.colors.surface,
                }}
              />
            );
          }}
          ListEmptyComponent={
            <View style={styles.empty}>
              <Text variant="bodyLarge" style={{ color: theme.colors.onSurfaceVariant }}>
                {isConfigured
                  ? 'No sessions yet.'
                  : 'Open the demo session or configure a server.'}
              </Text>
            </View>
          }
          contentContainerStyle={styles.listContent}
          refreshControl={
            <RefreshControl
              refreshing={isRefreshing}
              onRefresh={handleRefresh}
              colors={[theme.colors.primary]}
              tintColor={theme.colors.primary}
            />
          }
        />

        <FAB
          icon="plus"
          style={[styles.fab, { backgroundColor: theme.colors.primary }]}
          onPress={handleNewSession}
          color={theme.colors.onPrimary}
        />
      </View>
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  listContent: {
    paddingVertical: 8,
  },
  empty: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  loading: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  fab: {
    position: 'absolute',
    right: 16,
    bottom: 16,
  },
  connectionRow: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    alignItems: 'flex-start',
  },
  connectionChip: {
    backgroundColor: 'rgba(0,0,0,0.05)',
  },
});
