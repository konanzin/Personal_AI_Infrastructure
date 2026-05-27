/**
 * Audio ElevenLabs
 *
 * STT/TTS abstraction layer using ElevenLabs as the primary provider.
 *
 * Current implementation provides:
 * - AudioRecorder interface for capture abstraction
 * - MockAudioRecorder for development/testing (no native deps required)
 * - ElevenLabsTranscriber for STT via ElevenLabs API
 *
 * TODO(M6-full): Replace MockAudioRecorder with ExpoAudioRecorder
 *                once expo-av is added to the project.
 */

// ------------------------------------------------------------------
// Errors
// ------------------------------------------------------------------

export class AudioCaptureError extends Error {
  constructor(
    message: string,
    public readonly code: 'permission_denied' | 'recording_failed' | 'transcoding_failed' | 'cancelled'
  ) {
    super(message);
    this.name = 'AudioCaptureError';
  }
}

export class TranscriptionError extends Error {
  constructor(
    message: string,
    public readonly code: 'network' | 'empty_result' | 'invalid_api_key' | 'unsupported_format'
  ) {
    super(message);
    this.name = 'TranscriptionError';
  }
}

export const MISSING_ELEVENLABS_API_KEY_MESSAGE =
  'Voice input needs an ElevenLabs API key. Add one in Settings. Assistant playback still falls back to your device voice.';

export function hasElevenLabsApiKey(apiKey?: string | null): boolean {
  return Boolean(apiKey?.trim());
}

// ------------------------------------------------------------------
// Types
// ------------------------------------------------------------------

export type VoiceState =
  | 'idle'
  | 'listening'
  | 'transcribing'
  | 'reviewing'
  | 'sending'
  | 'speaking'
  | 'cancelled'
  | 'error';

export type RecordingStatus =
  | { status: 'idle' }
  | { status: 'recording'; durationMs: number }
  | { status: 'stopped'; uri: string; durationMs: number }
  | { status: 'error'; error: string };

export type TranscriptionResult = {
  text: string;
  confidence?: number;
  language?: string;
};

export type AudioConfig = {
  apiKey?: string;
  voiceId?: string;
  modelId?: string;
};

// ------------------------------------------------------------------
// Audio Recorder Interface
// ------------------------------------------------------------------

export interface AudioRecorder {
  start(): Promise<void>;
  stop(): Promise<{ uri: string; durationMs: number }>;
  cancel(): Promise<void>;
  getStatus(): RecordingStatus;
}

// ------------------------------------------------------------------
// Mock Audio Recorder
// ------------------------------------------------------------------

/**
 * Mock recorder that simulates audio capture without native dependencies.
 * Useful for UI development and testing the voice flow before expo-av is wired.
 */
export class MockAudioRecorder implements AudioRecorder {
  private state: RecordingStatus = { status: 'idle' };
  private startTime = 0;
  private intervalId: ReturnType<typeof setInterval> | null = null;

  async start(): Promise<void> {
    if (this.state.status === 'recording') {
      return;
    }
    this.startTime = Date.now();
    this.state = { status: 'recording', durationMs: 0 };

    this.intervalId = setInterval(() => {
      if (this.state.status === 'recording') {
        this.state = {
          status: 'recording',
          durationMs: Date.now() - this.startTime,
        };
      }
    }, 100);
  }

  async stop(): Promise<{ uri: string; durationMs: number }> {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }

    const durationMs = Date.now() - this.startTime;
    const mockUri = `mock://recording-${Date.now()}.m4a`;
    this.state = { status: 'stopped', uri: mockUri, durationMs };

    return { uri: mockUri, durationMs };
  }

  async cancel(): Promise<void> {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
    this.state = { status: 'idle' };
  }

  getStatus(): RecordingStatus {
    return this.state;
  }
}

// ------------------------------------------------------------------
// Expo AV Audio Recorder
// ------------------------------------------------------------------

/**
 * Real audio recorder using expo-av Audio.Recording.
 *
 * Requests microphone permissions, records to a local file, and returns
 * a file URI suitable for ElevenLabs multipart upload.
 */
export class ExpoAudioRecorder implements AudioRecorder {
  private recording: any | null = null;
  private state: RecordingStatus = { status: 'idle' };
  private startTime = 0;

  async start(): Promise<void> {
    if (this.state.status === 'recording') {
      return;
    }

    try {
      const { Audio } = await import('expo-av');

      const permission = await Audio.requestPermissionsAsync();
      if (permission.status !== 'granted') {
        throw new AudioCaptureError(
          'Microphone permission was denied. Enable it in Settings > Privacy > Microphone.',
          'permission_denied'
        );
      }

      const { recording } = await Audio.Recording.createAsync(
        Audio.RecordingOptionsPresets.HIGH_QUALITY
      );

      this.recording = recording;
      this.startTime = Date.now();
      this.state = { status: 'recording', durationMs: 0 };

      recording.setOnRecordingStatusUpdate((status: unknown) => {
        const s = status as { isRecording?: boolean; durationMillis?: number };
        if (s.isRecording && s.durationMillis !== undefined) {
          this.state = {
            status: 'recording',
            durationMs: Math.round(s.durationMillis),
          };
        }
      });
    } catch (err) {
      if (err instanceof AudioCaptureError) {
        throw err;
      }
      throw new AudioCaptureError(
        err instanceof Error ? err.message : 'Failed to start recording.',
        'recording_failed'
      );
    }
  }

  async stop(): Promise<{ uri: string; durationMs: number }> {
    if (!this.recording) {
      throw new AudioCaptureError('No active recording to stop.', 'recording_failed');
    }

    try {
      await this.recording.stopAndUnloadAsync();
      const uri = this.recording.getURI();
      const durationMs = Date.now() - this.startTime;

      if (!uri) {
        throw new AudioCaptureError('Recording produced no file URI.', 'recording_failed');
      }

      this.state = { status: 'stopped', uri, durationMs };
      return { uri, durationMs };
    } catch (err) {
      if (err instanceof AudioCaptureError) {
        throw err;
      }
      throw new AudioCaptureError(
        err instanceof Error ? err.message : 'Failed to stop recording.',
        'recording_failed'
      );
    } finally {
      this.recording = null;
    }
  }

  async cancel(): Promise<void> {
    if (this.recording) {
      try {
        await this.recording.stopAndUnloadAsync();
      } catch {
        // Ignore cleanup errors
      }
      this.recording = null;
    }
    this.state = { status: 'idle' };
  }

  getStatus(): RecordingStatus {
    return this.state;
  }
}

// ------------------------------------------------------------------
// ElevenLabs Transcriber
// ------------------------------------------------------------------

/**
 * ElevenLabs Speech-to-Text client.
 *
 * API docs: https://elevenlabs.io/docs/speech-to-text
 * Endpoint: POST /v1/speech-to-text
 * Accepts: audio file (multipart/form-data)
 * Returns: { text: string, language_code?: string, words?: [...] }
 */
export class ElevenLabsTranscriber {
  private apiKey?: string;
  private baseUrl = 'https://api.elevenlabs.io/v1';

  constructor(config: AudioConfig) {
    this.apiKey = config.apiKey;
  }

  /**
   * Transcribe an audio file.
   *
   * @param audioUri Local file URI or remote URL to the audio file.
   * @param opts Optional overrides (model_id, language_code, etc.)
   */
  async transcribe(
    audioUri: string,
    opts?: { languageCode?: string; tagAudioEvents?: boolean }
  ): Promise<TranscriptionResult> {
    if (!hasElevenLabsApiKey(this.apiKey)) {
      throw new TranscriptionError(MISSING_ELEVENLABS_API_KEY_MESSAGE, 'invalid_api_key');
    }

    const apiKey = this.apiKey as string;

    // In mock/development mode (mock:// URIs), return a placeholder so
    // the UI flow can be exercised without a real API call.
    if (audioUri.startsWith('mock://')) {
      await simulateDelay(800);
      return {
        text: '[Voice input simulated — add ElevenLabs API key in Settings for real STT]',
        confidence: 0.95,
      };
    }

    const url = `${this.baseUrl}/speech-to-text`;

    const formData = new FormData();
    formData.append('model_id', 'scribe_v1');
    if (opts?.languageCode) {
      formData.append('language_code', opts.languageCode);
    }
    if (opts?.tagAudioEvents !== undefined) {
      formData.append('tag_audio_events', String(opts.tagAudioEvents));
    }

    // React Native FormData accepts a { uri, name, type } object for file uploads.
    const fileName = audioUri.split('/').pop() || 'recording.m4a';
    const ext = fileName.split('.').pop()?.toLowerCase() || 'm4a';
    const mimeType =
      ext === 'wav' ? 'audio/wav' :
      ext === 'mp3' ? 'audio/mpeg' :
      ext === 'webm' ? 'audio/webm' :
      'audio/m4a';

    formData.append('file', {
      uri: audioUri,
      name: fileName,
      type: mimeType,
    } as unknown as Blob);

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'xi-api-key': apiKey,
      },
      body: formData,
    });

    if (response.status === 401) {
      throw new TranscriptionError('Invalid ElevenLabs API key.', 'invalid_api_key');
    }

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new TranscriptionError(
        `Transcription failed: HTTP ${response.status} — ${body}`,
        'network'
      );
    }

    const json = (await response.json()) as {
      text: string;
      language_code?: string;
      words?: unknown[];
    };

    if (!json.text || json.text.trim().length === 0) {
      throw new TranscriptionError('Transcription returned empty text.', 'empty_result');
    }

    return {
      text: json.text,
      language: json.language_code,
      confidence: json.words && json.words.length > 0 ? 0.9 : undefined,
    };
  }
}

// ------------------------------------------------------------------
// Convenience: create recorder + transcriber from settings
// ------------------------------------------------------------------

export function createAudioRecorder(): AudioRecorder {
  if (
    typeof navigator !== 'undefined' &&
    'product' in navigator &&
    (navigator as Record<string, unknown>).product === 'ReactNative'
  ) {
    return new ExpoAudioRecorder();
  }
  return new MockAudioRecorder();
}

export function createTranscriber(config: AudioConfig): ElevenLabsTranscriber {
  return new ElevenLabsTranscriber(config);
}

// ------------------------------------------------------------------
// Utilities
// ------------------------------------------------------------------

function simulateDelay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ------------------------------------------------------------------
// TTS Errors
// ------------------------------------------------------------------

export class TTSError extends Error {
  constructor(
    message: string,
    public readonly code: 'network' | 'synthesis_failed' | 'invalid_api_key' | 'playback_failed'
  ) {
    super(message);
    this.name = 'TTSError';
  }
}

// ------------------------------------------------------------------
// TTS Types
// ------------------------------------------------------------------

export type TTSResult = {
  audioBase64: string;
  format: string;
};

// ------------------------------------------------------------------
// TTS Player Interface
// ------------------------------------------------------------------

export interface TTSPlayer {
  play(audioBase64: string, format?: string): Promise<void>;
  stop(): Promise<void>;
  isPlaying(): boolean;
}

// ------------------------------------------------------------------
// ElevenLabs TTS Client
// ------------------------------------------------------------------

/**
 * ElevenLabs Text-to-Speech client.
 *
 * API docs: https://elevenlabs.io/docs/text-to-speech
 * Endpoint: POST /v1/text-to-speech/{voice_id}
 * Returns: audio/mpeg bytes
 */
export class ElevenLabsTTS {
  private apiKey: string;
  private voiceId: string;
  private modelId: string;
  private baseUrl = 'https://api.elevenlabs.io/v1';

  constructor(config: AudioConfig) {
    this.apiKey = config.apiKey ?? '';
    this.voiceId = config.voiceId || '21m00Tcm4TlvDq8ikWAM';
    this.modelId = config.modelId || 'eleven_flash_v2_5';
  }

  /**
   * Synthesize text into speech audio.
   *
   * @param text The text to synthesize.
   * @param opts Optional overrides (voiceId, modelId).
   * @returns Base64-encoded audio and format.
   */
  async synthesize(
    text: string,
    opts?: { voiceId?: string; modelId?: string }
  ): Promise<TTSResult> {
    if (!text || text.trim().length === 0) {
      throw new TTSError('Text to synthesize is empty.', 'synthesis_failed');
    }

    const voiceId = opts?.voiceId || this.voiceId;
    const url = `${this.baseUrl}/text-to-speech/${voiceId}`;

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'xi-api-key': this.apiKey,
        'Content-Type': 'application/json',
        Accept: 'audio/mpeg',
      },
      body: JSON.stringify({
        text: text.trim(),
        model_id: opts?.modelId || this.modelId,
      }),
    });

    if (response.status === 401) {
      throw new TTSError('Invalid ElevenLabs API key.', 'invalid_api_key');
    }

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new TTSError(
        `Synthesis failed: HTTP ${response.status} — ${body}`,
        'synthesis_failed'
      );
    }

    const arrayBuffer = await response.arrayBuffer();
    const audioBase64 = arrayBufferToBase64(arrayBuffer);

    return { audioBase64, format: 'audio/mpeg' };
  }
}

// ------------------------------------------------------------------
// Expo AV TTS Player
// ------------------------------------------------------------------

/**
 * TTS player using expo-av Audio.Sound.
 *
 * Plays base64-encoded audio via data URI.
 */
type ExpoSound = {
  unloadAsync: () => Promise<unknown>;
  stopAsync: () => Promise<unknown>;
  playAsync: () => Promise<unknown>;
  setOnPlaybackStatusUpdate: (cb: (status: unknown) => void) => void;
};

export class ExpoAVTTSPlayer implements TTSPlayer {
  private sound: ExpoSound | null = null;
  private playing = false;

  async play(audioBase64: string, format: string = 'audio/mpeg'): Promise<void> {
    await this.stop();

    const uri = `data:${format};base64,${audioBase64}`;

    try {
      // Lazy-load expo-av to avoid hard dependency at import time.
      const { Audio } = await import('expo-av');

      const { sound } = await Audio.Sound.createAsync(
        { uri },
        { shouldPlay: true }
      );

      this.sound = sound;
      this.playing = true;

      sound.setOnPlaybackStatusUpdate((status: unknown) => {
        const s = status as { isLoaded?: boolean; didJustFinish?: boolean; isPlaying?: boolean };
        if (s.isLoaded && s.didJustFinish) {
          this.playing = false;
        }
        if (s.isLoaded && s.isPlaying === false && !s.didJustFinish) {
          // Stopped externally
          this.playing = false;
        }
      });
    } catch (err) {
      this.playing = false;
      throw new TTSError(
        err instanceof Error ? err.message : 'Audio playback failed',
        'playback_failed'
      );
    }
  }

  async stop(): Promise<void> {
    if (this.sound) {
      try {
        await this.sound.stopAsync();
        await this.sound.unloadAsync();
      } catch {
        // Ignore unload errors
      }
      this.sound = null;
    }
    this.playing = false;
  }

  isPlaying(): boolean {
    return this.playing;
  }
}

// ------------------------------------------------------------------
// Mock TTS Player
// ------------------------------------------------------------------

/**
 * Mock TTS player that simulates playback without native dependencies.
 * Useful for UI development and testing the TTS flow.
 */
export class MockTTSPlayer implements TTSPlayer {
  private playing = false;
  private timeoutId: ReturnType<typeof setTimeout> | null = null;

  async play(audioBase64: string, _format?: string): Promise<void> {
    await this.stop();
    this.playing = true;

    // Simulate a 2-second playback
    this.timeoutId = setTimeout(() => {
      this.playing = false;
    }, 2000);
  }

  async stop(): Promise<void> {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId);
      this.timeoutId = null;
    }
    this.playing = false;
  }

  isPlaying(): boolean {
    return this.playing;
  }
}

// ------------------------------------------------------------------
// Convenience: create TTS + player from settings
// ------------------------------------------------------------------

export function createTTS(config: AudioConfig): ElevenLabsTTS {
  return new ElevenLabsTTS(config);
}

export function createTTSPlayer(): TTSPlayer {
  // Use Expo AV when available; fallback to mock for tests/Node.
  if (typeof navigator !== 'undefined' && 'product' in navigator && (navigator as Record<string, unknown>).product === 'ReactNative') {
    return new ExpoAVTTSPlayer();
  }
  return new MockTTSPlayer();
}

// ------------------------------------------------------------------
// Speech Engine Abstraction (unified TTS facade)
// ------------------------------------------------------------------

export interface SpeechEngine {
  /** Synthesize and play the given text. */
  speak(text: string): Promise<void>;
  /** Stop any active playback. */
  stop(): Promise<void>;
  /** Return true if currently speaking. */
  isSpeaking(): boolean;
}

/** ElevenLabs-backed speech engine. */
export class ElevenLabsSpeechEngine implements SpeechEngine {
  private player: TTSPlayer;
  private playing = false;

  constructor(private config: AudioConfig) {
    this.player = createTTSPlayer();
  }

  async speak(text: string): Promise<void> {
    const tts = createTTS(this.config);
    const result = await tts.synthesize(text);
    this.playing = true;
    await this.player.play(result.audioBase64, result.format);

    // Wait until playback naturally finishes
    return new Promise((resolve) => {
      const interval = setInterval(() => {
        if (!this.player.isPlaying()) {
          clearInterval(interval);
          this.playing = false;
          resolve();
        }
      }, 250);
    });
  }

  async stop(): Promise<void> {
    await this.player.stop();
    this.playing = false;
  }

  isSpeaking(): boolean {
    return this.playing || this.player.isPlaying();
  }
}

/** Local device TTS fallback using expo-speech. */
export class ExpoSpeechEngine implements SpeechEngine {
  private speaking = false;

  async speak(text: string): Promise<void> {
    const Speech = (await import('expo-speech')).default;
    this.speaking = true;

    return new Promise((resolve, reject) => {
      Speech.speak(text, {
        onDone: () => {
          this.speaking = false;
          resolve();
        },
        onStopped: () => {
          this.speaking = false;
          resolve();
        },
        onError: (err: Error) => {
          this.speaking = false;
          reject(new TTSError(err.message || 'Local TTS failed', 'playback_failed'));
        },
      });
    });
  }

  async stop(): Promise<void> {
    const Speech = (await import('expo-speech')).default;
    Speech.stop();
    this.speaking = false;
  }

  isSpeaking(): boolean {
    return this.speaking;
  }
}

/** Create the appropriate speech engine for the environment. */
export function createSpeechEngine(options?: { apiKey?: string; voiceId?: string }): SpeechEngine {
  if (options?.apiKey) {
    return new ElevenLabsSpeechEngine({ apiKey: options.apiKey, voiceId: options.voiceId });
  }
  return new ExpoSpeechEngine();
}

// ------------------------------------------------------------------
// Utilities
// ------------------------------------------------------------------

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}
