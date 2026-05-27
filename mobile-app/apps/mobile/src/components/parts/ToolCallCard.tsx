import { StyleSheet, View } from 'react-native';
import { Chip, Text, useTheme } from 'react-native-paper';

type Props = {
  toolName: string;
  args: Record<string, unknown>;
};

export function ToolCallCard({ toolName, args }: Props) {
  const theme = useTheme();

  return (
    <View style={[styles.card, { backgroundColor: theme.colors.secondaryContainer }]}> 
      <Chip icon="tools" compact style={styles.chip}>
        Tool Call
      </Chip>
      <Text variant="titleSmall">{toolName}</Text>
      <Text selectable style={[styles.payload, { color: theme.colors.onSecondaryContainer }]}>
        {JSON.stringify(args, null, 2)}
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
