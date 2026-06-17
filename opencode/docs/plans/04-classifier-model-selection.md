# Plano — Seleção do modelo do classificador (setup via /interview + override por máquina no mobile)

> **Status (2026-06-16):** Fase 0 ✅, Fase 1 ✅, Fase 2 ✅ — todas implementadas.
> Fase 2 usa campo de texto para o modelo em vez de dropdown (ver nota). Fase 1
> editou diretamente o fonte da skill no repo (`skills/Interview/SKILL.md`, Step 6)
> a pedido do usuário — a regra do CreateSkill em `skills/CLAUDE.md` vale para o
> ambiente local instalado, não para editar o fonte no repo.

## Objetivo

Permitir que o usuário escolha **qual modelo o classificador de prompt usa**, de duas formas:

1. **No setup do PC** — delegado ao fluxo `/interview` (skill Interview).
2. **Por máquina, no app mobile** — cada servidor OpenCode pode ter seu próprio modelo de classificação, configurado pela UI do app.

## Realidade arquitetural

- O classificador **roda no servidor (PC)**, não no celular. Logo "por máquina" no app = "por servidor ao qual o app se conecta". Cada `Machine` do app já mapeia 1:1 para um servidor OpenCode.
- Hoje o modelo é resolvido **só por env var ou fallback hardcoded** em `opencode/plugins/pai-hooks.js:87-93`. Env var é difícil de escrever remotamente e normalmente exige restart.
- O app já grava config remota via SSH (padrão `provider_auth_service.dart` → `providers_screen.dart:207-232`). Reaproveitamos esse padrão.

---

## Fase 0 — Keystone: config do classificador em arquivo (plugin)

Sem isso, as duas features viram gambiarra. É a peça base.

**Arquivo de config (novo):** `~/.config/opencode/PAI/USER/Config/classifier.json`
```json
{ "model": "openai/gpt-5.5", "useLLM": true, "timeoutMs": 25000 }
```
(mesma pasta do já existente `PAI/USER/Config/PAI_CONFIG.yaml`)

**Precedência por campo:** `env var (se setada) > classifier.json (se setado) > default hardcoded`.
Isso mantém as env vars como escape hatch de debug (ex.: `PAI_CLASSIFIER_USE_LLM=false` para testes offline continua vencendo) e troca o *default* hardcoded por uma escolha persistente do usuário.

**Mudanças em `opencode/plugins/pai-hooks.js`:**

1. Constante + leitor com cache por mtime (I/O desprezível, **hot-reload sem restart**):
   ```javascript
   const CLASSIFIER_CONFIG_PATH = join(
     homedir(), '.config/opencode/PAI/USER/Config/classifier.json'
   );
   let _classifierFileCache = { mtimeMs: 0, data: {} };
   function readClassifierConfigFile() {
     try {
       const st = statSync(CLASSIFIER_CONFIG_PATH);
       if (st.mtimeMs !== _classifierFileCache.mtimeMs) {
         const raw = JSON.parse(readFileSync(CLASSIFIER_CONFIG_PATH, 'utf-8'));
         _classifierFileCache = { mtimeMs: st.mtimeMs, data: raw && typeof raw === 'object' ? raw : {} };
       }
     } catch { /* ausente/inválido → mantém último cache (tolerante, igual auth.json) */ }
     return _classifierFileCache.data;
   }
   ```

2. `resolveClassifierConfig()` substitui `defaultClassifierModel()` + o objeto fixo de `pai-hooks.js:360`:
   ```javascript
   function resolveClassifierConfig() {
     const f = readClassifierConfigFile();
     const model =
       process.env.PAI_CLASSIFIER_MODEL
       || (process.env.PAI_OPENCODE_PROVIDER && process.env.PAI_OPENCODE_MODEL
            ? `${process.env.PAI_OPENCODE_PROVIDER}/${process.env.PAI_OPENCODE_MODEL}` : null)
       || f.model
       || 'opencode/deepseek-v4-flash-free';
     const useLLM =
       process.env.PAI_CLASSIFIER_USE_LLM !== undefined && process.env.PAI_CLASSIFIER_USE_LLM !== ''
         ? envFlag('PAI_CLASSIFIER_USE_LLM', true)
         : (typeof f.useLLM === 'boolean' ? f.useLLM : true);
     const timeoutMs = parseInt(
       process.env.PAI_CLASSIFIER_TIMEOUT_MS || f.timeoutMs || '25000', 10
     );
     return { useLLM, model, timeoutMs,
       endpoint: process.env.PAI_CLASSIFIER_API_URL || null,
       apiKey: process.env.PAI_CLASSIFIER_API_KEY || null };
   }
   ```

3. No ponto de classificação (~`pai-hooks.js:514`), trocar o uso do `classifierConfig` fixo por `const classifierConfig = resolveClassifierConfig();` (lido a cada classificação → pega mudança a quente).

4. Adicionar imports `statSync` / `homedir` se ainda não presentes.

**Testes:** estender `opencode/tests/mode-classifier.test.ts` (ou novo `classifier-config.test.ts`) cobrindo precedência: arquivo-só, env sobrepondo arquivo, arquivo ausente → fallback, JSON inválido → tolerância.

---

## Fase 1 — Setup no PC via `/interview`

A skill Interview (`skills/Interview/SKILL.md`) ganha um passo de fechamento "runtime/classificador".

> ⚠️ **Restrição de processo:** mexer em skill exige `Skill("CreateSkill")` (ver `skills/CLAUDE.md`). Este passo NÃO é edição direta — orquestrar via CreateSkill para adicionar a nova fase/descrição.

Conteúdo do novo passo (Fase 5 — leve, ao final do fluxo):
1. Descobrir modelos disponíveis (`opencode models` ou catálogo de provider).
2. Perguntar (uma pergunta por vez, padrão da skill): "Qual modelo o PAI deve usar para classificar prompts?" e "Habilitar classificação por LLM?".
3. Gravar `~/.config/opencode/PAI/USER/Config/classifier.json` (via Write tool, ou helper opcional `PAI/TOOLS/SetClassifierModel.ts` para validação determinística + escrita).
4. Confirmar por voz, igual aos demais passos.

**Edição direta permitida (não é skill):** `opencode/config/opencode.jsonc.template:102` — incluir "modelo de classificação" no template do comando `interview`.

---

## Fase 2 — Override por máquina no app mobile

**2a. Modelo (`mobile-app/apps/flutter/lib/models/machine.dart`)**
Adicionar dois campos opcionais a `Machine`: `String? classifierModel`, `bool? classifierUseLlm`. Atualizar construtor, `fromJson`, `toJson` (com `if (... != null)`) e `copyWith` (padrão `_sentinel`). Persistência em secure storage é automática.

**2b. Serviço SSH (novo `lib/services/classifier_config_service.dart`)** — espelha `provider_auth_service.dart`:
```dart
const classifierConfigPath =
    r'~/.config/opencode/PAI/USER/Config/classifier.json';

Map<String, dynamic> mergeClassifierConfigJson({
  required String currentJson, String? model, bool? useLlm, int? timeoutMs,
}) { /* decode tolerante + set dos campos presentes */ }

String buildClassifierConfigWriteCommand(Map<String, dynamic> data) {
  // heredoc com delimitador único (igual buildAuthJsonWriteCommand)
  // prefixo: 'mkdir -p ~/.config/opencode/PAI/USER/Config && cat > ...'
}
```

**2c. UI (`lib/screens/machines_screen.dart`)** — no editor de máquina:
- **Implementado como campo de texto** (`provider/model`), não dropdown. Decisão:
  o catálogo de `getProviders()` tem shapes variados (Map/List) e depende de fetch
  de rede; o campo de texto é robusto, sem dependência de rede, e aceita qualquer
  modelo. Dropdown populado pelo catálogo fica como melhoria futura.
- Switch "Use LLM classifier".
- No salvar, se `classifierModel` setado e SSH disponível, push best-effort via
  `_pushClassifierConfigViaSsh()` — mesmo fluxo de `providers_screen.dart:207-232`
  (connect → cat config atual → merge → write heredoc). Falha não bloqueia o save.
- `classifier_config_service.dart` grava em `~/.config/opencode/PAI/USER/Config/classifier.json`.
- Sem modelo → persiste `null/null` (servidor usa seu próprio default).

**2d. Pré-condição:** override por máquina exige SSH configurado naquela `Machine` (mesma condição da escrita de provider auth). Sem SSH → desabilitar o controle e explicar.

**Testes Dart:** espelhar o teste existente de provider_auth para `mergeClassifierConfigJson` / `buildClassifierConfigWriteCommand`.

---

## Fase 3 — comando dedicado `/classifier` (✅ implementada)

Além do passo no `/interview`, um comando focado para (re)configurar só o classificador.

- **Skill `skills/Classifier/SKILL.md`** — fonte única do procedimento: descobre modelos
  reais com `opencode models`, pergunta modelo + LLM/heurística (uma de cada vez), grava
  `classifier.json` (merge), confirma por voz. Registrada em `install-manifest.json`
  (`skills`) para não ser arquivada pelo installer.
- **Comando `/classifier`** em `opencode.jsonc.template` (par thin-command + skill, como
  `/interview`).
- **Interview Step 6** enxugado para **delegar** à skill Classifier (DRY); gatilhos
  "classifier" removidos do USE WHEN do Interview e cedidos à skill dedicada.

> Descoberta de modelos: `opencode models` lista os `provider/model` realmente
> configurados/autenticados (uma linha cada) — mesmo formato do `classifier.json`.
> No mobile o equivalente seria `GET /config/providers` (hoje a UI usa campo de texto).

> Ativação: por serem mudanças de fonte (template + skill + manifest), exigem re-rodar o
> installer (regenera `opencode.jsonc` e copia skills). O `deploy-plugin.sh` sozinho só
> sincroniza o plugin (Fase 0).

## Ordem de execução e esforço

| Fase | O quê | Esforço | Depende de |
|---|---|---|---|
| 0 | Config em arquivo + hot-reload (plugin) | E2 | — |
| 1 | Passo no `/interview` (via CreateSkill) | E1-E2 | Fase 0 |
| 2 | Override por máquina no mobile | E2 | Fase 0 |

Fases 1 e 2 são independentes entre si depois da 0.

## Riscos / decisões fechadas

- **Precedência:** env > arquivo > default (env continua sendo escape hatch de debug). ✅
- **Hot-reload:** leitura com cache por mtime a cada classificação — sem restart. ✅
- **Sem endpoint HTTP novo:** mobile escreve via SSH (OpenCode não expõe API de escrita de config). ✅
- **Compat:** `classifier.json` ausente → comportamento idêntico ao de hoje. ✅
