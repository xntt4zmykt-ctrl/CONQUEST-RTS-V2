# Nightly report — passe 33 (revue PR #92)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-9a1f` (PR #92, `4354548`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-ab8d`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #92 (`BoatFront.parkedBuf` / `GameState.collapseRemainBuf` — HEAD visuel). Correctifs sûrs, sans merger feel `2b37`/`07c6` ni hardening `9327`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `GameState.removePlayer` recycle `destroyBuf` | `GameState.luau` | V46 |
| `Placement.validTiles` recycle blockers / candidates / queue / visited | `Placement.luau` | V47 |

`parkedBuf` / `collapseRemainBuf` / `allyBuf` / `stripBuf` / `ctxBuf` / `doomedBuf` / `collapsingBuf` **conservés**. `seedBeachhead` / inbound recycle / `settledHumans` / `awaitingSpawn` **non touchés**. `CAPTURE_GUARD=80` visuel **inchangé**. Schéma filaire client **inchangé**. `tests/client.luau` et `PlacementPreview.luau` **non édités**. GameState ne require toujours pas Buildings / Research.

---

## Constatations PR #92 (à ne pas casser)

- **Autorité :** le client n’évalue aucune règle de combat/économie. Ordres = remotes + sequence. `Placement` est partagé : Preview et serveur exécutent le même `resolve` ; la vérité reste `Buildings.build` côté serveur.
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
- **Têtes de pont :** `launchAttack` recycle `parkedBuf` (V44). Truncate leftover **avant** `origLaunch`. Réinsert `1..n`. 0 pont → 1 front terre ; 2 `seedBeachhead` + terre → 3 Attack, mêmes objets. **Pas réentrant.** `seedBeachhead` visuel inchangé.
- **Effondrement :** `collapseFaction` recycle `collapseRemainBuf` / `collapseLeftBuf` / `collapseScratch` (V45). Truncate **avant** plunder et **avant** swap. Slot 99 / victime à 0 inerte. **Pas réentrant.**
- **Élimination bâtiments :** `removePlayer` recycle `destroyBuf` (V46). Snapshot **avant** `destroyBuilding` (destroy mute l’index). Fallback hash si `buildingsBySlot` nil. Truncate leftover **avant** la boucle destroy. Itérer `1..n`. **Pas réentrant.** Distinct de V37 (`elimBuf` slots) / V41 (`doomedBuf` hash d’Attack) / V45 (`collapseRemainBuf` tuiles). `GameState.destroyBuf` exposé banc (pas de filaire).
- **Placement partagé :** `validTiles` recycle `blockBuf` / `candBuf` / `queueBuf` / `visitBuf` / `emptyTileBuf` (V47). Early-out kind/index/owner → `emptyTileBuf` (**jamais** d’insert). Truncate leftover **avant** BFS (queue) et **avant** le sort. Retourne `candBuf` (resolve lit `tiles[1]` tout de suite). `placeScratch` distinct de `GameState.scratch`. **Pas réentrant.** Distinct de V40 (`ctxBuf`). Preview n’appelle pas `validTiles` (seulement `resolve`).
- **Spawn clic :** terre libre + `isSpawnIsolated`. Snap `r=6` seulement si la tuile cliquée est **occupée**.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `GameState` ne require pas `Buildings` / `Research` / `Types`.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–18) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.

---

## Specs worker (reste)

Ne pas merger feel `2b37`/`07c6` ni hardening `9327` sur cette branche sans rebase. Porter **une** recette à la fois.

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

### ISSUE-V48 — `WorldRenderer.applyDelta` alloue gains / losses / others

**Problème.** Chaque delta owner 10 Hz (playing) fait `local gains = {}`, `local losses = {}`, `local others = {}` puis `table.insert`. Trois allocations porteuses par tick par client, même si le delta est vide (`count = 0` → trois tables vides quand même). La loi (colonisation du neutre **sans** effet ; prise sur une faction → gains si `nextOwner == mySlot`, losses si `previous == mySlot`, others sinon) ne change pas. Distinct de V14b (payload `buffer.create`, filaire) : ici ce sont les **listes d’effets** côté Overlay.

**20K CCU.** Leftover V14b côté client. 8 humains × 10 Hz × 3 tables = pression GC client pendant les vagues de conquête (maxChanged du banc ~6800). Pas d’autorité (le client ne décide pas le owner). Unique call site = `applyDelta` → Overlay vagues. On peut retourner les pools (Overlay lit tout de suite).

**Faire.**

1. Ajouter `gainBuf: { number } = table.create(16)`, `lossBuf: { number } = table.create(16)`, `otherBuf: { number } = table.create(16)` module-level dans `WorldRenderer.luau`. `applyDelta` : nG / nL / nO = 0 ; remplir ; truncate leftover **avant** return (un leftover d’une vague A rejouerait un splash sur une tuile d’une vague B). Itérer `1..n`, pas `#` sans truncate. Early-out `count == 0` : truncate les trois à 0, retourner les pools vides (**ne pas** allouer `{}`). Pas de RemoteFunction.
2. Ne pas modifier le décodage `[u32 index][u8 slot]` (V14b reste ouvert). Ne pas toucher `flushOwnerDelta` / `markTileDirty` / `RequestSnapshot`. Ne pas require de module nouveau. Overlay : vérifier qu’il n’**stocke pas** l’identité des trois tables au-delà de la frame (s’il les range dans un champ, **cloner** ou dupliquer le pool — ne pas muter sous Overlay). Après V47. Ne pas porter `surveyTerritories` (V49) en même temps.

**Contraintes.** Client-only pour les buffers. Recette V47 (`candBuf` retourné parce que lu tout de suite). **V48 visual ≠ V14b (filaire `buffer.create`) ≠ V26 (`boatSnapBuf`).** Les buf ne sont pas réentrants. `applyDelta` est synchrone et unique par frame. Un leftover non truncaté ferait un effet de conquête fantôme. Client 34/34 (le banc « deltas de terrain et conquetes classees » **doit rester vert**). **Ne pas** éditer le schéma serveur.

**Tester.** Banc client « deltas de terrain et conquetes classees » **doit rester vert**. Deux `applyDelta` successifs : premier avec une prise, second delta vide → les trois listes `# == 0` (truncate). `./tests/run.sh`. Client 34/34.

**Fichiers.** `WorldRenderer.luau` (`applyDelta` seulement), `Overlay.luau` **seulement si** un champ conserve les tables (sinon ne pas toucher), `tests/client.luau` **seulement si** un assert truncate est ajouté dans le check existant (ne pas ajouter un 35e check). Serveur inchangé.

### ISSUE-V49 — `FactionLabels.surveyTerritories` alloue sumX / sumY / counts

**Problème.** Chaque `FactionLabels.refresh` (labels 10 Hz) fait `local sumX = {}`, `local sumY = {}`, `local counts = {}` puis parcourt la grille échantillonnée (`SAMPLE_STRIDE`). Trois hash alloués par refresh, même en lobby / 1 faction. La loi (barycentre = somme / compte échantillonné, pas `tiles` serveur ; slot disparu → `anchor:Destroy`) ne change pas. Distinct de V48 (listes de tuiles d’effets) et de V35 (`contactBuf` bots, serveur).

**20K CCU.** Leftover V48. 8 clients × 10 Hz × scan stridé + 3 hash. Recycle + `table.clear` élimine l’alloc courte. Pas d’autorité (labels cosmétique). `refresh` lit les trois maps tout de suite puis n’en conserve pas l’identité.

**Faire.**

1. Ajouter `sumXBuf: { [number]: number } = {}`, `sumYBuf: { [number]: number } = {}`, `countBuf: { [number]: number } = {}` module-level dans `FactionLabels.luau`. `surveyTerritories` : `table.clear` les trois **avant** le scan (un leftover d’un slot A afficherait une étiquette fantôme après `removePlayer`). Ne pas truncate d’array : ce sont des hash slot→nombre. Retourner les trois pools. Pas de RemoteFunction.
2. Ne pas modifier `SAMPLE_STRIDE` / formule barycentre / destruction d’ancre. Ne pas toucher Overlay / WorldRenderer (V48 déjà). Ne pas require de module nouveau. Après V48. Ne pas porter `applyDelta` en même temps.

**Contraintes.** Client-only. Recette V42 (`allyBuf` hash `table.clear`, leftover interdit). **V49 visual ≠ V48 (`gainBuf` arrays) ≠ V35 (`contactBuf` serveur).** Les buf ne sont pas réentrants. `refresh` est synchrone et unique. Un leftover sans `clear` ferait une étiquette pour un slot éliminé (le `counts[slot]` du tour d’avant). Client 34/34 (banc « etiquettes de faction : centre, contenu et disparition » **doit rester vert**). **Ne pas** éditer le serveur.

**Tester.** Banc client étiquettes **doit rester vert**. Deux `refresh` : premier avec 2 slots, second owner tout NEUTRAL → plus d’ancres. `./tests/run.sh`. Client 34/34.

**Fichiers.** `FactionLabels.luau` (`surveyTerritories` / `refresh` seulement), `tests/client.luau` **seulement si** le check existant suffit (ne pas ajouter un 35e check).

---

## Hors scope volontaire

- Merger feel `2b37`/`07c6` / hardening `9327` sur #39/#92.
- Spatial hash warships / `bunkerCells` (hardening N41) — `bunkersBySlot` + `carrierBuf` suffisent.
- Pairing convois simplifié hardening N40 (poids = level only) — la loi visuelle manhattan/alliance/`longCap` reste.
- `MODE_KEYS` mort (digits 1–4 = bâtiments). Cosmétique.
- Fallout disque = rayon **inner** seulement (OF outer = spec produit).
- Brancher les clés Config mortes (`ATTACK_SPEND_RATE`, `FRONT_TILES_PER_CONTACT`, `BOAT_LANDING_BONUS`).
- `combatUnlocked` forcé à `true` chaque tick playing (`init.server`) : prep=0, pas un leak client.
- Hover client `SpawnHint` (feel N58) — isolation serveur d’abord (V16b livré).
- Buffers déjà livrés réentrants : un seul appelant chacun (sauf `viewFor` **par slot** — c’est voulu). Dupliquer le buffer si un second appelant apparaît. `playerStatsForReplicate` appelle `frontHudForReplicate` — ne pas rappeler le HUD dans `replicate()`.
- Feel N70 `retreating` sur le snapshot — Overlay visuel ne teinte pas la retraite.
- Feel N20 `TRAIN_STOP_BONUS` dans `refreshRailNetwork` — HUD visuel lit l’espérance **sans** ce multiplicateur ; `Trade.deliveryValue` l’applique déjà. Ne pas porter.
- `delivery.level` snapshot à l’arrivée (feel) : le header Trade dit « niveau à l’arrivée » ; dispatch stocke déjà `level` mais `resolve` lit `factory.level`. Produit, pas un bug d’index.
- `dirtyIndexBuf` (feel N72 / hardening N53) — ne ferme pas l’alloc `buffer.create` (voir V14b).
- `buildRoster` (`init.server`, hors bundle) — 10 Hz playing, leftover N2 skip-si-inchangé.
- Feel `neighborScratch` dans `seedBeachhead` : visuel itère `priorityScratch` que `frontPriority` écrase. Ne pas le porter. Leftover séparé.
- `Nukes.splitMirv` `targets` — par MIRV, pas le hot path.
- `WorldRenderer.applyDelta` gains/losses/others — 10 Hz client (V48).
- `FactionLabels.surveyTerritories` — 10 Hz client (V49).

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–32 + **passe 33** (`destroyBuf` slot absent / sans bâtiment / leftover A→B CITY survit ; `validTiles` CAPITAL/hors carte/étrangère `emptyTileBuf` rawequal, deux resolve CITY tile identique).  
Invariants 5b–5f : index `buildingsBySlot` / `coolingBuildings` / `factoriesBySlot` / `portsByTile` / `navalBasesBySlot` vs hash, chaque 500 ticks.  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
