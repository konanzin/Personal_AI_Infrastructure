import { describe, test, expect } from "bun:test";
import {
  classifyPrompt,
  normalizeClassification,
  formatClassificationContext,
  getEffortLabel,
  isAlgorithmMode,
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

  test("classifyPromptWithLLM falls back on timeout", async () => {
    const { classifyPromptWithLLM } = await import("../plugins/lib/mode-classifier.lib.js");
    const result = await classifyPromptWithLLM("hi", {
      model: "opencode/deepseek-v4-flash-free",
      timeoutMs: 1,
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
