#!/usr/bin/env node
/*
 * Assemble les modules partages et serveur en un seul fichier Luau executable
 * par le CLI `luau`, pour pouvoir faire tourner la simulation hors de Studio.
 *
 * Les appels require(...) de Roblox designent des Instances, pas des chemins de
 * fichiers. On les reecrit donc en __require("NomDuModule") : le dernier
 * identifiant de l'expression suffit a identifier le module de facon unique,
 * que la forme soit require(ReplicatedStorage.Shared.Config),
 * require(script.Parent.GameState) ou require(Shared:WaitForChild("Config")).
 */

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");

// Deux bancs d'essai : le serveur (simulation) et le client (interface).
// Ils n'ont ni les memes modules ni les memes bouchons.
const TARGET = process.argv[2] === "client" ? "client" : "server";

const MODULE_DIRS =
  TARGET === "client"
    ? ["ReplicatedStorage/Shared", "StarterPlayerScripts/Client"]
    : ["ReplicatedStorage/Shared", "ServerScriptService/Server"];

// Modules exclus : ils dependent d'API que le banc d'essai ne simule pas et ne
// participent pas a la logique testee.
const EXCLUDE = new Set(["Persistence", "init.server", "init.client"]);

function rewriteRequires(source) {
  return source.replace(/require\(([^()]*(?:\([^()]*\))?[^()]*)\)/g, (match, inner) => {
    const tokens = inner.match(/[A-Za-z_][A-Za-z0-9_]*/g);
    if (!tokens || tokens.length === 0) return match;
    const name = tokens[tokens.length - 1];
    return `__require("${name}")`;
  });
}

function prepareModule(source) {
  return (
    rewriteRequires(source)
      // `export type` n'est licite qu'au niveau module ; une fois le code
      // enferme dans une fonction, il faut retirer le mot-cle.
      .replace(/^\s*export\s+type\s/gm, "type ")
      // La table `math` est en lecture seule dans Luau : le bruit de Roblox est
      // remplace par l'implementation de reference des bouchons.
      .replace(/\bmath\.noise\(/g, "__noise(")
  );
}

const parts = [];

parts.push(
  fs.readFileSync(path.join(ROOT, TARGET === "client" ? "tests/guistubs.luau" : "tests/stubs.luau"), "utf8")
);

parts.push(`
local __modules = {}
local __cache = {}

function __require(name)
	local cached = __cache[name]
	if cached ~= nil then
		return cached
	end
	local factory = __modules[name]
	if not factory then
		error("module introuvable dans le bundle : " .. tostring(name), 2)
	end
	local result = factory()
	__cache[name] = result
	return result
end
`);

let count = 0;
for (const dir of MODULE_DIRS) {
  const full = path.join(ROOT, dir);
  for (const file of fs.readdirSync(full).sort()) {
    if (!file.endsWith(".luau")) continue;
    const name = file.replace(/\.luau$/, "");
    if (EXCLUDE.has(name)) continue;

    const source = fs.readFileSync(path.join(full, file), "utf8");
    parts.push(`__modules["${name}"] = function()\n${prepareModule(source)}\nend\n`);
    count += 1;
  }
}

const driver = fs.readFileSync(
  path.join(ROOT, TARGET === "client" ? "tests/client.luau" : "tests/simulate.luau"),
  "utf8"
);
parts.push(driver);

const outPath = path.join(ROOT, `tests/.bundle-${TARGET}.luau`);
fs.writeFileSync(outPath, parts.join("\n"));

console.error(`bundle ${TARGET} : ${count} modules -> ${path.relative(ROOT, outPath)}`);
