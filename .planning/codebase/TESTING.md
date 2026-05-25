# Testing

**Analysis Date:** 2026-05-25

## Test Framework & Runner

**Framework:** Bun's built-in test runner (`bun:test`)
**Runtime:** Bun `>=1.3.10`
**Config:** `bunfig.toml` — sets global `timeout = 60_000` (PGLite WASM cold-start requires ~20s)

**Assertion API:** `expect` from `bun:test` — Jest-compatible API.
- `.toBe()`, `.toEqual()`, `.toContain()`, `.toBeNull()`, `.toBeTruthy()`, `.toBeFalsy()`
- `.toBeCloseTo(val, precision)` for floating-point math tests
- `.toThrow()`, `.rejects.toThrow()` for error assertions
- `.toHaveLength()`, `.toStartWith()`, `.toMatch()`, `.toBeGreaterThan()`
- No separate assertion library installed

**Run Commands:**
```bash
bun run test                 # Parallel 8-shard unit fast loop (+ serial pass at end)
bun run test:e2e             # All E2E tests sequentially (requires DATABASE_URL)
bun run test:slow            # *.slow.test.ts only
bun run test:serial          # *.serial.test.ts at --max-concurrency=1
bun run test:full            # verify + unit + slow + [e2e if DATABASE_URL set]
bun run verify               # Pre-push gate: type-check + CI shell guards (no tests)
bun test test/foo.test.ts    # Run single file
```

## Test Organization

**Test root:** `test/` (co-located with `src/`, not inside it)

**File structure:**
```
test/
├── *.test.ts               # Unit tests (386 files) — fast parallel shard
├── *.serial.test.ts        # Serial quarantine (19 files) — run after parallel
├── *.slow.test.ts          # Slow intentional tests (1 file) — separate pass
├── e2e/                    # Real-Postgres E2E tests (88 files)
│   ├── *.test.ts
│   └── helpers.ts          # DB lifecycle, fixture imports, timing utilities
├── helpers/                # Shared test utilities
│   ├── with-env.ts         # withEnv() helper for safe env mutation
│   ├── reset-pglite.ts     # TRUNCATE + re-seed for per-test PGLite reset
│   ├── schema-diff.ts      # Cross-engine schema parity diffing
│   └── schema-diff.test.ts # Tests of the schema diff helper itself
├── fixtures/               # Static test data
│   ├── whoknows-eval.jsonl
│   ├── longmemeval-mini.jsonl
│   ├── contradictions-mini.jsonl
│   ├── notability-eval-public.jsonl
│   ├── images/             # tiny.avif, tiny.heic
│   ├── openclaw-reference-minimal/  # AGENTS.md workspace fixture
│   └── claw-test-scenarios/         # fresh-install + upgrade-from-v0.18
├── ai/                     # AI gateway tests
│   ├── gateway.test.ts
│   ├── gateway-chat.test.ts
│   ├── recipe-*.test.ts    # Per-provider recipe tests
│   └── *.serial.test.ts
├── scripts/                # Tests of the CI scripts themselves
│   ├── check-test-isolation.test.ts
│   ├── run-unit-parallel.test.ts
│   └── run-unit-shard.test.ts
└── core/
    └── cycle.serial.test.ts
```

**E2E fixtures** at `test/e2e/fixtures/`: markdown files organized as a real brain (`people/`, `companies/`, `concepts/`, `meetings/`, `deals/`, `projects/`, `sources/`, `large/`, `apple-notes/`).

**Naming conventions:**
- `<subject>.test.ts` — unit test for `src/core/<subject>.ts` or `src/commands/<subject>.ts`
- `<feature>-<aspect>.test.ts` — targeted sub-area tests (e.g., `eval-contradictions-judge.test.ts`)
- `migrations-v0_12_0.test.ts` — migration-specific tests named after version
- `*.serial.test.ts` — quarantine suffix for files that use `mock.module()` or genuinely share env state
- `*.slow.test.ts` — intentionally cold-path tests excluded from fast loop

## Test Categories

### Unit Tests (`test/*.test.ts` + `test/ai/*.test.ts`)

**386 files.** No database, no network, no API keys required. Run in 8 parallel shards.

Scope — each file tests a single module or feature area:
- Pure functions: `markdown.test.ts`, `search.test.ts`, `sync.test.ts`, `sql-ranking.test.ts`, `emotional-weight.test.ts`, `whoknows.test.ts`
- Engine behavior against in-memory PGLite: `pglite-engine.test.ts`, `minions.test.ts`, `oauth.test.ts`
- CLI structure/registration: `cli.test.ts`, `doctor.test.ts` (source-code structural assertions)
- Security contracts: `file-upload-security.test.ts`, `trust-boundary-contract.test.ts`, `mcp-dispatch-summarize.test.ts`
- Migration DDL shape: `migrate.test.ts`, `migrations-v0_12_0.test.ts`, etc.
- Contract/parity tests: `parity.test.ts`, `public-exports.test.ts`, `operations-descriptions.test.ts`

### Serial Tests (`test/*.serial.test.ts`)

**19 files.** Run after parallel pass at `--max-concurrency=1`. Required when:
- `mock.module(...)` is used (affects the entire shard process)
- Tests genuinely share module-level state across `it()` boundaries

Examples: `embed.serial.test.ts`, `cycle.serial.test.ts` (uses `mock.module`), `eval-takes-quality-runner.serial.test.ts`, `brain-registry.serial.test.ts`.

### E2E Tests (`test/e2e/*.test.ts`)

**88 files.** Require `DATABASE_URL` (real Postgres + pgvector). Run sequentially (one file at a time) to avoid TRUNCATE CASCADE races. Skip gracefully when `DATABASE_URL` is unset.

Scope:
- Full operation pipeline against Postgres: `mechanical.test.ts` (all ~47 ops)
- Search quality and source-boost behavior: `search-quality.test.ts`, `search-swamp.test.ts`, `search-exclude.test.ts`
- Engine parity (Postgres vs PGLite): `engine-parity.test.ts`, `schema-drift.test.ts`
- Dream cycle phases end-to-end: `dream.test.ts`, `dream-synthesize-pglite.test.ts`
- OAuth/HTTP server: `serve-http-oauth.test.ts`, `serve-http-meta.test.ts`
- Migrations against real DB: `migration-v35-auto-rls.test.ts`, `migrate-chain.test.ts`
- Multi-source scenarios: `multi-source-bug-class.test.ts`, `multi-source.test.ts`
- Worker/supervisor lifecycle: `worker-abort-recovery.test.ts`, `zombie-reaping.test.ts`

### Slow Tests (`test/*.slow.test.ts`)

**1 file** (`test/scripts/test-shard.slow.test.ts`). Intentional cold-path correctness checks excluded from the main fast loop.

## Test Utilities

### `test/helpers/with-env.ts` — `withEnv(overrides, fn)`

Safe env mutation with try/finally restore. Required for all non-serial files that touch `process.env`:
```typescript
await withEnv({ OPENAI_API_KEY: 'sk-test', GBRAIN_HOME: undefined }, async () => {
  expect(loadConfig().openai_key).toBe('sk-test');
});
```
Supports nested composition — inner restores to outer's value, not original.

### `test/helpers/reset-pglite.ts` — `resetPgliteState(engine)`

TRUNCATE all public tables (except `schema_version`) + re-seed the default source FK row. Used in `beforeEach` to clear data without recreating the engine:
```typescript
beforeEach(async () => {
  await resetPgliteState(engine);
});
```

### `test/e2e/helpers.ts` — E2E DB lifecycle

```typescript
import { hasDatabase, setupDB, teardownDB, getEngine, getConn, importFixtures, time } from './helpers.ts';

beforeAll(async () => { await setupDB(); await importFixtures(); }, 30_000);
afterAll(teardownDB);
```

- `hasDatabase()` — checks `DATABASE_URL` env var
- `setupDB()` — connect, `initSchema()`, TRUNCATE CASCADE all tables, re-seed config
- `importFixtures()` — imports all markdown files from `test/e2e/fixtures/`
- `getConn()` — raw postgres.js connection for direct SQL queries in tests
- `time(fn)` — measures elapsed milliseconds

### Test seam functions (production modules)

Test-injectable hooks exported with `__` prefix (naming convention for test-only exports):
- `__setEmbedTransportForTests(fn)` / `__setChatTransportForTests(fn)` — in `src/core/ai/gateway.ts`
- `_clearMcpClientTokenCache()` — in `src/core/mcp-client.ts`
- `_resetDeprecationWarningsForTest()` — in `src/core/model-config.ts`
- `_uninstallSigchldHandlerForTests()` — in `src/core/zombie-reap.ts`

These enable testing gateway/LLM code without real API calls or module mocking.

### Factory helpers in test files

Tests define local factory functions rather than using a shared factory library:
```typescript
// test/search.test.ts
function makeResult(overrides: Partial<SearchResult> = {}): SearchResult {
  return { slug: 'test-page', page_id: 1, title: 'Test', ..., ...overrides };
}

// test/whoknows.test.ts
function input(slug, raw_match, days, salience, type = 'person') { ... }
```

### JSONL fixtures

Eval fixtures stored as `.jsonl` files under `test/fixtures/`:
- `whoknows-eval.jsonl` — `{ query, expected_top_3_slugs, notes? }`
- `longmemeval-mini.jsonl` — LongMemEval-format questions
- `contradictions-mini.jsonl` — contradiction detection test cases

## Coverage

**Well-tested areas:**
- PGLite engine: all 37+ BrainEngine methods in `test/pglite-engine.test.ts`
- Search pipeline: RRF fusion, source boost, dedup, intent classification
- Sync/import: manifest parsing, slug conversion, failure classification
- OAuth provider: full spec coverage including RFC 6749/7009 edge cases
- Migrations: each migration version has a dedicated test file
- Chunkers: recursive, code (tree-sitter), fence extraction
- Security boundaries: trust boundary, upload validation, slug security
- MCP operations: all 47 operations have parity coverage in `test/parity.test.ts`
- AI gateway: embed transport, chat transport, model resolution, recipe validation
- Error handling: StructuredAgentError, OperationError, UnrecoverableError

**Known gaps / partial coverage:**
- `src/commands/dream.ts` CLI flags — integration tested via E2E rather than unit
- `src/core/transcription.ts` — provider detection tested but full transcription pipeline requires real Groq/OpenAI
- Actual AI response quality — LLM calls use stubbed transports; real quality tested separately via eval harness
- `src/core/cycle/synthesize.ts` subagent fan-out — tested with stubbed `MessagesClient`
- Large file edge cases in `src/core/import-file.ts` — chunk boundary behavior

## Test Patterns

### Canonical PGLite block (R3 + R4 compliant)

Enforced by `scripts/check-test-isolation.sh`. Every PGLite-using unit test file must follow this exact shape:

```typescript
import { PGLiteEngine } from '../src/core/pglite-engine.ts';
import { resetPgliteState } from './helpers/reset-pglite.ts';

let engine: PGLiteEngine;

beforeAll(async () => {
  engine = new PGLiteEngine();
  await engine.connect({});
  await engine.initSchema();
});

afterAll(async () => {
  await engine.disconnect();
});

beforeEach(async () => {
  await resetPgliteState(engine);
});
```

Rationale: one engine per file (cold-start paid once); data wiped per-test; `afterAll` disconnects so engine doesn't leak across shard file boundaries.

### E2E skip pattern

```typescript
const skip = !hasDatabase();
const describeE2E = skip ? describe.skip : describe;

describeE2E('E2E: Feature', () => {
  beforeAll(async () => { await setupDB(); }, 30_000);
  afterAll(teardownDB);
  // ...
});
```

### Structural source-code assertions

Used when the safest test is asserting the shape of production source, not running it:
```typescript
test('doctor registers jsonb_integrity check', () => {
  const src = fs.readFileSync('src/commands/doctor.ts', 'utf8');
  expect(src).toContain("name: 'jsonb_integrity'");
});
```
Common for security-critical invariants (trust boundary call sites, protected job names), CLI registration checks, and naming contract enforcement.

### Async error testing

```typescript
await expect(queue.add('', {})).rejects.toThrow('Job name cannot be empty');
expect(() => engine.putPage('../etc/passwd', testPage)).toThrow();
```

### CLI invocation pattern

```typescript
const result = Bun.spawnSync({
  cmd: ['bun', 'run', 'src/cli.ts', '--help'],
  cwd: import.meta.dir + '/..',
});
const stdout = new TextDecoder().decode(result.stdout);
expect(stdout).toContain('doctor');
```

### Source-reading tests for regression guards

```typescript
test('check-source-id-projection: every rowToPage feeder includes source_id', async () => {
  const src = fs.readFileSync('src/core/postgres-engine.ts', 'utf8');
  // Assert specific SQL patterns are present
  expect(src).not.toContain('SELECT id, slug, type, title FROM pages');
});
```

### Test isolation enforcement

Four rules enforced by `scripts/check-test-isolation.sh` for all non-serial unit files:
- **R1:** No direct `process.env.X = ...` mutations — use `withEnv()` from `test/helpers/with-env.ts`
- **R2:** No `mock.module(...)` — rename file to `*.serial.test.ts`
- **R3:** `new PGLiteEngine(` only within ~50 lines after a `beforeAll(` line (no module-scope engines)
- **R4:** Any file creating `new PGLiteEngine(` must call `.disconnect(` inside `afterAll(`

## Running Tests

```bash
# Inner edit loop (fastest, ~85s on Apple Silicon)
bun run test

# Pre-push gate (type-check + 12 CI guards, no test runner)
bun run verify

# Before opening a PR
bun run test:full

# Run a specific test file
bun test test/pglite-engine.test.ts
bun test test/search.test.ts

# Run E2E tests (requires Docker + DATABASE_URL)
# Step 1: Start test DB
docker run -d --name gbrain-test-pg \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=gbrain_test \
  -p 5434:5432 pgvector/pgvector:pg16

# Step 2: Bootstrap schema
DATABASE_URL=postgresql://postgres:postgres@localhost:5434/gbrain_test \
  bun run src/cli.ts doctor --json > /dev/null 2>&1

# Step 3: Run
DATABASE_URL=postgresql://postgres:postgres@localhost:5434/gbrain_test \
  bun run test:e2e

# Step 4: Teardown
docker stop gbrain-test-pg && docker rm gbrain-test-pg

# Run serial tests only
bun run test:serial

# Check test isolation lint
bun run check:test-isolation

# View test failures from last run
cat .context/test-failures.log
```

**IMPORTANT: Never pipe `bun test` output through `head` or `tail`.** The exit code is `tail`'s (always 0), not bun's. Always redirect to a file first:
```bash
bun test > /tmp/test-out.txt 2>&1
echo "EXIT=$?"
tail -50 /tmp/test-out.txt
```
