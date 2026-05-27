import { create } from 'zustand';
import {
  saveSetting,
  loadSetting,
  saveCredentials,
  loadCredentials,
  clearCredentials,
} from '../lib/persistence';

export type ThemePreference = 'light' | 'dark' | 'system';

interface SettingsStore {
  serverUrl: string;
  username: string;
  password: string;
  themePreference: ThemePreference;
  notificationsEnabled: boolean;
  audioEnabled: boolean;
  elevenLabsApiKey: string;
  isHydrated: boolean;
  loadError: string | null;
  saveError: string | null;

  setServerUrl: (url: string) => void;
  setUsername: (username: string) => void;
  setPassword: (password: string) => void;
  setThemePreference: (pref: ThemePreference) => void;
  setNotificationsEnabled: (enabled: boolean) => void;
  setAudioEnabled: (enabled: boolean) => void;
  setElevenLabsApiKey: (key: string) => void;
  setLoadError: (error: string | null) => void;
  setSaveError: (error: string | null) => void;

  loadFromPersistence: () => Promise<void>;
  saveToPersistence: () => Promise<void>;
  clearAll: () => Promise<void>;
}

export const useSettingsStore = create<SettingsStore>((set, get) => ({
  serverUrl: '',
  username: '',
  password: '',
  themePreference: 'system',
  notificationsEnabled: true,
  audioEnabled: true,
  elevenLabsApiKey: '',
  isHydrated: false,
  loadError: null,
  saveError: null,

  setServerUrl: (url) => set({ serverUrl: url }),
  setUsername: (username) => set({ username }),
  setPassword: (password) => set({ password }),
  setThemePreference: (pref) => set({ themePreference: pref }),
  setNotificationsEnabled: (enabled) => set({ notificationsEnabled: enabled }),
  setAudioEnabled: (enabled) => set({ audioEnabled: enabled }),
  setElevenLabsApiKey: (key) => set({ elevenLabsApiKey: key }),
  setLoadError: (error) => set({ loadError: error }),
  setSaveError: (error) => set({ saveError: error }),

  loadFromPersistence: async () => {
    if (get().isHydrated) {
      return;
    }

    try {
      const [serverUrl, themePref, notifEnabled, audioEnabled, elevenLabsApiKey, creds] = await Promise.all([
        loadSetting('serverUrl'),
        loadSetting('themePreference'),
        loadSetting('notificationsEnabled'),
        loadSetting('audioEnabled'),
        loadSetting('elevenLabsApiKey'),
        loadCredentials(),
      ]);

      set({
        serverUrl: serverUrl ?? '',
        themePreference: (themePref as ThemePreference) ?? 'system',
        notificationsEnabled: notifEnabled !== 'false', // default true when null
        audioEnabled: audioEnabled !== 'false', // default true when null
        elevenLabsApiKey: elevenLabsApiKey ?? '',
        username: creds?.username ?? '',
        password: creds?.password ?? '',
        isHydrated: true,
        loadError: null,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to load settings from secure storage.';
      set({ isHydrated: true, loadError: message });
    }
  },

  saveToPersistence: async () => {
    const { serverUrl, username, password, themePreference, notificationsEnabled, audioEnabled, elevenLabsApiKey } = get();
    try {
      await saveSetting('serverUrl', serverUrl);
      await saveSetting('themePreference', themePreference);
      await saveSetting('notificationsEnabled', String(notificationsEnabled));
      await saveSetting('audioEnabled', String(audioEnabled));
      await saveSetting('elevenLabsApiKey', elevenLabsApiKey);
      await saveCredentials({ username, password });
      set({ saveError: null });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to save settings to secure storage.';
      set({ saveError: message });
      throw new Error(message);
    }
  },

  clearAll: async () => {
    try {
      await clearCredentials();
      await saveSetting('serverUrl', '');
      await saveSetting('themePreference', 'system');
      await saveSetting('notificationsEnabled', 'true');
      await saveSetting('audioEnabled', 'true');
      await saveSetting('elevenLabsApiKey', '');
      set({
        serverUrl: '',
        username: '',
        password: '',
        themePreference: 'system',
        notificationsEnabled: true,
        audioEnabled: true,
        elevenLabsApiKey: '',
        loadError: null,
        saveError: null,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to clear settings from secure storage.';
      set({ saveError: message });
      throw new Error(message);
    }
  },
}));
