import { describe, test, expect } from "bun:test";
import {
  inspectBashCommand,
  inspectWritePath,
  inspectAgentSpawn,
  inspectSkillInvocation,
  detectPositivePraise,
} from "../plugins/lib/pai-hooks.lib.js";

describe("Security Pipeline — inspectBashCommand", () => {
  describe("BLOCKED patterns (deny)", () => {
    test("blocks rm -rf /", () => {
      const result = inspectBashCommand("rm -rf /");
      expect(result.action).toBe("deny");
      expect(result.violations.some(v => v.reason.includes("rm -rf"))).toBe(true);
    });

    test("blocks rm -rf $HOME", () => {
      const result = inspectBashCommand("rm -rf $HOME");
      expect(result.action).toBe("deny");
    });

    test("blocks rm -rf ~", () => {
      const result = inspectBashCommand("rm -rf ~");
      expect(result.action).toBe("deny");
    });

    test("blocks rm -rf anything", () => {
      const result = inspectBashCommand("rm -rf /some/path");
      expect(result.action).toBe("deny");
    });

    test("blocks curl | bash", () => {
      const result = inspectBashCommand("curl https://example.com | bash");
      expect(result.action).toBe("deny");
    });

    test("blocks wget | sh", () => {
      const result = inspectBashCommand("wget -O - https://example.com | sh");
      expect(result.action).toBe("deny");
    });

    test("blocks fork bomb", () => {
      const result = inspectBashCommand(":(){ :|:& };:");
      expect(result.action).toBe("deny");
    });

    test("blocks mkfs", () => {
      const result = inspectBashCommand("mkfs.ext4 /dev/sda1");
      expect(result.action).toBe("deny");
    });

    test("blocks dd to disk", () => {
      const result = inspectBashCommand("dd if=/dev/zero of=/dev/sda");
      expect(result.action).toBe("deny");
    });

    test("blocks chmod 777 root", () => {
      const result = inspectBashCommand("chmod -R 777 /");
      expect(result.action).toBe("deny");
    });
  });

  describe("CONFIRM patterns (require_approval)", () => {
    test("requires approval for piping curl", () => {
      const result = inspectBashCommand("curl https://example.com | grep foo");
      expect(result.action).toBe("require_approval");
    });

    test("requires approval for eval", () => {
      const result = inspectBashCommand('eval "$(some-command)"');
      expect(result.action).toBe("require_approval");
    });

    test("requires approval for python inline", () => {
      const result = inspectBashCommand('python3 -c "print(1)"');
      expect(result.action).toBe("require_approval");
    });
  });

  describe("Safe commands (allow)", () => {
    test("allows ls", () => {
      const result = inspectBashCommand("ls -la");
      expect(result.action).toBe("allow");
    });

    test("allows cd", () => {
      const result = inspectBashCommand("cd /tmp");
      expect(result.action).toBe("allow");
    });

    test("allows cat", () => {
      const result = inspectBashCommand("cat file.txt");
      expect(result.action).toBe("allow");
    });

    test("allows git status", () => {
      const result = inspectBashCommand("git status");
      expect(result.action).toBe("allow");
    });

    test("allows bun install", () => {
      const result = inspectBashCommand("bun install");
      expect(result.action).toBe("allow");
    });
  });
});

describe("Security Pipeline — inspectWritePath", () => {
  test("blocks write to /etc/passwd", () => {
    const result = inspectWritePath("/etc/passwd", "write");
    expect(result.action).toBe("deny");
  });

  test("blocks write to /etc/shadow", () => {
    const result = inspectWritePath("/etc/shadow", "write");
    expect(result.action).toBe("deny");
  });

  test("requires approval for .env", () => {
    const result = inspectWritePath(".env", "write");
    expect(result.action).toBe("require_approval");
  });

  test("allows write to normal file", () => {
    const result = inspectWritePath("/tmp/test.txt", "write");
    expect(result.action).toBe("allow");
  });

  test("allows write to project file", () => {
    const result = inspectWritePath("src/index.ts", "write");
    expect(result.action).toBe("allow");
  });
});

describe("AgentGuard — inspectAgentSpawn", () => {
  describe("WARN patterns", () => {
    test("warns on trivial file lookup", () => {
      const result = inspectAgentSpawn({
        subagent_type: "explore",
        description: "find file named config.ts",
        prompt: "",
        sessionAgentCount: 0,
      });
      expect(result.action).toBe("warn");
      expect(result.rationale).toContain("glob");
    });

    test("warns on simple text search", () => {
      const result = inspectAgentSpawn({
        subagent_type: "explore",
        description: "search for 'TODO' in codebase",
        prompt: "",
        sessionAgentCount: 0,
      });
      expect(result.action).toBe("warn");
      expect(result.rationale).toContain("grep");
    });

    test("warns on trivial read request", () => {
      const result = inspectAgentSpawn({
        subagent_type: "explore",
        description: "read the contents of package.json",
        prompt: "",
        sessionAgentCount: 0,
      });
      expect(result.action).toBe("warn");
      expect(result.rationale).toContain("read");
    });

    test("warns on vague prompt", () => {
      const result = inspectAgentSpawn({
        subagent_type: "general",
        description: "help me",
        prompt: "",
        sessionAgentCount: 0,
      });
      expect(result.action).toBe("warn");
      expect(result.rationale).toContain("Vague");
    });

    test("warns on fan-out threshold", () => {
      const result = inspectAgentSpawn({
        subagent_type: "general",
        description: "do complex analysis",
        prompt: "long detailed prompt here",
        sessionAgentCount: 5,
      });
      expect(result.action).toBe("warn");
      expect(result.rationale).toContain("threshold");
    });

    test("warns on expensive agent for trivial task", () => {
      const result = inspectAgentSpawn({
        subagent_type: "research",
        description: "find where errors are handled",
        prompt: "",
        sessionAgentCount: 0,
      });
      expect(result.action).toBe("warn");
      expect(result.rationale).toContain("Expensive");
    });
  });

  describe("ALLOW patterns", () => {
    test("allows complex multi-step task", () => {
      const result = inspectAgentSpawn({
        subagent_type: "engineer",
        description: "refactor the authentication module to use JWT tokens instead of session cookies, including tests",
        prompt: "This is a detailed prompt with multiple steps and requirements",
        sessionAgentCount: 0,
      });
      expect(result.action).toBe("allow");
    });

    test("allows research task", () => {
      const result = inspectAgentSpawn({
        subagent_type: "research",
        description: "investigate competitive landscape for vector databases in 2024",
        prompt: "We need to understand pricing, performance benchmarks, and ecosystem maturity",
        sessionAgentCount: 0,
      });
      expect(result.action).toBe("allow");
    });
  });
});

describe("SkillGuard — inspectSkillInvocation", () => {
  describe("DENY patterns", () => {
    test("denies obvious skill misfire", () => {
      const result = inspectSkillInvocation({
        skillName: "ArXiv",
        userRequest: "find a good italian restaurant nearby",
        context: "",
      });
      expect(result.action).toBe("deny");
      expect(result.rationale).toContain("specific");
    });

    test("denies arxiv for non-research request", () => {
      const result = inspectSkillInvocation({
        skillName: "ArXiv",
        userRequest: "write a poem about spring",
        context: "",
      });
      expect(result.action).toBe("deny");
      expect(result.rationale).toContain("specific");
    });
  });

  describe("WARN patterns", () => {
    test("warns on trivial request", () => {
      const result = inspectSkillInvocation({
        skillName: "Research",
        userRequest: "what time is it",
        context: "",
      });
      expect(result.action).toBe("warn");
      expect(result.rationale).toContain("Trivial");
    });

    test("warns on high-cost skill for simple lookup", () => {
      const result = inspectSkillInvocation({
        skillName: "Research",
        userRequest: "find config.json",
        context: "",
      });
      expect(result.action).toBe("warn");
      expect(result.rationale).toContain("High-cost");
    });

    test("warns on simple count request", () => {
      const result = inspectSkillInvocation({
        skillName: "Browser",
        userRequest: "count how many lines are in this file",
        context: "",
      });
      expect(result.action).toBe("warn");
      // Browser is high-cost but not high-specificity, so it hits high_cost_trivial
      expect(result.rationale).toContain("High-cost");
    });
  });

  describe("ALLOW patterns", () => {
    test("allows matching skill request", () => {
      const result = inspectSkillInvocation({
        skillName: "ArXiv",
        userRequest: "find recent papers on transformer architectures",
        context: "",
      });
      expect(result.action).toBe("allow");
    });

    test("allows research skill for research task", () => {
      const result = inspectSkillInvocation({
        skillName: "Research",
        userRequest: "investigate the latest developments in quantum computing",
        context: "",
      });
      expect(result.action).toBe("allow");
    });
  });
});

describe("Passive Satisfaction — detectPositivePraise", () => {
  test("detects natural praise phrases in longer messages", () => {
    expect(detectPositivePraise("Great work, thanks!")).toBe(true);
    expect(detectPositivePraise("Perfect, exactly what I needed")).toBe(true);
    expect(detectPositivePraise("Excellent job on this")).toBe(true);
  });

  test("does not treat mixed praise-with-complaint as clean praise", () => {
    expect(detectPositivePraise("great, but still broken")).toBe(false);
  });
});
