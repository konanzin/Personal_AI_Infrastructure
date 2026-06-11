/**
 * PAI Hooks Plugin - Shared Utilities (pai-hooks.lib.js)
 * 
 * Common utilities extracted from PAI v5.0.0 hooks for use by pai-hooks.js.
 * Mirrors the functionality of hooks-reference/lib/* and security/* modules.
 * 
 * @version 1.0.0
 */

import { existsSync, readFileSync, writeFileSync, appendFileSync, mkdirSync, readdirSync, statSync, unlinkSync } from 'fs';
import { join, dirname, resolve } from 'path';
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

export function buildSpeak(event, data = {}) {
  const builder = SPEAK_BUILDERS[event];
  const phrase = builder ? builder(data) : `PAI event: ${event}`;
  // Keep it speakable: single line, bounded length
  return truncate(String(phrase).replace(/\s+/g, ' ').trim(), 160);
}

export function emitNotification({ event, sessionId, slug = null, title = null, data = {}, speak = null, level = null }) {
  try {
    const entry = {
      v: 1,
      timestamp: getISOTimestamp(),
      level: level || NOTIFICATION_LEVELS[event] || 'milestone',
      event,
      session_id: sessionId || 'unknown',
      slug,
      title: title || data.title || slug || null,
      speak: speak ? truncate(String(speak).replace(/\s+/g, ' ').trim(), 160) : buildSpeak(event, { ...data, slug, title }),
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

// Dangerous bash patterns that should be BLOCKED
const BLOCKED_PATTERNS = [
  { pattern: /rm\s+-rf/, reason: 'rm -rf detected', severity: 'critical' },
  { pattern: /curl\s+.*\|\s*bash/, reason: 'curl | bash detected', severity: 'critical' },
  { pattern: /curl\s+.*\|\s*sh/, reason: 'curl | sh detected', severity: 'critical' },
  { pattern: /wget\s+.*\|\s*bash/, reason: 'wget | bash detected', severity: 'critical' },
  { pattern: /wget\s+.*\|\s*sh/, reason: 'wget | sh detected', severity: 'critical' },
  { pattern: /:\(\)\s*\{\s*:\|:&\s*\};:/, reason: 'Fork bomb detected', severity: 'critical' },
  { pattern: /mkfs\./, reason: 'mkfs filesystem wipe detected', severity: 'critical' },
  { pattern: /dd\s+if=.*of=\/dev\/(sd|hd|nvme)/, reason: 'dd to disk device detected', severity: 'critical' },
  { pattern: />\s*\/dev\/(sd|hd|nvme)/, reason: 'Redirect to disk device detected', severity: 'critical' },
  { pattern: /chmod\s+-R\s+777\s+\//, reason: 'chmod 777 root detected', severity: 'high' },
  { pattern: /chown\s+-R\s+.*\s+\//, reason: 'chown root detected', severity: 'high' },
];

// Dangerous patterns that require CONFIRMATION
const CONFIRM_PATTERNS = [
  { pattern: /curl\s+.*\|/, reason: 'Piping curl output requires confirmation' },
  { pattern: /wget\s+.*\|/, reason: 'Piping wget output requires confirmation' },
  { pattern: /eval\s*[\(`"']/, reason: 'eval usage requires confirmation' },
  { pattern: /exec\s*\(/, reason: 'exec usage requires confirmation' },
  { pattern: /spawn\s*\(/, reason: 'spawn usage requires confirmation' },
  { pattern: /child_process/, reason: 'child_process usage requires confirmation' },
  { pattern: /python3?\s+-c\s/, reason: 'Python inline execution requires confirmation' },
  { pattern: /node\s+-e\s/, reason: 'Node inline execution requires confirmation' },
  { pattern: /perl\s+-e\s/, reason: 'Perl inline execution requires confirmation' },
];

// Alert patterns (logged but allowed)
const ALERT_PATTERNS = [
  { pattern: /npm\s+.*--unsafe-perm/, reason: 'npm --unsafe-perm detected' },
  { pattern: /process\.exit\s*\(/, reason: 'process.exit detected' },
];

// Sensitive paths that should be blocked for writes
const ZERO_ACCESS_PATHS = [
  '/etc/passwd',
  '/etc/shadow',
  '/etc/sudoers',
  '/etc/hosts',
  '/etc/resolv.conf',
];

const READ_ONLY_PATHS = [
  join(homedir(), '.ssh'),
  join(homedir(), '.gnupg'),
  join(homedir(), '.aws'),
];

const CONFIRM_WRITE_PATHS = [
  '.env',
  '.env.',
  '.npmrc',
  '.pypirc',
  'id_rsa',
  'id_ed25519',
  '.htpasswd',
  'shadow',
  'passwd',
  'sudoers',
];

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

export function inspectBashCommand(command) {
  const normalized = stripEnvVarPrefix(command);
  if (!normalized) return { action: 'allow', violations: [] };

  const violations = [];

  // Check blocked patterns
  for (const { pattern, reason, severity } of BLOCKED_PATTERNS) {
    if (pattern.test(normalized)) {
      violations.push({ action: 'deny', reason, severity, type: 'blocked' });
    }
  }

  // Check confirm patterns
  for (const { pattern, reason } of CONFIRM_PATTERNS) {
    if (pattern.test(normalized)) {
      violations.push({ action: 'require_approval', reason, severity: 'medium', type: 'confirm' });
    }
  }

  // Check alert patterns
  for (const { pattern, reason } of ALERT_PATTERNS) {
    if (pattern.test(normalized)) {
      violations.push({ action: 'alert', reason, severity: 'low', type: 'alert' });
    }
  }

  if (violations.length === 0) return { action: 'allow', violations: [] };

  // Priority: deny > require_approval > alert
  const hasDeny = violations.some(v => v.action === 'deny');
  if (hasDeny) {
    const critical = violations.filter(v => v.action === 'deny');
    return { action: 'deny', violations: critical };
  }

  const hasConfirm = violations.some(v => v.action === 'require_approval');
  if (hasConfirm) {
    const confirms = violations.filter(v => v.action === 'require_approval');
    return { action: 'require_approval', violations: confirms };
  }

  return { action: 'alert', violations };
}

export function inspectWritePath(filePath, action = 'write') {
  const normalized = resolve(expandTilde(filePath));
  const violations = [];

  // Zero access paths
  for (const p of ZERO_ACCESS_PATHS) {
    if (matchesPathPattern(normalized, p)) {
      violations.push({ action: 'deny', reason: `Zero access path: ${p}` });
    }
  }

  if (action === 'write' || action === 'delete') {
    // Read-only paths
    for (const p of READ_ONLY_PATHS) {
      if (matchesPathPattern(normalized, p)) {
        violations.push({ action: 'deny', reason: `Read-only path: ${p}` });
      }
    }

    // Confirm write paths
    for (const p of CONFIRM_WRITE_PATHS) {
      if (normalized.toLowerCase().includes(p.toLowerCase())) {
        violations.push({ action: 'require_approval', reason: `Writing to protected file: ${p}` });
      }
    }
  }

  if (action === 'delete') {
    violations.push({ action: 'require_approval', reason: 'Delete operation requires confirmation' });
  }

  if (violations.length === 0) return { action: 'allow', violations: [] };

  const hasDeny = violations.some(v => v.action === 'deny');
  if (hasDeny) return { action: 'deny', violations: violations.filter(v => v.action === 'deny') };

  const hasConfirm = violations.some(v => v.action === 'require_approval');
  if (hasConfirm) return { action: 'require_approval', violations: violations.filter(v => v.action === 'require_approval') };

  return { action: 'alert', violations };
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

  const hasBlock = hits.some(h => h.severity === 'block');
  const categories = [...new Set(hits.map(h => h.category))];
  const descriptions = hits.map(h => h.description);

  if (hasBlock) {
    return {
      action: 'deny',
      violations: hits.filter(h => h.severity === 'block'),
      reason: `Prompt security: ${categories.join('+')} — ${descriptions.join(', ')}`,
    };
  }

  return {
    action: 'alert',
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
// AGENT GUARD (Orchestration Inspector)
// ═══════════════════════════════════════════════════════════════

// Configuration
const AGENTGUARD_FANOUT_MAX = parseInt(process.env.PAI_AGENTGUARD_FANOUT_MAX || '3', 10);
const AGENTGUARD_DENY_CONFIDENCE = process.env.PAI_AGENTGUARD_DENY_CONFIDENCE === 'true';

// Patterns that indicate a task should use native tools instead of agents
const TRIVIAL_LOOKUP_PATTERNS = [
  // File location / existence
  { regex: /\b(find|locate|where is|search for)\s+(the\s+)?(file|files?)\s+(named|called|with|matching)\b/i, reason: 'Trivial file lookup — use glob/read/grep instead of agent', confidence: 'high' },
  { regex: /\b(find|locate|where is|search for)\s+(a\s+)?(file|files?)\b/i, reason: 'Trivial file lookup — use glob/read/grep instead of agent', confidence: 'medium' },
  // Simple content search
  { regex: /\b(search|grep|find)\s+(for\s+)?[\"']?[a-z0-9_.\-*]{1,30}[\"']?\s+in\s+(files?|code|codebase|project|repo)\b/i, reason: 'Simple text search — use grep/glob directly', confidence: 'high' },
  // Read file content
  { regex: /\b(read|show|display|get|output)\s+(the\s+)?(contents?|content|text|lines?)\s+(of\s+)?[a-zA-Z0-9_\-\.\/]{1,60}\b/i, reason: 'Trivial read — use read tool directly', confidence: 'high' },
  { regex: /\b(read|show|display|get)\s+(me\s+)?(the\s+)?file\b/i, reason: 'Trivial read — use read tool directly', confidence: 'medium' },
  // Simple counting/listing
  { regex: /\b(count|how many)\s+(files?|lines?|occurrences?|matches?)\b/i, reason: 'Simple counting — use bash wc/grep -c', confidence: 'medium' },
  { regex: /\b(list all|show all|enumerate)\s+(files?|directories?)\s+(matching|with|in)\b/i, reason: 'Simple listing — use glob/ls instead of agent', confidence: 'medium' },
];

// Patterns indicating vague or underspecified delegation
const VAGUE_PROMPT_PATTERNS = [
  { regex: /^.{1,30}$/, reason: 'Prompt too short for meaningful delegation (< 30 chars)', confidence: 'medium' },
  { regex: /\b(do something|help me|fix this|check this|look at this|handle this)\b/i, reason: 'Vague delegation — prompt lacks specificity', confidence: 'medium' },
  { regex: /\b(just|simply|only)\s+\w+\s+(it|this|that)\b/i, reason: 'Vague delegation — underspecified task', confidence: 'low' },
];

// Agent types that are expensive or specialized
const EXPENSIVE_AGENT_TYPES = ['research', 'extensive_research', 'deep_investigation', 'council', 'redteam', 'worldthreatmodel'];

// Agent types suitable for trivial tasks
const LIGHTWEIGHT_AGENT_TYPES = ['explore', 'quick', 'fast'];

/**
 * Inspects an agent spawn request and returns allow/warn/deny.
 *
 * Contract:
 *   Input:  { subagent_type, description, prompt, sessionAgentCount }
 *   Output: { action: 'allow'|'warn'|'deny', rationale, metadata }
 *
 * Philosophy: warn-first. Deny only when confidence is very high and
 * the misuse is unambiguous.
 */
export function inspectAgentSpawn({ subagent_type, description, prompt, sessionAgentCount = 0 }) {
  const text = `${description || ''} ${prompt || ''}`.toLowerCase().trim();
  const agentType = (subagent_type || '').toLowerCase();
  const hits = [];

  // Rule 1: Trivial lookup → should use native tools
  for (const { regex, reason, confidence } of TRIVIAL_LOOKUP_PATTERNS) {
    if (regex.test(text)) {
      hits.push({ rule: 'trivial_lookup', reason, confidence });
    }
  }

  // Rule 2: Vague delegation
  for (const { regex, reason, confidence } of VAGUE_PROMPT_PATTERNS) {
    if (regex.test(text)) {
      hits.push({ rule: 'vague_prompt', reason, confidence });
    }
  }

  // Rule 3: Fan-out threshold
  if (sessionAgentCount >= AGENTGUARD_FANOUT_MAX) {
    hits.push({
      rule: 'fanout_threshold',
      reason: `Session already spawned ${sessionAgentCount} agents (threshold: ${AGENTGUARD_FANOUT_MAX}) — consider serializing or using native tools`,
      confidence: 'medium',
    });
  }

  // Rule 4: Expensive agent for trivial-looking task
  const isExpensiveAgent = EXPENSIVE_AGENT_TYPES.some(t => agentType.includes(t));
  const looksTrivial = /\b(find|read|show|get|list|count|check|search for)\b/i.test(text) && text.length < 120;
  if (isExpensiveAgent && looksTrivial) {
    hits.push({
      rule: 'expensive_agent_trivial_task',
      reason: `Expensive agent '${subagent_type}' used for apparently trivial task — consider lighter alternative`,
      confidence: 'medium',
    });
  }

  // Decision logic
  if (hits.length === 0) {
    return {
      action: 'allow',
      rationale: 'No guard rules triggered',
      metadata: { agentType, textLength: text.length, sessionAgentCount },
    };
  }

  const highConfidenceHits = hits.filter(h => h.confidence === 'high');
  const hasDeny = AGENTGUARD_DENY_CONFIDENCE && highConfidenceHits.length > 0;

  if (hasDeny) {
    return {
      action: 'deny',
      rationale: highConfidenceHits.map(h => h.reason).join('; '),
      metadata: { agentType, hits, textLength: text.length, sessionAgentCount },
    };
  }

  return {
    action: 'warn',
    rationale: hits.map(h => h.reason).join('; '),
    metadata: { agentType, hits, textLength: text.length, sessionAgentCount },
  };
}

// ═══════════════════════════════════════════════════════════════
// SKILL GUARD (Skill Invocation Inspector)
// ═══════════════════════════════════════════════════════════════

// Skills that are expensive or have high startup cost
const HIGH_COST_SKILLS = [
  'research', 'extensive_research', 'deep_investigation',
  'apify', 'brightdata', 'browser', 'interceptor',
  'remotion', 'worldthreatmodel', 'council', 'redteam',
];

// Skills with very specific domains — easy to misfire
const HIGH_SPECIFICITY_SKILLS = [
  { name: 'arxiv', keywords: ['paper', 'research', 'academic', 'arxiv', 'citation', 'journal'] },
  { name: 'apify', keywords: ['scrape', 'scraping', 'instagram', 'linkedin', 'tiktok', 'social media', 'platform'] },
  { name: 'brightdata', keywords: ['scrape', 'crawl', 'bot', 'capcha', 'residential proxy'] },
  { name: 'remotion', keywords: ['video', 'animation', 'mp4', 'motion', 'render'] },
  { name: 'audioeditor', keywords: ['audio', 'podcast', 'transcribe', 'wav', 'mp3', 'cleanup'] },
  { name: 'usmetrics', keywords: ['gdp', 'inflation', 'fred', 'economy', 'unemployment', 'treasury'] },
  { name: 'privateinvestigator', keywords: ['find person', 'people search', 'background check', 'reverse lookup'] },
  { name: 'sales', keywords: ['pitch', 'sales deck', 'proposal', 'value proposition'] },
  { name: 'writestory', keywords: ['fiction', 'novel', 'story', 'character', 'plot', 'prose'] },
];

// Patterns indicating a request is trivial enough for native tools
const TRIVIAL_REQUEST_PATTERNS = [
  { regex: /^(what time is it|what day is it|what's the date)\b/i, reason: 'Trivial time/date query — native tool or no tool needed', confidence: 'high' },
  { regex: /^(count|how many)\b.*?\b(files?|lines?|words?|directories?)\b/i, reason: 'Simple count — use bash wc/ls', confidence: 'high' },
  { regex: /^(list|show)\s+(all\s+)?(files?|dirs?|directories?)\b/i, reason: 'Simple listing — use glob or ls', confidence: 'high' },
  { regex: /^(read|show|display)\s+(the\s+)?(contents?|content)\s+(of\s+)?[a-zA-Z0-9_\-\.\/]+\b/i, reason: 'Simple read — use read tool', confidence: 'high' },
  { regex: /^(find|grep|search)\s+(for\s+)?[\"']?[a-z0-9_.\-]+\.(?:ts|js|json|md|txt|yaml|yml|py|rs|go)[\"']?\b/i, reason: 'Simple file search — use grep/glob', confidence: 'medium' },
  { regex: /^(delete|remove|rm)\s+(the\s+)?(file|directory)\b/i, reason: 'Simple delete — use bash rm', confidence: 'medium' },
];

/**
 * Inspects a skill invocation request and returns allow/warn/deny.
 *
 * Contract:
 *   Input:  { skillName, userRequest, context }
 *   Output: { action: 'allow'|'warn'|'deny', rationale, metadata }
 *
 * Philosophy: warn-first. Deny only on unambiguous misfires.
 */
export function inspectSkillInvocation({ skillName, userRequest, context = '' }) {
  const request = (userRequest || '').toLowerCase().trim();
  const skill = (skillName || '').toLowerCase().trim();
  const hits = [];

  // Rule 1: Obvious skill misfire (high-specificity skill in wrong context)
  const specificityMatch = HIGH_SPECIFICITY_SKILLS.find(s => skill.includes(s.name));
  if (specificityMatch) {
    const hasDomainKeyword = specificityMatch.keywords.some(kw => request.includes(kw.toLowerCase()));
    const hasContextKeyword = context.toLowerCase().includes(specificityMatch.name);
    if (!hasDomainKeyword && !hasContextKeyword) {
      hits.push({
        rule: 'skill_misfire',
        reason: `Skill '${skillName}' is highly specific (${specificityMatch.keywords.slice(0, 3).join(', ')}) but request context shows no matching keywords`,
        confidence: 'high',
      });
    }
  }

  // Rule 2: Trivial request — should use native tools
  for (const { regex, reason, confidence } of TRIVIAL_REQUEST_PATTERNS) {
    if (regex.test(request)) {
      hits.push({ rule: 'trivial_request', reason, confidence });
    }
  }

  // Rule 3: High-cost skill on trivial-looking request
  const isHighCost = HIGH_COST_SKILLS.some(hc => skill.includes(hc));
  const isShortRequest = request.length < 80;
  const hasSimpleVerb = /\b(find|read|show|get|list|count|check|search|grep|where)\b/i.test(request);
  if (isHighCost && isShortRequest && hasSimpleVerb) {
    hits.push({
      rule: 'high_cost_trivial',
      reason: `High-cost skill '${skillName}' invoked for short/simple request — consider native tool`,
      confidence: 'medium',
    });
  }

  // Decision logic
  if (hits.length === 0) {
    return {
      action: 'allow',
      rationale: 'No guard rules triggered',
      metadata: { skill, requestLength: request.length },
    };
  }

  const highConfidenceHits = hits.filter(h => h.confidence === 'high');

  // Deny only on unambiguous misfires with high confidence
  if (highConfidenceHits.some(h => h.rule === 'skill_misfire')) {
    return {
      action: 'deny',
      rationale: highConfidenceHits.map(h => h.reason).join('; '),
      metadata: { skill, hits, requestLength: request.length },
    };
  }

  return {
    action: 'warn',
    rationale: hits.map(h => h.reason).join('; '),
    metadata: { skill, hits, requestLength: request.length },
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
    await fetch('http://localhost:31337/notify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message,
        voice_enabled: options.voice_enabled || false,
        voice_id: options.voice_id || process.env.ELEVENLABS_VOICE_ID,
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
  inspectEgress,
  inspectPrompt,
  inspectContent,
  inspectAgentSpawn,
  inspectSkillInvocation,
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
};
