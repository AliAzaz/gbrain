#!/usr/bin/env bash
#
# bootstrap-gbrain.sh — install and configure gbrain in a k8s pod (full bootstrap).
#
# Runs install-gbrain.sh then configure-gbrain.sh. For split k8s phases, call
# those scripts directly:
#   scripts/bootstrap/install-gbrain.sh    — once per image or initContainer
#   scripts/bootstrap/configure-gbrain.sh — every pod start (needs Secret)
#
# OpenClaw: when OPENCLAW_HOME or ~/.openclaw exists, configure-gbrain.sh also
# runs scripts/bootstrap/configure-openclaw.sh (skill install + env).
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
#   GBRAIN_HOME          — brain data directory (default: /data/gbrain; OpenClaw may use ~/.openclaw/data/gbrain)
#   GBRAIN_BRAIN_REPO    — git URL of YOUR markdown brain content; cloned to $GBRAIN_HOME/brain
#   GBRAIN_BRAIN_BRANCH  — branch of the brain content repo (default: master)
#   GBRAIN_NO_TEMPLATE   — set to "1" to skip MECE template when no GBRAIN_BRAIN_REPO
#   GBRAIN_AUTHOR_NAME / GBRAIN_AUTHOR_EMAIL — git author for scaffolded template
#   GBRAIN_EMBEDDING_MODEL / GBRAIN_EMBEDDING_DIMENSIONS / GBRAIN_CHAT_MODEL / GBRAIN_EXPANSION_MODEL
#   OPENCLAW_HOME / OPENCLAW_WORKSPACE — OpenClaw paths for skill + env hook
#
# Exit codes: same as install (2) + configure (3, 4)

set -euo pipefail

_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BOOTSTRAP="$_ROOT/scripts/bootstrap"

# OpenClaw deployments often set these before calling bootstrap.
if [[ -d "${OPENCLAW_HOME:-$HOME/.openclaw}" ]] && [[ -z "${GBRAIN_HOME:-}" ]]; then
  export GBRAIN_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}/data/gbrain"
fi

bash "$_BOOTSTRAP/install-gbrain.sh"
bash "$_BOOTSTRAP/configure-gbrain.sh"
