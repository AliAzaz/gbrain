#!/usr/bin/env bash
# verify-gbrain-openrouter-env.sh — read-only checks for OpenRouter embedding routing.
#
# Run on the pod in the same context where `gbrain embed` failed:
#   GBRAIN_HOME=/data/gbrain ./scripts/verify-gbrain-openrouter-env.sh
#
# Exit 0 when file/env routing points at openrouter:* and OPENROUTER_API_KEY is set.
# Exit 1 with actionable messages otherwise.

set -euo pipefail

failures=0
warn() { echo "WARN: $*" >&2; }
err() { echo "ERROR: $*" >&2; failures=$((failures + 1)); }

echo "=== gbrain OpenRouter env verification ==="

echo ""
echo "--- binary ---"
if ! command -v gbrain >/dev/null 2>&1; then
  warn "gbrain not on PATH (file-plane checks still apply)"
else
  gbrain_path="$(command -v gbrain)"
  echo "gbrain: $gbrain_path"
  if [[ -L "$gbrain_path" ]]; then
    warn "gbrain is a symlink (wrapper may have been clobbered by bun link): $(readlink "$gbrain_path")"
  fi
  head -3 "$gbrain_path" 2>/dev/null | sed 's/^/  /' || true
fi

echo ""
echo "--- env ---"
echo "GBRAIN_HOME=${GBRAIN_HOME:-<unset>}"
echo "GBRAIN_EMBEDDING_MODEL=${GBRAIN_EMBEDDING_MODEL:-<unset>}"
echo "GBRAIN_EMBEDDING_DIMENSIONS=${GBRAIN_EMBEDDING_DIMENSIONS:-<unset>}"
echo "OPENROUTER_API_KEY=${OPENROUTER_API_KEY:+set}"
echo "OPENAI_API_KEY=${OPENAI_API_KEY:+set}"

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  err "OPENROUTER_API_KEY is unset (add to k8s Deployment/Secret — inline kubectl export does not persist)"
fi

config_home="${GBRAIN_HOME:-$HOME}"
config_json="$config_home/.gbrain/config.json"

echo ""
echo "--- file-plane config ($config_json) ---"
if [[ -f "$config_json" ]]; then
  grep -E 'embedding_model|embedding_dimensions|chat_model|expansion_model' "$config_json" || true
  file_embed="$(grep -o '"embedding_model"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_json" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/' || true)"
else
  warn "config.json missing at $config_json"
  file_embed=""
fi

effective_embed="${GBRAIN_EMBEDDING_MODEL:-$file_embed}"
if [[ -z "$effective_embed" ]]; then
  err "No embedding_model in env or config.json — gateway will default to openai:text-embedding-3-large"
elif [[ "$effective_embed" != openrouter:* ]]; then
  err "embedding route is '$effective_embed' (expected openrouter:...)"
else
  echo "OK: effective embedding route is $effective_embed"
fi

if command -v gbrain >/dev/null 2>&1; then
  echo ""
  echo "--- gbrain config show (file/env plane) ---"
  gbrain config show 2>/dev/null | grep -E 'embedding_model|embedding_dimensions' || warn "gbrain config show failed or no embedding fields"

  echo ""
  echo "--- DB config get (informational; NOT used by embed) ---"
  db_embed="$(gbrain config get embedding_model 2>/dev/null || true)"
  if [[ -n "$db_embed" && "$db_embed" != "$effective_embed" ]]; then
    warn "DB embedding_model=$db_embed differs from effective $effective_embed — gbrain config set does not drive embed"
  elif [[ -n "$db_embed" ]]; then
    echo "DB embedding_model=$db_embed"
  fi

  echo ""
  echo "--- providers list (first 25 lines) ---"
  gbrain providers list 2>/dev/null | head -25 || warn "gbrain providers list failed"
fi

echo ""
if [[ $failures -gt 0 ]]; then
  echo "FAILED: $failures check(s). Fix:"
  echo "  1. Add deploy/k8s-gbrain-env.example.yaml env block to your Deployment"
  echo "  2. Re-run scripts/bootstrap/configure-gbrain.sh (or bootstrap-gbrain.sh) OR edit $config_json with openrouter routing"
  echo "  3. source /etc/profile.d/gbrain.sh before gbrain embed"
  exit 1
fi

echo "All checks passed."
exit 0
