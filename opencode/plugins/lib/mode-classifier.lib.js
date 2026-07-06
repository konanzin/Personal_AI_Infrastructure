/**
 * PAI Mode/Tier Classifier (mode-classifier.lib.js)
 *
 * Provider-agnostic prompt classification subsystem for the PAI → OpenCode port.
 * Restores explicit mode/tier selection as a first-class subsystem instead of
 * relying entirely on model-native self-selection from injected system context.
 *
 * Architecture:
 *   - Layer 1: LLM classifier via the local OpenCode CLI/model selector
 *   - Layer 2: Deterministic heuristic path only when LLM is explicitly disabled
 *   - Fail-safe: ALGORITHM E3 when the LLM classifier errors/timeouts
 *
 * Output contract:
 *   { mode: 'MINIMAL' | 'NATIVE' | 'ALGORITHM',
 *     tier: 'E1' | 'E2' | 'E3' | 'E4' | 'E5' | null,
 *     reason: string,
 *     source: 'heuristic' | 'override' | 'fail-safe' | 'llm' }
 *
 * @version 1.0.0
 */

import { existsSync } from 'fs';

const PAI_DEBUG_UI = process.env.PAI_DEBUG_UI === 'true';
const console = PAI_DEBUG_UI
  ? globalThis.console
  : {
      log() {},
      warn() {},
      error() {},
    };

// ═══════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════

const OVERRIDE_PATTERN = /\/(e[1-5])\b/i;
// The registered /e1–/e5 slash-commands expand to "Run PAI effort EN for: …"
// (opencode.jsonc.template), so the literal /eN never reaches the classifier on
// that path. Both spellings are the Principal's explicit tier order and bind.
const EXPANDED_OVERRIDE_PATTERN = /\bRun PAI effort (e[1-5])\b/i;

const MINIMAL_PATTERNS = [
  { pattern: /^(hi|hello|hey|ola|oi)\b/i, reason: 'Greeting' },
  { pattern: /^(ok|okay|thanks?|thx|bye|goodbye)\b/i, reason: 'Acknowledgment' },
  { pattern: /^(valeu|obrigad[oa]|brigad[ao]|beleza|blz|show|perfeito|ótimo|otimo|massa)[!. ]*$/i, reason: 'Acknowledgment' },
  { pattern: /^(valeu|obrigad[oa]|brigad[ao]),?\s+(ficou|est[aá]|foi)\s+(bom|boa|ótimo|otimo|excelente|perfeito)[!. ]*$/i, reason: 'Acknowledgment' },
  { pattern: /^\/?rate\s+\d/i, reason: 'Explicit rating' },
  { pattern: /^\d+\s*\/\s*10$/i, reason: 'Bare rating' },
  { pattern: /^\/?status\b/i, reason: 'Status check command' },
];

const NATIVE_PATTERNS = [
  { pattern: /^(what|who|when|where|why|how|is|are|does|can|will)\s+/i, reason: 'Single fact lookup' },
  { pattern: /^(qual|quais|quem|quando|onde|por que|porque|como|o que|quanto|quantos|quantas)\s+/i, reason: 'Single fact lookup' },
  { pattern: /^(find|search|lookup|show|list|get|tell me)\s+/i, reason: 'Information retrieval' },
  { pattern: /^(ache|busque|procure|mostre|liste|diga|me diga|conte|responda)\s+/i, reason: 'Information retrieval' },
  { pattern: /^(run|execute|run the command|what does this command do)\b/i, reason: 'Single command query' },
  { pattern: /^(rode|execute|rode o comando|o que esse comando faz)\b/i, reason: 'Single command query' },
  { pattern: /^(cat|ls|pwd|echo|grep|head|tail)\s+/i, reason: 'Simple command explanation' },
  { pattern: /^(explain|define|describe)\s+\S+$/i, reason: 'Single concept explanation' },
  { pattern: /^(explique|defina|descreva)\s+\S+$/i, reason: 'Single concept explanation' },
  { pattern: /^where is\s+/i, reason: 'Location lookup' },
  { pattern: /^onde (est[aá]|fica)\s+/i, reason: 'Location lookup' },
  { pattern: /^(what is|what's)\s+\S+\?*$/i, reason: 'Single definition' },
  { pattern: /^(o que [eé]|qual [eé])\s+\S+\?*$/i, reason: 'Single definition' },
];

const ALGORITHM_INDICATORS = [
  { pattern: /\b(implement|build|create|write|develop|refactor|migrate|fix|debug|solve)\b.*\b(file|files|module|component|function|class|test|script|api|endpoint|route|schema|migration|database)\b/i, reason: 'Implementation work' },
  { pattern: /\b(implemente|implementar|construa|construir|crie|criar|escreva|escrever|desenvolva|desenvolver|refatore|refatorar|migre|migrar|corrija|corrigir|debuge|debugar|resolva|resolver)\b.*\b(arquivo|arquivos|m[oó]dulo|componente|fun[cç][aã]o|classe|teste|script|api|endpoint|rota|schema|migra[cç][aã]o|banco de dados)\b/i, reason: 'Implementation work' },
  { pattern: /\b(refactor|rewrite|restructure|reorganize|redesign|extract|split|merge|rename|move)\b/i, reason: 'Refactoring' },
  { pattern: /\b(refatore|refatorar|reescreva|reescrever|reestruture|reestruturar|reorganize|reorganizar|redesenhe|redesenhar|extraia|extrair|separe|separar|divida|dividir|mescle|mesclar|renomeie|renomear|mova|mover)\b/i, reason: 'Refactoring' },
  { pattern: /\b(multi-step|multi-file|multiple files|architecture|design|pattern|framework|system|subsystem|pipeline|workflow)\b/i, reason: 'Architecture/design' },
  { pattern: /\b(multi-etapa|v[aá]rias etapas|m[uú]ltiplos arquivos|m[uú]ltiplas? arquivos|arquitetura|arquitetural|projete|projetar|desenhe|desenhar|padr[aã]o|framework|sistema|subsistema|pipeline|workflow)\b/i, reason: 'Architecture/design' },
  { pattern: /\b(add|implement|support|feature|integration|endpoint|handler|middleware|service|repository|controller|component)\b.*\b(new|new feature|to the|into|for)\b/i, reason: 'Feature addition' },
  { pattern: /\b(adicione|adicionar|implemente|implementar|suporte|feature|integra[cç][aã]o|endpoint|handler|middleware|servi[cç]o|reposit[oó]rio|controller|componente)\b.*\b(novo|nova|para|no|na|em)\b/i, reason: 'Feature addition' },
  { pattern: /\b(plan|design|strategy|approach|structure|organize|arrange)\b/i, reason: 'Planning/design' },
  { pattern: /\b(plano|planeje|planejar|estrat[eé]gia|abordagem|estruture|estruturar|organize|organizar)\b/i, reason: 'Planning/design' },
  { pattern: /\b(bug|error|issue|problem|broken|failing|crash|exception|regression|fix|repair|resolve)\b/i, reason: 'Debugging/repair' },
  { pattern: /\b(erro|problema|quebrado|falhando|crash|exce[cç][aã]o|regress[aã]o|corrigir|consertar|resolver)\b/i, reason: 'Debugging/repair' },
  { pattern: /\b(test|testing|spec|jest|vitest|mocha|cypress|playwright|e2e|unit test|integration test)\b/i, reason: 'Testing work' },
  { pattern: /\b(docker|kubernetes|k8s|deploy|ci\/cd|pipeline|infrastructure|terraform|ansible|provision)\b/i, reason: 'DevOps/infrastructure' },
  { pattern: /\b(performance|optimize|speed|latency|memory|cpu|bottleneck|slow|cache|benchmark|profile)\b/i, reason: 'Performance optimization' },
  { pattern: /\b(security|vulnerability|auth|authentication|authorization|encrypt|sanitize|xss|csrf|sql injection)\b/i, reason: 'Security work' },
  { pattern: /\b(seguran[cç]a|vulnerabilidade|autentica[cç][aã]o|autoriza[cç][aã]o|criptograf|sanitiz|inje[cç][aã]o sql|threat model|modelo de amea[cç]as|vetores de ataque|mitiga[cç][oõ]es)\b/i, reason: 'Security work' },
  { pattern: /\b(pai|algorithm|ideal state|isa|isc|telos|mission|goal|strategy|wisdom|belief|framework)\b/i, reason: 'PAI-affecting work' },
  { pattern: /\b(update|upgrade|migrate|version|dependency|package|npm|pip|cargo|gem|composer)\b/i, reason: 'Migration/upgrade' },
  { pattern: /\b(atualize|atualizar|upgrade|migra[cç][aã]o|migrar|vers[aã]o|depend[eê]ncia|pacote)\b/i, reason: 'Migration/upgrade' },
  { pattern: /\b(documentation|readme|doc|changelog|guide|tutorial|example|diagram|flowchart)\b/i, reason: 'Documentation' },
  { pattern: /^(Quero que você|Please implement|Can you implement|Implement|Build|Create|Add|Fix|Refactor|Write|Develop)\s+/i, reason: 'Explicit implementation request' },
  { pattern: /^(Quero que voc[eê]|Implemente|Construa|Crie|Adicione|Corrija|Refatore|Escreva|Desenvolva)\s+/i, reason: 'Explicit implementation request' },
  { pattern: /\b(compare|evaluate|assess|audit|review|analyze|investigate|research|study)\b.*\b(multiple|several|various|across|between|among)\b/i, reason: 'Multi-target analysis' },
  { pattern: /\b(compare|avalie|audite|revise|analise|investigue|pesquise|estude)\b.*\b(m[uú]ltipl[oa]s|v[aá]ri[oa]s|divers[oa]s|entre|atrav[eé]s|ao longo)\b/i, reason: 'Multi-target analysis' },
  { pattern: /\b(integrate|connect|hook|wire|plugin|adapter|bridge|wrapper|client|sdk|api)\b/i, reason: 'Integration work' },
  { pattern: /\b(integre|integrar|conecte|conectar|hook|plugin|adaptador|ponte|wrapper|cliente|sdk|api)\b/i, reason: 'Integration work' },
];

const TIER_INDICATORS = {
  E1: [
    { pattern: /\b(single|one|tiny|small|quick|fast|simple|minor|tweak|adjust|fix typo|rename|add comment|one line)\b/i, weight: 1 },
  ],
  E2: [
    { pattern: /\b(one file|single file|single module|single component|single function|one feature)\b/i, weight: 1 },
    { pattern: /\b(add|implement|create|write)\b.*\b(one|single|a|an)\b.*\b(function|method|class|component|test|utility|helper)\b/i, weight: 1 },
  ],
  E4: [
    { pattern: /\b(cross.cutting|doctrine|principle|constitutional|fundamental|core|central|critical|foundational)\b/i, weight: 1 },
    { pattern: /\b(rewrite|rebuild|restructure|redesign|rearchitect|overhaul|revamp|transform)\b.*\b(entire|whole|full|complete|system|app|application|platform|framework)\b/i, weight: 2 },
    { pattern: /\b(algorithm|system upgrade|framework upgrade|major version|breaking change|deprecat)\b/i, weight: 1 },
  ],
  E5: [
    { pattern: /\b(comprehensive|complete|full|end.to.end|enterprise|production|scale|scalable|multi.team|multi.project)\b/i, weight: 1 },
    { pattern: /\b(rewrite|rebuild|restructure|redesign|rearchitect|overhaul|revamp|transform)\b.*\b(platform|ecosystem|infrastructure|architecture|system|organization|company)\b/i, weight: 2 },
    { pattern: /\b(roadmap|multi.month|quarter|year|long.term|strategic|vision|mission)\b/i, weight: 1 },
  ],
};

// Word-count thresholds for tier estimation
const WORD_COUNT_THRESHOLDS = {
  E1: { max: 15 },
  E2: { max: 50 },
  E3: { min: 20, max: 150 },
  E4: { min: 50 },
  E5: { min: 100 },
};

// ═══════════════════════════════════════════════════════════════
// HEURISTIC CLASSIFIER
// ═══════════════════════════════════════════════════════════════

// Exported: pai-hooks.js must resolve the Principal's explicit /eN
// deterministically BEFORE the meta-command bypass and the LLM classifier —
// neither may outrank the one binding tier signal (Algorithm v6.3.3).
export function checkOverride(prompt) {
  const match = prompt.match(OVERRIDE_PATTERN) || prompt.match(EXPANDED_OVERRIDE_PATTERN);
  if (match) {
    const tier = match[1].toUpperCase();
    return {
      mode: 'ALGORITHM',
      tier,
      reason: `Explicit /${tier.toLowerCase()} override detected`,
      source: 'override',
      confidence: 1.0,
    };
  }
  return null;
}

function checkMinimal(prompt) {
  const trimmed = prompt.trim();
  if (trimmed.length <= 3) {
    return { mode: 'MINIMAL', reason: 'Very short prompt (≤3 chars)', confidence: 0.95 };
  }
  if (/^\d+$/.test(trimmed)) {
    return { mode: 'MINIMAL', reason: 'Bare number (likely rating)', confidence: 0.9 };
  }
  for (const { pattern, reason } of MINIMAL_PATTERNS) {
    if (pattern.test(trimmed)) {
      return { mode: 'MINIMAL', reason, confidence: 0.9 };
    }
  }
  return null;
}

// PAI meta/config slash-command invocations expand into multi-step-looking
// templates (e.g. /classifier → "discover models, ask, write config") that the
// classifier would otherwise escalate to ALGORITHM, running the full 7-phase
// Algorithm for a trivial config/status task. These are explicit user intents,
// so treat them as NATIVE and skip the LLM classifier entirely (bypass).
// Each pattern anchors to the exact HEAD of one command template in
// opencode.jsonc.template (W2.10): an unanchored prose substring captures other
// commands that merely mention the phrase — the /interview template ends with
// "prompt-classifier model" and was force-routed NATIVE by the old /classifier
// signature, against this comment's own exclusion list. Rewording a template
// head must update its anchor (tests/mode-classifier.test.ts reads the real
// templates and fails on drift). Excludes /pai, /interview, /e1–/e5 which
// legitimately want the Algorithm; an explicit /eN outranks this bypass.
const PAI_META_COMMAND_SIGNATURES = [
  { pattern: /^Set or update the prompt-classifier model\b/i, reason: 'PAI /classifier command (config task → NATIVE)' },
  { pattern: /^Report PAI system status\b/i, reason: 'PAI /status command (→ NATIVE)' },
  { pattern: /^Inspect Pulse scaffolding\b/i, reason: 'PAI /pulse command (→ NATIVE)' },
  { pattern: /^Check PAI Pulse status and metrics\b/i, reason: 'PAI /pu command (→ NATIVE)' },
  { pattern: /^Manage the PAI desktop voice\b/i, reason: 'PAI /voice command (→ NATIVE)' },
  { pattern: /^Search PAI context for:/i, reason: 'PAI /context command (→ NATIVE)' },
  { pattern: /^Perform a 2-phase PAI context search\b/i, reason: 'PAI /context-search|/cs command (→ NATIVE)' },
];

export function classifyPaiMetaCommand(prompt) {
  if (!prompt || typeof prompt !== 'string') return null;
  // Slash-command expansion delivers the template verbatim as the message
  // head; tolerate leading whitespace only, never a mid-prompt mention.
  const head = prompt.replace(/^\s+/, '');
  for (const { pattern, reason } of PAI_META_COMMAND_SIGNATURES) {
    if (pattern.test(head)) {
      return { mode: 'NATIVE', tier: null, reason, source: 'command', confidence: 0.95 };
    }
  }
  return null;
}

function hasObviousWorkRequest(prompt) {
  return /\b(implement|build|create|write|develop|refactor|migrate|fix|debug|solve|add|update|upgrade|delete|remove|edit|modify|change|implemente|implementar|construa|construir|crie|criar|escreva|escrever|desenvolva|desenvolver|refatore|refatorar|migre|migrar|corrija|corrigir|adicione|adicionar|atualize|atualizar|delete|deletar|remova|remover|edite|editar|modifique|modificar|altere|alterar)\b/i.test(prompt);
}

function checkContextRecall(prompt) {
  const trimmed = prompt.trim();
  if (hasObviousWorkRequest(trimmed)) return null;

  const asksFromContext = /\b(sem usar ferramentas|sem ler arquivos|contexto inicial|contexto atual|j[aá] tem no contexto|j[aá] sabe|lembra|lembre|recorde)\b/i.test(trimmed);
  const contextSubject = /\b(da|identidade|telos|principal|prefer[eê]ncias?|marcadores?|sentinels?|ctx-[a-z0-9-]+|codinome|nome)\b/i.test(trimmed);
  if (asksFromContext && contextSubject) {
    return { mode: 'NATIVE', reason: 'Context recall without tool use', confidence: 0.9 };
  }

  if (/^\s*(sem usar ferramentas|sem ler arquivos):?\s*(qual|quais|quem|quando|onde|como|o que|diga|cite|responda)\b/i.test(trimmed)) {
    return { mode: 'NATIVE', reason: 'Context-only answer requested', confidence: 0.9 };
  }

  return null;
}

function checkSimpleToolRequest(prompt) {
  const trimmed = prompt.trim();
  if (hasObviousWorkRequest(trimmed)) return null;

  if (/\b(rode|execute|use)\s+um\s+comando\b.*\b(contar|conte|quantos|quantas|listar|liste|diga|responda)\b/i.test(trimmed)) {
    return { mode: 'NATIVE', reason: 'Single command request', confidence: 0.88 };
  }

  if (/\bquantos?\s+arquivos?\b.*\b(comando|shell|contar|conte|rode|execute)\b/i.test(trimmed)) {
    return { mode: 'NATIVE', reason: 'Single command request', confidence: 0.88 };
  }

  if (/\b(run|execute|use)\s+a\s+(single\s+)?(shell\s+)?command\b.*\b(count|list|find|show|tell)\b/i.test(trimmed)) {
    return { mode: 'NATIVE', reason: 'Single command request', confidence: 0.88 };
  }

  return null;
}

function checkNative(prompt) {
  const trimmed = prompt.trim();

  const contextRecall = checkContextRecall(trimmed);
  if (contextRecall) return contextRecall;

  const simpleTool = checkSimpleToolRequest(trimmed);
  if (simpleTool) return simpleTool;

  if (hasObviousWorkRequest(trimmed)) return null;

  // If it's a question but very short, it's native
  if (trimmed.length < 80) {
    for (const { pattern, reason } of NATIVE_PATTERNS) {
      if (pattern.test(trimmed)) {
        return { mode: 'NATIVE', reason, confidence: 0.85 };
      }
    }
  }
  // Single command or code snippet explanation
  if (/^`[^`]+`\??$/.test(trimmed)) {
    return { mode: 'NATIVE', reason: 'Single backtick command query', confidence: 0.85 };
  }
  return null;
}

function checkAlgorithm(prompt) {
  const trimmed = prompt.trim().toLowerCase();
  let score = 0;
  let reasons = [];

  for (const { pattern, reason } of ALGORITHM_INDICATORS) {
    if (pattern.test(trimmed)) {
      score += 1;
      if (reasons.length < 3) reasons.push(reason);
    }
  }

  // High word count strongly suggests algorithm
  const wordCount = trimmed.split(/\s+/).length;
  if (wordCount > 80) {
    score += 1;
    if (reasons.length < 3) reasons.push('Long prompt (>80 words)');
  }
  if (wordCount > 200) {
    score += 2;
    if (reasons.length < 3) reasons.push('Very long prompt (>200 words)');
  }

  // Multiple sentences often mean multi-step
  const sentenceCount = trimmed.split(/[.!?]+/).filter(s => s.trim().length > 3).length;
  if (sentenceCount > 3) {
    score += 1;
    if (reasons.length < 3) reasons.push('Multiple sentences');
  }

  // Presence of numbered lists or bullet points
  if (/^(\d+[.)]|[-*] )\s+/m.test(trimmed)) {
    score += 1;
    if (reasons.length < 3) reasons.push('Contains numbered/bulleted list');
  }

  if (score >= 1) {
    return {
      mode: 'ALGORITHM',
      reason: reasons.join('; ') || 'Multiple algorithm indicators matched',
      confidence: Math.min(0.5 + score * 0.15, 0.95),
    };
  }

  return null;
}

function estimateTier(prompt, confidence) {
  const trimmed = prompt.trim().toLowerCase();
  const wordCount = trimmed.split(/\s+/).length;

  // Score each tier
  const scores = { E1: 0, E2: 0, E3: 0, E4: 0, E5: 0 };

  for (const [tier, indicators] of Object.entries(TIER_INDICATORS)) {
    for (const { pattern, weight } of indicators) {
      if (pattern.test(trimmed)) {
        scores[tier] += weight;
      }
    }
  }

  // Word count heuristics
  if (wordCount <= WORD_COUNT_THRESHOLDS.E1.max) scores.E1 += 1;
  if (wordCount <= WORD_COUNT_THRESHOLDS.E2.max && wordCount >= 10) scores.E2 += 1;
  if (wordCount >= WORD_COUNT_THRESHOLDS.E3.min && wordCount <= WORD_COUNT_THRESHOLDS.E3.max) scores.E3 += 1;
  if (wordCount >= WORD_COUNT_THRESHOLDS.E4.min) scores.E4 += 1;
  if (wordCount >= WORD_COUNT_THRESHOLDS.E5.min) scores.E5 += 1;

  // Complexity indicators
  const codeBlockCount = (trimmed.match(/```/g) || []).length / 2;
  if (codeBlockCount >= 2) scores.E3 += 1;
  if (codeBlockCount >= 4) scores.E4 += 1;

  const fileRefCount = (trimmed.match(/\b\w+\.(js|ts|jsx|tsx|py|go|rs|java|cpp|c|h|md|json|yaml|yml|toml)\b/gi) || []).length;
  if (fileRefCount >= 3) scores.E3 += 1;
  if (fileRefCount >= 6) scores.E4 += 1;

  // ALGORITHM indicator count influences tier
  // More complex indicators → higher tier
  let algorithmScore = 0;
  for (const { pattern } of ALGORITHM_INDICATORS) {
    if (pattern.test(trimmed)) {
      algorithmScore += 1;
    }
  }
  if (algorithmScore >= 3) scores.E3 += 1;
  if (algorithmScore >= 5) scores.E4 += 1;

  // Specific high-signal keywords that strongly suggest higher tiers
  if (/\b(refactor|rewrite|restructure|redesign|rearchitect|migrate|upgrade)\b.*\b(multiple|many|several|all|entire|complete|whole|system|module|modules|file|files|component|components)\b/i.test(trimmed)) {
    scores.E3 += 2;
  }

  // Find highest-scoring tier
  let bestTier = 'E3'; // Default fail-safe
  let bestScore = scores.E3;

  for (const tier of ['E5', 'E4', 'E3', 'E2', 'E1']) {
    if (scores[tier] > bestScore) {
      bestScore = scores[tier];
      bestTier = tier;
    }
  }

  // If confidence is low and tier is E1/E2, bump to E3 (fail-safe: under-escalation is worse)
  if (confidence < 0.7 && (bestTier === 'E1' || bestTier === 'E2')) {
    return 'E3';
  }

  return bestTier;
}

// ═══════════════════════════════════════════════════════════════
// PUBLIC API
// ═══════════════════════════════════════════════════════════════

/**
 * Classify a user prompt into MODE and TIER.
 *
 * @param {string} prompt - Raw user prompt text
 * @param {object} options - Optional configuration
 * @param {string} options.defaultModel - Reserved for caller-specific classifier model selection
 * @param {string} options.fallbackModel - Reserved for caller-specific fallback model selection
 * @param {boolean} options.useLLM - Whether to use the optional external LLM classifier
 * @returns {object} Classification result with mode, tier, reason, source
 */
export function classifyPrompt(prompt, options = {}) {
  if (!prompt || typeof prompt !== 'string') {
    return {
      mode: 'ALGORITHM',
      tier: 'E3',
      reason: 'Invalid or empty prompt — fail-safe to ALGORITHM E3',
      source: 'fail-safe',
      confidence: 1.0,
      latencyMs: 0,
    };
  }

  const startTime = performance.now();

  // Layer 0: Explicit override (/e1–/e5, literal or expanded slash-command
  // template). Checked before the meta-command bypass: the Principal's /eN is
  // the one binding tier signal (v6.3.3) and outranks every routing heuristic.
  const override = checkOverride(prompt);
  if (override) {
    return {
      ...override,
      latencyMs: Math.round(performance.now() - startTime),
    };
  }

  // Layer 0a: PAI meta/config command → NATIVE (never escalate a config task)
  const metaCommand = classifyPaiMetaCommand(prompt);
  if (metaCommand) {
    return { ...metaCommand, latencyMs: Math.round(performance.now() - startTime) };
  }

  // Layer 1: Deterministic heuristic
  const minimal = checkMinimal(prompt);
  if (minimal) {
    return {
      mode: 'MINIMAL',
      tier: null,
      reason: minimal.reason,
      source: 'heuristic',
      confidence: minimal.confidence,
      latencyMs: Math.round(performance.now() - startTime),
    };
  }

  const native = checkNative(prompt);
  if (native) {
    return {
      mode: 'NATIVE',
      tier: null,
      reason: native.reason,
      source: 'heuristic',
      confidence: native.confidence,
      latencyMs: Math.round(performance.now() - startTime),
    };
  }

  const algorithm = checkAlgorithm(prompt);
  if (algorithm) {
    const tier = estimateTier(prompt, algorithm.confidence);
    return {
      mode: 'ALGORITHM',
      tier,
      reason: algorithm.reason,
      source: 'heuristic',
      confidence: algorithm.confidence,
      latencyMs: Math.round(performance.now() - startTime),
    };
  }

  // Fail-safe: when no clear signal, prefer ALGORITHM E3
  // Under-escalation is worse than over-escalation in PAI doctrine
  return {
    mode: 'ALGORITHM',
    tier: 'E3',
    reason: 'No strong heuristic signal — fail-safe to ALGORITHM E3',
    source: 'fail-safe',
    confidence: 0.5,
    latencyMs: Math.round(performance.now() - startTime),
  };
}

// ═══════════════════════════════════════════════════════════════
// LLM CLASSIFIER
// ═══════════════════════════════════════════════════════════════

// Simple LRU cache for classification results
const classificationCache = new Map();
const CACHE_MAX_SIZE = 100;
const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

function getCached(prompt) {
  const entry = classificationCache.get(prompt);
  if (!entry) return null;
  if (Date.now() - entry.ts > CACHE_TTL_MS) {
    classificationCache.delete(prompt);
    return null;
  }
  return entry.result;
}

function setCached(prompt, result) {
  if (classificationCache.size >= CACHE_MAX_SIZE) {
    const firstKey = classificationCache.keys().next().value;
    classificationCache.delete(firstKey);
  }
  classificationCache.set(prompt, { result, ts: Date.now() });
}

/**
 * Auto-discover available LLM API endpoint.
 * Tries common endpoints and returns the first that responds.
 */
async function discoverEndpoint() {
  const candidates = [
    // OpenCode API (if/when available)
    { url: 'https://api.opencode.ai/v1', auth: null },
    // OpenAI API (if user has key)
    { url: 'https://api.openai.com/v1', auth: process.env.OPENAI_API_KEY },
    // Custom from env
    ...(process.env.PAI_CLASSIFIER_API_URL ? [{ url: process.env.PAI_CLASSIFIER_API_URL, auth: process.env.PAI_CLASSIFIER_API_KEY }] : []),
  ];

  for (const { url, auth } of candidates) {
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 2000);
      const res = await fetch(`${url}/models`, {
        signal: controller.signal,
        ...(auth ? { headers: { 'Authorization': `Bearer ${auth}` } } : {}),
      });
      clearTimeout(timeout);
      if (res.ok || res.status === 401) { // 401 means endpoint exists but needs auth
        return { url, auth };
      }
    } catch {
      // Continue to next candidate
    }
  }

  return null;
}

/**
 * Build the classification prompt for the LLM.
 * Exported so the golden-eval leakage fence can assert its few-shot examples
 * stay disjoint from the golden set (classifier-golden.test.ts).
 */
export function buildClassificationPrompt(userPrompt) {
  return `You are a prompt classifier for PAI (Personal AI Infrastructure). Your job is to classify user prompts into mode and tier.

## Classification Rules

**MODE:**
- MINIMAL — greetings, thanks, ratings, single-token acknowledgments, very short (<=3 chars), bare numbers (likely ratings)
- NATIVE — ONE fully-specified step: run a given command, make one mechanical edit (rename a file, fix a named typo, bump a version, add/remove one line), answer a single fact or short question. The decisive test: the prompt already says exactly WHAT and WHERE — nothing needs to be discovered or decided. Imperative verbs like "fix", "rename", "run", "add" do NOT make a prompt ALGORITHM when the change is fully specified.
- ALGORITHM — work that needs investigation, design decisions, multiple coordinated steps, or where the scope/location of the change must be discovered (debugging, refactoring, architecture, building features, audits, migrations).

**TIER (ALGORITHM only):**
- E1 — trivial, <90 seconds, single tiny change
- E2 — single-domain, ~3 minutes, one file/module/component, single feature addition
- E3 — multi-file substantial, ~10 minutes, refactoring across files, bug fixes, feature implementation
- E4 — cross-cutting/doctrine, ~30 minutes, system-wide changes, breaking changes, major refactoring
- E5 — comprehensive, >2 hours, platform/ecosystem level, complete rewrite, strategic architecture

**Overrides:** If the prompt contains "/e1" through "/e5", the tier is forced to that value.
**When uncertain between NATIVE and ALGORITHM, prefer NATIVE** — over-ceremony on a trivial fully-specified prompt is a guaranteed time tax. But vagueness IS a signal: an imperative whose scope or cause must be discovered ("fix the bug", "make it faster") is ALGORITHM, not NATIVE. When uncertain between adjacent tiers, pick the lower.

## Examples
<!-- NOTE: keep these DISJOINT from plugins/lib/classifier-golden.lib.js — the
     golden eval grades the classifier and must never contain strings the
     classifier was shown in its own instructions (train/test leakage). -->
- "delete the print statement on line 12 of app.py" → MODE: NATIVE (one fully-specified edit — nothing to discover)
- "roda npm install" → MODE: NATIVE (one given command; prompts may be in Portuguese)
- "why is checkout intermittently failing in production?" → MODE: ALGORITHM, TIER: E3 (cause must be discovered)
- "reescreve o serviço de fila para usar Redis" → MODE: ALGORITHM, TIER: E3 (multi-step design + implementation)
- "valeu!" → MODE: MINIMAL (thanks, no new work)

## Output Format
Respond with EXACTLY this format (no markdown, no extra text):

MODE: [MINIMAL|NATIVE|ALGORITHM]
TIER: [E1|E2|E3|E4|E5|null]
REASON: [one sentence explaining why]

## User Prompt to Classify
"""${userPrompt.replace(/"/g, '\"')}"""

CLASSIFICATION:`;
}

/**
 * Parse LLM response into classification object.
 */
function parseLLMResponse(text) {
  const modeMatch = text.match(/MODE:\s*(MINIMAL|NATIVE|ALGORITHM)/i);
  const tierMatch = text.match(/TIER:\s*(E[1-5]|null|none)/i);
  const reasonMatch = text.match(/REASON:\s*(.+?)(?:\n|$)/i);

  if (!modeMatch) {
    return null;
  }

  const mode = modeMatch[1].toUpperCase();
  let tier = tierMatch ? tierMatch[1].toUpperCase() : null;
  if (tier === 'NULL' || tier === 'NONE') tier = null;

  return {
    mode,
    tier: mode === 'ALGORITHM' ? tier : null,
    reason: reasonMatch ? reasonMatch[1].trim() : 'LLM classification',
    source: 'llm',
    confidence: 0.85,
  };
}

/**
 * Execute a subprocess to call opencode run with a model.
 * This uses the local opencode CLI to run the model.
 */
function resolveOpencodeBin() {
  if (process.env.OPENCODE_BIN) return process.env.OPENCODE_BIN;
  for (const candidate of ['/home/pai/.opencode/bin/opencode', '/home/pai/.local/bin/opencode']) {
    if (existsSync(candidate)) return candidate;
  }
  return 'opencode';
}

// Exported for on-demand evals (bin/eval-escalation-golden.js) that need the
// same raw `opencode run --pure` path production classification uses.
export async function execOpencodeRun(model, message, timeoutMs = 25000) {
  const bin = resolveOpencodeBin();
  const proc = Bun.spawn({
    cmd: [bin, 'run', '--pure', '--model', model, message],
    stdout: 'pipe',
    stderr: 'pipe',
    env: {
      ...process.env,
      OPENCODE: '1',
      PAI_CLASSIFIER_INTERNAL: 'true',
      PAI_CLASSIFIER_USE_LLM: 'false',
    },
  });

  // Set up timeout
  const timeout = setTimeout(() => {
    proc.kill();
  }, timeoutMs);

  try {
    const stdout = await new Response(proc.stdout).text();
    const stderr = await new Response(proc.stderr).text();
    const exitCode = await proc.exited;
    clearTimeout(timeout);

    if (exitCode !== 0) {
      throw new Error(`opencode run exited with code ${exitCode}: ${stderr}`);
    }

    return stdout;
  } catch (err) {
    clearTimeout(timeout);
    proc.kill();
    throw err;
  }
}

/**
 * Classify using an LLM via opencode run.
 * 
 * Uses `opencode run --pure --model <model> <prompt>` to get classification.
 * Matches original PAI failure semantics by fail-safing to ALGORITHM E3 on
 * error/timeout, unless providerConfig.fallback === 'heuristic' is explicitly
 * set for offline/debug use.
 * 
 * @param {string} prompt - Raw user prompt text
 * @param {object} providerConfig - Optional: { model, timeoutMs }
 * @returns {Promise<object>} Classification result
 */
export async function classifyPromptWithLLM(prompt, providerConfig = null) {
  // Check cache first. `noCache` bypasses both read and write — the cache is a
  // production latency optimization; evals with repeated runs of the same prompt
  // (bin/eval-classifier-golden.js --runs N) would otherwise replay run 1 N times.
  const noCache = providerConfig?.noCache === true;
  const cached = noCache ? null : getCached(prompt);
  if (cached) {
    return { ...cached, latencyMs: 0 };
  }

  // Start timing
  const startTime = performance.now();

  // If no provider config or LLM not explicitly enabled, fall back to heuristic
  if (!providerConfig) {
    const result = classifyPrompt(prompt);
    return { ...result, source: 'heuristic' };
  }

  const {
    model = 'opencode/deepseek-v4-flash-free',
    timeoutMs = 25000,
    fallback = process.env.PAI_CLASSIFIER_FALLBACK || 'fail-safe',
  } = providerConfig;

  // Build the classification prompt
  const classificationPrompt = buildClassificationPrompt(prompt);

  try {
    // Run opencode with the model
    const stdout = await execOpencodeRun(model, classificationPrompt, timeoutMs);

    // Parse the response - look for the CLASSIFICATION output
    const lines = stdout.split('\n');
    let classificationText = '';
    let inClassification = false;

    for (const line of lines) {
      if (line.includes('CLASSIFICATION:')) {
        inClassification = true;
        continue;
      }
      if (inClassification) {
        if (line.trim() === '') continue;
        classificationText += line + '\n';
        // Stop after we have 3 lines (MODE, TIER, REASON)
        if (classificationText.split('\n').filter(l => l.trim()).length >= 3) break;
      }
    }

    // If we didn't find structured output, try to parse from the whole response
    if (!classificationText) {
      classificationText = stdout;
    }

    const parsed = parseLLMResponse(classificationText);
    if (!parsed) {
      throw new Error('Could not parse LLM response');
    }

    const result = {
      ...parsed,
      latencyMs: Math.round(performance.now() - startTime),
    };

    // Cache the result
    if (!noCache) setCached(prompt, result);

    return normalizeClassification(result);
  } catch (error) {
    console.error(`[PAI Classifier] LLM error: ${error.message}.`);
    if (fallback === 'heuristic') {
      const result = classifyPrompt(prompt);
      return {
        ...result,
        reason: `${result.reason} (LLM fallback: ${error.message})`,
        source: 'heuristic',
        latencyMs: Math.round(performance.now() - startTime),
      };
    }
    return {
      mode: 'ALGORITHM',
      tier: 'E3',
      reason: `LLM classifier failed — fail-safe to ALGORITHM E3: ${error.message}`,
      source: 'fail-safe',
      confidence: 1.0,
      latencyMs: Math.round(performance.now() - startTime),
    };
  }
}

/**
 * Resolve the effective classifier config from a persistent config file and the
 * process environment. Pure (no I/O) so the precedence policy is unit-testable;
 * the caller supplies the parsed file contents and an env map.
 *
 * Precedence per field: env var (debug escape hatch) > config file (persistent
 * user choice, written by setup / mobile) > hardcoded default. A missing or
 * empty file therefore reproduces the legacy env-only behavior exactly.
 *
 * @param {object} fileData - Parsed classifier.json ({ model, useLLM, timeoutMs })
 * @param {object} env - Environment map (typically process.env)
 * @returns {{useLLM: boolean, model: string, timeoutMs: number, endpoint: ?string, apiKey: ?string}}
 */
export function resolveClassifierConfig(fileData = {}, env = {}) {
  const file = fileData && typeof fileData === 'object' && !Array.isArray(fileData) ? fileData : {};

  const envModel =
    env.PAI_CLASSIFIER_MODEL ||
    (env.PAI_OPENCODE_PROVIDER && env.PAI_OPENCODE_MODEL
      ? `${env.PAI_OPENCODE_PROVIDER}/${env.PAI_OPENCODE_MODEL}`
      : null);
  const model =
    envModel ||
    (typeof file.model === 'string' && file.model ? file.model : null) ||
    'opencode/deepseek-v4-flash-free';

  const envUseLLM = env.PAI_CLASSIFIER_USE_LLM;
  const useLLM =
    envUseLLM !== undefined && envUseLLM !== ''
      ? !/^(0|false|no|off)$/i.test(String(envUseLLM).trim())
      : typeof file.useLLM === 'boolean'
        ? file.useLLM
        : true;

  const timeoutMs = parseInt(env.PAI_CLASSIFIER_TIMEOUT_MS || file.timeoutMs || '25000', 10);

  return {
    useLLM,
    model,
    timeoutMs,
    endpoint: env.PAI_CLASSIFIER_API_URL || null,
    apiKey: env.PAI_CLASSIFIER_API_KEY || null,
  };
}

/**
 * Normalize a classification result to ensure it always has the expected shape.
 *
 * @param {object} result - Raw classification result
 * @returns {object} Normalized result
 */
export function normalizeClassification(result) {
  if (!result || typeof result !== 'object') {
    return {
      mode: 'ALGORITHM',
      tier: 'E3',
      reason: 'Normalization fail-safe — ALGORITHM E3',
      source: 'fail-safe',
      confidence: 1.0,
      latencyMs: 0,
    };
  }

  const validModes = ['MINIMAL', 'NATIVE', 'ALGORITHM'];
  const validTiers = ['E1', 'E2', 'E3', 'E4', 'E5', null];
  // 'command' = PAI meta-command bypass (a deliberate NATIVE route, NOT a failure).
  // It must be valid or classifyPaiMetaCommand results get coerced to 'fail-safe'
  // and pollute the classifier health signal with legitimate /status, /voice, etc.
  const validSources = ['heuristic', 'override', 'fail-safe', 'llm', 'command'];

  const mode = validModes.includes(result.mode) ? result.mode : 'ALGORITHM';
  const tier = validTiers.includes(result.tier) ? result.tier : 'E3';

  return {
    mode,
    tier: mode === 'ALGORITHM' ? tier : null,
    reason: typeof result.reason === 'string' && result.reason.length > 0
      ? result.reason
      : 'No reason provided',
    source: validSources.includes(result.source) ? result.source : 'fail-safe',
    confidence: typeof result.confidence === 'number' ? Math.max(0, Math.min(1, result.confidence)) : 0.5,
    latencyMs: typeof result.latencyMs === 'number' ? result.latencyMs : 0,
  };
}

/**
 * Format classification for injection into system context.
 *
 * @param {object} classification - Normalized classification result
 * @returns {string} Formatted context string
 */
export function formatClassificationContext(classification) {
  const { mode, tier, reason, source } = classification;
  const tierLine = tier ? `\n**Tier:** ${tier}` : '';

  // An explicit /eN token is the Principal's own instruction — authoritative.
  // Every other source is a pre-classifier guess; the primary model has read
  // the full prompt and owns the final mode/tier call (drift register W1.2).
  const stance = source === 'override'
    ? '> This tier was explicitly requested by the user (/eN override). Honor it.'
    : '> Suggested by the PAI Mode/Tier pre-classifier. Treat it as a starting point: adopt it when it matches your own read of the request, and override it (either direction) when it does not. Note the discrepancy when you override.';

  return `## Mode/Tier Classification (${source === 'override' ? 'user override' : 'suggestion'})
**Mode:** ${mode}${tierLine}
**Reason:** ${reason}
**Source:** ${source}

${stance}`;
}

/**
 * Check if a classification result should trigger the Algorithm.
 *
 * @param {object} classification - Normalized classification result
 * @returns {boolean}
 */
export function isAlgorithmMode(classification) {
  return classification?.mode === 'ALGORITHM';
}

/**
 * Get the effort tier string for display/logging.
 *
 * @param {object} classification - Normalized classification result
 * @returns {string}
 */
export function getEffortLabel(classification) {
  if (classification?.mode === 'MINIMAL') return 'MINIMAL';
  if (classification?.mode === 'NATIVE') return 'NATIVE';
  if (classification?.mode === 'ALGORITHM') return `ALGORITHM ${classification.tier || 'E3'}`;
  return 'UNKNOWN';
}
