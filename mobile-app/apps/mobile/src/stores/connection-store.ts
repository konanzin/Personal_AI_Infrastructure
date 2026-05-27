import { create } from 'zustand';
import { ConnectionState } from '@pai/shared-types';
import { verifyAuth, type ClientConfig } from '@pai/opencode-mobile-client';

interface ConnectionStore {
  state: ConnectionState;
  lastError: string | null;
  reconnectAttempts: number;

  setState: (state: ConnectionState) => void;
  setError: (error: string | null) => void;
  setStreaming: () => void;
  setStale: () => void;
  setReconnecting: () => void;
  setConnected: () => void;
  setOffline: (error?: string) => void;
  incrementReconnect: () => void;
  resetReconnect: () => void;
  checkConnection: (config: ClientConfig) => Promise<void>;
}

export const useConnectionStore = create<ConnectionStore>((set, get) => ({
  state: 'offline',
  lastError: null,
  reconnectAttempts: 0,

  setState: (state) => set({ state, lastError: null }),
  setError: (error) => set({ lastError: error }),

  setStreaming: () => {
    const current = get().state;
    if (current !== 'streaming') {
      set({ state: 'streaming', lastError: null });
    }
  },

  setStale: () => {
    const current = get().state;
    if (current === 'connected' || current === 'streaming') {
      set({ state: 'stale', lastError: null });
    }
  },

  setReconnecting: () => {
    const current = get().state;
    if (current !== 'reconnecting') {
      set((s) => ({
        state: 'reconnecting',
        lastError: null,
        reconnectAttempts: s.reconnectAttempts + 1,
      }));
    }
  },

  setConnected: () => {
    set({ state: 'connected', lastError: null, reconnectAttempts: 0 });
  },

  setOffline: (error) => {
    set({ state: 'offline', lastError: error || null });
  },

  incrementReconnect: () => set((s) => ({ reconnectAttempts: s.reconnectAttempts + 1 })),
  resetReconnect: () => set({ reconnectAttempts: 0, lastError: null }),

  checkConnection: async (config) => {
    const current = get().state;
    if (current === 'connecting' || current === 'streaming') return;

    set({ state: 'connecting', lastError: null });
    try {
      await verifyAuth(config);
      set({ state: 'connected', lastError: null, reconnectAttempts: 0 });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Connection check failed';
      set({ state: 'offline', lastError: message });
    }
  },
}));
