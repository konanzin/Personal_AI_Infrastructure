import type { SessionMessage } from '@pai/shared-types';

export function buildPreviewFromMessages(
  messages: SessionMessage[]
): { preview: string; count: number } {
  const count = messages.length;
  const lastText = findLastTextContent(messages);
  return {
    preview: lastText
      ? truncate(lastText, 60)
      : `${count} message${count === 1 ? '' : 's'}`,
    count,
  };
}

function findLastTextContent(messages: SessionMessage[]): string | undefined {
  for (let i = messages.length - 1; i >= 0; i--) {
    const msg = messages[i];
    for (let j = msg.parts.length - 1; j >= 0; j--) {
      const part = msg.parts[j];
      if (part.type === 'text' && part.text.trim()) {
        return part.text.trim();
      }
    }
  }
  return undefined;
}

function truncate(str: string, max: number): string {
  return str.length > max ? str.slice(0, max) + '…' : str;
}
