# External Integrations

**Analysis Date:** 2026-05-25

## APIs & Services

### AI / LLM Providers

GBrain uses a unified AI gateway (`src/core/ai/gateway.ts`) with a recipe registry (`src/core/ai/recipes/`). Each recipe declares touchpoints (embedding, expansion, chat) and the env vars it requires.

**Anthropic** (primary chat + expansion provider)
- SDK: `@anthropic-ai/sdk ^0.30.0` (direct, for subagent tool-loop) + `@ai-sdk/anthropic ^3.0.71` (AI SDK wrapper)
- Models: `claude-opus-4-7`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`
- Auth: `ANTHROPIC_API_KEY`
- Recipe: `src/core/ai/recipes/anthropic.ts`

**OpenAI** (default embedding provider)
- SDK: `openai ^4.0.0` (direct, for embedding batch) + `@ai-sdk/openai ^3.0.53` (AI SDK wrapper)
- Default embedding model: `text-embedding-3-large` (1536 dims)
- Auth: `OPENAI_API_KEY`
- Recipe: `src/core/ai/recipes/openai.ts`

**Voyage AI** (alternative embedding, supports multimodal)
- SDK: `@ai-sdk/openai-compatible ^2.0.41` (OpenAI-compat adapter)
- Models: `voyage-4-large`, `voyage-4`, `voyage-3-large`, `voyage-3.5`, `voyage-multimodal-3`, etc.
- Flexible output dims: 256/512/1024/2048 for supported models
- Auth: `VOYAGE_API_KEY`
- Recipe: `src/core/ai/recipes/voyage.ts`

**Google (Gemini)**
- SDK: `@ai-sdk/google ^3.0.64`
- Embedding: `gemini-embedding-001`; Chat/expansion: `gemini-2.0-flash`, `gemini-1.5-pro`
- Auth: `GOOGLE_GENERATIVE_AI_API_KEY`
- Recipe: `src/core/ai/recipes/google.ts`

**Groq** (audio transcription + chat)
- Default transcription provider when `GROQ_API_KEY` is set (Whisper via Groq)
- Auth: `GROQ_API_KEY`
- Recipe: `src/core/ai/recipes/groq.ts`

**OpenRouter** (OpenAI-compat routing layer for multi-provider access)
- Base URL: `https://openrouter.ai/api/v1`
- Covers embedding + chat via upstream providers
- Auth: `OPENROUTER_API_KEY`
- Recipe: `src/core/ai/recipes/openrouter.ts`

**Azure OpenAI** (enterprise OpenAI deployment)
- Auth: `AZURE_OPENAI_API_KEY`, `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_DEPLOYMENT`
- Optional: `AZURE_OPENAI_API_VERSION` (default `2024-10-21`)
- Recipe: `src/core/ai/recipes/azure-openai.ts`

**Together AI** (open models)
- Auth: `TOGETHER_API_KEY`
- Recipe: `src/core/ai/recipes/together.ts`

**DeepSeek**
- Auth: `DEEPSEEK_API_KEY`
- Recipe: `src/core/ai/recipes/deepseek.ts`

**Alibaba DashScope (Qwen)**
- Auth: `DASHSCOPE_API_KEY`
- Recipe: `src/core/ai/recipes/dashscope.ts`

**MiniMax**
- Auth: `MINIMAX_API_KEY`
- Recipe: `src/core/ai/recipes/minimax.ts`

**Zhipu AI (GLM)**
- Recipe: `src/core/ai/recipes/zhipu.ts`

**LiteLLM Proxy** (self-hosted LLM proxy)
- Base URL: `LITELLM_BASE_URL` (optional)
- Auth: `LITELLM_API_KEY` (optional — proxy can run unauthenticated locally)
- Recipe: `src/core/ai/recipes/litellm-proxy.ts`

**Ollama** (local model server)
- Recipe: `src/core/ai/recipes/ollama.ts`

**llama.cpp server**
- Base URL: `LLAMA_SERVER_BASE_URL` (optional)
- Auth: `LLAMA_SERVER_API_KEY` (optional)
- Recipe: `src/core/ai/recipes/llama-server.ts`

### Audio Transcription

- **Groq Whisper** (default when `GROQ_API_KEY` set): `src/core/transcription.ts`
- **OpenAI Whisper** (fallback when `OPENAI_API_KEY` set)
- **ffmpeg** (system binary, required for audio files >25MB — splits into <25MB chunks)
  - Not a Node/Bun package; must be installed separately: `brew install ffmpeg` / `apt install ffmpeg`

## Databases & Storage

### Database Engines (pluggable via engine factory)

**PGLite** — embedded Postgres 17.5 via WASM
- Package: `@electric-sql/pglite 0.4.3`
- Zero-config default, no external server needed
- Implementation: `src/core/pglite-engine.ts`
- Schema: `src/core/pglite-schema.ts`
- Data dir: `~/.gbrain/` (or `GBRAIN_HOME/.gbrain/`)

**Postgres + pgvector** — managed Supabase or self-hosted
- Client: `postgres ^3.4.0` (postgres.js)
- pgvector helper: `pgvector ^0.2.0`
- Required for: pgbouncer pooling, RLS, HTTP MCP server OAuth tables, multi-user deployments
- Connection: `GBRAIN_DATABASE_URL` or `DATABASE_URL` (postgres.js connection string)
- Pool size: `GBRAIN_POOL_SIZE` (default 10; lower to 2 for Supabase transaction pooler)
- Session timeouts: `GBRAIN_STATEMENT_TIMEOUT` (default 5min), `GBRAIN_IDLE_TX_TIMEOUT` (default 5min)
- Implementation: `src/core/postgres-engine.ts`
- Schema: `src/schema.sql` (source of truth), `src/core/schema-embedded.ts` (auto-generated)

**Supabase** (managed Postgres hosting option)
- Management API: `https://api.supabase.com/v1/` — used during `gbrain init` for project discovery and pooler URL detection (`src/core/supabase-admin.ts`)
- No Supabase client SDK used — raw postgres.js connects directly to the Supabase Postgres pooler
- Connection: standard `DATABASE_URL` pointing to Supabase pooler
- Supabase Management API auth: one-time access token during setup (not persisted)

**Query layer:** No ORM. Raw SQL via:
- `postgres.js` tagged template (`sql`...) for Postgres engine
- PGLite's `db.query(sql, params)` for embedded engine
- `src/core/sql-query.ts` — unified scalar-safe SQL adapter for OAuth/admin infrastructure (works on both engines)

### File Storage Backends (pluggable via `src/core/storage.ts`)

**S3 / R2 / MinIO**
- SDK: `@aws-sdk/client-s3 ^3.1028.0`
- Config: `accessKeyId`, `secretAccessKey`, `bucket`, `region`, `endpoint`
- Implementation: `src/core/storage/s3.ts`

**Supabase Storage**
- Config: `projectUrl`, `serviceRoleKey`, `bucket`
- Implementation: `src/core/storage/supabase.ts`

**Local filesystem**
- Path: `localPath` config key (default `/tmp/gbrain-storage`)
- Implementation: `src/core/storage/local.ts`

Storage config lives in `gbrain.yml` at the brain repo root under `storage:` key.

## Authentication & Authorization

### CLI / Local (default)

- No auth required for local CLI use
- `OperationContext.remote: false` set by `src/cli.ts` — trusted caller, full access
- Shell job execution gated by `GBRAIN_ALLOW_SHELL_JOBS=1` env var (default off)

### MCP Server (stdio)

- `OperationContext.remote: true` set by `src/mcp/server.ts`
- No token auth on stdio MCP — trust boundary is OS process ownership
- Scope enforcement via `scope?: 'read' | 'write' | 'admin'` on each operation
- `localOnly: boolean` operations rejected on remote/HTTP path

### HTTP MCP Server (`gbrain serve --http`)

**OAuth 2.1** — implemented in `src/core/oauth-provider.ts` + `src/commands/serve-http.ts`

- Standards: OAuth 2.1, RFC 7591 (DCR), RFC 7009 (token revocation), PKCE (RFC 7636)
- Grant types: `client_credentials` (Perplexity, Claude), `authorization_code` + PKCE (ChatGPT)
- Scopes: `read`, `write`, `admin`
- Token storage: SHA-256 hashed in `oauth_tokens` / `oauth_clients` Postgres tables
- Legacy `access_tokens` table grants `read+write+admin` for pre-v0.26 backwards compat
- Admin dashboard: `admin/dist/` SPA served at `/admin`, auth via HTTP-only SameSite=Strict cookie
- Bootstrap token: printed to stderr on first start (for initial admin login)
- DCR (`/register`): disabled by default, enabled via `--enable-dcr` flag

**Rate limiting** (`src/mcp/rate-limit.ts`)
- Pre-auth IP bucket: 30 req/60s (fires BEFORE DB lookup to cap brute-force)
- Post-auth token bucket: 60 req/60s
- LRU-bounded key store to prevent memory exhaustion under adversarial key growth

**Request logging:** `mcp_request_log` table — params redacted by default via `summarizeMcpParams()`. Raw params opt-in via `--log-full-params` (localhost only).

### Thin-client mode (`gbrain init --mcp-only`)

- No local DB; routes all operations to remote `gbrain serve --http` over MCP
- OAuth client credentials stored in `~/.gbrain/config.json` under `remote_mcp`
- `GBRAIN_REMOTE_CLIENT_SECRET` env var for headless agents
- Implementation: `src/core/mcp-client.ts` + `src/cli.ts:runThinClientRouted`

## Infrastructure

### Hosting

**Self-hosted / local** — primary deployment model. Binary runs on developer machine, serves stdio MCP to Claude Desktop / Cursor / OpenClaw.

**Fly.io** — referenced in CLAUDE.md as a deployment target for `gbrain serve --http` (mentioned in health check timeout context). No Fly.io-specific config files in this repo.

**Docker** — used for local CI only (`docker-compose.ci.yml`, `docker-compose.test.yml`). Not the primary deployment artifact.

### Monitoring & Observability

**No external monitoring service detected** (no Datadog, Sentry, etc. SDKs).

**Built-in health endpoints** (HTTP server only):
- `GET /health` — liveness-only (`SELECT 1`, 3s timeout) returns `{status, version, engine}`
- `GET /admin/api/full-stats` — full DB stats (admin-cookie gated)
- `GET /admin/api/health-indicators` — `{expiring_soon, error_rate}` (admin-cookie gated)
- `GET /admin/events` — SSE live activity feed for the admin dashboard

**Structured logging:**
- `~/.gbrain/audit/shell-jobs-YYYY-Www.jsonl` — shell job audit trail
- `~/.gbrain/audit/subagent-jobs-YYYY-Www.jsonl` — subagent heartbeat audit
- `~/.gbrain/audit/backpressure-YYYY-Www.jsonl` — queue backpressure events
- `~/.gbrain/audit/slug-fallback-YYYY-Www.jsonl` — CJK slug fallback audit
- `~/.gbrain/sync-failures.jsonl` — sync parse failure log
- `~/.gbrain/upgrade-errors.jsonl` — upgrade failure trail
- `~/.gbrain/.gbrain/eval-receipts/` — cross-modal eval receipts
- Audit dir overridable via `GBRAIN_AUDIT_DIR`

**Progress reporting:** All bulk commands stream structured progress to stderr via `src/core/progress.ts`. JSON mode via `--progress-json`.

### CI/CD Infrastructure

- **GitHub Actions** — test.yml (4-shard unit), e2e.yml (Tier 1 + Tier 2), release.yml
- **gitleaks** — secret scanning on every PR/push
- **Docker** — `pgvector/pgvector:pg16` for E2E test DB
- **OpenClaw** — `npm install -g openclaw@2026.4.9` in Tier 2 E2E CI
- **ClawHub** — package registry for plugin distribution (`bun run publish:clawhub`)

### System Dependencies (not npm packages)

- **ffmpeg** — required for audio transcription of files >25MB (Whisper segments)
- **tini** — optional PID-1 wrapper for worker subtree zombie reaping (`src/core/minions/spawn-helpers.ts`)
- **git** — required for sync (reads git log, HEAD, working tree)
- **ps** — required by `gbrain serve` watchdog for parent-death detection on stdio MCP

## Environment Variables

### Required for Core Operation

| Variable | Purpose |
|----------|---------|
| `GBRAIN_DATABASE_URL` or `DATABASE_URL` | Postgres connection string (if using Postgres engine) |
| `ANTHROPIC_API_KEY` | Anthropic Claude (chat, synthesis, subagent loops) |
| `OPENAI_API_KEY` | OpenAI embedding (default embedding provider) |

### AI Provider Keys (configure the provider you use)

| Variable | Provider |
|----------|---------|
| `VOYAGE_API_KEY` | Voyage AI (embedding, multimodal) |
| `GROQ_API_KEY` | Groq (transcription default; also chat/expansion) |
| `GOOGLE_GENERATIVE_AI_API_KEY` | Google Gemini (embedding, chat, expansion) |
| `OPENROUTER_API_KEY` | OpenRouter (multi-provider routing) |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI |
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI endpoint URL |
| `AZURE_OPENAI_DEPLOYMENT` | Azure OpenAI deployment name |
| `AZURE_OPENAI_API_VERSION` | Azure API version (default `2024-10-21`) |
| `TOGETHER_API_KEY` | Together AI |
| `DEEPSEEK_API_KEY` | DeepSeek |
| `DASHSCOPE_API_KEY` | Alibaba DashScope (Qwen) |
| `MINIMAX_API_KEY` | MiniMax |
| `LLAMA_SERVER_BASE_URL` | llama.cpp server base URL |
| `LLAMA_SERVER_API_KEY` | llama.cpp server auth (optional) |
| `LITELLM_BASE_URL` | LiteLLM proxy base URL (optional) |
| `LITELLM_API_KEY` | LiteLLM proxy auth (optional) |

### gbrain-Specific Configuration

| Variable | Purpose |
|----------|---------|
| `GBRAIN_HOME` | Override `~` as parent dir for `.gbrain/` data directory |
| `GBRAIN_POOL_SIZE` | Postgres connection pool size (default 10) |
| `GBRAIN_STATEMENT_TIMEOUT` | Postgres statement timeout (default 5min) |
| `GBRAIN_IDLE_TX_TIMEOUT` | Postgres idle transaction timeout (default 5min) |
| `GBRAIN_EMBEDDING_MODEL` | Override embedding model (e.g. `voyage:voyage-4-large`) |
| `GBRAIN_EMBEDDING_DIMENSIONS` | Override embedding vector dimensions |
| `GBRAIN_EXPANSION_MODEL` | Override query expansion model |
| `GBRAIN_CHAT_MODEL` | Override chat model |
| `GBRAIN_CHAT_FALLBACK_CHAIN` | Comma-separated fallback model chain |
| `GBRAIN_EMBEDDING_MULTIMODAL` | Enable multimodal embedding (`true`/`false`) |
| `GBRAIN_EMBEDDING_MULTIMODAL_MODEL` | Multimodal embedding model override |
| `GBRAIN_ALLOW_SHELL_JOBS` | Enable shell job handler on worker (`1` = enabled) |
| `GBRAIN_ANTHROPIC_MAX_INFLIGHT` | Max concurrent Anthropic subagent calls (default 8) |
| `GBRAIN_AUDIT_DIR` | Override audit JSONL directory |
| `GBRAIN_SKILLS_DIR` | Explicit skills directory override (beats OPENCLAW_WORKSPACE) |
| `GBRAIN_SOURCE_BOOST` | Custom source boost map (CSV `prefix:factor` pairs) |
| `GBRAIN_SEARCH_EXCLUDE` | Custom hard-exclude slug prefixes (CSV) |
| `GBRAIN_REMOTE_CLIENT_SECRET` | OAuth client secret for thin-client mode |
| `GBRAIN_CONTRIBUTOR_MODE` | Enable eval capture for BrainBench (`1` = enabled) |
| `GBRAIN_NO_REEMBED` | Skip post-upgrade re-embedding (`1` = skip) |
| `GBRAIN_REEMBED_GRACE_SECONDS` | Seconds to wait before auto-proceeding re-embed (default 10) |
| `GBRAIN_QUEUE_WAITING_THRESHOLD` | Doctor queue health warn threshold (default 10) |
| `GBRAIN_SYNC_FRESHNESS_WARN_HOURS` | Warn threshold for stale sync (default 24h) |
| `GBRAIN_SYNC_FRESHNESS_FAIL_HOURS` | Fail threshold for stale sync (default 72h) |
| `GBRAIN_NO_GITIGNORE` | Skip .gitignore auto-management on sync (`1` = skip) |
| `GBRAIN_PLUGIN_PATH` | Colon-separated paths to Minion plugin directories |
| `GBRAIN_RECIPES_DIR` | Additional (untrusted) integration recipes directory |
| `GBRAIN_NO_BANNER` | Suppress identity banner in thin-client mode (`1` = suppress) |
| `GBRAIN_DEBUG` | Enable debug logging in select components (`1` = on) |
| `GBRAIN_FRICTION_RUN_ID` | Active friction run ID for `gbrain friction log` |
| `OPENCLAW_WORKSPACE` | Path to OpenClaw workspace (for skills dir auto-detection) |
| `GBRAIN_DIRECT_DATABASE_URL` | Direct Postgres URL (bypasses PgBouncer for migration use) |
| `OPENCLAW_TELEGRAM_GROUP` | Telegram group ID for restart-sweep recipe alerts |

### Secrets Location

- API keys: stored in `~/.gbrain/config.json` (file plane) or set as env vars
- OAuth tokens: stored SHA-256 hashed in `oauth_tokens` DB table
- No `.env` files committed to repo

---

*Integration audit: 2026-05-25*
