import { describe, expect, test } from "bun:test";
import { chmodSync, mkdirSync, mkdtempSync, readdirSync, statSync, writeFileSync } from "fs";
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
  write(join(paiDir, "USER/SECURITY/PATTERNS.yaml"), "version: \"test\"\n");
}

function runCheck(home: string) {
  return Bun.spawnSync({
    cmd: ["bash", installScript, "--check"],
    env: { ...process.env, HOME: home },
    stdout: "pipe",
    stderr: "pipe",
  });
}

function outputOf(result: ReturnType<typeof runCheck>) {
  return `${result.stdout.toString()}\n${result.stderr.toString()}`;
}

describe("Installer hygiene", () => {
  test("install manifest tracks repo agents, commands, and skills", () => {
    expect(sorted(manifest.agents)).toEqual(repoFiles(join(opencodeRoot, "agents"), ".md"));
    expect(sorted(manifest.commands)).toEqual(repoFiles(join(opencodeRoot, "commands"), ".md"));
    expect(sorted(manifest.skills)).toEqual(repoDirs(join(repoRoot, "skills")));
  });

  test("install.sh --check passes when generated artifacts match the manifest", async () => {
    const home = mkdtempSync(join(tmpdir(), "pai-install-clean-"));
    await seedCleanInstall(home);

    const result = runCheck(home);
    expect(outputOf(result)).toContain("Installed runtime matches manifest");
    expect(result.exitCode).toBe(0);
  });

  test("install.sh --check fails when stale skills are installed", async () => {
    const home = mkdtempSync(join(tmpdir(), "pai-install-drift-"));
    await seedCleanInstall(home);
    mkdirSync(join(home, ".config/opencode/skills/interceptor-browser"), { recursive: true });

    const result = runCheck(home);
    expect(outputOf(result)).toContain("interceptor-browser");
    expect(result.exitCode).toBe(1);
  });
});
