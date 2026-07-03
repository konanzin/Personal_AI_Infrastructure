import { describe, expect, test } from "bun:test";
import { spawnSync } from "child_process";
import { existsSync, mkdtempSync, readdirSync } from "fs";
import { homedir, tmpdir } from "os";
import { join } from "path";
import { fileURLToPath } from "url";

import {
  shellQuoteSingle,
  shouldSandboxCommand,
  resolveSandboxScript,
  wrapBashInSandbox,
} from "../plugins/lib/pai-hooks.lib.js";

const opencodeRoot = fileURLToPath(new URL("..", import.meta.url));
const SANDBOX_SH = join(opencodeRoot, "bin/pai-sandbox.sh");
const BWRAP = ["/usr/bin/bwrap", "/usr/local/bin/bwrap", "/bin/bwrap"].some(existsSync);

function runSandboxed(cmd: string, cwd?: string) {
  return spawnSync("bash", [SANDBOX_SH, cmd], { cwd, encoding: "utf-8", timeout: 30000 });
}

describe("Sandbox — decision logic (shouldSandboxCommand)", () => {
  test("plain commands are sandboxed", () => {
    expect(shouldSandboxCommand("ls -la", {})).toBe(true);
    expect(shouldSandboxCommand("bun test", {})).toBe(true);
  });

  test("session kill switch PAI_SANDBOX=off disables wrapping", () => {
    expect(shouldSandboxCommand("ls", { PAI_SANDBOX: "off" })).toBe(false);
  });

  test("human-approved escape prefix runs unwrapped (gated by 'ask' in opencode.jsonc)", () => {
    expect(shouldSandboxCommand("PAI_SANDBOX=off bun install", {})).toBe(false);
  });

  test("sudo commands are not wrapped (own ask boundary; no sudo in userns)", () => {
    expect(shouldSandboxCommand("sudo pacman -Syu", {})).toBe(false);
  });

  test("already-wrapped commands are not double-wrapped", () => {
    expect(shouldSandboxCommand(`${SANDBOX_SH} 'ls'`, {})).toBe(false);
  });

  test("empty/non-string commands are not wrapped", () => {
    expect(shouldSandboxCommand("", {})).toBe(false);
    expect(shouldSandboxCommand(undefined as unknown as string, {})).toBe(false);
  });
});

describe("Sandbox — wrapping (wrapBashInSandbox)", () => {
  test("PAI_SANDBOX_BIN overrides the script path", () => {
    expect(resolveSandboxScript({ PAI_SANDBOX_BIN: "/x/sb.sh" })).toBe("/x/sb.sh");
    expect(wrapBashInSandbox("ls", { PAI_SANDBOX_BIN: "/x/sb.sh" })).toBe("/x/sb.sh 'ls'");
  });

  test("single quotes in the command survive quoting", () => {
    const wrapped = wrapBashInSandbox("echo 'a b'", { PAI_SANDBOX_BIN: "/x/sb.sh" });
    // Round-trip through a real shell to prove the quoting is correct.
    const out = spawnSync("bash", ["-c", wrapped.replace("/x/sb.sh", "printf %s")], {
      encoding: "utf-8",
    });
    expect(out.stdout).toBe("echo 'a b'");
  });

  test(`shellQuoteSingle escapes embedded single quotes`, () => {
    expect(shellQuoteSingle(`a'b`)).toBe(`'a'\\''b'`);
  });
});

describe.if(BWRAP)("Sandbox — bwrap confinement (functional)", () => {
  test("simple command works and exit code propagates", () => {
    expect(runSandboxed("echo hi").stdout.trim()).toBe("hi");
    expect(runSandboxed("exit 7").status).toBe(7);
  });

  test("write inside the working directory is allowed", () => {
    const dir = mkdtempSync(join(tmpdir(), "pai-sbx-"));
    const r = runSandboxed("touch inside.txt && cat /etc/hostname > /dev/null", dir);
    expect(r.status).toBe(0);
    expect(existsSync(join(dir, "inside.txt"))).toBe(true);
  });

  test("write outside the working directory is blocked, with escalation hint", () => {
    const dir = mkdtempSync(join(tmpdir(), "pai-sbx-"));
    const target = join(homedir(), `.pai-sbx-escape-${process.pid}`);
    const r = runSandboxed(`touch ${target}`, dir);
    expect(r.status).not.toBe(0);
    expect(existsSync(target)).toBe(false);
    expect(r.stderr).toContain("[PAI-SANDBOX]");
    expect(r.stderr).toContain("PAI_SANDBOX=off");
  });

  test.if(existsSync(join(homedir(), ".ssh")) && readdirSync(join(homedir(), ".ssh")).length > 0)(
    "~/.ssh is masked (visible but empty)",
    () => {
      const r = runSandboxed("ls -A ~/.ssh | wc -l");
      expect(r.status).toBe(0);
      expect(r.stdout.trim()).toBe("0");
    },
  );

  test.if(existsSync(join(process.env.PAI_DIR || join(homedir(), ".config/opencode/PAI"), "USER")))(
    "PAI/USER (life data) is masked",
    () => {
      const r = runSandboxed('ls -A "${PAI_DIR:-$HOME/.config/opencode/PAI}/USER" | wc -l');
      expect(r.status).toBe(0);
      expect(r.stdout.trim()).toBe("0");
    },
  );

  test("network stays available in T1 (loopback resolvable path unaffected)", () => {
    // No external traffic: just prove the netns was NOT unshared by checking
    // a non-loopback interface is still visible inside the sandbox.
    const r = runSandboxed("ip -o link show | grep -cv 'lo:'");
    expect(r.status).toBe(0);
    expect(Number(r.stdout.trim())).toBeGreaterThan(0);
  });
});

describe("Sandbox — plugin integration (tool.execute.before mutates output.args)", () => {
  const pluginPath = join(opencodeRoot, "plugins/pai-hooks.js");
  const mockContext = { project: {}, client: {}, $: {}, directory: "/tmp", worktree: "/tmp" };
  const loadPlugin = async () => (await import(pluginPath)).default(mockContext);

  test("wraps a safe command when sandbox is available", async () => {
    process.env.PAI_SANDBOX_BIN = SANDBOX_SH;
    delete process.env.PAI_SANDBOX;
    try {
      const plugin = await loadPlugin();
      const output = { args: { command: "echo hi" } };
      await plugin["tool.execute.before"]({ tool: "bash", sessionID: "s", callID: "c" }, output);
      if (BWRAP) {
        expect(output.args.command).toContain("pai-sandbox.sh");
        expect(output.args.command).toContain("'echo hi'");
      } else {
        expect(output.args.command).toBe("echo hi"); // fail-open without bwrap
      }
    } finally {
      delete process.env.PAI_SANDBOX_BIN;
    }
  });

  test("PAI_SANDBOX=off leaves the command untouched", async () => {
    process.env.PAI_SANDBOX_BIN = SANDBOX_SH;
    process.env.PAI_SANDBOX = "off";
    try {
      const plugin = await loadPlugin();
      const output = { args: { command: "echo hi" } };
      await plugin["tool.execute.before"]({ tool: "bash", sessionID: "s", callID: "c" }, output);
      expect(output.args.command).toBe("echo hi");
    } finally {
      delete process.env.PAI_SANDBOX_BIN;
      delete process.env.PAI_SANDBOX;
    }
  });

  test("the deny floor still sees the ORIGINAL command (inspection before wrap)", async () => {
    process.env.PAI_SANDBOX_BIN = SANDBOX_SH;
    try {
      const plugin = await loadPlugin();
      await expect(
        plugin["tool.execute.before"](
          { tool: "bash", sessionID: "s", callID: "c" },
          { args: { command: "rm -rf /" } },
        ),
      ).rejects.toThrow(/PAI SECURITY.*BLOCKED/);
    } finally {
      delete process.env.PAI_SANDBOX_BIN;
    }
  });
});
