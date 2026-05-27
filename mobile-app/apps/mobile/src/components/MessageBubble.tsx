import type { SessionMessage } from '@pai/shared-types';
import { StyleSheet, View } from 'react-native';
import { Text, useTheme } from 'react-native-paper';
import { MessagePartRenderer } from './MessagePartRenderer';

type Props = {
  message: SessionMessage;
};

export function MessageBubble({ message }: Props) {
  const theme = useTheme();
  const isUser = message.role === 'user';
  const isAssistant = message.role === 'assistant';

  const bubbleColor = isUser
    ? theme.colors.primaryContainer
    : isAssistant
      ? theme.colors.surfaceVariant
      : theme.colors.secondaryContainer;

  return (
    <View style={[styles.row, isUser ? styles.rowUser : styles.rowAssistant]}>
      <View style={[styles.bubble, { backgroundColor: bubbleColor }]}> 
        <View style={styles.header}>
          <Text variant="labelMedium">{message.role.toUpperCase()}</Text>
          <Text variant="labelSmall">{new Date(message.createdAt).toLocaleTimeString()}</Text>
        </View>
        <View style={styles.parts}>
          {message.parts.map((part, index) => (
            <MessagePartRenderer key={`${message.id}-${part.type}-${index}`} part={part} />
          ))}
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  rowUser: {
    alignItems: 'flex-end',
  },
  rowAssistant: {
    alignItems: 'flex-start',
  },
  bubble: {
    maxWidth: '88%',
    borderRadius: 16,
    padding: 12,
    gap: 10,
    overflow: 'hidden',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 12,
  },
  parts: {
    gap: 8,
  },
});
