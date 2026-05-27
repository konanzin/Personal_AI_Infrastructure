import {
  View,
  StyleSheet,
  FlatList,
  KeyboardAvoidingView,
  Platform,
  AppState,
  RefreshControl,
} from 'react-native';
import {
  Text,
  Button,
  useTheme,
  Banner,
  ActivityIndicator,
  TextInput,
  Chip,
} from 'react-native-paper';
import { useLocalSearchParams, useRouter, Stack } from 'expo-router';
import { useEffect, useCallback, useRef, useState } from 'react';
import { useMessageStore, useSessionStore, useSettingsStore, useAppStore, useConnectionStore, useVoiceStore } from '../../src/stores';
import type { ClientConfig } from '@pai/opencode-mobile-client';
import {
  subscribeToEvents,
  type EventCallback,
  mapSsePayloadToMessage,
  mapSsePayloadToMessagePart,
  mapSsePayloadToMessagePartDelta,
  deriveSessionStatus,
} from '@pai/opencode-mobile-client';
import type { SessionMessage, TextPart } from '@pai/shared-types';
import { mobileTrace, summarizePayload, summarizeParts } from '../../src/lib/mobile-trace-logger';
import { MessageBubble } from '../../src/components/MessageBubble';
import { DEMO_SESSION_ID, demoMessages, demoSession } from '../../src/demo/demo-session';
import {
  hasElevenLabsApiKey,
  MISSING_ELEVENLABS_API_KEY_MESSAGE,
} from '@pai/audio-elevenlabs';

function buildConfig(settings: {
  serverUrl: string;
  username: string;
  password: string;
}): ClientConfig | null {
  const url = settings.serverUrl.trim();
  if (!url || !settings.username || !settings.password) {
    return null;
  }
  return {
    baseUrl: url,
    username: settings.username,
    password: settings.password,
  };
}

const FALLBACK_REFRESH_DELAY_MS = 4000;
const SSE_THROTTLE_MS = 800;

export default function SessionDetailScreen() {
  const theme = useTheme();
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id: string }>();
  const settings = useSettingsStore();
  const [isAwaitingReply, setIsAwaitingReply] = useState(false);
  const [demoTimeline, setDemoTimeline] = useState<SessionMessage[]>(demoMessages);
  const [sseConnected, setSseConnected] = useState(false);
  const [liveReady, setLiveReady] = useState(false);
  const [hasBeenLiveReady, setHasBeenLiveReady] = useState(false);
  const listRef = useRef<FlatList<SessionMessage>>(null);
  const pollingRunRef = useRef(0);
  const fallbackTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const sseSubRef = useRef<{ unsubscribe: () => void } | null>(null);
  const lastRefreshRef = useRef(0);
  const { activeSession, loadSession, refreshSession } = useSessionStore();
  const {
    messagesBySession,
    draftsBySession,
    isLoading,
    isRefreshing,
    isSending,
    error,
    loadMessages,
    refreshMessages,
    clearError,
    send,
    setMessages,
    upsertMessage,
    upsertMessagePart,
    applyMessagePartDelta,
    setDraft,
    loadDraft,
    clearDraft,
  } = useMessageStore();
  const setActiveSessionId = useAppStore((s) => s.setActiveSessionId);
  const {
    state: connectionState,
    checkConnection,
    setStreaming,
    setStale,
    setReconnecting,
    setConnected,
    setOffline,
  } = useConnectionStore();
  const appStateRef = useRef(AppState.currentState);

  const {
    state: voiceState,
    transcription: voiceTranscription,
    error: voiceError,
    recordingDurationMs,
    isSpeaking,
    startRecording,
    stopRecordingAndTranscribe,
    confirmTranscription,
    cancel: cancelVoice,
    setTranscription: setVoiceTranscription,
    speak,
    stopSpeaking,
  } = useVoiceStore();

  const isDemoSession = id === DEMO_SESSION_ID;
  const config = buildConfig(settings);
  const messages = isDemoSession ? demoTimeline : messagesBySession[id] || [];
  const draft = draftsBySession[id] || '';
  const needsTranscriptionKey =
    settings.audioEnabled && !isDemoSession && !hasElevenLabsApiKey(settings.elevenLabsApiKey);

  // Throttled refresh for SSE events
  const throttledRefresh = useCallback(
    (config: ClientConfig, sessionId: string) => {
      const now = Date.now();
      if (now - lastRefreshRef.current < SSE_THROTTLE_MS) {
        return;
      }
      lastRefreshRef.current = now;
      refreshMessages(config, sessionId);
      refreshSession(config, sessionId);
    },
    [refreshMessages, refreshSession]
  );

  // SSE subscription for real sessions
  useEffect(() => {
    mobileTrace('sse', 'session-screen:sse-effect-start', {
      id: id ?? 'undef',
      isDemoSession: String(isDemoSession),
      configPresent: String(!!config),
      appState: appStateRef.current,
    });

    if (isDemoSession || !config || !id) {
      mobileTrace('sse', 'session-screen:sse-guard-block', {
        reason: isDemoSession ? 'demo' : !config ? 'no-config' : 'no-id',
        id: id ?? 'undef',
        isDemoSession: String(isDemoSession),
        configPresent: String(!!config),
      });
      return;
    }

    if (appStateRef.current !== 'active') {
      mobileTrace('sse', 'session-screen:sse-appstate-block', {
        appState: appStateRef.current,
        id,
      });
      return;
    }

    mobileTrace('sse', 'session-screen:sse-subscribe', {
      id,
      baseUrl: config.baseUrl,
      username: config.username,
    });

    setSseConnected(false);
    setLiveReady(false);
    setHasBeenLiveReady(false);
    setReconnecting();

    const isTerminalStatus = (data: Record<string, unknown> | undefined, originalEvent?: string): boolean => {
      // String status (shallow payload)
      const rawStatus = typeof data?.status === 'string' ? data.status : '';
      if (rawStatus === 'idle' || rawStatus === 'error') return true;

      // Object status: { status: { type: 'idle' | 'error' } }
      const statusObj = typeof data?.status === 'object' && data?.status !== null ? data.status as Record<string, unknown> : undefined;
      const statusType = typeof statusObj?.type === 'string' ? statusObj.type : '';
      if (statusType === 'idle' || statusType === 'error') return true;

      // Nested properties status: { properties: { status: { type: 'idle' | 'error' } } }
      const props = typeof data?.properties === 'object' && data?.properties !== null ? data.properties as Record<string, unknown> : undefined;
      const nestedStatus = typeof props?.status === 'object' && props?.status !== null ? props.status as Record<string, unknown> : undefined;
      const nestedType = typeof nestedStatus?.type === 'string' ? nestedStatus.type : '';
      if (nestedType === 'idle' || nestedType === 'error') return true;

      // Original event fallback
      return originalEvent === 'session.idle';
    };

    const handleEvent: EventCallback = (event) => {
      const eventSessionId = event.sessionId ?? null;

      // Log every incoming SSE event at the screen layer
      mobileTrace('sse', 'session-screen:event', {
        originalEvent: event.originalEvent ?? '',
        normalizedType: event.type,
        sessionId: eventSessionId ?? '',
        payloadShape: summarizePayload(event.data),
      });

      switch (event.type) {
        case 'connected':
          setSseConnected(true);
          setLiveReady(true);
          setHasBeenLiveReady(true);
          setConnected();
          break;
        case 'disconnected':
          setSseConnected(false);
          setLiveReady(false);
          setStale();
          break;
        case 'error': {
          if (eventSessionId === id || eventSessionId === null) {
            setSseConnected(false);
            setLiveReady(false);
            setOffline(typeof event.data === 'string' ? event.data : 'SSE error');
            if (eventSessionId === id) {
              throttledRefresh(config, id);
              setIsAwaitingReply(false);
            }
          }
          break;
        }
        case 'message': {
          if (eventSessionId === id) {
            setStreaming();

            // Try incremental application first
            const payload = event.data;
            if (event.originalEvent === 'message.updated') {
              const message = mapSsePayloadToMessage(payload);
              mobileTrace('sse', 'session-screen:mapper-result', {
                mapper: 'mapSsePayloadToMessage',
                originalEvent: event.originalEvent,
                result: message ? (message.parts.length === 1 && message.parts[0]?.type === 'text' && (message.parts[0] as TextPart).text === '' ? 'shell' : 'full') : 'null',
                msgId: message?.id ?? '',
              });
              if (message) {
                upsertMessage(id, message);
                setIsAwaitingReply(false);
                break; // Skip throttledRefresh
              }
            }

            if (event.originalEvent === 'message.part.updated') {
              const partUpdate = mapSsePayloadToMessagePart(payload);
              mobileTrace('sse', 'session-screen:mapper-result', {
                mapper: 'mapSsePayloadToMessagePart',
                originalEvent: event.originalEvent,
                result: partUpdate ? 'part' : 'null',
                msgId: partUpdate?.messageId ?? '',
              });
              if (partUpdate) {
                upsertMessagePart(id, partUpdate.messageId, partUpdate.part);
                setIsAwaitingReply(false);
                break; // Skip throttledRefresh
              }
            }

            if (event.originalEvent === 'message.part.delta') {
              const deltaUpdate = mapSsePayloadToMessagePartDelta(payload);
              mobileTrace('sse', 'session-screen:mapper-result', {
                mapper: 'mapSsePayloadToMessagePartDelta',
                originalEvent: event.originalEvent,
                result: deltaUpdate ? 'delta' : 'null',
                msgId: deltaUpdate?.messageId ?? '',
                field: deltaUpdate?.field ?? '',
              });
              if (deltaUpdate) {
                applyMessagePartDelta(id, deltaUpdate.messageId, deltaUpdate.field, deltaUpdate.delta);
                setIsAwaitingReply(false);
                break; // Skip throttledRefresh
              }
            }

            // Fallback: throttled refresh for ambiguous or unmapped events
            mobileTrace('sse', 'session-screen:fallback-refresh', {
              reason: 'unmapped-event',
              originalEvent: event.originalEvent ?? '',
            });
            throttledRefresh(config, id);
            setIsAwaitingReply(false);
          }
          break;
        }
        case 'status': {
          if (eventSessionId === id) {
            const data = event.data as Record<string, unknown> | undefined;
            const statusInfo = deriveSessionStatus(data);
            if (statusInfo?.isTerminal) {
              setConnected();
              setIsAwaitingReply(false);
              // Still refresh to ensure full consistency
              throttledRefresh(config, id);
            } else if (isTerminalStatus(data, event.originalEvent)) {
              setConnected();
              throttledRefresh(config, id);
              setIsAwaitingReply(false);
            }
          }
          break;
        }
      }
    };

    const sub = subscribeToEvents(config, handleEvent);
    sseSubRef.current = sub;
    mobileTrace('sse', 'session-screen:sse-subscribed', { id, hasUnsubscribe: String(!!sub.unsubscribe) });

    return () => {
      mobileTrace('sse', 'session-screen:sse-cleanup', { id });
      sub.unsubscribe();
      sseSubRef.current = null;
      setSseConnected(false);
      setLiveReady(false);
      setHasBeenLiveReady(false);
    };
  }, [
    config?.baseUrl,
    config?.username,
    config?.password,
    id,
    isDemoSession,
    throttledRefresh,
    setStreaming,
    setStale,
    setReconnecting,
    setConnected,
    setOffline,
    upsertMessage,
    upsertMessagePart,
    applyMessagePartDelta,
  ]);

  useEffect(() => {
    if (isDemoSession) {
      setDemoTimeline(demoMessages);
      loadDraft(id);
    } else if (id) {
      loadDraft(id);
    }
  }, [id, isDemoSession, loadDraft, clearDraft]);

  // Trace: log screen identity on mount and when id changes
  useEffect(() => {
    mobileTrace('render', 'session-screen:identity', {
      id: id ?? 'undef',
      isDemoSession: String(isDemoSession),
      configPresent: String(!!config),
      sseConnected: String(sseConnected),
      connectionState,
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  useEffect(() => {
    return () => {
      pollingRunRef.current += 1;
    };
  }, []);

  useEffect(() => {
    if (id) {
      setActiveSessionId(id);
    }
    return () => {
      setActiveSessionId(null);
    };
  }, [id, setActiveSessionId]);

  useEffect(() => {
    if (isDemoSession) {
      setMessages(DEMO_SESSION_ID, demoTimeline);
    }
  }, [isDemoSession, demoTimeline, setMessages]);

  useEffect(() => {
    if (messages.length > 0) {
      requestAnimationFrame(() => {
        listRef.current?.scrollToEnd({ animated: true });
      });
    }
  }, [messages.length]);

  // Trace: log summary of last assistant message whenever messages change
  useEffect(() => {
    if (!id || isDemoSession) return;
    const lastAssistant = [...messages]
      .reverse()
      .find((m) => m.role === 'assistant');
    if (lastAssistant) {
      mobileTrace('render', 'session-screen:last-assistant', {
        sessionId: id,
        msgId: lastAssistant.id,
        partsCount: lastAssistant.parts.length,
        partsSummary: summarizeParts(lastAssistant.parts as TextPart[]),
      });
    }
  }, [messages, id, isDemoSession]);

  const lastSpokenMessageIdRef = useRef<string | null>(null);

  useEffect(() => {
    if (!settings.audioEnabled) return;
    if (isDemoSession) return;

    const lastAssistantMessage = [...messages]
      .reverse()
      .find((m) => m.role === 'assistant');

    if (
      lastAssistantMessage &&
      lastAssistantMessage.id !== lastSpokenMessageIdRef.current
    ) {
      const text = lastAssistantMessage.parts
        .filter((p): p is TextPart => p.type === 'text')
        .map((p) => p.text)
        .join(' ');

      if (text.trim()) {
        lastSpokenMessageIdRef.current = lastAssistantMessage.id;
        speak(text, settings.elevenLabsApiKey);
      }
    }
  }, [messages, settings.audioEnabled, settings.elevenLabsApiKey, isDemoSession, speak]);

  useEffect(() => {
    return () => {
      stopSpeaking();
    };
  }, [stopSpeaking]);

  const handleRetry = useCallback(() => {
    if (config && id) {
      loadMessages(config, id);
    }
  }, [config, id, loadMessages]);

  const handleRefresh = useCallback(async () => {
    if (!config || !id || isDemoSession) return;
    await refreshSession(config, id);
    await refreshMessages(config, id);
    await checkConnection(config);
  }, [config, id, isDemoSession, refreshSession, refreshMessages, checkConnection]);

  const handleSend = useCallback(async (overrideText?: string) => {
    const text = (overrideText ?? draft).trim();
    mobileTrace('sse', 'session-screen:handleSend', {
      sessionId: id ?? 'undef',
      textLen: text.length,
      isDemo: String(isDemoSession),
      sseConnected: String(sseConnected),
      liveReady: String(liveReady),
      isAwaitingReply: String(isAwaitingReply),
      isSending: String(isSending),
    });
    if (!id || !text || isSending || isAwaitingReply) {
      return;
    }

    // Block send on real sessions until live-ready
    if (!isDemoSession && config && !liveReady) {
      mobileTrace('sse', 'session-screen:handleSend-blocked', {
        sessionId: id,
        reason: 'not-live-ready',
        liveReady: String(liveReady),
      });
      return;
    }

    if (isDemoSession) {
      const userMessage: SessionMessage = {
        id: `demo-user-${Date.now()}`,
        sessionId: DEMO_SESSION_ID,
        role: 'user',
        createdAt: new Date().toISOString(),
        parts: [{ type: 'text', text }],
      };

      setDemoTimeline((current) => [...current, userMessage]);
      clearDraft(id);
      setIsAwaitingReply(true);

      setTimeout(() => {
        setDemoTimeline((current) => [
          ...current,
          {
            id: `demo-assistant-${Date.now()}`,
            sessionId: DEMO_SESSION_ID,
            role: 'assistant',
            createdAt: new Date().toISOString(),
            parts: [
              {
                type: 'text',
                text: `Demo response to: "${text}". This preview proves the chat UI works locally on-device.`,
              },
            ],
          },
        ]);
        setIsAwaitingReply(false);
      }, 900);
      return;
    }

    if (!config) {
      return;
    }

    const parts: TextPart[] = [{ type: 'text', text }];
    const sent = await send(config, id, parts);
    if (sent) {
      clearDraft(id);
      setIsAwaitingReply(true);

      // If SSE is not active, schedule a single fallback refresh
      if (!sseConnected) {
        if (fallbackTimerRef.current) {
          mobileTrace('sse', 'session-screen:fallback-cancel', { sessionId: id, reason: 'reschedule' });
          clearTimeout(fallbackTimerRef.current);
        }
        mobileTrace('sse', 'session-screen:fallback-schedule', { sessionId: id, delayMs: FALLBACK_REFRESH_DELAY_MS });
        fallbackTimerRef.current = setTimeout(() => {
          mobileTrace('sse', 'session-screen:fallback-fire', { sessionId: id });
          refreshMessages(config, id);
          refreshSession(config, id);
          setIsAwaitingReply(false);
        }, FALLBACK_REFRESH_DELAY_MS);
      }
    }
  }, [config, id, draft, isSending, isAwaitingReply, send, refreshMessages, refreshSession, isDemoSession, clearDraft, sseConnected]);

  // Cleanup fallback timer
  useEffect(() => {
    return () => {
      if (fallbackTimerRef.current) {
        mobileTrace('sse', 'session-screen:fallback-cancel', { reason: 'unmount' });
        clearTimeout(fallbackTimerRef.current);
      }
    };
  }, []);

  const handleStartRecording = useCallback(async () => {
    if (!settings.audioEnabled) return;
    if (needsTranscriptionKey) {
      router.push('/settings');
      return;
    }
    await startRecording();
  }, [startRecording, settings.audioEnabled, needsTranscriptionKey, router]);

  const handleStopRecording = useCallback(async () => {
    await stopRecordingAndTranscribe(settings.elevenLabsApiKey);
  }, [stopRecordingAndTranscribe, settings.elevenLabsApiKey]);

  const handleConfirmVoice = useCallback(() => {
    const text = confirmTranscription();
    if (text && id) {
      handleSend(text);
    }
  }, [confirmTranscription, id, handleSend]);

  const handleCancelVoice = useCallback(() => {
    cancelVoice();
  }, [cancelVoice]);

  const screenTitle = isDemoSession ? demoSession.title : activeSession?.title ?? 'Session';
  const showConfigureBanner = !config && !isDemoSession;
  const showErrorBanner = !!error;
  const showConnectionChip = config && !isDemoSession && connectionState !== 'connected' && (hasBeenLiveReady || connectionState === 'offline');
  const showLiveReadyConnecting = config && !isDemoSession && !liveReady;
  const showLiveReadyReady = config && !isDemoSession && liveReady;
  const showVoiceError = !!voiceError && voiceState === 'error';
  const showSpeakingIndicator = isSpeaking;

  const connectionChipProps =
    connectionState === 'streaming'
      ? { icon: 'wifi' as const, text: 'Streaming…' }
      : connectionState === 'reconnecting'
        ? { icon: 'wifi-sync' as const, text: 'Reconnecting…' }
        : connectionState === 'stale'
          ? { icon: 'wifi-strength-1' as const, text: 'Stale' }
          : connectionState === 'connecting'
            ? { icon: 'wifi-sync' as const, text: 'Connecting…' }
            : connectionState === 'offline'
              ? { icon: 'wifi-off' as const, text: 'Offline' }
              : { icon: 'wifi-off' as const, text: 'Connection issue' };

  return (
    <>
      <Stack.Screen
        options={{
          title: screenTitle,
        }}
      />
      <KeyboardAvoidingView
        style={[styles.container, { backgroundColor: theme.colors.background }]}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        keyboardVerticalOffset={96}
      >
        {showConfigureBanner && (
          <Banner
            visible={true}
            actions={[
              {
                label: 'Go to Settings',
                onPress: () => router.push('/settings'),
              },
            ]}
            icon="server-off"
          >
            Server not configured. Enter your server URL and credentials in Settings.
          </Banner>
        )}

        {showConnectionChip && (
          <View style={styles.connectionRow}>
            <Chip icon={connectionChipProps.icon} style={styles.connectionChip}>
              {connectionChipProps.text}
            </Chip>
          </View>
        )}

        {showLiveReadyConnecting && (
          <View style={styles.connectionRow}>
            <Chip icon="wifi-sync" style={styles.connectionChip}>
              Connecting live updates…
            </Chip>
          </View>
        )}

        {showLiveReadyReady && (
          <View style={styles.connectionRow}>
            <Chip icon="check-circle" style={[styles.connectionChip, { backgroundColor: 'rgba(34,197,94,0.12)' }]}>
              Live ready
            </Chip>
          </View>
        )}

        {showErrorBanner && (
          <Banner
            visible={true}
            actions={[
              {
                label: 'Dismiss',
                onPress: clearError,
              },
              {
                label: 'Retry',
                onPress: handleRetry,
              },
            ]}
            icon="alert-circle"
          >
            {error}
          </Banner>
        )}

        {showVoiceError && (
          <Banner
            visible={true}
            actions={[
              {
                label: 'Dismiss',
                onPress: handleCancelVoice,
              },
            ]}
            icon="microphone-off"
          >
            {voiceError}
          </Banner>
        )}

        {isLoading && (
          <View style={styles.loading}>
            <ActivityIndicator animating={true} size="large" />
          </View>
        )}

        {!isLoading && messages.length === 0 && !error && (
          <View style={styles.empty}>
            <Text variant="bodyLarge" style={{ color: theme.colors.onSurfaceVariant }}>
              {isDemoSession
                ? 'Send a demo message to preview the timeline locally.'
                : config
                  ? 'No messages in this session yet.'
                  : 'Configure server to load messages.'}
            </Text>
          </View>
        )}

        {!isLoading && messages.length > 0 && (
          <FlatList
            ref={listRef}
            data={messages}
            keyExtractor={(item) => item.id}
            renderItem={({ item }) => <MessageBubble message={item} />}
            contentContainerStyle={styles.listContent}
            inverted={false}
            refreshControl={
              <RefreshControl
                refreshing={isRefreshing}
                onRefresh={handleRefresh}
                colors={[theme.colors.primary]}
                tintColor={theme.colors.primary}
              />
            }
          />
        )}

        <View style={styles.footer}>
          {showSpeakingIndicator && (
            <View style={styles.speakingRow}>
              <ActivityIndicator animating={true} size="small" color={theme.colors.primary} />
              <Text variant="bodyMedium" style={{ color: theme.colors.primary }}>
                Speaking…
              </Text>
              <Button
                mode="text"
                onPress={() => stopSpeaking()}
                compact
                style={{ marginLeft: 'auto' }}
              >
                Stop
              </Button>
            </View>
          )}

          {voiceState === 'idle' && (
            <>
              {needsTranscriptionKey && (
                <Banner
                  visible={true}
                  actions={[
                    {
                      label: 'Open Settings',
                      onPress: () => router.push('/settings'),
                    },
                  ]}
                  icon="key-alert"
                >
                  {MISSING_ELEVENLABS_API_KEY_MESSAGE}
                </Banner>
              )}
              <TextInput
                mode="outlined"
                label="Message"
                value={draft}
                onChangeText={(text) => setDraft(id, text)}
                multiline
                numberOfLines={3}
                maxLength={2000}
                disabled={(!config && !isDemoSession) || isSending || isAwaitingReply}
                placeholder={
                  isDemoSession
                    ? 'Type a demo message…'
                    : config
                      ? 'Type a message…'
                      : 'Configure server to send messages'
                }
                style={styles.input}
                right={
                  <TextInput.Icon
                    icon="microphone"
                    onPress={handleStartRecording}
                    disabled={
                      !settings.audioEnabled ||
                      needsTranscriptionKey ||
                      (!config && !isDemoSession) ||
                      isSending ||
                      isAwaitingReply ||
                      (!isDemoSession && !!config && !liveReady)
                    }
                  />
                }
              />
              {isAwaitingReply && (
                <View style={styles.awaitingReply}>
                  <ActivityIndicator animating={true} size="small" />
                  <Text variant="bodyMedium">Waiting for assistant response…</Text>
                </View>
              )}
              <Button
                mode="contained"
                onPress={() => handleSend()}
                disabled={(!config && !isDemoSession) || !draft.trim() || isSending || isAwaitingReply || (!isDemoSession && !!config && !liveReady)}
                loading={isSending || isAwaitingReply}
                style={styles.button}
              >
                {isDemoSession ? 'Send Demo Message' : 'Send Message'}
              </Button>
            </>
          )}

          {voiceState === 'listening' && (
            <View style={styles.voicePanel}>
              <View style={styles.recordingRow}>
                <View style={styles.recordingDot} />
                <Text variant="bodyLarge" style={{ color: theme.colors.error }}>
                  Recording… {Math.round(recordingDurationMs / 1000)}s
                </Text>
              </View>
              <Button
                mode="contained-tonal"
                onPress={handleStopRecording}
                icon="stop"
                style={styles.button}
              >
                Stop Recording
              </Button>
              <Button
                mode="outlined"
                onPress={handleCancelVoice}
                icon="close"
                style={styles.button}
              >
                Cancel
              </Button>
            </View>
          )}

          {voiceState === 'transcribing' && (
            <View style={styles.voicePanel}>
              <View style={styles.awaitingReply}>
                <ActivityIndicator animating={true} size="small" />
                <Text variant="bodyMedium">Transcribing…</Text>
              </View>
            </View>
          )}

          {voiceState === 'reviewing' && voiceTranscription !== null && (
            <View style={styles.voicePanel}>
              <Text variant="titleSmall" style={{ color: theme.colors.primary }}>
                Review transcription
              </Text>
              <TextInput
                mode="outlined"
                value={voiceTranscription}
                onChangeText={setVoiceTranscription}
                multiline
                numberOfLines={4}
                maxLength={2000}
                style={styles.input}
              />
              <Button
                mode="contained"
                onPress={handleConfirmVoice}
                disabled={!voiceTranscription.trim() || isSending || isAwaitingReply || (!isDemoSession && !!config && !liveReady)}
                loading={isSending || isAwaitingReply}
                icon="send"
                style={styles.button}
              >
                Send
              </Button>
              <Button
                mode="outlined"
                onPress={handleCancelVoice}
                icon="close"
                style={styles.button}
              >
                Cancel
              </Button>
            </View>
          )}

          <Button mode="contained" onPress={() => router.back()} style={styles.button}>
            Go Back
          </Button>
        </View>
      </KeyboardAvoidingView>
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  listContent: {
    paddingVertical: 8,
  },
  empty: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  loading: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  footer: {
    padding: 16,
    gap: 12,
    borderTopWidth: 1,
    borderTopColor: 'rgba(0,0,0,0.1)',
  },
  input: {
    backgroundColor: 'transparent',
  },
  awaitingReply: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  button: {
    width: '100%',
  },
  connectionRow: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    alignItems: 'flex-start',
  },
  connectionChip: {
    backgroundColor: 'rgba(0,0,0,0.05)',
  },
  voicePanel: {
    gap: 12,
  },
  recordingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingVertical: 8,
  },
  recordingDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: '#ef4444',
  },
  speakingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingVertical: 8,
    paddingHorizontal: 12,
    backgroundColor: 'rgba(0,0,0,0.03)',
    borderRadius: 8,
  },
});
