# Codebase Structure

**Analysis Date:** 2026-05-25

## Root Layout

```
gbrain/
├── src/                    # All TypeScript source code
│   ├── cli.ts              # CLI entry point (compiled to bin/gbrain)
│   ├── version.ts          # VERSION constant
│   ├── schema.sql          # Full Postgres + pgvector DDL (source of truth)
│   ├── core/               # Shared library modules
│   ├── commands/           # One file per CLI subcommand
│   ├── mcp/                # MCP protocol layer (dispatch, tool defs, HTTP)
│   ├── types/              # Shared TypeScript type definitions
│   ├── eval/               # Evaluation harnesses (LongMemEval, etc.)
│   └── assets/wasm/        # Tree-sitter WASM grammars (36 files) embedded at build time
├── test/                   # Bun test files
│   ├── *.test.ts           # Fast parallel unit tests
│   ├── *.slow.test.ts      # Cold-path tests (excluded from fast loop)
│   ├── *.serial.test.ts    # mock.module / env-contention tests (--max-concurrency=1)
│   ├── e2e/                # Real Postgres E2E tests (need DATABASE_URL)
│   ├── helpers/            # Test helpers (reset-pglite.ts, with-env.ts, cli-pty-runner.ts)
│   └── fixtures/           # Test fixture files
├── skills/                 # GBrain skills (fat markdown, tool-agnostic)
│   ├── RESOLVER.md         # Routing table (accepted alongside AGENTS.md)
│   ├── conventions/        # Cross-cutting rules (quality, brain-first, model-routing)
│   ├── migrations/         # Version migration instructions for agents
│   ├── functional-area-resolver/ # Two-layer dispatch pattern for large RESOLVER.md files
│   └── <skill-name>/       # One subdirectory per skill, each with SKILL.md
├── admin/                  # React 19 + Vite admin SPA
│   ├── src/                # SPA source (pages/, lib/)
│   └── dist/               # Built SPA — committed, served by serve-http.ts
├── scripts/                # CI guard scripts and build utilities
├── docs/                   # Documentation
│   ├── architecture/       # Architecture reference docs
│   ├── guides/             # User guides
│   ├── mcp/                # Per-client MCP setup guides
│   ├── eval/               # Eval methodology docs
│   └── ethos/              # Philosophy essays
├── recipes/                # Integration recipe YAML files
├── templates/              # SOUL.md, USER.md, ACCESS_POLICY.md, HEARTBEAT.md templates
├── evals/                  # Evaluation harnesses (functional-area-resolver A/B evals)
├── deploy/                 # Deployment config
├── bin/                    # Compiled binary output
├── package.json            # Bun package manifest
├── tsconfig.json           # TypeScript configuration
├── bunfig.toml             # Bun-specific config
├── VERSION                 # Single source of truth for version (4-segment: X.Y.Z.W)
├── gbrain.yml              # Brain repo storage tiering config (optional, in brain repo)
├── openclaw.plugin.json    # ClawHub plugin manifest
├── CLAUDE.md               # Project instructions for Claude Code
├── AGENTS.md               # Entry point for non-Claude agents
└── CHANGELOG.md            # Release history
```

## Source Layout (`src/`)

### `src/core/` — Shared library modules

The heart of the codebase. Everything in here is imported by both commands and MCP layer.

```
src/core/
├── operations.ts           # Contract-first op definitions (~2846 lines, ~47 ops)
├── operations-descriptions.ts  # Extracted tool description constants
├── engine.ts               # BrainEngine interface + supporting types (~50+ methods)
├── engine-factory.ts       # Dynamic import by config ('pglite' | 'postgres')
├── pglite-engine.ts        # PGLite (WASM Postgres 17.5) implementation (~3773 lines)
├── pglite-schema.ts        # PGLite-specific DDL (pgvector, pg_trgm, triggers)
├── postgres-engine.ts      # Postgres + pgvector implementation (~3793 lines)
├── schema-embedded.ts      # AUTO-GENERATED from schema.sql
├── db.ts                   # Postgres connection management (singleton pool)
├── config.ts               # GBrainConfig type + load/save helpers
├── types.ts                # Shared domain types (Page, PageType, SearchResult, etc.)
├── migrate.ts              # Schema migration runner + MIGRATIONS array
├── import-file.ts          # importFromFile + importFromContent pipeline
├── sync.ts                 # Pure sync functions (manifest, slug conversion, filtering)
├── link-extraction.ts      # extractEntityRefs, extractPageLinks, inferLinkType
├── markdown.ts             # Frontmatter parsing, body splitter, inferType
├── embedding.ts            # Batch embedding calls (delegates to ai/gateway.ts)
├── cycle.ts                # 11-phase brain maintenance cycle (dream/autopilot)
├── oauth-provider.ts       # GBrainOAuthProvider (OAuth 2.1 full spec)
├── sql-query.ts            # Engine-aware SQL adapter (PGLite + Postgres uniform)
├── progress.ts             # Shared bulk-action progress reporter (stderr)
├── errors.ts               # StructuredAgentError + buildError + serializeError
├── cli-options.ts          # Global flag parser (--quiet, --progress-json)
├── model-config.ts         # 4-tier model system (utility/reasoning/deep/subagent)
├── brain-registry.ts       # BrainRegistry — multi-brain engine lookup
├── mcp-client.ts           # callRemoteTool — thin-client HTTP MCP caller
├── source-resolver.ts      # Source ID resolution chain
├── destructive-guard.ts    # Soft-delete + archive lifecycle guards
├── cjk.ts                  # CJK detection/slug/tokenization utilities
├── utils.ts                # parseEmbedding, tryParseEmbedding, validateSourceId
├── backoff.ts              # Adaptive load-aware throttling
├── storage.ts              # Pluggable storage interface selector
├── storage-config.ts       # Storage tiering config (db_tracked / db_only)
│
├── ai/                     # AI gateway and provider recipes
│   ├── gateway.ts          # configureGateway, embed, chat, expand — unified seam
│   ├── types.ts            # AIGatewayConfig, Recipe, EmbeddingTouchpoint, etc.
│   ├── model-resolver.ts   # resolveRecipe, assertTouchpoint
│   ├── dims.ts             # Per-provider embedding dimension passthrough
│   ├── errors.ts           # AIConfigError, AITransientError, normalizeAIError
│   └── recipes/            # Provider-specific recipes (anthropic, openai, voyage, etc.)
│
├── chunkers/               # Content chunking strategies
│   ├── recursive.ts        # Markdown recursive chunker (MARKDOWN_CHUNKER_VERSION)
│   ├── semantic.ts         # Sentence-boundary semantic chunker
│   ├── code.ts             # Tree-sitter code chunker (29 languages)
│   └── edge-extractor.ts   # Code edge (call/def relationship) extraction
│
├── search/                 # Hybrid search pipeline
│   ├── hybrid.ts           # Vector + keyword + RRF fusion orchestrator
│   ├── expansion.ts        # Multi-query expansion via Haiku
│   ├── dedup.ts            # Result deduplication
│   ├── sql-ranking.ts      # Source-factor CASE + hard-exclude SQL builders
│   ├── source-boost.ts     # DEFAULT_SOURCE_BOOSTS + parseSourceBoostEnv
│   ├── intent.ts           # Query intent classifier (entity/temporal/event/general)
│   ├── query-cache.ts      # SemanticQueryCache (similarity threshold, knobs_hash)
│   ├── mode.ts             # Search mode bundles (conservative/balanced/tokenmax)
│   ├── token-budget.ts     # Token budget enforcement
│   ├── two-pass.ts         # Cathedral II two-pass retrieval (anchor expand + hydrate)
│   ├── eval.ts             # Retrieval eval metrics (P@k, R@k, MRR, nDCG@k)
│   ├── keyword.ts          # Keyword search helpers
│   ├── vector.ts           # Vector search helpers
│   └── telemetry.ts        # Search telemetry recording
│
├── minions/                # Postgres-native job queue
│   ├── queue.ts            # MinionQueue (submit, claim, complete, fail, stall, cascade-kill)
│   ├── worker.ts           # MinionWorker (handler registry, lock renewal, shutdown)
│   ├── supervisor.ts       # MinionSupervisor (spawn + restart gbrain jobs work)
│   ├── types.ts            # MinionJob, MinionJobInput, handler context types
│   ├── protected-names.ts  # PROTECTED_JOB_NAMES constant (shell, subagent, etc.)
│   ├── rate-leases.ts      # Outbound concurrency caps (Anthropic inflight guard)
│   ├── wait-for-completion.ts  # Poll-until-terminal helper for CLI callers
│   ├── plugin-loader.ts    # GBRAIN_PLUGIN_PATH discovery
│   ├── spawn-helpers.ts    # detectTini + buildSpawnInvocation
│   ├── transcript.ts       # Subagent message → markdown renderer
│   ├── attachments.ts      # Attachment validation
│   ├── backpressure-audit.ts  # maxWaiting coalesce event JSONL audit
│   ├── tools/
│   │   └── brain-allowlist.ts  # 13-op subagent tool registry + trusted-workspace path
│   └── handlers/
│       ├── shell.ts            # Shell job handler (/bin/sh or argv spawn)
│       ├── shell-audit.ts      # Per-submission JSONL audit trail
│       ├── subagent.ts         # LLM-loop handler (Anthropic Messages API tool-loop)
│       ├── subagent-aggregator.ts  # Fan-in aggregator handler
│       ├── subagent-audit.ts   # JSONL heartbeat + event audit
│       └── supervisor-audit.ts # Supervisor lifecycle audit
│
├── cycle/                  # Dream cycle phase implementations
│   ├── synthesize.ts       # Transcript → brain pages (Sonnet subagents)
│   ├── patterns.ts         # Cross-session theme detection
│   ├── emotional-weight.ts # computeEmotionalWeight pure function
│   ├── recompute-emotional-weight.ts  # Cycle phase orchestrator
│   ├── extract-facts.ts    # Facts fence index reconcile phase
│   ├── extract-takes.ts    # Takes fence extraction phase
│   ├── anomaly.ts          # Stats helpers for find_anomalies
│   ├── auto-think.ts       # Auto-think phase
│   ├── budget-meter.ts     # LLM cost budget tracking
│   ├── drift.ts            # Multi-source drift detection
│   ├── transcript-discovery.ts  # Filesystem walk for transcript files
│   └── phases/
│       └── consolidate.ts  # Facts consolidation phase
│
├── facts/                  # Hot-memory facts index
│   ├── extract.ts          # Fact extraction from pages
│   ├── queue.ts            # Facts extraction queue
│   ├── recall.ts           # Fact retrieval
│   ├── forget.ts           # Fact deletion
│   ├── meta-hook.ts        # _meta.brain_hot_memory injection hook
│   ├── classify.ts         # Fact kind classification
│   ├── eligibility.ts      # Facts backstop eligibility gate
│   └── ...
│
├── think/                  # Think command internals
│   ├── index.ts            # runThink orchestrator
│   ├── prompt.ts           # Prompt construction
│   ├── sanitize.ts         # INJECTION_PATTERNS, sanitizeQuery
│   └── gather.ts           # Context gathering for think
│
├── storage/                # Pluggable file storage backends
│   ├── local.ts            # Local filesystem storage
│   ├── s3.ts               # AWS S3 storage
│   └── supabase.ts         # Supabase Storage
│
├── eval/                   # Eval infrastructure
│   └── metric-glossary.ts  # Metric definitions (P@k, nDCG@k, MRR, Jaccard@k)
│
├── eval-contradictions/    # Contradiction probe infrastructure
├── cross-modal-eval/       # Cross-modal quality gate (json-repair, aggregate, runner, receipts)
├── takes-quality-eval/     # Takes quality evaluation
├── enrichment/             # Global enrichment service modules
└── entities/               # Entity consolidation (consolidate.ts, resolve.ts)
```

### `src/commands/` — CLI command implementations

One file per command (or closely related command group). Imported lazily by `handleCliOnly()` in `src/cli.ts`.

Key files:
- `serve.ts` — `gbrain serve` (stdio MCP lifecycle, signal handling, watchdog)
- `serve-http.ts` — `gbrain serve --http` (Express 5, OAuth 2.1, admin SPA, SSE)
- `sync.ts` — `gbrain sync` + `performSync` / `performFullSync` library entrypoints
- `dream.ts` — `gbrain dream` (thin alias over `runCycle`)
- `doctor.ts` — `gbrain doctor` (~35 health checks)
- `embed.ts` — `gbrain embed` (stale chunk embedding)
- `jobs.ts` — `gbrain jobs` subcommands + `gbrain jobs work` daemon
- `agent.ts` — `gbrain agent run` (submit subagent jobs)
- `init.ts` — `gbrain init` (engine setup, search mode picker)
- `upgrade.ts` — `gbrain upgrade` (self-update + migration runner)
- `apply-migrations.ts` — `gbrain apply-migrations`
- `import.ts` — `gbrain import` (direct file import, parallel workers)
- `extract.ts` — `gbrain extract links|timeline|all`
- `think.ts` — `gbrain think` (inline LLM reasoning with brain context)
- `auth.ts` — `gbrain auth create|list|revoke|register-client` (token management)
- `models.ts` — `gbrain models` routing dashboard + `gbrain models doctor`
- `takes.ts` — `gbrain takes` CRUD
- `sources.ts` — `gbrain sources` multi-source management
- `migrations/` — TypeScript migration orchestrators (v0_11_0.ts, v0_12_0.ts, etc.)

### `src/mcp/` — MCP protocol layer

```
src/mcp/
├── server.ts           # stdio MCP server (startMcpServer, handleToolCall)
├── dispatch.ts         # dispatchToolCall, buildOperationContext, validateParams, summarizeMcpParams
├── tool-defs.ts        # buildToolDefs — convert Operation[] to MCP tool definitions
├── http-transport.ts   # Legacy simple bearer-auth HTTP (superseded by serve-http.ts)
└── rate-limit.ts       # BoundedLRU token-bucket limiter (pre-auth IP + post-auth token)
```

### `src/eval/` — Evaluation harnesses

```
src/eval/
├── longmemeval/        # LongMemEval benchmark harness
│   ├── harness.ts
│   ├── adapter.ts
│   └── sanitize.ts
```

## Key Files

**Entry Points:**
- `src/cli.ts` — CLI main, command dispatch, thin-client routing, `connectEngine()` (1554 lines)
- `src/mcp/server.ts` — stdio MCP server startup
- `src/commands/serve-http.ts` — HTTP MCP server with OAuth 2.1 (1083 lines)

**Contracts:**
- `src/core/operations.ts` — ~47 operation definitions, `OperationContext`, `Operation`, `OperationError` (2846 lines)
- `src/core/engine.ts` — `BrainEngine` interface + all supporting types
- `src/core/types.ts` — `Page`, `PageType`, `SearchResult`, `Chunk`, domain types

**Database:**
- `src/schema.sql` — Full Postgres DDL (~850+ lines, 30+ tables)
- `src/core/schema-embedded.ts` — Auto-generated from schema.sql
- `src/core/pglite-schema.ts` — PGLite-specific schema variant
- `src/core/pglite-engine.ts` — PGLite implementation (3773 lines)
- `src/core/postgres-engine.ts` — Postgres implementation (3793 lines)
- `src/core/migrate.ts` — Migration runner + `MIGRATIONS` array (DDL versions 1-60+)

**AI / Search:**
- `src/core/ai/gateway.ts` — Unified AI gateway (embed, chat, expand)
- `src/core/search/hybrid.ts` — RRF hybrid search orchestrator
- `src/core/import-file.ts` — importFromFile / importFromContent

**Brain Maintenance:**
- `src/core/cycle.ts` — 11-phase dream cycle
- `src/core/sync.ts` — git-diff-driven sync

**Configuration:**
- `src/core/config.ts` — `GBrainConfig`, `loadConfig()`, `gbrainPath()`
- `VERSION` — 4-segment version string (single source of truth)
- `gbrain.yml` — Optional brain-repo storage tiering config

**Skills:**
- `skills/RESOLVER.md` — Routing table (trigger phrases → skill names)
- `skills/_brain-filing-rules.md` — Cross-cutting brain filing rules
- `skills/conventions/` — Model routing, quality, brain-first conventions

## Naming Conventions

**Files:**
- `kebab-case.ts` for all source files (`pglite-engine.ts`, `serve-http.ts`, `import-file.ts`)
- `*.test.ts` for parallel unit tests
- `*.slow.test.ts` for cold-path tests excluded from fast loop
- `*.serial.test.ts` for tests that use `mock.module()` or share file-level state
- `e2e/*.test.ts` for real-Postgres E2E tests

**Operations (in `operations.ts`):**
- `snake_case` for operation names used as MCP tool names (`get_page`, `put_page`, `find_experts`)
- `kebab-case` for CLI hints (`cliHints.name`) when different from op name

**TypeScript:**
- `PascalCase` for interfaces and classes (`BrainEngine`, `MinionQueue`, `GBrainConfig`)
- `camelCase` for functions and variables (`importFromFile`, `hybridSearch`)
- `UPPER_SNAKE_CASE` for module-level constants (`MAX_SEARCH_LIMIT`, `PROTECTED_JOB_NAMES`)

**Database tables:**
- `snake_case` plural (`pages`, `content_chunks`, `minion_jobs`, `oauth_tokens`)

## Module Boundaries

**Core → never imports Commands:**
`src/core/` modules are a shared library. They never import from `src/commands/`. Commands import from core. This is the primary layering rule.

**Operations → imports Core only:**
`src/core/operations.ts` imports from other `src/core/` modules (engine.ts, search/hybrid.ts, import-file.ts, etc.) but never from `src/commands/`.

**MCP layer → imports Core and Operations:**
`src/mcp/dispatch.ts` imports `operations` from `src/core/operations.ts` and `BrainEngine` from `src/core/engine.ts`.

**CLI → imports Commands + Core:**
`src/cli.ts` imports lazily from `src/commands/` via dynamic imports inside `handleCliOnly()`. It also imports directly from `src/core/` for shared utilities (`config.ts`, `operations.ts`, `mcp-client.ts`).

**Minions → imports Core only:**
`src/core/minions/` imports `BrainEngine` and domain types from `src/core/` but never from `src/commands/`.

**Import path aliases:**
None configured. All imports use relative paths with `.ts` extensions (Bun native resolution).

**Public exports (package.json subpath exports):**
`gbrain/engine`, `gbrain/types`, `gbrain/operations`, `gbrain/pglite-engine`, `gbrain/link-extraction`, `gbrain/import-file`, `gbrain/transcription`, `gbrain/embedding`, `gbrain/config`, `gbrain/markdown`, `gbrain/backoff`, `gbrain/search/hybrid`, `gbrain/search/expansion`, `gbrain/extract` — consumed by the sibling `gbrain-evals` repo.

## Where to Add New Code

**New operation (CLI + MCP):**
1. Define the handler function in `src/core/operations.ts`
2. Add to the `operations` array at the bottom of `src/core/operations.ts`
3. Set `scope`, `localOnly`, and `cliHints` as appropriate

**New CLI-only command:**
1. Create `src/commands/<command-name>.ts`
2. Add to `CLI_ONLY` set in `src/cli.ts`
3. Add a `case '<command-name>':` in the `handleCliOnly()` switch in `src/cli.ts`

**New dream cycle phase:**
1. Create phase logic in `src/core/cycle/<phase-name>.ts`
2. Add to `CyclePhase` union and `ALL_PHASES` array in `src/core/cycle.ts`
3. Add the phase runner case in `runCycle()`

**New AI provider:**
1. Create `src/core/ai/recipes/<provider-name>.ts` implementing `Recipe` + touchpoints
2. Register in `src/core/ai/recipes/index.ts`

**New Minion job handler:**
1. Create `src/core/minions/handlers/<handler-name>.ts`
2. Register in `src/commands/jobs.ts` inside `registerBuiltinHandlers()` or via plugin

**New unit test:**
- Place as `test/<module-name>.test.ts`
- Use canonical PGLite block from `test/helpers/reset-pglite.ts` if DB needed
- Use `withEnv()` from `test/helpers/with-env.ts` instead of direct `process.env` mutation

**New E2E test:**
- Place as `test/e2e/<feature-name>.test.ts`
- Gate with `if (!process.env.DATABASE_URL) { ... }` skip block

---

*Structure analysis: 2026-05-25*
