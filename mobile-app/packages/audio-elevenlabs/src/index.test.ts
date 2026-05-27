import { describe, expect, test } from 'bun:test';
import {
  ExpoSpeechEngine,
  ElevenLabsTranscriber,
  ElevenLabsSpeechEngine,
  MISSING_ELEVENLABS_API_KEY_MESSAGE,
  TranscriptionError,
  createSpeechEngine,
  hasElevenLabsApiKey,
} from './index';

describe('hasElevenLabsApiKey', () => {
  test('returns false for empty values', () => {
    expect(hasElevenLabsApiKey('')).toBe(false);
    expect(hasElevenLabsApiKey('   ')).toBe(false);
    expect(hasElevenLabsApiKey(undefined)).toBe(false);
    expect(hasElevenLabsApiKey(null)).toBe(false);
  });

  test('returns true for a trimmed key', () => {
    expect(hasElevenLabsApiKey('  sk_test_123  ')).toBe(true);
  });
});

describe('ElevenLabsTranscriber', () => {
  test('fails fast with friendly guidance when key is missing', async () => {
    const transcriber = new ElevenLabsTranscriber({ apiKey: '' });

    await expect(transcriber.transcribe('file:///tmp/voice.m4a')).rejects.toMatchObject({
      message: MISSING_ELEVENLABS_API_KEY_MESSAGE,
      code: 'invalid_api_key',
    } satisfies Partial<TranscriptionError>);
  });
});

describe('createSpeechEngine', () => {
  test('returns ExpoSpeechEngine when key is missing', () => {
    expect(createSpeechEngine()).toBeInstanceOf(ExpoSpeechEngine);
  });

  test('returns ElevenLabsSpeechEngine when key is present', () => {
    expect(createSpeechEngine({ apiKey: 'sk_test_123' })).toBeInstanceOf(ElevenLabsSpeechEngine);
  });
});
