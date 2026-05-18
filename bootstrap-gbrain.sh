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

set -euo pipefail

_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_BOOTSTRAP="$_ROOT/scripts/bootstrap"

bash "$_BOOTSTRAP/install-gbrain.sh"
bash "$_BOOTSTRAP/configure-gbrain.sh"
