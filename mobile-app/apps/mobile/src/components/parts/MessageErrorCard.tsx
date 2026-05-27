import { StyleSheet, View } from 'react-native';
import { Chip, Text, useTheme } from 'react-native-paper';

type Props = {
  message: string;
  code?: string;
};

export function MessageErrorCard({ message, code }: Props) {
  const theme = useTheme();

  return (
    <View style={[styles.card, { backgroundColor: theme.colors.errorContainer }]}> 
      <Chip icon="alert" compact style={styles.chip}>
        Error
      </Chip>
      {code ? <Text variant="labelMedium">Code: {code}</Text> : null}
      <Text variant="bodyMedium">{message}</Text>
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
});
