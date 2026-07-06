/**
 * Classifier-mode driver — runs in a SUBPROCESS with PAI_DIR at a throwaway
 * dir and drives the REAL chat.message hook once, so the parent test can
 * assert what gate vs shadow mode actually persisted (W2.2 plumbing).
 *
 * Invoked as:
 *   PAI_DIR=<tmp> PAI_CLASSIFIER_USE_LLM=false [PAI_CLASSIFIER_MODE=shadow] \
 *     bun drive-classifier-mode.mjs <sessionId> "<prompt>"
 */
import { fileURLToPath } from "url";

const [sid, prompt, waitMsArg] = process.argv.slice(2);
if (!sid || !prompt) {
  console.error("usage: drive-classifier-mode.mjs <sessionId> <prompt> [waitMsForAsyncTelemetry]");
  process.exit(2);
}
const waitMs = parseInt(waitMsArg || "0", 10) || 0;

const pluginPath = fileURLToPath(new URL("../../plugins/pai-hooks.js", import.meta.url));
const mod = await import(pluginPath);
const plugin = await mod.default({
  project: { name: "shadow-test", root: process.env.PAI_DIR },
  client: {},
  $: {},
  directory: process.env.PAI_DIR,
  worktree: process.env.PAI_DIR,
});

await plugin.event({
  event: { type: "session.created", properties: { sessionID: sid, info: {} } },
});
const t0 = Date.now();
await plugin["chat.message"]({ sessionID: sid }, { parts: [{ type: "text", text: prompt }] });
// How long the hook held the prompt — shadow+LLM must NOT block on the
// classifier subprocess (fire-and-forget), so this stays near-zero there.
console.log(`CHAT_MS=${Date.now() - t0}`);

// Fire-and-forget telemetry needs the process alive to land; wait when asked.
if (waitMs > 0) await new Promise((r) => setTimeout(r, waitMs));

console.log("DRIVE_OK");
