/**
 * Polyfill: XMLHttpRequest readyState constants
 * 
 * In Expo Go on Android (Hermes), XMLHttpRequest constructor exists but its
 * static constants (UNSENT, OPENED, HEADERS_RECEIVED, LOADING, DONE) are
 * undefined. react-native-sse compares xhr.readyState against
 * XMLHttpRequest.DONE (expecting 4), so the comparison becomes
 * `readyState === undefined`, which is always false → open event never fires.
 * 
 * @see docs/SSE_LIVE_READY_HANDOFF.md
 */
if (typeof globalThis.XMLHttpRequest !== 'undefined') {
  const XHR = globalThis.XMLHttpRequest as any;
  if (XHR.DONE === undefined) {
    XHR.UNSENT = 0;
    XHR.OPENED = 1;
    XHR.HEADERS_RECEIVED = 2;
    XHR.LOADING = 3;
    XHR.DONE = 4;
  }
}
