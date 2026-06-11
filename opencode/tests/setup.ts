// Test preload: isolate the plugin's PAI_DIR so running `bun test` never
// creates or touches ~/.config/opencode/PAI on the developer's machine.
// Loaded via opencode/bunfig.toml [test].preload — runs before any test
// module (and therefore before pai-hooks.lib.js computes PAI_DIR).
import { mkdtempSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

if (!process.env.PAI_DIR) {
  process.env.PAI_DIR = mkdtempSync(join(tmpdir(), "pai-test-"));
}
