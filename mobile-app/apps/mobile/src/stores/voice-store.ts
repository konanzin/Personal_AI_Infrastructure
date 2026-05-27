import { create } from 'zustand';
import {
  VoiceState,
  createAudioRecorder,
  createTranscriber,
  AudioRecorder,
  ElevenLabsTranscriber,
  TranscriptionResult,
  AudioCaptureError,
  TranscriptionError,
  TTSError,
  createSpeechEngine,
  hasElevenLabsApiKey,
  MISSING_ELEVENLABS_API_KEY_MESSAGE,
  type SpeechEngine,
} from '@pai/audio-elevenlabs';

interface VoiceStore {
  state: VoiceState;
  transcription: string | null;
  error: string | null;
  recordingDurationMs: number;
  isSpeaking: boolean;

  /** Start audio recording */
  startRecording: () => Promise<void>;

  /** Stop recording and run transcription */
  stopRecordingAndTranscribe: (apiKey?: string) => Promise<void>;

  /** Confirm transcription — caller should read transcription and send via message store */
  confirmTranscription: () => string | null;

  /** Cancel the current voice flow and reset */
  cancel: () => void;

  /** Reset to idle (clears transcription/error) */
  reset: () => void;

  /** Set transcription manually (e.g. for editing in review) */
  setTranscription: (text: string) => void;

  /** Synthesize and play text via TTS (ElevenLabs if key provided, else local fallback) */
  speak: (text: string, apiKey?: string, voiceId?: string) => Promise<void>;

  /** Stop any active TTS playback */
  stopSpeaking: () => Promise<void>;
}

let recorder: AudioRecorder | null = null;
let speechEngine: SpeechEngine | null = null;

export const useVoiceStore = create<VoiceStore>((set, get) => ({
  state: 'idle',
  transcription: null,
  error: null,
  recordingDurationMs: 0,
  isSpeaking: false,

  startRecording: async () => {
    try {
      get().reset();
      recorder = createAudioRecorder();
      await recorder.start();
      set({ state: 'listening', recordingDurationMs: 0 });

      // Poll duration while recording
      const poll = () => {
        const status = recorder?.getStatus();
        if (status?.status === 'recording') {
          set({ recordingDurationMs: status.durationMs });
          requestAnimationFrame(poll);
        }
      };
      poll();
    } catch (err) {
      const message = normalizeAudioError(err);
      set({ state: 'error', error: message });
    }
  },

  stopRecordingAndTranscribe: async (apiKey) => {
    if (!recorder) {
      set({ state: 'error', error: 'No active recorder.' });
      return;
    }

    if (!hasElevenLabsApiKey(apiKey)) {
      try {
        await recorder.cancel();
      } catch {
        // Ignore recorder cleanup errors for missing-key fallback.
      } finally {
        recorder = null;
      }

      set({
        state: 'error',
        error: MISSING_ELEVENLABS_API_KEY_MESSAGE,
        recordingDurationMs: 0,
      });
      return;
    }

    try {
      const normalizedApiKey = apiKey as string;
      set({ state: 'transcribing' });
      const { uri, durationMs } = await recorder.stop();
      set({ recordingDurationMs: durationMs });

      const transcriber = createTranscriber({ apiKey: normalizedApiKey.trim() });
      const result: TranscriptionResult = await transcriber.transcribe(uri);

      set({
        state: 'reviewing',
        transcription: result.text,
        error: null,
      });
    } catch (err) {
      const message = normalizeAudioError(err);
      set({ state: 'error', error: message });
    } finally {
      recorder = null;
    }
  },

  confirmTranscription: () => {
    const { transcription, state } = get();
    if (state !== 'reviewing' || !transcription) {
      return null;
    }
    set({ state: 'idle', transcription: null, error: null });
    return transcription;
  },

  cancel: () => {
    if (recorder) {
      recorder.cancel().catch(() => {});
      recorder = null;
    }
    set({ state: 'idle', transcription: null, error: null, recordingDurationMs: 0 });
  },

  reset: () => {
    set({ state: 'idle', transcription: null, error: null, recordingDurationMs: 0 });
  },

  setTranscription: (text) => {
    set({ transcription: text });
  },

  speak: async (text, apiKey, voiceId) => {
    if (!text.trim()) return;

    try {
      set({ isSpeaking: true });
      await get().stopSpeaking();

      speechEngine = createSpeechEngine({ apiKey, voiceId });
      await speechEngine.speak(text);

      set({ isSpeaking: false });
    } catch (err) {
      // TTS errors are non-fatal; log and move on
      console.warn('TTS playback failed:', normalizeAudioError(err));
      set({ isSpeaking: false });
    }
  },

  stopSpeaking: async () => {
    try {
      if (speechEngine) {
        await speechEngine.stop();
        speechEngine = null;
      }
    } catch {
      // Ignore cleanup errors
    }
    set({ isSpeaking: false });
  },
}));

function normalizeAudioError(err: unknown): string {
  if (err instanceof AudioCaptureError) {
    return err.message;
  }
  if (err instanceof TranscriptionError) {
    return err.message;
  }
  if (err instanceof TTSError) {
    return err.message;
  }
  if (err instanceof Error) {
    return err.message;
  }
  return 'An unexpected audio error occurred.';
}
