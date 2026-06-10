# Spike: OpenCode API Validation

Tested against OpenCode `1.16.2` running locally.

Date: 2026-06-09

## 1. Session Creation with Directory

### POST /session (without directory)

**Request:**
```
POST /session
Content-Type: application/json
{"title":"test-session"}
```

**Response (200):**
```json
{
    "id": "ses_151457f6affe5ENkPznY4B3dM1",
    "slug": "hidden-moon",
    "projectID": "7b40e2caafa8a41cc0888900d89429e0fb98137d",
    "directory": "/home/rbferreira/Personal_AI_Infrastructure",
    "path": "",
    "cost": 0,
    "tokens": { "input": 0, "output": 0, "reasoning": 0, "cache": { "read": 0, "write": 0 } },
    "title": "test-session",
    "version": "1.16.2",
    "time": { "created": 1781047918741, "updated": 1781047918741 }
}
```

**Finding:** When no `directory` query param is provided, the session inherits the server's working directory (the directory `opencode serve` was launched from). The `projectID` is a hash derived from that directory.

### POST /session?directory=/tmp/test-spike

**Request:**
```
POST /session?directory=/tmp/test-spike
Content-Type: application/json
{"title":"test-with-dir"}
```

**Response (200):**
```json
{
    "id": "ses_1514578a3ffe6ijqV4rFaWIrOj",
    "slug": "misty-orchid",
    "projectID": "global",
    "directory": "/tmp/test-spike",
    "path": "tmp/test-spike",
    "cost": 0,
    "tokens": { "input": 0, "output": 0, "reasoning": 0, "cache": { "read": 0, "write": 0 } },
    "title": "test-with-dir",
    "version": "1.16.2",
    "time": { "created": 1781047920476, "updated": 1781047920476 }
}
```

**Findings:**
- `directory` query parameter is supported and correctly scopes the session.
- `directory` field in the response matches the value sent.
- `path` field contains a relative version of the directory (without leading `/`).
- `projectID` becomes `"global"` when the directory is outside the server's own project tree.
- When directory is within the server project, `projectID` matches the hash and `path` is relative to the project root.

## 2. Session Listing with Directory Filter

### GET /session (all sessions)

Returns all sessions as a JSON array. Each session object has the same schema shown above.

### GET /session?directory=/tmp/test-spike

**Response (200):**
```json
[
    {
        "id": "ses_1514578a3ffe6ijqV4rFaWIrOj",
        "slug": "misty-orchid",
        "projectID": "global",
        "directory": "/tmp/test-spike",
        "path": "tmp/test-spike",
        "title": "test-with-dir",
        "version": "1.16.2",
        "time": { "created": 1781047920476, "updated": 1781047920476 }
    }
]
```

**Finding:** Directory filtering works correctly. Only sessions matching the exact directory path are returned. This is an exact match, not prefix-based.

## 3. Session by ID

### GET /session/{id}

Returns the full session object, same schema as creation response. Confirmed `directory` field is always present.

### DELETE /session/{id}

Returns `true` (boolean) with HTTP 200 on successful deletion.

## 4. Session Object Schema

All session responses share this structure:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique session ID (format: `ses_*`) |
| `slug` | string | Human-readable slug (e.g., `"misty-orchid"`) |
| `projectID` | string | Project hash or `"global"` for external directories |
| `directory` | string | Absolute path of the session's working directory |
| `path` | string | Relative path from server root (empty string if same directory) |
| `cost` | number | Accumulated cost |
| `tokens` | object | Token usage breakdown (`input`, `output`, `reasoning`, `cache`) |
| `title` | string | Session title |
| `version` | string | OpenCode version that created the session |
| `time` | object | `created` and `updated` timestamps (Unix ms) |
| `agent` | string? | Agent used (e.g., `"build"`, `"explore"`) -- only after first message |
| `model` | object? | `{id, providerID, variant}` -- only after first message |
| `parentID` | string? | Parent session ID for sub-agent sessions |
| `summary` | object? | `{additions, deletions, files}` -- only after tool use |
| `permission` | array? | Permission overrides for sub-agent sessions |

## 5. Provider Read Endpoints

### GET /config/providers

**Response (200):**
```json
{
  "providers": [
    {
      "id": "kimi-for-coding",
      "name": "Kimi For Coding",
      "source": "api",
      "env": ["KIMI_API_KEY"],
      "key": "sk-kimi-XXXX...",
      "options": {},
      "models": {
        "k2p6": { "id": "k2p6", "providerID": "kimi-for-coding", ... },
        ...
      }
    }
  ]
}
```

**WARNING:** This endpoint returns API keys in plaintext. The mobile app MUST sanitize/redact keys before display or logging.

### GET /provider

**Response (200):**
```json
{
  "all": [
    {
      "id": "openrouter",
      "name": "OpenRouter",
      "source": "custom",
      "env": ["OPENROUTER_API_KEY"],
      "options": {},
      "models": { ... }
    }
  ]
}
```

**Finding:** `/provider` returns ALL known providers (built-in + custom), including those without credentials. `/config/providers` returns only configured/authenticated providers with their actual keys. These are different views:
- `/config/providers` = active providers with credentials (sensitive data)
- `/provider` = full provider registry (catalog of available providers and models)

## 6. Provider Write Endpoints

### POST /config/providers, PUT /config/providers, POST /provider, PUT /provider

**All return HTTP 200 with HTML (web UI SPA catch-all).** None of these routes exist as API endpoints.

**Conclusion: OpenCode 1.16.2 has NO HTTP API for writing provider configuration.**

### CLI: opencode providers

```
opencode providers list         -- list providers and credentials
opencode providers login [url]  -- log in to a provider
opencode providers logout       -- log out from a configured provider
```

`opencode providers login` supports:
- `-p, --provider` -- provider id or name to log in to (skips selection)
- `-m, --method` -- login method label (skips method selection)

### Credential Storage

Credentials are stored in `~/.local/share/opencode/auth.json`:

```json
{
  "kimi-for-coding": {
    "type": "api",
    "key": "sk-kimi-XXXX..."
  }
}
```

Simple JSON object keyed by provider ID. Each entry has:
- `type`: authentication type (e.g., `"api"`)
- `key`: the API key

## 7. Implications for Mobile App

### Session/Directory (Phases 1-3)

All planned session features are fully supported by the API:

1. `createSession(directory:)` -- use `POST /session?directory=<path>`. Confirmed working.
2. `listSessions(directory:)` -- use `GET /session?directory=<path>`. Confirmed working as exact match.
3. Session schema always includes `directory` field. No parsing ambiguity.
4. The existing `OpenCodeClient` already has `directory` support for `listSessionRecords`, `sendMessage`, and SSE events. Only `createSession` needs the parameter added.

### Provider Management (Phase 6)

Since there is no HTTP write API for providers:

1. **Read operations** are fully supported via `GET /config/providers` (active) and `GET /provider` (catalog).
2. **Write operations** require one of:
   - **Option A (recommended):** Write directly to `~/.local/share/opencode/auth.json` via SSH or PAI agent. The format is simple and deterministic.
   - **Option B:** Execute `opencode providers login -p <provider> -m <method>` via SSH. This is interactive (prompts for key), making automation harder.
   - **Option C:** Wait for a future OpenCode HTTP API for provider management.
3. **Cache invalidation:** After writing credentials, the server may need a restart or a signal to reload. The mobile app should call `GET /config/providers` to verify the write took effect. If the provider doesn't appear, document that a server restart is needed.
4. **Security:** `GET /config/providers` exposes API keys. The mobile app must never log, cache, or display raw key values. Sanitize immediately after parsing.

### Recommended Approach for Provider Write (Phase 6)

Given the simple `auth.json` format, the safest path is:

1. Read current `auth.json` via SSH (`cat ~/.local/share/opencode/auth.json`).
2. Merge the new provider entry.
3. Write back via SSH (`cat > ~/.local/share/opencode/auth.json << 'EOF' ... EOF`).
4. Verify via `GET /config/providers`.
5. If verification fails, the server may need restart. Document this limitation.

When PAI machine agent is available, delegate this operation to the agent for better safety and atomicity.

## 8. Mobile App Provider Write Implementation

Based on the findings above, the mobile app writes provider credentials as follows:

1. **Read** current `~/.local/share/opencode/auth.json` via SSH.
2. **Merge** the new entry using `mergeProviderAuthJson()` (in `lib/services/provider_auth_service.dart`).
3. **Write** back via SSH heredoc (`buildAuthJsonWriteCommand()`).
4. **Verify** via `GET /config/providers` that OpenCode recognizes the provider. If not, the UI warns that a server restart may be required.

### Entry format

```json
{
  "provider-id": {
    "type": "api",
    "key": "sk-..."
  }
}
```

- `type` is always `"api"`. Never the provider name (e.g., not `"openai"`).
- `key` is the API key string.
- There is **no HTTP write API** in OpenCode 1.16.2.
- Custom provider `baseUrl` is **not implemented** in this flow. The `auth.json` format does not appear to support it; a separate spike is needed to discover where OpenCode stores custom base URLs.

## 9. Additional Observations

- **Server working directory matters:** Sessions created without `directory` inherit the server's CWD. For mobile, always pass `directory` explicitly.
- **`projectID` behavior:** External directories get `"global"` as projectID. This is fine for the mobile app since we scope by directory, not projectID.
- **Timestamps:** Use Unix milliseconds (not seconds). The mobile app's existing `Session.fromJson` already handles this.
- **Session deletion:** `DELETE /session/{id}` returns `true` (boolean, not JSON object). The mobile app should handle this.
