# Nightly report — passe 16 (revue PR #44)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-420a` (PR #44, `7d98ea9`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-ec5b`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**.

Revue de PR #44 (autorité + recycle inbound sur le HEAD visuel). Correctifs sûrs portés ici, sans merger feel `df65` ni hardening `9f25`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `justClaimed` ne avale plus le premier Attack réel | `SystemsBootstrap.luau`, `IntentValidator.luau` | V12 |
| `areAllied` : expiry non-nombre → `false` (`true` legacy vivant) | `GameState.luau` | — |
| `viewFor` s’aligne sur `areAllied` (plus d’allié fantôme unilatéral) | `Diplomacy.luau` | — |
| Missiles **outbound** purgés dans `removePlayer` | `GameState.luau` | — |
| `stripTerritory` : `tiles = 0` + skip élimination / éco si `awaitingSpawn` | `ChantierB.luau`, `GameState.luau` | — |
| `setOwner` refuse un slot sans `players[slot]` | `GameState.luau` | — |
| `±inf` refusé (sequence, ratio, cibles entières) | `IntentValidator.luau`, `init.server.luau` | — |
| JoinRequest `ended` : notify client | `init.server.luau` | — |
| Lobby / ended : replication **1 Hz** (playing 10 Hz inchangé) | `init.server.luau` | V9 |
| Persistence : `release` / `BindToClose` n’écrivent plus si déjà flush | `Persistence.luau` | V9 partiel |
| `findSeaPath` poolé (`visitBuf` / `parent` / `queue`) | `Navy.luau` | V2 |
| `tryAnnex` poolé (`visited` / `queue` / `pocket`) | `ChantierB.luau` | V5 |
| `syncCarriers` dirty NAVAL_BASE + `carrierSeen` recyclé | `Navy.luau`, `GameState.luau` | V3 |
| Own-tile / allié : restitution **100 %** (plus de malus 25 % via `beginRetreat`) | `Navy.luau` | — |
| `targetOwner` au launch + `retreatBoats` par intention + auto-retraite si flip | `Navy.luau` | V6 / N49+N53 |
| `spawnTradeShips` : `math.clamp` crashait si `< 4` ports étrangers | `Navy.luau` | bug net (crash tick) |
| Embargo terrestre = maritime only (doc) | `Trade.luau` | V10 |
| Clés Config mortes commentées | `Config.luau`, `ChantierB.luau` | V12 |
| Cap 8 pulses de conquête live | `Effects.luau` | V11 partiel |
| Factory : `tradeDeliveries` / `tradeCooldowns` au destroy | `GameState.luau` | — |

V8 (convoi vs PORT détruit) était **déjà** correct : `resolveTrade` no-op, le bateau est retiré, pas d’or. Capture de PORT = continue.

---

## Constatations PR #44 (à ne pas casser)

- **Autorité :** le client n’évalue aucune règle de combat/économie. Ordres = remotes + sequence.
- **Vérité runtime :** `SystemsBootstrap.install()` → `ChantierB.apply(Config)`. Ne pas tuner `Config.luau` seul.
- **Combat vivant :** `ChantierB.stepAttacks`. `GameState.stepAttacks` est mort après install.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique).
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Crash évité :** `math.clamp(floor(n/3), 4, n)` avec `n < 4` plantait `Navy.step` dès 2 ports. Un salon alpha à 2 humains + peu de ports = serveur down.

---

## Specs worker (reste)

Ne pas merger feel `df65` ni hardening `9f25` sur cette branche sans rebase. Porter **une** recette à la fois.

### ISSUE-V1 — Packing spawn 18 factions

**Problème.** `SPAWN_RADIUS=18` + `SPAWN_MIN_PLAYER_DISTANCE=30` : les seeds 7 / 99991 / 1234567 / 424242 placent 11–15 factions sur 18. Les tribus sautent.

**20K CCU.** Un salon Classique sous-peuplé fausse l’éco, les bots et le climax nucléaire (0 frappe en 10 min sur le run principal).

**Faire.** `GameState.findSpawn` : recherche spirale / rejet plus souple pour `isTribe` (dist min 20) **ou** disque tribu plus petit (`TRIBE_SPAWN_RADIUS`). Ne pas réduire le disque humain.

**Contraintes.** Server-only. Ne pas toucher `claimSpawn` visuel. `addPlayer` déjà rollback si `findSpawn` nil.

**Tester.** `EXTRA_SEEDS` + seed 424242 : `spawned == BOT_COUNT + TRIBE_COUNT`. `./tests/run.sh`.

### ISSUE-V4 — `bunkersBySlot` (scan restant)

**Problème.** `attackLogic` short-circuit si 0 bunker, sinon O(bâtiments) **par tuile conquise**. `applyDefenseAura` écrit encore un buffer ignoré par le combat installé.

**20K CCU.** Front large × 10 Hz × scan hash bâtiments = pics CPU combat.

**Faire.** Recette feel N42 Option B : `bunkersBySlot[slot][tile]`. Posted = O(bunkers du défenseur). Puis Option A feel N45 : plus d’appels `applyDefenseAura` (fonction conservée pour `tileCost` hors install). Dirty sur `placeBuilding` / `destroyBuilding` / `transferBuilding` si `DEFENSE`.

**Tester.** Bunker pose/capture/destroy ; posted bonus ×5 / speed ×3 uniquement si défenseur a un bunker in-range. P0 metrics inchangés.

### ISSUE-V7 — `findSpawn` / `claimSpawn` anti-splash

**Problème.** Spawn ignore cratère ogive / fallout chaud. Un humain peut (re)naître dans le splash.

**Faire.** Recette feel N50/N52 : `isSpawnSafe` partagé `findSpawn` + `claimSpawn` (C1+C2). Contrat B missiles inbound **inchangé**.

**Tester.** MIRV existant + capitale sous fallout → refus / autre tuile.

### ISSUE-V9b — Persistence debounce 30 s

**Problème.** `record()` appelle encore `UpdateAsync` tout de suite (une écriture / humain). Le double-write `release`/`BindToClose` est corrigé ; la tempête de fin de match (8 writes synchrones) reste.

**20K CCU.** N salons × 8 humains × `endMatch` = burst DataStore.

**Faire.** `record()` marque dirty **sans** `save`. Flush 30 s + `endMatch` + `release` + `BindToClose`. Une écriture / userId / match.

**Contraintes.** Ne pas perdre l’XP d’un éliminé si le salon crash avant flush : flush immédiat sur `settledHumans` **ou** accepter ≤1 write / éliminé.

**Tester.** Hors bundle (`Persistence`). Studio : 8 humains `endMatch` = ≤8 writes, disconnect après `record` = 0 write supplémentaire.

### ISSUE-V11b — Smoke / shadows construction

**Problème.** `BuildingModels` : `Smoke` + `PointLight.Shadows` par usine/SAM. Les pulses sont plafonnés (8). La fumée ne l’est pas.

**Faire.** Pas de Smoke/shadows si `UserGameSettings.SavedQualityLevel` bas (pcall, défaut = garder). Pas de logique de jeu côté client.

**Tester.** `tests/client.luau` (ne pas casser le banc). Studio : rush de poses.

### ISSUE-V13 — Rot doomsday O(carte)

**Problème.** `ChantierB.stepDoomsday` parcourt `TILE_COUNT` par joueur marqué pour arracher `quota` tuiles.

**20K CCU.** 10 Hz × 40 960 lectures buffer quand le cadran tourne = pic en fin de partie, pile quand le HUD explose déjà.

**Faire.** Liste incrémentale des tuiles par slot (même structure que `border`) **ou** reservoir sampling sur un index compact. Ne pas changer la formule `Doomsday.rotQuota`.

**Tester.** Cadran existant + 1 humain sous quota. Invariants `tiles` vs buffer.

### ISSUE-V14 — `flushOwnerDelta` alloue chaque tick

**Problème.** Table `indices` + `buffer.create` à chaque `replicate()` playing 10 Hz.

**Faire.** Scratch module `deltaScratch` pré-dimensionné, growth only. Nil si `dirty` vide (déjà le cas).

**Tester.** Match 6000 ticks, P0 metrics. Pas de changement de format `[u32][u8]`.

### ISSUE-V15 — Reinforce mid-combat

**Problème.** `GameState` (et le combat installé) peut ajouter des troupes à un front existant sans re-checker `combatUnlocked` / `areAllied` si l’état a changé entre deux ticks.

**Faire.** Au reinforce : si `areAllied` ou pas `combatUnlocked`, skip (le front existant continue, pas de nouveau commit). Documenter le contrat.

**Tester.** Alliance signée pendant un front : plus de troupes ne partent pas ; le front n’est pas annulé (c’est `Diplomacy.accept` qui casse les fronts).

### ISSUE-V16 — Isolation clic spawn / SAM index

**Problème.** Feel N55 (disque isolation `claimSpawn`) et N57 (index SAM O(B) au lieu du scan) absents du HEAD visuel.

**Faire.** Porter **une** recette. N55 : `claimSpawn` refuse un disque trop proche d’une autre capitale. N57 : `samsBySlot` comme `bunkersBySlot`.

**Tester.** Clic spawn collé à une capitale ennemie. Interception SAM inchangée (chance 1.0, lock exclusif).

---

## Hors scope volontaire

- Merger feel `df65` / hardening `9f25` sur #39/#44.
- Spatial hash warships (buffers recyclés côté hardening — porter plus tard).
- `MODE_KEYS` mort (digits 1–4 = bâtiments). Cosmétique.
- Fallout disque = rayon **inner** seulement (OF outer = spec produit).
- Brancher les clés Config mortes (commentées seulement).

---

## Tests

```
./tests/run.sh
```

Client : 34 checks.  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + **passe 16** (`areAllied` corrompu, `±inf` ratio, missiles outbound, spawn wait tiles=0, premier Attack après claim, own-tile 100 %, `targetSlot` après flip, pool `findSeaPath`, carriers dirty).  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
