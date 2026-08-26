# Nightly report — passe 29 (revue PR #81)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-d685` (PR #81, `109ff75`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-107e`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #81 (`gatherSites` siteBuf / `stepElimination` elimBuf — HEAD visuel). Correctifs sûrs, sans merger feel `69f4`/`b62d` ni hardening `bef6`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `Navy.findSeaPath` walk scratch `pathWalkBuf` | `Navy.luau` | V38 N83 |
| `GameState.refreshRailNetwork` pool `stationBuf` | `GameState.luau` | V39 N84 |

`visitBuf` / `parentPool` / `queuePool` **conservés**. Retour **unique** (`boat.path` ne reçoit jamais `pathWalkBuf`). `buildingsBySlot[slot]` + skip `IS_STATION` **conservés**. Inners `neighborsOf` **alloués** (deviennent `building.links`). Formule HUD `railIncome` **visuelle** (pas de `TRAIN_STOP_BONUS` — il vit dans `Trade`). Skip `awaitingSpawn` et `settledHumans` **conservés**. `siteBuf` / `elimBuf` **non retouchés**. Schéma filaire client **inchangé**. GameState ne require toujours pas Buildings / Research.

---

## Constatations PR #81 (à ne pas casser)

- **Autorité :** le client n’évalue aucune règle de combat/économie. Ordres = remotes + sequence.
- **Vérité runtime :** `SystemsBootstrap.install()` → `ChantierB.apply(Config)`. Ne pas tuner `Config.luau` seul.
- **Combat vivant :** `ChantierB.stepAttacks`. Guard = `ChantierB.CAPTURE_GUARD` (80), **pas** `Config.MAX_TILES_PER_TICK` (56 après apply, 400 brut).
- **Posted DEFENSE :** `bunkersBySlot` + `attackLogic`. Buffer `defense` mort. Plus d’écritures `applyDefenseAura`.
- **Posted SAM :** `samsBySlot` + `tryIntercept` / `samsOf`. Slot sans SAM ne rescane plus le hash. `samsOf` recycle un buffer — **pas réentrant**.
- **Posted SILO :** `silosBySlot` + `Nukes.launch`. Fantôme hors index ignoré.
- **Cooldown 10 Hz :** `coolingBuildings` + `armCooldown` (SAM **et** silos). SAM-only gèlerait `SILO_COOLDOWN`.
- **Posted tous kinds :** `buildingsBySlot`. Bots upgrade / score nuke / rail collect via l’index.
- **Posted FACTORY :** `factoriesBySlot` (sous-ensemble, 10 Hz Trade). Ne pas itérer `buildingsBySlot` pour les colis.
- **Posted PORT :** `portsByTile` `{slot, level}`. Distinct de `_carriersDirty` (NAVAL_BASE). Vague = `TRADE_SHIP_INTERVAL` 45, pas 10 Hz. **Loi manhattan visuelle inchangée.**
- **Posted NAVAL_BASE :** `navalBasesBySlot`. Spawn seulement si `_carriersDirty`. Un PORT n’est jamais un carrier.
- **Warships targeting :** `carrierBuf`/`targetBuf` (V24). Early-out 0 carrier / 0 bateau d’un autre slot. Pas de spatial hash.
- **Score nuke bots :** `fillBlastBuf` une fois par visée (V27). Index présent + set nil = 0, pas de fallback hash.
- **UnitSnapshot 10 Hz :** `snapshotBoats` / `snapshotMissiles` (V26). Table vide recyclee (pas `nil`) pour retirer le dernier fantôme client. Pas de `path` / `homeTile` / `retreating` / `progress` / `sx`.
- **BuildingDelta 10 Hz :** `buildingSnapBuf` (V28). Early-out dirty vide → `nil`. Destruction `kind=0`. `links` = table live (Overlay lit tout de suite).
- **HUD fronts 10 Hz :** `frontHudForReplicate` (V29), appelé **une fois** depuis `playerStatsForReplicate`. Terre et `isBeachhead` = tas séparés. Slot sans front absent (nil, pas `{}`).
- **Prix HUD 10 Hz :** `Buildings.pricesFor` (V30). Slot inconnu = map vide, **pas** `math.huge` (réservé à `priceFor` unitaire). Pas dans GameState — cycle `require`.
- **Stats HUD 10 Hz :** `playerStatsForReplicate` (V31). `eraProgress` / `buildPrices` posés dans `init.server`. Record recyclé par slot ; slot parti absent de la porteuse.
- **Ère HUD 10 Hz :** `Research.progress` (V32). Min scalaire or / tuiles / bâtiments, **pas** de table `ratios`. Slot inconnu / `MAX_ID` = 1. Schéma `eraProgress` number 0..1 inchangé.
- **Diplomatie 1 Hz :** `viewFor` (V33). **Un record par slot** (`viewBuf[slot]`), pas un buf global (la boucle `FireClient` séquentielle viderait le client précédent). Slot disparu → maps vides, pas de scan. `requestIsLive` visuel conservé.
- **Diplomatie 10 Hz :** `Diplomacy.step` (V34). `expiredBuf` + `expiredRecPool`. Collecter `n`, poser `rec.a`/`rec.b`, itérer `1..n`. **`true` legacy continue** ; non-number (ex. `"oops"`) expire. Feel N79 ne copie pas ce type-guard.
- **Bots perception :** `Bots.neighborFactions` (V35). `contactBuf` unique, `table.clear`. Slot inconnu → map vide. **Pas réentrant.**
- **Bots pose :** `Bots.gatherSites` (V36). `siteBuf` (`table.create(60)`). Caps 40/60/45. Pas de shuffle. Truncate leftover. Slot / côte vide → `# == 0`. **Pas réentrant.** Unique appelant `decideBuild`.
- **Élimination 10 Hz :** `stepElimination` (V37). `elimBuf` (`table.create(8)`). **Pas** nommé `doomed`. Skip `awaitingSpawn`. Truncate leftover **avant** `removePlayer`. Ne pas truncate à 0 après return. Buffer **partagé inter-instances**. `settledHumans` inchangé.
- **Path maritime :** `Navy.findSeaPath` (V38). `pathWalkBuf` walk scratch. Copie inverse dans un tableau **neuf**. `return out`, jamais `return pathWalkBuf`. Origine terrestre **exclue**. `visitBuf` / `parentPool` / `queuePool` inchangés. **Pas réentrant.** Unique appelant synchrone (invasion / retraite / convoi).
- **Réseau ferroviaire :** `refreshRailNetwork` (V39). `stationBuf` + `railParentBuf` / `railXsBuf` / `railYsBuf` + maps de grappe. Truncate leftover **puis** `table.sort`. Itérer `1..count`, pas `#`. Inners `neighborsOf` uniques. Formule HUD visuelle **sans** `TRAIN_STOP_BONUS`. **Pas réentrant.**
- **Spawn clic :** terre libre + `isSpawnIsolated`. Snap `r=6` seulement si la tuile cliquée est **occupée**.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `GameState` ne require pas `Buildings` / `Research` / `Types`.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–18) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.

---

## Specs worker (reste)

Ne pas merger feel `69f4`/`b62d` ni hardening `bef6` sur cette branche sans rebase. Porter **une** recette à la fois.

### ISSUE-V1 — Packing spawn 18 factions

**Problème.** `SPAWN_RADIUS=18` + `SPAWN_MIN_PLAYER_DISTANCE=30` : les seeds 7 / 99991 / 1234567 / 424242 placent 11–15 factions sur 18. Les tribus sautent. `spawnCenter` et `isSpawnIsolated` sont vivants mais le disque 21² reste trop large : occupancy ≫ minDist.

**20K CCU.** Un salon Classique sous-peuplé fausse l’éco, les bots et le climax nucléaire.

**Faire.** Recherche spirale / rejet plus souple pour `isTribe` (dist min 20) **ou** `TRIBE_SPAWN_RADIUS` plus petit. Ne pas réduire le disque humain. Ne pas re-poser `isSpawnIsolated` / `spawnCenter`.

**Contraintes.** Server-only. `addPlayer` rollback si `findSpawn` nil. `stripTerritory` doit continuer d’effacer `spawnCenter`.

**Tester.** `EXTRA_SEEDS` + seed 424242 : `spawned == BOT_COUNT + TRIBE_COUNT`. `./tests/run.sh`.

### ISSUE-V7 — `findSpawn` / `claimSpawn` anti-splash

**Problème.** Spawn ignore cratère ogive / fallout chaud. Un humain peut (re)naître dans le splash. Isolation clic (V16b) ne couvre **pas** le fallout.

**Faire.** Recette feel N50/N52 : `isSpawnSafe` partagé `findSpawn` + `claimSpawn` (C1+C2), **en plus** de `isSpawnIsolated`. Contrat B missiles inbound **inchangé**.

**Tester.** MIRV existant + capitale sous fallout → refus / autre tuile. Isolation clic (passe 19) reste verte.

### ISSUE-V9b — Persistence debounce 30 s

**Problème.** `Persistence.record()` marque dirty **puis** appelle `save()` tout de suite (`UpdateAsync` / humain). Le double-write `release`/`BindToClose` est corrigé ; la tempête de fin de match (8 writes synchrones) reste.

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

**Problème.** Passe 17 recycle `deltaIndices` mais `buffer.create(count * 5)` reste obligatoire : un tampon trop grand serait lu comme des tuiles fantômes (slot 0). Feel N72 a `dirtyIndexBuf` (liste d’indices, pas l’en-tête filaire).

**20K CCU.** 10 Hz playing × alloc buffer = pression GC sur 8 clients.

**Faire.** Préfixer le payload `[u32 count][u32 index][u8 slot]…` **ou** RemoteEvent séparé pour la longueur. Adapter le client (`WorldRenderer` / init.client). Growth-only ensuite. Ne pas porter feel N72 seul : ça ne ferme pas l’alloc `buffer.create`.

**Contraintes.** Changer client **et** serveur dans le même commit. Ne pas casser `RequestSnapshot` (carte entière, autre remote).

**Tester.** Match 6000 ticks, P0 metrics. Client 34/34.

### ISSUE-V40 — `Buildings.contextFor` table + 2 closures par resolve

**Problème.** Chaque `Buildings.resolve` (intent `BuildOrder` + `Bots.decideBuild`) fait `return { slot, era, gold, terrain, ownerAt = function…, buildingAt = function… }`. Trois allocations (record + 2 closures) par clic / décision bot. Les closures capturent `state`. `Placement.resolve` lit `ctx` de façon synchrone et abandonne — le record n’a pas besoin d’être unique. Feel N85. Distinct de V30 (`pricesFor`) et de V39 (`stationBuf`).

**20K CCU.** Un shard 8 humains + 16 bots pose/upgrade plusieurs fois par seconde en mid-game. Recycle du record + fonctions module (lisent `ctxState`) élimine l’alloc courte. Pas d’autorité (même `buffer.readu8(state.owner)` / `state.buildings[index]`). Ne pas fusionner avec le ctx client : `PlacementPreview` / `init.client` construisent **leurs** closures sur Overlay / WorldRenderer.

**Faire.** Recette feel N85 (`69f4`) :

1. Ajouter `ctxState: GameState?` et `ctxBuf: Placement.Context` module-level dans `Buildings.luau`. `ownerAt` / `buildingAt` = fonctions **module** (pas de `function` inline) : `ownerAt` lit `buffer.readu8(ctxState.owner, index)` ; `buildingAt` lit `ctxState.buildings[index]` (kind/slot/level ou nil,nil,nil — **même contrat**). `contextFor` : slot inconnu → `return nil` **sans** muter `ctxBuf`. Slot vivant : poser `ctxState = state`, `ctxBuf.slot/era/gold/terrain`, `ctxBuf.ownerAt` / `ctxBuf.buildingAt` = les fonctions module (identité stable), `return ctxBuf`.
2. Ne pas require de module nouveau. Ne pas toucher `pricesFor` / `siteBuf` / `stationBuf`. Ne pas toucher `Placement.luau` (le type `Context` reste). Ne pas toucher `PlacementPreview.resolve` (le client passe ses propres closures — un `ctxBuf` serveur n’existe pas côté client). `resolve` reste le seul appelant serveur. Pas de RemoteFunction.
3. Après V39. Ne pas porter `ChantierB` doomed/collapsing (V41) en même temps.

**Contraintes.** Server-only. Recette `viewBuf` (record réécrit, pas une nouvelle table) + closures stables. **V40 visual ≠ V30 (`pricesFor`, déjà fait) ≠ V36 (`siteBuf`, déjà fait) ≠ V39 (`stationBuf`, déjà fait).** `ctxBuf` n’est pas réentrant. `resolve` est synchrone et unique. Ne pas `table.clone(ctxBuf)`. Ne pas stocker le ctx au-delà de `Placement.resolve`. `terrain` est le buffer live (pas une copie) — Overlay client a le sien. Ne pas require Placement côté GameState (cycle).

**Tester.** `Buildings.contextFor(state, slot)` deux fois → `rawequal`. Slot 99 → `nil`. `Buildings.resolve` pose encore une CITY (snap / exact inchangé — banc placement existant). Après `contextFor(A)` puis `contextFor(B)`, un `ownerAt` **conservé** du premier ctx lit B (non réentrant — documenter, ne pas « corriger » en clonant). `./tests/run.sh`. Client 34/34. 6000 ticks.

**Fichiers.** `Buildings.luau` (`contextFor` + helpers module, `resolve` inchangé à l’appel), `tests/simulate.luau` (bloc court à côté du banc V30 / `pricesFor`).

### ISSUE-V41 — `ChantierB.cancelOpposingFronts` / `collapsing` allouent 10 Hz

**Problème.** Chaque tick avec fronts, `cancelOpposingFronts` fait `local doomed: { boolean } = {}` (hash sparse indexé par i d’attaque) et le wrap `stepAttacks` fait `local collapsing = {}` puis `table.insert(collapsing, { victim, captor })` par front sous le seuil. Deux allocations porteuses + N records par tick de combat. La loi (clash `min(troops)`, refund si troops>0 au remove, collapse si `tiles < collapseThreshold()` encore vrai **après** la passe) ne change pas. Feel N86. Distinct de V37 (`elimBuf` élimination) et de `retreatAttack` (couple).

**20K CCU.** Leftover combat vivant. 10 Hz × 18 slots × quelques fronts. Recycle des porteuses (et pool des records collapse) élimine l’alloc courte du hot path. Pas d’autorité (mêmes soustractions, même `table.remove` arrière, même notify). Ne pas fusionner avec `elimBuf` : collapse n’est pas une élimination (territoire redistribué, pas `removePlayer`).

**Faire.** Recette feel N86 (`69f4`) :

1. Ajouter `doomedBuf: { [number]: boolean } = {}` module-level dans `ChantierB.luau`. Au début de `cancelOpposingFronts` : `table.clear(doomedBuf)`. Remplacer `doomed` par `doomedBuf`. Ne **pas** itérer `#doomedBuf` (c’est un hash sparse — la boucle `for i = #state.attacks, 1, -1` reste). Ajouter `collapsingBuf` (`table.create(8)`) + `collapseRecPool` (`table.create(8)`, records `{ victim, captor }`). Au début du wrap `stepAttacks` : n = 0. À chaque insert : n += 1 ; réécrire un rec du pool (créer si `collapseRecPool[n] == nil`) ; `collapsingBuf[n] = rec`. Truncate leftover n+1..# **avant** la boucle `for _, entry in collapsing`. Traiter `1..n` (pas `#` sans truncate). Pas de RemoteFunction.
2. Ne pas toucher `BoatFront` (`parked` par `launchAttack`). Ne pas toucher `GameState.stepAttacks` mort (`local _ = origStepAttacks`). `CAPTURE_GUARD=80` visuel **inchangé**. `stripTerritory` visuel (`awaitingSpawn = true`) **inchangé**. Après V40. Ne pas porter `contextFor` en même temps.

**Contraintes.** Pas de RemoteFunction. Recette V34 (`expiredBuf` + pool records) pour collapsing ; recette `table.clear` hash pour doomed (comme `contactBuf` V35). **V41 visual ≠ V37 (`elimBuf`, déjà fait) ≠ V38 (`pathWalkBuf`, déjà fait).** `doomedBuf` / `collapsingBuf` ne sont pas réentrants. `stepAttacks` est unique par tick. Ne pas `table.remove` dans `collapsingBuf` pendant l’itération — la collecte est close avant le traitement. Un leftover d’état A dans l’état B sans truncate ferait collapse d’un slot fantôme — truncate obligatoire (recette V37). Les records ne sont pas répliqués.

**Tester.** Banc combat vivant existant (guard=80) **doit rester vert**. Ajouter : deux joueurs, fronts opposés A→B et B→A avec troupes égales → les deux fronts disparaissent, troupes restituées (clash). Un défenseur sous le seuil → `collapseFaction` toujours appelé (territoire du captor augmente). Deux appels `cancelOpposingFronts` sans fronts → pas d’erreur, `next(doomedBuf) == nil` après clear. `./tests/run.sh`. Client 34/34. 6000 ticks.

**Fichiers.** `ChantierB.luau` (`cancelOpposingFronts` + wrap `stepAttacks` seulement), `tests/simulate.luau` (bloc court).

---

## Hors scope volontaire

- Merger feel `69f4`/`b62d` / hardening `bef6` sur #39/#81.
- Spatial hash warships / `bunkerCells` (hardening N41) — `bunkersBySlot` + `carrierBuf` suffisent.
- Pairing convois simplifié hardening N40 (poids = level only) — la loi visuelle manhattan/alliance/`longCap` reste.
- `MODE_KEYS` mort (digits 1–4 = bâtiments). Cosmétique.
- Fallout disque = rayon **inner** seulement (OF outer = spec produit).
- Brancher les clés Config mortes (`ATTACK_SPEND_RATE`, `FRONT_TILES_PER_CONTACT`, `BOAT_LANDING_BONUS`).
- `combatUnlocked` forcé à `true` chaque tick playing (`init.server`) : prep=0, pas un leak client.
- Hover client `SpawnHint` (feel N58) — isolation serveur d’abord (V16b livré).
- `samsOf` / `fillBlastBuf` / `snapshotBoats` / `buildingSnapBuf` / `frontHudForReplicate` / `pricesFor` / `playerStatsForReplicate` / `viewFor` / `expiredBuf` / `contactBuf` / `siteBuf` / `elimBuf` / `pathWalkBuf` / `stationBuf` réentrants : un seul appelant chacun (sauf `viewFor` **par slot** — c’est voulu). Dupliquer le buffer si un second appelant apparaît. `playerStatsForReplicate` appelle `frontHudForReplicate` — ne pas rappeler le HUD dans `replicate()`.
- Feel N70 `retreating` sur le snapshot — Overlay visuel ne teinte pas la retraite.
- Feel N20 `TRAIN_STOP_BONUS` dans `refreshRailNetwork` — HUD visuel lit l’espérance **sans** ce multiplicateur ; `Trade.deliveryValue` l’applique déjà. Ne pas porter.
- `delivery.level` snapshot à l’arrivée (feel) : le header Trade dit « niveau à l’arrivée » ; dispatch stocke déjà `level` mais `resolve` lit `factory.level`. Produit, pas un bug d’index.
- Feel N85 (`contextFor`) / N86 (`doomedBuf`/`collapsingBuf`) — V40 / V41.
- `dirtyIndexBuf` (feel N72 / hardening N53) — ne ferme pas l’alloc `buffer.create` (voir V14b).

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–28 + **passe 29** (`findSeaPath` pathWalk identite unique + p1 intact, trajet inverse sans pollution ; `stationBuf` liens usine + income + identite `factory.links`, slot 99 sans erreur).  
Invariants 5b–5f : index `buildingsBySlot` / `coolingBuildings` / `factoriesBySlot` / `portsByTile` / `navalBasesBySlot` vs hash, chaque 500 ticks.  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
