#!/usr/bin/env bash
#
# configure-openclaw.sh — OpenClaw workspace hooks after gbrain configure.
# Sourced/called from configure-gbrain.sh when OpenClaw paths are detected.
#
set -euo pipefail

log() { echo "[configure-openclaw $(date -u +%FT%TZ)] $*" >&2; }

OPENCLAW_HOME="${OPENCLAW_HOME:-${HOME}/.openclaw}"
# Skills + AGENTS.md resolve from OpenClaw home (e.g. /root/.openclaw/skills/pureclaw-gbrain).
OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-$OPENCLAW_HOME}"
INSTALL_DIR="${GBRAIN_INSTALL_DIR:-/opt/gbrain}"

if [[ -z "${GBRAIN_HOME:-}" ]] && [[ -d "$OPENCLAW_HOME" ]]; then
  export GBRAIN_HOME="$OPENCLAW_HOME/data/gbrain"
  mkdir -p "$GBRAIN_HOME"
  log "GBRAIN_HOME defaulting to $GBRAIN_HOME (OpenClaw layout)"
fi
BRAIN_DATA="${GBRAIN_HOME:-/data/gbrain}"
export GBRAIN_HOME="$BRAIN_DATA"

# Load OpenClaw env (API keys, etc.) when present.
if [[ -f "$OPENCLAW_HOME/.env" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "$OPENCLAW_HOME/.env"
  set +a
  log "Sourced $OPENCLAW_HOME/.env"
elif [[ -f "/root/.openclaw/.env" ]] && [[ "$OPENCLAW_HOME" != "/root/.openclaw" ]]; then
  set -a
  source "/root/.openclaw/.env"
  set +a
  log "Sourced /root/.openclaw/.env"
fi

# Install pureclaw-gbrain skill into $OPENCLAW_HOME/skills/ (e.g. /root/.openclaw/skills/pureclaw-gbrain).
SKILL_SRC="$INSTALL_DIR/skills/pureclaw-gbrain"
SKILL_DEST="$OPENCLAW_HOME/skills/pureclaw-gbrain"
if [[ -d "$SKILL_SRC" ]]; then
  mkdir -p "$OPENCLAW_HOME/skills"
  rm -rf "$SKILL_DEST"
  cp -a "$SKILL_SRC/." "$SKILL_DEST/"
  log "Installed pureclaw-gbrain skill → $SKILL_DEST"
else
  log "warn: $SKILL_SRC not found; skip skill copy"
fi

if command -v gbrain >/dev/null 2>&1; then
  if gbrain skillpack install pureclaw-gbrain --workspace "$OPENCLAW_WORKSPACE" >/dev/null 2>&1; then
    log "skillpack install pureclaw-gbrain OK (includes skills/conventions shared deps)"
  else
    log "warn: skillpack install skipped or failed — re-run: gbrain skillpack install pureclaw-gbrain --workspace $OPENCLAW_WORKSPACE (needed for conventions + managed AGENTS.md block)"
  fi
fi

log "OpenClaw: home=$OPENCLAW_HOME workspace=$OPENCLAW_WORKSPACE skill=$SKILL_DEST GBRAIN_HOME=$BRAIN_DATA"
