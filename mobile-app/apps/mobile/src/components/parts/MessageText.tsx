import Markdown from 'react-native-markdown-display';
import { StyleSheet } from 'react-native';
import { useTheme } from 'react-native-paper';

type Props = {
  text: string;
};

export function MessageText({ text }: Props) {
  const theme = useTheme();

  const markdownStyles = {
    body: {
      color: theme.colors.onSurface,
      fontSize: 15,
      lineHeight: 22,
    },
    heading1: {
      color: theme.colors.onSurface,
      fontSize: 20,
      lineHeight: 28,
      fontWeight: '600' as const,
      marginVertical: 8,
    },
    heading2: {
      color: theme.colors.onSurface,
      fontSize: 18,
      lineHeight: 26,
      fontWeight: '600' as const,
      marginVertical: 6,
    },
    heading3: {
      color: theme.colors.onSurface,
      fontSize: 16,
      lineHeight: 24,
      fontWeight: '600' as const,
      marginVertical: 4,
    },
    strong: {
      color: theme.colors.onSurface,
      fontWeight: '700' as const,
    },
    em: {
      color: theme.colors.onSurface,
      fontStyle: 'italic' as const,
    },
    link: {
      color: theme.colors.primary,
    },
    code_inline: {
      color: theme.colors.onSurface,
      backgroundColor: theme.colors.surfaceVariant,
      fontFamily: 'monospace',
      fontSize: 13,
      paddingHorizontal: 4,
      paddingVertical: 2,
      borderRadius: 4,
    },
    bullet_list: {
      marginVertical: 4,
    },
    ordered_list: {
      marginVertical: 4,
    },
    list_item: {
      marginVertical: 2,
    },
    paragraph: {
      marginVertical: 4,
    },
  };

  return (
    <Markdown style={markdownStyles}>
      {text}
    </Markdown>
  );
}
