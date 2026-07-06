/**
 * PAI Hooks Plugin - Shared Utilities (pai-hooks.lib.js)
 * 
 * Common utilities extracted from PAI v5.0.0 hooks for use by pai-hooks.js.
 * Mirrors the functionality of hooks-reference/lib/* and security/* modules.
 * 
 * @version 1.0.0
 */

import { existsSync, readFileSync, writeFileSync, appendFileSync, mkdirSync, readdirSync, statSync, unlinkSync } from 'fs';
import { execFileSync } from 'child_process';
import { basename, join, dirname, resolve } from 'path';
import { homedir } from 'os';

const PAI_DEBUG_UI = process.env.PAI_DEBUG_UI === 'true';
const console = PAI_DEBUG_UI
  ? globalThis.console
  : {
      log() {},
      warn() {},
      error() {},
    };

// ═══════════════════════════════════════════════════════════════
// PATHS & DIRECTORIES
// ═══════════════════════════════════════════════════════════════

export const PAI_DIR = process.env.PAI_DIR || join(homedir(), '.config', 'opencode', 'PAI');
export const MEMORY_DIR = join(PAI_DIR, 'MEMORY');
export const STATE_DIR = join(MEMORY_DIR, 'STATE');
export const WORK_DIR = join(MEMORY_DIR, 'WORK');
export const LEARNING_DIR = join(MEMORY_DIR, 'LEARNING');
export const OBSERVABILITY_DIR = join(MEMORY_DIR, 'OBSERVABILITY');
export const SECURITY_DIR = join(PAI_DIR, 'USER', 'SECURITY');

// ═══════════════════════════════════════════════════════════════
// FILE OPERATIONS
// ═══════════════════════════════════════════════════════════════

export function ensureDir(dir) {
  try {
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
  } catch (e) {
    console.error(`[PAI] Failed to create directory ${dir}:`, e.message);
  }
}

export function safeReadJson(path, defaultValue = null) {
  try {
    if (existsSync(path)) {
      const content = readFileSync(path, 'utf-8');
      return JSON.parse(content);
    }
  } catch (e) {
    // Ignore parse errors — fail open
  }
  return defaultValue;
}

export function safeWriteJson(path, data) {
  try {
    ensureDir(dirname(path));
    const tmp = path + '.tmp';
    writeFileSync(tmp, JSON.stringify(data, null, 2), 'utf-8');
    // Atomic rename
    const { renameSync } = require('fs');
    renameSync(tmp, path);
    return true;
  } catch (e) {
    console.error(`[PAI] Failed to write ${path}:`, e.message);
    return false;
  }
}

export function appendJsonL(path, data) {
  try {
    ensureDir(dirname(path));
    // Strip lone UTF-16 surrogates that break jq parsing
    const line = JSON.stringify(data).replace(/\\ud[89a-f][0-9a-f]{2}(?!\\ud[c-f][0-9a-f]{2})/gi, '');
    appendFileSync(path, line + '\n', 'utf-8');
    return true;
  } catch (e) {
    console.error(`[PAI] Failed to append to ${path}:`, e.message);
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════
// TIME UTILITIES
// ═══════════════════════════════════════════════════════════════

export function getISOTimestamp() {
  return new Date().toISOString();
}

export function hashString(str, maxLen = 16) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    hash ^= str.charCodeAt(i);
    hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
  }
  const hex = (hash >>> 0).toString(16).padStart(8, '0');
  return hex.slice(0, maxLen);
}

export function getPSTComponents() {
  const now = new Date();
  const pst = new Date(now.toLocaleString('en-US', { timeZone: 'America/Los_Angeles' }));
  return {
    year: pst.getFullYear(),
    month: String(pst.getMonth() + 1).padStart(2, '0'),
    day: String(pst.getDate()).padStart(2, '0'),
    hours: String(pst.getHours()).padStart(2, '0'),
    minutes: String(pst.getMinutes()).padStart(2, '0'),
    seconds: String(pst.getSeconds()).padStart(2, '0'),
  };
}

export function getPSTDate() {
  const c = getPSTComponents();
  return `${c.year}-${c.month}-${c.day}`;
}

// ═══════════════════════════════════════════════════════════════
// SESSION UTILITIES
// ═══════════════════════════════════════════════════════════════

export function getSessionId(input) {
  return input.sessionID || input.sessionId || input.session_id || `session-${Date.now()}`;
}

export function findStateFile(sessionId) {
  if (sessionId) {
    const scoped = join(STATE_DIR, `current-work-${sessionId}.json`);
    if (existsSync(scoped)) return scoped;
  }
  const legacy = join(STATE_DIR, 'current-work.json');
  if (existsSync(legacy)) return legacy;
  return null;
}

// ═══════════════════════════════════════════════════════════════
// STRING UTILITIES
// ═══════════════════════════════════════════════════════════════

export function truncate(s, max) {
  if (!s) return '';
  return s.length > max ? s.slice(0, max) + '...[truncated]' : s;
}

// ═══════════════════════════════════════════════════════════════
// SECURITY UTILITIES
// ═══════════════════════════════════════════════════════════════

export function logSecurityEvent(event) {
  const securityLogPath = join(STATE_DIR, 'security-events.jsonl');
  appendJsonL(securityLogPath, {
    timestamp: getISOTimestamp(),
    ...event,
  });
}

// ═══════════════════════════════════════════════════════════════
// NOTIFICATIONS STREAM (contract v1)
// ═══════════════════════════════════════════════════════════════
// Producer side of the Pulse-mobile plan (PULSE_MOBILE_PLAN.md).
// Append-only and template-deterministic: `speak` is always built from
// event fields, never an LLM. No rate limiting or deduplication here —
// routing and coalescing belong to the broker/renderers, the producer
// stays dumb. Schema is documented in opencode/docs/NOTIFICATIONS_STREAM.md.

export const NOTIFICATIONS_PATH = join(OBSERVABILITY_DIR, 'notifications.jsonl');

const NOTIFICATION_LEVELS = {
  session_started: 'milestone',
  phase_transition: 'milestone',
  agent_completed: 'milestone',
  guard_denied: 'attention',
  security_blocked: 'attention',
  tool_failing: 'attention',
  permission_needed: 'attention',
  session_completed: 'digest',
};

const SPEAK_BUILDERS = {
  session_started: (d) => `Resuming work on ${d.title || d.slug || 'a tracked session'}`,
  phase_transition: (d) => `${d.title || d.slug || 'Current work'} entered the ${d.phase || 'next'} phase`,
  agent_completed: (d) => d.completed_line || 'An agent finished its task',
  guard_denied: (d) => `Blocked a ${d.guard || 'guarded'} call${d.target ? ` to ${d.target}` : ''}: ${d.reason || 'guard rule'}`,
  security_blocked: (d) => `Security blocked ${d.tool || 'an action'}: ${d.reason || 'dangerous pattern'}`,
  tool_failing: (d) => `The ${d.tool || 'current'} tool failed ${d.count || 'several'} times in a row`,
  permission_needed: (d) => `Waiting for your permission${d.tool ? ` to run ${d.tool}` : ''}`,
  session_completed: (d) => {
    const what = d.title || d.slug || 'The session';
    const dur = d.duration_human ? ` after ${d.duration_human}` : '';
    return `${what} completed${dur}`;
  },
};

export function normalizeNotificationLanguage(language) {
  if (typeof language !== 'string') return null;
  const raw = language.trim().replace(/_/g, '-');
  if (!raw) return null;
  const parts = raw.split('-');
  const code = parts[0].toLowerCase();
  if (!/^[a-z]{2,3}$/.test(code)) return null;
  // Region defaults only for the two locales with provisioned TTS voices; every
  // other well-formed BCP-47 tag is preserved, not dropped (drift register W2.4).
  // As the model gets more multilingual, es-ES / ja-JP / fr notifications flow
  // instead of being clamped to en/pt or nulled out of the stream.
  let region = parts[1];
  if (!region) {
    if (code === 'pt') region = 'BR';
    else if (code === 'en') region = 'US';
  }
  return region ? `${code}-${region.toUpperCase()}` : code;
}

export function buildSpeak(event, data = {}) {
  const builder = SPEAK_BUILDERS[event];
  const phrase = builder ? builder(data) : `PAI event: ${event}`;
  // Keep it speakable: single line, bounded length
  return truncate(String(phrase).replace(/\s+/g, ' ').trim(), 160);
}

export function emitNotification({
  event,
  sessionId,
  slug = null,
  title = null,
  data = {},
  speak = null,
  level = null,
  language = null,
}) {
  try {
    const normalizedLanguage =
      normalizeNotificationLanguage(language) ||
      normalizeNotificationLanguage(data.language) ||
      'en-US';
    const entry = {
      v: 1,
      timestamp: getISOTimestamp(),
      level: level || NOTIFICATION_LEVELS[event] || 'milestone',
      event,
      session_id: sessionId || 'unknown',
      slug,
      title: title || data.title || slug || null,
      speak: speak ? truncate(String(speak).replace(/\s+/g, ' ').trim(), 160) : buildSpeak(event, { ...data, slug, title }),
      language: normalizedLanguage,
      data,
    };
    appendJsonL(NOTIFICATIONS_PATH, entry);
    return entry;
  } catch {
    // Notification emission must never break the main flow
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════
// PATTERN INSPECTOR (SecurityPipeline component)
// ═══════════════════════════════════════════════════════════════

// ───────────────────────────────────────────────────────────────
// SECURITY POLICY (externalized — parity with original SecurityPipeline)
//
// The policy lives in PAI/USER/SECURITY/PATTERNS.yaml. Loading cascades:
//   1. user file  → parse + compile
//   2. file absent → bundled default below (canonical; mirrors the shipped
//      PATTERNS.yaml so the plugin never bricks and tests run without install)
//   3. file present but corrupt/invalid → FAIL-CLOSED (deny gated tools,
//      except read/write to the policy file itself so it can be repaired)
//
// Bash tiers: trusted (fast-path allow) → blocked (deny) → alert (log+allow).
// There is intentionally NO bash "confirm" tier (matches the original "ZERO
// confirm" philosophy); confirmation survives only for path tiers, which the
// runtime surfaces through OpenCode's native permission prompt.
// ───────────────────────────────────────────────────────────────

// Version is the STALENESS signal: install.sh --check compares the installed
// PATTERNS.yaml version against the template's. Bump it (here AND in
// Patterns.example.yaml) whenever patterns change, or existing installs will
// keep running the old policy with no warning — that drift already happened once.
const DEFAULT_SECURITY_POLICY_OBJ = {
  version: '3.3-opencode',
  bash: {
    trusted: [
      { pattern: '^playwright-cli\\b', reason: 'Playwright CLI (Browser skill)' },
      { pattern: '^bunx playwright\\b', reason: 'Playwright one-shot (Browser skill)' },
      { pattern: '^agent-browser\\b', reason: 'agent-browser CLI (Browser skill)' },
    ],
    blocked: [
      // Terminator class ["']?(\s|$|;|&&|\|) tolerates a closing quote (bash -c 'rm -rf /')
      // and a trailing glob (`/*` wipes the same tree `/` does but used to slip to alert).
      { pattern: 'rm\\s.*-\\w*r.*\\s+["\']?/\\*?["\']?(\\s|$|;|&&|\\|)', reason: 'Recursive deletion of system root (/ or /*)' },
      { pattern: 'rm\\s.*-\\w*r.*\\s+["\']?~(/\\*?)?["\']?(\\s|$|;|&&|\\|)', reason: 'Recursive deletion of home directory (~ or ~/*)' },
      { pattern: 'rm\\s.*-\\w*r.*\\s+["\']?\\$\\{?HOME\\}?(/\\*?)?["\']?(\\s|$|;|&&|\\|)', reason: 'Recursive deletion of home directory ($HOME or $HOME/*)' },
      // /home, /home/<user>, and their /* forms wipe an entire home tree; deeper
      // paths (/home/user/proj) fall through to the recursive-rm alert tier.
      { pattern: 'rm\\s.*-\\w*r.*\\s+["\']?/home(/[^/\\s*]+)?/?\\*?["\']?(\\s|$|;|&&|\\|)', reason: 'Recursive deletion of a home tree (/home...)' },
      { pattern: 'rm\\s.*-\\w*r.*\\s+["\']?/(etc|usr|var|boot|bin|sbin|lib(64)?|opt|srv|root)/?\\*?["\']?(\\s|$|;|&&|\\|)', reason: 'Recursive deletion of a top-level system directory' },
      // Non-rm catastrophic deletion: find -delete rooted at /, ~, $HOME or a whole
      // home dir (deeper roots like /home/user/tmp are legitimate cleanup).
      { pattern: '\\bfind\\s+["\']?(/home(/[^/\\s]+)?/?|/|~/?|\\$\\{?HOME\\}?/?)["\']?\\s[^|;&]*-delete\\b', reason: 'find -delete across root or an entire home directory' },
      { pattern: '(^|[;&|]\\s*|\\bsudo\\s+)shred\\b', reason: 'Irrecoverable file destruction (shred)' },
      // git clean needs BOTH -x (include ignored) and force to be destructive-and-run.
      // -n/--dry-run anywhere makes it a safe preview even alongside -xf, so it is
      // exempted up front; plain `git clean -fd` stays at the alert tier.
      { pattern: 'git\\s+clean\\b(?![^|;&]*\\s(-[a-z]*n[a-z]*|--dry-run)\\b)(?=[^|;&]*\\s-[a-z]*x)(?=[^|;&]*\\s(-[a-z]*f|--force))', reason: 'git clean -x removes ignored+untracked files irrecoverably' },
      { pattern: 'rm\\s.*-\\w*r.*\\s(~|\\$\\{?HOME\\}?)/\\.config/opencode(/|\\s|$|;|&&)', reason: 'Recursive deletion of ~/.config/opencode (entire PAI infrastructure)' },
      { pattern: 'rm\\s.*-\\w*r.*\\s+~/Projects/?(\\s|$|;|&&)', reason: 'Recursive deletion of ~/Projects' },
      { pattern: 'rm\\s.*(PATTERNS\\.yaml|pai-hooks(\\.lib)?\\.js)', reason: 'Deletion of PAI security policy/plugin disables protection' },
      { pattern: ':\\(\\)\\s*\\{\\s*:\\|:&\\s*\\};:', reason: 'Fork bomb' },
      { pattern: 'mkfs(\\.|\\b)', reason: 'Filesystem format/wipe (mkfs)' },
      { pattern: 'dd\\s+if=/dev/zero', reason: 'Disk overwrite with zeros (dd if=/dev/zero)' },
      { pattern: 'dd\\s+if=.*of=/dev/(sd|hd|nvme)', reason: 'dd to disk device' },
      { pattern: '>\\s*/dev/(sd|hd|nvme)', reason: 'Redirect to disk device' },
      { pattern: 'diskutil\\s+(eraseDisk|zeroDisk|apfs\\s+(deleteContainer|eraseVolume))', reason: 'Disk/volume destruction (diskutil)' },
      { pattern: 'chmod\\s+-R\\s+777\\s+/', reason: 'chmod 777 on root' },
      { pattern: 'chown\\s+-R\\s+.*\\s+/(\\s|$)', reason: 'chown -R on root' },
      { pattern: 'gh\\s+repo\\s+delete', reason: 'GitHub repository deletion' },
      { pattern: 'gh\\s+repo\\s+edit\\b.*--visibility\\s+public', reason: 'Repository visibility changed to public' },
      { pattern: '(curl|wget|fetch|aria2c|httpie)\\s+[^|]*\\|\\s*(sh|bash|zsh)\\b', reason: 'Piping HTTP downloader output to shell interpreter' },
      // Matches only real dotenv secret files: the token must START a path segment
      // with `.env` (so foo.env / app.env.example don't match) and any extension
      // chain must not end in a template suffix (.env.sample/.example/.template/.dist
      // are secretless by convention; .env.local/.env.production are secrets).
      { pattern: '\\b(cat|grep|rg|sed|awk|source|less|head|tail)\\b[^|;&]*[\\s"\'=/]\\.env(\\.(?!example\\b|sample\\b|template\\b|dist\\b)[\\w-]+)*(?=$|[\\s"\';|&)])', reason: 'Reading .env via shell (use Read tool or secrets utility)' },
      // ── Curated high-severity adds (harvested from opencode-policy, MIT; corpus
      // vendored at opencode/security/reference/). Selective on purpose: only
      // low-false-positive catastrophic signatures (crypto miners, reverse shells)
      // that the base pattern set lacked. ──
      { pattern: '\\bxmrig\\b', reason: 'Crypto miner (xmrig)' },
      { pattern: '\\b(cpuminer|minerd|ccminer|ethminer)\\b', reason: 'Crypto miner' },
      { pattern: 'stratum\\+(tcp|ssl)://', reason: 'Mining pool connection (stratum)' },
      { pattern: '\\bnc(at)?\\b[^|;&\\n]*\\s-[a-zA-Z]*e\\b', reason: 'netcat with -e/execute (reverse shell)' },
      { pattern: '\\bsocat\\b[^|;&\\n]*exec:', reason: 'socat exec reverse shell' },
      { pattern: '(>&?|<)\\s*/dev/(tcp|udp)/', reason: 'Bash /dev/tcp reverse shell' },
      { pattern: '\\bperl\\b.*[Ss]ocket.*connect', reason: 'Perl reverse shell' },
      { pattern: '\\bruby\\b.*TCPSocket', reason: 'Ruby reverse shell' },
      { pattern: '\\bphp\\b.*fsockopen', reason: 'PHP reverse shell' },
    ],
    alert: [
      { pattern: 'rm\\s+.*-\\w*[rR]', reason: 'Recursive rm (logged for audit)' },
      { pattern: 'git\\s+push\\b.*(--force|\\s-f\\b)', reason: 'Force push (audit)' },
      { pattern: 'git\\s+reset\\s+--hard', reason: 'Hard reset (audit)' },
      { pattern: 'git\\s+clean\\b[^|;&]*\\s(-[a-z]*f[a-z]*|--force)\\b', reason: 'Force clean of untracked files (audit)' },
      { pattern: '\\bDROP\\s+(DATABASE|TABLE)\\b', reason: 'Destructive SQL (audit)' },
      { pattern: '\\bTRUNCATE\\b', reason: 'Table truncate (audit)' },
      { pattern: 'terraform\\s+destroy', reason: 'Infrastructure destruction (audit)' },
      { pattern: '\\b(nc|ncat|socat)\\s', reason: 'Netcat/socat usage (exfil risk, audit)' },
      { pattern: '\\bsendmail\\b', reason: 'Direct sendmail usage (exfil risk, audit)' },
      { pattern: '(curl|wget)\\b.*(-X\\s*POST|--data|--post-data|--post-file|\\s-d\\s)', reason: 'Outbound HTTP POST (audit)' },
      { pattern: '^(printenv|env)\\s*$', reason: 'Full environment dump (audit)' },
      { pattern: '^set\\s*$', reason: 'Shell variable dump (audit)' },
      { pattern: 'eval\\s*[\\(`"]', reason: 'eval usage (audit)' },
      { pattern: 'python3?\\s+-c\\s', reason: 'Python inline execution (audit)' },
      { pattern: 'node\\s+-e\\s', reason: 'Node inline execution (audit)' },
      { pattern: 'ruby\\s+-e\\s', reason: 'Ruby inline execution (audit)' },
      { pattern: 'perl\\s+-e\\s', reason: 'Perl inline execution (audit)' },
      { pattern: 'npm\\s+.*--unsafe-perm', reason: 'npm --unsafe-perm (audit)' },
    ],
  },
  paths: {
    // block read + write + delete
    zeroAccess: [
      '~/.ssh/id_*', '~/.ssh/*.pem', '~/.aws/credentials', '~/.gnupg/**',
      '**/service-account*.json', '/etc/shadow', '/etc/gshadow', '/proc/kcore',
      '/etc/ssl/private/**',
      // Installed PAI user-data is the Principal's private substrate. Runtime
      // startup context may load selected summaries, but ad-hoc Read tool access
      // to credentials and high-sensitivity personal stores is a hard deny.
      '~/.config/opencode/auth.json',
      '~/.local/share/opencode/auth.json',
      '~/.claude/.credentials.json',
      '~/.config/claude/credentials.json',
      '~/.config/gh/hosts.yml',
      '~/.config/opencode/PAI/USER/Config/PAI_CONFIG.yaml',
      '~/.config/opencode/PAI/USER/Config/voice.env',
      '~/.config/opencode/PAI/USER/CONTACTS.md',
      '~/.config/opencode/PAI/USER/FINANCES/**',
      '~/.config/opencode/PAI/USER/HEALTH/**',
      '~/.config/opencode/PAI/USER/BUSINESS/**',
      '~/.config/opencode/PAI/USER/OUR_STORY.md',
      '**/.env', '**/.env.*',
      // Exemptions ('!'): dotenv TEMPLATES are secretless by convention and must
      // stay readable/writable — mirrors the bash-side .env guard's suffix carve-out.
      // They pierce only the floating '**/.env*' globs above; anchored dirs
      // (/etc/ssl/private/**, ~/.gnupg/**) still deny template-named files inside.
      '!**/.env.example', '!**/.env.sample', '!**/.env.template', '!**/.env.dist',
      '!**/.env.*.example', '!**/.env.*.sample', '!**/.env.*.template', '!**/.env.*.dist',
    ],
    // log + allow on read/write (empty: .env reads are denied above, matching original PAI)
    alertAccess: [],
    // require approval (native prompt) on read/write
    confirmAccess: ['~/.config/opencode/.mcp.json'],
    // block write + delete (reads allowed)
    readOnly: [
      '/etc/**',
      // authorized_keys is world-readable by design but writing it = SSH backdoor.
      '~/.ssh/authorized_keys*',
      '~/.config/opencode/PAI/USER/SECURITY/PATTERNS.yaml',
      '~/.config/opencode/plugins/pai-hooks.js',
      '~/.config/opencode/plugins/lib/**',
    ],
    // block delete only
    noDelete: ['~/.config/opencode/PAI/**', '~/.config/opencode/plugins/**', '**/.git/**'],
    // require approval on write
    confirmWrite: ['**/.npmrc', '**/.pypirc', '**/id_rsa', '**/id_ed25519', '**/.htpasswd'],
  },
};

// Minimal indentation-based parser for the constrained PATTERNS.yaml subset:
// top-level scalars, two-level maps, sequences of `- key: value` items and
// sequences of scalar strings. Anything outside this shape throws (→ fail-closed).
function parseSecurityYaml(text) {
  const lines = [];
  for (const rawLine of String(text).split(/\r?\n/)) {
    const line = rawLine.replace(/\t/g, '  ');
    const trimmed = line.trim();
    if (!trimmed || trimmed === '---' || trimmed.startsWith('#')) continue;
    const indent = line.match(/^ */)[0].length;
    lines.push({ indent, content: line.slice(indent).replace(/\s+$/, '') });
  }
  let pos = 0;

  const unquote = (v) => {
    const s = v.trim();
    if (s.length >= 2 && ((s[0] === "'" && s.endsWith("'")) || (s[0] === '"' && s.endsWith('"')))) {
      return s.slice(1, -1);
    }
    return s;
  };

  const parseNode = (indent) => {
    if (pos >= lines.length) return null;
    return lines[pos].content.startsWith('- ') ? parseSeq(indent) : parseMap(indent);
  };

  function parseMap(indent) {
    const map = {};
    while (pos < lines.length) {
      const { indent: ind, content } = lines[pos];
      if (ind < indent) break;
      if (ind > indent) { pos++; continue; }
      if (content.startsWith('- ')) break;
      const m = content.match(/^([\w.-]+):\s*(.*)$/);
      if (!m) { pos++; continue; }
      const key = m[1];
      const val = m[2];
      pos++;
      if (val === '') {
        const childIndent = pos < lines.length ? lines[pos].indent : indent + 2;
        map[key] = childIndent > indent ? parseNode(childIndent) : null;
      } else if (val === '[]') {
        map[key] = [];
      } else {
        map[key] = unquote(val);
      }
    }
    return map;
  }

  function parseSeq(indent) {
    const arr = [];
    while (pos < lines.length) {
      const { indent: ind, content } = lines[pos];
      if (ind < indent) break;
      if (ind > indent) { pos++; continue; }
      if (!content.startsWith('- ')) break;
      const rest = content.slice(2);
      if (/^[\w.-]+:(\s|$)/.test(rest)) {
        // inline map item: re-anchor as a map line at indent+2 and parse a map
        lines[pos] = { indent: ind + 2, content: rest };
        arr.push(parseMap(ind + 2));
      } else {
        arr.push(unquote(rest));
        pos++;
      }
    }
    return arr;
  }

  return parseNode(0);
}

function compileSecurityPolicy(obj, source) {
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) throw new Error('policy root is not a map');
  const bash = obj.bash || {};
  const paths = obj.paths || {};
  const rules = (list, severity) => {
    const out = [];
    for (const item of Array.isArray(list) ? list : []) {
      const pattern = item && item.pattern;
      if (typeof pattern !== 'string' || !pattern) throw new Error('bash rule missing pattern');
      out.push({ re: new RegExp(pattern, 'i'), reason: (typeof item.reason === 'string' && item.reason) ? item.reason : pattern, severity });
    }
    return out;
  };
  const globs = (list, label) => {
    const out = [];
    for (const g of Array.isArray(list) ? list : []) {
      if (typeof g !== 'string' || !g) throw new Error('path rule is not a string');
      // '!'-prefixed entries are exemptions: a path matching one is exempt from the
      // FLOATING ('**/'-prefixed) globs of the same tier. Directory-anchored globs
      // are absolute — exemptions cannot pierce them (see matchGlobs).
      if (g.startsWith('!')) {
        out.push({ glob: g.slice(1), reason: `${label} exemption: ${g}`, negate: true });
      } else {
        out.push({ glob: g, reason: `${label}: ${g}` });
      }
    }
    return out;
  };
  const policy = {
    status: 'ok',
    source,
    version: typeof obj.version === 'string' ? obj.version : null,
    reason: null,
    bash: {
      trusted: rules(bash.trusted, 'low'),
      blocked: rules(bash.blocked, 'critical'),
      alert: rules(bash.alert, 'low'),
    },
    paths: {
      zeroAccess: globs(paths.zeroAccess, 'Zero-access path'),
      alertAccess: globs(paths.alertAccess, 'Sensitive path'),
      confirmAccess: globs(paths.confirmAccess, 'Protected path'),
      readOnly: globs(paths.readOnly, 'Read-only path'),
      noDelete: globs(paths.noDelete, 'Protected from deletion'),
      confirmWrite: globs(paths.confirmWrite, 'Protected file'),
    },
  };
  // Corruption guards: a structurally-valid but empty policy must NOT silently disarm.
  // Exemption ('!') entries don't count — a tier of only exemptions protects nothing.
  if (policy.bash.blocked.length === 0) throw new Error('policy defines no blocked bash patterns');
  if (policy.paths.zeroAccess.filter((e) => !e.negate).length === 0) throw new Error('policy defines no zero-access paths');
  return policy;
}

const _emptyTiers = () => ({ zeroAccess: [], alertAccess: [], confirmAccess: [], readOnly: [], noDelete: [], confirmWrite: [] });
const _corruptPolicy = (source, reason) => ({ status: 'corrupt', source, reason, bash: { trusted: [], blocked: [], alert: [] }, paths: _emptyTiers() });

function securityPolicyPath() {
  return join(process.env.PAI_DIR || PAI_DIR, 'USER', 'SECURITY', 'PATTERNS.yaml');
}

export function isSecurityPolicyPath(filePath) {
  try {
    return resolve(expandTilde(String(filePath || ''))) === resolve(securityPolicyPath());
  } catch {
    return false;
  }
}

let _policyCache = null;

export function loadSecurityPolicy() {
  const path = securityPolicyPath();
  let exists = false;
  let mtimeMs = null;
  try {
    if (existsSync(path)) { exists = true; mtimeMs = statSync(path).mtimeMs; }
  } catch { exists = false; }

  const cacheKey = exists ? `file:${mtimeMs}` : 'default';
  if (_policyCache && _policyCache.path === path && _policyCache.key === cacheKey) return _policyCache.policy;

  let policy;
  if (exists) {
    try {
      policy = compileSecurityPolicy(parseSecurityYaml(readFileSync(path, 'utf-8')), path);
    } catch (e) {
      console.error(`[PAI] 🛡️ Security policy ${path} is corrupt — failing closed: ${e.message}`);
      policy = _corruptPolicy(path, e.message);
    }
  } else {
    try {
      policy = compileSecurityPolicy(DEFAULT_SECURITY_POLICY_OBJ, 'bundled-default');
      policy.status = 'default';
      console.warn(`[PAI] 🛡️ Security policy ${path} not found — using bundled default policy`);
    } catch (e) {
      policy = _corruptPolicy('bundled-default', e.message);
    }
  }

  _policyCache = { path, key: cacheKey, policy };
  return policy;
}

const HIGH_CONFIDENCE_SECRET_CONTENT = [
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  /\b(sk_live_[A-Za-z0-9]{16,}|sk-ant-[A-Za-z0-9_-]{16,}|sk-proj-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{16,}|whsec_[A-Za-z0-9]{16,})\b/,
  /\b(?:OPENAI|ANTHROPIC|MOONSHOT|ELEVENLABS|GITHUB|STRIPE|AWS|GOOGLE|SLACK)[A-Z0-9_]*(?:API_KEY|TOKEN|SECRET|ACCESS_KEY_ID|SECRET_ACCESS_KEY)\s*=\s*['"]?[A-Za-z0-9_./+=:-]{16,}/,
];

function highestPriorityResult(violations) {
  if (violations.length === 0) return { action: 'allow', violations: [] };

  const hasDeny = violations.some(v => v.action === 'deny');
  if (hasDeny) return { action: 'deny', violations: violations.filter(v => v.action === 'deny') };

  const hasConfirm = violations.some(v => v.action === 'require_approval');
  if (hasConfirm) return { action: 'require_approval', violations: violations.filter(v => v.action === 'require_approval') };

  return { action: 'alert', violations };
}

function stripEnvVarPrefix(command) {
  return command.replace(
    /^\s*(?:[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|[^\s]*)\s+)*/,
    ''
  );
}

function matchesBashPattern(command, pattern) {
  try {
    return new RegExp(pattern, 'i').test(command);
  } catch {
    return command.toLowerCase().includes(pattern.toLowerCase());
  }
}

function expandTilde(p) {
  return p.startsWith('~') ? p.replace('~', homedir()) : p;
}

function matchesPathPattern(filePath, pattern) {
  const expandedPattern = expandTilde(pattern);
  const normalizedPath = resolve(expandTilde(filePath));

  if (pattern.includes('*')) {
    let regexStr = expandedPattern
      .replace(/\*\*/g, '<<<DOUBLESTAR>>>')
      .replace(/\*/g, '<<<SINGLESTAR>>>')
      .replace(/[.+^${}()|[\]\\]/g, '\\$&')
      .replace(/<<<DOUBLESTAR>>>/g, '.*')
      .replace(/<<<SINGLESTAR>>>/g, '[^/]*');
    try {
      return new RegExp(`^${regexStr}$`).test(normalizedPath);
    } catch {
      return false;
    }
  }

  return normalizedPath === expandedPattern ||
    normalizedPath.startsWith(expandedPattern.endsWith('/') ? expandedPattern : expandedPattern + '/');
}

function matchGlobs(filePath, list) {
  // Exemptions ('!') can carve out of FLOATING basename patterns ('**/...') only.
  // Directory-anchored protections (/etc/ssl/private/**, ~/.gnupg/**) are absolute:
  // a template-named file inside a protected directory must NOT escape the tier
  // (an earlier tier-wide nullification made /etc/ssl/private/.env.example pass).
  const exempt = list.some((e) => e.negate && matchesPathPattern(filePath, e.glob));
  const out = [];
  for (const entry of list) {
    if (entry.negate) continue;
    if (!matchesPathPattern(filePath, entry.glob)) continue;
    if (exempt && entry.glob.startsWith('**/')) continue;
    out.push(entry);
  }
  return out;
}

export function inspectBashCommand(command) {
  const policy = loadSecurityPolicy();
  const normalized = stripEnvVarPrefix(String(command || ''));
  if (!normalized) return { action: 'allow', violations: [] };

  if (policy.status === 'corrupt') {
    return {
      action: 'deny',
      violations: [{ action: 'deny', reason: `Security policy unavailable — failing closed (${policy.reason || 'corrupt'})`, severity: 'critical', type: 'fail-closed' }],
    };
  }

  // Trusted fast-path — skip all further checks
  for (const t of policy.bash.trusted) {
    if (t.re.test(normalized)) return { action: 'allow', violations: [] };
  }

  const violations = [];
  for (const b of policy.bash.blocked) {
    if (b.re.test(normalized)) violations.push({ action: 'deny', reason: b.reason, severity: b.severity, type: 'blocked' });
  }
  for (const a of policy.bash.alert) {
    if (a.re.test(normalized)) violations.push({ action: 'alert', reason: a.reason, severity: a.severity, type: 'alert' });
  }

  // Priority: deny > alert (no bash "confirm" tier — matches original doctrine)
  if (violations.some(v => v.action === 'deny')) {
    return { action: 'deny', violations: violations.filter(v => v.action === 'deny') };
  }
  if (violations.length > 0) return { action: 'alert', violations };
  return { action: 'allow', violations: [] };
}

export function inspectWritePath(filePath, action = 'write') {
  const policy = loadSecurityPolicy();
  if (policy.status === 'corrupt') {
    if (isSecurityPolicyPath(filePath)) return { action: 'allow', violations: [] };
    return { action: 'deny', violations: [{ action: 'deny', reason: 'Security policy unavailable — failing closed', severity: 'critical', type: 'fail-closed' }] };
  }

  const violations = [];

  // Zero-access paths: blocked for read, write, and delete
  for (const v of matchGlobs(filePath, policy.paths.zeroAccess)) violations.push({ action: 'deny', reason: v.reason });

  if (action === 'write' || action === 'delete') {
    for (const v of matchGlobs(filePath, policy.paths.readOnly)) violations.push({ action: 'deny', reason: v.reason });
    for (const v of matchGlobs(filePath, policy.paths.confirmWrite)) violations.push({ action: 'require_approval', reason: v.reason });
    for (const v of matchGlobs(filePath, policy.paths.confirmAccess)) violations.push({ action: 'require_approval', reason: v.reason });
    for (const v of matchGlobs(filePath, policy.paths.alertAccess)) violations.push({ action: 'alert', reason: v.reason });
  }

  if (action === 'delete') {
    for (const v of matchGlobs(filePath, policy.paths.noDelete)) violations.push({ action: 'deny', reason: v.reason });
    violations.push({ action: 'require_approval', reason: 'Delete operation requires confirmation' });
  }

  return highestPriorityResult(violations);
}

export function inspectReadPath(filePath) {
  if (!filePath || typeof filePath !== 'string') return { action: 'allow', violations: [] };

  const policy = loadSecurityPolicy();
  if (policy.status === 'corrupt') {
    if (isSecurityPolicyPath(filePath)) return { action: 'allow', violations: [] };
    return { action: 'deny', violations: [{ action: 'deny', reason: 'Security policy unavailable — failing closed', severity: 'critical', type: 'fail-closed' }] };
  }

  const violations = [];
  for (const v of matchGlobs(filePath, policy.paths.zeroAccess)) violations.push({ action: 'deny', reason: v.reason, severity: 'critical' });
  for (const v of matchGlobs(filePath, policy.paths.confirmAccess)) violations.push({ action: 'require_approval', reason: v.reason, severity: 'medium' });
  for (const v of matchGlobs(filePath, policy.paths.alertAccess)) violations.push({ action: 'alert', reason: v.reason, severity: 'low' });

  return highestPriorityResult(violations);
}

function isAllowedSecretWriteTarget(filePath) {
  const normalized = resolve(expandTilde(filePath));
  const allowedRoots = [
    join(PAI_DIR, 'USER'),
    join(PAI_DIR, 'MEMORY', 'SECURITY'),
    join(PAI_DIR, 'MEMORY', 'OBSERVABILITY'),
    join(PAI_DIR, 'MEMORY', 'STATE'),
    join(PAI_DIR, '.env'),
  ];

  return allowedRoots.some((p) => matchesPathPattern(normalized, p));
}

export function inspectWriteContent(filePath, content = '') {
  if (!filePath || typeof content !== 'string' || !content) return { action: 'allow', violations: [] };
  if (isAllowedSecretWriteTarget(filePath)) return { action: 'allow', violations: [] };

  const violations = [];
  for (const pattern of HIGH_CONFIDENCE_SECRET_CONTENT) {
    if (pattern.test(content)) {
      violations.push({
        action: 'deny',
        reason: 'High-confidence secret material cannot be written outside PAI protected zones',
        severity: 'critical',
      });
      break;
    }
  }

  return highestPriorityResult(violations);
}

// ═══════════════════════════════════════════════════════════════
// RELATIONSHIP MEMORY CAPTURE (conservative port of RelationshipMemory.hook.ts)
//
// Original inferred World/Biographical/Opinion notes on every session end.
// We keep it deliberately low-noise: one Biographical (B) note per COMPLETED,
// non-trivial work session, appended to the daily relationship file. This is
// the feeder for RelationshipReflect.ts; sentiment inference is left out to
// avoid the original's noise.
// ═══════════════════════════════════════════════════════════════

export function captureRelationshipNote({ sessionId, title, category }) {
  try {
    if (!title || typeof title !== 'string' || title.trim().length < 5) return { captured: false, reason: 'no_title' };
    const { ymd, ym, hhmm } = toRelationshipStamp();
    const dir = join(MEMORY_DIR, 'RELATIONSHIP', ym);
    ensureDir(dir);
    const file = join(dir, `${ymd}.md`);
    const header = existsSync(file) ? '' : `# Relationship notes — ${ymd}\n\n`;
    const note = `## ${hhmm}\n- B @da: completed work — ${title.trim()}${category ? ` (${category})` : ''}\n\n`;
    appendFileSync(file, `${header}${note}`, 'utf-8');
    return { captured: true, file };
  } catch (e) {
    return { captured: false, reason: 'error', error: e.message };
  }
}

function toRelationshipStamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  const ymd = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const ym = `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
  const hhmm = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  return { ymd, ym, hhmm };
}

// ═══════════════════════════════════════════════════════════════
// REPEAT DETECTION (ported from RepeatDetection.hook.ts)
//
// Original ran on UserPromptSubmit (could block via exit 2). OpenCode's
// message.updated fires after the message is in flight, so this is advisory
// (alert only). Faithful algorithm: trigram+bigram Jaccard similarity vs the
// previous prompt in the SAME session, persisted per session.
// ═══════════════════════════════════════════════════════════════

function repeatTokens(text) {
  return String(text)
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter((w) => w.length >= 3);
}

function ngrams(tokens, n) {
  const out = new Set();
  for (let i = 0; i + n <= tokens.length; i++) out.add(tokens.slice(i, i + n).join(' '));
  return out;
}

function jaccard(a, b) {
  if (a.size === 0 && b.size === 0) return 0;
  let inter = 0;
  for (const x of a) if (b.has(x)) inter++;
  const union = a.size + b.size - inter;
  return union === 0 ? 0 : inter / union;
}

export function detectRepeatPrompt(sessionId, content, threshold = 0.6) {
  const result = { similarity: 0, isRepeat: false };
  try {
    const text = String(content || '');
    if (text.length < 20) return result;
    const statePath = join(STATE_DIR, `last-prompt-${sessionId}.json`);
    const prev = safeReadJson(statePath, null);
    const tokens = repeatTokens(text);
    const grams = new Set([...ngrams(tokens, 3), ...ngrams(tokens, 2)]);

    if (prev && Array.isArray(prev.grams) && prev.grams.length > 0) {
      result.similarity = jaccard(grams, new Set(prev.grams));
      result.isRepeat = result.similarity >= threshold;
    }
    safeWriteJson(statePath, { grams: [...grams], at: getISOTimestamp() });
  } catch {
    // best-effort
  }
  return result;
}

// ═══════════════════════════════════════════════════════════════
// TELOS SUMMARY SYNC (ported from TelosSummarySync.hook.ts)
//
// Original fired on PostToolUse when a USER/TELOS source file was written and
// spawned GenerateTelosSummary.ts. OpenCode equivalent: call from
// tool.execute.after for write/edit. Fail-soft; no-op unless the edited file is
// a TELOS source (not PRINCIPAL_TELOS.md / Backups) and the tool is installed.
// ═══════════════════════════════════════════════════════════════

export function maybeSyncTelosSummary(filePath) {
  try {
    if (!filePath || typeof filePath !== 'string') return { synced: false, reason: 'no_path' };
    const norm = resolve(expandTilde(filePath));
    const telosDir = resolve(join(PAI_DIR, 'USER', 'TELOS'));
    if (!norm.startsWith(`${telosDir}/`)) return { synced: false, reason: 'not_telos' };
    if (norm.endsWith('/PRINCIPAL_TELOS.md') || norm.includes('/Backups/')) {
      return { synced: false, reason: 'excluded' };
    }
    const tool = join(PAI_DIR, 'TOOLS', 'GenerateTelosSummary.ts');
    if (!existsSync(tool)) return { synced: false, reason: 'tool_absent' };
    execFileSync('bun', [tool], { timeout: 5000, stdio: 'ignore' });
    return { synced: true };
  } catch (e) {
    return { synced: false, reason: 'error', error: e.message };
  }
}

// ═══════════════════════════════════════════════════════════════
// INTEGRITY TELEMETRY (session-end — fuses DocIntegrity + IntegrityCheck)
//
// Faithful-but-conservative port: when PAI system files changed during the
// session, throttled by a cooldown, run the existing validators in fail-soft
// mode and log the outcome. Telemetry only — NEVER auto-edits docs (deliberate
// deviation from the original's surgical edits). No spawn happens unless PAI
// files actually changed AND the installed validators exist, so it is inert in
// tests and on plain sessions.
// ═══════════════════════════════════════════════════════════════

export function detectChangedPaiSystemFiles(sessionId, toolActivityPath) {
  try {
    if (!existsSync(toolActivityPath)) return [];
    const lines = readFileSync(toolActivityPath, 'utf-8').trim().split('\n').filter(Boolean);
    const changed = new Set();
    const paiRoot = resolve(PAI_DIR);
    for (const line of lines) {
      let entry;
      try { entry = JSON.parse(line); } catch { continue; }
      if (entry.session_id !== sessionId) continue;
      if (!['write', 'edit', 'multiedit'].includes(entry.tool_name)) continue;
      const fp = entry.ground_truth?.file_path;
      if (!fp) continue;
      const norm = resolve(expandTilde(fp));
      if (norm.startsWith(`${paiRoot}/`) || /pai-hooks|\/DOCUMENTATION\/|\/ALGORITHM\//.test(norm)) {
        changed.add(norm);
      }
    }
    return [...changed];
  } catch {
    return [];
  }
}

export function runIntegrityTelemetry({ sessionId, changedFiles, cooldownMs = 5 * 60 * 1000 }) {
  const result = { ran: false, skipped: null };
  try {
    if (!changedFiles || changedFiles.length === 0) { result.skipped = 'no_pai_changes'; return result; }

    const statePath = join(STATE_DIR, 'integrity-state.json');
    const state = safeReadJson(statePath, {});
    const now = Date.now();
    if (state.lastRunAt && (now - state.lastRunAt) < cooldownMs) { result.skipped = 'cooldown'; return result; }

    const binDir = join(PAI_DIR, 'bin');
    const validators = [
      ['doc', join(binDir, 'validate-doc-integrity.js'), ['--json'], 'bun'],
      ['promise', join(binDir, 'validate-promise-integrity.sh'), [], 'bash'],
      ['tools', join(binDir, 'validate-tools-manifest.js'), ['--json'], 'bun'],
    ];
    const outcomes = {};
    let anyFail = false;
    let anyRan = false;
    for (const [name, path, args, cmd] of validators) {
      if (!existsSync(path)) { outcomes[name] = 'absent'; continue; }
      anyRan = true;
      try {
        execFileSync(cmd, [path, ...args], { timeout: 20000, stdio: 'ignore' });
        outcomes[name] = 'pass';
      } catch {
        outcomes[name] = 'fail';
        anyFail = true;
      }
    }

    if (!anyRan) { result.skipped = 'no_validators'; return result; }

    result.ran = true;
    result.outcomes = outcomes;
    appendJsonL(join(OBSERVABILITY_DIR, 'integrity.jsonl'), {
      timestamp: getISOTimestamp(),
      event: 'integrity_check',
      session_id: sessionId,
      changed_files: changedFiles.length,
      outcomes,
      drift: anyFail,
    });
    state.lastRunAt = now;
    state.lastSession = sessionId;
    safeWriteJson(statePath, state);
    if (anyFail) {
      emitNotification({ event: 'integrity_drift', sessionId, data: { outcomes } });
    }
  } catch (e) {
    result.error = e.message;
  }
  return result;
}

// ═══════════════════════════════════════════════════════════════
// SMART APPROVER (deterministic permission assistance — ported from
// SmartApprover.hook.ts). Faithful port: trusted-path fast-path + a
// read-allow cache, NO LLM. The optional LLM RulesInspector
// (SECURITY_RULES.md + classifier) is intentionally NOT implemented here.
//
// OpenCode adaptation: the plugin cannot observe the user's eventual
// permission decision, so the cache only remembers low-risk read allows
// (for telemetry/consistency); writes are never auto-allowed unless they
// fall under a trusted prefix.
// ═══════════════════════════════════════════════════════════════

const TRUSTED_PREFIXES = [
  PAI_DIR,
  join(homedir(), 'Projects'),
  '/tmp',
];

export function isTrustedPath(target) {
  if (!target || typeof target !== 'string') return false;
  try {
    const normalized = resolve(expandTilde(target));
    return TRUSTED_PREFIXES.some((root) => {
      const r = resolve(root);
      return normalized === r || normalized.startsWith(`${r}/`);
    });
  } catch {
    return false;
  }
}

function permissionCachePath() {
  return join(STATE_DIR, 'permission-cache.json');
}

export function permissionCacheGet(tool, target) {
  const cache = safeReadJson(permissionCachePath(), {});
  return cache[`${tool}:${String(target).slice(0, 100)}`] || null;
}

export function permissionCacheAllowRead(tool, target) {
  try {
    const path = permissionCachePath();
    const cache = safeReadJson(path, {});
    const keys = Object.keys(cache);
    // Bound the cache to avoid unbounded growth (drop oldest insertion).
    if (keys.length > 500 && !cache[`${tool}:${String(target).slice(0, 100)}`]) {
      delete cache[keys[0]];
    }
    cache[`${tool}:${String(target).slice(0, 100)}`] = 'allow';
    safeWriteJson(path, cache);
  } catch {
    // Cache is best-effort; never break the permission flow.
  }
}

// ═══════════════════════════════════════════════════════════════
// EGRESS INSPECTOR (SecurityPipeline component)
// ═══════════════════════════════════════════════════════════════

const OUTBOUND_TOOLS = /\b(curl|wget|nc|ncat|fetch|http)\b/i;

const CREDENTIAL_PATTERNS = [
  [/sk_live_/i, 'Stripe live key'],
  [/sk_test_/i, 'Stripe test key'],
  [/sk-ant-/i, 'Anthropic API key'],
  [/sk-proj-/i, 'OpenAI project key'],
  [/PRIVATE KEY/i, 'Private key material'],
  [/whsec_/i, 'Webhook secret'],
];

const PIPE_TO_SHELL = /\|\s*(sh|bash|zsh)\b/i;

export function inspectEgress(command) {
  if (!command) return { action: 'allow', violations: [] };

  const policy = loadSecurityPolicy();
  if (policy.status === 'corrupt') {
    return { action: 'deny', violations: [{ action: 'deny', reason: 'Security policy unavailable — failing closed', severity: 'critical', type: 'fail-closed' }] };
  }

  const violations = [];

  // Credential exfiltration — only when combined with outbound tools
  if (OUTBOUND_TOOLS.test(command)) {
    for (const [pattern, label] of CREDENTIAL_PATTERNS) {
      if (pattern.test(command)) {
        violations.push({ action: 'deny', reason: `Credential exfiltration blocked: ${label} sent via outbound tool` });
      }
    }
  }

  // Pipe to shell interpreter
  if (PIPE_TO_SHELL.test(command)) {
    violations.push({ action: 'deny', reason: 'Piping output to shell interpreter' });
  }

  if (violations.length === 0) return { action: 'allow', violations: [] };
  return { action: 'deny', violations };
}

// ═══════════════════════════════════════════════════════════════
// SANDBOX (T1 — bwrap filesystem confinement for bash commands)
//
// The allow-by-default bash posture is bounded by the kernel, not only by
// the regex floor: tool.execute.before rewrites the command to run inside
// bin/pai-sandbox.sh (read-only root, rw only in $PWD/tmp/caches, secret
// dirs masked). Inline escape: prefix a command with the real token
// `pai-nosandbox`, which opencode.jsonc maps to "ask" — a human approval
// prompt. (An env-var prefix cannot gate it; see shouldSandboxCommand.)
// ═══════════════════════════════════════════════════════════════

export function shellQuoteSingle(s) {
  return `'${String(s).replace(/'/g, `'\\''`)}'`;
}

export function shouldSandboxCommand(command, env = {}) {
  if (!command || typeof command !== 'string') return false;
  // Session-level kill switch: set by a human at launch (out of band). An
  // in-session agent cannot alter the launcher env, so this is safe.
  if (env.PAI_SANDBOX === 'off') return false;
  const c = command.trimStart();
  // Human-approved inline escape hatch. Must be a real leading command token
  // (not an env-var prefix): OpenCode parses bash with tree-sitter and drops
  // variable_assignment nodes before permission matching, so an env prefix
  // like `PAI_SANDBOX=off ` is NEVER gated (it matches "*" -> allow and
  // escapes silently). `pai-nosandbox` is a command_name, so the pattern
  // "pai-nosandbox *": "ask" in opencode.jsonc fires a real approval prompt —
  // this branch is only reachable after a human approves. The command string
  // is left intact (not rewritten) so the matcher always sees the token.
  if (/^pai-nosandbox\s/.test(c)) return false;
  // sudo is its own "ask" boundary and cannot run inside a user namespace.
  if (/^sudo\s/.test(c)) return false;
  if (c.includes('pai-sandbox.sh')) return false; // already wrapped
  return true;
}

export function resolveSandboxScript(env = {}) {
  return env.PAI_SANDBOX_BIN || join(PAI_DIR, 'bin', 'pai-sandbox.sh');
}

export function sandboxAvailable(env = {}) {
  if (!existsSync(resolveSandboxScript(env))) return false;
  return ['/usr/bin/bwrap', '/usr/local/bin/bwrap', '/bin/bwrap']
    .some((p) => existsSync(p));
}

export function wrapBashInSandbox(command, env = {}) {
  return `${resolveSandboxScript(env)} ${shellQuoteSingle(command)}`;
}

// ═══════════════════════════════════════════════════════════════
// PROMPT GUARD (PromptInspector)
// ═══════════════════════════════════════════════════════════════

const INJECTION_PATTERNS = [
  { regex: /ignore\s+(all\s+)?previous\s+instructions/i, category: 'injection', severity: 'block', description: 'Ignore previous instructions' },
  { regex: /forget\s+(everything|what|all|your)/i, category: 'injection', severity: 'block', description: 'Forget context directive' },
  { regex: /your\s+new\s+(instructions|role|task)\s+(are|is)/i, category: 'injection', severity: 'block', description: 'New instructions directive' },
  { regex: /you\s+are\s+now\s+a\s/i, category: 'injection', severity: 'block', description: 'Role reassignment attempt' },
  { regex: /disregard\s+(all\s+)?(prior|previous|above)/i, category: 'injection', severity: 'block', description: 'Disregard prior instructions' },
  { regex: /system\s+override\s*:/i, category: 'injection', severity: 'block', description: 'System override directive' },
  { regex: /\[SYSTEM\]\s*:/i, category: 'injection', severity: 'block', description: 'System message impersonation' },
  { regex: /\[ADMIN\]\s*:/i, category: 'injection', severity: 'block', description: 'Admin message impersonation' },
  { regex: /do\s+not\s+(follow|obey|listen|apply)\s+(your|the|any|previous)/i, category: 'injection', severity: 'block', description: 'Instruction override attempt' },
];

const SECURITY_DISABLE_PATTERNS = [
  { regex: /disable\s+(all\s+)?(security|logging|hooks?|monitoring|protection)/i, category: 'security_disable', severity: 'block', description: 'Security disable directive' },
  { regex: /skip\s+(all\s+)?(security|validation|checks?|hooks?)/i, category: 'security_disable', severity: 'block', description: 'Security skip directive' },
  { regex: /turn\s+off\s+(all\s+)?(security|logging|monitoring)/i, category: 'security_disable', severity: 'block', description: 'Security turn-off directive' },
];

const EVASION_PATTERNS = [
  { regex: /\batob\s*\(/i, category: 'evasion', severity: 'warn', description: 'Base64 decode function' },
  { regex: /\bbase64\s+(-d|--decode|decode)\b/i, category: 'evasion', severity: 'warn', description: 'Base64 decode command' },
  { regex: /\becho\s+[A-Za-z0-9+/=]{20,}\s*\|\s*(base64|openssl)/i, category: 'evasion', severity: 'block', description: 'Encoded payload piped to decoder' },
  { regex: /\\x[0-9a-f]{2}.*\\x[0-9a-f]{2}.*\\x[0-9a-f]{2}/i, category: 'evasion', severity: 'warn', description: 'Hex-encoded content' },
];

const SENSITIVE_DATA_PATTERNS = [
  /\.env\b/i, /\bapi[_-]?key\b/i, /\bsecret[_-]?key\b/i, /\bcredential/i,
  /\bprivate[_-]?key\b/i, /\bssh[_-]?key\b/i, /\baws[_-]?access/i,
];

const EXFILTRATION_INTENT = [
  /\bsend\b.{0,30}\bto\s+(https?:|an?\s|the\s|my\s)/i,
  /\bpost\b.{0,30}\bto\s+(https?:|an?\s|the\s|my\s)/i,
  /\bupload\b.{0,30}\bto\s/i,
  /\bforward\b.{0,30}\bto\s/i,
  /\bexfiltrat/i,
  /\bpipe\b.{0,20}\bto\s/i,
  /\bsend\s+(the\s+)?(contents?|data|output|file|keys?|tokens?|secrets?|credentials?)\b/i,
];

const ALL_PROMPT_PATTERNS = [...INJECTION_PATTERNS, ...SECURITY_DISABLE_PATTERNS, ...EVASION_PATTERNS];

export function inspectPrompt(prompt) {
  if (!prompt || prompt.length < 10) return { action: 'allow', violations: [] };

  const hits = [];

  for (const { regex, category, description, severity } of ALL_PROMPT_PATTERNS) {
    if (regex.test(prompt)) {
      hits.push({ description, category, severity });
    }
  }

  // Two-phase exfiltration: sensitive data reference + outbound intent
  const hasSensitive = SENSITIVE_DATA_PATTERNS.some(p => p.test(prompt));
  if (hasSensitive) {
    for (const pattern of EXFILTRATION_INTENT) {
      if (pattern.test(prompt)) {
        hits.push({ description: 'Sensitive data + exfiltration intent', category: 'exfiltration', severity: 'block' });
        break;
      }
    }
  }

  if (hits.length === 0) return { action: 'allow', violations: [] };

  const categories = [...new Set(hits.map(h => h.category))];
  const descriptions = hits.map(h => h.description);

  // Advisory by design (drift register W1.1b): natural-language intent is
  // never a gate. Blocking lives in the action-level floor (bash/write/egress
  // inspectors); this inspector logs and annotates so the model judges text
  // it can actually read. `severity: 'block'` marks the high-signal hits.
  return {
    action: 'alert',
    severity: hits.some(h => h.severity === 'block') ? 'block' : 'warn',
    violations: hits,
    reason: `Prompt security: ${categories.join('+')} — ${descriptions.join(', ')}`,
  };
}

// ═══════════════════════════════════════════════════════════════
// CONTENT SCANNER (InjectionInspector)
// ═══════════════════════════════════════════════════════════════

const CONTENT_INJECTION_PATTERNS = [
  { regex: /ignore\s+(all\s+)?previous\s+instructions/i, category: 'instruction_override', description: 'Ignore previous instructions' },
  { regex: /forget\s+(everything|what|all|your)\s+(you\s+)?(were|know|previous)/i, category: 'instruction_override', description: 'Forget previous context' },
  { regex: /your\s+new\s+instructions\s+are/i, category: 'instruction_override', description: 'New instructions directive' },
  { regex: /you\s+are\s+now\s+in\s+\w+\s+mode/i, category: 'instruction_override', description: 'Mode switch attempt' },
  { regex: /disregard\s+(all\s+)?(prior|previous|above)/i, category: 'instruction_override', description: 'Disregard prior instructions' },
  { regex: /system\s+override[:\s]/i, category: 'system_impersonation', description: 'System override directive' },
  { regex: /admin\s+command[:\s]/i, category: 'system_impersonation', description: 'Admin command directive' },
  { regex: /\[SYSTEM\]\s*:/i, category: 'system_impersonation', description: 'System message impersonation' },
  { regex: /\[ADMIN\]\s*:/i, category: 'system_impersonation', description: 'Admin message impersonation' },
  { regex: /maintenance\s+mode[:\s]/i, category: 'system_impersonation', description: 'Maintenance mode claim' },
  { regex: /delete\s+all\s+files/i, category: 'dangerous_action', description: 'Delete all files directive' },
  { regex: /rm\s+-rf\s+[~\/]/i, category: 'dangerous_action', description: 'Recursive delete command' },
  { regex: /send\s+(your|the|all)\s+(config|configuration|credentials|secrets|keys|tokens)\s+to/i, category: 'exfiltration', description: 'Credential exfiltration attempt' },
  { regex: /exfiltrate|upload\s+(your|the)\s+(data|config|secrets)/i, category: 'exfiltration', description: 'Data exfiltration directive' },
  { regex: /disable\s+(all\s+)?(security|logging|monitoring|protection)/i, category: 'dangerous_action', description: 'Security disable directive' },
  { regex: /URGENT\s*(SYSTEM\s+)?MESSAGE\s*:/i, category: 'urgency_manipulation', description: 'Urgent system message' },
  { regex: /CRITICAL\s+UPDATE\s*:/i, category: 'urgency_manipulation', description: 'Critical update claim' },
  { regex: /EMERGENCY\s*(OVERRIDE|ACTION|UPDATE)\s*:/i, category: 'urgency_manipulation', description: 'Emergency override' },
  { regex: /<!--\s*(ignore|forget|system|admin|override|execute|delete|you\s+must)/i, category: 'hidden_instruction', description: 'Hidden instruction in HTML comment' },
  { regex: /style\s*=\s*"[^"]*color\s*:\s*white[^"]*font-size\s*:\s*[01]px/i, category: 'hidden_instruction', description: 'Invisible text styling' },
  { regex: /style\s*=\s*"[^"]*display\s*:\s*none/i, category: 'hidden_instruction', description: 'Hidden display element' },
];

export function inspectContent(content) {
  if (!content || content.length < 20) return { action: 'allow', violations: [] };

  const hits = [];

  for (const { regex, category, description } of CONTENT_INJECTION_PATTERNS) {
    const match = content.match(regex);
    if (match) {
      hits.push({ description, category, matched: match[0].substring(0, 100) });
    }
  }

  if (hits.length === 0) return { action: 'allow', violations: [] };

  const patternList = hits.map(h => `${h.description} (${h.category})`).join(', ');
  return {
    action: 'alert',
    violations: hits,
    reason: `Prompt injection detected: ${patternList}`,
  };
}

// ═══════════════════════════════════════════════════════════════
// AGENT GUARD (Orchestration Inspector — resource floor only)
// ═══════════════════════════════════════════════════════════════
// W2.1 (drift register, 2026-07-06): the keyword corpora that second-guessed
// the model's delegation and skill choices are gone — trivial-lookup/vague-
// prompt regexes, expensive-agent tables, and the whole SkillGuard
// (inspectSkillInvocation) with its high-cost/high-specificity skill lists:
// once the keyword rules left, nothing non-keyword remained in it. They were
// frozen judgment over a stringified-args proxy and advisory-only in practice
// (AgentGuard deny was env-gated off by default; SkillGuard never denied) —
// warn noise, not safety. The security floor (bash/secrets/egress/paths) is
// untouched; skill telemetry lives in subagent-trace and execution.jsonl.
// What stays is the one resource floor: the per-session fan-out cap.

const AGENTGUARD_FANOUT_MAX = parseInt(process.env.PAI_AGENTGUARD_FANOUT_MAX || '3', 10);

/**
 * Inspects an agent spawn request. Resource floor ONLY: warns when the
 * session's spawn count crosses the fan-out cap. Never denies — the cap is
 * budget advice; which agent to spawn is the model's judgment (W2.1).
 *
 * Contract (unchanged):
 *   Input:  { subagent_type, description, prompt, sessionAgentCount }
 *   Output: { action: 'allow'|'warn', rationale, metadata }
 */
export function inspectAgentSpawn({ subagent_type, description, prompt, sessionAgentCount = 0 }) {
  const agentType = (subagent_type || '').toLowerCase();
  const textLength = `${description || ''} ${prompt || ''}`.trim().length;

  if (sessionAgentCount >= AGENTGUARD_FANOUT_MAX) {
    const reason = `Session already spawned ${sessionAgentCount} agents (threshold: ${AGENTGUARD_FANOUT_MAX}) — consider serializing or using native tools`;
    return {
      action: 'warn',
      rationale: reason,
      metadata: {
        agentType,
        hits: [{ rule: 'fanout_threshold', reason, confidence: 'medium' }],
        textLength,
        sessionAgentCount,
      },
    };
  }

  return {
    action: 'allow',
    rationale: 'Within fan-out budget',
    metadata: { agentType, textLength, sessionAgentCount },
  };
}

// ═══════════════════════════════════════════════════════════════
// SATISFACTION CAPTURE UTILITIES
// ═══════════════════════════════════════════════════════════════

export const WORD_NUMBERS = {
  one: 1, two: 2, three: 3, four: 4, five: 5,
  six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
};

export function parseExplicitRating(prompt) {
  const trimmed = prompt.trim();
  const lowerTrimmed = trimmed.toLowerCase();

  // Handle /rate N and /rating N prefix
  const ratePrefixMatch = lowerTrimmed.match(/^\/(?:rate|rating)\s+(.*)$/);
  if (ratePrefixMatch) {
    const afterPrefix = ratePrefixMatch[1].trim();
    // Try to parse the number after the prefix
    const numMatch = afterPrefix.match(/^(10|[1-9])(?:\s|$)/);
    if (numMatch) {
      const rating = parseInt(numMatch[1], 10);
      const rest = afterPrefix.slice(numMatch[1].length).trim() || undefined;
      if (rating >= 1 && rating <= 10) {
        return { rating, comment: rest };
      }
    }
  }

  // Check word-form ratings first
  for (const [word, num] of Object.entries(WORD_NUMBERS)) {
    if (lowerTrimmed === word || lowerTrimmed.startsWith(word + ' ') || lowerTrimmed.startsWith(word + '!')) {
      const rest = trimmed.slice(word.length).trim().replace(/^[!.,]+/, '').trim() || undefined;
      return { rating: num, comment: rest };
    }
  }

  const ratingPattern = /^(10|[1-9])(?:\s*[-:]\s*|\s+)?(.*)$/;
  const match = trimmed.match(ratingPattern);
  if (!match) return null;

  const rating = parseInt(match[1], 10);
  const rest = match[2]?.trim() || undefined;

  if (rating < 1 || rating > 10) return null;

  const afterNumber = trimmed.slice(match[1].length);
  if (afterNumber.length > 0 && /^[/\.\dA-Za-z]/.test(afterNumber)) return null;

  if (rest) {
    const sentenceStarters = /^(items?|things?|steps?|files?|lines?|bugs?|issues?|errors?|times?|minutes?|hours?|days?|seconds?|percent|%|th\b|st\b|nd\b|rd\b|of\b|in\b|at\b|to\b|the\b|a\b|an\b)/i;
    if (sentenceStarters.test(rest)) return null;
  }

  return { rating, comment: rest };
}

export function isSystemText(prompt) {
  const SYSTEM_TEXT_PATTERNS = [
    /^<task-notification>/i,
    /^<system-reminder>/i,
    /^This session is being continued from a previous conversation/i,
    /^Please continue the conversation/i,
    /^Note:.*was read before/i,
  ];
  return SYSTEM_TEXT_PATTERNS.some(re => re.test(prompt.trim()));
}

export function detectPositivePraise(prompt) {
  const POSITIVE_PRAISE_WORDS = new Set([
    'excellent', 'amazing', 'brilliant', 'fantastic', 'wonderful', 'beautiful',
    'incredible', 'awesome', 'perfect', 'great', 'nice', 'superb', 'outstanding',
    'magnificent', 'stellar', 'phenomenal', 'remarkable', 'terrific', 'splendid',
  ]);

  const POSITIVE_PHRASES = new Set([
    'great job', 'good job', 'nice work', 'well done', 'nice job', 'good work',
    'love it', 'nailed it', 'looks great', 'looks good', 'thats great', 'that works',
  ]);

  const NEGATION_MARKERS = new Set(['but', 'however', 'though', 'except']);

  const normalized = prompt.trim().toLowerCase().replace(/[.!?,'"]/g, '');
  const words = normalized.split(/\s+/);

  for (const phrase of POSITIVE_PHRASES) {
    if (normalized.includes(phrase)) {
      return true;
    }
  }

  if (words.some((word) => NEGATION_MARKERS.has(word))) {
    return false;
  }

  if (words.length <= 2) {
    if (POSITIVE_PRAISE_WORDS.has(normalized) || POSITIVE_PHRASES.has(normalized)) {
      return true;
    }
    if (words.length === 2 && words.every(w => POSITIVE_PRAISE_WORDS.has(w))) {
      return true;
    }
  }

  if (words.length <= 8 && POSITIVE_PRAISE_WORDS.has(words[0])) {
    return true;
  }

  return false;
}

// ═══════════════════════════════════════════════════════════════
// LEARNING UTILITIES
// ═══════════════════════════════════════════════════════════════

export function getLearningCategory(content, comment) {
  const text = `${content} ${comment || ''}`.toLowerCase();

  const algorithmIndicators = [
    /over.?engineer/,
    /wrong approach/,
    /should have asked/,
    /didn't follow/,
    /missed the point/,
    /too complex/,
    /didn't understand/,
    /wrong direction/,
    /not what i wanted/,
    /approach|method|strategy|reasoning/
  ];

  const systemIndicators = [
    /hook|crash|broken/,
    /tool|config|deploy|path/,
    /import|module|file.*not.*found/,
    /typescript|javascript|npm|bun/
  ];

  for (const pattern of algorithmIndicators) {
    if (pattern.test(text)) return 'ALGORITHM';
  }

  for (const pattern of systemIndicators) {
    if (pattern.test(text)) return 'SYSTEM';
  }

  return 'ALGORITHM';
}

// ═══════════════════════════════════════════════════════════════
// WORK REGISTRY UTILITIES
// ═══════════════════════════════════════════════════════════════

export function readWorkRegistry() {
  const workJsonPath = join(STATE_DIR, 'work.json');
  try {
    const data = JSON.parse(readFileSync(workJsonPath, 'utf-8'));
    return data.sessions ? data : { sessions: {} };
  } catch { return { sessions: {} }; }
}

export function writeWorkRegistry(reg) {
  const workJsonPath = join(STATE_DIR, 'work.json');
  ensureDir(STATE_DIR);
  const tmp = workJsonPath + '.tmp';
  writeFileSync(tmp, JSON.stringify(reg, null, 2));
  const { renameSync } = require('fs');
  renameSync(tmp, workJsonPath);
}

export function findArtifactPath(slug) {
  const dir = join(WORK_DIR, slug);
  const isa = join(dir, 'ISA.md');
  if (existsSync(isa)) return isa;
  const legacy = join(dir, 'PRD.md');
  if (existsSync(legacy)) return legacy;
  return null;
}

// ═══════════════════════════════════════════════════════════════
// PULSE INTEGRATION
// ═══════════════════════════════════════════════════════════════

export async function emitPulseEvent(event) {
  try {
    await fetch('http://localhost:31337/api/events', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(event),
      signal: AbortSignal.timeout(1000),
    });
    return true;
  } catch (e) {
    return false;
  }
}

export async function notifyPulse(message, options = {}) {
  try {
    const language = normalizeNotificationLanguage(options.language);
    await fetch('http://localhost:31337/notify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message,
        voice_enabled: options.voice_enabled || false,
        voice_id: options.voice_id || process.env.ELEVENLABS_VOICE_ID,
        ...(language ? { language } : {}),
      }),
      signal: AbortSignal.timeout(2000),
    });
    return true;
  } catch (e) {
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════
// GIT SNAPSHOT
// ═══════════════════════════════════════════════════════════════

export function gitSnapshot(cwd) {
  try {
    const { execFileSync } = require('child_process');
    const head = execFileSync('git', ['rev-parse', '--short', 'HEAD'], {
      cwd, encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 500,
    }).trim();
    const status = execFileSync('git', ['status', '--porcelain'], {
      cwd, encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 500,
    });
    return { head, dirty: status.trim().length > 0 };
  } catch {
    return undefined;
  }
}

// ═══════════════════════════════════════════════════════════════
// SESSION NAME UTILITIES
// ═══════════════════════════════════════════════════════════════

export function readSessionNames() {
  const namesPath = join(STATE_DIR, 'session-names.json');
  try {
    if (existsSync(namesPath)) {
      return JSON.parse(readFileSync(namesPath, 'utf-8'));
    }
  } catch {}
  return {};
}

export function writeSessionNames(names) {
  const namesPath = join(STATE_DIR, 'session-names.json');
  safeWriteJson(namesPath, names);
}

// ═══════════════════════════════════════════════════════════════
// ISA FRONTMATTER UTILITIES
// ═══════════════════════════════════════════════════════════════

export function parseFrontmatter(content) {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return null;
  const fm = {};
  for (const line of match[1].split('\n')) {
    const idx = line.indexOf(':');
    if (idx > 0) fm[line.slice(0, idx).trim()] = line.slice(idx + 1).trim().replace(/^["']|["']$/g, '');
  }
  return fm;
}

// ═══════════════════════════════════════════════════════════════
// ISA ↔ WORK-STATE SYNC
// ═══════════════════════════════════════════════════════════════

/**
 * Detect whether a file path is an ISA/task artifact.
 * Recognizes:
 *   - task ISA paths in MEMORY/WORK/**
 *   - project ISA.md files
 *   - legacy PRD.md files
 */
export function isISAArtifactPath(filePath) {
  if (!filePath) return false;
  const normalized = filePath.replace(/\\/g, '/');
  const isaPatterns = [
    /MEMORY\/WORK\/[^/]+\/ISA\.md$/i,
    /MEMORY\/WORK\/[^/]+\/PRD\.md$/i,
    /\/ISA\.md$/i,
  ];
  return isaPatterns.some(p => p.test(normalized));
}

/**
 * Extract state-bearing fields from an ISA file's frontmatter.
 * Returns null if file is missing or has no parseable frontmatter.
 */
export function extractISAState(filePath) {
  try {
    if (!existsSync(filePath)) return null;
    const content = readFileSync(filePath, 'utf-8');
    const fm = parseFrontmatter(content);
    if (!fm) return null;

    const state = {};
    if (fm.phase !== undefined) state.phase = fm.phase;
    if (fm.progress !== undefined) state.progress = fm.progress;
    if (fm.updated !== undefined) state.updated = fm.updated;
    if (fm.effort !== undefined) state.effort = fm.effort;
    if (fm.mode !== undefined) state.mode = fm.mode;
    if (fm.task !== undefined) state.task = fm.task;
    if (fm.slug !== undefined) state.slug = fm.slug;
    if (fm.title !== undefined) state.title = fm.title;
    if (fm.status !== undefined) state.status = fm.status;

    return Object.keys(state).length > 0 ? state : null;
  } catch {
    return null;
  }
}

/**
 * Synchronize ISA frontmatter state into the work.json registry.
 * Upserts the matching session by slug or sessionUUID; never duplicates.
 * If sessionId is provided, also updates current-work-<sessionId>.json.
 */
export function syncISAToWorkRegistry(filePath, sessionId = null) {
  const isaState = extractISAState(filePath);
  if (!isaState) return { synced: false, reason: 'no_state_extracted' };

  try {
    const registry = readWorkRegistry();
    if (!registry.sessions) registry.sessions = {};

    // Derive slug from file path: /.../MEMORY/WORK/<slug>/ISA.md
    const pathParts = filePath.replace(/\\/g, '/').split('/');
    const workIdx = pathParts.findIndex(p => p.toUpperCase() === 'WORK');
    let slug = (workIdx >= 0 && pathParts[workIdx + 1])
      ? pathParts[workIdx + 1]
      : null;
    // Fallback: use parent directory name when path is not under MEMORY/WORK
    if (!slug && pathParts.length >= 2) {
      slug = pathParts[pathParts.length - 2];
    }

    // Find existing session: prefer exact slug match, then sessionUUID match
    let targetSlug = null;
    if (slug && registry.sessions[slug]) {
      targetSlug = slug;
    } else if (sessionId) {
      for (const [s, sess] of Object.entries(registry.sessions)) {
        if (sess.sessionUUID === sessionId) {
          targetSlug = s;
          break;
        }
      }
    }

    // If no existing session, create one only when we have a slug
    if (!targetSlug) {
      if (!slug) return { synced: false, reason: 'no_slug_derived' };
      targetSlug = slug;
      registry.sessions[targetSlug] = {
        sessionUUID: sessionId || undefined,
        started: isaState.updated || getISOTimestamp(),
      };
    }

    const session = registry.sessions[targetSlug];
    const previousPhase = session.phase;

    // Apply ISA state fields (source of truth)
    if (isaState.phase !== undefined) session.phase = isaState.phase;
    if (isaState.progress !== undefined) session.progress = isaState.progress;
    if (isaState.updated !== undefined) session.updatedAt = isaState.updated;
    if (isaState.effort !== undefined) session.effort = isaState.effort;
    if (isaState.mode !== undefined) session.mode = isaState.mode;
    if (isaState.task !== undefined) session.task = isaState.task;
    if (isaState.title !== undefined) session.task = isaState.title;
    if (isaState.status !== undefined) session.status = isaState.status;

    session.updatedAt = getISOTimestamp();

    writeWorkRegistry(registry);

    // Notify on real phase transitions (ISA frontmatter is the single
    // source of truth for phase, so this is THE phase-change signal)
    if (isaState.phase !== undefined && isaState.phase !== previousPhase) {
      emitNotification({
        event: 'phase_transition',
        sessionId: sessionId || session.sessionUUID || null,
        slug: targetSlug,
        title: session.task || null,
        data: {
          phase: isaState.phase,
          previous_phase: previousPhase ?? null,
          progress: isaState.progress ?? null,
        },
      });
    }

    // Also sync to current-work-<sessionId>.json when available
    if (sessionId) {
      try {
        const cwPath = join(STATE_DIR, `current-work-${sessionId}.json`);
        const cw = safeReadJson(cwPath, { session_id: sessionId });
        cw.isa_sync = isaState;
        cw.isa_synced_at = getISOTimestamp();
        cw.isa_source = filePath;
        safeWriteJson(cwPath, cw);
      } catch {
        // Best-effort: current-work update is non-critical
      }
    }

    return { synced: true, slug: targetSlug, fields: Object.keys(isaState) };
  } catch (e) {
    console.error(`[PAI] ISA sync failed: ${e.message}`);
    return { synced: false, reason: e.message };
  }
}

// ═══════════════════════════════════════════════════════════════
// ISC CHECKPOINTS
// ═══════════════════════════════════════════════════════════════

export function parseCriteriaList(content) {
  const criteria = [];
  const lines = String(content || '').split(/\r?\n/);

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const match = line.match(/^\s*-\s*\[([ xX~-])\]\s*(?:\[[A-Z]\]\s*)?(ISC-\d+(?:\.\d+)?(?:-[A-Z]-\d+)?)\s*(?::|—|-)\s*(.+?)\s*$/);
    if (!match) continue;

    const marker = match[1].trim().toLowerCase();
    criteria.push({
      id: match[2],
      description: match[3].trim(),
      status: marker === 'x' ? 'completed' : marker === '~' || marker === '-' ? 'deferred' : 'open',
      line: i + 1,
    });
  }

  return criteria;
}

function expandCheckpointPath(value) {
  let out = String(value || '').trim();
  if (!out) return out;
  if (out === '~') out = homedir();
  if (out.startsWith('~/')) out = join(homedir(), out.slice(2));
  out = out.replace(/^\$HOME(?=\/|$)/, homedir());
  return out;
}

export function loadCheckpointRepos() {
  const allowlistPath = join(PAI_DIR, 'checkpoint-repos.txt');
  if (!existsSync(allowlistPath)) return [];

  try {
    return [...new Set(readFileSync(allowlistPath, 'utf-8')
      .split(/\r?\n/)
      .map(line => line.trim())
      .filter(line => line && !line.startsWith('#'))
      .map(expandCheckpointPath))];
  } catch {
    return [];
  }
}

function checkpointSlugFor(filePath, fm = {}) {
  const normalized = String(filePath || '').replace(/\\/g, '/');
  const parts = normalized.split('/');
  const workIdx = parts.findIndex(part => part.toUpperCase() === 'WORK');
  if (workIdx >= 0 && parts[workIdx + 1]) return parts[workIdx + 1];
  return fm.slug || fm.title || basename(dirname(filePath || 'project-isa'));
}

function checkpointStatePath(filePath, slug) {
  const normalized = String(filePath || '').replace(/\\/g, '/');
  if (/\/MEMORY\/WORK\/[^/]+\/(?:ISA|PRD)\.md$/i.test(normalized)) {
    return join(dirname(filePath), '.checkpoint-state.json');
  }
  return join(STATE_DIR, 'checkpoints', `${hashString(String(slug), 12)}.json`);
}

function loadCheckpointState(path) {
  const fallback = { committed_iscs: [], last_commit_sha: {}, entries: [] };
  if (!existsSync(path)) return fallback;
  try {
    const parsed = JSON.parse(readFileSync(path, 'utf-8'));
    return {
      committed_iscs: Array.isArray(parsed.committed_iscs) ? parsed.committed_iscs : [],
      last_commit_sha: parsed.last_commit_sha && typeof parsed.last_commit_sha === 'object' ? parsed.last_commit_sha : {},
      entries: Array.isArray(parsed.entries) ? parsed.entries : [],
    };
  } catch {
    return fallback;
  }
}

function saveCheckpointState(path, state) {
  ensureDir(dirname(path));
  const tmp = `${path}.tmp`;
  writeFileSync(tmp, JSON.stringify(state, null, 2) + '\n', 'utf-8');
  const { renameSync } = require('fs');
  renameSync(tmp, path);
}

function gitCheckpoint(repo, args) {
  return execFileSync('git', ['-C', repo, ...args], {
    encoding: 'utf-8',
    timeout: 5000,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function isCheckpointGitRepo(repo) {
  try {
    gitCheckpoint(repo, ['rev-parse', '--git-dir']);
    return true;
  } catch {
    return false;
  }
}

function hasCheckpointChanges(repo) {
  try {
    return gitCheckpoint(repo, ['status', '--porcelain']).trim().length > 0;
  } catch {
    return false;
  }
}

function sanitizeCheckpointSubject(value) {
  return String(value || 'checkpoint')
    .replace(/\s+/g, ' ')
    .replace(/[`$]/g, '')
    .trim()
    .slice(0, 200);
}

function commitCheckpoint(repo, iscId, slug, description) {
  gitCheckpoint(repo, ['add', '-A']);
  gitCheckpoint(repo, ['commit', '-m', `${iscId} (${slug}): ${sanitizeCheckpointSubject(description)}`, '--quiet', '--no-verify', '--no-gpg-sign']);
  return gitCheckpoint(repo, ['rev-parse', 'HEAD']).trim();
}

export function recordISCCheckpointsFromISA(filePath, options = {}) {
  try {
    if (!isISAArtifactPath(filePath) || !existsSync(filePath)) {
      return { status: 'skipped', reason: 'not_isa_artifact', checkpoints: [] };
    }

    const content = readFileSync(filePath, 'utf-8');
    const fm = parseFrontmatter(content) || {};
    const slug = checkpointSlugFor(filePath, fm);
    const stateFile = checkpointStatePath(filePath, slug);
    const state = loadCheckpointState(stateFile);
    const already = new Set(state.committed_iscs);
    const newlyCompleted = parseCriteriaList(content)
      .filter(criterion => criterion.status === 'completed' && !already.has(criterion.id));

    if (newlyCompleted.length === 0) {
      return { status: 'noop', reason: 'no_new_completed_isc', slug, checkpoints: [] };
    }

    const repos = loadCheckpointRepos();
    if (repos.length === 0) {
      return {
        status: 'skipped',
        reason: 'no_checkpoint_repos_configured',
        slug,
        allowlist: join(PAI_DIR, 'checkpoint-repos.txt'),
        checkpoints: newlyCompleted.map(criterion => criterion.id),
      };
    }

    const entries = [];
    for (const criterion of newlyCompleted) {
      const repoResults = [];
      for (const repo of repos) {
        if (!existsSync(repo)) {
          repoResults.push({ repo, status: 'missing', sha: null });
          continue;
        }
        if (!isCheckpointGitRepo(repo)) {
          repoResults.push({ repo, status: 'not_git', sha: null });
          continue;
        }
        if (!hasCheckpointChanges(repo)) {
          repoResults.push({ repo, status: 'clean', sha: null });
          continue;
        }
        try {
          const sha = commitCheckpoint(repo, criterion.id, slug, criterion.description);
          state.last_commit_sha[repo] = sha;
          repoResults.push({ repo, status: 'committed', sha });
        } catch (error) {
          repoResults.push({
            repo,
            status: 'failed',
            sha: null,
            error: error?.stderr?.toString?.() || error?.message || String(error),
          });
        }
      }

      state.committed_iscs.push(criterion.id);
      const entry = {
        id: criterion.id,
        description: criterion.description,
        slug,
        timestamp: getISOTimestamp(),
        session_id: options.sessionId || null,
        source: filePath,
        repos: repoResults,
      };
      state.entries.push(entry);
      entries.push(entry);
    }

    saveCheckpointState(stateFile, state);
    return { status: 'ok', slug, stateFile, checkpoints: entries };
  } catch (error) {
    return {
      status: 'failed',
      reason: error?.message || String(error),
      checkpoints: [],
    };
  }
}

export function writeFrontmatterField(content, field, value) {
  const fmMatch = content.match(/^(---\n)([\s\S]*?)(\n---)/);
  if (!fmMatch) return content;
  const lines = fmMatch[2].split('\n');
  let found = false;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].startsWith(`${field}:`)) {
      lines[i] = `${field}: ${value}`;
      found = true;
      break;
    }
  }
  if (!found) lines.push(`${field}: ${value}`);
  return fmMatch[1] + lines.join('\n') + fmMatch[3] + content.slice(fmMatch[0].length);
}

// ═══════════════════════════════════════════════════════════════
// WORK SESSION ANALYSIS
// ═══════════════════════════════════════════════════════════════

export function getRecentWorkSessions(cutoffHours = 48) {
  if (!existsSync(WORK_DIR)) return [];

  const sessions = [];
  const now = Date.now();
  const cutoff = cutoffHours * 60 * 60 * 1000;

  try {
    const entries = readdirSync(WORK_DIR, { withFileTypes: true })
      .filter(d => d.isDirectory() && /^\d{8}-\d{6}_/.test(d.name))
      .map(d => d.name)
      .sort()
      .reverse()
      .slice(0, 30);

    for (const dirName of entries) {
      const match = dirName.match(/^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})_(.+)$/);
      if (!match) continue;

      const [, y, mo, d, h, mi, s, slug] = match;
      const dirTime = new Date(`${y}-${mo}-${d}T${h}:${mi}:${s}`).getTime();

      if (now - dirTime > cutoff) break;

      const isaPath = findArtifactPath(dirName);
      if (!isaPath) continue;

      try {
        const head = readFileSync(isaPath, 'utf-8').substring(0, 600);
        const statusMatch = head.match(/^status:\s*"?(\w+)"?/m);
        const titleMatch = head.match(/^title:\s*"?(.+?)"?\s*$/m);
        const status = statusMatch ? statusMatch[1] : 'UNKNOWN';
        const title = titleMatch ? titleMatch[1] : slug.replace(/-/g, ' ');

        if (status === 'COMPLETED') continue;

        sessions.push({
          dirName,
          title: title.length > 60 ? title.substring(0, 57) + '...' : title,
          status,
          timestamp: `${y}-${mo}-${d} ${h}:${mi}`,
        });
      } catch { /* skip */ }
    }
  } catch (err) {
    console.error(`[PAI] Error scanning WORK dirs: ${err.message}`);
  }

  return sessions;
}

// ═══════════════════════════════════════════════════════════════
// EXPORT DEFAULT
// ═══════════════════════════════════════════════════════════════

export default {
  PAI_DIR,
  MEMORY_DIR,
  STATE_DIR,
  WORK_DIR,
  LEARNING_DIR,
  OBSERVABILITY_DIR,
  ensureDir,
  safeReadJson,
  safeWriteJson,
  appendJsonL,
  getISOTimestamp,
  getPSTComponents,
  getPSTDate,
  getSessionId,
  findStateFile,
  truncate,
  logSecurityEvent,
  inspectBashCommand,
  inspectWritePath,
  inspectReadPath,
  inspectWriteContent,
  inspectEgress,
  shellQuoteSingle,
  shouldSandboxCommand,
  resolveSandboxScript,
  sandboxAvailable,
  wrapBashInSandbox,
  inspectPrompt,
  inspectContent,
  inspectAgentSpawn,
  parseExplicitRating,
  isSystemText,
  detectPositivePraise,
  getLearningCategory,
  readWorkRegistry,
  writeWorkRegistry,
  findArtifactPath,
  emitPulseEvent,
  notifyPulse,
  gitSnapshot,
  readSessionNames,
  writeSessionNames,
  parseFrontmatter,
  writeFrontmatterField,
  getRecentWorkSessions,
  isISAArtifactPath,
  extractISAState,
  syncISAToWorkRegistry,
  parseCriteriaList,
  loadCheckpointRepos,
  recordISCCheckpointsFromISA,
};
