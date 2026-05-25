# PureClaw GBrain — Installation & Usage Guide

## Path layout (bootstrap defaults)

Matches `scripts/bootstrap/configure-openclaw.sh` and `configure-gbrain.sh`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `OPENCLAW_HOME` | `~/.openclaw` (pod: `/root/.openclaw`) | OpenClaw home — `AGENTS.md`, `skills/`, `.env` |
| `OPENCLAW_WORKSPACE` | **`$OPENCLAW_HOME`** (same directory) | Passed to `gbrain skillpack install --workspace` |
| `GBRAIN_HOME` | `$OPENCLAW_HOME/data/gbrain` | Brain DB + `$GBRAIN_HOME/brain/` markdown repo |
| `GBRAIN_INSTALL_DIR` | `/opt/gbrain` | GBrain CLI install + bundled skillpack **source** |

**Installed skill location (bootstrap):** **`$OPENCLAW_HOME/skills/pureclaw-gbrain/`** — e.g. `/root/.openclaw/skills/pureclaw-gbrain/SKILL.md`.

The agent resolves **`skills/pureclaw-gbrain/SKILL.md`** relative to `$OPENCLAW_WORKSPACE` (default `$OPENCLAW_HOME`).

**Do not confuse** `$GBRAIN_INSTALL_DIR/skills/` (catalog at `/opt/gbrain/skills/`) with **`$OPENCLAW_HOME/skills/`** (what the running agent loads after install).

## Prerequisites

- **`gbrain`** on `PATH` (CLI installed and wired to your brain deployment).
- **A reachable brain** — database + embeddings configured the way your environment expects (e.g. Postgres/pgvector, Supabase, or a bundled PGLite layout). `gbrain doctor --fast` should succeed before you rely on the agent.
- **An agent workspace with a `skills/` directory** — typically `$OPENCLAW_WORKSPACE` (folder containing root `AGENTS.md` and `skills/`).

## How It Works

This skill is **instruction-based**. The agent reads `SKILL.md` and follows the memory protocol: wake discipline, Iron Laws, `gbrain search` / `gbrain query` before escalating outward, and **`gbrain put`** for durable writes.

**GBrain store + brain repo.** Agent captures use **`gbrain put`** (DB + embeddings, searchable immediately). Markdown under **`$GBRAIN_HOME/brain/`** comes from bootstrap template, git clone, or manual edits; **cron** (`gbrain sync --repo "$GBRAIN_HOME/brain" && gbrain embed --stale`, or `gbrain autopilot --install`) keeps the DB aligned with files on disk. No workspace `MEMORY.md` — recall is **only** via `gbrain search` / `query` / `get`.

There is no separate API key just for the skill — authentication is whatever your **GBrain deployment** already uses (`DATABASE_URL`, provider keys for embeddings/chat if applicable, etc.). If you also run **PureClaw Connect**, connector traffic can feed facts into GBrain; this skill defines how those facts get captured and retrieved.

## Installation

### Option A — Copy the skill folder (same pattern as PureClaw Connect)

```bash
export OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
export OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-$OPENCLAW_HOME}"
mkdir -p "$OPENCLAW_HOME/skills"
cp -r "$GBRAIN_INSTALL_DIR/skills/pureclaw-gbrain" "$OPENCLAW_HOME/skills/pureclaw-gbrain"
# Or from a local checkout: cp -r ./skills/pureclaw-gbrain "$OPENCLAW_HOME/skills/"
```

### Option B — Bootstrap / skillpack (recommended)

OpenClaw bootstrap (`configure-openclaw.sh`) copies from `$GBRAIN_INSTALL_DIR/skills/pureclaw-gbrain` → **`$OPENCLAW_HOME/skills/pureclaw-gbrain`** and runs:

```bash
gbrain skillpack install pureclaw-gbrain --workspace "$OPENCLAW_WORKSPACE"
```

Manual equivalent:

```bash
export OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
export OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-$OPENCLAW_HOME}"
gbrain skillpack install pureclaw-gbrain --workspace "$OPENCLAW_WORKSPACE"
```

Skillpack copies into **`$OPENCLAW_HOME/skills/`** (not `/opt/gbrain` on the agent): `pureclaw-gbrain/`, shared **`skills/conventions/`** (including `cron-via-minions.md`), and brain filing rules. It updates the **`<!-- gbrain:skillpack:begin -->` … `<!-- gbrain:skillpack:end -->`** managed block in `$OPENCLAW_HOME/AGENTS.md` (or `RESOLVER.md`). Do not edit inside those markers by hand.

**Prefer Option B over Option A** when possible: copy-only installs skip conventions; cron/dream scheduling in `SKILL.md` §9 assumes conventions may be present.

**Optional add-ons** (install into the workspace):

```bash
gbrain skillpack install signal-detector --workspace "$OPENCLAW_WORKSPACE"
gbrain skillpack install cold-start --workspace "$OPENCLAW_WORKSPACE"
```

Full catalog index: `$GBRAIN_INSTALL_DIR/docs/GBRAIN_SKILLPACK.md` (default `/opt/gbrain/docs/GBRAIN_SKILLPACK.md`).

The directory should contain:

```
pureclaw-gbrain/
  SKILL.md
  AGENTS.md
  INSTALL.md
  _meta.json
```

## Running the Skill

1. **Workspace location** — Ensure the agent’s cwd / docs resolve paths relative to `$OPENCLAW_WORKSPACE` (parent of `skills/`):

   ```bash
   export OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
   export OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-$OPENCLAW_HOME}"
   export GBRAIN_HOME="${GBRAIN_HOME:-$OPENCLAW_HOME/data/gbrain}"
   ```

2. **Health check** — From the workspace (or anywhere `gbrain` is configured):

   ```bash
   gbrain doctor --fast
   ```

3. **Agent routing** — Merge the wake protocol and semantic routing from **`skills/pureclaw-gbrain/AGENTS.md`** into the **human-maintained** part of root **`AGENTS.md`** (outside the skillpack managed fence). Skillpack only adds a compact table row for `pureclaw-gbrain → skills/pureclaw-gbrain/SKILL.md`; it does **not** inject the full wake protocol for you.

Reload or restart the host agent so it picks up `AGENTS.md`.

## First-Time Usage: Wire + Verify

After install:

1. Paste or merge **`skills/pureclaw-gbrain/AGENTS.md`**  (outside the `gbrain:skillpack` fence), or use workspace `AGENTS.md` your operator already installed.
2. Run **`gbrain doctor --fast`** (and full **`gbrain doctor`** if anything looks wrong). After skillpack install, run **`gbrain skillpack-check`** — exit 0 means routing + managed block are consistent.
3. Send a short test message that names a placeholder entity, e.g.:

   > "Quick note: Halcyon Labs is evaluating us for a pilot next quarter."

   The agent should call `gbrain put companies/halcyon-labs` (and append to `daily/YYYY-MM-DD`) **without asking permission**, then confirm what was written. You can then `gbrain delete companies/halcyon-labs` if it was only a test.

4. Verify search (and optional on-disk export):

   ```bash
   gbrain search "halcyon"
   gbrain get companies/halcyon-labs
   gbrain get daily/$(date +%Y-%m-%d)
   gbrain config get sync.last_run   # after cron/autopilot has run
   ```

   If the agent saved to workspace `MEMORY.md` / `memory/*.md` instead of using `gbrain put`, or answered from those files without `gbrain search`, the skill was not loaded correctly — re-check `AGENTS.md` and `skills/pureclaw-gbrain/SKILL.md`.

## Everyday Usage

Talk naturally; the skill's triggers cover memory language and entity mentions:

> "What do you remember about Priya?"

> "Search your brain for anything on the Series A deck."

> "Log this decision: we're postponing the EU launch."

> "Who did we meet last Tuesday?"

The agent should call `gbrain search` / `gbrain query` **in the same turn** (not narrate that it is going to), cite receipts when the brain is invoked, and capture new facts with `gbrain put` per **`SKILL.md`**.

## Upgrading from local-file memory

If you ran an older version of this skill (or another OpenClaw memory skill) that wrote to `MEMORY.md`, `USER.md`, or `memory/YYYY-MM-DD.md` on disk, do a one-time migration on the next wake:

```bash
# Long-term truths → personal/profile (main-session only retrieval after this)
cat "$OPENCLAW_HOME/MEMORY.md" | gbrain put personal/profile

# Daily stream → daily/<date> pages, one per file
for f in "$OPENCLAW_HOME/memory/"*.md; do
  date_slug=$(basename "$f" .md)
  cat "$f" | gbrain put "daily/$date_slug"
done
```

After verifying with `gbrain search`, you can archive the local files. The agent should never read them again — the skill's wake protocol pulls everything from GBrain.

## Workspace Isolation

Each OpenClaw **workspace** has its own `skills/` tree and its own **`AGENTS.md`**. Your GBrain **data plane** is determined by how `gbrain` is configured on that machine or pod (brain directory, `DATABASE_URL`, etc.). Workspace A and workspace B do **not** share memory unless they point at the **same** brain backend.

## Troubleshooting

**`gbrain doctor --fast` fails or brain unreachable:** Fix CLI configuration and database connectivity first — the skill cannot compensate for a down brain.

**Pages missing from search after a raw file edit:** Prefer **`gbrain put`** for entity pages; raw markdown without DB ingest stays invisible to hybrid search until **`gbrain sync`** (see **`SKILL.md`** §4).

**Skillpack refused to write / mentions lock:** Another install may be running, or `.gbrain-skillpack.lock` is stale. Retry after it clears, or use **`--force-unlock`** only when you know no other skillpack process is active.

**Skillpack skipped files (`skipped_locally_modified`):** Your tree differs from the bundle. Use **`--dry-run`** to preview, then **`--overwrite-local`** if you intend to replace local copies.

**Managed block looks wrong:** Don’t hand-edit between **`<!-- gbrain:skillpack:begin -->`** and **`<!-- gbrain:skillpack:end -->`**. Re-run **`gbrain skillpack install pureclaw-gbrain`** from the gbrain repo, or fix the fence per GBrain docs.

## Uninstall

Remove the skill directory:

```bash
rm -rf "$OPENCLAW_HOME/skills/pureclaw-gbrain"
```

Or (updates the managed block when applicable):

```bash
gbrain skillpack uninstall pureclaw-gbrain --workspace "$OPENCLAW_WORKSPACE"
```

That removes the skill only. It does **not** delete brain data. If you deleted the folder by hand, ensure root **`AGENTS.md`** no longer references `skills/pureclaw-gbrain/SKILL.md`, or adjust the skillpack managed block so it stays consistent.
