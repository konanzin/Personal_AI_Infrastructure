import { StyleSheet, View } from 'react-native';
import { Button, Chip, Text, useTheme } from 'react-native-paper';

type Props = {
  text: string;
  options?: string[];
};

export function QuestionCard({ text, options }: Props) {
  const theme = useTheme();

  return (
    <View style={[styles.card, { backgroundColor: theme.colors.primaryContainer }]}> 
      <Chip icon="help-circle" compact style={styles.chip}>
        Question
      </Chip>
      <Text variant="bodyLarge">{text}</Text>
      {options && options.length > 0 && (
        <View style={styles.options}>
          {options.map((option) => (
            <Button key={option} mode="outlined" compact disabled>
              {option}
            </Button>
          ))}
        </View>
      )}
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
  options: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
});
