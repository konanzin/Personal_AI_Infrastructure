import { create } from 'zustand';

export type ThemeMode = 'light' | 'dark';

interface DevicePermissions {
  microphone: boolean;
  notifications: boolean;
  camera: boolean;
}

interface AppStore {
  themeMode: ThemeMode;
  activeRoute: string;
  activeSessionId: string | null;
  devicePermissions: DevicePermissions;

  setThemeMode: (mode: ThemeMode) => void;
  setActiveRoute: (route: string) => void;
  setActiveSessionId: (id: string | null) => void;
  setDevicePermission: (key: keyof DevicePermissions, granted: boolean) => void;
  initializeTheme: (preference: 'light' | 'dark' | 'system') => void;
}

export const useAppStore = create<AppStore>((set) => ({
  themeMode: 'light',
  activeRoute: '/',
  activeSessionId: null,
  devicePermissions: {
    microphone: false,
    notifications: false,
    camera: false,
  },

  setThemeMode: (mode) => set({ themeMode: mode }),
  setActiveRoute: (route) => set({ activeRoute: route }),
  setActiveSessionId: (id) => set({ activeSessionId: id }),
  setDevicePermission: (key, granted) =>
    set((s) => ({
      devicePermissions: { ...s.devicePermissions, [key]: granted },
    })),
  initializeTheme: (preference) => {
    if (preference === 'system') {
      // Default to light; in a real app we'd detect system preference
      set({ themeMode: 'light' });
    } else {
      set({ themeMode: preference });
    }
  },
}));
