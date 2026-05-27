import { StyleSheet, View } from 'react-native';
import { Chip, Text, useTheme } from 'react-native-paper';

type Props = {
  action: string;
  resource: string;
  description: string;
};

export function PermissionRequestCard({ action, resource, description }: Props) {
  const theme = useTheme();

  return (
    <View style={[styles.card, { backgroundColor: theme.colors.errorContainer }]}> 
      <Chip icon="shield-alert" compact style={styles.chip}>
        Permission Needed
      </Chip>
      <Text variant="titleSmall">{action}</Text>
      <Text variant="bodyMedium">Resource: {resource}</Text>
      <Text variant="bodySmall">{description}</Text>
      <Text variant="labelSmall">Response actions will be wired in the next slice.</Text>
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
