/**
 * Wrapper: EventSourcePolyfill with XHR transport forced and debug logging
 * 
 * React Native's fetch exposes Response.body but it is not a real
 * ReadableStream, causing event-source-polyfill's FetchTransport to fail.
 * This wrapper forces XHR transport and adds deep logging for Samsung/Expo debugging.
 */

// CRITICAL: Polyfill XMLHttpRequest constants BEFORE importing event-source-polyfill.
// In Expo Go / Hermes, XHR exists but its static constants are undefined.
// event-source-polyfill checks these at import time.
const XHR = (globalThis as any).XMLHttpRequest;
if (XHR != null) {
  if (XHR.UNSENT === undefined) XHR.UNSENT = 0;
  if (XHR.OPENED === undefined) XHR.OPENED = 1;
  if (XHR.HEADERS_RECEIVED === undefined) XHR.HEADERS_RECEIVED = 2;
  if (XHR.LOADING === undefined) XHR.LOADING = 3;
  if (XHR.DONE === undefined) XHR.DONE = 4;
}

// Hide fetch so event-source-polyfill uses XHRTransport
const originalFetch = globalThis.fetch;
const originalResponse = globalThis.Response;
// @ts-ignore
(globalThis as any).fetch = undefined;
// @ts-ignore
(globalThis as any).Response = undefined;

// Import after hiding fetch
import { EventSourcePolyfill as OriginalEventSourcePolyfill } from 'event-source-polyfill';

// Restore fetch
(globalThis as any).fetch = originalFetch;
(globalThis as any).Response = originalResponse;

export { OriginalEventSourcePolyfill as EventSourcePolyfill };
