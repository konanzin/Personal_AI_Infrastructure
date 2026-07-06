import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync, readdirSync } from "fs";
import { join } from "path";

const agentsDir = join(import.meta.dir, "../agents");

type AgentBoundary = "read-only" | "auditor" | "custodian" | "code-producer";

type ExpectedAgent = {
  file: string;
  boundary: AgentBoundary;
  edit: "allow" | "ask" | "deny";
  bash: "allow" | "ask" | "deny" | "scoped";
  requiredAllowedBash?: string[];
};

const EXPECTED_AGENTS: ExpectedAgent[] = [
  { file: "Cato.md", boundary: "read-only", edit: "deny", bash: "scoped", requiredAllowedBash: ["test -f *CrossVendorAudit.ts", "bun *CrossVendorAudit.ts*"] },
  { file: "Arthur.md", boundary: "custodian", edit: "deny", bash: "scoped", requiredAllowedBash: ["test -f *Arthur.ts", "bun *Arthur.ts*"] },
  { file: "Forge.md", boundary: "code-producer", edit: "deny", bash: "scoped", requiredAllowedBash: ["command -v codex", "test -f *ForgeProgress.ts", "bun *ForgeProgress.ts*"] },
  { file: "Anvil.md", boundary: "code-producer", edit: "deny", bash: "scoped", requiredAllowedBash: ["test -f *AnvilProgress.ts", "bun *AnvilProgress.ts*"] },
  { file: "Engineer.md", boundary: "code-producer", edit: "allow", bash: "allow" },
  { file: "ClaudeResearcher.md", boundary: "read-only", edit: "deny", bash: "ask" },
  { file: "CodexResearcher.md", boundary: "read-only", edit: "deny", bash: "ask" },
  { file: "GeminiResearcher.md", boundary: "read-only", edit: "deny", bash: "ask" },
  { file: "GrokResearcher.md", boundary: "read-only", edit: "deny", bash: "ask" },
  { file: "PerplexityResearcher.md", boundary: "read-only", edit: "deny", bash: "ask" },
  { file: "Silas.md", boundary: "auditor", edit: "ask", bash: "ask" },
];

function frontmatter(file: string): string {
  const text = readFileSync(join(agentsDir, file), "utf-8");
  const match = text.match(/^---\n([\s\S]*?)\n---/);
  if (!match) throw new Error(`${file} has no frontmatter`);
  return match[1];
}

function description(fm: string): string {
  return fm.match(/^description:\s*(.*)$/m)?.[1] ?? "";
}

function permissionBlock(fm: string): string {
  const lines = fm.split(/\r?\n/);
  const start = lines.findIndex((line) => line === "permission:");
  if (start < 0) return "";
  const out: string[] = [];
  for (let i = start + 1; i < lines.length; i += 1) {
    const line = lines[i];
    if (/^\S/.test(line)) break;
    out.push(line);
  }
  return out.join("\n");
}

function scalarPermission(block: string, tool: string): string | null {
  const match = block.match(new RegExp(`^  ${tool}:\\s*(allow|ask|deny)\\s*$`, "m"));
  return match?.[1] ?? null;
}

function mapPermissionBlock(block: string, tool: string): string {
  const lines = block.split(/\r?\n/);
  const start = lines.findIndex((line) => line === `  ${tool}:`);
  if (start < 0) return "";
  const out: string[] = [];
  for (let i = start + 1; i < lines.length; i += 1) {
    const line = lines[i];
    if (/^  \S/.test(line)) break;
    out.push(line);
  }
  return out.join("\n");
}

describe("Agent frontmatter permission boundaries", () => {
  test("boundary prose cannot appear without explicit permission frontmatter", () => {
    const boundaryLanguage = /read-only|called BY Research|auditor|security audits|Credential Custodian|Writes code|implementation work/i;
    const files = readdirSync(agentsDir).filter((file) => file.endsWith(".md"));
    const missing = files.filter((file) => {
      const fm = frontmatter(file);
      return boundaryLanguage.test(description(fm)) && permissionBlock(fm) === "";
    });
    expect(missing).toEqual([]);
  });

  for (const expected of EXPECTED_AGENTS) {
    test(`${expected.file} declares explicit ${expected.boundary} permissions in frontmatter`, () => {
      expect(existsSync(join(agentsDir, expected.file))).toBe(true);
      const block = permissionBlock(frontmatter(expected.file));
      expect(block).not.toBe("");

      for (const tool of ["read", "glob", "grep", "list"] as const) {
        expect(scalarPermission(block, tool)).toBe("allow");
      }
      expect(scalarPermission(block, "edit")).toBe(expected.edit);
      expect(scalarPermission(block, "task")).toBe("deny");

      if (expected.bash === "scoped") {
        const bashBlock = mapPermissionBlock(block, "bash");
        expect(bashBlock).toContain('"*": deny');
        for (const allowed of expected.requiredAllowedBash ?? []) {
          expect(bashBlock).toContain(`"${allowed}": allow`);
        }
      } else {
        expect(scalarPermission(block, "bash")).toBe(expected.bash);
      }
    });
  }
});
