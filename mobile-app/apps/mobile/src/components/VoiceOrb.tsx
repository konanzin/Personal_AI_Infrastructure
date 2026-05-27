import React from 'react';
import { View, StyleSheet, Pressable, ActivityIndicator } from 'react-native';
import { Text, useTheme } from 'react-native-paper';
import type { VoiceState } from '@pai/audio-elevenlabs';

interface VoiceOrbProps {
  state: VoiceState;
  onPress: () => void;
  durationMs?: number;
  size?: number;
}

export function VoiceOrb({ state, onPress, durationMs = 0, size = 160 }: VoiceOrbProps) {
  const theme = useTheme();

  const isListening = state === 'listening';
  const isTranscribing = state === 'transcribing';
  const isReviewing = state === 'reviewing';
  const isActive = isListening || isTranscribing || isReviewing;

  const orbColor = isListening
    ? theme.colors.error
    : isActive
      ? theme.colors.primary
      : theme.colors.primaryContainer;

  const iconColor = isListening
    ? theme.colors.onError
    : isActive
      ? theme.colors.onPrimary
      : theme.colors.primary;

  const durationText = isListening
    ? `${Math.round(durationMs / 1000)}s`
    : null;

  return (
    <View style={styles.container}>
      <Pressable
        onPress={onPress}
        disabled={isTranscribing || isReviewing}
        style={({ pressed }) => [
          styles.orb,
          {
            width: size,
            height: size,
            borderRadius: size / 2,
            backgroundColor: orbColor,
            opacity: pressed ? 0.8 : 1,
            transform: [{ scale: pressed ? 0.96 : 1 }],
          },
          isListening && styles.pulsingOrb,
        ]}
        accessibilityRole="button"
        accessibilityLabel={
          isListening ? 'Stop recording' : isTranscribing ? 'Transcribing' : 'Start voice input'
        }
      >
        {isTranscribing ? (
          <ActivityIndicator size="large" color={iconColor} />
        ) : (
          <Text
            style={[
              styles.icon,
              { color: iconColor, fontSize: size * 0.35 },
            ]}
          >
            {isListening ? '⏹' : isReviewing ? '✓' : '🎤'}
          </Text>
        )}
      </Pressable>

      {durationText && (
        <Text
          variant="bodyMedium"
          style={[styles.duration, { color: theme.colors.error }]}
        >
          Recording… {durationText}
        </Text>
      )}

      {isReviewing && (
        <Text
          variant="bodySmall"
          style={[styles.hint, { color: theme.colors.onSurfaceVariant }]}
        >
          Review your message below
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    gap: 12,
  },
  orb: {
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
    elevation: 8,
  },
  pulsingOrb: {
    shadowOpacity: 0.3,
    shadowRadius: 20,
    elevation: 12,
  },
  icon: {
    fontWeight: '600',
  },
  duration: {
    marginTop: 4,
    fontWeight: '600',
  },
  hint: {
    marginTop: 2,
  },
});
