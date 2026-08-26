# Nightly report — passe 17 (revue PR #47)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-ec5b` (PR #47, `e1f1482`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-5c92`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #47 (autorité + recycle inbound + perf CCU, HEAD visuel). Correctifs sûrs, sans merger feel `5c74`/`df65` ni hardening `f8c8`/`9f25`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `bunkersBySlot` : posted DEFENSE O(bunkers) plus O(hash bâtiments) | `GameState.luau`, `ChantierB.luau` | V4 Option B |
| Reinforce terrestre ignore `isBeachhead` (défense en profondeur, BoatFront parque déjà) | `GameState.luau` | V15 |
| `spawnCenter` posé à `addPlayer` ; `stripTerritory` l’efface (plus d’ancre fantôme humaine) | `GameState.luau`, `ChantierB.luau` | V1 partiel |
| `findSpawn` retombe sur `capitalTile` si `spawnCenter` nil | `GameState.luau` | V1 partiel |
| `removePlayer` purge `quickChatSent` / `quickChatLast` (slot recyclé) | `GameState.luau` | — |
| `Diplomacy.step` : expiry non-nombre ne crash plus ; `true` legacy conservé ; corrompu purgé | `Diplomacy.luau` | — |
| `viewFor` masque les demandes périmées ; `setTargetMark` notifie via `areAllied` | `Diplomacy.luau` | — |
| Nuke `kind` hors `NUKE_STATS` → `InvalidSchema` | `IntentValidator.luau` | — |
| Bots previewent `Nukes.samRange(level)` (plus `Config.SAM_RANGE=34`) | `Nukes.luau`, `Bots.luau` | V16 partiel |
| `flushOwnerDelta` recycle `deltaIndices` ; buffer toujours taille exacte `[u32][u8]` | `GameState.luau` | V14 partiel |
| Banc : `error()` si failures (le Luau CLI n’a pas `os.exit`) | `tests/simulate.luau`, `tests/client.luau` | — |

`applyDefenseAura` **écrit encore** le buffer `defense` (mort pour le combat installé). Option A volontairement reportée.

---

## Constatations PR #47 (à ne pas casser)

- **Autorité :** le client n’évalue aucune règle de combat/économie. Ordres = remotes + sequence.
- **Vérité runtime :** `SystemsBootstrap.install()` → `ChantierB.apply(Config)`. Ne pas tuner `Config.luau` seul.
- **Combat vivant :** `ChantierB.stepAttacks`. `GameState.stepAttacks` est un cadavre après install (commenté).
- **BoatFront :** parque tous les `isBeachhead` pendant `launchAttack` ; le skip dans `GameState` est un filet.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `Nukes.samRange` n’introduit pas de cycle (`Bots` requérait déjà `Nukes`).
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passe 16) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances — inchangé. Manquait le quick-chat de slot.

---

## Specs worker (reste)

Ne pas merger feel `5c74`/`df65` ni hardening `f8c8`/`9f25` sur cette branche sans rebase. Porter **une** recette à la fois.

### ISSUE-V1 — Packing spawn 18 factions

**Problème.** `SPAWN_RADIUS=18` + `SPAWN_MIN_PLAYER_DISTANCE=30` : les seeds 7 / 99991 / 1234567 / 424242 placent 11–15 factions sur 18. Les tribus sautent. Passe 17 pose `spawnCenter` (la min-distance **marche** maintenant) mais le disque 21² reste trop large : occupancy ≫ minDist.

**20K CCU.** Un salon Classique sous-peuplé fausse l’éco, les bots et le climax nucléaire.

**Faire.** Recherche spirale / rejet plus souple pour `isTribe` (dist min 20) **ou** `TRIBE_SPAWN_RADIUS` plus petit. Ne pas réduire le disque humain. Ne pas re-poser `spawnCenter` (déjà vivant).

**Contraintes.** Server-only. `addPlayer` rollback si `findSpawn` nil. `stripTerritory` doit continuer d’effacer `spawnCenter`.

**Tester.** `EXTRA_SEEDS` + seed 424242 : `spawned == BOT_COUNT + TRIBE_COUNT`. `./tests/run.sh`.

### ISSUE-V4b — Stopper `applyDefenseAura` (Option A)

**Problème.** `placeBuilding` / `destroyBuilding` DEFENSE écrivent encore le buffer `defense`. Le combat installé lit `bunkersBySlot`. `GameState.tileCost` (mort) est le seul lecteur.

**20K CCU.** Aura = disque `DEFENSE_RADIUS`² écritures par pose/capture/destroy, pile sur un tick de combat.

**Faire.** Recette feel N45 Option A : plus d’appels `applyDefenseAura` après install. Fonction conservée pour `tileCost` hors install. Ne pas toucher `bunkersBySlot`.

**Tester.** Pose/capture/destroy bunker : posted ×5 / speed ×3 inchangés. P0 metrics.

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

### ISSUE-V11b — Smoke / shadows construction

**Problème.** `BuildingModels` : `Smoke` + `PointLight.Shadows` par usine/SAM. Les pulses sont plafonnés (8). La fumée ne l’est pas.

**Faire.** Pas de Smoke/shadows si `UserGameSettings.SavedQualityLevel` bas (pcall, défaut = garder). Pas de logique de jeu côté client.

**Tester.** `tests/client.luau` (ne pas casser le banc). Studio : rush de poses.

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

### ISSUE-V16 — Isolation clic spawn / `samsBySlot`

**Problème.** Feel N55 (disque isolation `claimSpawn`) et N57 (index SAM O(B) au lieu du scan) absents du HEAD visuel. Passe 17 aligne seulement la **preview bot** sur `samRange(level)`. `tryIntercept` et `Buildings.samsOf` scannent encore tout le hash.

**Faire.** Porter **une** recette. N55 : `claimSpawn` refuse un disque trop proche d’une autre capitale. N57 : `samsBySlot` comme `bunkersBySlot` (dirty `placeBuilding` / `destroyBuilding` / `transferBuilding` si SAM). `Buildings.samsOf` lit l’index.

**Tester.** Clic spawn collé à une capitale ennemie. Interception SAM inchangée (chance 1.0, lock exclusif). Bot ne lance plus dans un SAM lvl 1 (portée ~70, pas 34).

### ISSUE-V17 — `MAX_TILES_PER_TICK` double-mort

**Problème.** `ChantierB.apply` pose `MAX_TILES_PER_TICK=56` mais le combat vivant hardcode `guard < 80`. Le débit réel = `attackTilesPerTick * speedFactor`.

**20K CCU.** Un reviewer qui baisse la clé Config croit limiter le tick ; le salon continue à 80 captures.

**Faire.** Lire `Config.MAX_TILES_PER_TICK` (après apply) dans `ChantierB.stepAttacks` **ou** commenter/rename la clé comme morte. Ne pas changer 80 sans banc P0.

**Tester.** P0 `changedTiles` p95. `./tests/run.sh`.

---

## Hors scope volontaire

- Merger feel `5c74` / hardening `f8c8` sur #39/#47.
- Spatial hash warships / `bunkerCells` (hardening N41) — `bunkersBySlot` suffit pour V4 Option B.
- `MODE_KEYS` mort (digits 1–4 = bâtiments). Cosmétique.
- Fallout disque = rayon **inner** seulement (OF outer = spec produit).
- Brancher les clés Config mortes (`ATTACK_SPEND_RATE`, `FRONT_TILES_PER_CONTACT`, `BOAT_LANDING_BONUS`).
- `combatUnlocked` forcé à `true` chaque tick playing (`init.server`) : prep=0, pas un leak client.

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16 + **passe 17** (`spawnCenter` / strip, `Diplomacy.step` corrompu + `true` legacy, nuke kind 99, `bunkersBySlot` posted ×5, quickChat recycle, beachhead non-renforcé, `flushOwnerDelta` format, `Nukes.samRange`).  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
