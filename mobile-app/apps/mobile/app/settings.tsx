import { View, StyleSheet, ScrollView } from 'react-native';
import {
  Text,
  TextInput,
  Switch,
  Button,
  SegmentedButtons,
  useTheme,
  HelperText,
  Banner,
  ActivityIndicator,
} from 'react-native-paper';
import { useEffect, useState } from 'react';
import { useConnectionStore, useSettingsStore, type ThemePreference } from '../src/stores';
import { Stack } from 'expo-router';
import {
  OpenCodeAuthError,
  OpenCodeNetworkError,
  type ClientConfig,
  verifyAuth,
} from '@pai/opencode-mobile-client';
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
  const user = settings.username.trim();
  if (!url || !user || !settings.password || !/^https?:\/\//.test(url)) {
    return null;
  }
  return {
    baseUrl: url,
    username: user,
    password: settings.password,
  };
}

function connectionCopy(state: string, lastError: string | null): string | null {
  if (lastError) return lastError;
  switch (state) {
    case 'connecting':
      return 'Testing connection to your server…';
    case 'connected':
      return 'Connection succeeded. Credentials and server URL look good.';
    case 'authFailed':
      return 'Authentication failed. Double-check your username and password.';
    case 'offline':
      return 'No connection test has been run yet.';
    default:
      return null;
  }
}

export default function SettingsScreen() {
  const theme = useTheme();
  const store = useSettingsStore();
  const connection = useConnectionStore();

  const [serverUrl, setServerUrl] = useState(store.serverUrl);
  const [username, setUsername] = useState(store.username);
  const [password, setPassword] = useState(store.password);
  const [themePreference, setThemePreference] = useState<ThemePreference>(store.themePreference);
  const [notificationsEnabled, setNotificationsEnabled] = useState(store.notificationsEnabled);
  const [audioEnabled, setAudioEnabled] = useState(store.audioEnabled);
  const [elevenLabsApiKey, setElevenLabsApiKey] = useState(store.elevenLabsApiKey);
  const [saved, setSaved] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [isTestingConnection, setIsTestingConnection] = useState(false);

  useEffect(() => {
    if (!store.isHydrated) {
      return;
    }

    setServerUrl(store.serverUrl);
    setUsername(store.username);
    setPassword(store.password);
    setThemePreference(store.themePreference);
    setNotificationsEnabled(store.notificationsEnabled);
    setAudioEnabled(store.audioEnabled);
    setElevenLabsApiKey(store.elevenLabsApiKey);
  }, [
    store.isHydrated,
    store.serverUrl,
    store.username,
    store.password,
    store.themePreference,
    store.notificationsEnabled,
    store.audioEnabled,
    store.elevenLabsApiKey,
  ]);

  const handleSave = async () => {
    setSaveError(null);
    store.setServerUrl(serverUrl.trim());
    store.setUsername(username.trim());
    store.setPassword(password);
    store.setThemePreference(themePreference);
    store.setNotificationsEnabled(notificationsEnabled);
    store.setAudioEnabled(audioEnabled);
    store.setElevenLabsApiKey(elevenLabsApiKey.trim());
    try {
      await store.saveToPersistence();
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    } catch (_err) {
      setSaveError(store.saveError ?? 'Failed to save settings.');
    }
  };

  const handleTestConnection = async () => {
    const config = buildConfig({
      serverUrl,
      username,
      password,
    });

    if (!config) {
      connection.setState('offline');
      connection.setError('Enter a valid server URL, username, and password before testing.');
      return;
    }

    connection.setState('connecting');
    setIsTestingConnection(true);
    try {
      await verifyAuth(config);
      connection.setState('connected');
      connection.resetReconnect();
    } catch (err) {
      if (err instanceof OpenCodeAuthError) {
        connection.setState('authFailed');
        connection.setError('Authentication failed. Check your username and password.');
      } else if (err instanceof OpenCodeNetworkError) {
        connection.setState('offline');
        connection.setError('Could not reach the server. Check the URL, Wi‑Fi, and server status.');
      } else if (err instanceof Error) {
        connection.setState('offline');
        connection.setError(err.message);
      } else {
        connection.setState('offline');
        connection.setError('Unknown connection test failure.');
      }
    } finally {
      setIsTestingConnection(false);
    }
  };

  const isValidUrl = serverUrl.trim() === '' || /^https?:\/\//.test(serverUrl.trim());
  const connectionMessage = connectionCopy(connection.state, connection.lastError);
  const showConnectionBanner = Boolean(connectionMessage) && (connection.state !== 'offline' || connection.lastError);
  const showSaveErrorBanner = !!saveError;
  const hasSpeechToTextKey = hasElevenLabsApiKey(elevenLabsApiKey);

  return (
    <>
      <Stack.Screen options={{ title: 'Settings' }} />
      <ScrollView
        style={[styles.container, { backgroundColor: theme.colors.background }]}
        contentContainerStyle={styles.content}
        keyboardShouldPersistTaps="handled"
      >
        <Text variant="headlineSmall" style={{ color: theme.colors.primary }}>
          Server
        </Text>

        {showSaveErrorBanner && saveError && (
          <Banner
            visible={true}
            actions={[
              {
                label: 'Dismiss',
                onPress: () => setSaveError(null),
              },
            ]}
            icon="alert-circle"
          >
            {saveError}
          </Banner>
        )}

        {showConnectionBanner && connectionMessage && (
          <Banner
            visible={true}
            icon={connection.state === 'connected' ? 'check-circle' : 'connection'}
            actions={
              connection.lastError
                ? [
                    {
                      label: 'Dismiss',
                      onPress: () => connection.setError(null),
                    },
                  ]
                : []
            }
          >
            {connectionMessage}
          </Banner>
        )}

        <TextInput
          label="Server URL"
          value={serverUrl}
          onChangeText={setServerUrl}
          placeholder="https://your-server.example.com"
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="url"
          style={styles.input}
        />
        {!isValidUrl && (
          <HelperText type="error">URL must start with http:// or https://</HelperText>
        )}

        <TextInput
          label="Username"
          value={username}
          onChangeText={setUsername}
          autoCapitalize="none"
          autoCorrect={false}
          style={styles.input}
        />

        <TextInput
          label="Password"
          value={password}
          onChangeText={setPassword}
          secureTextEntry
          style={styles.input}
        />

        <Button
          mode="outlined"
          onPress={handleTestConnection}
          style={styles.testButton}
          disabled={!isValidUrl || isTestingConnection}
          icon="connection"
        >
          {isTestingConnection ? 'Testing Connection…' : 'Test Connection'}
        </Button>
        {isTestingConnection && <ActivityIndicator animating={true} style={styles.testingSpinner} />}

        <Text variant="headlineSmall" style={[styles.sectionTitle, { color: theme.colors.primary }]}> 
          Appearance
        </Text>

        <SegmentedButtons
          value={themePreference}
          onValueChange={(v) => setThemePreference(v as ThemePreference)}
          buttons={[
            { value: 'light', label: 'Light' },
            { value: 'dark', label: 'Dark' },
            { value: 'system', label: 'System' },
          ]}
          style={styles.segmented}
        />

        <Text variant="headlineSmall" style={[styles.sectionTitle, { color: theme.colors.primary }]}>
          Preferences
        </Text>

        <View style={styles.row}>
          <Text variant="bodyLarge">Notifications</Text>
          <Switch
            value={notificationsEnabled}
            onValueChange={setNotificationsEnabled}
          />
        </View>

        <View style={styles.row}>
          <Text variant="bodyLarge">Audio</Text>
          <Switch
            value={audioEnabled}
            onValueChange={setAudioEnabled}
          />
        </View>

        <TextInput
          label="ElevenLabs API Key"
          value={elevenLabsApiKey}
          onChangeText={setElevenLabsApiKey}
          placeholder="sk_..."
          autoCapitalize="none"
          autoCorrect={false}
          secureTextEntry
          style={styles.input}
        />
        <HelperText type={hasSpeechToTextKey ? 'info' : 'error'} visible={true}>
          {hasSpeechToTextKey
            ? 'Voice input is enabled. Assistant replies still fall back to device speech when needed.'
            : MISSING_ELEVENLABS_API_KEY_MESSAGE}
        </HelperText>

        <Button
          mode="contained"
          onPress={handleSave}
          style={styles.saveButton}
          disabled={!isValidUrl}
        >
          {saved ? 'Saved!' : 'Save Settings'}
        </Button>
      </ScrollView>
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    padding: 24,
    gap: 12,
  },
  input: {
    marginTop: 8,
  },
  sectionTitle: {
    marginTop: 24,
    marginBottom: 8,
  },
  segmented: {
    marginTop: 8,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 12,
    marginBottom: 12,
  },
  saveButton: {
    marginTop: 24,
  },
  testButton: {
    marginTop: 12,
  },
  testingSpinner: {
    marginTop: 8,
  },
});
