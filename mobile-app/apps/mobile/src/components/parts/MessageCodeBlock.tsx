import { StyleSheet, View } from 'react-native';
import { Text, useTheme } from 'react-native-paper';

type Props = {
  language: string;
  code: string;
};

export function MessageCodeBlock({ language, code }: Props) {
  const theme = useTheme();
  const normalizedCode = code.trim();
  const lines = normalizedCode.split('\n');

  return (
    <View style={[styles.container, { backgroundColor: theme.colors.surfaceVariant }]}> 
      <Text variant="labelSmall" style={{ color: theme.colors.onSurfaceVariant }}>
        {language || 'code'}
      </Text>
      <View style={styles.codeWrapper}>
        {lines.map((line, index) => (
          <Text key={`${index}-${line}`} style={[styles.code, { color: theme.colors.onSurfaceVariant }]}>
            {line || ' '}
          </Text>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    borderRadius: 12,
    padding: 12,
    gap: 8,
    overflow: 'hidden',
    maxWidth: '100%',
  },
  codeWrapper: {
    maxWidth: '100%',
    overflow: 'hidden',
    gap: 0,
  },
  code: {
    fontSize: 13,
    lineHeight: 18,
    marginVertical: 0,
    paddingVertical: 0,
  },
});
