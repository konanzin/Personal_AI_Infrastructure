import { create } from 'zustand';
import type { SessionMessage, MessagePart, TextPart } from '@pai/shared-types';
import {
  listMessages,
  promptAsync,
  type ClientConfig,
  OpenCodeAuthError,
  OpenCodeNetworkError,
} from '@pai/opencode-mobile-client';
import { saveDraft, loadDraft, clearDraft } from '../lib/persistence';
import {
  upsertMessageWithReconciliation,
  upsertPartWithDedup,
  applyTextDeltaToParts,
} from './message-store-helpers';
import { mobileTrace } from '../lib/mobile-trace-logger';

interface MessageStore {
  messagesBySession: Record<string, SessionMessage[]>;
  draftsBySession: Record<string, string>;
  isLoading: boolean;
  isRefreshing: boolean;
  isSending: boolean;
  error: string | null;

  loadMessages: (config: ClientConfig, sessionId: string) => Promise<SessionMessage[] | null>;
  refreshMessages: (config: ClientConfig, sessionId: string) => Promise<SessionMessage[] | null>;
  send: (config: ClientConfig, sessionId: string, parts: SessionMessage['parts']) => Promise<SessionMessage | null>;
  addMessage: (sessionId: string, message: SessionMessage) => void;
  removeMessage: (sessionId: string, messageId: string) => void;
  setMessages: (sessionId: string, messages: SessionMessage[]) => void;
  upsertMessage: (sessionId: string, message: SessionMessage) => void;
  upsertMessagePart: (sessionId: string, messageId: string, part: MessagePart) => void;
  applyMessagePartDelta: (sessionId: string, messageId: string, field: string, delta: string) => void;
  setDraft: (sessionId: string, text: string) => void;
  loadDraft: (sessionId: string) => Promise<void>;
  clearDraft: (sessionId: string) => void;
  clearError: () => void;
  reset: () => void;
}

export const useMessageStore = create<MessageStore>((set) => ({
  messagesBySession: {},
  draftsBySession: {},
  isLoading: false,
  isRefreshing: false,
  isSending: false,
  error: null,

  loadMessages: async (config, sessionId) => {
    set({ isLoading: true, error: null });
    try {
      const messages = await listMessages(config, sessionId);
      const deduped = dedupeById(messages);
      set((state) => ({
        messagesBySession: {
          ...state.messagesBySession,
          [sessionId]: deduped,
        },
        isLoading: false,
      }));
      return deduped;
    } catch (err) {
      const message = normalizeError(err);
      set({ error: message, isLoading: false });
      return null;
    }
  },

  refreshMessages: async (config, sessionId) => {
    set({ isRefreshing: true, error: null });
    try {
      const messages = await listMessages(config, sessionId);
      const deduped = dedupeById(messages);
      set((state) => ({
        messagesBySession: {
          ...state.messagesBySession,
          [sessionId]: deduped,
        },
        isRefreshing: false,
      }));
      return deduped;
    } catch (err) {
      const message = normalizeError(err);
      set({ error: message, isRefreshing: false });
      return null;
    }
  },

  send: async (config, sessionId, parts) => {
    set({ isSending: true, error: null });
    mobileTrace('store', 'send:start', { sessionId, partCount: parts.length });

    const tempId = `local-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const optimisticMessage: SessionMessage = {
      id: tempId,
      sessionId,
      role: 'user',
      parts,
      createdAt: new Date().toISOString(),
    };

    set((state) => ({
      messagesBySession: {
        ...state.messagesBySession,
        [sessionId]: [...(state.messagesBySession[sessionId] || []), optimisticMessage],
      },
    }));

    try {
      await promptAsync(config, sessionId, { parts });
      set({ isSending: false });
      mobileTrace('store', 'send:success', { sessionId, tempId });
      return optimisticMessage;
    } catch (err) {
      const message = normalizeError(err);
      mobileTrace('store', 'send:failure', { sessionId, tempId, error: message });
      set((state) => {
        const sessionMessages = state.messagesBySession[sessionId] || [];
        const filtered = sessionMessages.filter((m) => m.id !== tempId);
        return {
          messagesBySession: {
            ...state.messagesBySession,
            [sessionId]: filtered,
          },
          error: message,
          isSending: false,
        };
      });
      return null;
    }
  },

  addMessage: (sessionId, message) =>
    set((state) => ({
      messagesBySession: {
        ...state.messagesBySession,
        [sessionId]: [...(state.messagesBySession[sessionId] || []), message],
      },
    })),

  removeMessage: (sessionId, messageId) =>
    set((state) => {
      const sessionMessages = state.messagesBySession[sessionId] || [];
      const filtered = sessionMessages.filter((m) => m.id !== messageId);
      return {
        messagesBySession: {
          ...state.messagesBySession,
          [sessionId]: filtered,
        },
      };
    }),

  setMessages: (sessionId, messages) =>
    set((state) => ({
      messagesBySession: {
        ...state.messagesBySession,
        [sessionId]: messages,
      },
    })),

  upsertMessage: (sessionId, message) =>
    set((state) => {
      const sessionMessages = state.messagesBySession[sessionId] || [];
      const existingIdx = sessionMessages.findIndex((m) => m.id === message.id);
      const isNew = existingIdx < 0;
      const isReconcile =
        !isNew &&
        message.role === 'user' &&
        sessionMessages[existingIdx]?.id.startsWith('local-');

      mobileTrace('store', 'upsertMessage', {
        sessionId,
        msgId: message.id,
        role: message.role,
        isNew: String(isNew),
        existingIdx: isNew ? -1 : existingIdx,
        isReconcile: String(isReconcile),
        incomingParts: message.parts.length,
      });

      const nextMessages = upsertMessageWithReconciliation(sessionMessages, message);
      return {
        messagesBySession: {
          ...state.messagesBySession,
          [sessionId]: nextMessages,
        },
      };
    }),

  upsertMessagePart: (sessionId, messageId, part) =>
    set((state) => {
      const sessionMessages = state.messagesBySession[sessionId] || [];
      const msgIdx = sessionMessages.findIndex((m) => m.id === messageId);
      if (msgIdx < 0) {
        mobileTrace('store', 'upsertMessagePart', {
          sessionId,
          messageId,
          result: 'target-not-found',
          sessionMsgCount: sessionMessages.length,
          knownIds: sessionMessages.map((m) => m.id).join(','),
        });
        return state;
      }

      const msg = sessionMessages[msgIdx];
      const nextParts = upsertPartWithDedup(msg.parts, part);
      const nextMsg: SessionMessage = { ...msg, parts: nextParts };
      const nextMessages = sessionMessages.map((m, i) => (i === msgIdx ? nextMsg : m));

      mobileTrace('store', 'upsertMessagePart', {
        sessionId,
        messageId,
        result: 'updated',
        oldParts: msg.parts.length,
        newParts: nextParts.length,
      });

      return {
        messagesBySession: {
          ...state.messagesBySession,
          [sessionId]: nextMessages,
        },
      };
    }),

  applyMessagePartDelta: (sessionId, messageId, field, delta) =>
    set((state) => {
      if (field !== 'text' || !delta) return state;
      const sessionMessages = state.messagesBySession[sessionId] || [];
      const msgIdx = sessionMessages.findIndex((m) => m.id === messageId);
      if (msgIdx < 0) {
        mobileTrace('store', 'applyMessagePartDelta', {
          sessionId,
          messageId,
          result: 'target-not-found',
          sessionMsgCount: sessionMessages.length,
          knownIds: sessionMessages.map((m) => m.id).join(','),
        });
        return state;
      }

      const msg = sessionMessages[msgIdx];
      const beforeTextLen = msg.parts
        .filter((p): p is TextPart => p.type === 'text')
        .reduce((sum, p) => sum + (p.text?.length ?? 0), 0);

      const nextParts = applyTextDeltaToParts(msg.parts, delta);
      const afterTextLen = nextParts
        .filter((p): p is TextPart => p.type === 'text')
        .reduce((sum, p) => sum + (p.text?.length ?? 0), 0);

      const nextMsg: SessionMessage = { ...msg, parts: nextParts };
      const nextMessages = sessionMessages.map((m, i) => (i === msgIdx ? nextMsg : m));

      mobileTrace('store', 'applyMessagePartDelta', {
        sessionId,
        messageId,
        result: 'updated',
        role: msg.role,
        beforeTextLen,
        afterTextLen,
        deltaLen: delta.length,
      });

      return {
        messagesBySession: {
          ...state.messagesBySession,
          [sessionId]: nextMessages,
        },
      };
    }),

  setDraft: (sessionId, text) => {
    set((state) => ({
      draftsBySession: { ...state.draftsBySession, [sessionId]: text },
    }));
    saveDraft(sessionId, text).catch(() => {});
  },

  loadDraft: async (sessionId) => {
    const text = await loadDraft(sessionId);
    if (text !== null) {
      set((state) => ({
        draftsBySession: { ...state.draftsBySession, [sessionId]: text },
      }));
    }
  },

  clearDraft: (sessionId) => {
    set((state) => {
      const next = { ...state.draftsBySession };
      delete next[sessionId];
      return { draftsBySession: next };
    });
    clearDraft(sessionId).catch(() => {});
  },

  clearError: () => set({ error: null }),

  reset: () =>
    set({
      messagesBySession: {},
      isLoading: false,
      isRefreshing: false,
      isSending: false,
      error: null,
    }),
}));

function normalizeError(err: unknown): string {
  if (err instanceof OpenCodeAuthError) {
    return 'Authentication failed. Check your credentials in Settings.';
  }
  if (err instanceof OpenCodeNetworkError) {
    return 'Cannot reach the server. Check your network connection.';
  }
  if (err instanceof Error) {
    return err.message;
  }
  return 'An unexpected error occurred.';
}

function dedupeById(messages: SessionMessage[]): SessionMessage[] {
  const seen = new Set<string>();
  return messages.filter((msg) => {
    if (seen.has(msg.id)) return false;
    seen.add(msg.id);
    return true;
  });
}
