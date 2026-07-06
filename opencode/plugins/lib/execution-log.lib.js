/**
 * execution-log.lib.js — runtime-owned skill execution telemetry (W2.6).
 *
 * MEMORY/SKILLS/execution.jsonl used to be written by the MODEL: 44 skill
 * files carried an identical "## Execution Log" block instructing it to
 * hand-run an echo with placeholder values (workflow name, 8-word summary,
 * approximate duration). Prompt-emitted bookkeeping is fabrication-prone —
 * observed live (2026-07-06): a skill transcribed the echo template instead
 * of executing it, logging a literal 00:00:00 timestamp. The runtime already
 * sees every skill invocation in tool.execute.after with the real name,
 * outcome and wall-clock duration, so it owns this stream now.
 *
 * Schema note: `source: 'runtime'` separates these rows from historical
 * model-written ones. `workflow` is gone — only the model knew which internal
 * workflow it picked, which made the field self-reported; the raw args
 * preview carries the same signal without asking anyone to summarize.
 */
import { join } from 'path';
import { PAI_DIR, appendJsonL, getISOTimestamp } from './pai-hooks.lib.js';

export const SKILL_EXECUTION_PATH = join(PAI_DIR, 'MEMORY', 'SKILLS', 'execution.jsonl');

const INPUT_PREVIEW_MAX = 160;

/**
 * Pure event builder (unit-testable; emit stamps the timestamp).
 *
 * @param {object} p
 * @param {string} p.skillName
 * @param {object|string|undefined} p.args      Raw tool args — previewed, never interpreted.
 * @param {boolean} p.success
 * @param {number|undefined} p.durationMs
 * @param {string|undefined} p.sessionId
 * @returns {object} event without `ts`
 */
export function buildSkillExecutionEvent({ skillName, args, success, durationMs, sessionId }) {
  let preview = '';
  try {
    preview = typeof args === 'string' ? args : JSON.stringify(args ?? {});
  } catch {
    preview = '[unserializable args]';
  }
  if (preview.length > INPUT_PREVIEW_MAX) preview = preview.slice(0, INPUT_PREVIEW_MAX) + '…';

  return {
    skill: skillName || 'unknown',
    input: preview,
    status: success ? 'ok' : 'error',
    duration_s: Number.isFinite(durationMs) ? Math.round(durationMs / 100) / 10 : null,
    session_id: sessionId || null,
    source: 'runtime',
  };
}

/**
 * Append one skill-execution row. Failures are swallowed by appendJsonL —
 * telemetry must never break the tool call it observes. `path` is overridable
 * for tests only; production callers use the default stream.
 */
export function emitSkillExecution(params, path = SKILL_EXECUTION_PATH) {
  const event = { ts: getISOTimestamp(), ...buildSkillExecutionEvent(params) };
  appendJsonL(path, event);
  return event;
}
