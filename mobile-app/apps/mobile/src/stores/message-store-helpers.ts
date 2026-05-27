import type { SessionMessage, MessagePart, TextPart } from '@pai/shared-types';

/** Reconciliation time window in milliseconds (30 seconds) */
export const RECONCILE_WINDOW_MS = 30000;

/**
 * Check if two message parts are semantically equivalent.
 * Used for deduplication in upsertMessagePart.
 */
export function partsMatch(a: MessagePart, b: MessagePart): boolean {
  if (a.type !== b.type) return false;

  switch (a.type) {
    case 'text':
      return b.type === 'text' && a.text === b.text;
    case 'code':
      return b.type === 'code' && a.language === b.language && a.code === b.code;
    case 'tool_call':
      return b.type === 'tool_call' && a.callId === b.callId;
    case 'tool_result':
      return b.type === 'tool_result' && a.callId === b.callId;
    case 'permission_request':
      return b.type === 'permission_request' && a.requestId === b.requestId;
    case 'question':
      return b.type === 'question' && a.questionId === b.questionId;
    case 'error':
      return (
        b.type === 'error' && a.message === b.message && a.code === b.code
      );
    default:
      return false;
  }
}

/**
 * Find the index of a part that matches the target part.
 * Returns -1 if no match found.
 */
export function findMatchingPartIndex(
  parts: MessagePart[],
  target: MessagePart
): number {
  return parts.findIndex((p) => partsMatch(p, target));
}

/**
 * Check if a message ID is an optimistic local ID.
 */
export function isOptimisticMessage(message: SessionMessage): boolean {
  return message.id.startsWith('local-');
}

/**
 * Determine if an optimistic message can be reconciled with a real message.
 * Safety conditions:
 * - Both are user messages
 * - Same session
 * - The optimistic message has a local-* id
 * - Within the time window
 * - First text part matches
 */
export function canReconcileOptimistic(
  optimistic: SessionMessage,
  real: SessionMessage,
  timeWindowMs: number = RECONCILE_WINDOW_MS
): boolean {
  if (optimistic.role !== 'user' || real.role !== 'user') return false;
  if (optimistic.sessionId !== real.sessionId) return false;
  if (!isOptimisticMessage(optimistic)) return false;

  const optimisticTime = new Date(optimistic.createdAt).getTime();
  const realTime = new Date(real.createdAt).getTime();
  if (Number.isNaN(optimisticTime) || Number.isNaN(realTime)) return false;
  if (Math.abs(realTime - optimisticTime) > timeWindowMs) return false;

  const optText = optimistic.parts.find(
    (p): p is TextPart => p.type === 'text'
  );
  const realText = real.parts.find((p): p is TextPart => p.type === 'text');
  if (!optText || !realText) return false;

  return optText.text === realText.text;
}

/**
 * Sort messages by createdAt ascending (oldest first).
 * Falls back to stable array order if createdAt is invalid or equal.
 */
export function sortByCreatedAt(messages: SessionMessage[]): SessionMessage[] {
  return [...messages].sort((a, b) => {
    const aTime = new Date(a.createdAt).getTime();
    const bTime = new Date(b.createdAt).getTime();
    if (Number.isNaN(aTime) || Number.isNaN(bTime)) return 0;
    return aTime - bTime;
  });
}

/**
 * Count parts that carry displayable information.
 * Empty text parts (e.g., placeholders) are excluded.
 */
function countDisplayableParts(parts: MessagePart[]): number {
  return parts.filter((p) => {
    if (p.type === 'text') {
      return (p.text ?? '').trim().length > 0;
    }
    return true;
  }).length;
}

/**
 * Upsert a message into a session's message array with auto-reconciliation
 * of optimistic local messages and stable ordering.
 */
export function upsertMessageWithReconciliation(
  sessionMessages: SessionMessage[],
  message: SessionMessage
): SessionMessage[] {
  // Try auto-reconciliation for user messages
  if (message.role === 'user') {
    const optimisticIdx = sessionMessages.findIndex((m) =>
      canReconcileOptimistic(m, message)
    );
    if (optimisticIdx >= 0) {
      const nextMessages = sessionMessages.map((m, i) =>
        i === optimisticIdx ? message : m
      );
      return sortByCreatedAt(nextMessages);
    }
  }

  // Standard upsert by id
  const idx = sessionMessages.findIndex((m) => m.id === message.id);
  let nextMessages: SessionMessage[];
  if (idx >= 0) {
    const existing = sessionMessages[idx];
    // Prevent assistant message regression: don't replace a richer message
    // with a sparser one during streaming full-message replacements.
    if (
      existing.role === 'assistant' &&
      message.role === 'assistant' &&
      countDisplayableParts(existing.parts) > countDisplayableParts(message.parts)
    ) {
      nextMessages = sessionMessages;
    } else {
      nextMessages = sessionMessages.map((m, i) => (i === idx ? message : m));
    }
  } else {
    nextMessages = [...sessionMessages, message];
  }
  return sortByCreatedAt(nextMessages);
}

/**
 * Upsert a part into a message's parts array with deduplication.
 * If a matching part exists, it is replaced. Otherwise it is appended.
 */
export function upsertPartWithDedup(
  parts: MessagePart[],
  part: MessagePart
): MessagePart[] {
  const existingIdx = findMatchingPartIndex(parts, part);
  if (existingIdx >= 0) {
    return parts.map((p, i) => (i === existingIdx ? part : p));
  }
  return [...parts, part];
}

/**
 * Apply a text delta to the last text part in a message's parts array.
 * If no text part exists, appends a new one with the delta text.
 * This handles SSE message.part.delta events for field === "text".
 */
export function applyTextDeltaToParts(
  parts: MessagePart[],
  delta: string
): MessagePart[] {
  // Find the last text part to append to (most likely the streaming part)
  let targetIdx = -1;
  for (let i = parts.length - 1; i >= 0; i--) {
    if (parts[i].type === 'text') {
      targetIdx = i;
      break;
    }
  }

  if (targetIdx >= 0) {
    return parts.map((p, i) =>
      i === targetIdx ? { ...p, text: (p as TextPart).text + delta } : p
    );
  }

  // No text part found — create one
  return [...parts, { type: 'text', text: delta } as TextPart];
}
