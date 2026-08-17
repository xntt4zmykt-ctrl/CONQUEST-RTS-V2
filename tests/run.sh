#!/usr/bin/env bash
# Fait tourner la simulation serveur hors de Studio et verifie les invariants.
#
# Prerequis : node (assemblage du bundle) et luau (execution).
#   brew install luau
set -euo pipefail

cd "$(dirname "$0")/.."

node tests/bundle.js
exec luau tests/.bundle.luau
