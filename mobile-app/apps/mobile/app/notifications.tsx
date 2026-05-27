import { View, StyleSheet } from 'react-native';
import { Text, Button, useTheme } from 'react-native-paper';
import { useRouter, Stack } from 'expo-router';

export default function NotificationsScreen() {
  const theme = useTheme();
  const router = useRouter();

  return (
    <>
      <Stack.Screen options={{ title: 'Notifications' }} />
      <View style={[styles.container, { backgroundColor: theme.colors.background }]}>
        <Text variant="headlineSmall" style={{ color: theme.colors.primary }}>
          Notifications
        </Text>
        <Text variant="bodyMedium" style={[styles.subtitle, { color: theme.colors.onSurfaceVariant }]}>
          Your notification center will appear here. For now, this is a placeholder screen.
        </Text>
        <Button mode="contained" onPress={() => router.back()} style={styles.button}>
          Go Back
        </Button>
      </View>
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  subtitle: {
    marginTop: 12,
    textAlign: 'center',
    marginBottom: 32,
  },
  button: {
    width: '100%',
    maxWidth: 280,
  },
});
