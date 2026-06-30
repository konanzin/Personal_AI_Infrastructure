import { existsSync, readFileSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';

export interface EdgeTtsUtterance {
  text: string;
  language?: string;
  voice?: string;
  rate?: string;
  volume?: string;
}

export interface EdgeTtsResolvedConfig {
  text: string;
  language: string;
  voice: string;
  rate: string;
  volume: string;
}

const DEFAULT_VOICES: Record<string, string> = {
  'pt-BR': 'pt-BR-FranciscaNeural',
  'en-US': 'en-US-AvaNeural',
};

const DEFAULT_VOICE_CONFIG_PATH = join(homedir(), '.config', 'opencode', 'PAI', 'USER', 'Config', 'voice.env');

export function sanitizeForSpeech(text: unknown): string {
  if (typeof text !== 'string') return '';
  return text
    .replace(/<think>[\s\S]*?<\/think>/gi, ' ')
    .replace(/<\/?think>/gi, ' ')
    .replace(/<reflection>[\s\S]*?<\/reflection>/gi, ' ')
    .replace(/<\/?reflection>/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function normalizeLanguage(language: unknown): string {
  if (typeof language !== 'string') return 'en-US';
  const raw = language.trim().replace(/_/g, '-');
  if (!raw) return 'en-US';
  const [code, region] = raw.split('-');
  const lowerCode = code.toLowerCase();
  if (lowerCode === 'pt') return `pt-${(region || 'BR').toUpperCase()}`;
  if (lowerCode === 'en') return `en-${(region || 'US').toUpperCase()}`;
  return raw;
}

function envKeyForLanguage(language: string): string {
  return language.toUpperCase().replace(/[^A-Z0-9]/g, '_');
}

export function parseVoiceEnv(content: string): Record<string, string> {
  const config: Record<string, string> = {};
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const match = line.match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match) continue;
    let value = match[2].trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    config[match[1]] = value;
  }
  return config;
}

function loadVoiceEnv(env: Record<string, string | undefined>): Record<string, string> {
  const configPath = env.PAI_EDGE_TTS_CONFIG || env.PAI_VOICE_CONFIG || DEFAULT_VOICE_CONFIG_PATH;
  if (!configPath || !existsSync(configPath)) return {};
  try {
    return parseVoiceEnv(readFileSync(configPath, 'utf-8'));
  } catch {
    return {};
  }
}

function resolveRuntimeEnv(env: Record<string, string | undefined>): Record<string, string | undefined> {
  if (env !== process.env) return env;
  return { ...loadVoiceEnv(env), ...env };
}

export function resolveVoiceEnabled(env: Record<string, string | undefined> = process.env): boolean {
  env = resolveRuntimeEnv(env);
  const raw = env.PAI_VOICE_ENABLED || env.PAI_EDGE_TTS_ENABLED;
  return !/^(0|false|no|off)$/i.test((raw || 'true').trim());
}

export function resolveVoice(language: string, env: Record<string, string | undefined> = process.env): string {
  env = resolveRuntimeEnv(env);
  const normalized = normalizeLanguage(language);
  const keyed = env[`PAI_EDGE_TTS_VOICE_${envKeyForLanguage(normalized)}`];
  if (keyed) return keyed;
  if (normalized in DEFAULT_VOICES) return DEFAULT_VOICES[normalized];
  if (normalized.toLowerCase().startsWith('pt-')) return DEFAULT_VOICES['pt-BR'];
  if (normalized.toLowerCase().startsWith('en-')) return DEFAULT_VOICES['en-US'];
  return env.PAI_EDGE_TTS_DEFAULT_VOICE || DEFAULT_VOICES['en-US'];
}

export function parseSpeakerLine(line: string): EdgeTtsUtterance | null {
  const trimmed = line.trim();
  if (!trimmed) return null;

  if (trimmed.startsWith('{')) {
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === 'object') {
        const text = sanitizeForSpeech((parsed as Record<string, unknown>).text);
        if (!text) return null;
        return {
          text,
          language: normalizeLanguage((parsed as Record<string, unknown>).language),
          voice: typeof (parsed as Record<string, unknown>).voice === 'string' ? (parsed as Record<string, string>).voice : undefined,
          rate: typeof (parsed as Record<string, unknown>).rate === 'string' ? (parsed as Record<string, string>).rate : undefined,
          volume: typeof (parsed as Record<string, unknown>).volume === 'string' ? (parsed as Record<string, string>).volume : undefined,
        };
      }
    } catch {
      // Fall back to treating malformed JSON-ish input as plain text.
    }
  }

  const text = sanitizeForSpeech(trimmed);
  return text ? { text } : null;
}

export function resolveEdgeTtsConfig(
  utterance: EdgeTtsUtterance,
  env: Record<string, string | undefined> = process.env,
): EdgeTtsResolvedConfig {
  env = resolveRuntimeEnv(env);
  const language = normalizeLanguage(utterance.language || env.PAI_EDGE_TTS_LANGUAGE || env.PAI_VOICE_LANGUAGE || 'en-US');
  return {
    text: sanitizeForSpeech(utterance.text),
    language,
    voice: utterance.voice || resolveVoice(language, env),
    rate: utterance.rate || env.PAI_EDGE_TTS_RATE || '+15%',
    volume: utterance.volume || env.PAI_EDGE_TTS_VOLUME || '+0%',
  };
}
