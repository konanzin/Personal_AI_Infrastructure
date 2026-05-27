import { beforeEach, describe, expect, it, mock } from 'bun:test';

const persistenceMocks = {
  saveSetting: mock(async (_name: string, _value: string) => {}),
  loadSetting: mock(async (_name: string) => null as string | null),
  saveCredentials: mock(async (_creds: { username: string; password: string }) => {}),
  loadCredentials: mock(async () => null as { username: string; password: string } | null),
  clearCredentials: mock(async () => {}),
};

mock.module('../lib/persistence', () => persistenceMocks);

const { useSettingsStore } = await import('./settings-store');

describe('useSettingsStore persistence', () => {
  beforeEach(() => {
    persistenceMocks.saveSetting.mockReset();
    persistenceMocks.loadSetting.mockReset();
    persistenceMocks.saveCredentials.mockReset();
    persistenceMocks.loadCredentials.mockReset();
    persistenceMocks.clearCredentials.mockReset();

    persistenceMocks.saveSetting.mockImplementation(async () => {});
    persistenceMocks.loadSetting.mockImplementation(async () => null);
    persistenceMocks.saveCredentials.mockImplementation(async () => {});
    persistenceMocks.loadCredentials.mockImplementation(async () => null);
    persistenceMocks.clearCredentials.mockImplementation(async () => {});

    useSettingsStore.setState({
      serverUrl: '',
      username: '',
      password: '',
      themePreference: 'system',
      notificationsEnabled: true,
      audioEnabled: true,
      elevenLabsApiKey: '',
      isHydrated: false,
    });
  });

  it('loads persistence only once after hydration', async () => {
    persistenceMocks.loadSetting.mockImplementation(async (name: string) => {
      if (name === 'serverUrl') return 'http://127.0.0.1:4096';
      if (name === 'themePreference') return 'dark';
      if (name === 'notificationsEnabled') return 'false';
      if (name === 'audioEnabled') return 'true';
      if (name === 'elevenLabsApiKey') return 'key-123';
      return null;
    });
    persistenceMocks.loadCredentials.mockImplementation(async () => ({
      username: 'opencode',
      password: 'pai-mobile',
    }));

    await useSettingsStore.getState().loadFromPersistence();
    await useSettingsStore.getState().loadFromPersistence();

    expect(persistenceMocks.loadSetting).toHaveBeenCalledTimes(5);
    expect(persistenceMocks.loadCredentials).toHaveBeenCalledTimes(1);
    expect(useSettingsStore.getState()).toMatchObject({
      serverUrl: 'http://127.0.0.1:4096',
      username: 'opencode',
      password: 'pai-mobile',
      themePreference: 'dark',
      notificationsEnabled: false,
      audioEnabled: true,
      elevenLabsApiKey: 'key-123',
      isHydrated: true,
    });
  });

  it('saves settings sequentially before credentials', async () => {
    const calls: string[] = [];
    persistenceMocks.saveSetting.mockImplementation(async (name: string) => {
      calls.push(name);
    });
    persistenceMocks.saveCredentials.mockImplementation(async () => {
      calls.push('credentials');
    });

    useSettingsStore.setState({
      serverUrl: 'http://127.0.0.1:4096',
      username: 'opencode',
      password: 'pai-mobile',
      themePreference: 'system',
      notificationsEnabled: true,
      audioEnabled: true,
      elevenLabsApiKey: '',
      isHydrated: true,
    });

    await useSettingsStore.getState().saveToPersistence();

    expect(calls).toEqual([
      'serverUrl',
      'themePreference',
      'notificationsEnabled',
      'audioEnabled',
      'elevenLabsApiKey',
      'credentials',
    ]);
  });

  it('sets loadError when persistence load fails', async () => {
    persistenceMocks.loadSetting.mockImplementation(async () => {
      throw new Error('Samsung keystore locked');
    });
    persistenceMocks.loadCredentials.mockImplementation(async () => {
      throw new Error('Samsung keystore locked');
    });

    await useSettingsStore.getState().loadFromPersistence();

    expect(useSettingsStore.getState().isHydrated).toBe(true);
    expect(useSettingsStore.getState().loadError).toBe('Samsung keystore locked');
  });

  it('sets saveError when persistence save fails', async () => {
    persistenceMocks.saveSetting.mockImplementation(async () => {
      throw new Error('Samsung keystore locked');
    });

    useSettingsStore.setState({
      serverUrl: 'http://127.0.0.1:4096',
      username: 'opencode',
      password: 'pai-mobile',
      themePreference: 'system',
      notificationsEnabled: true,
      audioEnabled: true,
      elevenLabsApiKey: '',
      isHydrated: true,
    });

    await expect(useSettingsStore.getState().saveToPersistence()).rejects.toThrow('Samsung keystore locked');
    expect(useSettingsStore.getState().saveError).toBe('Samsung keystore locked');
  });
});
