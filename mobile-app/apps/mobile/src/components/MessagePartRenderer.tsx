import type { MessagePart } from '@pai/shared-types';
import { StyleSheet, View } from 'react-native';
import { Text } from 'react-native-paper';
import { MessageCodeBlock } from './parts/MessageCodeBlock';
import { MessageErrorCard } from './parts/MessageErrorCard';
import { MessageText } from './parts/MessageText';
import { PermissionRequestCard } from './parts/PermissionRequestCard';
import { QuestionCard } from './parts/QuestionCard';
import { ToolCallCard } from './parts/ToolCallCard';
import { ToolResultCard } from './parts/ToolResultCard';

type Props = {
  part: MessagePart;
};

export function MessagePartRenderer({ part }: Props) {
  switch (part.type) {
    case 'text':
      return <MessageText text={part.text} />;
    case 'code':
      return <MessageCodeBlock language={part.language} code={part.code} />;
    case 'tool_call':
      return <ToolCallCard toolName={part.toolName} args={part.args} />;
    case 'tool_result':
      return <ToolResultCard callId={part.callId} result={part.result} error={part.error} />;
    case 'permission_request':
      return (
        <PermissionRequestCard
          action={part.action}
          resource={part.resource}
          description={part.description}
        />
      );
    case 'question':
      return <QuestionCard text={part.text} options={part.options} />;
    case 'error':
      return <MessageErrorCard message={part.message} code={part.code} />;
    default:
      return (
        <View style={styles.fallback}>
          <Text>Unsupported message part.</Text>
        </View>
      );
  }
}

const styles = StyleSheet.create({
  fallback: {
    padding: 12,
  },
});
