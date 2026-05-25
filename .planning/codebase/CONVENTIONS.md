# Code Conventions

**Analysis Date:** 2026-05-25

## Language & Typing

**TypeScript version:** `^5.6.0` with `strict: true` (all strict checks enabled).

**Key tsconfig settings:**
- `target: ESNext`, `module: ESNext`, `moduleResolution: bundler`
- `allowImportingTsExtensions: true` — `.ts` extensions used explicitly in import paths
- `types: ["bun-types"]` — no Node.js types; Bun runtime assumed
- `baseUrl: "."` with path alias `@/*` → `src/*` (rarely used; most imports are relative)
- `noEmit: true` — compilation only for type checking, not code generation

**Type patterns used:**

- `import type` is used extensively (335+ occurrences) for type-only imports — separates runtime from type deps
- `interface` preferred over `type` for object shapes (e.g., `BrainEngine`, `OperationContext`, `Page`)
- `type` used for unions (e.g., `PageType`, `ErrorCode`, `ProgressMode`)
- `readonly` used on class fields, `ReadonlySet<T>`, `ReadonlyArray<T>` for immutability
- `as const` used on literal arrays and discriminant values: `readonly kind = 'postgres' as const`
- Exhaustiveness helper `assertNever(x: never): never` in `src/core/types.ts` — enforced via `switch` defaults on discriminated unions
- `(string & {})` open union pattern for forward-compatible error codes (allows named values + arbitrary string extensions)
- Optional chaining (`?.`) and nullish coalescing (`??`) used consistently
- Generic type parameters named `T`, `R` for simple cases; descriptive names for complex types
- Zod used sparingly — only `z.object({ queries: z.array(z.string()).min(1).max(5) })` in `src/core/ai/gateway.ts` for LLM response schemas

**No `any` except:**
- Explicit `as any` in test helpers (narrowly scoped)
- Engine raw SQL results use `Record<string, unknown>` not `any`

## Code Style

**Formatter:** No Prettier config detected. Code uses consistent 2-space indentation throughout.

**Linting:** No ESLint config file; a few inline `// eslint-disable-line` comments for specific rules (`no-console`, `@typescript-eslint/ban-types`, `@typescript-eslint/no-require-imports`).

**Naming conventions:**

| Element | Convention | Examples |
|---------|-----------|---------|
| Files | `kebab-case.ts` | `pglite-engine.ts`, `sync-concurrency.ts`, `import-file.ts` |
| Directories | `kebab-case/` | `chunkers/`, `minions/`, `cross-modal-eval/` |
| Classes | `PascalCase` | `PGLiteEngine`, `MinionQueue`, `StructuredAgentError` |
| Interfaces | `PascalCase` | `BrainEngine`, `OperationContext`, `ThrottleConfig` |
| Type aliases | `PascalCase` | `PageType`, `ErrorCode`, `ProgressMode` |
| Functions | `camelCase` | `buildSyncManifest`, `validateSourceId`, `clampSearchLimit` |
| Constants (module-level) | `UPPER_SNAKE_CASE` | `MAX_SEARCH_LIMIT`, `BATCH_SIZE`, `DEFAULT_POOL_SIZE_FALLBACK` |
| Private/module-internal | Leading `_` prefix | `_config`, `_modelCache`, `_embedTransport`, `_extendedModels` |
| Test seam exports | Double `__` prefix | `__setEmbedTransportForTests`, `__setChatTransportForTests` |
| Error codes | `snake_case` strings | `'page_not_found'`, `'permission_denied'`, `'rate_limited'` |
| Progress phases | `snake_case.dot.separated` | `'doctor.db_checks'`, `'sync.imports'`, `'import.files'` |

**File organization — command files (`src/commands/*.ts`):**
```
1. JSDoc comment block explaining purpose + usage examples
2. Imports (Node builtins → project imports → types)
3. Module-level constants (HELP text, limits)
4. Local interfaces/types
5. Pure helper functions
6. Main exported async function (e.g., runSalience, runSync)
```

**File organization — core files (`src/core/*.ts`):**
```
1. JSDoc block explaining design rules, version history
2. Imports with `import type` for type-only deps
3. Module-level constants (UPPER_SNAKE_CASE)
4. Exported types/interfaces
5. Exported classes (if any)
6. Exported functions
```

**Progress always writes to `stderr`.** Stdout is reserved for JSON data output. Enforced by `scripts/check-progress-to-stdout.sh` CI guard.

## Error Handling

**Two error hierarchies are used:**

**1. `OperationError` (`src/core/operations.ts`)** — MCP/CLI layer errors:
```typescript
throw new OperationError('permission_denied', 'Access denied', 'Pass --confirm-destructive', 'https://...');
```
Serializes to `{ error: code, message, suggestion, docs }` via `.toJSON()`.

**2. `StructuredAgentError` + `buildError` (`src/core/errors.ts`)** — agent-facing errors with envelope:
```typescript
throw errorFor({ class: 'FileTooLarge', code: 'file_too_large', message: '...', hint: '...' });
// or:
const e = buildError({ class: 'ConfirmationRequired', code: 'cost_preview_requires_yes', message: '...' });
throw new StructuredAgentError(e);
```
The `envelope` property carries `{ class, code, message, hint?, docs_url? }`.

**`serializeError(value: unknown): StructuredError`** — normalize any throwable to the structured envelope for JSON output. Used at CLI output boundaries.

**Error catch pattern:**
```typescript
try {
  const result = await op();
} catch (e: unknown) {
  // check instanceof before using properties
  const code = (e as { code?: string })?.code;
  if (code !== '42P01') throw e; // narrow and re-throw
}
```

**Database-specific:**
- `isUndefinedColumnError(err, column)` in `src/core/utils.ts` — pattern-matches SQLSTATE 42703; only catches column-missing, lets network/lock errors propagate
- Engine raw SQL wrapped in try/catch with error code inspection

**Env/config errors:** Fail-loud with actionable messages. `validateSourceId()` throws `Error` with fix hint. `validateSlug()` throws with specific message.

**`UnrecoverableError`** in `src/core/minions/types.ts` — signals that a Minion job should go straight to `dead` state on first attempt (no retries).

## Async Patterns

**All async I/O uses `async/await`.** No callback-style async.

**Concurrency patterns:**
- `Promise.all([a, b, c])` for independent parallel work where all must succeed: `const [pages, takesKw, takesVec] = await Promise.all([...])`
- `Promise.allSettled([a, b, c])` for parallel work where partial success is acceptable (cross-modal eval, multi-model scoring)
- `Promise.race([probe, timeout])` for timeout enforcement (health checks, DB lock wait)

**Batch processing:** for-of loop with `await` inside (not `map` + `Promise.all`) when ordered processing or sequential DB writes are required. `Promise.all` + `.map` used when fully parallelizable.

**Abort signal pattern:**
```typescript
// From MinionWorker
await Promise.race([
  handler(ctx),
  new Promise((_, reject) => ctx.signal.addEventListener('abort', () => reject(new Error('abort')))),
]);
```

**No raw `setTimeout` for delays** — backoff utilities in `src/core/backoff.ts` used instead.

**Fire-and-forget pattern** (JSONL audit logging, eval capture): async function called without `await`, errors absorbed with best-effort try/catch so the main flow never blocks.

## Module System

**ESM throughout:** `"type": "module"` in `package.json`. All imports use `.ts` extension explicitly:
```typescript
import { PGLiteEngine } from '../src/core/pglite-engine.ts';
import type { BrainEngine } from './engine.ts';
```

**No barrel files at `src/core/index.ts`** beyond the minimal public API surface:
```typescript
export type { BrainEngine } from './engine.ts';
export { PostgresEngine } from './postgres-engine.ts';
export * from './types.ts';
export { parseMarkdown, serializeMarkdown, splitBody } from './markdown.ts';
```

**Public package exports** declared in `package.json` `exports` map — 17 named subpaths. Enforced by `scripts/check-exports-count.sh`.

**Dynamic imports** used intentionally for lazy-loading heavy modules:
```typescript
const { isAnthropicProvider } = await import('../model-config.ts');
```
Used in `src/core/minions/queue.ts` to avoid circular imports and in `src/cli.ts` to defer command module loading.

**`import.meta.url` and `import.meta.dir`** used in tests and scripts for path resolution (no `__dirname`).

## Documentation Style

**Every public module has a leading JSDoc block** explaining:
- What the module does
- Version history (`v0.14.0: ...`, `v0.22.0: ...`)
- Design rules / constraints (e.g., "NEVER reads process.env at call time")
- Key exports and their purpose

**Inline comments on non-obvious logic:** SQL query explanations, algorithm rationale, security reasoning. Examples:
```typescript
// v0.26.9 (F7b): ctx.remote is now a REQUIRED field — fail-closed semantics
// Anything that isn't strictly `false` is now treated as remote.
```

**`@internal` JSDoc tag** used for test-seam exports that should not be consumed by external callers:
```typescript
/** @internal Exported for test access (test/mcp-client-hardening.test.ts). */
export function _clearMcpClientTokenCache(): void { ... }
```

**`@deprecated` JSDoc tag** used with migration hint:
```typescript
/** @deprecated v0.29.1: prefer getEffectiveDates (composite-keyed, multi-source-safe). */
```

**Horizontal dividers** `// ────────` used to separate major sections within large files.

**Version annotation pattern** in CLAUDE.md (not in source): `v0.X.Y (#NNN, contributed by @user)` tracks when a behavior was introduced.

## Security Patterns

**Trust boundary via `OperationContext.remote: boolean` (REQUIRED field):**
- `remote: false` → trusted local CLI caller (set in `src/cli.ts`)
- `remote: true` → untrusted agent-facing caller (set in `src/mcp/server.ts` and HTTP transport)
- Anything not strictly `false` is treated as remote (fail-closed)

**Permission checks at op boundaries:**
```typescript
if (ctx.remote !== false) throw new OperationError('permission_denied', '...');
```

**Input validation:**
- `validateSlug(slug)` rejects traversal patterns, empty, absolute paths
- `validateSourceId(id)` enforces `^[a-z0-9_-]+$` — safe for both filesystem and SQL
- `validateUploadPath(path, root, strict)` — `strict=true` for remote callers, confines to cwd

**Token storage:** SHA-256 hashed via `hashToken()` in `src/core/utils.ts`. Never stored plaintext.

**SQL injection prevention:** Parameterized queries via postgres.js. `LIKE` patterns escape `%`, `_`, `\` before interpolation. `pgArray()` escapes commas/quotes/braces in array elements.

**Process env at config time, not call time:** `src/core/ai/gateway.ts` design rule: "NEVER reads `process.env` at call time." Config read once via `configureGateway()`.

**SSRF helpers:** `isInternalUrl`, `parseOctet`, `hostnameToOctets`, `isPrivateIpv4` in `src/commands/integrations.ts` — external recipe HTTP endpoints validated before execution.

**Shell job protection:**
- `PROTECTED_JOB_NAMES` in `src/core/minions/protected-names.ts` — shell jobs require `allowProtectedSubmit: true` and `GBRAIN_ALLOW_SHELL_JOBS=1`
- Shell handler spawns `/bin/sh -c cmd` with explicit env allowlist (`PATH, HOME, USER, LANG, TZ, NODE_ENV`)

**Privacy:**
- `src/core/eval-capture-scrub.ts` — PII scrubber strips emails, phones, SSN, credit cards, JWT/bearer tokens before eval capture
- Progress always to stderr; no page body content in stdout logs
