/**
 * PAI Hooks Plugin for OpenCode
 * 
 * Implements 8 critical PAI hooks using OpenCode's native plugin system.
 * Ported from PAI v5.0.0 (Claude Code hooks) to native OpenCode events.
 * 
 * Hooks:
 * - F1: SecurityPipeline (tool.execute.before) — Validate bash commands and writes
 * - F2: LoadContext (session.created) — Load PAI context, check Pulse, init registry
 * - F3: SessionCleanup (session.idle) — Clean up session, update work.json, sync counts
 * - F4: ToolActivityTracker (tool.execute.after) — Log tool usage to JSONL
 * - F5: ContentScanner (tool.execute.after for web tools) — Validate web content
 * - F6: PromptGuard (message.updated) — Detect dangerous prompt patterns
 * - F7: SatisfactionCapture (session.idle) — Log rating availability
 * - F8: WorkCompletionLearning (session.idle) — Analyze patterns, write learning signals
 * 
 * @version 2.0.0
 * @license MIT
 */

import {
  existsSync, readFileSync, writeFileSync, appendFileSync, mkdirSync, readdirSync, statSync, unlinkSync,
} from 'fs';
import { join, dirname } from 'path';

import {
  PAI_DIR, MEMORY_DIR, STATE_DIR, WORK_DIR, LEARNING_DIR, OBSERVABILITY_DIR,
  ensureDir, safeReadJson, safeWriteJson, appendJsonL,
  getISOTimestamp, getPSTComponents, getPSTDate,
  getSessionId, findStateFile, truncate,
  logSecurityEvent,
  inspectBashCommand, inspectWritePath, inspectEgress,
  inspectPrompt, inspectContent,
  parseExplicitRating, isSystemText, detectPositivePraise,
  getLearningCategory,
  readWorkRegistry, writeWorkRegistry, findArtifactPath,
  emitPulseEvent, notifyPulse, gitSnapshot,
  readSessionNames, writeSessionNames,
  parseFrontmatter, writeFrontmatterField,
  getRecentWorkSessions,
} from './pai-hooks.lib.js';

// ═══════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════

const PLUGIN_VERSION = '2.0.0';
const MIN_PROMPT_LENGTH = 3;

// ═══════════════════════════════════════════════════════════════
// MAIN PLUGIN EXPORT
// ═══════════════════════════════════════════════════════════════

export const PAIHooksPlugin = async ({ project, client, $, directory, worktree }) => {
  // Ensure all required directories exist
  ensureDir(MEMORY_DIR);
  ensureDir(STATE_DIR);
  ensureDir(WORK_DIR);
  ensureDir(LEARNING_DIR);
  ensureDir(OBSERVABILITY_DIR);
  ensureDir(join(LEARNING_DIR, 'SIGNALS'));
  ensureDir(join(LEARNING_DIR, 'SYSTEM'));
  ensureDir(join(LEARNING_DIR, 'ALGORITHM'));

  // File paths
  const sessionRegistryPath = join(STATE_DIR, 'work.json');
  const toolActivityPath = join(STATE_DIR, 'tool-activity.jsonl');
  const learningPath = join(LEARNING_DIR, 'signals.jsonl');
  const ratingsPath = join(LEARNING_DIR, 'SIGNALS', 'ratings.jsonl');
  const countsPath = join(STATE_DIR, 'counts.json');
  const lastResponseCache = join(STATE_DIR, 'last-response.txt');
  const currentWorkPath = join(STATE_DIR, 'current-work.json');

  console.log(`[PAI] Plugin v${PLUGIN_VERSION} initialized`);

  return {
    // ═══════════════════════════════════════════════════════════════
    // F2: LoadContext - Load PAI context on session start
    // ═══════════════════════════════════════════════════════════════
    "session.created": async (input, output) => {
      const timestamp = getISOTimestamp();
      const sessionId = getSessionId(input);

      try {
        console.log(`[PAI] 🚀 Session started at ${timestamp}`);
        console.log(`[PAI] 📁 Project: ${project?.name || directory || 'unknown'}`);
        console.log(`[PAI] 🔑 Session ID: ${sessionId}`);

        // Initialize or update session registry (atomic read-modify-write)
        let registry = safeReadJson(sessionRegistryPath, { sessions: {}, lastSessionId: null, version: '2.0' });

        // Upsert session into work.json registry (mirrors isa-utils upsertSession)
        const timestamp_iso = new Date().toISOString();
        const now = new Date();
        const pad = (n) => n.toString().padStart(2, '0');
        const datePrefix = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}00`;
        const taskSlug = (project?.name || directory || 'session')
          .toLowerCase()
          .replace(/[^a-z0-9]+/g, '-')
          .replace(/^-|-$/g, '')
          .slice(0, 40);
        const slug = `${datePrefix}_${taskSlug}`;

        registry.sessions[slug] = {
          task: project?.name || directory || 'Native session',
          sessionName: project?.name || undefined,
          sessionUUID: sessionId,
          phase: 'native',
          progress: '0/0',
          effort: 'native',
          mode: 'native',
          started: timestamp_iso,
          updatedAt: timestamp_iso,
          currentMode: 'native',
          modeHistory: [{ mode: 'native', startedAt: Date.now() }],
          ratings: [],
          minimalCount: 0,
        };
        registry.lastSessionId = sessionId;

        // Aggressive cleanup: remove old native sessions (>2h idle)
        const TWO_HOURS = 2 * 60 * 60 * 1000;
        for (const [s, sess] of Object.entries(registry.sessions)) {
          const updatedMs = new Date(sess.updatedAt || sess.started || 0).getTime();
          if (now.getTime() - updatedMs > TWO_HOURS && sess.phase !== 'complete') {
            delete registry.sessions[s];
          }
        }

        // Cap at 50 sessions
        const entries = Object.entries(registry.sessions);
        if (entries.length > 50) {
          entries.sort((a, b) => {
            const aTime = new Date(a[1].updatedAt || a[1].started || 0).getTime();
            const bTime = new Date(b[1].updatedAt || b[1].started || 0).getTime();
            return bTime - aTime;
          });
          for (const [s] of entries.slice(50)) {
            delete registry.sessions[s];
          }
        }

        safeWriteJson(sessionRegistryPath, registry);
        console.log(`[PAI] 📝 Session registry updated (${Object.keys(registry.sessions).length} total sessions)`);

        // Write current-work.json for session tracking
        safeWriteJson(currentWorkPath, {
          session_id: sessionId,
          session_dir: slug,
          created_at: timestamp_iso,
        });

        // Check Pulse daemon connection
        try {
          const response = await fetch('http://localhost:31337/api/pulse/health', {
            signal: AbortSignal.timeout(2000),
          });
          if (response.ok) {
            console.log('[PAI] 💓 Pulse daemon connected');
          } else {
            console.log('[PAI] ⚠️ Pulse daemon returned non-OK status');
          }
        } catch (e) {
          console.log('[PAI] ⚠️ Pulse daemon not available (port 31337)');
        }

        // Load active work summary
        try {
          const sessions = getRecentWorkSessions(48);
          if (sessions.length > 0) {
            console.log(`[PAI] 📋 Active work: ${sessions.length} recent sessions`);
            for (const s of sessions.slice(0, 5)) {
              console.log(`[PAI]    ⚡ ${s.title} | ${s.timestamp} | ${s.status}`);
            }
          }
        } catch (e) {
          // Silent fail for work summary
        }

        // Load relationship context (high-confidence opinions)
        try {
          const opinionsPath = join(PAI_DIR, 'USER', 'OPINIONS.md');
          if (existsSync(opinionsPath)) {
            const content = readFileSync(opinionsPath, 'utf-8');
            const highConfidence = [];
            const opinionBlocks = content.split(/^### /gm).slice(1);

            for (const block of opinionBlocks.slice(0, 10)) {
              const lines = block.split('\n');
              const statement = lines[0]?.trim();
              const confidenceMatch = block.match(/\*\*Confidence:\*\*\s*([\d.]+)/);
              const confidence = confidenceMatch ? parseFloat(confidenceMatch[1]) : 0;

              if (confidence >= 0.85 && statement) {
                highConfidence.push(`• ${statement} (${(confidence * 100).toFixed(0)}%)`);
              }
            }

            if (highConfidence.length > 0) {
              console.log(`[PAI] 💡 ${highConfidence.length} high-confidence opinions loaded`);
            }
          }
        } catch (e) {
          // Silent fail
        }

        // Load learning context digest
        try {
          const signalsDir = join(LEARNING_DIR, 'SIGNALS');
          if (existsSync(signalsDir)) {
            const files = readdirSync(signalsDir).filter(f => f.endsWith('.jsonl'));
            let signalCount = 0;
            for (const f of files) {
              try {
                const lines = readFileSync(join(signalsDir, f), 'utf-8').trim().split('\n').filter(Boolean);
                signalCount += lines.length;
              } catch {}
            }
            if (signalCount > 0) {
              console.log(`[PAI] 📚 ${signalCount} learning signals in archive`);
            }
          }
        } catch (e) {
          // Silent fail
        }

      } catch (e) {
        console.error('[PAI] ❌ Error in LoadContext:', e.message);
      }
    },

    // ═══════════════════════════════════════════════════════════════
    // F1: SecurityPipeline - Validate commands before execution
    // ═══════════════════════════════════════════════════════════════
    "tool.execute.before": async (input, output) => {
      const tool = input.tool;
      const args = input.args || {};
      const sessionId = getSessionId(input);

      try {
        // Security checks for Bash commands
        if (tool === 'bash' && args.command) {
          const cmd = args.command;

          // Run PatternInspector
          const patternResult = inspectBashCommand(cmd);

          // Run EgressInspector
          const egressResult = inspectEgress(cmd);

          // Combine results: deny > require_approval > alert > allow
          let result = { action: 'allow', violations: [] };

          if (patternResult.action === 'deny' || egressResult.action === 'deny') {
            result = {
              action: 'deny',
              violations: [
                ...(patternResult.action === 'deny' ? patternResult.violations : []),
                ...(egressResult.action === 'deny' ? egressResult.violations : []),
              ],
            };
          } else if (patternResult.action === 'require_approval' || egressResult.action === 'require_approval') {
            result = {
              action: 'require_approval',
              violations: [
                ...(patternResult.action === 'require_approval' ? patternResult.violations : []),
                ...(egressResult.action === 'require_approval' ? egressResult.violations : []),
              ],
            };
          } else if (patternResult.action === 'alert') {
            result = patternResult;
          } else if (egressResult.action === 'alert') {
            result = egressResult;
          }

          if (result.action !== 'allow') {
            console.error(`[PAI] 🛡️ SecurityPipeline: ${result.violations.length} dangerous pattern(s) detected in bash command`);
            console.error(`[PAI] Command: ${truncate(cmd, 200)}`);

            for (const v of result.violations) {
              console.error(`[PAI]   - ${v.reason} (${v.severity || 'unknown'})`);
            }

            // Log security event
            logSecurityEvent({
              sessionId,
              tool: 'bash',
              eventType: result.action === 'deny' ? 'block' : (result.action === 'require_approval' ? 'confirm' : 'alert'),
              inspector: 'SecurityPipeline',
              target: truncate(cmd, 500),
              reason: result.violations.map(v => v.reason).join('; '),
              actionTaken: result.action === 'deny' ? 'Hard block' : (result.action === 'require_approval' ? 'Prompted for approval' : 'Alert logged'),
            });

            // Block critical violations by throwing
            if (result.action === 'deny') {
              throw new Error(`[PAI SECURITY] BLOCKED: Dangerous pattern detected in bash command: ${result.violations.map(v => v.reason).join(', ')}`);
            }
          }
        }

        // Security checks for Write/Edit operations
        if ((tool === 'write' || tool === 'edit' || tool === 'multiedit') && args.filePath) {
          const filePath = args.filePath;
          const action = tool === 'edit' || tool === 'multiedit' ? 'write' : 'write';
          const result = inspectWritePath(filePath, action);

          if (result.action !== 'allow') {
            console.error(`[PAI] 🛡️ SecurityPipeline: Write to sensitive path detected: ${filePath}`);

            for (const v of result.violations) {
              console.error(`[PAI]   - ${v.reason}`);
            }

            logSecurityEvent({
              sessionId,
              tool,
              eventType: result.action === 'deny' ? 'block' : 'confirm',
              inspector: 'SecurityPipeline',
              target: filePath,
              reason: result.violations.map(v => v.reason).join('; '),
              actionTaken: result.action === 'deny' ? 'Hard block' : 'Prompted for approval',
            });

            if (result.action === 'deny') {
              throw new Error(`[PAI SECURITY] BLOCKED: Attempted write to sensitive path: ${filePath}. ${result.violations.map(v => v.reason).join(', ')}`);
            }
          }
        }

        // Security checks for delete operations
        if ((tool === 'bash' && args.command) && /rm\s+-/.test(args.command)) {
          const result = inspectWritePath(args.command, 'delete');
          if (result.action !== 'allow') {
            logSecurityEvent({
              sessionId,
              tool: 'bash',
              eventType: 'confirm',
              inspector: 'SecurityPipeline',
              target: truncate(args.command, 500),
              reason: result.violations.map(v => v.reason).join('; '),
              actionTaken: 'Delete operation flagged for approval',
            });
          }
        }

      } catch (e) {
        // Re-throw blocking errors, log others
        if (e.message && e.message.includes('[PAI SECURITY] BLOCKED')) {
          throw e;
        }
        console.error('[PAI] ❌ SecurityPipeline error:', e.message);
      }
    },

    // ═══════════════════════════════════════════════════════════════
    // F4: ToolActivityTracker + F5: ContentScanner
    // ═══════════════════════════════════════════════════════════════
    "tool.execute.after": async (input, output) => {
      const timestamp = getISOTimestamp();
      const tool = input.tool;
      const sessionId = getSessionId(input);
      const args = input.args || {};

      try {
        // Calculate duration if startTime available
        const duration = input.startTime ? Date.now() - input.startTime : 0;

        // Capture ground truth for write and bash tools
        let groundTruth = undefined;
        if ((tool === 'write' || tool === 'edit' || tool === 'multiedit') && args.filePath) {
          const gt = { file_path: args.filePath };
          if (args.old_string && args.new_string) {
            gt.diff = {
              removed: truncate(args.old_string, 500),
              added: truncate(args.new_string, 500),
            };
          }
          if (args.content) {
            gt.content_preview = truncate(args.content, 500);
            gt.content_bytes = args.content.length;
          }
          const gs = gitSnapshot(process.cwd());
          if (gs) gt.git = gs;
          groundTruth = gt;
        }

        if (tool === 'bash' && args.command) {
          const gt = { command: truncate(args.command, 500) };
          // Try to capture exit code and output from result
          const result = output?.result;
          if (result && typeof result === 'object') {
            if (result.stdout && typeof result.stdout === 'string') {
              gt.stdout_preview = truncate(result.stdout, 800);
              gt.stdout_bytes = result.stdout.length;
            }
            if (result.stderr && typeof result.stderr === 'string') {
              gt.stderr_preview = truncate(result.stderr, 800);
            }
            if ('exit_code' in result || 'exitCode' in result) {
              gt.exit_code = result.exit_code ?? result.exitCode;
            }
          }
          groundTruth = gt;
        }

        // Log tool activity to JSONL (mirrors ToolActivityTracker)
        const activity = {
          timestamp,
          event: 'tool_use',
          source: 'tool-activity',
          type: 'tool_use',
          session_id: sessionId,
          tool_name: tool,
          tool_input_preview: truncate(JSON.stringify(args), 300),
          success: !output?.error && !(output?.result && output.result?.error),
          duration,
          metadata: {
            callID: input.callID,
            title: output?.title,
          },
          ...(groundTruth ? { ground_truth: groundTruth } : {}),
        };

        appendJsonL(toolActivityPath, activity);

        // Track skill usage and emit to Pulse
        if (tool === 'skill') {
          const skillName = args?.name || 'unknown';
          console.log(`[PAI] 🎯 Skill used: ${skillName}`);

          try {
            await emitPulseEvent({
              type: 'skill_used',
              skill: skillName,
              timestamp,
              sessionId,
            });
          } catch (e) {
            // Pulse not available, ignore
          }
        }

        // Bump lastToolActivity on work.json (debounced)
        try {
          const registry = readWorkRegistry();
          let bestSlug = null;
          let bestTime = 0;
          for (const [slug, session] of Object.entries(registry.sessions)) {
            if (session.sessionUUID !== sessionId) continue;
            if (session.phase === 'complete') continue;
            const t = new Date(session.updatedAt || session.started || 0).getTime();
            if (t > bestTime) { bestTime = t; bestSlug = slug; }
          }
          if (bestSlug) {
            const DEBOUNCE_MS = 30 * 1000;
            const current = registry.sessions[bestSlug].lastToolActivity;
            if (!current || (Date.now() - new Date(current).getTime() >= DEBOUNCE_MS)) {
              registry.sessions[bestSlug].lastToolActivity = new Date().toISOString();
              writeWorkRegistry(registry);
            }
          }
        } catch (e) {
          // Silent fail
        }

        // Content scanning for web tools (mirrors ContentScanner)
        if (tool === 'webfetch' || tool === 'websearch') {
          const resultText = output?.result;

          if (resultText) {
            const content = typeof resultText === 'string' ? resultText : JSON.stringify(resultText);

            // Check for error indicators
            const has404 = content.includes('404') || content.includes('Not Found') || content.includes('not found');
            const hasError = content.includes('error') || content.includes('Error') || content.includes('ERROR');
            const isShort = content.length < 200;
            const isVeryShort = content.length < 50;

            // Check for prompt injection patterns in web content
            const injectionResult = inspectContent(content);
            if (injectionResult.action !== 'allow') {
              console.warn(`[PAI] ⚠️ ContentScanner: ${injectionResult.reason}`);
              logSecurityEvent({
                sessionId,
                tool,
                eventType: 'injection',
                inspector: 'ContentScanner',
                target: truncate(content, 500),
                reason: injectionResult.reason,
                actionTaken: 'Alert injected into context',
              });
            }

            if (has404) {
              console.warn('[PAI] ⚠️ ContentScanner: 404/Not Found detected in web content');
            }

            if (hasError && isShort) {
              console.warn('[PAI] ⚠️ ContentScanner: Error page detected (short content + error keywords)');
            }

            if (isVeryShort) {
              console.warn('[PAI] ⚠️ ContentScanner: Web content unusually short - possible blocking or empty response');
            } else if (isShort && !has404 && !hasError) {
              console.warn('[PAI] ⚠️ ContentScanner: Web content shorter than 200 chars - verify completeness');
            }

            // Log content scan result
            if (has404 || hasError || isVeryShort || injectionResult.action !== 'allow') {
              logSecurityEvent({
                sessionId,
                tool,
                eventType: 'content_scan_alert',
                inspector: 'ContentScanner',
                has404,
                hasError,
                contentLength: content.length,
                injectionDetected: injectionResult.action !== 'allow',
                timestamp,
              });
            }
          }
        }

        // Track file changes for Telos sync
        if (tool === 'write' || tool === 'edit' || tool === 'multiedit') {
          const filePath = args?.filePath || '';
          if (filePath.includes('TELOS/') || filePath.includes('USER/') || filePath.includes('PROJECTS/')) {
            console.log(`[PAI] 📝 User content modified: ${filePath}`);
          }
        }

        // Cache last response for satisfaction analysis
        if (output?.result && typeof output.result === 'string' && output.result.length > 0) {
          try {
            writeFileSync(lastResponseCache, output.result.slice(0, 2000), 'utf-8');
          } catch (e) {
            // Silent fail
          }
        }

      } catch (e) {
        console.error('[PAI] ❌ ToolActivityTracker error:', e.message);
      }
    },

    // ═══════════════════════════════════════════════════════════════
    // F6: PromptGuard - Detect dangerous patterns in user messages
    // ═══════════════════════════════════════════════════════════════
    "message.updated": async (input, output) => {
      const sessionId = getSessionId(input);

      try {
        const message = input.message || input.info;
        if (!message?.content) return;

        const content = typeof message.content === 'string'
          ? message.content
          : JSON.stringify(message.content);

        if (!content || content.length < 5) return;

        // Use PromptInspector to check for dangerous patterns
        const result = inspectPrompt(content);

        if (result.action !== 'allow') {
          console.warn(`[PAI] 🛡️ PromptGuard: ${result.violations.length} dangerous pattern(s) detected in prompt`);
          for (const v of result.violations) {
            console.warn(`[PAI]   - ${v.description} (${v.category}, ${v.severity})`);
          }

          logSecurityEvent({
            sessionId,
            eventType: result.action === 'deny' ? 'block' : 'alert',
            inspector: 'PromptGuard',
            tool: 'UserPrompt',
            target: truncate(content, 500),
            reason: result.reason,
            actionTaken: result.action === 'deny' ? 'Blocked prompt' : 'Alert logged',
          });

          if (result.action === 'deny') {
            // In OpenCode, we can't truly block like Claude Code hooks
            // Log it strongly and let the framework handle it
            console.error(`[PAI SECURITY] 🚨 BLOCKED: ${result.reason}`);
            // We log but don't throw here since OpenCode's message.updated
            // may not support blocking — the alert is the best we can do
          }
        }

        // Check for high repetition (basic repeat detection)
        if (content.length > 100) {
          const words = content.split(/\s+/).filter(w => w.length > 0);
          const uniqueWords = new Set(words.map(w => w.toLowerCase()));
          const repetitionRatio = words.length > 0 ? uniqueWords.size / words.length : 1;

          if (repetitionRatio < 0.3) {
            console.warn(`[PAI] 🔄 PromptGuard: High repetition detected (ratio: ${repetitionRatio.toFixed(2)})`);

            logSecurityEvent({
              sessionId,
              eventType: 'high_repetition_prompt',
              inspector: 'PromptGuard',
              repetitionRatio,
              timestamp: getISOTimestamp(),
            });
          }
        }

      } catch (e) {
        console.error('[PAI] ❌ PromptGuard error:', e.message);
      }
    },

    // ═══════════════════════════════════════════════════════════════
    // F3: SessionCleanup + F7: SatisfactionCapture + F8: WorkCompletionLearning
    // ═══════════════════════════════════════════════════════════════
    "session.idle": async (input, output) => {
      const timestamp = getISOTimestamp();
      const sessionId = getSessionId(input);

      try {
        console.log('[PAI] 🏁 Session complete - Running cleanup...');

        // 1. SessionCleanup: Mark work directory as completed and clear state
        try {
          const stateFile = findStateFile(sessionId);
          if (stateFile) {
            const currentWork = safeReadJson(stateFile);
            if (currentWork) {
              // Mark ISA.md/PRD.md as completed
              if (currentWork.session_dir) {
                const isaPath = findArtifactPath(currentWork.session_dir);
                const workPath = join(WORK_DIR, currentWork.session_dir);
                const metaPath = join(workPath, 'META.yaml');
                let marked = false;

                if (isaPath && existsSync(isaPath)) {
                  try {
                    let isaContent = readFileSync(isaPath, 'utf-8');
                    isaContent = writeFrontmatterField(isaContent, 'phase', 'complete');
                    isaContent = writeFrontmatterField(isaContent, 'updated', timestamp);
                    isaContent = isaContent.replace(/^status: ACTIVE$/m, 'status: COMPLETED');
                    isaContent = isaContent.replace(/^completed_at: null$/m, `completed_at: "${timestamp}"`);
                    writeFileSync(isaPath, isaContent, 'utf-8');
                    marked = true;
                  } catch {}
                }

                if (existsSync(metaPath)) {
                  try {
                    let metaContent = readFileSync(metaPath, 'utf-8');
                    metaContent = metaContent.replace(/^status: "ACTIVE"$/m, 'status: "COMPLETED"');
                    metaContent = metaContent.replace(/^completed_at: null$/m, `completed_at: "${timestamp}"`);
                    writeFileSync(metaPath, metaContent, 'utf-8');
                    marked = true;
                  } catch {}
                }

                if (marked) {
                  console.log(`[PAI] 📝 Marked work directory as COMPLETED: ${currentWork.session_dir}`);
                }
              }

              // Mark work.json sessions as complete
              try {
                const registry = readWorkRegistry();
                let touched = 0;
                for (const [, session] of Object.entries(registry.sessions)) {
                  if (session.sessionUUID !== sessionId) continue;
                  if (session.phase === 'complete') continue;
                  session.phase = 'complete';
                  session.updatedAt = timestamp;
                  touched++;
                }
                if (touched > 0) {
                  writeWorkRegistry(registry);
                  console.log(`[PAI] 📝 Marked ${touched} work.json session(s) complete`);
                }
              } catch (e) {
                console.error(`[PAI] Failed to mark work.json sessions complete: ${e.message}`);
              }

              // Clean session-names.json
              try {
                const names = readSessionNames();
                if (names[sessionId]) {
                  delete names[sessionId];
                  writeSessionNames(names);
                  console.log(`[PAI] 📝 Removed session ${sessionId} from session-names.json`);
                }
              } catch (e) {
                console.error(`[PAI] Failed to clean session-names.json: ${e.message}`);
              }

              // Delete state file
              try {
                unlinkSync(stateFile);
                console.log('[PAI] 📝 Cleared session work state');
              } catch {}
            }
          }
        } catch (e) {
          console.error(`[PAI] SessionCleanup error: ${e.message}`);
        }

        // 2. SatisfactionCapture: Prompt for rating and log availability
        try {
          console.log('[PAI] ⭐ Rate this session: Type /rate [1-10] or provide feedback');

          // Check if a rating was provided (look for explicit rating patterns in input)
          const prompt = input.prompt || input.message?.content || '';
          const promptStr = typeof prompt === 'string' ? prompt : '';

          if (promptStr.length >= MIN_PROMPT_LENGTH && !isSystemText(promptStr)) {
            // Fast path: explicit rating
            const explicitResult = parseExplicitRating(promptStr);
            if (explicitResult) {
              console.log(`[PAI] ⭐ Explicit rating: ${explicitResult.rating}`);

              let lastResponse = '';
              try {
                if (existsSync(lastResponseCache)) {
                  lastResponse = readFileSync(lastResponseCache, 'utf-8');
                }
              } catch {}

              appendJsonL(ratingsPath, {
                timestamp,
                rating: explicitResult.rating,
                session_id: sessionId,
                source: 'explicit',
                comment: explicitResult.comment,
                response_preview: lastResponse ? truncate(lastResponse, 500) : undefined,
              });

              // Update work.json with rating
              try {
                const registry = readWorkRegistry();
                for (const [, session] of Object.entries(registry.sessions)) {
                  if (session.sessionUUID === sessionId) {
                    if (!session.ratings) session.ratings = [];
                    session.ratings.push({
                      value: explicitResult.rating,
                      timestamp: Date.now(),
                      message: explicitResult.comment?.slice(0, 32),
                    });
                    session.minimalCount = (session.minimalCount || 0) + 1;
                    writeWorkRegistry(registry);
                    break;
                  }
                }
              } catch {}

              // Capture low rating learning
              if (explicitResult.rating < 5) {
                const category = getLearningCategory(promptStr, explicitResult.comment);
                const { year, month, day, hours, minutes, seconds } = getPSTComponents();
                const yearMonth = `${year}-${month}`;
                const learningsDir = join(LEARNING_DIR, category, yearMonth);
                ensureDir(learningsDir);
                const label = `low-rating-${explicitResult.rating}`;
                const filename = `${year}-${month}-${day}-${hours}${minutes}${seconds}_LEARNING_${label}.md`;
                const filepath = join(learningsDir, filename);

                const content = `---
capture_type: LEARNING
timestamp: ${year}-${month}-${day} ${hours}:${minutes}:${seconds} PST
rating: ${explicitResult.rating}
source: explicit
auto_captured: true
tags: [low-rating, improvement-opportunity]
---

# Low Rating Captured: ${explicitResult.rating}/10

**Date:** ${year}-${month}-${day}
**Rating:** ${explicitResult.rating}/10
**Detection Method:** Explicit Rating
${explicitResult.comment ? `**Feedback:** ${explicitResult.comment}` : ''}

---

## Context

${lastResponse ? truncate(lastResponse, 1000) : 'No context available'}

---

## Improvement Notes

This response was rated ${explicitResult.rating}/10. Use this as an improvement opportunity.

---
`;
                writeFileSync(filepath, content, 'utf-8');
                console.log(`[PAI] 🧠 Captured low rating learning: ${filename}`);
              }
            }

            // Fast path: positive praise
            if (detectPositivePraise(promptStr)) {
              console.log(`[PAI] ⭐ Positive praise detected → rating 8`);

              let lastResponse = '';
              try {
                if (existsSync(lastResponseCache)) {
                  lastResponse = readFileSync(lastResponseCache, 'utf-8');
                }
              } catch {}

              appendJsonL(ratingsPath, {
                timestamp,
                rating: 8,
                session_id: sessionId,
                source: 'implicit',
                sentiment_summary: `Direct praise: "${promptStr.trim()}"`,
                confidence: 0.95,
                response_preview: lastResponse ? truncate(lastResponse, 500) : undefined,
              });

              // Update work.json
              try {
                const registry = readWorkRegistry();
                for (const [, session] of Object.entries(registry.sessions)) {
                  if (session.sessionUUID === sessionId) {
                    if (!session.ratings) session.ratings = [];
                    session.ratings.push({
                      value: 8,
                      timestamp: Date.now(),
                      message: promptStr.trim().slice(0, 32),
                    });
                    session.minimalCount = (session.minimalCount || 0) + 1;
                    writeWorkRegistry(registry);
                    break;
                  }
                }
              } catch {}
            }
          }
        } catch (e) {
          console.error(`[PAI] SatisfactionCapture error: ${e.message}`);
        }

        // 3. WorkCompletionLearning: Capture learning signals
        try {
          const stateFile = findStateFile(sessionId);
          if (stateFile) {
            const currentWork = safeReadJson(stateFile);
            if (currentWork?.session_dir) {
              const workPath = join(WORK_DIR, currentWork.session_dir);
              const isaPath = findArtifactPath(currentWork.session_dir);
              const metaPath = join(workPath, 'META.yaml');

              let workMeta = {};
              if (isaPath) {
                try {
                  const isaContent = readFileSync(isaPath, 'utf-8');
                  const fm = parseFrontmatter(isaContent);
                  if (fm) workMeta = fm;
                } catch {}
              } else if (existsSync(metaPath)) {
                try {
                  const metaContent = readFileSync(metaPath, 'utf-8');
                  const fm = parseFrontmatter(metaContent);
                  if (fm) workMeta = fm;
                } catch {}
              }

              // Determine if significant work was done
              const hasFilesChanged = workMeta.lineage?.files_changed?.length > 0;
              const hasMultipleTasks = (currentWork.task_count ?? 0) > 1;
              const isManual = workMeta.source === 'MANUAL';
              const hasSignificantWork = hasFilesChanged || hasMultipleTasks || isManual;

              if (hasSignificantWork) {
                const category = getLearningCategory(workMeta.title || '');
                const { year, month } = getPSTComponents();
                const monthDir = join(LEARNING_DIR, category, `${year}-${month}`);
                ensureDir(monthDir);

                const dateStr = getPSTDate();
                const timeStr = new Date().toISOString().split('T')[1].slice(0, 5).replace(':', '');
                const titleSlug = (workMeta.title || 'work')
                  .toLowerCase()
                  .replace(/[^a-z0-9]+/g, '-')
                  .slice(0, 30);
                const filename = `${dateStr}_${timeStr}_work_${titleSlug}.md`;
                const filepath = join(monthDir, filename);

                // Calculate session duration
                let duration = 'Unknown';
                if (currentWork.created_at) {
                  const start = new Date(currentWork.created_at);
                  const end = new Date();
                  const minutes = Math.round((end.getTime() - start.getTime()) / 60000);
                  if (minutes < 60) {
                    duration = `${minutes} minutes`;
                  } else {
                    const hours = Math.floor(minutes / 60);
                    const mins = minutes % 60;
                    duration = `${hours}h ${mins}m`;
                  }
                }

                const content = `# Work Completion Learning

**Title:** ${workMeta.title || 'Untitled'}
**Duration:** ${duration}
**Category:** ${category}
**Session:** ${sessionId}

---

## What Was Done

- **Files Changed:** ${workMeta.lineage?.files_changed?.length || 0}
- **Tools Used:** ${workMeta.lineage?.tools_used?.join(', ') || 'None tracked'}
- **Agents Spawned:** ${workMeta.lineage?.agents_spawned?.length || 0}

## Insights

*This work session completed successfully. Consider what made it effective:*

- Was the approach straightforward or did it require iteration?
- Were there any blockers or surprises?
- What patterns from this work apply to future tasks?

---

*Auto-captured by WorkCompletionLearning at session end*
`;
                if (!existsSync(filepath)) {
                  writeFileSync(filepath, content, 'utf-8');
                  console.log(`[PAI] 🧠 Created learning file: ${filename}`);
                }

                // Also log to signals.jsonl
                appendJsonL(learningPath, {
                  timestamp,
                  type: 'work_completion',
                  category,
                  title: workMeta.title || 'Untitled',
                  workDir: currentWork.session_dir,
                  sessionId,
                  duration,
                  filesChanged: workMeta.lineage?.files_changed?.length || 0,
                });
              } else {
                console.log('[PAI] 🧠 Trivial work session, skipping learning capture');
              }
            }
          }
        } catch (e) {
          console.error(`[PAI] WorkCompletionLearning error: ${e.message}`);
        }

        // 4. SessionCleanup: Clean temp files
        try {
          const tmpDir = join(PAI_DIR, '.tmp');
          if (existsSync(tmpDir)) {
            const tmpFiles = readdirSync(tmpDir);
            for (const file of tmpFiles) {
              try {
                unlinkSync(join(tmpDir, file));
              } catch {}
            }
            if (tmpFiles.length > 0) {
              console.log(`[PAI] 🧹 Cleaned ${tmpFiles.length} temp files`);
            }
          }
        } catch (e) {
          // Silent fail
        }

        // Clean up /tmp/pai-* files
        try {
          const tmpFiles = readdirSync('/tmp').filter(f => f.startsWith('pai-'));
          for (const file of tmpFiles) {
            try {
              unlinkSync(join('/tmp', file));
            } catch {}
          }
          if (tmpFiles.length > 0) {
            console.log(`[PAI] 🧹 Cleaned ${tmpFiles.length} /tmp/pai-* files`);
          }
        } catch (e) {
          // Silent fail
        }

        // 5. Update counts
        try {
          let counts = safeReadJson(countsPath, { sessions: 0, tools: 0, skills: 0, ratings: 0, lastUpdated: timestamp });
          counts.sessions = (counts.sessions || 0) + 1;
          counts.lastUpdated = timestamp;
          safeWriteJson(countsPath, counts);
        } catch (e) {
          // Silent fail
        }

        // 6. Voice notification (optional)
        try {
          await notifyPulse('Session complete', { voice_enabled: false });
        } catch (e) {
          // Pulse not available
        }

        console.log('[PAI] ✅ Session cleanup complete');

      } catch (e) {
        console.error('[PAI] ❌ Session cleanup error:', e.message);
      }
    },
  };
};

export default PAIHooksPlugin;
