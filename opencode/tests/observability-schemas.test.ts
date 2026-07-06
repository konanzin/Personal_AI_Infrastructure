/**
 * Observability schema ROUND-TRIP.
 *
 * The old version of this file validated hand-written object literals against the
 * schemas. That could never catch the failure it was meant to prevent: an emitter
 * renaming or dropping a field. The literals were written to match the schema, and
 * the validator ignored extra keys — so a real emitter drifting from its schema
 * stayed green.
 *
 * This version drives the REAL emitters (logSecurityEvent, emitNotification) and the
 * REAL hooks (session.created, chat.message, tool.execute.after) in a subprocess with
 * PAI_DIR pointed at a throwaway dir, then validates what actually landed on disk —
 * with a STRICT validator that flags any key not declared in the schema. If an
 * emitter renames `actionTaken`→`action`, strict validation reports both an unknown
 * `action` and a missing required `actionTaken`. Schema and emitter can no longer
 * drift apart silently.
 */
import { describe, expect, test, beforeAll } from "bun:test";
import { readFileSync, mkdtempSync, existsSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { fileURLToPath } from "url";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));
const schemasDir = join(repoRoot, "opencode", "schemas");
const driver = fileURLToPath(new URL("./helpers/emit-observability-events.mjs", import.meta.url));

function readSchema(name: string) {
  return JSON.parse(readFileSync(join(schemasDir, name), "utf-8"));
}

function typeOf(value: unknown) {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

/**
 * Structural JSON-schema check. With `strict`, any object key not present in the
 * schema's `properties` is an error — this is what turns a rename/typo into a test
 * failure. `strict` does not recurse into free-form `metadata`/`payload`/`data`
 * bags (those are intentionally open), only the top-level event envelope.
 */
function validate(schema: any, value: unknown, opts: { strict?: boolean } = {}, path = "$"): string[] {
  const errors: string[] = [];

  if (schema.type !== undefined) {
    const allowed = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!allowed.includes(typeOf(value))) {
      errors.push(`${path} expected ${allowed.join("|")} got ${typeOf(value)}`);
      return errors;
    }
  }

  if (schema.const !== undefined && value !== schema.const) {
    errors.push(`${path} expected const ${JSON.stringify(schema.const)} got ${JSON.stringify(value)}`);
  }
  if (schema.enum && !schema.enum.includes(value)) {
    errors.push(`${path} expected one of ${schema.enum.join(",")} got ${JSON.stringify(value)}`);
  }

  if (typeof value === "string") {
    if (schema.minLength !== undefined && value.length < schema.minLength) errors.push(`${path} shorter than ${schema.minLength}`);
    if (schema.maxLength !== undefined && value.length > schema.maxLength) errors.push(`${path} longer than ${schema.maxLength}`);
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) errors.push(`${path} does not match ${schema.pattern}`);
  }
  if (typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) errors.push(`${path} below ${schema.minimum}`);
    if (schema.maximum !== undefined && value > schema.maximum) errors.push(`${path} above ${schema.maximum}`);
  }

  if (typeOf(value) === "object") {
    const object = value as Record<string, unknown>;
    const props = schema.properties ?? {};
    for (const key of schema.required ?? []) {
      if (!(key in object)) errors.push(`${path}.${key} is required but missing`);
    }
    for (const [key, childSchema] of Object.entries(props)) {
      if (key in object) errors.push(...validate(childSchema, object[key], opts, `${path}.${key}`));
    }
    // The teeth: an emitter field the schema does not declare. Only enforced where
    // the schema declares a `properties` map — objects typed as an open bag
    // (metadata/payload/data: `{type:object}` with no properties, or
    // additionalProperties:true) are intentionally free-form and not policed.
    const isClosedShape = Object.keys(props).length > 0 && schema.additionalProperties !== true;
    if (opts.strict && isClosedShape) {
      for (const key of Object.keys(object)) {
        if (!(key in props)) errors.push(`${path}.${key} is not declared in the schema (rename/drift?)`);
      }
    }
  }

  return errors;
}

// ── Drive the real emitters in a subprocess, capture on-disk records ──
const records: Record<string, any> = {};
let driverOutput = "";

beforeAll(() => {
  const home = mkdtempSync(join(tmpdir(), "pai-obs-"));
  const proc = Bun.spawnSync({
    cmd: ["bun", driver],
    env: { ...process.env, PAI_DIR: home, PAI_CLASSIFIER_USE_LLM: "false" },
    stdout: "pipe",
    stderr: "pipe",
  });
  driverOutput = new TextDecoder().decode(proc.stdout) + new TextDecoder().decode(proc.stderr);

  const lastRecord = (rel: string) => {
    const p = join(home, rel);
    if (!existsSync(p)) return undefined;
    const lines = readFileSync(p, "utf-8").split("\n").filter(Boolean);
    return lines.length ? JSON.parse(lines[lines.length - 1]) : undefined;
  };

  records.security = lastRecord("MEMORY/STATE/security-events.jsonl");
  records.notification = lastRecord("MEMORY/OBSERVABILITY/notifications.jsonl");
  records.session = lastRecord("MEMORY/OBSERVABILITY/session-events.jsonl");
  records.classifier = lastRecord("MEMORY/OBSERVABILITY/mode-classifier.jsonl");
  records.failure = lastRecord("MEMORY/OBSERVABILITY/tool-failures.jsonl");
  records.trace = lastRecord("MEMORY/OBSERVABILITY/subagent-trace.jsonl");
  records.execution = lastRecord("MEMORY/SKILLS/execution.jsonl");
});

describe("Observability schema round-trip (real emitters → disk → strict schema)", () => {
  test("the driver produced every stream", () => {
    expect(driverOutput).toContain("EMIT_OK");
    for (const key of ["security", "notification", "session", "classifier", "failure", "trace", "execution"]) {
      expect(records[key], `stream '${key}' produced no record`).toBeDefined();
    }
  });

  const cases: Array<[string, string]> = [
    ["security", "security-event.schema.json"],
    ["notification", "notification-event.schema.json"],
    ["session", "session-event.schema.json"],
    ["classifier", "mode-classifier-event.schema.json"],
    ["failure", "tool-failure-event.schema.json"],
    ["trace", "subagent-trace-event.schema.json"],
    ["execution", "skill-execution-event.schema.json"],
  ];

  for (const [key, schemaFile] of cases) {
    test(`${key} emitter output matches ${schemaFile} (strict)`, () => {
      expect(records[key]).toBeDefined();
      expect(validate(readSchema(schemaFile), records[key], { strict: true })).toEqual([]);
    });
  }
});

// Guard-the-guard: prove strict validation actually catches the drift it claims to.
describe("Strict validator catches emitter drift", () => {
  test("a renamed required field is flagged (unknown key present)", () => {
    const schema = readSchema("security-event.schema.json");
    const drifted = {
      timestamp: "2026-06-15T00:00:00.000Z",
      eventType: "block",
      inspector: "SecurityPipeline",
      action: "Hard block", // emitter renamed actionTaken → action
    };
    const errors = validate(schema, drifted, { strict: true });
    expect(errors.some((e) => e.includes("action") && e.includes("not declared"))).toBe(true);
  });

  test("a dropped required field is flagged", () => {
    const schema = readSchema("session-event.schema.json");
    const missing = { timestamp: "2026-06-15T00:00:00.000Z", event: "session_created", session_id: "x" };
    // payload dropped
    const errors = validate(schema, missing, { strict: true });
    expect(errors.some((e) => e.includes("payload") && e.includes("required"))).toBe(true);
  });
});
