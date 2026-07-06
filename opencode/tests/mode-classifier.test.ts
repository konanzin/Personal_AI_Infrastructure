import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import {
  classifyPrompt,
  normalizeClassification,
  formatClassificationContext,
  getEffortLabel,
  isAlgorithmMode,
  resolveClassifierConfig,
} from "../plugins/lib/mode-classifier.lib.js";

describe("Mode Classifier — classifyPrompt", () => {
  describe("MINIMAL mode", () => {
    test("greeting → MINIMAL", () => {
      const result = classifyPrompt("hi");
      expect(result.mode).toBe("MINIMAL");
      expect(result.tier).toBeNull();
      expect(result.source).toBe("heuristic");
    });

    test("hello there → MINIMAL", () => {
      const result = classifyPrompt("hello there");
      expect(result.mode).toBe("MINIMAL");
    });

    test("thanks → MINIMAL", () => {
      const result = classifyPrompt("thanks");
      expect(result.mode).toBe("MINIMAL");
    });

    test("bare number → MINIMAL", () => {
      const result = classifyPrompt("5");
      expect(result.mode).toBe("MINIMAL");
    });

    test("rating command → MINIMAL", () => {
      const result = classifyPrompt("/rate 8 good job");
      expect(result.mode).toBe("MINIMAL");
    });

    test("very short prompt ≤3 chars → MINIMAL", () => {
      const result = classifyPrompt("ok");
      expect(result.mode).toBe("MINIMAL");
    });

    test("Portuguese acknowledgment → MINIMAL", () => {
      const result = classifyPrompt("Valeu, ficou ótimo!");
      expect(result.mode).toBe("MINIMAL");
      expect(result.source).toBe("heuristic");
    });
  });

  describe("NATIVE mode", () => {
    test("single fact lookup → NATIVE", () => {
      const result = classifyPrompt("what is 2+2?");
      expect(result.mode).toBe("NATIVE");
      expect(result.tier).toBeNull();
    });

    test("simple command question → NATIVE", () => {
      const result = classifyPrompt("what does ls -la do?");
      expect(result.mode).toBe("NATIVE");
    });

    test("where is a file → NATIVE", () => {
      const result = classifyPrompt("where is the config file?");
      expect(result.mode).toBe("NATIVE");
    });

    test("single definition → NATIVE", () => {
      const result = classifyPrompt("what's TypeScript?");
      expect(result.mode).toBe("NATIVE");
    });

    test("Portuguese context recall without tools → NATIVE", () => {
      const result = classifyPrompt("Sem usar ferramentas: qual é o nome da minha DA?");
      expect(result.mode).toBe("NATIVE");
      expect(result.source).toBe("heuristic");
    });

    test("TELOS marker recall from startup context → NATIVE", () => {
      const result = classifyPrompt(
        "Sem usar ferramentas nem ler arquivos: diga quais destes marcadores estão no seu contexto inicial e quais não estão: CTX-ID-EARLY-ALPHA, CTX-TELOS-TAIL-DELTA.",
      );
      expect(result.mode).toBe("NATIVE");
      expect(result.source).toBe("heuristic");
    });

    test("Portuguese single shell command request → NATIVE", () => {
      const result = classifyPrompt(
        "Quantos arquivos TypeScript (.ts) existem a partir do diretório atual? Rode um comando de shell para contar e me diga o número.",
      );
      expect(result.mode).toBe("NATIVE");
      expect(result.source).toBe("heuristic");
    });
  });

  describe("ALGORITHM mode", () => {
    test("implementation request → ALGORITHM", () => {
      const result = classifyPrompt("implement a user authentication system");
      expect(result.mode).toBe("ALGORITHM");
      expect(result.tier).toBeDefined();
    });

    test("multi-file refactor → ALGORITHM E3+", () => {
      const result = classifyPrompt("refactor the auth module into multiple files");
      expect(result.mode).toBe("ALGORITHM");
      expect(["E3", "E4", "E5"]).toContain(result.tier);
    });

    test("architecture question → ALGORITHM", () => {
      const result = classifyPrompt("design a microservices architecture for our platform");
      expect(result.mode).toBe("ALGORITHM");
    });

    test("debugging request → ALGORITHM", () => {
      const result = classifyPrompt("fix the bug where login fails intermittently");
      expect(result.mode).toBe("ALGORITHM");
    });

    test("PAI-affecting work → ALGORITHM", () => {
      const result = classifyPrompt("update the PAI algorithm to support new features");
      expect(result.mode).toBe("ALGORITHM");
    });

    test("long complex prompt → ALGORITHM", () => {
      const prompt = "I need you to implement a complete user management system with authentication, authorization, password reset, email verification, and role-based access control. It should use JWT tokens, support OAuth2 providers, and have comprehensive unit and integration tests.";
      const result = classifyPrompt(prompt);
      expect(result.mode).toBe("ALGORITHM");
    });

    test("Portuguese architecture prompt → ALGORITHM via heuristic", () => {
      const result = classifyPrompt(
        "Projete a arquitetura de um app de notas local-first: stack, modelo de dados, estratégia de sincronização e principais trade-offs.",
      );
      expect(result.mode).toBe("ALGORITHM");
      expect(result.source).toBe("heuristic");
    });
  });

  describe("Overrides", () => {
    test("/e1 override forces ALGORITHM E1", () => {
      const result = classifyPrompt("/e1 do something simple");
      expect(result.mode).toBe("ALGORITHM");
      expect(result.tier).toBe("E1");
      expect(result.source).toBe("override");
    });

    test("/e5 override on complex ask → ALGORITHM E5", () => {
      const result = classifyPrompt("/e5 rebuild everything");
      expect(result.mode).toBe("ALGORITHM");
      expect(result.tier).toBe("E5");
      expect(result.source).toBe("override");
    });

    // The /eN slash-commands never deliver a literal "/eN" to the classifier:
    // OpenCode expands them to the template "Run PAI effort EN for: $ARGUMENTS"
    // (opencode.jsonc.template). The override must bind on that path too, or
    // the Principal's explicit tier order silently degrades to a heuristic
    // suggestion (audit finding, 2026-07-05).
    test("expanded /e4 slash-command template binds as override", () => {
      const result = classifyPrompt("Run PAI effort E4 for: refactor the auth module");
      expect(result.mode).toBe("ALGORITHM");
      expect(result.tier).toBe("E4");
      expect(result.source).toBe("override");
    });

    test("expanded template binds for every tier and any case", () => {
      for (const n of [1, 2, 3, 4, 5]) {
        const result = classifyPrompt(`run pai effort e${n} for: some task`);
        expect(result.tier).toBe(`E${n}`);
        expect(result.source).toBe("override");
      }
    });

    test("prose mentioning effort levels without the command shape is not an override", () => {
      const result = classifyPrompt("explain what the PAI effort tiers mean");
      expect(result.source).not.toBe("override");
    });
  });

  describe("Fail-safe", () => {
    test("empty prompt → ALGORITHM E3 fail-safe", () => {
      const result = classifyPrompt("");
      expect(result.mode).toBe("ALGORITHM");
      expect(result.tier).toBe("E3");
      expect(result.source).toBe("fail-safe");
    });

    test("null prompt → ALGORITHM E3 fail-safe", () => {
      const result = classifyPrompt(null);
      expect(result.mode).toBe("ALGORITHM");
      expect(result.tier).toBe("E3");
      expect(result.source).toBe("fail-safe");
    });

    test("undefined prompt → ALGORITHM E3 fail-safe", () => {
      const result = classifyPrompt(undefined);
      expect(result.mode).toBe("ALGORITHM");
      expect(result.tier).toBe("E3");
      expect(result.source).toBe("fail-safe");
    });

    test("ambiguous prompt → ALGORITHM E3", () => {
      const result = classifyPrompt("something maybe");
      expect(result.mode).toBe("ALGORITHM");
      expect(result.tier).toBe("E3");
      expect(result.source).toBe("fail-safe");
    });
  });

  describe("Latency", () => {
    test("classification is fast (<10ms)", () => {
      const result = classifyPrompt("implement a complete e-commerce platform with payment processing, inventory management, and real-time analytics");
      expect(result.latencyMs).toBeGreaterThanOrEqual(0);
      expect(result.latencyMs).toBeLessThan(10);
    });
  });
});

describe("Mode Classifier — normalizeClassification", () => {
  test("normalizes valid result", () => {
    const result = normalizeClassification({
      mode: "ALGORITHM",
      tier: "E3",
      reason: "test",
      source: "heuristic",
      confidence: 0.8,
      latencyMs: 5,
    });
    expect(result.mode).toBe("ALGORITHM");
    expect(result.tier).toBe("E3");
    expect(result.confidence).toBe(0.8);
  });

  test("null input → fail-safe", () => {
    const result = normalizeClassification(null);
    expect(result.mode).toBe("ALGORITHM");
    expect(result.tier).toBe("E3");
    expect(result.source).toBe("fail-safe");
  });

  test("invalid mode → ALGORITHM", () => {
    const result = normalizeClassification({ mode: "INVALID", tier: "E1" });
    expect(result.mode).toBe("ALGORITHM");
  });

  test("non-ALGORITHM mode strips tier", () => {
    const result = normalizeClassification({ mode: "NATIVE", tier: "E3" });
    expect(result.mode).toBe("NATIVE");
    expect(result.tier).toBeNull();
  });

  test("clamps confidence to [0,1]", () => {
    const result = normalizeClassification({ confidence: 1.5 });
    expect(result.confidence).toBe(1.0);
  });
});

describe("Mode Classifier — formatClassificationContext", () => {
  test("formats ALGORITHM with tier", () => {
    const ctx = formatClassificationContext({
      mode: "ALGORITHM", tier: "E3", reason: "Implementation work", source: "heuristic",
    });
    expect(ctx).toContain("ALGORITHM");
    expect(ctx).toContain("E3");
    expect(ctx).toContain("Implementation work");
    expect(ctx).toContain("heuristic");
  });

  test("formats NATIVE without tier", () => {
    const ctx = formatClassificationContext({
      mode: "NATIVE", tier: null, reason: "Fact lookup", source: "heuristic",
    });
    expect(ctx).toContain("NATIVE");
    expect(ctx).not.toContain("Tier:");
  });

  // Drift register W1.2: the pre-classifier is advisory — the primary model
  // self-selects. Only an explicit user /eN override is binding.
  test("non-override classification is presented as a suggestion, never authoritative", () => {
    for (const source of ["heuristic", "llm", "fail-safe"]) {
      const ctx = formatClassificationContext({
        mode: "ALGORITHM", tier: "E3", reason: "x", source,
      });
      expect(ctx).toContain("suggestion");
      expect(ctx).toContain("override it");
      expect(ctx).not.toContain("above self-selection");
      expect(ctx).not.toContain("still follow it");
    }
  });

  test("user /eN override remains binding", () => {
    const ctx = formatClassificationContext({
      mode: "ALGORITHM", tier: "E4", reason: "Explicit override", source: "override",
    });
    expect(ctx).toContain("explicitly requested by the user");
    expect(ctx).toContain("Honor it");
  });
});

describe("Mode Classifier — getEffortLabel", () => {
  test("MINIMAL", () => {
    expect(getEffortLabel({ mode: "MINIMAL" })).toBe("MINIMAL");
  });

  test("NATIVE", () => {
    expect(getEffortLabel({ mode: "NATIVE" })).toBe("NATIVE");
  });

  test("ALGORITHM E3", () => {
    expect(getEffortLabel({ mode: "ALGORITHM", tier: "E3" })).toBe("ALGORITHM E3");
  });
});

describe("Mode Classifier — isAlgorithmMode", () => {
  test("returns true for ALGORITHM", () => {
    expect(isAlgorithmMode({ mode: "ALGORITHM" })).toBe(true);
  });

  test("returns false for NATIVE", () => {
    expect(isAlgorithmMode({ mode: "NATIVE" })).toBe(false);
  });

  test("returns false for null", () => {
    expect(isAlgorithmMode(null)).toBe(false);
  });
});

describe("Mode Classifier — LLM Fallback", () => {
  test("classifyPromptWithLLM falls back to heuristic when no provider", async () => {
    const { classifyPromptWithLLM } = await import("../plugins/lib/mode-classifier.lib.js");
    const result = await classifyPromptWithLLM("implement auth", null);
    expect(result.mode).toBe("ALGORITHM");
    expect(result.source).toBe("heuristic");
  });

  test("classifyPromptWithLLM fail-safes on timeout by default", async () => {
    const { classifyPromptWithLLM } = await import("../plugins/lib/mode-classifier.lib.js");
    const result = await classifyPromptWithLLM("hi", {
      model: "opencode/deepseek-v4-flash-free",
      timeoutMs: 1,
    });
    expect(result.mode).toBe("ALGORITHM");
    expect(result.tier).toBe("E3");
    expect(result.source).toBe("fail-safe");
  });

  test("classifyPromptWithLLM supports explicit heuristic fallback for debug/offline", async () => {
    const { classifyPromptWithLLM } = await import("../plugins/lib/mode-classifier.lib.js");
    const result = await classifyPromptWithLLM("hi", {
      model: "opencode/deepseek-v4-flash-free",
      timeoutMs: 1,
      fallback: "heuristic",
    });
    expect(result.mode).toBe("MINIMAL");
    expect(result.source).toBe("heuristic");
  });

  test("LLM fallback returns valid classification structure", async () => {
    const { classifyPromptWithLLM } = await import("../plugins/lib/mode-classifier.lib.js");
    const result = await classifyPromptWithLLM("implement auth system", null);
    expect(result.mode).toBe("ALGORITHM");
    expect(result.tier).toBeDefined();
    expect(result.reason).toBeDefined();
    expect(result.source).toBe("heuristic");
  });
});

describe("resolveClassifierConfig — precedence", () => {
  test("empty file + empty env → hardcoded defaults (legacy behavior)", () => {
    const cfg = resolveClassifierConfig({}, {});
    expect(cfg.model).toBe("opencode/deepseek-v4-flash-free");
    expect(cfg.useLLM).toBe(true);
    expect(cfg.timeoutMs).toBe(25000);
    expect(cfg.endpoint).toBeNull();
    expect(cfg.apiKey).toBeNull();
  });

  test("file-only values win over hardcoded defaults", () => {
    const cfg = resolveClassifierConfig(
      { model: "openai/gpt-5.5", useLLM: false, timeoutMs: 8000 },
      {},
    );
    expect(cfg.model).toBe("openai/gpt-5.5");
    expect(cfg.useLLM).toBe(false);
    expect(cfg.timeoutMs).toBe(8000);
  });

  test("env var overrides the file (debug escape hatch)", () => {
    const cfg = resolveClassifierConfig(
      { model: "openai/gpt-5.5", useLLM: true },
      { PAI_CLASSIFIER_MODEL: "anthropic/claude-opus", PAI_CLASSIFIER_USE_LLM: "false" },
    );
    expect(cfg.model).toBe("anthropic/claude-opus");
    expect(cfg.useLLM).toBe(false);
  });

  test("PAI_OPENCODE_PROVIDER/MODEL compose into model when PAI_CLASSIFIER_MODEL absent", () => {
    const cfg = resolveClassifierConfig(
      { model: "file/model" },
      { PAI_OPENCODE_PROVIDER: "someprovider", PAI_OPENCODE_MODEL: "somemodel" },
    );
    expect(cfg.model).toBe("someprovider/somemodel");
  });

  test("PAI_CLASSIFIER_MODEL beats PAI_OPENCODE_* composite", () => {
    const cfg = resolveClassifierConfig(
      {},
      {
        PAI_CLASSIFIER_MODEL: "explicit/model",
        PAI_OPENCODE_PROVIDER: "someprovider",
        PAI_OPENCODE_MODEL: "somemodel",
      },
    );
    expect(cfg.model).toBe("explicit/model");
  });

  test("empty-string env var does not override file (treated as unset)", () => {
    const cfg = resolveClassifierConfig(
      { model: "file/model", useLLM: false },
      { PAI_CLASSIFIER_MODEL: "", PAI_CLASSIFIER_USE_LLM: "" },
    );
    expect(cfg.model).toBe("file/model");
    expect(cfg.useLLM).toBe(false);
  });

  test("invalid file shape (array/null) falls back to defaults, no throw", () => {
    expect(resolveClassifierConfig([], {}).model).toBe("opencode/deepseek-v4-flash-free");
    expect(resolveClassifierConfig(null as any, {}).useLLM).toBe(true);
  });

  test("env useLLM accepts 0/no/off as false", () => {
    for (const v of ["0", "no", "off", "FALSE"]) {
      expect(resolveClassifierConfig({}, { PAI_CLASSIFIER_USE_LLM: v }).useLLM).toBe(false);
    }
    expect(resolveClassifierConfig({}, { PAI_CLASSIFIER_USE_LLM: "1" }).useLLM).toBe(true);
  });

  test("file useLLM only honored when boolean (non-boolean → default true)", () => {
    expect(resolveClassifierConfig({ useLLM: "false" as any }, {}).useLLM).toBe(true);
    expect(resolveClassifierConfig({ useLLM: false }, {}).useLLM).toBe(false);
  });
});

describe("Mode Classifier — PAI meta-command bypass (→ NATIVE, never ALGORITHM)", () => {
  // Uses the ACTUAL expanded command templates from the config so this test
  // catches drift if a template is reworded away from its classifier signature.
  const templateOf = (name: string) => {
    const cfg = readFileSync(
      new URL("../config/opencode.jsonc.template", import.meta.url),
      "utf-8",
    );
    // crude: find the command block's "template" string
    const re = new RegExp(`"${name}"\\s*:\\s*\\{[\\s\\S]*?"template"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"`);
    const m = cfg.match(re);
    return m ? m[1] : "";
  };

  for (const cmd of ["classifier", "status", "pulse", "pu", "voice", "context-search"]) {
    test(`/${cmd} expanded template classifies NATIVE`, () => {
      const tpl = templateOf(cmd).replace(/\$ARGUMENTS/g, "foo");
      expect(tpl.length).toBeGreaterThan(0);
      const result = classifyPrompt(tpl);
      expect(result.mode).toBe("NATIVE");
    });
  }

  test("/pai template still enters ALGORITHM (not bypassed)", () => {
    const tpl = "Execute the PAI Algorithm for: refactor the auth module";
    expect(classifyPrompt(tpl).mode).toBe("ALGORITHM");
  });
});
