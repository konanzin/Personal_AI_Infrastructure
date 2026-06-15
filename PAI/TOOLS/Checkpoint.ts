#!/usr/bin/env bun
/**
 * Checkpoint.ts - OpenCode-native ISC checkpoint inspection CLI.
 *
 * Commands:
 *   list <slug>                 List checkpointed ISCs for a work slug.
 *   show <slug> <isc-id>        Show matching checkpoint commits.
 *   rollback <slug> <isc-id>    Preview git reset commands only.
 *   record <slug> <isc-id> ...  Explicitly commit dirty allowlisted repos.
 *
 * Rollback is preview-only by design. This CLI never executes destructive git
 * operations; it only prints commands for the principal to run manually.
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { dirname, join } from "path";
import { homedir } from "os";

type RepoResult = {
  repo: string;
  sha: string | null;
  status: "committed" | "clean" | "missing" | "not_git" | "failed";
  error?: string;
};

type CheckpointEntry = {
  id: string;
  description: string;
  slug: string;
  timestamp: string;
  repos: RepoResult[];
};

type CheckpointState = {
  committed_iscs: string[];
  last_commit_sha: Record<string, string>;
  entries: CheckpointEntry[];
};

const PAI_DIR = process.env.PAI_DIR || join(homedir(), ".config", "opencode", "PAI");
const WORK_DIR = join(PAI_DIR, "MEMORY", "WORK");
const STATE_DIR = join(PAI_DIR, "MEMORY", "STATE", "checkpoints");
const ALLOWLIST_PATH = join(PAI_DIR, "checkpoint-repos.txt");

function expandPath(value: string): string {
  let out = value.trim();
  if (out === "~") out = homedir();
  if (out.startsWith("~/")) out = join(homedir(), out.slice(2));
  out = out.replace(/^\$HOME(?=\/|$)/, homedir());
  return out;
}

function parseArgs(argv: string[]) {
  const opts: Record<string, string[] | boolean> = {};
  const positionals: string[] = [];
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith("--")) {
      positionals.push(arg);
      continue;
    }
    const key = arg.slice(2);
    if (key === "json" || key === "help" || key === "dry-run") {
      opts[key] = true;
      continue;
    }
    const value = argv[++i];
    if (value === undefined) {
      opts[key] = true;
      continue;
    }
    const current = opts[key];
    opts[key] = Array.isArray(current) ? [...current, value] : [value];
  }
  return { opts, positionals };
}

function optValues(opts: Record<string, string[] | boolean>, key: string): string[] {
  const value = opts[key];
  return Array.isArray(value) ? value : [];
}

function optString(opts: Record<string, string[] | boolean>, key: string): string | null {
  return optValues(opts, key)[0] || null;
}

function statePath(slug: string): string {
  const workPath = join(WORK_DIR, slug, ".checkpoint-state.json");
  return existsSync(workPath) ? workPath : join(STATE_DIR, `${slug}.json`);
}

function emptyState(): CheckpointState {
  return { committed_iscs: [], last_commit_sha: {}, entries: [] };
}

function loadState(slug: string): CheckpointState {
  const path = statePath(slug);
  if (!existsSync(path)) return emptyState();
  try {
    const parsed = JSON.parse(readFileSync(path, "utf-8"));
    return {
      committed_iscs: Array.isArray(parsed.committed_iscs) ? parsed.committed_iscs : [],
      last_commit_sha: parsed.last_commit_sha && typeof parsed.last_commit_sha === "object" ? parsed.last_commit_sha : {},
      entries: Array.isArray(parsed.entries) ? parsed.entries : [],
    };
  } catch {
    return emptyState();
  }
}

function saveState(slug: string, state: CheckpointState) {
  const path = existsSync(join(WORK_DIR, slug)) ? join(WORK_DIR, slug, ".checkpoint-state.json") : join(STATE_DIR, `${slug}.json`);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(state, null, 2)}\n`, "utf-8");
}

function loadAllowlist(extraRepos: string[] = []): string[] {
  const repos: string[] = [];
  if (existsSync(ALLOWLIST_PATH)) {
    for (const line of readFileSync(ALLOWLIST_PATH, "utf-8").split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      repos.push(expandPath(trimmed));
    }
  }
  repos.push(...extraRepos.map(expandPath));
  return [...new Set(repos)];
}

function git(repo: string, args: string[]): string {
  const proc = Bun.spawnSync({
    cmd: ["git", "-C", repo, ...args],
    stdout: "pipe",
    stderr: "pipe",
  });
  if (proc.exitCode !== 0) {
    throw new Error(proc.stderr.toString().trim() || `git ${args.join(" ")} failed`);
  }
  return proc.stdout.toString();
}

function isGitRepo(repo: string): boolean {
  try {
    git(repo, ["rev-parse", "--git-dir"]);
    return true;
  } catch {
    return false;
  }
}

function hasChanges(repo: string): boolean {
  try {
    return git(repo, ["status", "--porcelain"]).trim().length > 0;
  } catch {
    return false;
  }
}

function sanitizeMessage(value: string): string {
  return value.replace(/\s+/g, " ").replace(/[`$]/g, "").trim().slice(0, 200);
}

function findCommit(repo: string, slug: string, iscId: string) {
  try {
    const grep = `${iscId} (${slug}):`;
    const out = git(repo, ["log", "--all", "-F", "--grep", grep, "--pretty=format:%H\t%ci\t%s", "-n", "1"]);
    const line = out.split(/\r?\n/)[0]?.trim();
    if (!line) return null;
    const [sha, date, ...subject] = line.split("\t");
    return { sha, date, subject: subject.join("\t") };
  } catch {
    return null;
  }
}

function record(slug: string, iscId: string, description: string, repos: string[]): CheckpointEntry {
  const state = loadState(slug);
  if (state.committed_iscs.includes(iscId)) {
    const existing = state.entries.find((entry) => entry.id === iscId);
    return existing || { id: iscId, slug, description, timestamp: new Date().toISOString(), repos: [] };
  }

  const results: RepoResult[] = [];
  for (const repo of repos) {
    if (!existsSync(repo)) {
      results.push({ repo, sha: null, status: "missing" });
      continue;
    }
    if (!isGitRepo(repo)) {
      results.push({ repo, sha: null, status: "not_git" });
      continue;
    }
    if (!hasChanges(repo)) {
      results.push({ repo, sha: null, status: "clean" });
      continue;
    }
    try {
      git(repo, ["add", "-A"]);
      git(repo, ["commit", "-m", `${iscId} (${slug}): ${sanitizeMessage(description)}`, "--quiet", "--no-verify", "--no-gpg-sign"]);
      const sha = git(repo, ["rev-parse", "HEAD"]).trim();
      state.last_commit_sha[repo] = sha;
      results.push({ repo, sha, status: "committed" });
    } catch (error) {
      results.push({
        repo,
        sha: null,
        status: "failed",
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  const entry = { id: iscId, slug, description, timestamp: new Date().toISOString(), repos: results };
  state.committed_iscs.push(iscId);
  state.entries.push(entry);
  saveState(slug, state);
  return entry;
}

function print(data: unknown, json: boolean) {
  if (json) {
    console.log(JSON.stringify(data, null, 2));
    return;
  }
  if (typeof data === "string") console.log(data);
  else console.log(JSON.stringify(data, null, 2));
}

function usage() {
  console.log(`Usage:
  bun PAI/TOOLS/Checkpoint.ts list <slug> [--json]
  bun PAI/TOOLS/Checkpoint.ts show <slug> <isc-id> [--json]
  bun PAI/TOOLS/Checkpoint.ts rollback <slug> <isc-id> [--json]
  bun PAI/TOOLS/Checkpoint.ts record <slug> <isc-id> <description...> [--repo PATH] [--json]

Allowlist: ${ALLOWLIST_PATH}
Rollback is preview-only; no destructive git command is executed.`);
}

const { opts, positionals } = parseArgs(process.argv.slice(2));
const json = Boolean(opts.json);
const command = positionals[0];

if (!command || opts.help) {
  usage();
  process.exit(command ? 0 : 1);
}

if (command === "list") {
  const slug = positionals[1];
  if (!slug) {
    usage();
    process.exit(1);
  }
  const state = loadState(slug);
  print({ status: "ok", slug, checkpoints: state.entries, committed_iscs: state.committed_iscs, last_commit_sha: state.last_commit_sha }, json);
  process.exit(0);
}

if (command === "show" || command === "rollback") {
  const slug = positionals[1];
  const iscId = positionals[2];
  if (!slug || !iscId) {
    usage();
    process.exit(1);
  }
  const state = loadState(slug);
  const stateEntry = state.entries.find((entry) => entry.id === iscId);
  const repos = stateEntry?.repos?.filter((repo) => repo.sha) || [];
  const searched = repos.length > 0
    ? repos.map((repo) => ({ repo: repo.repo, sha: repo.sha, subject: `${iscId} (${slug}): ${stateEntry?.description || ""}` }))
    : loadAllowlist().map((repo) => {
        const hit = findCommit(repo, slug, iscId);
        return hit ? { repo, ...hit } : null;
      }).filter(Boolean);

  if (command === "show") {
    print({ status: searched.length > 0 ? "ok" : "not_found", slug, isc_id: iscId, commits: searched }, json);
    process.exit(0);
  }

  const commands = searched.map((hit: any) => ({
    repo: hit.repo,
    sha: hit.sha,
    command: `git -C ${hit.repo} reset --hard ${hit.sha}`,
  }));
  print({ status: commands.length > 0 ? "preview" : "not_found", slug, isc_id: iscId, destructive_executed: false, commands }, json);
  if (!json) {
    for (const item of commands) {
      console.log(`REPO: ${item.repo}`);
      console.log(`TARGET: ${item.sha}`);
      console.log(`To roll back manually: ${item.command}`);
    }
    if (commands.length > 0) console.log("(preview only; no destructive operation performed)");
  }
  process.exit(0);
}

if (command === "record") {
  const slug = positionals[1];
  const iscId = positionals[2];
  const description = positionals.slice(3).join(" ").trim() || optString(opts, "description") || "checkpoint";
  if (!slug || !iscId) {
    usage();
    process.exit(1);
  }
  const repos = loadAllowlist(optValues(opts, "repo"));
  if (repos.length === 0) {
    print({ status: "skipped", reason: "no_checkpoint_repos_configured", allowlist: ALLOWLIST_PATH }, json);
    process.exit(0);
  }
  const entry = record(slug, iscId, description, repos);
  print({ status: "ok", checkpoint: entry }, json);
  process.exit(0);
}

usage();
process.exit(1);
