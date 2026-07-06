/**
 * Observability emitter driver — runs in a SUBPROCESS with PAI_DIR pointed at a
 * throwaway dir, so every stream path (STATE_DIR / OBSERVABILITY_DIR) resolves
 * inside it. It drives the REAL emitters and hooks — not hand-written literals —
 * so the on-disk records the parent test validates are exactly what production
 * writes. A renamed or dropped field here fails the schema round-trip.
 *
 * Invoked as: PAI_DIR=<tmp> PAI_CLASSIFIER_USE_LLM=false bun emit-observability-events.mjs
 * Emits one record to each of the seven observability streams, then prints "EMIT_OK".
 */
import { fileURLToPath } from "url";
import {
  logSecurityEvent,
  emitNotification,
} from "../../plugins/lib/pai-hooks.lib.js";

const pluginPath = fileURLToPath(new URL("../../plugins/pai-hooks.js", import.meta.url));
const mod = await import(pluginPath);
const plugin = await mod.default({
  project: { name: "obs-test", root: process.env.PAI_DIR },
  client: {},
  $: {},
  directory: process.env.PAI_DIR,
  worktree: process.env.PAI_DIR,
});

const sid = "ses_obs_roundtrip";

// 1. security-events.jsonl — real exported emitter.
logSecurityEvent({
  sessionId: sid,
  tool: "bash",
  eventType: "block",
  inspector: "SecurityPipeline",
  target: "rm -rf /tmp/x",
  reason: "rm -rf detected",
  actionTaken: "Hard block",
});

// 2. notifications.jsonl — real exported emitter.
emitNotification({
  event: "agent_completed",
  sessionId: sid,
  speak: "Tarefa concluida",
  language: "pt-BR",
  data: { completed_line: "Tarefa concluida", source: "test", language: "pt-BR" },
});

// 3. session-events.jsonl — real session.created handler via the bus bridge.
await plugin.event({
  event: { type: "session.created", properties: { sessionID: sid, info: {} } },
});

// 4. mode-classifier.jsonl — real chat.message handler (heuristic path: no subprocess).
await plugin["chat.message"](
  { sessionID: sid },
  { parts: [{ type: "text", text: "implement the authentication module with jwt" }] },
);

// 5. tool-failures.jsonl — real tool.execute.after handler on a failing tool result.
await plugin["tool.execute.after"](
  { tool: "bash", sessionID: sid, callID: "call_fail" },
  { args: { command: "false" }, error: { message: "boom: an exception was thrown" } },
);

// 6 + 7. subagent-trace.jsonl AND MEMORY/SKILLS/execution.jsonl — the same real
// tool.execute.after skill invocation feeds both (execution.jsonl is
// runtime-owned since W2.6).
await plugin["tool.execute.after"](
  { tool: "skill", sessionID: sid, callID: "call_skill" },
  { args: { name: "TestSkill" }, title: "skill run" },
);

console.log("EMIT_OK");
