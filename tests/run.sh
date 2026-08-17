#!/usr/bin/env bash
# Fait tourner la simulation serveur hors de Studio et verifie les invariants.
#
# Prerequis : node (assemblage du bundle) et luau (execution).
#   brew install luau
# Pas de `set -e` : on veut executer les deux bancs meme si le premier echoue,
# et rapporter les deux resultats.
set -uo pipefail

cd "$(dirname "$0")/.."

# Banc serveur : simulation et invariants.
node tests/bundle.js server
luau tests/.bundle-server.luau
server_status=$?

echo

# Banc client : construction et execution de toute l'interface.
node tests/bundle.js client
luau tests/.bundle-client.luau
client_status=$?

exit $(( server_status | client_status ))
