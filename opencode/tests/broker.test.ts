import { describe, test, expect, afterAll } from "bun:test";
import { mkdtempSync, mkdirSync, appendFileSync, rmSync, writeFileSync } from "fs";
import { join, dirname } from "path";
import { tmpdir } from "os";
import { fileURLToPath } from "url";

import {
  parseJsonlChunk,
  decideRender,
  dedupeKey,
  translateLegacyNotify,
  RingBuffer,
  type NotificationEvent,
  type Subscriber,
} from "../broker/broker-lib.ts";
import {
  parseSpeakerLine,
  parseVoiceEnv,
  resolveEdgeTtsConfig,
  resolveVoiceEnabled,
  resolveVoice,
  sanitizeForSpeech,
} from "../broker/edge-tts-lib.ts";
import { createDedupeStore, MIN_CAPACITY } from "../broker/renderer-dedupe.ts";

const mkEvent = (over: Partial<NotificationEvent> = {}): NotificationEvent => ({
  v: 1,
  timestamp: "2026-06-11T18:00:00.000Z",
  level: "milestone",
  event: "phase_transition",
  session_id: "ses-1",
  slug: "slug-1",
  title: "Work",
  speak: "Work entered the verify phase",
  language: "en-US",
  data: { phase: "verify" },
  ...over,
});

const mkSub = (over: Partial<Subscriber> = {}): Subscriber => ({
  id: "sub-1",
  device: "phone",
  name: "s24",
  focusedSession: null,
  listening: true,
  ...over,
});

describe("Broker lib — parseJsonlChunk", () => {
  test("parses complete lines and keeps the partial tail", () => {
    const e = JSON.stringify(mkEvent());
    const { events, rest } = parseJsonlChunk(`${e}\n${e}\n{"v":1,"event":"trunc`);
    expect(events.length).toBe(2);
    expect(rest).toStartWith('{"v":1');
  });

  test("skips corrupt interior lines without dying", () => {
    const e = JSON.stringify(mkEvent());
    const { events } = parseJsonlChunk(`not-json\n${e}\n\n`);
    expect(events.length).toBe(1);
  });
});

describe("Broker lib — routing policy v1", () => {
  test("attention always speaks for listening subscribers", () => {
    const ev = mkEvent({ level: "attention", event: "guard_denied" });
    const watcher = mkSub({ id: "a", focusedSession: "ses-1" });
    const other = mkSub({ id: "b" });
    expect(decideRender(ev, [watcher, other], other).speak).toBe(true);
    expect(decideRender(ev, [watcher, other], watcher).speak).toBe(true);
  });

  test("milestone is suppressed for other subscribers when someone watches the session", () => {
    const ev = mkEvent();
    const watcher = mkSub({ id: "a", device: "desktop", focusedSession: "ses-1" });
    const phone = mkSub({ id: "b" });
    const d = decideRender(ev, [watcher, phone], phone);
    expect(d.speak).toBe(false);
    expect(d.reason).toBe("session-on-screen");
  });

  test("focus matches by slug too", () => {
    const ev = mkEvent();
    const watcher = mkSub({ id: "a", focusedSession: "slug-1" });
    const other = mkSub({ id: "b" });
    expect(decideRender(ev, [watcher, other], other).speak).toBe(false);
  });

  test("target focus does not mute itself", () => {
    const ev = mkEvent();
    const watcher = mkSub({ id: "a", focusedSession: "ses-1" });
    const d = decideRender(ev, [watcher], watcher);
    expect(d.speak).toBe(true);
    expect(d.reason).toBe("default");
  });

  test("muted subscriber never speaks, even on attention", () => {
    const muted = mkSub({ listening: false });
    expect(decideRender(mkEvent(), [muted], muted).speak).toBe(false);
    expect(decideRender(mkEvent({ level: "attention" }), [muted], muted).speak).toBe(false);
  });

  test("default is to speak", () => {
    const sub = mkSub();
    const d = decideRender(mkEvent(), [sub], sub);
    expect(d.speak).toBe(true);
    expect(d.reason).toBe("default");
  });
});

describe("Broker lib — legacy /notify translation", () => {
  test("message becomes a milestone legacy_notify with speak", () => {
    const ev = translateLegacyNotify({ message: "Running the Research workflow", title: "Ava Chen", voice_id: "x", language: "en-US" });
    expect(ev).not.toBeNull();
    expect(ev!.event).toBe("legacy_notify");
    expect(ev!.level).toBe("milestone");
    expect(ev!.speak).toBe("Running the Research workflow");
    expect(ev!.language).toBe("en-US");
    expect(ev!.title).toBe("Ava Chen");
    expect(ev!.data.voice_id).toBe("x");
  });

  test("phase payloads map to phase_transition", () => {
    const ev = translateLegacyNotify({ message: "Entering VERIFY", phase: "VERIFY", slug: "s", language: "en-US" });
    expect(ev!.event).toBe("phase_transition");
    expect(ev!.data.phase).toBe("verify");
    expect(ev!.slug).toBe("s");
  });

  test("voice_enabled:false yields empty speak (dashboard-only upstream)", () => {
    const ev = translateLegacyNotify({ message: "silent progress", voice_enabled: false });
    expect(ev!.speak).toBe("");
  });

  test("speaking payloads without language are rejected", () => {
    expect(translateLegacyNotify({ message: "This would speak without a selector" })).toBeNull();
  });

  test("missing message is rejected", () => {
    expect(translateLegacyNotify({} as any)).toBeNull();
  });
});

describe("Broker lib — misc", () => {
  test("dedupeKey prefers message_id, then phase, then timestamp", () => {
    expect(dedupeKey(mkEvent({ data: { message_id: "m1" } }))).toBe("ses-1:phase_transition:m1");
    expect(dedupeKey(mkEvent({ data: { phase: "verify" } }))).toBe("ses-1:phase_transition:verify");
    expect(dedupeKey(mkEvent({ data: {} }))).toBe("ses-1:phase_transition:2026-06-11T18:00:00.000Z");
  });

  test("ring buffer keeps only the newest N", () => {
    const ring = new RingBuffer<number>(3);
    [1, 2, 3, 4, 5].forEach((n) => ring.push(n));
    expect(ring.last(10)).toEqual([3, 4, 5]);
  });
});

describe("Edge TTS speaker config", () => {
  test("parses JSON utterance lines with language", () => {
    expect(parseSpeakerLine('{"text":"Trabalho concluido","language":"pt-BR"}')).toEqual({
      text: "Trabalho concluido",
      language: "pt-BR",
      voice: undefined,
      rate: undefined,
      volume: undefined,
    });
  });

  test("parses plain text utterance lines", () => {
    expect(parseSpeakerLine("Done now")).toEqual({ text: "Done now" });
  });

  test("sanitizes thinking tags before speech", () => {
    expect(sanitizeForSpeech("Visible <think>hidden</think> done")).toBe("Visible done");
  });

  test("selects default and overridden voices by language", () => {
    expect(resolveVoice("pt-BR", {})).toBe("pt-BR-FranciscaNeural");
    expect(resolveVoice("en-US", {})).toBe("en-US-AvaNeural");
    expect(resolveVoice("pt-BR", { PAI_EDGE_TTS_VOICE_PT_BR: "pt-BR-AntonioNeural" })).toBe("pt-BR-AntonioNeural");
  });

  test("parses persisted voice env config", () => {
    expect(parseVoiceEnv(`
# PAI voice config
PAI_EDGE_TTS_LANGUAGE=pt-BR
PAI_VOICE_ENABLED=false
export PAI_EDGE_TTS_VOICE_PT_BR="pt-BR-ThalitaMultilingualNeural"
PAI_EDGE_TTS_RATE='+10%'
`)).toEqual({
      PAI_EDGE_TTS_LANGUAGE: "pt-BR",
      PAI_VOICE_ENABLED: "false",
      PAI_EDGE_TTS_VOICE_PT_BR: "pt-BR-ThalitaMultilingualNeural",
      PAI_EDGE_TTS_RATE: "+10%",
    });
  });

  test("resolves voice feedback enabled flag", () => {
    expect(resolveVoiceEnabled({})).toBe(true);
    expect(resolveVoiceEnabled({ PAI_VOICE_ENABLED: "false" })).toBe(false);
    expect(resolveVoiceEnabled({ PAI_VOICE_ENABLED: "off" })).toBe(false);
    expect(resolveVoiceEnabled({ PAI_EDGE_TTS_ENABLED: "0" })).toBe(false);
    expect(resolveVoiceEnabled({ PAI_VOICE_ENABLED: "true" })).toBe(true);
  });

  test("resolves Edge TTS config with rate and volume defaults", () => {
    expect(resolveEdgeTtsConfig({ text: "Done", language: "en-US" }, {})).toEqual({
      text: "Done",
      language: "en-US",
      voice: "en-US-AvaNeural",
      rate: "+15%",
      volume: "+0%",
    });
  });

  test("loads persisted voice config for runtime resolution", () => {
    const dir = mkdtempSync(join(tmpdir(), "pai-voice-config-"));
    const configPath = join(dir, "voice.env");
    writeFileSync(configPath, "PAI_VOICE_ENABLED=false\nPAI_EDGE_TTS_LANGUAGE=pt-BR\nPAI_EDGE_TTS_VOICE_PT_BR=pt-BR-AntonioNeural\n", "utf-8");

    const previous = process.env.PAI_EDGE_TTS_CONFIG;
    const previousVoiceEnabled = process.env.PAI_VOICE_ENABLED;
    const previousEdgeEnabled = process.env.PAI_EDGE_TTS_ENABLED;
    process.env.PAI_EDGE_TTS_CONFIG = configPath;
    delete process.env.PAI_VOICE_ENABLED;
    delete process.env.PAI_EDGE_TTS_ENABLED;
    try {
      expect(resolveVoiceEnabled(process.env)).toBe(false);
      expect(resolveEdgeTtsConfig({ text: "Oi" }, process.env)).toEqual({
        text: "Oi",
        language: "pt-BR",
        voice: "pt-BR-AntonioNeural",
        rate: "+15%",
        volume: "+0%",
      });
    } finally {
      if (previous === undefined) {
        delete process.env.PAI_EDGE_TTS_CONFIG;
      } else {
        process.env.PAI_EDGE_TTS_CONFIG = previous;
      }
      if (previousVoiceEnabled === undefined) {
        delete process.env.PAI_VOICE_ENABLED;
      } else {
        process.env.PAI_VOICE_ENABLED = previousVoiceEnabled;
      }
      if (previousEdgeEnabled === undefined) {
        delete process.env.PAI_EDGE_TTS_ENABLED;
      } else {
        process.env.PAI_EDGE_TTS_ENABLED = previousEdgeEnabled;
      }
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe("Renderer dedupe ledger", () => {
  const dirs: string[] = [];
  const newPath = () => {
    const dir = mkdtempSync(join(tmpdir(), "pai-dedupe-"));
    dirs.push(dir);
    return join(dir, "seen.json");
  };
  afterAll(() => {
    for (const dir of dirs) rmSync(dir, { recursive: true, force: true });
  });

  test("marks fresh once, then deduplicates", () => {
    const s = createDedupeStore({ path: newPath(), flushMs: 1 });
    expect(s.markAndCheckFresh("a")).toBe(true);
    expect(s.markAndCheckFresh("a")).toBe(false);
    expect(s.has("a")).toBe(true);
    expect(s.has("b")).toBe(false);
  });

  test("never deduplicates an empty key", () => {
    const s = createDedupeStore({ path: newPath(), flushMs: 1 });
    expect(s.markAndCheckFresh("")).toBe(true);
    expect(s.markAndCheckFresh("")).toBe(true);
  });

  test("persists across reloads (survives restart)", () => {
    const path = newPath();
    const s1 = createDedupeStore({ path, flushMs: 1 });
    s1.markAndCheckFresh("k1");
    s1.markAndCheckFresh("k2");
    s1.flush();

    const s2 = createDedupeStore({ path });
    expect(s2.markAndCheckFresh("k1")).toBe(false);
    expect(s2.markAndCheckFresh("k2")).toBe(false);
    expect(s2.markAndCheckFresh("k3")).toBe(true);
  });

  test("clamps capacity to the floor and evicts oldest beyond it", () => {
    const s = createDedupeStore({ path: newPath(), capacity: 5, flushMs: 1 });
    // capacity requested 5 but floored to MIN_CAPACITY (>= largest /recent n)
    const total = MIN_CAPACITY + 10;
    for (let i = 0; i < total; i++) s.markAndCheckFresh(`key-${i}`);
    expect(s.size()).toBe(MIN_CAPACITY);
    // the 10 oldest were evicted → fresh again
    expect(s.has("key-0")).toBe(false);
    expect(s.markAndCheckFresh("key-0")).toBe(true);
    // a recent one is still present
    expect(s.has(`key-${total - 1}`)).toBe(true);
  });

  test("corrupt ledger file loads as empty (fail-open)", () => {
    const path = newPath();
    writeFileSync(path, "{not valid json", "utf-8");
    const s = createDedupeStore({ path });
    expect(s.size()).toBe(0);
    expect(s.markAndCheckFresh("x")).toBe(true);
  });
});

// ─── Integration: real broker process, real SSE ─────────────────────────────

const brokerPath = fileURLToPath(new URL("../broker/pulse-broker.ts", import.meta.url));

interface BrokerHandle {
  port: number;
  paiDir: string;
  proc: ReturnType<typeof Bun.spawn>;
  streamPath: string;
}

async function startBroker(): Promise<BrokerHandle> {
  const paiDir = mkdtempSync(join(tmpdir(), "pai-broker-test-"));
  const streamPath = join(paiDir, "MEMORY", "OBSERVABILITY", "notifications.jsonl");
  mkdirSync(dirname(streamPath), { recursive: true });

  const proc = Bun.spawn(["bun", brokerPath, "--port", "0"], {
    env: { ...process.env, PAI_DIR: paiDir },
    stdout: "pipe",
    stderr: "inherit",
  });

  const reader = proc.stdout.getReader();
  const decoder = new TextDecoder();
  let out = "";
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    const { value, done } = await reader.read();
    if (done) break;
    out += decoder.decode(value);
    const m = out.match(/localhost:(\d+)/);
    if (m) {
      reader.releaseLock();
      return { port: Number(m[1]), paiDir, proc, streamPath };
    }
  }
  proc.kill();
  throw new Error(`broker did not start: ${out}`);
}

async function* sseFrames(res: Response): AsyncGenerator<any> {
  const reader = res.body!.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) return;
    buffer += decoder.decode(value, { stream: true });
    let sep: number;
    while ((sep = buffer.indexOf("\n\n")) !== -1) {
      const frame = buffer.slice(0, sep);
      buffer = buffer.slice(sep + 2);
      const dataLine = frame.split("\n").find((l) => l.startsWith("data: "));
      if (dataLine) yield JSON.parse(dataLine.slice(6));
    }
  }
}

async function nextFrame(gen: AsyncGenerator<any>, ms = 5000): Promise<any> {
  return Promise.race([
    gen.next().then((r) => r.value),
    new Promise((_, rej) => setTimeout(() => rej(new Error("SSE frame timeout")), ms)),
  ]);
}

const handles: BrokerHandle[] = [];
afterAll(() => {
  for (const h of handles) {
    h.proc.kill();
    rmSync(h.paiDir, { recursive: true, force: true });
  }
});

describe("Broker integration", () => {
  test("health, subscribe, tail-to-SSE, legacy notify and presence", async () => {
    const broker = await startBroker();
    handles.push(broker);
    const base = `http://localhost:${broker.port}`;

    // Health (both the broker path and the upstream-compat path)
    const health = await (await fetch(`${base}/health`)).json();
    expect(health.status).toBe("ok");
    const compat = await (await fetch(`${base}/api/pulse/health`)).json();
    expect(compat.service).toBe("pulse-broker");

    // Subscribe
    const res = await fetch(`${base}/subscribe?device=phone&name=test`);
    expect(res.ok).toBe(true);
    const frames = sseFrames(res);
    const hello = await nextFrame(frames);
    expect(hello.type).toBe("hello");
    expect(hello.id).toStartWith("sub-");

    // Producer appends -> tailer -> SSE delivery with render decision
    appendFileSync(broker.streamPath, JSON.stringify(mkEvent()) + "\n", "utf-8");
    const delivery = await nextFrame(frames);
    expect(delivery.type).toBe("notification");
    expect(delivery.event.event).toBe("phase_transition");
    expect(delivery.render.speak).toBe(true);
    expect(delivery.dedupe_key).toContain("ses-1:phase_transition");

    // Legacy /notify joins the same pipeline
    const notifyRes = await fetch(`${base}/notify`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ message: "Entering the VERIFY phase", phase: "VERIFY", title: "Vera", language: "en-US" }),
    });
    expect(notifyRes.status).toBe(200);
    const legacy = await nextFrame(frames);
    expect(legacy.event.event).toBe("phase_transition");
    expect(legacy.event.data.source).toBe("legacy_notify");

    // Presence: mute, then a milestone arrives with speak:false
    const mute = await fetch(`${base}/presence`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: hello.id, listening: false }),
    });
    expect((await mute.json()).listening).toBe(false);
    appendFileSync(broker.streamPath, JSON.stringify(mkEvent({ data: { phase: "learn" } })) + "\n", "utf-8");
    const mutedDelivery = await nextFrame(frames);
    expect(mutedDelivery.render.speak).toBe(false);
    expect(mutedDelivery.render.reason).toBe("muted");
  }, 20_000);

  test("focused subscriber suppresses voice for other subscribers on that session", async () => {
    const broker = await startBroker();
    handles.push(broker);
    const base = `http://localhost:${broker.port}`;

    const deskRes = await fetch(`${base}/subscribe?device=desktop&name=desk&focus=ses-1`);
    const desk = sseFrames(deskRes);
    await nextFrame(desk); // hello

    const phoneRes = await fetch(`${base}/subscribe?device=phone&name=s24`);
    const phone = sseFrames(phoneRes);
    await nextFrame(phone); // hello

    appendFileSync(broker.streamPath, JSON.stringify(mkEvent()) + "\n", "utf-8");
    const deskDelivery = await nextFrame(desk);
    expect(deskDelivery.render.speak).toBe(true);
    const phoneDelivery = await nextFrame(phone);
    expect(phoneDelivery.render.speak).toBe(false);
    expect(phoneDelivery.render.reason).toBe("session-on-screen");

    // attention still speaks on the phone
    appendFileSync(broker.streamPath, JSON.stringify(mkEvent({ level: "attention", event: "guard_denied" })) + "\n", "utf-8");
    await nextFrame(desk); // consume desk's attention
    const phoneAttention = await nextFrame(phone);
    expect(phoneAttention.event.level).toBe("attention");
    expect(phoneAttention.render.speak).toBe(true);
  }, 20_000);
});
