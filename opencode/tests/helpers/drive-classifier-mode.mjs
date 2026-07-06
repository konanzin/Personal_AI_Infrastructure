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

const [sid, prompt] = process.argv.slice(2);
if (!sid || !prompt) {
  console.error("usage: drive-classifier-mode.mjs <sessionId> <prompt>");
  process.exit(2);
}

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
await plugin["chat.message"]({ sessionID: sid }, { parts: [{ type: "text", text: prompt }] });

console.log("DRIVE_OK");
