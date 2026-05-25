# Architecture

**Analysis Date:** 2026-05-25

## System Overview

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                          Entry Points                                    │
├──────────────────┬─────────────────────┬────────────────────────────────┤
│  CLI             │  MCP stdio server   │  MCP HTTP server               │
│  `src/cli.ts`    │  `src/mcp/server.ts`│  `src/commands/serve-http.ts`  │
└────────┬─────────┴──────────┬──────────┴────────────────┬───────────────┘
         │                   │                            │
         └───────────────────┼────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       Operation Layer                                    │
│                `src/core/operations.ts`                                  │
│   ~47 Operations defined: get_page, put_page, search, query, think,     │
│   submit_job, extract_facts, recall, find_experts, find_anomalies, ...   │
│   Shared dispatch: `src/mcp/dispatch.ts`                                 │
└────────────────────────────┬────────────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────────────┐
│                       Engine Interface                                   │
│                   `src/core/engine.ts` (BrainEngine)                     │
│   Engine factory: `src/core/engine-factory.ts`                           │
├──────────────────────────────────────┬──────────────────────────────────┤
│  PGLiteEngine                        │  PostgresEngine                   │
│  `src/core/pglite-engine.ts`         │  `src/core/postgres-engine.ts`    │
│  Embedded Postgres 17.5 via WASM     │  Postgres + pgvector (Supabase/   │
│  Zero-config, single-file DB         │  self-hosted). Uses postgres.js.  │
└──────────────────────────────────────┴──────────────────────────────────┘
```

GBrain is a personal knowledge brain and agent platform. It indexes markdown notes (and code, images) into a Postgres database with vector embeddings, exposes ~47 operations via both a CLI and a Model Context Protocol server, runs a job queue for LLM subagents and shell jobs, and runs a nightly maintenance cycle that syncs, extracts links/timeline, synthesizes transcripts, and embeds content.

## Architecture Pattern

**Contract-first, pluggable-engine monolith with an embedded job queue.**

Key patterns:
- **Contract-first operations**: `src/core/operations.ts` is the single source of truth. CLI, stdio MCP, and HTTP MCP all call the same `Operation.handler(ctx, params)`. Adding an operation once makes it available on all three surfaces.
- **Pluggable engine**: `BrainEngine` interface (`src/core/engine.ts`) is implemented by both `PGLiteEngine` (WASM-embedded Postgres) and `PostgresEngine` (postgres.js). The factory (`src/core/engine-factory.ts`) dynamically imports the chosen engine so PGLite WASM is never loaded for Postgres users.
- **Trust boundary**: `OperationContext.remote: boolean` is a required field. `remote: false` means trusted local CLI; `remote: true` means untrusted MCP caller. Security-sensitive operations branch on this field. The HTTP MCP server and stdio server both set `remote: true`; the CLI sets `remote: false`.
- **Thin-client routing** (`v0.31.1`): when `isThinClient(cfg)` is true, `src/cli.ts` routes non-`localOnly` ops through `callRemoteTool` instead of opening the local engine. Shared ops work against a remote HTTP MCP server without a local brain.

## Core Components

| Component | Responsibility | Location |
|-----------|----------------|----------|
| Operations | Contract-first handler definitions (~47 ops) | `src/core/operations.ts` |
| BrainEngine | Pluggable DB interface (~50+ methods) | `src/core/engine.ts` |
| PGLiteEngine | Embedded Postgres WASM implementation | `src/core/pglite-engine.ts` |
| PostgresEngine | Postgres + pgvector implementation | `src/core/postgres-engine.ts` |
| Engine Factory | Dynamic import by config | `src/core/engine-factory.ts` |
| MCP Dispatch | Shared tool-call dispatch (stdio + HTTP) | `src/mcp/dispatch.ts` |
| AI Gateway | Unified seam for all LLM/embedding calls | `src/core/ai/gateway.ts` |
| Hybrid Search | Vector + keyword + RRF fusion pipeline | `src/core/search/hybrid.ts` |
| Import Pipeline | Chunk + embed + tag + persist | `src/core/import-file.ts` |
| Sync | Git diff → import changed files | `src/core/sync.ts` |
| Minions Queue | Postgres-native job queue (BullMQ-inspired) | `src/core/minions/queue.ts` |
| Minions Worker | Job handler registry + lock renewal | `src/core/minions/worker.ts` |
| Dream Cycle | 11-phase nightly brain maintenance | `src/core/cycle.ts` |
| Brain Registry | Multi-brain engine lookup by brainId | `src/core/brain-registry.ts` |
| OAuth Provider | OAuth 2.1 + token management for HTTP server | `src/core/oauth-provider.ts` |
| Config | File-plane + DB-plane configuration | `src/core/config.ts` |
| Facts | Hot-memory extraction + recall index | `src/core/facts/` |
| Chunkers | 3-tier: recursive / semantic / code (tree-sitter) | `src/core/chunkers/` |

## Data Flow

### Query / Search Request (CLI or MCP)

1. **Entry** (`src/cli.ts` or `src/mcp/server.ts`) — parse arguments, set `remote` flag, call `op.handler(ctx, params)` via `src/mcp/dispatch.ts`
2. **`query` / `search` handler** (`src/core/operations.ts`) — optionally expands the query (`src/core/search/expansion.ts`) then calls `hybridSearch` / `hybridSearchCached`
3. **`hybridSearch`** (`src/core/search/hybrid.ts`) — embeds query via `src/core/embedding.ts`, fires `engine.searchKeyword` + `engine.searchVector` in parallel, applies RRF fusion, backlink + salience boosts, dedup, token-budget enforcement
4. **Engine SQL** (`pglite-engine.ts` or `postgres-engine.ts`) — `ts_rank` keyword + HNSW cosine vector via pgvector, source-factor CASE ranking, hard-exclude clauses
5. **Result** — returned as `SearchResult[]`, formatted by the CLI renderer or serialized as MCP tool-call JSON

### Ingest / Sync Flow

1. **Sync trigger** (`src/commands/sync.ts` → `performSync`) — git diff against `last_commit` bookmark finds changed `.md` / code files
2. **importFromFile** (`src/core/import-file.ts`) — parse frontmatter + body (`src/core/markdown.ts`), chunk text (`src/core/chunkers/recursive.ts` or `code.ts`), optionally extract fenced-code chunks
3. **Embed** (`src/core/embedding.ts`) — batch OpenAI / Voyage API calls via `src/core/ai/gateway.ts`
4. **putPage + upsertChunks** — engine writes page row + content_chunks with `vector(N)` embeddings
5. **Auto-link** — `extractPageLinks` scans compiled_truth; `put_page` fires auto-link post-hook when `remote === false`

### Dream Cycle (nightly, `gbrain dream`)

Phases run in order in `src/core/cycle.ts`:
1. `lint` → filesystem writes only, no DB
2. `backlinks` → filesystem writes only
3. `sync` → DB: import changed files
4. `synthesize` → fan out Sonnet subagents per transcript, write wiki pages
5. `extract` → DB: link + timeline extraction
6. `extract_facts` → DB: facts fence index reconcile
7. `patterns` → single Sonnet subagent for cross-session themes
8. `recompute_emotional_weight` → `engine.batchLoadEmotionalInputs` → `engine.setEmotionalWeightBatch`
9. `consolidate` → cluster facts, synthesize takes
10. `embed` → embed stale chunks
11. `orphans` → report only, no DB writes
12. `purge` → hard-delete soft-deleted pages + sources past TTL

### Subagent Job Flow (Minions)

1. Submit via `src/core/minions/queue.ts` `MinionQueue.add()` — writes `minion_jobs` row
2. Worker (`src/core/minions/worker.ts`) claims the job via `SELECT ... FOR UPDATE SKIP LOCKED`
3. Handler dispatch: `subagent` → `src/core/minions/handlers/subagent.ts` (Anthropic Messages API tool-loop), `shell` → `src/core/minions/handlers/shell.ts`, `autopilot-cycle` → `runCycle()`
4. Subagent tool calls route through `src/core/minions/tools/brain-allowlist.ts` — subset of 13 operations, namespace-enforced slugs
5. Completion: `queue.completeJob()` writes terminal status; parent-child `child_done` inbox messages fan-in to aggregator

## Entry Points

**CLI (`src/cli.ts`)**
- Invoked as `gbrain <command>` (compiled binary at `bin/gbrain`)
- Parses global flags first (`src/core/cli-options.ts`), then command
- `CLI_ONLY` set (~50 commands) bypass the operation layer and import command modules directly via `handleCliOnly()`
- Shared operations go through `op.handler(ctx, params)` with `remote: false`
- Thin-client installs route shared ops to `callRemoteTool()` before `connectEngine()`

**MCP stdio server (`src/commands/serve.ts` → `src/mcp/server.ts`)**
- Started by `gbrain serve` (used by Claude Desktop, Cursor, etc.)
- All tool calls set `remote: true`
- `ListTools` response built from `buildToolDefs(operations)` — auto-generated from operation definitions
- Tool calls dispatched through `src/mcp/dispatch.ts`

**MCP HTTP server (`src/commands/serve-http.ts`)**
- Started by `gbrain serve --http [--port N]`
- Express 5 + OAuth 2.1 (PKCE, `client_credentials`, refresh rotation)
- `/mcp` endpoint: `requireBearerAuth` middleware → scope check → `dispatchToolCall()`
- `/admin` endpoint: React 19 SPA (`admin/dist/`) served as static files
- `/health` and `/admin/events` (SSE) endpoints
- All calls set `remote: true`; scope enforcement happens before `op.handler`

## Key Abstractions

**`BrainEngine` interface** (`src/core/engine.ts`)
- Central contract for all DB operations. ~50+ methods across lifecycle, CRUD, search, links, timeline, tags, chunks, takes, facts, jobs, eval, and admin.
- `readonly kind: 'postgres' | 'pglite'` discriminator for engine-specific branching
- `transaction<T>()` and `withReservedConnection<T>()` for session-level GUC safety

**`Operation` interface** (`src/core/operations.ts`)
- `name: string` — used as CLI command name and MCP tool name
- `params: Record<string, ParamDef>` — JSON Schema-style parameter definitions
- `handler(ctx: OperationContext, params) => Promise<unknown>` — the implementation
- `scope?: 'read' | 'write' | 'admin'` — OAuth scope required over HTTP
- `localOnly?: boolean` — ops that refuse remote callers (file_upload, sync_brain, etc.)

**`OperationContext`** (`src/core/operations.ts`)
- Carries `engine`, `config`, `logger`, `dryRun`, `remote`, `auth`, `sourceId`, `brainId`
- `remote: boolean` is required (compiler-enforced since v0.26.9)
- `allowedSlugPrefixes?: string[]` — trusted-workspace slug allow-list for dream-cycle subagents
- `takesHoldersAllowList?: string[]` — per-token filter for takes visibility

**`AIGateway`** (`src/core/ai/gateway.ts`)
- Configured once via `configureGateway(config)` at startup
- Exports `embed()`, `embedOne()`, `chat()`, `expand()` — unified interface regardless of provider
- Recipe registry (`src/core/ai/recipes/`) supports: OpenAI, Anthropic, Voyage, Google, Groq, DeepSeek, Ollama, OpenRouter, etc.
- `_shrinkState` map for adaptive batch-size safety under token-limit errors

**`MinionQueue` / `MinionWorker`** (`src/core/minions/queue.ts`, `worker.ts`)
- Postgres-native job queue (no Redis dependency)
- Parent-child DAGs, depth/child caps, per-job timeouts, idempotency keys, cascade-kill
- Protected job names (`PROTECTED_JOB_NAMES`) gate shell/subagent submission from MCP callers

## Extension Points

**AI provider recipes** (`src/core/ai/recipes/`)
- Add a new file following the `Recipe` interface shape and register in `src/core/ai/recipes/index.ts`
- Each recipe declares touchpoints (embed, expand, chat) with model lists and optional feature flags

**Minion handlers** (`src/core/minions/handlers/`)
- Register via `worker.registerHandler(name, fn)` at worker startup
- Plugin handlers loaded from `GBRAIN_PLUGIN_PATH` — must ship `gbrain.plugin.json` with `plugin_version: "gbrain-plugin-v1"`
- Shell and subagent handlers are built-in; custom handlers go in the host repo via the plugin contract

**Operations** (`src/core/operations.ts`)
- Adding a new `Operation` object and including it in the `operations` array automatically exposes it on CLI, stdio MCP, and HTTP MCP
- Scope/localOnly flags control transport availability

**Skills** (`skills/`)
- Fat markdown files (tool-agnostic) routed via `skills/RESOLVER.md` or `skills/AGENTS.md`
- `gbrain skillpack install` bundles and installs skills into agent workspaces
- `skills/conventions/` and cross-cutting `skills/_brain-filing-rules.md` are shared references

**Chunkers** (`src/core/chunkers/`)
- Three tiers: `recursive.ts` (markdown), `semantic.ts` (sentence-boundary), `code.ts` (tree-sitter, 29 languages)
- Add a new chunker by implementing the `chunkText`-compatible function signature and wiring into `importFromFile`

**Storage backends** (`src/core/storage/`)
- `local.ts`, `s3.ts`, `supabase.ts` implement a pluggable storage interface
- `storage-config.ts` routes by path prefix; `db_tracked` vs `db_only` tiers

**Brain mounts** (`src/core/brain-registry.ts`)
- `~/.gbrain/mounts.json` declares additional brain engines by mount id
- `BrainRegistry.getBrain(id)` lazily creates + caches the engine
- Operations receive the resolved engine via `ctx.engine`

---

*Architecture analysis: 2026-05-25*
