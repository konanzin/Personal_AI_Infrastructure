import { describe, expect, test } from "bun:test";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, statSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { fileURLToPath } from "url";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));
const opencodeRoot = join(repoRoot, "opencode");
const installScript = join(opencodeRoot, "install.sh");
const manifestPath = join(opencodeRoot, "install-manifest.json");

interface InstallManifest {
  agents: string[];
  commands: string[];
  skills: string[];
}

const manifest = JSON.parse(await Bun.file(manifestPath).text()) as InstallManifest;

function sorted(values: string[]) {
  return [...values].sort((a, b) => a.localeCompare(b));
}

function repoFiles(dir: string, suffix: string) {
  return sorted(readdirSync(dir).filter((name) => name.endsWith(suffix)));
}

function repoDirs(dir: string) {
  return sorted(
    readdirSync(dir).filter((name) => statSync(join(dir, name)).isDirectory()),
  );
}

function write(path: string, content = "") {
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, content, "utf-8");
}

async function seedCleanInstall(home: string) {
  const opencodeHome = join(home, ".config/opencode");
  const agentsDir = join(opencodeHome, "agents");
  const commandsDir = join(opencodeHome, "commands");
  const skillsDir = join(opencodeHome, "skills");
  const paiDir = join(opencodeHome, "PAI");

  mkdirSync(agentsDir, { recursive: true });
  mkdirSync(commandsDir, { recursive: true });
  mkdirSync(skillsDir, { recursive: true });
  mkdirSync(join(opencodeHome, "plugins"), { recursive: true });
  mkdirSync(join(opencodeHome, "docs"), { recursive: true });
  mkdirSync(join(paiDir, "schemas"), { recursive: true });
  mkdirSync(join(paiDir, "bin"), { recursive: true });
  mkdirSync(join(paiDir, "TOOLS"), { recursive: true });

  for (const agent of manifest.agents) write(join(agentsDir, agent));
  for (const command of manifest.commands) write(join(commandsDir, command));
  for (const skill of manifest.skills) mkdirSync(join(skillsDir, skill), { recursive: true });

  const template = Bun.file(join(opencodeRoot, "config/opencode.jsonc.template"));
  const rendered = (await template.text()).replace(
    '"./plugins/pai-hooks.js"',
    `"${join(opencodeHome, "plugins/pai-hooks.js")}"`,
  );
  write(join(opencodeHome, "opencode.jsonc"), rendered);
  write(join(opencodeHome, "docs/OBSERVABILITY_CONTRACTS.md"), "# Contracts\n");
  for (const schema of repoFiles(join(opencodeRoot, "schemas"), ".json")) {
    write(join(paiDir, "schemas", schema), "{}\n");
  }
  write(join(paiDir, "bin/validate-doc-integrity.js"), "#!/usr/bin/env bun\n");
  chmodSync(join(paiDir, "bin/validate-doc-integrity.js"), 0o755);
  write(join(paiDir, "bin/validate-tools-manifest.js"), await Bun.file(join(opencodeRoot, "bin/validate-tools-manifest.js")).text());
  chmodSync(join(paiDir, "bin/validate-tools-manifest.js"), 0o755);
  write(join(paiDir, "TOOLS/manifest.json"), JSON.stringify({ version: 1, runtime: "opencode", tools: {} }, null, 2));
  // Seed the REAL template — --check now compares the installed policy's version
  // line against Patterns.example.yaml, so a synthetic version would read as stale.
  write(
    join(paiDir, "USER/SECURITY/PATTERNS.yaml"),
    await Bun.file(join(repoRoot, "PAI/DOCUMENTATION/Security/Patterns.example.yaml")).text(),
  );
  // T1 sandbox wrapper — a real install always ships it; --check asserts its presence.
  write(join(paiDir, "bin/pai-sandbox.sh"), "#!/usr/bin/env bash\nexec /bin/bash -c \"$1\"\n");
  chmodSync(join(paiDir, "bin/pai-sandbox.sh"), 0o755);
  // O5 health timer — a real install writes + enables it; enablement is the
  // timers.target.wants/ symlink, which --check probes file-based.
  const unitDir = join(home, ".config/systemd/user");
  write(join(unitDir, "pai-health.timer"), "[Timer]\nOnCalendar=daily\n");
  mkdirSync(join(unitDir, "timers.target.wants"), { recursive: true });
  writeFileSync(join(unitDir, "timers.target.wants/pai-health.timer"), "[Timer]\nOnCalendar=daily\n");
}

function runCheck(home: string) {
  return Bun.spawnSync({
    cmd: ["bash", installScript, "--check"],
    // PAI_SANDBOX=off makes the T1 sandbox drift check deterministic here: --check
    // otherwise runs a live bwrap confinement probe, which would depend on the host's
    // user-namespace support. The sandbox wiring is grep-tested separately below, and
    // the probe itself is exercised directly; this test targets manifest/config drift.
    env: { ...process.env, HOME: home, PAI_SANDBOX: "off" },
    stdout: "pipe",
    stderr: "pipe",
  });
}

function outputOf(result: ReturnType<typeof runCheck>) {
  return `${result.stdout.toString()}\n${result.stderr.toString()}`;
}

type BashRule = { pattern: string; action: string };

function bashRules(template: string): BashRule[] {
  const block = template.match(/"bash":\s*\{[\s\S]*?\n\s*\}/)?.[0] ?? "";
  return [...block.matchAll(/^\s+"([^"]+)":\s*"(allow|ask|deny)"/gm)].map((match) => ({
    pattern: match[1],
    action: match[2],
  }));
}

function matchesCommandPattern(command: string, pattern: string): boolean {
  const regex = new RegExp(`^${pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*")}$`);
  return regex.test(command);
}

function simulatedBashPermission(command: string, rules: BashRule[]): string | null {
  let decision: string | null = null;
  for (const rule of rules) {
    if (matchesCommandPattern(command, rule.pattern)) decision = rule.action;
  }
  return decision;
}

describe("Installer hygiene", () => {
  test("install manifest tracks repo agents, commands, and skills", () => {
    expect(sorted(manifest.agents)).toEqual(repoFiles(join(opencodeRoot, "agents"), ".md"));
    expect(sorted(manifest.commands)).toEqual(repoFiles(join(opencodeRoot, "commands"), ".md"));
    expect(sorted(manifest.skills)).toEqual(repoDirs(join(repoRoot, "skills")));
  });

  test("validators have ONE source: no repo PAI/bin mirror, installer copies opencode/bin only (W2.9)", async () => {
    // The repo used to carry a PAI/bin mirror of opencode/bin. It kept going
    // stale (shipped the deepseek pin and pre-W1.1 assertions long after the
    // canonical copies were fixed) and the installer copied it FIRST, relying
    // on a later overwrite to mask the drift. Single source now: $PAI_DIR/bin
    // is populated exclusively from opencode/bin.
    expect(existsSync(join(repoRoot, "PAI/bin"))).toBe(false);
    const installSh = await Bun.file(join(opencodeRoot, "install.sh")).text();
    const treeCopyLine = installSh.match(/for dir in ([^;]*); do/)?.[1] ?? "";
    expect(treeCopyLine).not.toContain(" bin");
  });

  test("install.sh --check passes when generated artifacts match the manifest", async () => {
    const home = mkdtempSync(join(tmpdir(), "pai-install-clean-"));
    await seedCleanInstall(home);

    const result = runCheck(home);
    expect(outputOf(result)).toContain("Installed runtime matches manifest");
    expect(result.exitCode).toBe(0);
  }, 30000);

  test("install.sh --check fails when stale skills are installed", async () => {
    const home = mkdtempSync(join(tmpdir(), "pai-install-drift-"));
    await seedCleanInstall(home);
    mkdirSync(join(home, ".config/opencode/skills/interceptor-browser"), { recursive: true });

    const result = runCheck(home);
    expect(outputOf(result)).toContain("interceptor-browser");
    expect(result.exitCode).toBe(1);
  }, 30000);

  test("patch_installed_paths never rewrites the security policy's deliberate ~/.claude refs", () => {
    // The policy's `~/.claude/.credentials.json` zero-access entry targets the
    // reference harness's REAL credential file — it is a deny pattern, not a
    // legacy port path. The blanket ~/.claude → ~/.config/opencode rewrite
    // turned that deny into allow on a live install (2026-07-07), and the seed
    // runs BEFORE the patcher, so every fresh install was born with the hole.
    // This runs the real function from install.sh against a fake tree.
    const home = mkdtempSync(join(tmpdir(), "pai-patch-exempt-"));
    const paiDir = join(home, ".config/opencode/PAI");
    const policyPath = join(paiDir, "USER/SECURITY/PATTERNS.yaml");
    const mirrorPath = join(paiDir, "plugins/lib/pai-hooks.lib.js");
    const templatePath = join(paiDir, "DOCUMENTATION/Security/Patterns.example.yaml");
    const docPath = join(paiDir, "DOCUMENTATION/Some/Doc.md");
    write(policyPath, "zeroAccess:\n  - '~/.claude/.credentials.json'\n");
    write(mirrorPath, "const ZERO = ['~/.claude/.credentials.json'];\n");
    write(templatePath, "zeroAccess:\n  - '~/.claude/.credentials.json'\n");
    write(docPath, "Legacy path: ~/.claude/skills/foo\n");

    const install = readFileSync(installScript, "utf-8");
    const fn = install.match(/^patch_installed_paths\(\) \{[\s\S]*?\n\}/m)?.[0];
    expect(fn).toBeDefined();
    const result = Bun.spawnSync({
      cmd: [
        "bash", "-c",
        `log() { :; }; success() { :; }
         SKILLS_DIR="${join(home, ".config/opencode/skills")}"
         AGENTS_DIR="${join(home, ".config/opencode/agents")}"
         COMMANDS_DIR="${join(home, ".config/opencode/commands")}"
         PAI_DIR="${paiDir}"
         ${fn}
         patch_installed_paths`,
      ],
      stdout: "pipe",
      stderr: "pipe",
    });
    expect(result.exitCode).toBe(0);
    // Deliberate security refs survive — in the live policy, the seed template,
    // and the repo-canonical lib mirror.
    expect(readFileSync(policyPath, "utf-8")).toContain("~/.claude/.credentials.json");
    expect(readFileSync(templatePath, "utf-8")).toContain("~/.claude/.credentials.json");
    expect(readFileSync(mirrorPath, "utf-8")).toContain("~/.claude/.credentials.json");
    // ...while genuine legacy paths elsewhere still get patched.
    expect(readFileSync(docPath, "utf-8")).toContain("~/.config/opencode/skills/foo");
  });

  test("install.sh --check fails when the installed security policy is STALE", async () => {
    // The policy is seeded only when absent, so template improvements never
    // propagate on their own — a real install ran an old policy for months.
    // --check compares the version line against Patterns.example.yaml.
    const home = mkdtempSync(join(tmpdir(), "pai-install-stale-policy-"));
    await seedCleanInstall(home);
    writeFileSync(
      join(home, ".config/opencode/PAI/USER/SECURITY/PATTERNS.yaml"),
      'version: "3.1-opencode"\nbash:\n  blocked:\n    - pattern: "x"\n      reason: "y"\npaths:\n  zeroAccess:\n    - "/etc/shadow"\n',
      "utf-8",
    );

    const result = runCheck(home);
    expect(outputOf(result)).toContain("Security policy STALE");
    expect(result.exitCode).toBe(1);
  }, 30000);

  test("plugin array is pai-hooks only (no third-party plugins)", async () => {
    const template = await Bun.file(join(opencodeRoot, "config/opencode.jsonc.template")).text();
    const pluginLine = template.split("\n").find((l) => l.includes('"plugin"') && !l.trimStart().startsWith("//"));
    expect(pluginLine).toBeDefined();
    expect(pluginLine).toContain("pai-hooks.js");
    expect(pluginLine).not.toContain("opencode-sandbox");
  });

  test("bash posture matches original PAI: allow by default, ask only on boundary crossings", async () => {
    const template = await Bun.file(join(opencodeRoot, "config/opencode.jsonc.template")).text();
    const bashBlock = template.match(/"bash":\s*\{[\s\S]*?\}/)?.[0] ?? "";
    expect(bashBlock).toContain('"*": "allow"');
    expect(bashBlock).not.toContain('"*": "ask"');
    // Boundary crossings that must still prompt: privilege escalation,
    // escaping the T1 sandbox, and deleting the security floor itself.
    // The escape must be a real command token, not an env-var prefix —
    // opencode drops variable_assignment nodes before matching, so an
    // env prefix would never gate (it would escape silently).
    expect(bashBlock).toMatch(/"sudo \*":\s*"ask"/);
    expect(bashBlock).toMatch(/"pai-nosandbox \*":\s*"ask"/);
    expect(bashBlock).not.toContain("PAI_SANDBOX=off");
    expect(bashBlock).toMatch(/pai-hooks\.lib\.js":\s*"ask"/);
    // High-blast-radius external mutations are not part of the normal
    // allow-by-default bash lane. They use native ask so the rare prompt
    // remains meaningful instead of training approval reflexes.
    for (const boundary of [
      "git push",
      "git push *",
      "gh pr *",
      "gh issue *",
      "gh release *",
      "sendmail *",
      "npm publish*",
      "bun publish*",
      "bun run deploy*",
      "wrangler deploy*",
      "vercel deploy*",
      "terraform apply*",
    ]) {
      expect(bashBlock).toContain(`"${boundary}": "ask"`);
    }
    const rules = bashRules(template);
    for (const command of [
      "git push",
      "git push origin main",
      "gh pr create --title hi",
      "gh issue comment 1 --body hi",
      "sendmail person@example.com",
      "npm publish",
      "bun run deploy",
      "wrangler deploy",
    ]) {
      expect(simulatedBashPermission(command, rules)).toBe("ask");
    }
    for (const command of ["git status", "bun test", "curl -i http://localhost:3000/health"]) {
      expect(simulatedBashPermission(command, rules)).toBe("allow");
    }
    // Self-modification surfaces stay on ask (the deny floor can't protect
    // itself from the Edit tool).
    const editBlock = template.match(/"edit":\s*\{[\s\S]*?\}/)?.[0] ?? "";
    expect(editBlock).toMatch(/plugins\/\*\*":\s*"ask"/);
    expect(editBlock).toMatch(/opencode\.jsonc":\s*"ask"/);
  });

  test("template is model-agnostic: no hardcoded model, has the injection marker", async () => {
    const template = await Bun.file(join(opencodeRoot, "config/opencode.jsonc.template")).text();
    expect(template.match(/"model":\s*"[^"]*"/g) || []).toHaveLength(0);
    expect(template).toContain("PAI_MODEL_INJECTION_POINT");
  });

  test("agents omit `model` so they inherit the primary (model-agnostic)", () => {
    const agentsDir = join(opencodeRoot, "agents");
    for (const f of readdirSync(agentsDir).filter((n) => n.endsWith(".md"))) {
      const fm = readFileSync(join(agentsDir, f), "utf-8").split(/\n/).slice(0, 15).join("\n");
      expect(fm).not.toMatch(/^model:/m);
    }
  });

  test("per-machine primary-model file injects the model into the rendered config", async () => {
    const home = mkdtempSync(join(tmpdir(), "pai-install-model-"));
    await seedCleanInstall(home);
    // No override file: template has no model, installed has none → --check matches.
    expect(runCheck(home).exitCode).toBe(0);
    // With the file, render injects a model line the installed config lacks → drift,
    // proving the injection applied.
    const cfgDir = join(home, ".config/opencode/PAI/USER/Config");
    mkdirSync(cfgDir, { recursive: true });
    writeFileSync(join(cfgDir, "primary-model"), "openai/gpt-5.5\n");
    const result = runCheck(home);
    expect(result.exitCode).toBe(1);
    expect(outputOf(result)).toContain("opencode.jsonc differs");
    // Two full-validator spawns; the default 5s bun timeout is too tight.
  }, 30000);
});

// The T1 sandbox is only a real backstop if installation guarantees it. These pin
// the wiring so it cannot silently regress out of the installer (which would return
// the harness to a fail-open-with-no-signal state on every fresh machine).
describe("Installer wires the T1 sandbox", () => {
  const install = readFileSync(installScript, "utf-8");

  test("bootstraps bubblewrap across the common package managers", () => {
    expect(install).toContain("install_bwrap");
    // Called from prerequisites so every install attempts it.
    expect(install).toMatch(/check_prerequisites[\s\S]*install_bwrap/);
    for (const pm of ["apt-get", "pacman", "dnf", "zypper", "apk"]) {
      expect(install).toContain(pm);
    }
    expect(install).toContain("bubblewrap");
  });

  test("verifies confinement after install and reports a sandbox status", () => {
    expect(install).toContain("verify_sandbox");
    // verify_sandbox runs in main() after the wrapper script is installed.
    expect(install).toMatch(/install_pai_core[\s\S]*verify_sandbox/);
    // The outcome surfaces in the install report and in --check drift mode.
    expect(install).toContain("SANDBOX_STATUS");
    expect(install).toContain("T1 sandbox:");
    expect(install).toMatch(/bwrap absent.*commands run unconfined/);
  });
});

describe("Installer wires the O5 health-check timer", () => {
  const install = readFileSync(installScript, "utf-8");

  test("health-check consumer script exists, is executable, and runs all probes", () => {
    const scriptPath = join(opencodeRoot, "bin", "pai-health-check.sh");
    const script = readFileSync(scriptPath, "utf-8");
    expect(script).toContain("monitor-classifier-health.js");
    expect(script).toContain("monitor-security-events.ts");
    expect(script).toContain("--check");
    expect(script).toContain("notify-send");
    expect(script).toContain("health-check.jsonl");
    // Executable bit — the systemd unit ExecStarts it directly.
    const mode = statSync(scriptPath).mode;
    expect(mode & 0o111).toBeGreaterThan(0);
  });

  test("install main() installs and enables the timer", () => {
    expect(install).toContain("install_health_timer");
    expect(install).toMatch(/install_renderer_service\s*\n\s*install_health_timer/);
    expect(install).toContain("pai-health.timer");
    expect(install).toContain("pai-health.service");
    expect(install).toContain("OnCalendar=daily");
    expect(install).toContain("Persistent=true");
    expect(install).toMatch(/systemctl --user enable --now pai-health\.timer/);
  });

  test("--check fails when the timer is not scheduled (O5 consumer probe)", () => {
    // The probe lives in check_runtime_contracts so drift mode notices a
    // disabled/removed timer — "runnable but unscheduled" must be red.
    // Enablement is checked as the timers.target.wants/ symlink (what
    // `systemctl --user enable` creates), so it respects $HOME overrides.
    expect(install).toMatch(/check_runtime_contracts[\s\S]*Health timer not scheduled/);
    expect(install).toMatch(/timers\.target\.wants\/pai-health\.timer/);
  });
});
