#!/usr/bin/env bash
#
# install-gbrain.sh — install toolchain and gbrain source (k8s image / initContainer phase).
#
# Idempotent: safe to re-run. Does NOT require OPENROUTER_API_KEY.
#
# Optional env:
#   GBRAIN_REPO, GBRAIN_BRANCH, GBRAIN_INSTALL_DIR, GBRAIN_HOME
#   GBRAIN_EMBEDDING_MODEL, GBRAIN_EMBEDDING_DIMENSIONS, GBRAIN_CHAT_MODEL, GBRAIN_EXPANSION_MODEL
#   (baked into wrappers; must match configure phase if GBRAIN_HOME changes)
#
# Exit codes:
#   0   install complete
#   2   install failure (bun, git, or bun install)

set -euo pipefail

log() { echo "[install-gbrain $(date -u +%FT%TZ)] $*" >&2; }
fail() { log "ERROR: $*"; exit "${2:-1}"; }

gbrain_bootstrap_init_env() {
  REPO="${GBRAIN_REPO:-https://github.com/AliAzaz/gbrain.git}"
  BRANCH="${GBRAIN_BRANCH:-master}"
  INSTALL_DIR="${GBRAIN_INSTALL_DIR:-/opt/gbrain}"
  BRAIN_DATA="${GBRAIN_HOME:-/data/gbrain}"
  export GBRAIN_HOME="$BRAIN_DATA"
  export HOME="${HOME:-/root}"
  GBRAIN_EMBEDDING_MODEL="${GBRAIN_EMBEDDING_MODEL:-openrouter:openai/text-embedding-3-large}"
  GBRAIN_EMBEDDING_DIMENSIONS="${GBRAIN_EMBEDDING_DIMENSIONS:-1536}"
  GBRAIN_CHAT_MODEL="${GBRAIN_CHAT_MODEL:-openrouter:anthropic/claude-sonnet-4.5}"
  GBRAIN_EXPANSION_MODEL="${GBRAIN_EXPANSION_MODEL:-openrouter:openai/gpt-4o-mini}"
  export GBRAIN_EMBEDDING_MODEL GBRAIN_EMBEDDING_DIMENSIONS GBRAIN_CHAT_MODEL GBRAIN_EXPANSION_MODEL
  mkdir -p "$BRAIN_DATA" "$(dirname "$INSTALL_DIR")"
}

gbrain_bootstrap_init_env

log "config: REPO=$REPO BRANCH=$BRANCH"
log "config: INSTALL_DIR=$INSTALL_DIR GBRAIN_HOME=$BRAIN_DATA"

# -- Install prerequisites -----------------------------------------------------
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

# -- Install Bun (idempotent) --------------------------------------------------
if ! command -v bun >/dev/null 2>&1; then
  log "Installing Bun..."
  curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1 || fail "bun installer failed" 2
fi
export PATH="$HOME/.bun/bin:$PATH"
command -v bun >/dev/null 2>&1 || fail "bun not on PATH after install" 2
log "bun version: $(bun --version)"

# -- Clone or update the gbrain fork -------------------------------------------
if [[ ! -d "$INSTALL_DIR/.git" ]]; then
  log "Cloning $REPO (branch $BRANCH) into $INSTALL_DIR..."
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 --branch "$BRANCH" "$REPO" "$INSTALL_DIR" || fail "git clone failed" 2
else
  log "Pulling latest $BRANCH in $INSTALL_DIR..."
  git -C "$INSTALL_DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH"
fi

# -- Install gbrain dependencies + link the binary -----------------------------
cd "$INSTALL_DIR"
log "Running bun install..."
bun install --frozen-lockfile >/dev/null 2>&1 || bun install >/dev/null 2>&1 || fail "bun install failed" 2

log "Linking gbrain binary..."
bun link >/dev/null 2>&1 || true

BUN_BIN="$(command -v bun || echo "$HOME/.bun/bin/bun")"
GBRAIN_CLI="$INSTALL_DIR/src/cli.ts"

log "Installing env-injecting gbrain wrappers (both /usr/local/bin/ and ~/.bun/bin/)..."

WRAPPER_BODY="#!/usr/bin/env bash
# gbrain env-injecting wrapper — written by install-gbrain.sh on $(date -u +%FT%TZ).
# Guarantees GBRAIN_HOME + OpenRouter routing are set for every gbrain
# invocation, regardless of the caller's environment state. The k8s
# Deployment YAML env block is the canonical fix; this wrapper is the
# defense-in-depth fallback so deployments without that block still work.

export GBRAIN_HOME=\"\${GBRAIN_HOME:-$BRAIN_DATA}\"

export GBRAIN_EMBEDDING_MODEL=\"\${GBRAIN_EMBEDDING_MODEL:-$GBRAIN_EMBEDDING_MODEL}\"
export GBRAIN_EMBEDDING_DIMENSIONS=\"\${GBRAIN_EMBEDDING_DIMENSIONS:-$GBRAIN_EMBEDDING_DIMENSIONS}\"
export GBRAIN_CHAT_MODEL=\"\${GBRAIN_CHAT_MODEL:-$GBRAIN_CHAT_MODEL}\"
export GBRAIN_EXPANSION_MODEL=\"\${GBRAIN_EXPANSION_MODEL:-$GBRAIN_EXPANSION_MODEL}\"

exec \"$BUN_BIN\" run \"$GBRAIN_CLI\" \"\$@\"
"

echo "$WRAPPER_BODY" > /usr/local/bin/gbrain
chmod 0755 /usr/local/bin/gbrain

if [[ -L "$HOME/.bun/bin/gbrain" ]] || [[ -e "$HOME/.bun/bin/gbrain" ]]; then
  rm -f "$HOME/.bun/bin/gbrain"
  echo "$WRAPPER_BODY" > "$HOME/.bun/bin/gbrain"
  chmod 0755 "$HOME/.bun/bin/gbrain"
  log "Replaced bun-linked entry at $HOME/.bun/bin/gbrain with env-injecting wrapper"
fi

command -v gbrain >/dev/null 2>&1 || fail "gbrain binary missing after install" 2
log "gbrain version: $(gbrain --version 2>/dev/null || echo unknown)"
log "Install complete: $INSTALL_DIR"
