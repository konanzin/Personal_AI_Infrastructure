import { describe, expect, test } from "bun:test";
import { readFileSync } from "fs";
import { join } from "path";
import { fileURLToPath } from "url";
import { emitNotification } from "../plugins/lib/pai-hooks.lib.js";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));
const schemasDir = join(repoRoot, "opencode", "schemas");

function readSchema(name: string) {
  return JSON.parse(readFileSync(join(schemasDir, name), "utf-8"));
}

function typeOf(value: unknown) {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

function validate(schema: any, value: unknown, path = "$"): string[] {
  const errors: string[] = [];

  if (schema.type !== undefined) {
    const allowed = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!allowed.includes(typeOf(value))) {
      errors.push(`${path} expected ${allowed.join("|")} got ${typeOf(value)}`);
      return errors;
    }
  }

  if (schema.const !== undefined && value !== schema.const) {
    errors.push(`${path} expected const ${JSON.stringify(schema.const)}`);
  }

  if (schema.enum && !schema.enum.includes(value)) {
    errors.push(`${path} expected one of ${schema.enum.join(",")}`);
  }

  if (typeof value === "string") {
    if (schema.minLength !== undefined && value.length < schema.minLength) {
      errors.push(`${path} shorter than ${schema.minLength}`);
    }
    if (schema.maxLength !== undefined && value.length > schema.maxLength) {
      errors.push(`${path} longer than ${schema.maxLength}`);
    }
    if (schema.pattern && !(new RegExp(schema.pattern).test(value))) {
      errors.push(`${path} does not match ${schema.pattern}`);
    }
  }

  if (typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) {
      errors.push(`${path} below ${schema.minimum}`);
    }
    if (schema.maximum !== undefined && value > schema.maximum) {
      errors.push(`${path} above ${schema.maximum}`);
    }
  }

  if (typeOf(value) === "object") {
    const object = value as Record<string, unknown>;
    for (const key of schema.required ?? []) {
      if (!(key in object)) errors.push(`${path}.${key} is required`);
    }
    for (const [key, childSchema] of Object.entries(schema.properties ?? {})) {
      if (key in object) errors.push(...validate(childSchema, object[key], `${path}.${key}`));
    }
  }

  return errors;
}

const timestamp = "2026-06-15T00:00:00.000Z";

describe("Observability JSON schemas", () => {
  test("mode classifier event matches schema", () => {
    const event = {
      timestamp,
      session_id: "ses_test",
      event: "mode_classification",
      mode: "ALGORITHM",
      tier: "E3",
      source: "heuristic",
      reason: "implementation request",
      confidence: 0.92,
      latency_ms: 2,
      fallback: false,
      prompt_hash: "abc123",
      prompt_preview: "implement auth",
    };

    expect(validate(readSchema("mode-classifier-event.schema.json"), event)).toEqual([]);
  });

  test("security event matches schema", () => {
    const event = {
      timestamp,
      sessionId: "ses_test",
      tool: "bash",
      eventType: "block",
      inspector: "SecurityPipeline",
      target: "rm -rf /tmp/x",
      reason: "rm -rf detected",
      actionTaken: "Hard block",
    };

    expect(validate(readSchema("security-event.schema.json"), event)).toEqual([]);
  });

  test("session, failure, and subagent trace events match schemas", () => {
    const sessionEvent = {
      timestamp,
      event: "session_created",
      session_id: "ses_test",
      payload: { project: "repo" },
    };
    const failureEvent = {
      timestamp,
      event: "tool_failure",
      session_id: "ses_test",
      tool_name: "bash",
      failure_mode: "security_blocked",
      error_message: "PAI SECURITY BLOCKED",
      retry_happened: false,
      security_involved: true,
      permission_involved: false,
      tool_input_preview: "{\"command\":\"rm -rf /\"}",
      duration_ms: 12,
      metadata: { callID: "call_test" },
    };
    const traceEvent = {
      timestamp,
      event: "agent_spawned",
      session_id: "ses_test",
      type: "agent",
      name: "Forge",
      description: "implement parser",
      success: true,
      duration_ms: 150,
      metadata: { callID: "call_agent" },
    };

    expect(validate(readSchema("session-event.schema.json"), sessionEvent)).toEqual([]);
    expect(validate(readSchema("tool-failure-event.schema.json"), failureEvent)).toEqual([]);
    expect(validate(readSchema("subagent-trace-event.schema.json"), traceEvent)).toEqual([]);
  });

  test("notification event emitted by current helper matches schema", () => {
    const event = emitNotification({
      event: "agent_completed",
      sessionId: "ses_test",
      speak: "Tarefa concluida",
      language: "pt-BR",
      data: { completed_line: "Tarefa concluida", source: "test", language: "pt-BR" },
    });

    expect(event).not.toBeNull();
    expect(validate(readSchema("notification-event.schema.json"), event)).toEqual([]);
  });
});
