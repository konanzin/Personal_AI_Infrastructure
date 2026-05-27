import { create } from 'zustand';
import type { SessionSummary, Session } from '@pai/shared-types';
import {
  listSessions,
  getSession,
  createSession,
  type ClientConfig,
  OpenCodeAuthError,
  OpenCodeNetworkError,
} from '@pai/opencode-mobile-client';

interface SessionStore {
  sessions: SessionSummary[];
  activeSession: Session | null;
  isLoading: boolean;
  isRefreshing: boolean;
  error: string | null;
  isConfigured: boolean;

  setConfigured: (configured: boolean) => void;
  loadSessions: (config: ClientConfig) => Promise<void>;
  loadSession: (config: ClientConfig, sessionId: string) => Promise<void>;
  refreshSessions: (config: ClientConfig) => Promise<void>;
  refreshSession: (config: ClientConfig, sessionId: string) => Promise<void>;
  createNewSession: (config: ClientConfig, title?: string) => Promise<Session | null>;
  clearError: () => void;
  reset: () => void;
}

export const useSessionStore = create<SessionStore>((set) => ({
  sessions: [],
  activeSession: null,
  isLoading: false,
  isRefreshing: false,
  error: null,
  isConfigured: false,

  setConfigured: (configured) => set({ isConfigured: configured }),

  loadSessions: async (config) => {
    set({ isLoading: true, error: null });
    try {
      const sessions = await listSessions(config);
      set({ sessions, isLoading: false, isConfigured: true });
    } catch (err) {
      const message = normalizeError(err);
      set({ error: message, isLoading: false });
    }
  },

  loadSession: async (config, sessionId) => {
    set({ isLoading: true, error: null });
    try {
      const session = await getSession(config, sessionId);
      set({ activeSession: session, isLoading: false });
    } catch (err) {
      const message = normalizeError(err);
      set({ error: message, isLoading: false });
    }
  },

  createNewSession: async (config, title) => {
    set({ isLoading: true, error: null });
    try {
      const session = await createSession(config, { title });
      set((state) => ({
        sessions: [
          {
            id: session.id,
            title: session.title,
            updatedAt: session.updatedAt,
            messageCount: 0,
          },
          ...state.sessions,
        ],
        activeSession: session,
        isLoading: false,
      }));
      return session;
    } catch (err) {
      const message = normalizeError(err);
      set({ error: message, isLoading: false });
      return null;
    }
  },

  refreshSessions: async (config) => {
    set({ isRefreshing: true, error: null });
    try {
      const sessions = await listSessions(config);
      set({ sessions, isRefreshing: false, isConfigured: true });
    } catch (err) {
      const message = normalizeError(err);
      set({ error: message, isRefreshing: false });
    }
  },

  refreshSession: async (config, sessionId) => {
    set({ isRefreshing: true, error: null });
    try {
      const session = await getSession(config, sessionId);
      set({ activeSession: session, isRefreshing: false });
    } catch (err) {
      const message = normalizeError(err);
      set({ error: message, isRefreshing: false });
    }
  },

  clearError: () => set({ error: null }),

  reset: () =>
    set({
      sessions: [],
      activeSession: null,
      isLoading: false,
      isRefreshing: false,
      error: null,
      isConfigured: false,
    }),
}));

function normalizeError(err: unknown): string {
  if (err instanceof OpenCodeAuthError) {
    return 'Authentication failed. Check your username and password in Settings.';
  }
  if (err instanceof OpenCodeNetworkError) {
    return 'Cannot reach the server. Check your network and server URL in Settings.';
  }
  if (err instanceof Error) {
    return err.message;
  }
  return 'An unexpected error occurred.';
}
