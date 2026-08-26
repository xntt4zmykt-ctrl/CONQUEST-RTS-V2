# Nightly report — passe 32 (revue PR #90)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-d3e2` (PR #90, `f42bdca`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-9a1f`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #90 (`Bots.decideDiplomacy` allyBuf / `ChantierB.stepDoomsday` stripBuf — HEAD visuel). Correctifs sûrs, sans merger feel `2b37`/`07c6` ni hardening `ca14`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `BoatFront.launchAttack` recycle `parkedBuf` | `BoatFront.luau` | V44 |
| `GameState.collapseFaction` recycle `collapseRemainBuf` / `collapseLeftBuf` / `collapseScratch` | `GameState.luau` | V45 |

`allyBuf` / `stripBuf` / `ctxBuf` / `doomedBuf` / `collapsingBuf` **conservés**. `seedBeachhead` / `enqueueFront` / `isBeachhead` **non touchés**. `COLLAPSE_MAX_PASSES` / plunder / `awaitingSpawn` **inchangés**. `CAPTURE_GUARD=80` visuel **inchangé**. Schéma filaire client **inchangé**. GameState ne require toujours pas Buildings / Research.

---

## Constatations PR #90 (à ne pas casser)

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
- **Placement serveur :** `Buildings.contextFor` (V40). `ctxBuf` + `ownerAt`/`buildingAt` module. Deux appels → `rawequal`. Slot inconnu → `nil` sans muter. **Pas réentrant** : un `ownerAt` conservé lit le `ctxState` vivant. `resolve` synchrone unique. Ne pas `table.clone`.
- **Clash / collapse 10 Hz :** `doomedBuf` hash + `collapsingBuf` pool (V41). `table.clear(doomedBuf)` en tête de `cancelOpposingFronts`. Ne **pas** itérer `#doomedBuf`. Truncate leftover collapsing **avant** `collapseFaction`. `ChantierB.doomedBuf` exposé pour le banc (`next` après clear). **Pas réentrant.** Distinct de `elimBuf` (redistribution, pas `removePlayer`).
- **Bots diplomatie :** `decideDiplomacy` recycle `allyBuf` (V42). Hash, `table.clear`, pas de truncate. Distinct de `contactBuf` (voisins de tuiles). **Pas réentrant.** `Bots.step` séquentiel — un second `clear` au bot suivant est voulu. `Bots.allyBuf` exposé banc (pas de filaire). Seuils accept/coalition **inchangés**.
- **Rot cadran :** `stepDoomsday` recycle `stripBuf` (V43). Array + truncate leftover **avant** arrachage. Reset `n=0` / truncate à 0 **après** (un leftover ferait `setOwner(NEUTRAL)` sur le camp précédent). Itérer `1..n`, pas `#`. Distinct de V13 (scan O(carte) encore). Formule `Doomsday.rotQuota` **inchangée**. **Pas réentrant.**
- **Têtes de pont :** `launchAttack` recycle `parkedBuf` (V44). Truncate leftover **avant** `origLaunch`. Réinsert `1..n`. 0 pont → 1 front terre ; 2 `seedBeachhead` + terre → 3 Attack, mêmes objets. **Pas réentrant.** Distinct de V41 (`collapsingBuf`) et V29 (HUD tas). `seedBeachhead` visuel inchangé (fallback enqueue la tuile, pas de refund feel).
- **Effondrement :** `collapseFaction` recycle `collapseRemainBuf` / `collapseLeftBuf` / `collapseScratch` (V45). Truncate **avant** plunder et **avant** swap. `where = collapseRemainBuf[1]` avant le premier swap. Slot 99 / victime à 0 inerte. **Pas réentrant.** Distinct de V41 (`collapsingBuf` victim/captor) et V37 (`elimBuf` slots). `stripTerritory` visuel (`awaitingSpawn`) inchangé.
- **Spawn clic :** terre libre + `isSpawnIsolated`. Snap `r=6` seulement si la tuile cliquée est **occupée**.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `GameState` ne require pas `Buildings` / `Research` / `Types`.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–18) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.

---

## Specs worker (reste)

Ne pas merger feel `2b37`/`07c6` ni hardening `ca14` sur cette branche sans rebase. Porter **une** recette à la fois.

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

**Problème.** `ChantierB.stepDoomsday` parcourt `TILE_COUNT` par joueur marqué pour arracher `quota` tuiles. V43 recycle seulement la **liste temporaire** (`stripBuf`) : le scan 40 960 reste.

**20K CCU.** 10 Hz × 40 960 lectures buffer quand le cadran tourne = pic en fin de partie.

**Faire.** Liste incrémentale des tuiles par slot (même structure que `border`) **ou** reservoir sampling sur un index compact. Ne pas changer la formule `Doomsday.rotQuota`. Ne pas retoucher `stripBuf` (V43 déjà).

**Tester.** Cadran existant + 1 humain sous quota. Invariants `tiles` vs buffer. Banc V43 (deux camps, chacun perd le sien) **doit rester vert**.

### ISSUE-V14b — En-tête de compteur pour `flushOwnerDelta`

**Problème.** Passe 17 recycle `deltaIndices` mais `buffer.create(count * 5)` reste obligatoire : un tampon trop grand serait lu comme des tuiles fantômes (slot 0). Feel N72 a `dirtyIndexBuf` (liste d’indices, pas l’en-tête filaire).

**20K CCU.** 10 Hz playing × alloc buffer = pression GC sur 8 clients.

**Faire.** Préfixer le payload `[u32 count][u32 index][u8 slot]…` **ou** RemoteEvent séparé pour la longueur. Adapter le client (`WorldRenderer` / init.client). Growth-only ensuite. Ne pas porter feel N72 seul : ça ne ferme pas l’alloc `buffer.create`.

**Contraintes.** Changer client **et** serveur dans le même commit. Ne pas casser `RequestSnapshot` (carte entière, autre remote).

**Tester.** Match 6000 ticks, P0 metrics. Client 34/34.

### ISSUE-V46 — `GameState.removePlayer` alloue `doomed` snapshot bâtiments

**Problème.** Chaque `removePlayer` fait `local doomed: { number } = {}` puis `table.insert` des clés `buildingsBySlot[slot]` (fallback hash `buildings` si l’index est nil). Une allocation porteuse + N inserts par élimination, y compris strip `tiles=0` et recycle de slot mid-game. La loi (snapshot **avant** `destroyBuilding` parce que destroy mute l’index, fallback hash pour tests partiels, inbound GC **avant** `setOwner`) ne change pas. Distinct de V37 (`elimBuf` slots) et de V41 (`doomedBuf` hash d’Attack) et de V45 (`collapseRemainBuf` tuiles).

**20K CCU.** Leftover V37. Un shard 18 slots élimine / recycle plusieurs fois par partie (strip, doomsday, conquête). Recycle de la porteuse élimine l’alloc courte. Pas d’autorité (mêmes `destroyBuilding`, même ordre). Ne pas fusionner avec `elimBuf` : elim collecte les slots, removePlayer détruit les bâtiments **d’un** slot. Ne pas fusionner avec `ChantierB.doomedBuf` (hash d’indices d’Attack). Ne pas nommer le buffer `doomed` : collision de vocabulaire avec V37/V41 — `destroyBuf`.

**Faire.**

1. Ajouter `destroyBuf: { number } = table.create(16)` module-level dans `GameState.luau`. `removePlayer` : n = 0 ; si `buildingsBySlot[slot]` alors clés → `destroyBuf[n] = index` ; sinon fallback hash `building.slot == slot`. Truncate leftover n+1..# **avant** la boucle `destroyBuilding` (un leftover d’état A détruirait un bâtiment fantôme d’état B au même index de tuile). Itérer `1..n`, pas `#` sans truncate. Pas de RemoteFunction.
2. Ne pas modifier `settledHumans` / inbound transports `kind==1` / missiles contrat B / convois `kind==2` / cadran / colis / `setOwner`. Ne pas require de module nouveau. Ne pas toucher `stepElimination` (`elimBuf` déjà). Fallback hash **conservé** (tests partiels sans index). Ne pas `table.clone` de `buildingsBySlot[slot]` (c’est un hash live que destroy mute). Après V45. Ne pas porter `validTiles` (V47) en même temps.

**Contraintes.** Server-only. Recette V37 (`elimBuf` truncate leftover **avant** traitement). **V46 visual ≠ V37 (`elimBuf`, déjà fait) ≠ V41 (`doomedBuf` Attack, déjà fait) ≠ V45 (`collapseRemainBuf` tuiles, déjà fait).** `destroyBuf` n’est pas réentrant. `removePlayer` est synchrone ; `stepElimination` peut enchaîner plusieurs slots — truncate **à chaque** appel (n recompté). Un leftover sans truncate ferait `destroyBuilding` d’une tuile encore occupée sur une autre instance. Overlay n’itère pas cette liste. Client 34/34 (pas 35 : pas de `SpawnHint` feel).

**Tester.** Banc `removePlayer index` / `buildingsBySlot` existant **doit rester vert**. Banc V37 elimBuf **doit rester vert**. Ajouter : `removePlayer` d’un slot sans bâtiment → pas d’erreur, `next(buildingsBySlot[slot])` nil. Deux instances : A a une CITY, `removePlayer(A)` ; B a une CITY à un **autre** index → la CITY de B survit (leftover). Slot déjà absent → return, pas d’erreur. `./tests/run.sh`. Client 34/34. 6000 ticks.

**Fichiers.** `GameState.luau` (`removePlayer` snapshot seulement, du `local doomed` jusqu’à la boucle destroy), `tests/simulate.luau` (bloc court à côté du banc « buildingsBySlot » / V37).

### ISSUE-V47 — `Placement.validTiles` alloue blockers / candidates / queue / visited

**Problème.** Chaque `Placement.validTiles` (donc chaque `resolve` build) fait `local blockers = {}`, `local candidates = {}`, `local visited = { [index] = true }`, `local queue = { index }`. Quatre allocations porteuses par clic / décision bot. Early-out `return {}` (kind non buildable, hors carte, tuile étrangère) alloue encore une table vide. La loi (BFS **connexe** sur le territoire, tri par distance, spacing, coastalOnly, `tiles[1]` = plus proche) ne change pas. Distinct de V40 (`ctxBuf` Buildings) et de V39 (`stationBuf`, pas `building.links`).

**20K CCU.** Leftover V40. Un shard 8 humains + 16 bots résout des poses plusieurs fois par seconde (bots `decideBuild`). Recycle des porteuses élimine l’alloc courte du BFS. Pas d’autorité (même graphe, même `tiles[1]`). Unique call site prod = `Placement.resolve` qui lit `#tiles` et `tiles[1]` **immédiatement** — on peut retourner le pool candidats (pas un clone). Ne pas fusionner avec `ctxBuf` : le ctx est un record ownerAt/buildingAt, pas la liste de tuiles.

**Faire.**

1. Ajouter `blockBuf: { number } = table.create(32)`, `candBuf: { number } = table.create(32)`, `queueBuf: { number } = table.create(64)`, `visitBuf: { [number]: true } = {}`, `emptyTileBuf: { number } = table.create(0)` module-level dans `Placement.luau`. Early-out kind/index/owner : `return emptyTileBuf` (**ne pas** y `table.insert`). `validTiles` vivant : nB / nC / nQ = 0 ; `table.clear(visitBuf)` ; seed `visitBuf[index]=true`, `queueBuf[1]=index`, nQ=1. Truncate leftover **avant** le BFS (queue) et **avant** le sort candidats (un leftover mélange d’anciennes tuiles dans `tiles[1]`). Itérer `1..n`, pas `#` sans truncate. Retourner `candBuf` (pas `table.clone`). Pas de RemoteFunction.
2. Ne pas modifier `resolve` / `priceFor` / `radiusFor` / spacing / coastalOnly. Ne pas toucher `PlacementPreview.luau` ni `Buildings.contextFor` (V40 déjà). Ne pas require de module nouveau. `neighbors` scratch `table.create(4, 0)` **par appel** peut passer en module (`placeScratch`, distinct de GameState.scratch). Early `return {}` existants → `emptyTileBuf`. Ne pas trier `candBuf` au-delà de nC. Après V46. Ne pas porter `destroyBuf` en même temps.

**Contraintes.** Pas de RemoteFunction. Recette V40 (`ctxBuf` leftover interdit de toucher Placement — c’est **ce** leftover). **V47 visual ≠ V40 (`ctxBuf`, déjà fait) ≠ V39 (`stationBuf`) ≠ V30 (`pricesFor`).** Les buf ne sont pas réentrants. `resolve` est synchrone et unique. `emptyTileBuf` ne doit **jamais** recevoir d’insert. Overlay / Preview client n’appellent pas `validTiles` (seulement `resolve` via le serveur, Preview construit son propre ctx). Retourner `candBuf` est licite **uniquement** parce que `resolve` lit `tiles[1]` tout de suite — ne pas stocker l’identité côté HUD. Un leftover non truncaté ferait poser sur une tuile d’un resolve précédent. Client 34/34. **Ne pas** éditer `tests/client.luau`.

**Tester.** Bancs placement / CITY resolve / V40 `contextFor` existants **doivent rester verts**. Ajouter : `validTiles` tuile étrangère → `# == 0`, `rawequal` avec un second early-out (même `emptyTileBuf`). Deux `resolve` CITY successifs sur le même ctx → `tile` identique (pas de leftover). Slot 99 / hors carte → `# == 0`, pas d’erreur. `./tests/run.sh`. Client 34/34. 6000 ticks.

**Fichiers.** `Placement.luau` (`validTiles` seulement), `tests/simulate.luau` (bloc court à côté du banc CITY / `contextFor` V40). **Ne pas** éditer `PlacementPreview.luau` / `tests/client.luau`.

---

## Hors scope volontaire

- Merger feel `2b37`/`07c6` / hardening `ca14` sur #39/#90.
- Spatial hash warships / `bunkerCells` (hardening N41) — `bunkersBySlot` + `carrierBuf` suffisent.
- Pairing convois simplifié hardening N40 (poids = level only) — la loi visuelle manhattan/alliance/`longCap` reste.
- `MODE_KEYS` mort (digits 1–4 = bâtiments). Cosmétique.
- Fallout disque = rayon **inner** seulement (OF outer = spec produit).
- Brancher les clés Config mortes (`ATTACK_SPEND_RATE`, `FRONT_TILES_PER_CONTACT`, `BOAT_LANDING_BONUS`).
- `combatUnlocked` forcé à `true` chaque tick playing (`init.server`) : prep=0, pas un leak client.
- Hover client `SpawnHint` (feel N58) — isolation serveur d’abord (V16b livré).
- `samsOf` / `fillBlastBuf` / `snapshotBoats` / `buildingSnapBuf` / `frontHudForReplicate` / `pricesFor` / `playerStatsForReplicate` / `viewFor` / `expiredBuf` / `contactBuf` / `siteBuf` / `elimBuf` / `pathWalkBuf` / `stationBuf` / `ctxBuf` / `doomedBuf` / `allyBuf` / `stripBuf` / `parkedBuf` / `collapseRemainBuf` réentrants : un seul appelant chacun (sauf `viewFor` **par slot** — c’est voulu). Dupliquer le buffer si un second appelant apparaît. `playerStatsForReplicate` appelle `frontHudForReplicate` — ne pas rappeler le HUD dans `replicate()`.
- Feel N70 `retreating` sur le snapshot — Overlay visuel ne teinte pas la retraite.
- Feel N20 `TRAIN_STOP_BONUS` dans `refreshRailNetwork` — HUD visuel lit l’espérance **sans** ce multiplicateur ; `Trade.deliveryValue` l’applique déjà. Ne pas porter.
- `delivery.level` snapshot à l’arrivée (feel) : le header Trade dit « niveau à l’arrivée » ; dispatch stocke déjà `level` mais `resolve` lit `factory.level`. Produit, pas un bug d’index.
- `dirtyIndexBuf` (feel N72 / hardening N53) — ne ferme pas l’alloc `buffer.create` (voir V14b).
- `buildRoster` (`init.server`, hors bundle) — 10 Hz playing, leftover N2 skip-si-inchangé.
- Feel `neighborScratch` dans `seedBeachhead` : visuel itère `priorityScratch` que `frontPriority` écrase. Ne pas le porter dans V44 (`seedBeachhead` gelé). Leftover séparé.
- `removePlayer` snapshot `doomed` — par élimination, pas 10 Hz (V46).
- `Placement.validTiles` blockers/candidates — par clic / décision bot, pas 10 Hz (V47).
- `Nukes.splitMirv` `targets` — par MIRV, pas le hot path.

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–31 + **passe 32** (`parkedBuf` 0 pont / 2 ponts+terre / leftover inter-instances ; `collapseRemainBuf` slot 99 inerte, victime à 0, truncate A→B).  
Invariants 5b–5f : index `buildingsBySlot` / `coolingBuildings` / `factoriesBySlot` / `portsByTile` / `navalBasesBySlot` vs hash, chaque 500 ticks.  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
