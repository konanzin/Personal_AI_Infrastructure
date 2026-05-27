import { StyleSheet, View } from 'react-native';
import { Chip, Text, useTheme } from 'react-native-paper';

type Props = {
  callId: string;
  result: unknown;
  error?: string;
};

export function ToolResultCard({ callId, result, error }: Props) {
  const theme = useTheme();
  const isError = Boolean(error);

  return (
    <View
      style={[
        styles.card,
        { backgroundColor: isError ? theme.colors.errorContainer : theme.colors.tertiaryContainer },
      ]}
    >
      <Chip icon={isError ? 'alert-circle' : 'check-circle'} compact style={styles.chip}>
        Tool Result
      </Chip>
      <Text variant="bodySmall">Call ID: {callId}</Text>
      <Text selectable style={styles.payload}>
        {error ?? JSON.stringify(result, null, 2)}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    borderRadius: 12,
    padding: 12,
    gap: 8,
  },
  chip: {
    alignSelf: 'flex-start',
  },
  payload: {
    fontFamily: 'monospace',
    fontSize: 12,
    lineHeight: 18,
  },
});
