import { View, StyleSheet, ScrollView, AppState } from 'react-native';
import {
  Text,
  Button,
  useTheme,
  Banner,
  ActivityIndicator,
  TextInput,
  List,
} from 'react-native-paper';
import { useRouter } from 'expo-router';
import { useEffect, useCallback, useRef } from 'react';
import {
  useVoiceStore,
  useSessionStore,
  useSettingsStore,
  useMessageStore,
  useConnectionStore,
} from '../src/stores';
import { VoiceOrb } from '../src/components/VoiceOrb';
import type { ClientConfig } from '@pai/opencode-mobile-client';
import { DEMO_SESSION_ID } from '../src/demo/demo-session';
import {
  hasElevenLabsApiKey,
  MISSING_ELEVENLABS_API_KEY_MESSAGE,
} from '@pai/audio-elevenlabs';

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

export default function HomeScreen() {
  const theme = useTheme();
  const router = useRouter();
  const settings = useSettingsStore();
  const config = settings.isHydrated ? buildConfig(settings) : null;

  const {
    state: voiceState,
    transcription: voiceTranscription,
    error: voiceError,
    recordingDurationMs,
    startRecording,
    stopRecordingAndTranscribe,
    confirmTranscription,
    cancel: cancelVoice,
    setTranscription: setVoiceTranscription,
    reset: resetVoice,
  } = useVoiceStore();

  const {
    sessions,
    isLoading: sessionsLoading,
    error: sessionError,
    loadSessions,
    createNewSession,
  } = useSessionStore();

  const { send: sendMessage, setDraft } = useMessageStore();
  const { state: connectionState, checkConnection } = useConnectionStore();

  const appStateRef = useRef(AppState.currentState);
  const needsTranscriptionKey =
    settings.audioEnabled && !hasElevenLabsApiKey(settings.elevenLabsApiKey);

  // Load sessions on mount / when config changes
  useEffect(() => {
    if (config) {
      loadSessions(config);
      checkConnection(config);
    }
  }, [config?.baseUrl, config?.username, config?.password]);

  // Refresh on app resume
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

  const handleOrbPress = useCallback(async () => {
    if (voiceState === 'idle') {
      if (!settings.audioEnabled) return;
      if (needsTranscriptionKey) {
        router.push('/settings');
        return;
      }
      await startRecording();
    } else if (voiceState === 'listening') {
      await stopRecordingAndTranscribe(settings.elevenLabsApiKey);
    }
  }, [
    voiceState,
    startRecording,
    stopRecordingAndTranscribe,
    settings.audioEnabled,
    settings.elevenLabsApiKey,
    needsTranscriptionKey,
    router,
  ]);

  const handleConfirmVoice = useCallback(async () => {
    const text = confirmTranscription();
    if (!text) return;

    if (!settings.isHydrated) {
      setVoiceTranscription(text);
      return;
    }

    if (!config) {
      setVoiceTranscription(text);
      router.push('/settings');
      return;
    }

    let targetSessionId: string;

    if (sessions.length === 0) {
      const session = await createNewSession(config, text.slice(0, 40));
      if (!session) {
        // Fallback: keep text in voice store for retry
        setVoiceTranscription(text);
        return;
      }
      targetSessionId = session.id;
    } else {
      // Pick most recently updated session
      const mostRecent = [...sessions].sort(
        (a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
      )[0];
      targetSessionId = mostRecent.id;
    }

    // Send the message
    await sendMessage(config, targetSessionId, [{ type: 'text', text }]);

    // Navigate to session
    router.push(`/session/${targetSessionId}`);
  }, [
    confirmTranscription,
    config,
    sessions,
    createNewSession,
    sendMessage,
    router,
    setVoiceTranscription,
    settings.isHydrated,
  ]);

  const handleCancelVoice = useCallback(() => {
    cancelVoice();
  }, [cancelVoice]);

  const showVoiceError = !!voiceError && voiceState === 'error';
  const showSessionError = !!sessionError;
  const isReviewing = voiceState === 'reviewing' && voiceTranscription !== null;

  // Sort sessions for recent list
  const recentSessions = [...sessions]
    .sort((a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime())
    .slice(0, 3);

  return (
    <ScrollView
      style={[styles.container, { backgroundColor: theme.colors.background }]}
      contentContainerStyle={styles.content}
      keyboardShouldPersistTaps="handled"
    >
      {/* Header */}
      <View style={styles.header}>
        <Text variant="headlineMedium" style={{ color: theme.colors.primary }}>
          PAI
        </Text>
        <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
          Tap the orb to speak
        </Text>
      </View>

      {/* Voice Orb */}
      <View style={styles.orbSection}>
        <VoiceOrb
          state={voiceState}
          onPress={handleOrbPress}
          durationMs={recordingDurationMs}
          size={180}
        />
      </View>

      {/* Voice Error */}
      {showVoiceError && (
        <Banner
          visible={true}
          actions={[
            {
              label: 'Dismiss',
              onPress: handleCancelVoice,
            },
          ]}
          icon="microphone-off"
          style={styles.banner}
        >
          {voiceError}
        </Banner>
      )}

      {needsTranscriptionKey && !showVoiceError && !isReviewing && (
        <Banner
          visible={true}
          actions={[
            {
              label: 'Open Settings',
              onPress: () => router.push('/settings'),
            },
          ]}
          icon="key-alert"
          style={styles.banner}
        >
          {MISSING_ELEVENLABS_API_KEY_MESSAGE}
        </Banner>
      )}

      {/* Session Error */}
      {showSessionError && (
        <Banner
          visible={true}
          actions={[
            {
              label: 'Dismiss',
              onPress: () => useSessionStore.getState().clearError(),
            },
          ]}
          icon="alert-circle"
          style={styles.banner}
        >
          {sessionError}
        </Banner>
      )}

      {/* Review Panel */}
      {isReviewing && (
        <View style={styles.reviewPanel}>
          <Text variant="titleSmall" style={{ color: theme.colors.primary }}>
            Review
          </Text>
          <TextInput
            mode="outlined"
            value={voiceTranscription}
            onChangeText={setVoiceTranscription}
            multiline
            numberOfLines={4}
            maxLength={2000}
            style={styles.input}
          />
          <Button
            mode="contained"
            onPress={handleConfirmVoice}
            icon="send"
            style={styles.button}
            loading={sessionsLoading}
          >
            Send
          </Button>
          <Button
            mode="outlined"
            onPress={handleCancelVoice}
            icon="close"
            style={styles.button}
          >
            Cancel
          </Button>
        </View>
      )}

      {/* Recent Sessions */}
      {recentSessions.length > 0 && !isReviewing && (
        <View style={styles.recentSection}>
          <Text
            variant="titleSmall"
            style={[styles.sectionTitle, { color: theme.colors.onSurfaceVariant }]}
          >
            Recent
          </Text>
          {recentSessions.map((session) => (
            <List.Item
              key={session.id}
              title={session.title}
              description={
                session.lastMessagePreview ??
                (session.messageCount !== undefined ? `${session.messageCount} messages` : undefined)
              }
              left={(props) => <List.Icon {...props} icon="chat" />}
              onPress={() => router.push(`/session/${session.id}`)}
              style={[
                styles.sessionItem,
                { backgroundColor: theme.colors.surface },
              ]}
            />
          ))}
        </View>
      )}

      {/* Loading indicator for sessions */}
      {sessionsLoading && !isReviewing && recentSessions.length === 0 && (
        <View style={styles.loading}>
          <ActivityIndicator animating={true} size="small" />
        </View>
      )}

      {/* Secondary Actions */}
      {!isReviewing && (
        <View style={styles.secondaryActions}>
          <Button
            mode="text"
            onPress={() => router.push('/sessions')}
            icon="chat"
            style={styles.secondaryButton}
          >
            All Sessions
          </Button>
          <Button
            mode="text"
            onPress={() => router.push('/settings')}
            icon="cog"
            style={styles.secondaryButton}
          >
            Settings
          </Button>
        </View>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    padding: 24,
    gap: 20,
    alignItems: 'center',
  },
  header: {
    alignItems: 'center',
    marginTop: 24,
    gap: 4,
  },
  orbSection: {
    marginVertical: 24,
  },
  banner: {
    width: '100%',
    maxWidth: 400,
  },
  reviewPanel: {
    width: '100%',
    maxWidth: 400,
    gap: 12,
  },
  input: {
    backgroundColor: 'transparent',
  },
  button: {
    width: '100%',
  },
  recentSection: {
    width: '100%',
    maxWidth: 400,
    gap: 4,
  },
  sectionTitle: {
    marginBottom: 4,
  },
  sessionItem: {
    borderRadius: 8,
    marginVertical: 2,
  },
  loading: {
    paddingVertical: 16,
  },
  secondaryActions: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 8,
  },
  secondaryButton: {
    flex: 1,
  },
});
