#!/usr/bin/env bash
# patch-gbrain-openrouter-config.sh — fix OpenRouter routing on an existing pod
# without a full bootstrap re-run.
#
# Usage (on the pod):
#   export OPENROUTER_API_KEY=sk-or-...
#   export GBRAIN_HOME=/data/gbrain   # or your brain data path
#   ./scripts/patch-gbrain-openrouter-config.sh
#   ./scripts/patch-gbrain-openrouter-config.sh --embed-all
#
# Writes $GBRAIN_HOME/.gbrain/config.json (file-plane) then optionally re-embeds.

set -euo pipefail

EMBED_MODE="stale"
if [[ "${1:-}" == "--embed-all" ]]; then
  EMBED_MODE="all"
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--embed-all]" >&2
  exit 1
fi

BRAIN_DATA="${GBRAIN_HOME:-/data/gbrain}"
GBRAIN_EMBEDDING_MODEL="${GBRAIN_EMBEDDING_MODEL:-openrouter:openai/text-embedding-3-large}"
GBRAIN_EMBEDDING_DIMENSIONS="${GBRAIN_EMBEDDING_DIMENSIONS:-1536}"
GBRAIN_CHAT_MODEL="${GBRAIN_CHAT_MODEL:-openrouter:anthropic/claude-sonnet-4.5}"
GBRAIN_EXPANSION_MODEL="${GBRAIN_EXPANSION_MODEL:-openrouter:openai/gpt-4o-mini}"

export GBRAIN_HOME="$BRAIN_DATA"
export GBRAIN_EMBEDDING_MODEL GBRAIN_EMBEDDING_DIMENSIONS GBRAIN_CHAT_MODEL GBRAIN_EXPANSION_MODEL

config_path="$BRAIN_DATA/.gbrain/config.json"
db_path="$BRAIN_DATA/.gbrain/brain.pglite"
mkdir -p "$(dirname "$config_path")"

CONFIG_PATH="$config_path" DB_PATH="$db_path" \
EMBED_MODEL="$GBRAIN_EMBEDDING_MODEL" EMBED_DIMS="$GBRAIN_EMBEDDING_DIMENSIONS" \
CHAT_MODEL="$GBRAIN_CHAT_MODEL" EXPANSION_MODEL="$GBRAIN_EXPANSION_MODEL" \
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
'

echo "Patched $config_path:"
grep -E 'embedding_model|embedding_dimensions' "$config_path" || true

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$_SCRIPT_DIR/verify-gbrain-openrouter-env.sh" ]]; then
  "$_SCRIPT_DIR/verify-gbrain-openrouter-env.sh"
fi

if ! command -v gbrain >/dev/null 2>&1; then
  echo "gbrain not on PATH; config patched. Re-run embed after fixing PATH."
  exit 0
fi

if [[ "$EMBED_MODE" == "all" ]]; then
  echo "Running: gbrain embed --all"
  gbrain embed --all
else
  echo "Running: gbrain embed --stale"
  gbrain embed --stale
fi
