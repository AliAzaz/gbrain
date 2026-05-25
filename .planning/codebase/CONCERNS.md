# Technical Concerns

**Analysis Date:** 2026-05-25

---

## Critical Issues

### P1: `gbrain query <common-keyword>` infinite loop / memory spiral
- **Symptoms:** `gbrain query the` pegged at 99% CPU for 7 days, 6+ GB RSS before manual kill (TODOS.md:139-168)
- **Files:** `src/core/search/expansion.ts`, `src/core/search/hybrid.ts`
- **Root cause candidates:** catastrophic regex backtracking on single-word query expansion, RRF loop on non-shrinking result set, `postgres.js` cursor that never closes on large results
- **Risk:** Silent production DoS. Any user with >5K pages and an ambiguous keyword can hang their terminal session indefinitely
- **Status:** Explicitly deferred ("out of scope") in TODOS.md; no fix yet

### P1: Duplicate `validateSourceId` with divergent regex
- **Files:** `src/core/utils.ts:57` (`/^[a-z0-9_-]+$/`) vs `src/core/sources-ops.ts:145` (`/^[a-z][a-z0-9-]{0,31}$/` per `SOURCE_ID_RE`)
- **Risk:** The private `sources-ops.ts` copy enforces `^[a-z]` anchor and 32-char cap; the exported `utils.ts` copy does not. Callers of the exported version silently accept IDs that `sources-ops.ts` would reject, creating inconsistent validation across the codebase
- **Fix:** Remove the private copy from `sources-ops.ts`; import from `utils.ts` with a tighter regex there

### Budget meter bypasses non-Anthropic models silently
- **File:** `src/core/cycle/budget-meter.ts:94-99`
- **Issue:** `BudgetMeter` emits a one-time stderr warning and then allows unlimited LLM submits for any model not in `ANTHROPIC_PRICING`. This means OpenAI GPT-4o, Google Gemini, or any third-party model used in dream cycles and drift phases has **no cost cap**
- **Code:** `Budget gate disabled for this submit. (Per-provider pricing modules: TODO v0.29.)`
- **Status:** Marked TODO v0.29 but still present in current code

---

## Technical Debt

### 57+ schema migrations in a single file
- **File:** `src/core/migrate.ts` (3,186 lines, 53+ migration entries)
- **Issue:** Every schema migration is appended to one monolithic array. The file is approaching 3,200 lines. Forward-reference bootstrap code (`applyForwardReferenceBootstrap`) in both `pglite-engine.ts` and `postgres-engine.ts` manually probes for 10+ specific column states — adding a new column requires updating two engine files and the bootstrap probe list or hitting the "upgrade-wedge" class that has bitten users 10+ times
- **Risk:** High cognitive load for contributors; easy to miss a bootstrap probe site

### `extract.ts` redundant `walkMarkdownFiles` call
- **File:** `src/commands/extract.ts:486`
- **Issue:** `extractForSlugs` calls `walkMarkdownFiles(brainDir)` at line 486 solely to build `allSlugs` for link resolution — a full directory walk even when only a small incremental slug set needs processing. TODOS.md notes this should be replaced with `engine.getAllSlugs()` but it is still present
- **Impact:** On 200K-page brains this is ~400K extra syscalls per incremental extract run

### `file_url` operation returns a fake non-URL
- **File:** `src/core/operations.ts:1923`
- **Issue:** `file_url` handler has `// TODO: generate signed URL from Supabase Storage` and returns `gbrain:files/${storage_path}` — a non-HTTP URI scheme that no browser or SDK can follow. The operation is `admin + localOnly`, but any code calling this expecting a real URL will silently receive an unusable value
- **Code:** `return { storage_path: rows[0].storage_path, url: \`gbrain:files/${rows[0].storage_path}\` };`

### `eval-cross-modal` missing `--budget-usd` cap
- **File:** `src/commands/eval-cross-modal.ts:16`
- **Issue:** Comment explicitly marks it: `--budget-usd hard cap is a v0.27.x follow-up TODO`. No maximum spend is enforced. Default cycles=3 in TTY, 1 in non-TTY, but scripted loops can accumulate uncapped costs across Opus 4.7 + GPT-4o + Gemini calls

### Static pricing tables drift
- **Files:** `src/core/anthropic-pricing.ts`, `src/core/embedding-pricing.ts`, `src/core/cross-modal-eval/runner.ts:327`
- **Issue:** All cost estimates are hardcoded constants. Model pricing updates (Opus 4.7 price was already wrong at $15/$75 → corrected to $5/$25 in v0.31.12) will silently produce wrong estimates until manually discovered. TODOS.md acknowledges a `gbrain prices refresh` skill is needed but not yet built

### `gray-matter` still used for core parsing
- **Files:** `src/core/markdown.ts:1`, `src/core/minions/plugin-loader.ts:35`, `src/commands/integrations.ts:22`
- **Issue:** `storage-config.ts` explicitly replaced `gray-matter` because "it silently returned `{data: {}}` on delimiter-less YAML and broke the entire feature on every install." The same library is still imported in 3 other files for frontmatter parsing. Any YAML file lacking the opening `---` delimiter fed to these paths will silently produce empty data

### `walkMarkdownFiles` used 4 times in `extract.ts` for separate passes
- **File:** `src/commands/extract.ts:486,582,645,708`
- Each call is a full recursive `readdirSync` walk. Four separate passes over the same directory tree in sequence is unnecessary

### Multi-source code duplicated between engines
- **Files:** `src/core/postgres-engine.ts` (~3,793 lines), `src/core/pglite-engine.ts` (~3,773 lines)
- Both engines implement all 40+ `BrainEngine` methods independently. Schema parity is CI-guarded (`test/helpers/schema-diff.ts`) but logic parity is not. Bugs fixed in one engine have been missed in the other (e.g., PR #860's `listAllPageRefs` fix required changes in both files). The `scripts/check-source-id-projection.sh` guard was added precisely because of this pattern

---

## Security Concerns

### Open CORS on `/mcp`, `/token`, `/authorize`, `/register`, `/revoke`
- **File:** `src/commands/serve-http.ts:230-234`
- **Issue:** `app.use('/mcp', cors())` — no `origin` restriction. Any website on the internet can make cross-origin requests to these endpoints. The `/mcp` endpoint handles authenticated tool calls. The `/authorize` endpoint initiates OAuth flows
- **Impact:** CSRF-adjacent risk: an attacker page that obtains a valid OAuth token (e.g., via PKCE in a browser context) can call `/mcp` from any origin

### No HTTP security headers (`helmet` absent)
- **File:** `src/commands/serve-http.ts`
- **Issue:** No `Content-Security-Policy`, no `X-Frame-Options`, no `Strict-Transport-Security`, no `X-Content-Type-Options`. The admin SPA at `/admin` serving React 19 has no CSP protection
- **Recommendation:** Add `helmet` middleware before route registration

### Shell injection in `transcription.ts` via `ffprobe`/`ffmpeg`
- **File:** `src/core/transcription.ts:178-192`
- **Issue:** `audioPath` is interpolated directly into an `execSync` shell string:
  ```
  `ffprobe -v error ... "${audioPath}"`
  `ffmpeg -i "${audioPath}" ... "${tmpDir}/segment_%03d${ext}"`
  ```
  If `audioPath` contains `$(...)` or backticks, this executes arbitrary commands. The path originates from user-supplied `file_upload`, which goes through `validateUploadPath`, but the quoting relies entirely on double-quote wrapping which can be escaped with `"` in the filename
- **Recommendation:** Use `execFileSync` with argv array to avoid shell interpretation entirely

### `trust proxy: 'loopback'` may expose real IP on Fly.io/k8s
- **File:** `src/commands/serve-http.ts:220`
- **Issue:** `app.set('trust proxy', 'loopback')` trusts `X-Forwarded-For` only from loopback addresses. On Fly.io and Kubernetes, the proxy is a different node, not `127.0.0.1`. Rate limiting keyed on `req.ip` may use the proxy's IP instead of the real client IP, neutralizing the IP-bucket rate limiter
- **Impact:** Pre-auth IP rate limiter (30 req/60s) is the first defense against brute-force on `/token`; if it sees the same proxy IP for all clients, one busy client exhausts the bucket for all clients on that node

### `GBRAIN_ALLOW_SHELL_JOBS=1` documented but undersupervised
- **File:** `src/core/minions/handlers/shell.ts`, `src/core/minions/supervisor.ts:449`
- **Issue:** Setting `GBRAIN_ALLOW_SHELL_JOBS=1` enables arbitrary shell command execution on the worker process. The shell handler uses `/bin/sh -c cmd` with an allowlisted env, but `cmd` comes from the `minion_jobs` table. Any SQL-injection or insecure job-submission path that writes to `minion_jobs` with a crafted `cmd` bypasses the MCP-level guards
- **Current mitigation:** Protected job names require `allowProtectedSubmit: true`; the `shell` job name is not in `PROTECTED_JOB_NAMES`. But a `shell` job submitted via the Postgres-level queue (direct SQL INSERT) would execute on a worker with the flag set

### Prompt injection surface not fully covered by `INJECTION_PATTERNS`
- **File:** `src/core/think/sanitize.ts`
- **Issue:** The 14-pattern `INJECTION_PATTERNS` list addresses common jailbreak phrases. More sophisticated injections using Unicode lookalikes, base64 payloads, or indirect prompt injection via retrieved content (where the injected text arrives through a `search` result, not a direct `take`) are not covered. The pattern set is explicitly acknowledged as "~95% of trivial injections"
- **Note:** LongMemEval harness reuses the same patterns but the search pipeline returning content to agents does not apply them

---

## Performance Concerns

### Postgres CJK FTS returns empty results
- **File:** `src/core/pglite-engine.ts:828`, `src/core/postgres-engine.ts` (no CJK path)
- **Issue:** Postgres keyword search uses `to_tsvector('english', ...)` which cannot segment CJK text. The ILIKE fallback implemented in v0.32.7 exists only for PGLite. Multi-tenant Postgres deployments silently return zero keyword results for any Chinese/Japanese/Korean query
- **Impact:** High for Postgres users with CJK content; invisible at deploy time (no error, just empty results)
- **Status:** TODOS.md explicitly defers until "users complain"

### E2E tests are sequential (5–10 min)
- **File:** `scripts/run-e2e.sh`, `bun run test:e2e`
- **Issue:** All 29 E2E files run sequentially. "Template-DB parallelization is a v0.27+ TODO" per CLAUDE.md. On a Mac dev box, this takes 5–10 minutes for every full pre-ship gate
- **Impact:** Slows CI feedback loop and discourages running E2E before pushing

### `walkMarkdownFiles` called 4× per extract run
- **File:** `src/commands/extract.ts` (lines 486, 582, 645, 708)
- Each invocation is a full recursive `readdirSync` walk. On a 200K-file brain repo this is ~800K–1.6M syscalls per `gbrain extract` invocation

### `getStats()` under heavy load causes /health 503
- **File:** `src/commands/serve-http.ts:56-82`
- **Issue:** `/health` races `engine.getStats()` (6× `COUNT(*)` queries) against a 3-second timeout. On brains with 96K+ pages through PgBouncer, this previously triggered orchestrator restart cascades (Fly.io seeing 503). The `/health` endpoint was fixed in v0.28.10 to use `SELECT 1` liveness, but `/admin/api/full-stats` still calls `probeHealth(engine)` with the heavy stats query through `requireAdmin` middleware — an authenticated attacker or a misconfigured monitoring tool hitting `/admin/api/full-stats` repeatedly can still trigger pool saturation

### Anthropic pricing table only: non-Anthropic models bypass budget gate
- **File:** `src/core/cycle/budget-meter.ts`
- `ANTHROPIC_PRICING` covers Anthropic models only. All OpenAI, Google, Voyage, MiniMax models produce `cost = null` → `unpricedSubmitsThisCycle++` but no abort. Large OpenAI embedding batches in the dream cycle have no budget ceiling

---

## Dependency Risks

### `@electric-sql/pglite` pinned at `0.4.3` (exact, not caret)
- **File:** `package.json:83`
- Pinned without `^`, meaning security patches to pglite must be manually tracked and bumped. PGLite embeds Postgres 17.5 via WASM — any Postgres CVE affecting the WASM build requires a manual dep update
- **Risk:** Users running the binary build get the exact 0.4.3 WASM blob with no automatic updates

### `@modelcontextprotocol/sdk` pinned at `1.29.0` (exact)
- **File:** `package.json:86`
- The MCP SDK is moving rapidly. Exact pins prevent auto-uptake of security or breaking-change fixes but also mean the codebase may accumulate auth/protocol drift without it being visible

### `tree-sitter-wasms` and `web-tree-sitter` pinned at old exact versions
- **Files:** `package.json:100-101` — `tree-sitter-wasms: 0.1.13`, `web-tree-sitter: 0.22.6`
- 36 WASM grammar blobs committed to `src/assets/wasm/` are tied to these exact versions. Any grammar CVE or Bun WASM ABI change requires a coordinated update of all 36 files + the compiled binary

### `ai` (Vercel AI SDK) and `@ai-sdk/*` on caret `^`
- **File:** `package.json:77-80,87`
- `"ai": "^6.0.168"` — major version 6 with caret allows any 6.x.y. Multiple security/breaking fixes to the AI SDK transport layer have shipped between patch versions. The gateway (`src/core/ai/gateway.ts`) monkey-patches the Voyage HTTP layer with `voyageCompatFetch`; an AI SDK minor that changes the fetch intercept shape would silently break Voyage embeddings

### `express: "^5.1.0"` (Express 5 is RC-quality)
- **File:** `package.json:91`
- Express 5 was in beta/RC for years; the caret allows any 5.x. The HTTP server relies on Express 5-specific behavior (`next` call semantics, `res.json` shape changes). A breaking Express 5.x minor could affect the OAuth token endpoint or the admin routes

### `gray-matter` known to silently return empty on delimiter-less YAML
- **File:** `package.json:95`
- The library has a documented silent-failure mode (no delimiter → `{data: {}}`). Three import sites remain in the codebase despite the issue being identified and worked around in `storage-config.ts`. No plan to replace the remaining usages

---

## Test Coverage Gaps

### No test for `src/commands/jobs.ts` (1,180-line daemon entrypoint)
- `jobs.ts` is the worker daemon (`gbrain jobs work`), job submission CLI, and autopilot-cycle handler. It has no matching test file. The worker's lifecycle (shutdown/disconnect ownership) was the subject of a recent bug fix (v0.28.1) with no regression test for the `jobs.ts` dispatch path itself

### No test for `src/commands/migrate-engine.ts`
- Bidirectional engine migration (`pglite ↔ supabase`) has no unit or integration test. This is a destructive operation: data loss on a failed migration would be catastrophic

### No test for `src/core/oauth-provider.ts`
- The OAuth 2.1 provider is a security-critical module. `test/oauth.test.ts` covers it via the higher-level HTTP E2E test, but there is no direct unit test for the provider class itself. SQL-level behavior (token rotation, sweep, DCR) is only tested through the E2E server spawn

### No test for `src/commands/eval-cross-modal.ts`
- The cross-modal eval runner has no test file. It calls three different LLM providers and writes receipt files. The aggregation logic is tested via `test/` but the CLI dispatch and `--budget-usd` path are untested

### No test for `src/core/cycle/transcript-discovery.ts`
- Transcript discovery drives the dream cycle's synthesize phase. No test file. The `isDreamOutput` guard and exclude-pattern matching are only covered transitively via `test/cycle-synthesize.test.ts`

### No test for `src/core/search/expansion.ts` or `src/core/search/source-boost.ts`
- Multi-query expansion (Haiku calls for query reformulation) and source-boost configuration have no dedicated test files. The P1 infinite-loop bug candidate lives in `expansion.ts`

### Migration orchestrators `v0_28_0.ts`, `v0_29_1.ts`, `v0_18_0.ts`, `v0_18_1.ts` have no tests
- These orchestrators run destructive or schema-altering SQL. No test files. Tests exist for v0_11_0 and v0_12_2 orchestrators; newer ones are untested

### E2E tests skip gracefully when `DATABASE_URL` is unset — coverage gap in CI
- Several unit tests marked `*.test.ts` (not `*.e2e.test.ts`) depend on having a live Postgres. Without `DATABASE_URL`, they silently skip rather than fail. This creates false-green CI on Postgres-only paths in the pull request diff

---

## Architectural Concerns

### Two 3,700-line engine files with manually-kept parity
- **Files:** `src/core/postgres-engine.ts` (3,793 lines), `src/core/pglite-engine.ts` (3,773 lines)
- Every BrainEngine method is implemented twice. A CI guard (`scripts/check-source-id-projection.sh`) covers one specific divergence class. Logical bugs (wrong JOIN, wrong WHERE clause) in a method implemented in both engines are not automatically caught. The v0.32.8 multi-source fix, the v0.22.1 stale-chunk fix, and the v0.22.6.1 bootstrap fix all required parallel changes in both files

### `src/core/operations.ts` is a 2,846-line operation registry
- All ~47 operations, their params, scopes, trust-boundary logic, and handlers live in a single file. The file mixes type definitions, security enforcement, and business logic. New contributors must read and understand the entire file before safely adding an operation. The trust-boundary enforcement (`ctx.remote !== false`) is scattered across dozens of handlers without a common gateway

### `src/core/migrate.ts` is a 3,186-line monolith
- 57+ migrations stored in one array, with a 600-line `applyForwardReferenceBootstrap` function and a complex `runMigrations` runner. Adding migration v58 requires understanding the full file structure. The forward-reference bootstrap probes must be manually extended for any new column-with-index

### Postgres connection pool default of 10 causes MaxClients on Supabase
- **File:** `src/core/db.ts:11-14`
- Supabase transaction pooler has a low connection limit. The default pool of 10 causes `MaxClients` errors when `gbrain upgrade` spawns subprocesses. Users must manually set `GBRAIN_POOL_SIZE=2`. This is a known footgun documented in CLAUDE.md but not surfaced to users at `gbrain init` time

### Trust-boundary enforcement is distributed across 10+ handler sites
- **File:** `src/core/operations.ts`
- The pattern `ctx.remote !== false` (trust-closed semantics, v0.26.9) is manually repeated at 4+ critical call sites. A new operation that copies a handler without including the remote check silently degrades to permissive behavior. There is no shared middleware that enforces this at the dispatch layer

### `src/cli.ts` is a 1,554-line dispatch table
- Every command is dispatched via a long chain of `if (command === '...')` blocks. The CLI routing is not tested as a unit — routing correctness is verified through higher-level tests. Adding a new command requires knowing the full dispatch order to avoid shadowing

### `src/commands/sync.ts` N+1 pattern in `resolveSlugByPathOrSourcePath`
- **File:** `src/commands/sync.ts:960`
- Comment: `TODO(multi-source): runEmbed → src/commands/embed.ts:175 + :418 call sites silently default to source_id='default' for non-default-source pages`
- Multi-source embed after sync does not thread `sourceId`, so embeddings for non-default sources are silently associated with the wrong source

---

## Operational Concerns

### 30+ undocumented `GBRAIN_*` environment variables
- Variables like `GBRAIN_ALLOW_SHELL_JOBS`, `GBRAIN_SEARCH_DEBUG`, `GBRAIN_LME_DEBUG`, `GBRAIN_CONTRIBUTOR_MODE`, `GBRAIN_NO_REEMBED`, `GBRAIN_REEMBED_GRACE_SECONDS`, `GBRAIN_SYNC_FRESHNESS_WARN_HOURS`, `GBRAIN_DRIFT_LIMIT`, `GBRAIN_DRIFT_TIMEOUT_MS`, `GBRAIN_NO_GITIGNORE`, `GBRAIN_NO_BANNER`, `GBRAIN_DIRECT_DATABASE_URL` are read from `process.env` in scattered locations with no central registry or `--help` exposure. A misconfigured `.env` silently changes security-relevant behavior

### PGLite WASM crash on macOS 26.3 produces opaque error
- **File:** `src/core/pglite-engine.ts:173`
- Known macOS WASM bug (#223). The error is caught and a human-readable message emitted, but the bug exists in the macOS kernel's WASM JIT. Users on affected macOS versions must use Postgres instead of PGLite; there is no automated fallback or detection

### No backup/recovery CLI
- GBrain uses the brain repo's git history as its source of truth for markdown content. But `pages` table data (frontmatter, auto-extracted links, takes, emotional weights, vector embeddings) are not in git. `gbrain export` exists for specific page types, but there is no `gbrain backup` command that snapshots the full DB state. A corrupted PGLite file or a bad migration that drops data has no first-party recovery path

### Pricing tables in two separate files risk divergence
- **Files:** `src/core/anthropic-pricing.ts`, `src/core/embedding-pricing.ts`
- Already diverged once (Opus 4.7 was wrong in `anthropic-pricing.ts`). No automation confirms that the prices match Anthropic's published rates. The `cross-modal-eval` runner now reads from `ANTHROPIC_PRICING` to avoid the drift, but the embedding pricing table is separate and has no guard

### `--log-full-params` default-off means request bodies are invisible to operators
- **File:** `src/commands/serve-http.ts`
- The default `summarizeMcpParams` redaction in `mcp_request_log` means operators cannot see what operations agents are calling, only the bucketed byte-size and declared-key list. Debugging agent misbehavior in production requires restarting the server with `--log-full-params`, which logs raw params to stderr

### `openclaw-AGENTS.md` deleted from repo root (active git status)
- **Git status:** `D openclaw-AGENTS.md` appears in the current `git status`. This file serves as the non-Claude agent routing entry point. Deleting it breaks any agent configured to look for `AGENTS.md` at the repo root for gbrain's own skill routing

---

## Recommended Focus Areas

### 1. P1: `gbrain query` infinite loop (TODOS.md:139)
Any user with a large brain can reproduce this. 99% CPU + 6 GB RSS for 7 days is a data point from production. Add a `MAX_EXPANSION_TERMS` hard limit in `src/core/search/expansion.ts` and a per-run result-set size cap in `src/core/search/hybrid.ts` to break the loop. Add a regression test reproducing the single-keyword case.

### 2. Shell injection in `src/core/transcription.ts`
Replace `execSync(\`ffprobe -v error ... "${audioPath}"\`)` with `execFileSync('ffprobe', [...args])` at lines 178-192 and 225. This is a small change with high security impact. Same fix needed for `ffmpeg` at line 191.

### 3. Open CORS on `/mcp` and OAuth endpoints
Change `cors()` to `cors({ origin: allowlist })` in `src/commands/serve-http.ts:230-234`. For self-hosted deployments, the origin should default to the `--public-url` value. Add `helmet()` for security headers.

### 4. Duplicate `validateSourceId` with divergent regex
Consolidate `src/core/sources-ops.ts:145` to import from `src/core/utils.ts:57`. The two regexes (`/^[a-z0-9_-]+$/` vs the stricter version in `sources-ops.ts`) produce different validation behavior depending on which code path handles the source ID.

### 5. Budget gate for non-Anthropic models in `budget-meter.ts`
Add pricing entries for OpenAI and Google models to a unified pricing module (or at minimum, fail-closed when `cost === null` rather than fail-open with a warning). The `(Per-provider pricing modules: TODO v0.29.)` comment has been in the code since v0.29; it is now v0.33+.

---

*Concerns audit: 2026-05-25*
