# PAI Mobile — Flutter SSE Experiment

> Flutter prototype demonstrating native SSE streaming to OpenCode server.
> This experiment validates the hypothesis that Flutter handles SSE more
> reliably than React Native's polyfill-based approach.

## Structure

```
lib/
├── main.dart                      # App entry point
├── models/
│   └── event.dart                 # OpenCodeEvent data model
├── services/
│   └── opencode_client.dart       # SSE client with Basic Auth
└── screens/
    └── events_screen.dart         # Connection UI + event viewer
```

## Key Implementation

### SSE without Polyfills

The Dart `http` package provides native streaming via `http.Client.send()`:

```dart
final request = http.Request('GET', url);
request.headers['Accept'] = 'text/event-stream';
request.headers['Authorization'] = _encodeBasicAuth();

final response = await _httpClient!.send(request);

// Stream transforms — no XMLHttpRequest, no EventSource polyfill
response.stream
  .transform(utf8.decoder)
  .transform(const LineSplitter())
  .listen((line) {
    // Parse SSE line-by-line
  });
```

### Comparison with React Native

| Aspect | React Native | Flutter (Dart) |
|--------|-------------|----------------|
| **HTTP client** | `fetch` / `XMLHttpRequest` | `http.Client` (native Dart) |
| **SSE support** | Requires `event-source-polyfill` | Native streaming via `Stream` |
| **Stream handling** | EventSource API emulation | `Stream.transform()` + `LineSplitter` |
| **Error recovery** | Manual handshake timers, debug probes | Built-in `onError`/`onDone` callbacks |
| **Code complexity** | ~150 lines with workarounds | ~80 lines, idiomatic Dart |
| **Platform layers** | JS bridge → native → JS | Dart VM (native) or AOT compiled |

## Running

```bash
cd mobile-app/apps/flutter
flutter pub get
flutter run
```

## Status

- **ISC-1** ✅ Project scaffolded
- **ISC-2** ✅ Basic Auth configured
- **ISC-3** ✅ SSE stream implementation
- **ISC-4** ✅ `connected` event
- **ISC-5** ✅ `message` events
- **ISC-6** ✅ `status` events
- **ISC-7** ✅ `error` events
- **ISC-8** ✅ `disconnected` event
- **ISC-9** ✅ Type normalization matches TS logic
- **ISC-10** ⏸️ Android emulator (requires Android SDK)
- **ISC-11** ✅ No RN dependencies
- **ISC-12** ✅ No custom native code

## Findings

**Flutter's SSE handling is significantly cleaner:**

1. **No polyfills needed** — Dart's `http` package handles streaming natively
2. **No XMLHttpRequest quirks** — avoids Hermes/Expo Go incompatibilities
3. **Stream composition** — `Stream.transform()` is idiomatic and composable
4. **Error handling** — `onError`/`onDone` are first-class, not bolted-on
5. **Type safety** — Dart's sound null safety catches edge cases at compile time

**Trade-offs to consider:**

1. **Team expertise** — Dart/Flutter learning curve for TS/React Native developers
2. **Ecosystem** — React Native has more mature libraries for some mobile features
3. **Native modules** — If you need Kotlin/Swift for hardware features, Flutter's FFI is more complex
4. **Bundle size** — Flutter apps are typically larger than RN

## Recommendation

For the specific pain point (SSE reliability), **Flutter is the clear winner**. The streaming implementation is native, clean, and doesn't require the workaround layers that plague the React Native version.

If the rest of the mobile app (UI, stores, navigation) is working well in React Native, a pragmatic approach might be:
- Keep the existing RN app for UI/features
- Extract SSE into a native module or consider a hybrid approach
- Or, if you're early in development, Flutter's first-class streaming makes a compelling case for migration

## Next Steps

1. Test on a physical Android device with a real OpenCode server
2. Benchmark memory/CPU usage during long-running SSE sessions
3. Evaluate Flutter's `http` package vs dedicated SSE packages (`eventsource`, `sse_client`)
4. Compare build times and bundle sizes

---

*Experiment completed 2026-05-28*
