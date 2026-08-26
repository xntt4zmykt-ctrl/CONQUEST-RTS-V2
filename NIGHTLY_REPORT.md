# Nightly report — passe 35 (revue PR #97)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-bee8` (PR #97, `c30dc38`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-2932`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #97 (`WorldRenderer.gainBuf` / `FactionLabels.countBuf` — HEAD visuel). Correctifs sûrs, sans merger feel `2b37`/`e277`/`1e43` ni hardening `ae35`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `HUD.update` recycle `self.ranked` + inner records | `HUD.luau` | V50 |
| `PlacementPreview.resolve` recycle `previewCtxBuf` | `PlacementPreview.luau` | V51 |

`gainBuf` / `countBuf` / `destroyBuf` / `validTiles` pools / `parkedBuf` / `collapseRemainBuf` / `allyBuf` / `stripBuf` / `ctxBuf` / `doomedBuf` / `collapsingBuf` **conservés**. `seedBeachhead` / inbound recycle / `settledHumans` / `awaitingSpawn` **non touchés**. `CAPTURE_GUARD=80` visuel **inchangé**. Schéma filaire client **inchangé** (V14b reste ouvert). `WorldRenderer.luau` / `FactionLabels.luau` **non édités**. Serveur **inchangé**. GameState ne require toujours pas Buildings / Research.

---

## Constatations PR #97 (à ne pas casser)

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
- **Deltas owner client :** `applyDelta` recycle `gainBuf` / `lossBuf` / `otherBuf` (V48). Truncate leftover **avant** return. Early-out `count == 0` → pools à `# == 0` (jamais `{}`). Loi inchangée (colonisation du neutre sans effet). Effects / init.client lisent tout de suite et n’en conservent pas l’identité. **Pas réentrant.** Distinct de V14b (filaire `buffer.create`).
- **Étiquettes :** `surveyTerritories` recycle `sumXBuf` / `sumYBuf` / `countBuf` (V49). `table.clear` **avant** le scan (leftover slot A = étiquette fantôme). Hash slot→nombre, pas d’array. **Pas réentrant.** Distinct de V48 (arrays) et de V35 (`contactBuf` serveur).
- **Classement HUD :** `HUD.update` recycle `self.ranked` + inner records (V50). Truncate leftover **avant** `table.sort`. Pas de `table.insert`, pas de nouvelle table. `VictoryScreen.show` lit tout de suite et copie vers `row.Text` — il ne stocke pas l’identité. Clé de tri inchangée (tuiles desc, tie-break troupes). **Pas réentrant.** Distinct de V49 (hash barycentre) et de V31 (`playerStatsForReplicate` serveur).
- **Fantôme placement :** `PlacementPreview.resolve` recycle `previewCtxBuf` (V51). Six champs réécrits, pas de nouvelle table. Recette feel N92 **sans** merger feel. `Placement.resolve` lit tout de suite. **Pas réentrant.** Distinct de V40 (`ctxBuf` serveur) et de V47 (`validTiles`). Preview n’appelle pas `validTiles`.
- **Spawn clic :** terre libre + `isSpawnIsolated`. Snap `r=6` seulement si la tuile cliquée est **occupée**.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `GameState` ne require pas `Buildings` / `Research` / `Types`.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–18) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.

---

## Specs worker (reste)

Ne pas merger feel `2b37`/`e277`/`1e43` ni hardening `ae35` sur cette branche sans rebase. Porter **une** recette à la fois.

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

**Problème.** Passe 17 recycle `deltaIndices` mais `buffer.create(count * 5)` reste obligatoire : un tampon trop grand serait lu comme des tuiles fantômes (slot 0). Feel N72 a `dirtyIndexBuf` (liste d’indices, pas l’en-tête filaire). V48 recycle les **listes d’effets** Overlay, pas le payload.

**20K CCU.** 10 Hz playing × alloc buffer = pression GC sur 8 clients.

**Faire.** Préfixer le payload `[u32 count][u32 index][u8 slot]…` **ou** RemoteEvent séparé pour la longueur. Adapter le client (`WorldRenderer` / init.client). Growth-only ensuite. Ne pas porter feel N72 seul : ça ne ferme pas l’alloc `buffer.create`.

**Contraintes.** Changer client **et** serveur dans le même commit. Ne pas casser `RequestSnapshot` (carte entière, autre remote). Ne pas retoucher `gainBuf` (V48 déjà).

**Tester.** Match 6000 ticks, P0 metrics. Client 34/34.

### ISSUE-V52 — `Overlay.applyUnits` closure `track` + extra missile 10 Hz

**Problème.** Chaque `UnitSnapshot` (10 Hz playing) fait `local function track(...)` dans `applyUnits` (une closure neuve par lot) puis, pour **chaque** missile, `extra = { tx = missile.tx, ty = missile.ty }`. `stepInterpolation` lit `unit.extra.tx/ty` plus tard. Distinct de `Vector2.new` sur `current`/`target` (hors passe : Vector2 Roblox est immuable ; changer la représentation est un refactor). Distinct de V50 (HUD ranked) et V51 (ctx Preview).

**20K CCU.** Leftover V51. 8 clients × 10 Hz × (1 closure + 1 table / missile en vol). Pas d’autorité (interpolation cosmétique). Un leftover `extra` d’un navire réutilisé en missile (ids recyclés côté serveur) viserait un `tx/ty` fantôme.

**Faire.**

1. Hoister `track` en fonction module (`trackUnit(self, id, slot, kind, x, y, isMissile, extra)`) — plus de closure par snapshot. `self.seen` / `self.units` inchangés (`table.clear(self.seen)` déjà). Pas de RemoteFunction.
2. Extra missile : à l’insert, poser `unit.extra = { tx, ty }` **une fois**. Sur un missile déjà suivi : muter `unit.extra.tx` / `unit.extra.ty` (créer extra si nil). Ne **pas** remplacer `unit.extra` par une nouvelle table à chaque lot. Navire : `extra` reste nil.
3. Ne **pas** changer `current` / `target` Vector2 (hors passe). Ne pas porter HUD ranked (V50) ni Preview ctx (V51). Ne pas retoucher `snapshotBoats` / `snapshotMissiles` serveur (V26 déjà, **sans** `retreating`). Après V51.

**Contraintes.** Client-only. Recette boatSnapBuf inner (records mutés). **V52 visual ≠ V26 (payload serveur) ≠ Vector2 refactor.** Non réentrant — un seul `applyUnits` / lot. Client 34/34 (banc « navires, missiles et interpolation » **doit rester vert** : pieces, Name, `applyUnits({}, {})` détruit). **Ne pas** éditer le serveur.

**Tester.** Banc client navires **doit rester vert**. Deux `applyUnits` du même missile (`id=3`, `tx/ty` différents) → `overlay.units[3].extra.tx` = le second, `rawequal` du record extra. `./tests/run.sh`. Client 34/34.

**Fichiers.** `Overlay.luau` (`applyUnits` / `track` seulement), `tests/client.luau` **seulement si** un assert extra est ajouté dans le check « navires, missiles et interpolation » (ne pas ajouter un 35e check). `UnitModels.luau` **non**.

### ISSUE-V53 — `init.client` closures hover 60 Hz

**Problème.** RenderStepped en mode `build` alloue deux closures par frame : `function(index) return w:ownerAt(index) end` et `function(index) o:buildingAt(...)`. V51 recycle le **record** `previewCtxBuf` ; le caller continue de fabriquer les closures. `buildingCounts` est déjà poolé (`EMPTY_COUNTS`). Distinct de V51 (Preview) et de V40 (`ctxBuf` serveur, closures module).

**20K CCU.** Leftover V52. 8 clients × hover 60 Hz × 2 closures. Pas d’autorité (le serveur re-résout). `Placement.resolve` appelle `ownerAt` / `buildingAt` de façon synchrone — on peut passer des closures stables.

**Faire.**

1. Hoister deux fonctions module dans `init.client.luau` (capturent `world` / `overlay` upvalues, comme V40 `ownerAt`/`buildingAt` capturent `ctxState`). Passer ces fonctions à `preview:resolve` — plus de `function` inline dans RenderStepped. Overlay nil → `ownerAt` 0 / `buildingAt` nil (même loi que le `if o then` actuel). Pas de RemoteFunction.
2. Ne pas changer la loi snap / upgrade / exact / invalid. Ne pas retoucher `previewCtxBuf` (V51 déjà). Ne pas appeler `validTiles` depuis Preview. Ne pas porter Overlay `track` (V52) en même temps. Après V52.

**Contraintes.** Client-only. Recette V40 (closures module, pas de table). **V53 visual ≠ V51 (record ctx) ≠ V40 (serveur).** `world` / `overlay` sont déjà des locals module — les capturer est licite. Client 34/34 (bancs « apercu de placement » et « accrochage du placement » **doivent rester verts**). **Ne pas** éditer le serveur / `PlacementPreview.luau` / `tests/client.luau` sauf assert dans un check existant.

**Tester.** Banc client aperçu + accrochage **doivent rester verts**. Deux `preview:resolve` successifs même tuile → même `tile` / même `status` (déjà V51). `./tests/run.sh`. Client 34/34.

**Fichiers.** `StarterPlayerScripts/Client/init.client.luau` (RenderStepped aperçu seulement). `PlacementPreview.luau` **non**.

---

## Hors scope volontaire

- Merger feel `2b37`/`e277`/`1e43` / hardening `ae35` sur #39/#97.
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
- `Overlay.applyUnits` `Vector2.new` par unité 10 Hz — Vector2 Roblox est immuable ; changer la représentation (nombres) est un refactor, pas un recycle. Hors passe (V52 ne touche que `track` + `extra`).
- `HUD.update` ranked + records — **fermé** (V50).
- `PlacementPreview.resolve` ctx hover — **fermé** (V51).
- `RadialMenu` `entries` à l’ouverture — geste joueur, pas 10 Hz.
- `HUD.refreshDiplomacyPanel` `markers` — à la sélection, pas 10 Hz.

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–34 inchangées (passe 35 = client-only).  
Invariants 5b–5f : index `buildingsBySlot` / `coolingBuildings` / `factoriesBySlot` / `portsByTile` / `navalBasesBySlot` vs hash, chaque 500 ticks.  
Client V48 : check « deltas de terrain et conquetes classees » — prise slot 2→1 classée en gain, delta vide `# == 0` + `rawequal` pools.  
Client V49 : check « etiquettes de faction : centre, contenu et disparition » — second refresh sans slot 1 détruit l’ancre (leftover `countBuf` interdirait ça).  
Client V50 : check « identite, ere, diplomatie et classement » — second `HUD.update` d’un seul slot → `#hud.ranked == 1` et `slot == 3`.  
Client V51 : check « accrochage du placement et bascule en amelioration » — deux `resolve` successifs même tuile / même status.  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
