#!/usr/bin/env bash
#
# bootstrap-gbrain.sh — install and configure gbrain in a k8s pod (full bootstrap).
#
# Runs install-gbrain.sh then configure-gbrain.sh. For split k8s phases, call
# those scripts directly:
#   scripts/bootstrap/install-gbrain.sh    — once per image or initContainer
#   scripts/bootstrap/configure-gbrain.sh — every pod start (needs Secret)
#
# Idempotent: safe to re-run on pod restart. Skips work that's already done.
#
# Required env:
#   OPENROUTER_API_KEY  — your OpenRouter API key (https://openrouter.ai/keys)
#
# Optional env:
#   GBRAIN_REPO          — git URL of gbrain fork (default: https://github.com/AliAzaz/gbrain.git)
#   GBRAIN_BRANCH        — branch to check out (default: master)
#   GBRAIN_INSTALL_DIR   — where to clone gbrain source (default: /opt/gbrain)
#   GBRAIN_HOME          — brain data directory (default: /data/gbrain)
#   GBRAIN_BRAIN_REPO    — git URL of YOUR markdown brain content; if set,
#                          it is cloned to $GBRAIN_HOME/brain and imported.
#                          When set, the MECE template scaffolder is skipped.
#   GBRAIN_BRAIN_BRANCH  — branch of the brain content repo (default: master)
#   GBRAIN_NO_TEMPLATE   — set to "1" to skip MECE template scaffolding when
#                          no GBRAIN_BRAIN_REPO is provided (default: empty,
#                          which means the MECE skeleton WILL be created)
#   GBRAIN_AUTHOR_NAME   — git commit author for the scaffolded template
#                          (default: "GBrain Bootstrap")
#   GBRAIN_AUTHOR_EMAIL  — git commit author email for the scaffolded template
#                          (default: bootstrap@gbrain.local)
#   GBRAIN_EMBEDDING_MODEL      — override embedding route (default:
#                          openrouter:openai/text-embedding-3-large)
#   GBRAIN_EMBEDDING_DIMENSIONS — vector width (default: 1536)
#   GBRAIN_CHAT_MODEL / GBRAIN_EXPANSION_MODEL — OpenRouter chat/expansion ids
#
# Exit codes:
#   0   bootstrap complete + smoke probes green
#   1   missing required env
#   2   install failure (bun, git, or bun install)
#   3   gbrain init / doctor failure
#   4   OpenRouter probe failure (credentials, network, or model id)
#

# set -euo pipefail

# _ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# _BOOTSTRAP="$_ROOT/scripts/bootstrap"

# bash "$_BOOTSTRAP/install-gbrain.sh"
# bash "$_BOOTSTRAP/configure-gbrain.sh"


#!/usr/bin/env bash
#
# bootstrap-gbrain.sh — install and configure gbrain in a k8s pod.
#
# Idempotent: safe to re-run on pod restart. Skips work that's already done.
#
# Required env:
#   OPENROUTER_API_KEY  — your OpenRouter API key (https://openrouter.ai/keys)
#

GBRAIN_INSTALL_DIR=/opt/gbrain
GBRAIN_HOME=/root/.openclaw/data/gbrain
source "/root/.openclaw/.env"
export OPENROUTER_API_KEY
cp -r $GBRAIN_INSTALL_DIR/skills/pureclaw-gbrain/. /root/.openclaw/skills/pureclaw-gbrain

set -euo pipefail

# -- logging ------------------------------------------------------------------
log() { echo "[bootstrap-gbrain $(date -u +%FT%TZ)] $*" >&2; }
fail() { log "ERROR: $*"; exit "${2:-1}"; }

# Merge OpenRouter routing into $GBRAIN_HOME/.gbrain/config.json (file-plane).
# The gateway reads embedding_model from env OR this file — NOT from
# `gbrain config set` (DB plane). Without this, shells that skip the wrapper
# or /etc/profile.d fall back to openai:text-embedding-3-large and fail with
# "OpenAI embedding requires OPENAI_API_KEY".
persist_gbrain_file_config() {
  local config_path="$BRAIN_DATA/.gbrain/config.json"
  local db_path="$BRAIN_DATA/.gbrain/brain.pglite"
  mkdir -p "$(dirname "$config_path")"
  CONFIG_PATH="$config_path" \
  DB_PATH="$db_path" \
  EMBED_MODEL="$GBRAIN_EMBEDDING_MODEL" \
  EMBED_DIMS="$GBRAIN_EMBEDDING_DIMENSIONS" \
  CHAT_MODEL="$GBRAIN_CHAT_MODEL" \
  EXPANSION_MODEL="$GBRAIN_EXPANSION_MODEL" \
  bun -e '
    const fs = require("fs");
    const path = require("path");
    const p = process.env.CONFIG_PATH;
    let cfg = {};
    try { cfg = JSON.parse(fs.readFileSync(p, "utf8")); } catch {}
    cfg.engine = cfg.engine || "pglite";
    if (!cfg.database_path) cfg.database_path = process.env.DB_PATH;
    cfg.embedding_model = process.env.EMBED_MODEL;
    cfg.embedding_dimensions = parseInt(process.env.EMBED_DIMS, 10);
    cfg.expansion_model = process.env.EXPANSION_MODEL;
    cfg.chat_model = process.env.CHAT_MODEL;
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + "\n", { mode: 0o600 });
  ' || fail "failed to persist OpenRouter routing to $config_path" 3
  log "Persisted OpenRouter routing to $config_path (survives shells without GBRAIN_EMBEDDING_MODEL)"
}

# -- scaffold_brain_template <target-dir> -------------------------------------
# Creates the MECE directory structure described in
# docs/GBRAIN_RECOMMENDED_SCHEMA.md inside <target-dir>:
#   - 20 knowledge directories, each with a README.md resolver
#   - top-level RESOLVER.md (master decision tree)
#   - schema.md (page conventions + person/company/meeting templates)
#   - log.md + index.md
#   - .raw/ sidecars under people/ and companies/
#   - initial git commit so the brain is version-controllable from day one
# Idempotent at the directory level — never clobbers an existing brain repo.
scaffold_brain_template() {
  local target="$1"
  local author_name="${GBRAIN_AUTHOR_NAME:-GBrain Bootstrap}"
  local author_email="${GBRAIN_AUTHOR_EMAIL:-bootstrap@gbrain.local}"

#### if [[ -d "$target/.git" ]] || [[ -f "$target/RESOLVER.md" ]]; then
  if [[ -f "$target/RESOLVER.md" ]] && [[ -f "$target/schema.md" ]]; then
    log "Brain template already exists at $target (skipping scaffold)"
    return 0
  fi

  log "Scaffolding MECE brain template at $target..."
  mkdir -p "$target"
  (
    cd "$target"
    git init -q
    git config --global --add safe.directory $target
    git config user.name "$author_name"
    git config user.email "$author_email"

    # ---- top-level files ---------------------------------------------------
    cat > .gitignore <<'EOF'
.gbrain/
*.tmp
*.swp
.DS_Store
node_modules/
EOF

    cat > README.md <<'EOF'
# Brain

LLM-maintained knowledge base. Structured markdown wiki of people,
companies, deals, meetings, projects, ideas, and concepts — owned and
maintained by your agent.

Read `RESOLVER.md` before creating any page. Read `schema.md` for page
conventions and templates. Every directory has a `README.md` resolver
explaining what goes there and what does NOT.

Generated by `bootstrap-gbrain.sh` from
`docs/GBRAIN_RECOMMENDED_SCHEMA.md` (v0.5.0). Customize freely — the
structure is yours to evolve.
EOF

    cat > RESOLVER.md <<'EOF'
# Resolver — Master Decision Tree

When creating or filing any new page, walk this tree. Every piece of
knowledge has EXACTLY ONE primary home.

## Decision tree — what is the primary subject?

1. A specific named person → `people/`
2. A specific organization (company, fund, nonprofit, gov body) → `companies/`
3. A financial transaction with terms and a decision → `deals/`
4. A record of a specific meeting/call → `meetings/`
5. Something being actively built (has a repo/spec/team) → `projects/`
6. A raw possibility nobody is building yet → `ideas/`
7. A reusable mental model or thesis → `concepts/`
8. A piece of prose publishable as a standalone work → `writing/`
9. Your institution's strategy/org/internal dynamics → `org/`
10. Political or civic landscape (policy, elections, gov) → `civic/`
11. Public narrative / content operations → `media/`
12. A major life program (enduring domain, many projects) → `programs/`
13. Domestic operations (properties, logistics, household) → `household/`
14. Private notes (health, personal reflection) → `personal/`
15. Hiring pipeline (candidate evals, role specs) → `hiring/`
16. A reusable LLM prompt → `prompts/`
17. A raw data import or snapshot → `sources/`
18. Agent deliverables (briefings, digests, research) → `agent/`
19. Unsorted / quick capture (you don't know yet) → `inbox/`
20. Dead / no longer relevant → `archive/`

## Disambiguation tiebreakers

- **Person vs. Company:** Is it about THEM as a human (beliefs,
  relationship, trajectory)? → people/. Is it about the ORG they run? →
  companies/. Both pages link to each other.
- **Concept vs. Idea:** Could you TEACH it as a framework? Concept.
  Could you BUILD it? Idea.
- **Concept vs. Personal:** Would you share it in a professional talk?
  Concept. Is it private reflection? Personal.
- **Idea vs. Project:** Is anyone working on it? Yes → project. No →
  idea. The graduation moment is when work starts.
- **Writing vs. Concepts:** Concept is distilled (~200 words). Writing
  is developed prose (argument, narrative).
- **Writing vs. Media:** Writing is the ARTIFACT (the essay). Media is
  the PRODUCTION + DISTRIBUTION infrastructure.
- **Org vs. Programs:** org/ is institutional knowledge ABOUT your
  organization. programs/ is your personal role + priorities WITHIN it.
- **Civic vs. People:** Political figures get people/ pages. Their
  legislative agenda + civic positioning goes in civic/.
- **Household vs. Personal:** Would a PA execute on it? → household
  (operational). Private reflection? → personal (inner life).
- **Sources vs. .raw/:** Per-entity enrichment data → .raw/ sidecar
  next to the entity. Bulk multi-entity imports → sources/.

## MECE check

If something genuinely doesn't fit any category, file it in `inbox/`
and flag it. That's a signal the schema needs to evolve. Don't force
the wrong category.
EOF

    cat > schema.md <<'EOF'
# Schema — Page Conventions

Every page has TWO layers separated by `---`:

- **Above the line — Compiled Truth.** Always current, rewritten on
  every new signal. Starts with a one-paragraph executive summary.
  Includes State, Open Threads, See Also.
- **Below the line — Timeline.** Append-only. Reverse-chronological.
  Each entry: date, source, what happened.

## Person template

```markdown
# Person Name

> Executive summary: who they are, why they matter, what you should
> know walking into any interaction with them.

## State
- **Role:** Current title
- **Company:** Current org
- **Relationship:** To you (friend, colleague, investor, etc.)
- **Key context:** 2-4 bullets of what matters right now

## What They Believe
- [Belief] — observed: [tweet/meeting/article, date]
- [Belief] — self-described: [interview/bio, date]
- [Belief] — inferred: [pattern across N interactions, confidence: high/medium/low]

## What They're Building
## What Motivates Them
## Communication Style
## Hobby Horses
## Assessment
- **Strengths:**
- **Gaps:**
- **Net read:**
- **Confidence:** high (5+ interactions) / medium (2-4) / low (1)
- **Last assessed:** YYYY-MM-DD

## Trajectory
## Relationship
## Contact
## Network
## Open Threads

---

## Timeline
- **YYYY-MM-DD** | Source — What happened.
```

## Company template

```markdown
# Company Name

> What they do, stage, why they matter.

## State
- **What:** One-line description
- **Stage:** Seed / Series A / Growth / Public
- **Key people:** Names with links to people pages
- **Key metrics:** Revenue, headcount, funding
- **Connection:** How they relate to your world

## Open Threads

---

## Timeline
```

## Meeting template

```markdown
# Meeting Title

> YOUR analysis — not a copy of the AI meeting notes.
> What matters given everything else going on.

## Attendees
## Key Decisions
## Action Items
## Connections to other brain pages

---

## Full Transcript
```

## Canonical slugs

- People: `first-last.md` (lowercase, hyphens)
- Companies: `company-name.md`
- Collisions: disambiguate (`david-liu-crustdata.md`)

The filename IS the entity identity. All cross-references use the slug.

## Epistemic discipline (people pages)

- Every claim cites its source. Three source types: `observed`,
  `self-described`, `inferred`.
- Confidence tracks interaction count. One meeting = low. Five+ = high.
- Never generalize from a single data point.
- User corrections override everything.
EOF

    # log.md (append-only chronological record)
    cat > log.md <<EOF
# Log

Chronological record of brain operations. Append-only.

- **$(date -u +%Y-%m-%d) | bootstrap** — MECE template scaffolded.
EOF

    # index.md (content catalog, rebuild periodically)
    cat > index.md <<'EOF'
# Index

Content catalog. Rebuild periodically with `gbrain stats` /
`gbrain doctor` or by re-walking the directory tree.

(Empty on first scaffold — populates as pages are created.)
EOF

    # ---- MECE directories with per-dir READMEs (resolvers) -----------------
    _readme() {
      local dirname="$1"
      shift
      mkdir -p "$dirname"
      cat > "$dirname/README.md" <<EOF
# $dirname/

$@
EOF
      # .gitkeep so git tracks the empty directory
      touch "$dirname/.gitkeep"
    }

    _readme "people" \
      "One page per human being.

## What goes here
- Anyone you've had a 1:1 or small-group meeting with
- Key colleagues, partners, direct collaborators
- Anyone with a strong working relationship
- Family, close friends, inner circle

## What does NOT go here
- The organizations they work for → \`companies/\`
- Hiring candidates being actively evaluated → \`hiring/\`
- Random names from mass guest lists with no interaction
- Political figures' civic positioning → \`civic/\` (but they still
  get a people/ page for who they are as a human)

## Slug convention
\`first-last.md\` — lowercase, hyphens for spaces.
Collisions: disambiguate (\`david-liu-crustdata.md\`).

## Sidecar
Per-person raw enrichment data lives in \`.raw/<slug>.json\`."

    _readme "companies" \
      "One page per organization (company, fund, nonprofit, gov body).

## What goes here
- Companies you do business with
- Funds you interact with
- Organizations relevant to your work

## What does NOT go here
- Individual people at the company → \`people/\` (cross-link both)
- A specific deal with the company → \`deals/\`
- Your own institution's strategy → \`org/\`

## Slug convention
\`company-name.md\` — lowercase, hyphens.

## Sidecar
Per-company raw enrichment data lives in \`.raw/<slug>.json\`."

    _readme "deals" \
      "Financial transactions with terms and a decision to make.

## What goes here
- Investment opportunities (rounds you're considering)
- Acquisitions, partnerships with financial terms
- Anything that requires a yes/no decision with money attached

## What does NOT go here
- The company doing the deal → \`companies/\` (cross-link)
- General company information without a transaction → \`companies/\`"

    _readme "meetings" \
      "Records of specific meetings/calls that happened at a specific time.

## What goes here
- Meeting transcripts with your analysis above the line
- Important calls with attendees and decisions

## What does NOT go here
- The people who attended → \`people/\` (cross-link)
- Recurring meeting templates → \`prompts/\`

## Slug convention
\`YYYY-MM-DD-meeting-topic.md\`"

    _readme "projects" \
      "Things being actively built — has a repo, spec, team, or active work.

## What goes here
- Software projects under development
- Initiatives with named owners and timelines
- Anything that has 'graduated' from idea to active work

## What does NOT go here
- Raw possibilities nobody is building → \`ideas/\`
- The major life domain the project sits in → \`programs/\`"

    _readme "ideas" \
      "Raw possibilities nobody is building yet.

## What goes here
- Speculative concepts you might pursue
- Things worth exploring but not yet committed to

## What does NOT go here
- Anything actively being built → \`projects/\`
- Mental models you'd teach as frameworks → \`concepts/\`

## Graduation
When someone starts working on an idea, move it to \`projects/\` and
keep a link from here pointing to the new project page."

    _readme "concepts" \
      "Reusable mental models, frameworks, theses about how the world works.

## What goes here
- Frameworks you'd teach in a professional talk
- Distilled mental models (~200 words of compiled truth)
- Theses about your domain

## What does NOT go here
- Developed prose / essays → \`writing/\`
- Private reflection → \`personal/\`
- Possibilities to build → \`ideas/\`"

    _readme "writing" \
      "Prose artifacts — essays, philosophy, drafts publishable as standalone work.

## What goes here
- Long-form essays
- Argument-driven prose
- Drafts of public writing

## What does NOT go here
- Distilled frameworks (~200 words) → \`concepts/\`
- Publication infrastructure or social monitoring → \`media/\`"

    _readme "programs" \
      "Major life workstreams — the forest, not the trees.

## What goes here
- Enduring domains of commitment that contain multiple projects
- Long-running themes (e.g., 'building company X', 'becoming healthier')

## What does NOT go here
- Specific projects within a program → \`projects/\` (cross-link)
- Your institution's strategy → \`org/\`"

    _readme "org" \
      "Your institution's strategy, org chart, processes, internal dynamics.

## What goes here
- Institutional strategy documents
- Internal processes and operations
- Your organization's structure

## What does NOT go here
- Your personal role or priorities within the org → \`programs/\`
- External companies → \`companies/\`"

    _readme "civic" \
      "Political landscape, policy, government, civic actors.

## What goes here
- Legislative agendas, policy debates
- Election context, government structure
- Civic positioning of political figures

## What does NOT go here
- The political figures themselves as humans → \`people/\` (cross-link)"

    _readme "media" \
      "Public narrative, content operations, social monitoring.

## What goes here
- Content production pipeline
- Social monitoring infrastructure
- Published posts and their performance

## What does NOT go here
- The essays themselves → \`writing/\`"

    _readme "personal" \
      "Private notes, health, personal reflection, inner life.

## What goes here
- Health logs, personal reflections
- Private thoughts not meant for sharing

## What does NOT go here
- Operational household stuff (PA would execute) → \`household/\`
- Anything you'd share in a professional talk → \`concepts/\`"

    _readme "household" \
      "Domestic operations — properties, logistics, household management.

## What goes here
- Property management, vendors, contractors
- Household logistics a PA would handle

## What does NOT go here
- Private reflections → \`personal/\`"

    _readme "hiring" \
      "Candidate pipelines and evaluations.

## What goes here
- Role specs
- Interview notes
- Active candidate evaluations

## What does NOT go here
- People you already hired → \`people/\`
- People you know but aren't evaluating → \`people/\`"

    _readme "sources" \
      "Raw data imports and archived snapshots.

## What goes here
- Bulk multi-entity imports (CSVs, JSON dumps)
- Periodic API exports
- Archive snapshots

## What does NOT go here
- Per-entity raw enrichment data → \`.raw/\` sidecar next to the entity"

    _readme "prompts" \
      "Reusable LLM prompt library.

## What goes here
- Templates for getting specific outputs from models
- Reusable system prompts

## What does NOT go here
- One-off prompts you used once → \`inbox/\` or discard"

    _readme "agent" \
      "Agent deliverables — briefings, digests, research the agent produced.

## What goes here
- Daily briefings
- Research reports
- Synthesized output the agent generated for your reading

## What does NOT go here
- Raw source material that fed the synthesis → \`sources/\`
- Notes you wrote → wherever they belong by subject"

    _readme "inbox" \
      "Unsorted quick captures (temporary).

## What goes here
- Things you don't yet know where to file
- Quick captures pending triage

## What does NOT go here
- Anything you DO know the home of — file it properly

If many items pile up here, it's a signal the schema needs to evolve."

    _readme "archive" \
      "Dead pages — no longer relevant, kept as historical record.

## What goes here
- Companies that died
- Ended relationships
- Resolved deals you want to remember
- Pages that no longer warrant compiled truth at the top

## What does NOT go here
- Active pages, even if dormant — keep them in their primary directory"

    # .raw/ subdirectories for the two highest-volume enrichment surfaces
    mkdir -p people/.raw companies/.raw
    touch people/.raw/.gitkeep companies/.raw/.gitkeep

    # ---- initial commit ----------------------------------------------------
    git add -A
    git commit -q -m "init: MECE brain template scaffolded by bootstrap-gbrain.sh

20 directories from docs/GBRAIN_RECOMMENDED_SCHEMA.md v0.5.0, each
with a README.md resolver, plus top-level RESOLVER.md + schema.md +
log.md + index.md and .raw/ sidecars under people/ + companies/."
  )
  log "Brain template scaffolded: 20 directories, 25 files, 1 commit."
}

# -- 1. Validate required env -------------------------------------------------
[[ -n "${OPENROUTER_API_KEY:-}" ]] || fail "OPENROUTER_API_KEY is required (https://openrouter.ai/keys)" 1

REPO="${GBRAIN_REPO:-https://github.com/AliAzaz/gbrain.git}"
BRANCH="${GBRAIN_BRANCH:-master}"
INSTALL_DIR="${GBRAIN_INSTALL_DIR:-/opt/gbrain}"
BRAIN_DATA="${GBRAIN_HOME:-/data/gbrain}"

export GBRAIN_HOME="$BRAIN_DATA"
export HOME="${HOME:-/root}"        # k8s containers sometimes leave HOME unset
# OpenRouter routing defaults (override via env before bootstrap). Used by the
# gbrain wrapper, profile.d, init flags, and persist_gbrain_file_config().
GBRAIN_EMBEDDING_MODEL="${GBRAIN_EMBEDDING_MODEL:-openrouter:openai/text-embedding-3-large}"
GBRAIN_EMBEDDING_DIMENSIONS="${GBRAIN_EMBEDDING_DIMENSIONS:-1536}"
GBRAIN_CHAT_MODEL="${GBRAIN_CHAT_MODEL:-openrouter:anthropic/claude-sonnet-4.5}"
GBRAIN_EXPANSION_MODEL="${GBRAIN_EXPANSION_MODEL:-openrouter:openai/gpt-4o-mini}"
export GBRAIN_EMBEDDING_MODEL GBRAIN_EMBEDDING_DIMENSIONS GBRAIN_CHAT_MODEL GBRAIN_EXPANSION_MODEL
mkdir -p "$BRAIN_DATA" "$(dirname "$INSTALL_DIR")"

log "config: REPO=$REPO BRANCH=$BRANCH"
log "config: INSTALL_DIR=$INSTALL_DIR GBRAIN_HOME=$BRAIN_DATA"

# -- 2. Install prerequisites -------------------------------------------------
# Most slim k8s base images lack git + curl. Detect package manager and install.
if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  log "Installing git + curl..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y --no-install-recommends git curl ca-certificates unzip >/dev/null
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache git curl ca-certificates bash >/dev/null
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q git curl ca-certificates >/dev/null
  else
    fail "No supported package manager found (apt/apk/dnf); install git + curl manually in base image" 2
  fi
fi

# -- 3. Install Bun (idempotent) ----------------------------------------------
if ! command -v bun >/dev/null 2>&1; then
  log "Installing Bun..."
  curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1 || fail "bun installer failed" 2
fi
export PATH="$HOME/.bun/bin:$PATH"
command -v bun >/dev/null 2>&1 || fail "bun not on PATH after install" 2
log "bun version: $(bun --version)"

# -- 4. Clone or update the gbrain fork ---------------------------------------
if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  log "Cloning $REPO (branch $BRANCH) into $INSTALL_DIR..."
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO" "$INSTALL_DIR" || fail "git clone failed" 2
else
  log "Pulling latest $BRANCH in $INSTALL_DIR..."
  #git -C "$INSTALL_DIR" fetch --depth 1 origin "$BRANCH"
  #git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH"
fi

# -- 5. Install gbrain dependencies + link the binary -------------------------
cd "$INSTALL_DIR"
log "Running bun install..."
bun install --frozen-lockfile >/dev/null 2>&1 || bun install >/dev/null 2>&1 || fail "bun install failed" 2

log "Linking gbrain binary..."
bun link >/dev/null 2>&1 || true   # idempotent; second run is a no-op or warning


# Resolve absolute paths to bun + gbrain entrypoint NOW, bake into wrapper.
# This avoids reliance on HOME being set when the wrapper runs (the agent
# process may have a different HOME or none at all).
BUN_BIN="$(command -v bun || echo "$HOME/.bun/bin/bun")"
GBRAIN_CLI="$INSTALL_DIR/src/cli.ts"

# Install an env-injecting wrapper at BOTH /usr/local/bin/gbrain AND
# $HOME/.bun/bin/gbrain (overwriting bun's link wrapper). Reason: bun's
# install adds $HOME/.bun/bin to PATH ahead of /usr/local/bin in the
# user's shell, so a wrapper only at /usr/local/bin gets shadowed.
# Overwriting both ensures every caller — agent process, kubectl exec
# shell, cron, anything — gets the env injection regardless of PATH order.
#
# No recursion concern: each wrapper exec's `bun run <cli.ts>` directly,
# not the other wrapper.
log "Installing env-injecting gbrain wrappers (both /usr/local/bin/ and ~/.bun/bin/)..."

WRAPPER_BODY="#!/usr/bin/env bash
# gbrain env-injecting wrapper — written by bootstrap-gbrain.sh on $(date -u +%FT%TZ).
# Guarantees GBRAIN_HOME + OpenRouter routing are set for every gbrain
# invocation, regardless of the caller's environment state. The k8s
# Deployment YAML env block is the canonical fix; this wrapper is the
# defense-in-depth fallback so deployments without that block still work.

# Brain location
export GBRAIN_HOME=\"\${GBRAIN_HOME:-$BRAIN_DATA}\"

# OpenRouter routing (file/env-plane only — gbrain config set does NOT
# propagate these — honor any overrides the caller already set).
export GBRAIN_EMBEDDING_MODEL=\"\${GBRAIN_EMBEDDING_MODEL:-$GBRAIN_EMBEDDING_MODEL}\"
export GBRAIN_EMBEDDING_DIMENSIONS=\"\${GBRAIN_EMBEDDING_DIMENSIONS:-$GBRAIN_EMBEDDING_DIMENSIONS}\"
export GBRAIN_CHAT_MODEL=\"\${GBRAIN_CHAT_MODEL:-$GBRAIN_CHAT_MODEL}\"
export GBRAIN_EXPANSION_MODEL=\"\${GBRAIN_EXPANSION_MODEL:-$GBRAIN_EXPANSION_MODEL}\"

# OPENROUTER_API_KEY is intentionally NOT injected here — it MUST come
# from the k8s Secret via the container's env. If it's missing, gbrain
# will fail loudly on the first provider call rather than appear to work
# with a stale baked-in value.

# Exec bun directly against the CLI entrypoint (absolute paths baked in
# at install time so the wrapper doesn't depend on HOME or PATH).
exec \"$BUN_BIN\" run \"$GBRAIN_CLI\" \"\$@\"
"

# Write the wrapper to /usr/local/bin/gbrain (regular file, fresh write).
echo "$WRAPPER_BODY" > /usr/local/bin/gbrain
chmod 0755 /usr/local/bin/gbrain

# Replace the bun-linked entry at $HOME/.bun/bin/gbrain with the wrapper.
# CRITICAL: `bun link` creates this as a SYMLINK pointing at
# /opt/gbrain/src/cli.ts. A naive `> ~/.bun/bin/gbrain` would dereference
# the symlink and CORRUPT cli.ts (we hit this bug once already). Always
# `rm` first to delete the symlink (which doesn't touch the target),
# then write a fresh regular file in its place.
#
# Why we need this: bun's installer puts ~/.bun/bin at the front of PATH.
# If we leave the symlink in place, the symlink wins over the wrapper at
# /usr/local/bin/gbrain — and the agent process calling `gbrain` skips
# the env injection. Replacing the symlink with the same wrapper makes
# every PATH-resolved call inject env, regardless of which path wins.
if [[ -L "$HOME/.bun/bin/gbrain" ]] || [[ -e "$HOME/.bun/bin/gbrain" ]]; then
  rm -f "$HOME/.bun/bin/gbrain"   # `rm` removes the symlink, NOT its target
  echo "$WRAPPER_BODY" > "$HOME/.bun/bin/gbrain"
  chmod 0755 "$HOME/.bun/bin/gbrain"
  log "Replaced bun-linked entry at $HOME/.bun/bin/gbrain with env-injecting wrapper (symlink removed first to avoid corrupting cli.ts)"
fi

command -v gbrain >/dev/null 2>&1 || fail "gbrain binary missing after install" 2
log "gbrain version: $(gbrain --version 2>/dev/null || echo unknown)"
log "Wrappers installed at both /usr/local/bin/gbrain AND $HOME/.bun/bin/gbrain."
log "Note: re-running 'bun link' would recreate the symlink at \$HOME/.bun/bin/gbrain"
log "and clobber the wrapper there. The canonical fix is the k8s Deployment YAML"
log "env block — see deploy/k8s-gbrain-env.example.yaml and /etc/profile.d/gbrain.sh."

# -- 6. Persist OpenRouter env for the agent process --------------------------
# These keys size the vector index and are file/env-only by design in gbrain
# (`gbrain config set` does NOT propagate them — see src/core/config.ts:191).
#
# Critical: the bootstrap's `export` only lives in the bootstrap's shell scope.
# When this script exits, the agent process — started by the container's
# entrypoint, NOT by this script — never sees them unless we also write
# /etc/profile.d/gbrain.sh, /etc/environment, AND $GBRAIN_HOME/.gbrain/config.json.
log "Routing: embed=$GBRAIN_EMBEDDING_MODEL dims=$GBRAIN_EMBEDDING_DIMENSIONS"
log "Routing: chat=$GBRAIN_CHAT_MODEL expansion=$GBRAIN_EXPANSION_MODEL"

# Persist to /etc/profile.d/ — every new login/non-login shell sources this
# (assuming the container's shell is bash and respects /etc/profile.d/, which
# is the default for Ubuntu/Debian/Alpine/RHEL). Skip if we can't write
# (rootless container, read-only fs).
PROFILE_FILE="/etc/profile.d/gbrain.sh"
if [[ -w "/etc/profile.d" ]] || [[ ! -e "$PROFILE_FILE" && -w "/etc" ]]; then
  cat > "$PROFILE_FILE" <<EOF
# gbrain — written by bootstrap-gbrain.sh on $(date -u +%FT%TZ)
# Source: $REPO @ $BRANCH
export GBRAIN_HOME="$BRAIN_DATA"
export GBRAIN_EMBEDDING_MODEL="$GBRAIN_EMBEDDING_MODEL"
export GBRAIN_EMBEDDING_DIMENSIONS="$GBRAIN_EMBEDDING_DIMENSIONS"
export GBRAIN_CHAT_MODEL="$GBRAIN_CHAT_MODEL"
export GBRAIN_EXPANSION_MODEL="$GBRAIN_EXPANSION_MODEL"
# OPENROUTER_API_KEY is supplied by the k8s Secret at pod start.
# Add gbrain binary path defensively (bun link sometimes lands here).
case ":\$PATH:" in
  *":\$HOME/.bun/bin:"*) ;;
  *) export PATH="\$HOME/.bun/bin:\$PATH" ;;
esac
EOF
  chmod 0644 "$PROFILE_FILE"
  log "Persisted env to $PROFILE_FILE (new shells will inherit GBRAIN_HOME, model routing, and PATH)"
else
  log "warn: /etc/profile.d/ not writable; agent process may need env set in k8s Deployment yaml instead"
fi

# Also write to /etc/environment for non-shell PID 1 children (some init
# systems read this; Docker/k8s entrypoints typically don't, but it's free).
ENV_FILE="/etc/environment"
if [[ -w "$ENV_FILE" ]] || [[ ! -e "$ENV_FILE" && -w "/etc" ]]; then
  # Remove any prior gbrain block, then append fresh
  if [[ -e "$ENV_FILE" ]]; then
    sed -i.bak '/^# gbrain-bootstrap-begin/,/^# gbrain-bootstrap-end/d' "$ENV_FILE" 2>/dev/null || true
    rm -f "${ENV_FILE}.bak"
  fi
  cat >> "$ENV_FILE" <<EOF
# gbrain-bootstrap-begin (written $(date -u +%FT%TZ))
GBRAIN_HOME=$BRAIN_DATA
GBRAIN_EMBEDDING_MODEL=$GBRAIN_EMBEDDING_MODEL
GBRAIN_EMBEDDING_DIMENSIONS=$GBRAIN_EMBEDDING_DIMENSIONS
GBRAIN_CHAT_MODEL=$GBRAIN_CHAT_MODEL
GBRAIN_EXPANSION_MODEL=$GBRAIN_EXPANSION_MODEL
# gbrain-bootstrap-end
EOF
  log "Persisted env to $ENV_FILE (PID-1 children that read /etc/environment will inherit)"
fi

### -- 7. Initialize the brain (idempotent) -------------------------------------
### PGLite stores its files under $GBRAIN_HOME/.gbrain/. If the dir exists, init
### is a no-op pass-through for migrations only.
##BRAIN_DB="$BRAIN_DATA/.gbrain/brain.pglite"
##if [[ ! -e "$BRAIN_DB" ]]; then
##  log "Initializing brain at $BRAIN_DATA..."
##  # Pipe empty stdin so the search-mode picker auto-accepts the default
##  # (gbrain detects non-TTY and respects it; this is belt + suspenders).
##  printf '\n' | gbrain init --pglite \
##    --embedding-model "$GBRAIN_EMBEDDING_MODEL" \
##    --embedding-dimensions "$GBRAIN_EMBEDDING_DIMENSIONS" \
##    --expansion-model "$GBRAIN_EXPANSION_MODEL" \
##    --chat-model "$GBRAIN_CHAT_MODEL" \
##    || fail "gbrain init failed" 3
##else
##  log "Brain already initialized at $BRAIN_DATA (running migrations only)..."
##  gbrain apply-migrations --yes >/dev/null 2>&1 || log "warn: apply-migrations exited non-zero; continuing"
##fi

BRAIN_DB="$BRAIN_DATA/.gbrain/brain.pglite"
if [[ ! -e "$BRAIN_DB" ]]; then
  log "Initializing brain at $BRAIN_DATA..."
  printf '\n' | gbrain init --pglite \
    --embedding-model "$GBRAIN_EMBEDDING_MODEL" \
    --embedding-dimensions "$GBRAIN_EMBEDDING_DIMENSIONS" \
    --expansion-model "$GBRAIN_EXPANSION_MODEL" \
    --chat-model "$GBRAIN_CHAT_MODEL" \
    || fail "gbrain init failed" 3
else
  #log "Active Database schema found at $BRAIN_DB (Running migrations only)..."
  log "Validation PASS: Database found on PV. Skipping init and migration layers."
fi

# File-plane routing: survives kubectl exec shells that skip profile.d / wrapper.
persist_gbrain_file_config

# -- 8. Health checks ---------------------------------------------------------
log "Running gbrain doctor..."
gbrain doctor --json > "$BRAIN_DATA/last-doctor.json" || fail "gbrain doctor failed (see $BRAIN_DATA/last-doctor.json)" 3
log "doctor passed; report saved to $BRAIN_DATA/last-doctor.json"

# probe_provider <touchpoint> <model> — run a provider smoke test, surface
# the full command output on failure so the operator can diagnose without
# re-running the command manually.
probe_provider() {
  local touchpoint="$1"
  local model="$2"
  local logfile="$BRAIN_DATA/last-probe-$touchpoint.log"
  local exit_code=0

  log "Probing OpenRouter $touchpoint endpoint ($model)..."
  set +e
  gbrain providers test --touchpoint "$touchpoint" --model "$model" > "$logfile" 2>&1
  exit_code=$?
  set -e

  if [[ $exit_code -ne 0 ]]; then
    log "Probe exited non-zero ($exit_code). Captured output:"
    sed 's/^/    /' "$logfile" >&2
    fail "OpenRouter $touchpoint probe failed; see $logfile" 4
  fi

  if ! grep -q "All probes green" "$logfile"; then
    log "Probe exited 0 but did not print 'All probes green'. Captured output:"
    sed 's/^/    /' "$logfile" >&2
    fail "OpenRouter $touchpoint probe returned success-marker-missing; see $logfile" 4
  fi

  log "OpenRouter $touchpoint probe: OK"
}

probe_provider embedding "$GBRAIN_EMBEDDING_MODEL"
probe_provider chat      "$GBRAIN_CHAT_MODEL"

# -- 9. Brain content: clone existing repo OR scaffold MECE template ---------
# Precedence:
#   1. If $GBRAIN_BRAIN_REPO is set → clone it (scaffold skipped). Existing
#      content owns its own structure.
#   2. Else, if $GBRAIN_NO_TEMPLATE != "1" → scaffold a fresh MECE brain at
#      $GBRAIN_HOME/brain following docs/GBRAIN_RECOMMENDED_SCHEMA.md.
#   3. Else, leave $GBRAIN_HOME/brain empty (operator opted out).
# Either path ends with `gbrain import` + `gbrain embed --stale` so the
# brain pages (real or skeletal README resolvers) are queryable.
BRAIN_CONTENT="$BRAIN_DATA/brain"

if [[ -n "${GBRAIN_BRAIN_REPO:-}" ]]; then
  BRAIN_CONTENT_BRANCH="${GBRAIN_BRAIN_BRANCH:-master}"
  if [[ ! -d "$BRAIN_CONTENT/.git" ]]; then
    log "Cloning brain content from $GBRAIN_BRAIN_REPO (branch $BRAIN_CONTENT_BRANCH)..."
    git clone --branch "$BRAIN_CONTENT_BRANCH" "$GBRAIN_BRAIN_REPO" "$BRAIN_CONTENT"
  else
    log "Pulling latest brain content from $GBRAIN_BRAIN_REPO..."
    git -C "$BRAIN_CONTENT" fetch origin "$BRAIN_CONTENT_BRANCH"
    git -C "$BRAIN_CONTENT" reset --hard "origin/$BRAIN_CONTENT_BRANCH"
  fi

elif [[ "${GBRAIN_NO_TEMPLATE:-0}" != "1" ]]; then
  scaffold_brain_template "$BRAIN_CONTENT"
else
  log "Skipping brain content (GBRAIN_BRAIN_REPO unset and GBRAIN_NO_TEMPLATE=1)"
fi

# Import + embed whatever landed (real brain repo OR scaffolded skeleton).
if [[ -d "$BRAIN_CONTENT" ]] && [[ -n "$(find "$BRAIN_CONTENT" -maxdepth 3 -name '*.md' -print -quit 2>/dev/null)" ]]; then
  log "Importing brain content (no-embed)..."
  gbrain import "$BRAIN_CONTENT" --no-embed
  log "Embedding stale chunks..."
  gbrain embed --stale || fail "gbrain embed --stale failed (check OPENROUTER_API_KEY and routing)" 3
  log "Brain content imported."
fi

# -- 9b. OpenRouter env verification (read-only) ------------------------------
VERIFY_SCRIPT="$INSTALL_DIR/scripts/verify-gbrain-openrouter-env.sh"
if [[ -x "$VERIFY_SCRIPT" ]]; then
  log "Running OpenRouter env verification..."
  GBRAIN_HOME="$BRAIN_DATA" "$VERIFY_SCRIPT" || fail "OpenRouter env verification failed; see output above" 3
else
  log "warn: $VERIFY_SCRIPT not found or not executable; skipping env verification"
fi

# -- 10. Final summary --------------------------------------------------------
log "──────────────────────────────────────────"
log "GBrain bootstrap complete."
log "  Install dir:  $INSTALL_DIR"
log "  Brain dir:    $BRAIN_DATA"
log "  Binary:       $(command -v gbrain)"
log "  Version:      $(gbrain --version 2>/dev/null || echo unknown)"
log "  Pages:        $(gbrain stats 2>/dev/null | grep -i 'page' | head -1 || echo 'gbrain stats failed')"
log "──────────────────────────────────────────"
log "Next: keep this pod alive (e.g. exec 'tail -f /dev/null'),"
log "      run 'gbrain serve --http --port 3131' to expose MCP over HTTP,"
log "      or run 'gbrain serve' for stdio MCP."
