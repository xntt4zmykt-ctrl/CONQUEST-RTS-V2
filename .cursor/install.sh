#!/usr/bin/env bash
#
# Installation de l'environnement de developpement Cloud Agent pour CONQUEST RTS.
#
# Le projet est un jeu Roblox. Hors de Studio, deux outils suffisent a tout le
# flux de developpement headless :
#   - rojo  : assemble l'arborescence en un fichier place (.rbxl) -> `rojo build`
#   - luau  : execute les bancs d'essai serveur et client -> `./tests/run.sh`
#             (l'assemblage des bundles utilise `node`, deja present dans l'image)
#
# rojo est epingle par aftman.toml ; on installe donc d'abord aftman (le
# gestionnaire d'outils Roblox) puis on le laisse resoudre la version exacte.
#
# Le script est idempotent : il peut tourner sur une image vierge comme sur un
# snapshot ou tout est deja present, sans jamais echouer ni dupliquer d'etat.
set -euo pipefail

# Versions epinglees pour une installation reproductible.
AFTMAN_VERSION="0.3.0"
LUAU_VERSION="0.735"
BIN_DIR="/usr/local/bin"

# aftman.toml est a la racine du depot : on s'y place quel que soit le cwd.
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

missing() { ! command -v "$1" >/dev/null 2>&1; }

# --- aftman (gestionnaire d'outils Roblox) --------------------------------
if missing aftman; then
	echo "[install] telechargement d'aftman ${AFTMAN_VERSION}"
	curl -fsSL -o "$TMP/aftman.zip" \
		"https://github.com/LPGhatguy/aftman/releases/download/v${AFTMAN_VERSION}/aftman-${AFTMAN_VERSION}-linux-x86_64.zip"
	unzip -oq "$TMP/aftman.zip" -d "$TMP/aftman"
	sudo install -m 0755 "$TMP/aftman/aftman" "$BIN_DIR/aftman"
fi

# --- luau (execution des bancs d'essai hors Studio) -----------------------
if missing luau; then
	echo "[install] telechargement de luau ${LUAU_VERSION}"
	curl -fsSL -o "$TMP/luau.zip" \
		"https://github.com/luau-lang/luau/releases/download/${LUAU_VERSION}/luau-ubuntu.zip"
	unzip -oq "$TMP/luau.zip" -d "$TMP/luau"
	sudo install -m 0755 "$TMP/luau/luau" "$BIN_DIR/luau"
fi

# --- rojo (epingle par aftman.toml) ---------------------------------------
# `aftman install` installe rojo dans ~/.aftman/bin, chemin qui n'est pas
# forcement sur le PATH des shells de l'agent ; on l'expose donc via un lien
# dans un repertoire systeme deja sur le PATH.
echo "[install] resolution des outils epingles (aftman.toml)"
aftman install --no-trust-check
if [ -x "$HOME/.aftman/bin/rojo" ]; then
	sudo ln -sf "$HOME/.aftman/bin/rojo" "$BIN_DIR/rojo"
fi

# --- verification ---------------------------------------------------------
echo "[install] outils disponibles :"
printf '  aftman : %s\n' "$(aftman --version)"
printf '  rojo   : %s\n' "$(rojo --version)"
printf '  luau   : %s\n' "luau ${LUAU_VERSION}"
printf '  node   : %s\n' "$(node --version)"
echo "[install] termine"
