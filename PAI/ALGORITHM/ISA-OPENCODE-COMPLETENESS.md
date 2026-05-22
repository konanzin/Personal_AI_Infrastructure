# ISA: Completude Máxima do Port PAI → OpenCode

**Version:** 1.0.0
**Effort:** E5 (Comprehensive)
**Status:** ACTIVE
**Created:** 2026-05-20
**Author:** PAI System

---

## Problem

O port do PAI v5.0.0 para OpenCode está em ~60% de compatibilidade com o sistema original nativo ao Claude Code. Faltam 22+ hooks e funcionalidades críticas que impedem o sistema de operar de forma autônoma (criar ISAs, guardar memórias, aprender com sessões, aprovar permissões inteligentemente).

## Vision

Alcançar a **completude máxima possível** dentro das limitações técnicas do OpenCode (~85-90% de compatibilidade), priorizando funcionalidades que o usuário observará em cada sessão.

## Out of Scope

- PULSE Dashboard (Next.js app de ~200 arquivos) — decisão consciente de não portar
- VoiceServer/TTS — requer infraestrutura externa
- KVSync/Cloudflare — sync cloud não é prioridade para instalação local
- MenuBar App Swift — macOS-only, não portável
- Integrações Telegram/iMessage — módulos de chat externos
- Hooks que dependem de eventos inexistentes no OpenCode (TeammateIdle, ConfigChange)

## Principles

1. **OpenCode Native Only** — usar APENAS eventos documentados em https://opencode.ai/docs/plugins/
2. **No Adapters** — não criar camadas de compatibilidade, implementar direto no evento nativo
3. **Incremental Delivery** — cada item deve ser testável independentemente
4. **Preserve Context Window** — documentar tudo em arquivos para agentes futuros lerem

## Constraints

- Usar JavaScript ES modules (não TypeScript para simplificar)
- Manter plugin em 2 arquivos: `pai-hooks.js` + `pai-hooks.lib.js`
- Todos os hooks devem ser resilientes (try/catch em torno de tudo)
- Logging via `console.log` (estruturado quando possível)
- Não quebrar hooks existentes (backward compat)

## Goal

Implementar todos os gaps de **baixa e média complexidade** identificados na revisão de compatibilidade, alcançando 85-90% de funcionalidade do PAI original.

## Criteria (ISCs)

- [ISC-001] Plugin carrega sem erros no OpenCode
- [ISC-002] Todos os eventos do OpenCode usados estão documentados
- [ISC-003] Nenhum hook quebra a execução normal do OpenCode
- [ISC-004] Validação 64/64 checks continua passando
- [ISC-005] Novos hooks geram logs observáveis na sessão
- [ISC-006] Documentação atualizada no plugin (comentários)

## Test Strategy

1. Instalar via `./opencode/install.sh`
2. Rodar validação: `bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh`
3. Testar cada evento manualmente (ex: criar arquivo ISA, rodar comando bash que falha, enviar mensagem repetida)
4. Verificar logs no console do OpenCode

## Features (Implementation Order)

### Phase 1: Low Complexity — Foundation (2-3h)

#### F1.1: command.executed — Track Custom Commands
**Event:** `command.executed`
**What:** Log usage of /pai, /status, /interview commands
**Implementation:**
```javascript
"command.executed": async (input, output) => {
  const { command, args } = input;
  appendJsonL(toolActivityPath, {
    timestamp: getISOTimestamp(),
    event: 'command_executed',
    command,
    args,
    session_id: getSessionId(input),
  });
  console.log(`[PAI] ⌨️ Command executed: ${command}`);
}
```
**Acceptance:** Running `/pai` shows `[PAI] ⌨️ Command executed: pai` in logs

#### F1.2: permission.replied — Log Permission Decisions
**Event:** `permission.replied`
**What:** Track whether user approved or denied permissions
**Implementation:**
```javascript
"permission.replied": async (input, output) => {
  const { tool, decision } = input; // decision: 'allow' | 'deny'
  appendJsonL(toolActivityPath, {
    timestamp: getISOTimestamp(),
    event: 'permission_replied',
    tool,
    decision,
    session_id: getSessionId(input),
  });
  console.log(`[PAI] 🔐 Permission ${decision} for: ${tool}`);
}
```
**Acceptance:** When OpenCode asks for permission and user replies, log shows decision

#### F1.3: session.deleted — Cleanup on Session Removal
**Event:** `session.deleted`
**What:** Remove session from work.json when explicitly deleted
**Implementation:**
```javascript
"session.deleted": async (input, output) => {
  const sessionId = getSessionId(input);
  try {
    const registry = readWorkRegistry();
    let deleted = 0;
    for (const [slug, session] of Object.entries(registry.sessions)) {
      if (session.sessionUUID === sessionId) {
        delete registry.sessions[slug];
        deleted++;
      }
    }
    if (deleted > 0) {
      writeWorkRegistry(registry);
      console.log(`[PAI] 🗑️ Removed ${deleted} session(s) from registry`);
    }
  } catch (e) {
    console.error('[PAI] ❌ Session delete cleanup error:', e.message);
  }
}
```
**Acceptance:** Deleting a session removes it from work.json

#### F1.4: file.edited — Track Direct Edits
**Event:** `file.edited`
**What:** Complement file.watcher.updated with explicit edit tracking
**Implementation:**
```javascript
"file.edited": async (input, output) => {
  const { path } = input;
  if (!path.includes('PAI/') && !path.includes('.claude/')) return;
  
  appendJsonL(toolActivityPath, {
    timestamp: getISOTimestamp(),
    event: 'file_edited',
    file_path: path,
    session_id: getSessionId(input),
  });
  console.log(`[PAI] ✏️ File edited: ${path}`);
}
```
**Acceptance:** Editing a PAI file shows edit log

### Phase 2: Medium Complexity — Intelligence (4-6h)

#### F2.1: session.compacted — Preserve PAI Context
**Event:** `experimental.session.compacting`
**What:** Inject PAI context into compaction prompt so memory survives context window resets
**Implementation:**
```javascript
"experimental.session.compacting": async (input, output) => {
  try {
    // Load current work context
    const currentWork = safeReadJson(join(STATE_DIR, 'current-work.json'), {});
    const registry = readWorkRegistry();
    
    // Find active session
    let activeSession = null;
    for (const [, session] of Object.entries(registry.sessions)) {
      if (session.sessionUUID === currentWork.session_id && session.phase !== 'complete') {
        activeSession = session;
        break;
      }
    }
    
    if (activeSession) {
      output.context.push(`## PAI Active Session Context
- Task: ${activeSession.task || 'Unknown'}
- Phase: ${activeSession.phase || 'native'}
- Progress: ${activeSession.progress || '0/0'}
- ISA: ${activeSession.isa_path || 'None'}
- Files Modified: ${(activeSession.files_modified || []).length} files`);
      console.log('[PAI] 🧠 Injected session context into compaction');
    }
    
    // Add high-confidence opinions
    try {
      const opinionsPath = join(PAI_DIR, 'USER', 'OPINIONS.md');
      if (existsSync(opinionsPath)) {
        const content = readFileSync(opinionsPath, 'utf-8');
        const opinions = content.split(/^### /gm).slice(1, 4);
        if (opinions.length > 0) {
          output.context.push(`## User Opinions (High Confidence)
${opinions.map(o => '- ' + o.split('\n')[0]).join('\n')}`);
        }
      }
    } catch {}
    
  } catch (e) {
    console.error('[PAI] ❌ Compaction hook error:', e.message);
  }
}
```
**Acceptance:** When session compacts, PAI context appears in continuation

#### F2.2: message.updated — Session Analysis & Effort Detection
**Event:** `message.updated`
**Enhancement to existing PromptGuard:** Add session analysis
**What:** Analyze user intent, detect effort tier, auto-name sessions
**Implementation:** Add to existing `message.updated` handler:
```javascript
// After PromptGuard checks, add:

// Session Analysis: Detect effort and intent
try {
  const effortKeywords = {
    E1: ['quick', 'simple', 'fast', 'check', 'verify', 'small'],
    E2: ['create', 'add', 'update', 'fix', 'implement'],
    E3: ['design', 'refactor', 'migrate', 'integrate'],
    E4: ['architect', 'system', 'infrastructure', 'protocol'],
    E5: ['rewrite', 'rebuild', 'overhaul', 'paradigm']
  };
  
  const lowerContent = content.toLowerCase();
  let detectedEffort = 'native';
  
  for (const [effort, keywords] of Object.entries(effortKeywords)) {
    if (keywords.some(kw => lowerContent.includes(kw))) {
      detectedEffort = effort;
      break;
    }
  }
  
  // Update session effort in work.json
  const registry = readWorkRegistry();
  for (const [, session] of Object.entries(registry.sessions)) {
    if (session.sessionUUID === sessionId && session.phase !== 'complete') {
      if (session.effort === 'native' || !session.effort) {
        session.effort = detectedEffort;
        writeWorkRegistry(registry);
        console.log(`[PAI] 🎯 Detected effort: ${detectedEffort}`);
      }
      break;
    }
  }
} catch (e) {
  // Silent fail
}
```
**Acceptance:** Saying "quick fix" sets effort to E1; "design system" sets to E4

#### F2.3: shell.env — PAI Environment Variables
**Event:** `shell.env`
**What:** Inject PAI environment variables into all shell executions
**Implementation:**
```javascript
"shell.env": async (input, output) => {
  output.env.PAI_DIR = PAI_DIR;
  output.env.PAI_VERSION = '5.0.0';
  output.env.PAI_USER = join(PAI_DIR, 'USER');
  
  // Load from .env if exists
  try {
    const envPath = join(PAI_DIR, '.env');
    if (existsSync(envPath)) {
      const envContent = readFileSync(envPath, 'utf-8');
      for (const line of envContent.split('\n')) {
        const [key, ...valueParts] = line.split('=');
        if (key && valueParts.length > 0) {
          output.env[key.trim()] = valueParts.join('=').trim();
        }
      }
    }
  } catch {}
  
  console.log('[PAI] 🌍 Injected PAI environment variables');
}
```
**Acceptance:** Running `echo $PAI_DIR` in bash shows correct path

### Phase 3: Polish — Documentation & Validation (1-2h)

#### F3.1: Update Plugin Header Documentation
Update comment block in `pai-hooks.js` to reflect all 15 hooks

#### F3.2: Add Validation Tests
Add checks to `validate-pai-installation.sh`:
- Check that `command.executed` tracking exists
- Check that `permission.replied` logging works
- Check that compaction context is configured

#### F3.3: Create TESTING.md
Document how to test each new hook manually

## Decisions

- **DEC-001:** Usar JavaScript em vez de TypeScript para manter simplicidade
- **DEC-002:** Não implementar SmartApprover completo (requeria ML/LLM calls que não são nativos)
- **DEC-003:** SessionAnalysis é rule-based (keywords) em vez de LLM-based por performance
- **DEC-004:** Contexto de compactação é opcional (try/catch) para não quebrar se evento experimental mudar

## Changelog

- **v1.0.0** (2026-05-20) — ISA inicial com 11 features em 3 fases

## Verification

### Pre-Implementation
- [ ] Ler documentação OpenCode: https://opencode.ai/docs/plugins/
- [ ] Confirmar que eventos `experimental.*` estão disponíveis na versão instalada
- [ ] Backup do plugin atual

### Per-Phase
- [ ] Phase 1: 4 features implementadas e testadas
- [ ] Phase 2: 3 features implementadas e testadas
- [ ] Phase 3: Documentação e validação atualizadas

### Post-Implementation
- [ ] Validação 64/64 checks passando
- [ ] Plugin carrega sem warnings
- [ ] Todos os eventos novos geram logs observáveis
- [ ] Commit com mensagem descritiva
- [ ] Push para origin/opencode

## Implementation Order

```
1. F1.1 command.executed
2. F1.2 permission.replied
3. F1.3 session.deleted
4. F1.4 file.edited
5. F2.1 experimental.session.compacting
6. F2.2 message.updated (enhance)
7. F2.3 shell.env
8. F3.1 Documentation
9. F3.2 Validation
10. F3.3 TESTING.md
```

**Estimated Total Time:** 8-12 hours
**Dependencies:** Nenhuma (cada feature é independente)
**Risk:** Baixo (todos são hooks opcionais que não quebram o sistema)

---

*ISA format: PAI v6.2.0 — Twelve-section frame*
*Next step: Assign to implementation agent*
