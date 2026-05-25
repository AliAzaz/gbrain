# Technology Stack

**Analysis Date:** 2026-05-25

## Runtime & Language

**Primary Language:** TypeScript 5.6+
- Strict mode enabled (`"strict": true` in `tsconfig.json`)
- ESNext target, ESNext module system, `bundler` module resolution
- `allowImportingTsExtensions: true` — `.ts` imports used directly (no emit path)
- Path alias: `@/*` → `src/*`
- Type check only via `tsc --noEmit` (Bun runtime handles execution)

**Runtime:** Bun `>=1.3.10` (required minimum; CI uses `bun-version: latest`)
- Bun is both the runtime AND the package manager AND the test runner AND the compiler
- Native WASM support used for PGLite and tree-sitter grammars
- `Bun.spawn` used for child process management (PTY support requires Bun 1.3.10+)

**Module system:** ESM only (`"type": "module"` in `package.json`)

## Package Manager & Dependencies

**Package Manager:** Bun (lockfile: `bun.lock`, format version 1)
- `bun install` for dependency installation
- `trustedDependencies: ["@electric-sql/pglite"]` — allows postinstall scripts

**Key Production Dependencies:**

| Package | Version | Purpose |
|---------|---------|---------|
| `@electric-sql/pglite` | `0.4.3` | Embedded Postgres 17.5 via WASM (zero-config engine) |
| `postgres` | `^3.4.0` | postgres.js client for Postgres/Supabase engine |
| `pgvector` | `^0.2.0` | pgvector type helpers for vector column binding |
| `@modelcontextprotocol/sdk` | `1.29.0` | MCP stdio + HTTP server implementation |
| `ai` | `^6.0.168` | Vercel AI SDK — unified LLM call layer |
| `@ai-sdk/anthropic` | `^3.0.71` | Anthropic provider for AI SDK |
| `@ai-sdk/openai` | `^3.0.53` | OpenAI provider for AI SDK |
| `@ai-sdk/google` | `^3.0.64` | Google Gemini provider for AI SDK |
| `@ai-sdk/openai-compatible` | `^2.0.41` | Generic OpenAI-compat provider (Voyage, OpenRouter, etc.) |
| `@anthropic-ai/sdk` | `^0.30.0` | Direct Anthropic SDK (subagent tool-loop) |
| `openai` | `^4.0.0` | Direct OpenAI SDK (embedding batch path) |
| `express` | `^5.1.0` | HTTP MCP server and admin dashboard |
| `express-rate-limit` | `^7.5.0` | Rate limiting for HTTP server |
| `@aws-sdk/client-s3` | `^3.1028.0` | S3/R2/MinIO file storage backend |
| `web-tree-sitter` | `0.22.6` | WASM tree-sitter runtime for code chunking |
| `tree-sitter-wasms` | `0.1.13` | 36 pre-compiled tree-sitter grammar WASMs |
| `@dqbd/tiktoken` | `^1.0.22` | cl100k_base tokenizer for chunk budget |
| `zod` | `^4.3.6` | Runtime schema validation |
| `gray-matter` | `^4.0.3` | YAML frontmatter parsing |
| `marked` | `^18.0.0` | Markdown rendering |
| `cors` | `^2.8.5` | CORS middleware for HTTP server |
| `cookie-parser` | `^1.4.7` | Cookie parsing for admin OAuth session |
| `eventsource-parser` | `^3.0.8` | SSE parsing for admin live feed |
| `@jsquash/avif` | `^2.1.1` | AVIF image decoding (multimodal ingestion) |
| `@jsquash/png` | `^3.1.1` | PNG image decoding (multimodal ingestion) |
| `heic-decode` | `^2.1.0` | HEIC image decoding (multimodal ingestion) |
| `exifr` | `^7.1.3` | EXIF metadata extraction |

**Key Dev Dependencies:**

| Package | Version | Purpose |
|---------|---------|---------|
| `typescript` | `^5.6.0` | Type checker (`tsc --noEmit` only; Bun handles execution) |
| `@types/bun` | `latest` | Bun runtime type definitions |
| `bun-types` | `^1.3.13` | Bun-specific type augmentations |
| `@types/express` | `^5.0.6` | Express type definitions |
| `@types/cors` | `^2.8.19` | cors type definitions |
| `@types/cookie-parser` | `^1.4.7` | cookie-parser type definitions |

## Build System

**Compiler:** `bun build --compile` — produces self-contained single-file binaries

**Primary build command:**
```bash
bun build --compile --outfile bin/gbrain src/cli.ts
```

**Cross-platform builds:**
```bash
bun build --compile --target=bun-darwin-arm64 --outfile bin/gbrain-darwin-arm64 src/cli.ts
bun build --compile --target=bun-linux-x64 --outfile bin/gbrain-linux-x64 src/cli.ts
```

**Binary outputs:** `bin/gbrain` (native), `bin/gbrain-darwin-arm64`, `bin/gbrain-linux-x64`

**Admin SPA build:**
```bash
cd admin && bun run build   # Vite 6.3.3 → admin/dist/
```
Admin SPA (`admin/dist/`) is committed so the binary can embed it.

**Schema codegen:**
```bash
bash scripts/build-schema.sh   # src/schema.sql → src/core/schema-embedded.ts
```

**LLMs.txt generation:**
```bash
bun run scripts/build-llms.ts   # → llms.txt, llms-full.txt
```

**Asset embedding:** 36 tree-sitter WASM grammars in `src/assets/wasm/` are embedded via `import path from '...' with { type: 'file' }` so `bun --compile` bundles them deterministically.

**Admin SPA stack:** React 19, Vite 6.3.3, TypeScript 5.8.3 (separate `admin/package.json`)

## Development Tools

**Type Checking:**
- `bun run typecheck` → `tsc --noEmit`
- Runs as part of `bun run verify` (pre-push gate)

**Linting / Static Analysis (shell scripts, not eslint/biome):**
- `scripts/check-jsonb-pattern.sh` — bans `${JSON.stringify(x)}::jsonb` interpolation and `max_stalled DEFAULT 1`
- `scripts/check-progress-to-stdout.sh` — bans `\r` progress writes to stdout
- `scripts/check-test-isolation.sh` — bans `process.env.X = ...` and `mock.module(...)` in parallel test files
- `scripts/check-privacy.sh` — bans real names in public-facing files
- `scripts/check-source-id-projection.sh` — ensures `source_id` in every `rowToPage` SELECT
- `scripts/check-wasm-embedded.sh` — ensures all tree-sitter WASMs are embedded in the binary
- `scripts/check-admin-build.sh` — ensures admin/dist/ is fresh
- `scripts/check-exports-count.sh` — pins public subpath export count
- `scripts/check-system-of-record.sh` — enforces CLAUDE.md as single source of truth
- `scripts/check-eval-glossary-fresh.sh` — ensures metric glossary is current
- `scripts/check-trailing-newline.sh` — trailing newline enforcement

**Secret Scanning:** gitleaks v2 (CI shard, `gitleaks/gitleaks-action`)

**No eslint or prettier detected** — formatting is enforced via TypeScript's own strict mode and the shell CI guards above.

**Git hooks:** None detected (no `.husky`, `.lefthook`, or similar).

## Test Infrastructure

**Test Runner:** Bun's built-in test runner (`bun test`)

**Test timeout:** 60,000ms (configured in `bunfig.toml` — required for PGLite WASM cold start)

**Test file taxonomy:**
- `test/*.test.ts` — parallel unit tests (8-shard fan-out via `scripts/run-unit-parallel.sh`)
- `test/*.slow.test.ts` — slow tests, run separately via `bun run test:slow`
- `test/*.serial.test.ts` — serial tests (top-level `mock.module` isolation), run at `--max-concurrency=1`
- `test/e2e/*.test.ts` — real Postgres E2E tests, require `DATABASE_URL`

**Test commands:**

```bash
bun run test              # Parallel unit fast loop (8-shard, ~85s, no DB needed)
bun run test:slow         # *.slow.test.ts only
bun run test:serial       # *.serial.test.ts at --max-concurrency=1
bun run test:e2e          # Real Postgres E2E (requires DATABASE_URL)
bun run test:full         # verify + all units + slow + smart E2E
bun run verify            # Type-check + all pre-push CI guards
bun run check:all         # All 7+ historical pre-checks (superset of verify)
bun run ci:local          # Full Docker-based local CI gate
bun run ci:local:diff     # Diff-aware E2E subset
```

**Test DB for E2E:** `pgvector/pgvector:pg16` Docker container; `DATABASE_URL=postgresql://postgres:postgres@localhost:PORT/gbrain_test`

**Test helpers:**
- `test/helpers/reset-pglite.ts` — truncate user data (fast between-test reset)
- `test/helpers/with-env.ts` — `withEnv({KEY: val}, fn)` for safe env mutation in tests
- `test/helpers/cli-pty-runner.ts` — real-PTY harness for CLI integration tests

**Coverage:** No coverage tooling configured.

**Failure logging:** Test failures written to `.context/test-failures.log` (or `/tmp/gbrain-test-failures.log`).

**Diff-aware E2E selector:** `scripts/select-e2e.ts` + `scripts/e2e-test-map.ts` — maps changed source files to relevant E2E tests; fail-closed (unmapped src/ changes trigger all E2E files).

## CI/CD

**CI System:** GitHub Actions

**Workflow files:**
- `.github/workflows/test.yml` — unit tests (4-shard matrix on `ubuntu-latest`, gitleaks secret scan, `bun run verify` on shard 1)
- `.github/workflows/e2e.yml` — E2E tests (Tier 1 mechanical + Tier 2 LLM skills with OpenClaw; nightly + PR triggers; `pgvector/pgvector:pg16` service)
- `.github/workflows/release.yml` — binary release build on `v*` tags (macOS arm64 + Linux x64; `softprops/action-gh-release` for GitHub Releases)

**Triggers:**
- `test.yml`: push to `master`, PRs to `master`
- `e2e.yml`: push to `master`, PRs to `master`, nightly cron (`0 6 * * *`), manual dispatch
- `release.yml`: push of `v*` tags

**Deployment target:** Self-contained binary (`bun build --compile`), distributed via GitHub Releases. No container registry or cloud hosting target in CI. Fly.io mentioned in CLAUDE.md as a deployment target for `gbrain serve --http`.

**Action pins:** All GitHub Actions pinned to commit SHAs (security best practice enforced).

## Key Scripts

```bash
bun run dev                    # Run CLI from source (bun run src/cli.ts)
bun run build                  # Compile self-contained binary → bin/gbrain
bun run build:all              # Cross-compile for darwin-arm64 + linux-x64
bun run build:admin            # Build admin React SPA → admin/dist/
bun run build:schema           # Regenerate src/core/schema-embedded.ts
bun run build:llms             # Regenerate llms.txt + llms-full.txt
bun run verify                 # Full pre-push gate (type-check + all guards)
bun run test                   # Parallel unit tests (default inner loop)
bun run test:e2e               # Real-Postgres E2E
bun run typecheck              # tsc --noEmit standalone
bun run ci:local               # Full local CI with Docker
bun run ci:select-e2e          # Print diff-selected E2E test list
publish:clawhub                # Build cross-platform + publish to ClawHub package registry
```

---

*Stack analysis: 2026-05-25*
