# Nightly report — passe 18 (revue PR #50)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-5c92` (PR #50, `4ff5fbf`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-121e`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #50 (bunkersBySlot, recycle slot, autorité — HEAD visuel). Correctifs sûrs, sans merger feel `e735`/`5c74` ni hardening `e91b`/`f8c8`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| Plus d’écritures `applyDefenseAura` à la pose/capture/destroy | `GameState.luau` | V4b Option A |
| Capture bunker : `bunkersBySlot` suit le camp (index helper partagé) | `GameState.luau` | V4 suite |
| Debit vivant nommé `ChantierB.CAPTURE_GUARD = 80` ; `MAX_TILES_PER_TICK` documenté mort | `ChantierB.luau`, `Config.luau`, `TickMetrics.luau` | V17 |
| `samsBySlot` : pose / capture / destroy / `removePlayer` | `GameState.luau` | V16 N57 |
| `Buildings.samsOf` lit l’index | `Buildings.luau` | V16 N57 |
| `tryIntercept` itère `samsBySlot` (O(SAM), plus O(hash)) | `Nukes.luau` | V16 N57 |
| Smoke / `PointLight.Shadows` absents si qualité < 4 ; pcall défaut = garder | `BuildingModels.luau` | V11b |

La fonction `applyDefenseAura` est **conservée** pour `tileCost` hors install. Le combat vivant ne la lit pas.

---

## Constatations PR #50 (à ne pas casser)

- **Autorité :** le client n’évalue aucune règle de combat/économie. Ordres = remotes + sequence.
- **Vérité runtime :** `SystemsBootstrap.install()` → `ChantierB.apply(Config)`. Ne pas tuner `Config.luau` seul.
- **Combat vivant :** `ChantierB.stepAttacks`. Guard = `ChantierB.CAPTURE_GUARD` (80), **pas** `Config.MAX_TILES_PER_TICK` (56 après apply, 400 brut).
- **Posted DEFENSE :** `bunkersBySlot` + `attackLogic`. Buffer `defense` mort pour le combat installé.
- **Posted SAM :** `samsBySlot` + `tryIntercept` / `samsOf`. Preview bot = `Nukes.samRange(level)`.
- **BoatFront :** parque tous les `isBeachhead` pendant `launchAttack` ; le skip dans `GameState` est un filet.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `samsBySlot` n’ajoute aucun require.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–17) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.

---

## Specs worker (reste)

Ne pas merger feel `e735`/`5c74` ni hardening `e91b`/`f8c8` sur cette branche sans rebase. Porter **une** recette à la fois.

### ISSUE-V1 — Packing spawn 18 factions

**Problème.** `SPAWN_RADIUS=18` + `SPAWN_MIN_PLAYER_DISTANCE=30` : les seeds 7 / 99991 / 1234567 / 424242 placent 11–15 factions sur 18. Les tribus sautent. `spawnCenter` est vivant (passe 17) mais le disque 21² reste trop large : occupancy ≫ minDist.

**20K CCU.** Un salon Classique sous-peuplé fausse l’éco, les bots et le climax nucléaire.

**Faire.** Recherche spirale / rejet plus souple pour `isTribe` (dist min 20) **ou** `TRIBE_SPAWN_RADIUS` plus petit. Ne pas réduire le disque humain. Ne pas re-poser `spawnCenter`.

**Contraintes.** Server-only. `addPlayer` rollback si `findSpawn` nil. `stripTerritory` doit continuer d’effacer `spawnCenter`.

**Tester.** `EXTRA_SEEDS` + seed 424242 : `spawned == BOT_COUNT + TRIBE_COUNT`. `./tests/run.sh`.

### ISSUE-V7 — `findSpawn` / `claimSpawn` anti-splash

**Problème.** Spawn ignore cratère ogive / fallout chaud. Un humain peut (re)naître dans le splash.

**Faire.** Recette feel N50/N52 : `isSpawnSafe` partagé `findSpawn` + `claimSpawn` (C1+C2). Contrat B missiles inbound **inchangé**.

**Tester.** MIRV existant + capitale sous fallout → refus / autre tuile.

### ISSUE-V9b — Persistence debounce 30 s

**Problème.** `record()` appelle encore `UpdateAsync` tout de suite (une écriture / humain). Le double-write `release`/`BindToClose` est corrigé ; la tempête de fin de match (8 writes synchrones) reste.

**20K CCU.** N salons × 8 humains × `endMatch` = burst DataStore.

**Faire.** `record()` marque dirty **sans** `save`. Flush 30 s + `endMatch` + `release` + `BindToClose`. Une écriture / userId / match.

**Contraintes.** Ne pas perdre l’XP d’un éliminé si le salon crash avant flush : flush immédiat sur `settledHumans` **ou** accepter ≤1 write / éliminé. Hors bundle (`Persistence`).

**Tester.** Studio : 8 humains `endMatch` = ≤8 writes, disconnect après `record` = 0 write supplémentaire.

### ISSUE-V13 — Rot doomsday O(carte)

**Problème.** `ChantierB.stepDoomsday` parcourt `TILE_COUNT` par joueur marqué pour arracher `quota` tuiles.

**20K CCU.** 10 Hz × 40 960 lectures buffer quand le cadran tourne = pic en fin de partie.

**Faire.** Liste incrémentale des tuiles par slot (même structure que `border`) **ou** reservoir sampling sur un index compact. Ne pas changer la formule `Doomsday.rotQuota`.

**Tester.** Cadran existant + 1 humain sous quota. Invariants `tiles` vs buffer.

### ISSUE-V14b — En-tête de compteur pour `flushOwnerDelta`

**Problème.** Passe 17 recycle `deltaIndices` mais `buffer.create(count * 5)` reste obligatoire : un tampon trop grand serait lu comme des tuiles fantômes (slot 0).

**20K CCU.** 10 Hz playing × alloc buffer = pression GC sur 8 clients.

**Faire.** Préfixer le payload `[u32 count][u32 index][u8 slot]…` **ou** RemoteEvent séparé pour la longueur. Adapter le client (`WorldRenderer` / init.client). Growth-only ensuite.

**Contraintes.** Changer client **et** serveur dans le même commit. Ne pas casser `RequestSnapshot` (carte entière, autre remote).

**Tester.** Match 6000 ticks, P0 metrics. Client 34/34.

### ISSUE-V16b — Isolation clic spawn

**Problème.** Feel N55 (disque isolation `claimSpawn`) absent du HEAD visuel. Passe 18 porte N57 (`samsBySlot`). Un clic collé à une capitale ennemie reste accepté.

**Faire.** Recette feel N55 uniquement : `isSpawnIsolated` (carré `SPAWN_RADIUS+3`) partagé `findSpawn` / `claimSpawn`. Ne pas re-toucher `samsBySlot`.

**Tester.** Clic spawn collé à une capitale ennemie → refus / autre tuile. `./tests/run.sh`.

### ISSUE-V18 — `Nukes.launch` scan silos O(hash)

**Problème.** `Nukes.launch` parcourt tout `state.buildings` pour trouver le silo prêt le plus proche. `tryIntercept` ne le fait plus (passe 18) ; le lancement si.

**20K CCU.** Un tir = scan hash global, pile sur un tick de combat / SAM.

**Faire.** Recette feel N60 `silosBySlot` : dirty `placeBuilding` / `destroyBuilding` / `transferBuilding` / `removePlayer` si SILO (même helper `setSlotIndex` que DEFENSE/SAM). `Nukes.launch` itère `silosBySlot[slot]`. Ne pas geler `SILO_COOLDOWN` (toujours armé dans `launch`).

**Tester.** Pose / capture / destroy SILO indexé. Lancement choisit le plus proche prêt. `./tests/run.sh`.

### ISSUE-V19 — `stepCooldowns` O(hash) 10 Hz

**Problème.** `Buildings.stepCooldowns` décrémente **tous** les bâtiments chaque tick. Seuls SAM et silos portent un cooldown vivant.

**20K CCU.** 10 Hz × N bâtiments, dont villes/usines à cooldown 0.

**Faire.** Recette hardening N43 : `coolingBuildings` + `armCooldown` SAM **et** silos (SAM-only gèlerait `SILO_COOLDOWN`). `Nukes.launch` / `tryIntercept` doivent appeler `armCooldown`.

**Tester.** SAM intercept → cooldown 90. Silo launch → `SILO_COOLDOWN`. Ville/usine jamais dans l’index. P0 metrics.

### ISSUE-V20 — `Trade.step` flatten FACTORY 10 Hz

**Problème.** Chaque tick, `Trade.step` alloue une liste, scannne le hash, **trie** les usines (déterminisme RNG). Feel a `factoriesBySlot` (N61) ; le sort 10 Hz reste (N66).

**20K CCU.** Alloc + sort sur le hot path économique.

**Faire.** Porter **une** recette. N61 : `factoriesBySlot` + iteration déterministe (tri des clés de l’index, pas un flatten hash). N66 : buffer recyclé, tri seulement si dirty. Vague ≠ 45 ticks (c’est le maritime).

**Tester.** Or colis inchangé. Deux seeds identiques → mêmes livraisons. `./tests/run.sh`.

### ISSUE-V21 — `spawnTradeShips` O(ports²)

**Problème.** Vague maritime (`TRADE_SHIP_INTERVAL=45`) flatten tous les PORT du hash puis paires. Hardening N40 a `portsByTile` + early-out cap + buffers recyclés. Visual ne l’a pas.

**20K CCU.** Moins chaud que 10 Hz, mais pic + alloc sur 24 convois max.

**Faire.** Recette hardening N40 (déjà portée feel N63) : `portsByTile` incrémental PORT only, early-out `MAX_TRADE_SHIPS` **et** `<2` avant flatten, `portsBuf`/`candidateBuf`. Distinct de `_carriersDirty` (NAVAL_BASE).

**Tester.** Cap 24 respecté. `<2` ports = pas de scan. P0 metrics. `./tests/run.sh`.

---

## Hors scope volontaire

- Merger feel `e735` / hardening `e91b` sur #39/#50.
- Spatial hash warships / `bunkerCells` (hardening N41) — `bunkersBySlot` suffit.
- `buildingsBySlot` générique (feel N62/N64) — V18 silos d’abord, une kind à la fois.
- `MODE_KEYS` mort (digits 1–4 = bâtiments). Cosmétique.
- Fallout disque = rayon **inner** seulement (OF outer = spec produit).
- Brancher les clés Config mortes (`ATTACK_SPEND_RATE`, `FRONT_TILES_PER_CONTACT`, `BOAT_LANDING_BONUS`).
- `combatUnlocked` forcé à `true` chaque tick playing (`init.server`) : prep=0, pas un leak client.
- `syncCarriers` spawn NAVAL_BASE encore O(B) quand dirty (feel N65) — dirty déjà vivant, scan rare.

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–17 + **passe 18** (`CAPTURE_GUARD=80` ≠ `MAX_TILES_PER_TICK`, aura buffer=0, capture bunker index, `samsBySlot` pose/intercept/capture/recycle/destroy).  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
