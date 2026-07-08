import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync, statSync } from "fs";
import { join, relative } from "path";
import { fileURLToPath } from "url";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));

function read(path: string) {
  return readFileSync(join(repoRoot, path), "utf-8");
}

function filesUnder(dir: string): string[] {
  const root = join(repoRoot, dir);
  const out: string[] = [];
  const walk = (path: string) => {
    for (const entry of readdirSync(path)) {
      const full = join(path, entry);
      const rel = relative(repoRoot, full);
      if (statSync(full).isDirectory()) {
        walk(full);
      } else if (/\.(md|ts)$/.test(entry)) {
        out.push(rel);
      }
    }
  };
  walk(root);
  return out;
}

describe("Pulse OpenCode scope", () => {
  test("PULSE.toml describes only the optional broker runtime", () => {
    const config = read("PAI/PULSE/PULSE.toml");

    expect(config).toContain('runtime = "opencode"');
    expect(config).toContain('status = "optional-broker"');
    expect(config).toContain("enabled_by_default = false");
    expect(config).not.toContain("[[job]]");
    expect(config).not.toContain("PAI/TOOLS/");
    expect(config).not.toContain("type = \"claude\"");
    expect(config).not.toContain("Observability/out");
  });

  test("Pulse docs mark original desktop daemon as legacy/out of scope", () => {
    const readme = read("PAI/PULSE/README.md");
    const systemDoc = read("PAI/DOCUMENTATION/Pulse/PulseSystem.md");
    const notificationDoc = read("PAI/DOCUMENTATION/Notifications/NotificationSystem.md");
    const skillDoc = read("PAI/DOCUMENTATION/Skills/SkillSystem.md");
    const isaDoc = read("PAI/DOCUMENTATION/Isa/IsaSystem.md");
    const streamDoc = read("opencode/docs/NOTIFICATIONS_STREAM.md");

    expect(readme).toContain("optional notification broker");
    expect(readme).toContain("not require `localhost:31337`");
    expect(systemDoc).toContain("legacy/reference material");
    expect(systemDoc).toContain("A running `localhost:31337` broker is optional");
    expect(notificationDoc).toContain("`pai_notify` is the only required final voice path");
    expect(notificationDoc).toContain("Never treat a missing broker as failure");
    expect(notificationDoc).not.toContain("VoiceCompletion.hook.ts");
    expect(skillDoc).toContain("Optional Legacy Pulse Progress Notification");
    expect(skillDoc).not.toContain("When executing a workflow, do BOTH");
    expect(isaDoc).toContain("optional Pulse broker/renderer");
    expect(streamDoc).toContain("optional broker");
    expect(streamDoc).toContain("If the broker is not running");
  });

  test("active skills do not require a live Pulse broker", () => {
    const offenders: string[] = [];
    const blockingCurl: string[] = [];

    for (const file of filesUnder("skills")) {
      const content = read(file);
      if (/MANDATORY: Voice Notification|Voice Notification \(REQUIRED|This is not optional\. Execute this curl/.test(content)) {
        offenders.push(file);
      }
      if (content.includes("http://localhost:31337/notify")) {
        for (const [index, line] of content.split("\n").entries()) {
          if (line.includes("curl") && line.includes("http://localhost:31337/notify") && !line.includes("--max-time 2")) {
            blockingCurl.push(`${file}:${index + 1}`);
          }
        }
      }
    }

    expect(offenders).toEqual([]);
    expect(blockingCurl).toEqual([]);
  });
});
