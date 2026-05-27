import * as SecureStore from 'expo-secure-store';

const KEY_PREFIX = 'pai_';

function key(name: string): string {
  return `${KEY_PREFIX}${name}`;
}

export async function saveSetting(name: string, value: string): Promise<void> {
  await SecureStore.setItemAsync(key(name), value);
}

export async function loadSetting(name: string): Promise<string | null> {
  return await SecureStore.getItemAsync(key(name));
}

export async function deleteSetting(name: string): Promise<void> {
  try {
    await SecureStore.deleteItemAsync(key(name));
  } catch (err) {
    console.warn(`Failed to delete setting "${name}":`, err);
  }
}

export async function saveDraft(sessionId: string, text: string): Promise<void> {
  try {
    await SecureStore.setItemAsync(key(`draft_${sessionId}`), text);
  } catch (err) {
    console.warn(`Failed to save draft for session "${sessionId}":`, err);
  }
}

export async function loadDraft(sessionId: string): Promise<string | null> {
  try {
    return await SecureStore.getItemAsync(key(`draft_${sessionId}`));
  } catch (err) {
    console.warn(`Failed to load draft for session "${sessionId}":`, err);
    return null;
  }
}

export async function clearDraft(sessionId: string): Promise<void> {
  try {
    await SecureStore.deleteItemAsync(key(`draft_${sessionId}`));
  } catch (err) {
    console.warn(`Failed to clear draft for session "${sessionId}":`, err);
  }
}

export interface Credentials {
  username: string;
  password: string;
}

export async function saveCredentials(creds: Credentials): Promise<void> {
  await saveSetting('username', creds.username);
  await saveSetting('password', creds.password);
}

export async function loadCredentials(): Promise<Credentials | null> {
  const [username, password] = await Promise.all([
    loadSetting('username'),
    loadSetting('password'),
  ]);
  if (username && password) {
    return { username, password };
  }
  return null;
}

export async function clearCredentials(): Promise<void> {
  await Promise.all([
    deleteSetting('username'),
    deleteSetting('password'),
  ]);
}
