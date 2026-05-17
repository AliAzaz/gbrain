# PureClaw GBrain — Installation & Usage Guide

## Prerequisites

- **`gbrain`** on `PATH` (CLI installed and wired to your brain deployment).
- **A reachable brain** — database + embeddings configured the way your environment expects (e.g. Postgres/pgvector, Supabase, or a bundled PGLite layout). `gbrain doctor --fast` should succeed before you rely on the agent.
- **An agent workspace with a `skills/` directory** — typically an [OpenClaw](https://openclaw.ai) workspace (folder containing root `AGENTS.md` and `skills/`).

## How It Works

This skill is **instruction-based**. The agent reads `SKILL.md` and follows the memory protocol: wake discipline, Iron Laws, `gbrain search` / `gbrain query` before escalating outward, and **`gbrain put`** for durable writes (record + DB + embeddings in one step).

**Single store.** GBrain is the only persistent memory in this design — there is no parallel `MEMORY.md` or `memory/YYYY-MM-DD.md` file in the agent workspace. Daily stream goes to `gbrain put daily/YYYY-MM-DD`. Long-term user truths go to `gbrain put personal/profile` (main session only). Entity pages (`people/`, `companies/`, `deals/`, …) go through `gbrain put` the same way. If you are upgrading from an older skill version that wrote to local markdown, see the "Upgrading from local-file memory" section below.

There is no separate API key just for the skill — authentication is whatever your **GBrain deployment** already uses (`DATABASE_URL`, provider keys for embeddings/chat if applicable, etc.). If you also run **PureClaw Connect**, connector traffic can feed facts into GBrain; this skill defines how those facts get captured and retrieved.

## Installation

### Option A — Copy the skill folder (same pattern as PureClaw Connect)

```bash
mkdir -p /path/to/workspace/skills
cp -r pureclaw-gbrain /path/to/workspace/skills/pureclaw-gbrain
```

Use your real OpenClaw workspace path for `/path/to/workspace` (often `~/.openclaw/workspace` or `$OPENCLAW_WORKSPACE`).

### Option B — From a GBrain repo checkout (skillpack)

```bash
cd /path/to/gbrain
gbrain skillpack install pureclaw-gbrain --workspace /path/to/workspace
```

Skillpack also copies **shared dependency files** listed in `openclaw.plugin.json` (conventions + brain filing rules) and updates the **`<!-- gbrain:skillpack:begin -->` … `<!-- gbrain:skillpack:end -->`** managed block in `AGENTS.md` or `RESOLVER.md`. Do not edit inside those markers by hand.

The directory should contain:

```
pureclaw-gbrain/
  SKILL.md
  AGENTS.md
  INSTALL.md
  _meta.json
```

## Running the Skill

1. **Workspace location** — Ensure the agent’s cwd / docs resolve paths relative to the workspace root (parent of `skills/`). Common convention:

   ```bash
   export OPENCLAW_WORKSPACE=/path/to/workspace
   ```

2. **Health check** — From the workspace (or anywhere `gbrain` is configured):

   ```bash
   gbrain doctor --fast
   ```

3. **Agent routing** — Merge the wake protocol and semantic routing from **`skills/pureclaw-gbrain/AGENTS.md`** into the **human-maintained** part of root **`AGENTS.md`** (outside the skillpack managed fence). Skillpack only adds a compact table row for `pureclaw-gbrain → skills/pureclaw-gbrain/SKILL.md`; it does **not** inject the full wake protocol for you.

Reload or restart the host agent so it picks up `AGENTS.md`.

## First-Time Usage: Wire + Verify

After install:

1. Paste or merge **`skills/pureclaw-gbrain/AGENTS.md`** into root **`AGENTS.md`** (outside the `gbrain:skillpack` fence).
2. Run **`gbrain doctor --fast`** (and full **`gbrain doctor`** if anything looks wrong).
3. Send a short test message that names a placeholder entity, e.g.:

   > "Quick note: Halcyon Labs is evaluating us for a pilot next quarter."

   The agent should call `gbrain put companies/halcyon-labs` (and append to `daily/YYYY-MM-DD`) **without asking permission**, then confirm what was written. You can then `gbrain delete companies/halcyon-labs` if it was only a test.

4. Verify the writes landed in GBrain (not on disk somewhere):

   ```bash
   gbrain search "halcyon"            # should return the page
   gbrain get companies/halcyon-labs
   gbrain get daily/$(date +%Y-%m-%d)
   ```

   If the agent saved to a local `MEMORY.md` or `memory/YYYY-MM-DD.md` instead, the skill was not loaded correctly — re-check that `AGENTS.md` references `skills/pureclaw-gbrain/SKILL.md` and that the agent is reading it.

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
cat /path/to/workspace/MEMORY.md | gbrain put personal/profile

# Daily stream → daily/<date> pages, one per file
for f in /path/to/workspace/memory/*.md; do
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
rm -rf /path/to/workspace/skills/pureclaw-gbrain
```

Or from a GBrain checkout (updates the managed block when applicable):

```bash
gbrain skillpack uninstall pureclaw-gbrain --workspace /path/to/workspace
```

That removes the skill only. It does **not** delete brain data. If you deleted the folder by hand, ensure root **`AGENTS.md`** no longer references `skills/pureclaw-gbrain/SKILL.md`, or adjust the skillpack managed block so it stays consistent.
