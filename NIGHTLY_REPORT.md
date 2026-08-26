# Nightly report — passe 46 (revue PR #124)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-65f4` (PR #124, `c585c6b`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-f5e9`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #124 (`Overlay.applyRouteProgress` interpolation nombres — HEAD visuel). Correctifs sûrs, sans merger feel `8f41`/`4a67` ni hardening `2ea8`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `applyRouteProgress` pose `CFrame.new(cx, cy, cz) * segment.rot` (`rot` cuit une fois), plus de `CFrame.lookAt` deux Vector3 60 Hz | `Overlay.luau` | V63 |

`rankByTiles` / hover closures / `trackUnit` extra / `targetX`/`currentX` / unités lookAt (V56) / camion lerp (V57) / houle (V58) / feuillage (V59) / câble PORT (V60) / lift cuit (V61) / interpolation nombres (V62) / `previewCtxBuf` / `self.ranked` / `gainBuf` / `countBuf` / `destroyBuf` / `validTiles` pools / `parkedBuf` / `collapseRemainBuf` / `allyBuf` / `stripBuf` / `ctxBuf` / `doomedBuf` / `collapsingBuf` **conservés**. `seedBeachhead` / inbound recycle / `settledHumans` / `awaitingSpawn` **non touchés**. `CAPTURE_GUARD=80` visuel **inchangé**. Schéma filaire client **inchangé** (V14b reste ouvert). `HUD.luau` / `init.client.luau` / `PlacementPreview.luau` / `FactionLabels.luau` / `UnitModels.luau` / `WorldSpace.luau` / `WorldRenderer.luau` / `BuildingModels.luau` **non édités**. Serveur **inchangé**. GameState ne require toujours pas Buildings / Research. Extra missile **inchangé** (V52). `targetX`/`currentX` **inchangés** (V55). Unités lookAt **inchangées** (V56). Camion lerp **inchangé** (V57). Houle `oceanRipples` **inchangée** (V58). Feuillage `animatedFoliage` **inchangé** (V59). Câble `PortCraneCable` **inchangé** (V60). Lift `layer.origin` **inchangé** (V61). Lerp `ox/dx` **inchangé** (V62). Radar / `CapitalFlag` / `PortCraneBoom` `CFrame.Angles` **inchangés**. Transparency CityWindows / beacons / FactoryOutput / SiloWarning **inchangées**. `RestCFrame` posé à la construction **inchangé**. Explosion / wake / splash **inchangés** (événement). `part.Size = Vector3.new` chantier **inchangé** (API). LookAt camion / unités **conservés** (leftover V64, pas V63).

---

## Constatations PR #124 (à ne pas casser)

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
- **Classement HUD :** `HUD.update` recycle `self.ranked` + inner records (V50). Truncate leftover **avant** `table.sort`. Pas de `table.insert`, pas de nouvelle table. Comparateur `rankByTiles` module (V54) — plus de `function` inline 10 Hz. Loi inchangée (tuiles desc, tie-break troupes). `VictoryScreen.show` lit tout de suite et copie vers `row.Text` — il ne stocke pas l’identité. **Pas réentrant.** Distinct de V49 (hash barycentre) et de V31 (`playerStatsForReplicate` serveur).
- **Fantôme placement :** `PlacementPreview.resolve` recycle `previewCtxBuf` (V51). Six champs réécrits, pas de nouvelle table. Recette feel N92 **sans** merger feel. `Placement.resolve` lit tout de suite. **Pas réentrant.** Distinct de V40 (`ctxBuf` serveur) et de V47 (`validTiles`). Preview n’appelle pas `validTiles`. Closures `ownerAt` / `buildingAt` : désormais stables côté caller (V53).
- **Unités Overlay :** `applyUnits` hoist `trackUnit` (V52). Insert missile : `unit.extra = { tx, ty }` **une fois** (copie, jamais l’alias `missileSnapBuf`). Déjà suivi : muter `tx`/`ty`, jamais remplacer le record. Navire : `extra` reste nil. `table.clear(self.seen)` déjà. **Pas réentrant.** Distinct de V26 (payload serveur). Cible : `targetX`/`targetY` + `currentX`/`currentY` nombres (V55) — insert pose une fois, update mute, lerp numérique. Splash / interpolation lisent `currentX`/`currentY`. Pose 60 Hz : X/Z monde en nombres (`x * TILE - HALF + TILE/2`, constantes Overlay depuis Config) + **un** `CFrame.lookAt` par unité (V56). Immobile = regard −Z (même pose que `CFrame.new(x,y,z)`). Plus de `WorldSpace.tileToWorld` / `Vector3.Unit` / `CFrame.new(position)` sur le chemin unités. Extra missile **inchangé**. `WorldSpace.tileToWorld` reste pour splash / explosion / bâtiments (événement, pas 60 Hz unités).
- **Camion Overlay :** boucle `route.delivery` de `stepInterpolation` (V57). Lerp X/Y/Z en nombres depuis `path[i].X/.Y/.Z` + `TRUCK_LIFT` (0.8, déjà cuit dans `route.from`/`route.to` — plus de `Vector3.new(0, 0.8, 0)`). Un `CFrame.lookAt` par camion. Pièces non-roue : `frame * piece.offset` **sans** `* CFrame.new()`. Roues : `CFrame.Angles` (spin) conservé. `buildFactoryRoute` / `route.path` Vector3 **inchangés** (posé à la construction). Voie sans `delivery` → `continue`, zéro alloc. Pulse / `Parent = nil` à l’arrivée **inchangés**. **Pas réentrant.** Distinct de V56 (unités), V55 (`targetX`), V52 (`extra`).
- **Houle océan :** boucle `oceanRipples` de `WorldRenderer.step` (V58). Lire `ripple.base.X/.Y/.Z` en nombres, poser `CFrame.new(bx + wave * 0.45, by, bz + math.cos(time + phase) * 0.2)`. Plus de `ripple.base + Vector3.new(...)`. `Transparency` inchangée (`0.73 + wave * 0.09`). `buildOcean` / `ripple.base` **inchangés** (glints posés une fois). 0 glint → zéro alloc. **Pas réentrant.** Distinct de V57 (camion), V56 (unités), V55 (`targetX`). Rotation Y des glints (`CFrame.Angles` à `buildOcean`) n’est pas rejouée dans `step` : `CFrame.new(x,y,z)` pose l’identité — acceptable (vue stratégique, bandes minces).
- **Feuillage :** boucle `animatedFoliage` de `WorldRenderer.step` (V59). Lire `leaf.base.X/.Y/.Z` en nombres, poser `CFrame.new(bx, by + math.sin(time * 1.2 + leaf.phase) * 0.018, bz)`. Plus de `leaf.base * CFrame.Angles(...)`. Amplitude 0.018 conservée en translation Y (Ball : tilt ≈ invisible). `buildDecorations` / `leaf.base` **inchangés**. 0 couronne → zéro alloc. **Pas réentrant.** Distinct de V58 (houle), V57 (camion), V56 (unités), V60 (câble).
- **Câble PORT :** branche `PortCraneCable` de `BuildingModels.animate` (V60). Lire `rest.X/.Y/.Z` en nombres, poser `CFrame.new(rx, ry + math.sin(time * 0.8) * 0.35, rz)`. Plus de `rest + Vector3.new(...)`. Amplitude 0.35 conservée. `RestCFrame` posé une fois à `create`. Radar / flag / boom `CFrame.Angles` **inchangés** (rotation visible). Transparency **inchangée**. 0 câble (usine, ville) → la branche n’alloue rien. **Pas réentrant.** Distinct de V59 (feuillage), V58 (houle), V57 (camion), V61 (chantier).
- **Chantier de voie :** `applyRouteProgress` (V61 + V62 + V63). `layer.origin` / `layer.ox/oy/oz` cuits une fois dans `buildFactoryRoute` (shoulder = origin, asphalt = `+ (0, 0.08k, 0)`, stripe = `+ (0, 0.18k, 0)`). `segment.dx/dy/dz` cuits depuis `direction` (grille HV, un axe ≈ 0). `segment.rot = CFrame.lookAt(Vector3.zero, direction)` cuit une fois. Hot path : `t = visible - shown / 2` ; `cx, cy, cz = ox + dx*t, oy + dy*t, oz + dz*t` ; `CFrame.new(cx, cy, cz) * segment.rot`. Plus de `layer.origin + direction * t`. Plus de `CFrame.lookAt` 60 Hz. `part.Size = Vector3.new` **inchangé** (API). `layer.origin` / `segment.direction` conservés (construction, pas le hot path). 0 chantier (`construction == nil`) → `continue`, zéro alloc. **Pas réentrant.** Distinct de V60 (câble), V57 (camion **livraison**), V61 (lift), V62 (lerp). Leftover : `Size = Vector3.new` 60 Hz (API) et lookAt camion / unités (V64).
- **Hover 60 Hz :** `previewOwnerAt` / `previewBuildingAt` module (V53). Capturent `world` / `overlay`. Overlay nil → `buildingAt` nil. World nil → `ownerAt` 0. Plus de `function` inline dans RenderStepped. **Pas réentrant** au sens V40 (un resolve / frame). Distinct de V51 (record ctx) et de V40 (serveur).
- **Spawn clic :** terre libre + `isSpawnIsolated`. Snap `r=6` seulement si la tuile cliquée est **occupée**.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `GameState` ne require pas `Buildings` / `Research` / `Types`.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–18) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.
- **PR #124 :** interpolation nombres `ox/dx` (V62) intacte. Banc pose/capture → Parts Road stables, `oy` asphalt ≠ shoulder, `rot` à l’origine et `rawequal` après deux frames. Rien à revert.

---

## Specs worker (reste)

Ne pas merger feel `8f41`/`4a67` ni hardening `2ea8` sur cette branche sans rebase. Porter **une** recette à la fois.

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

### ISSUE-V64 — Overlay camion lookAt deux Vector3 60 Hz

**Problème.** V63 ferme le lookAt chantier. Reste, **par camion en livraison, à chaque frame** : `CFrame.lookAt(Vector3.new(px, py, pz), Vector3.new(px+dx, py+dy, pz+dz))`. Deux allocs Vector3 **en plus** du `CFrame.Angles` roues (rotation réelle, inévitable). La direction d’un segment de `route.path` est constante (grille HV, assertée au banc, Y lift identique aux deux bouts). Distinct de V63 (chantier `segment.rot`), de V57 (lerp nombres camion), de V56 (unités — le look **change** chaque frame tant que `mag > 0.01`, pas la même recette). Recette : cuire `route.segRot[i] = CFrame.lookAt(Vector3.zero, path[i+1] - path[i])` à `buildFactoryRoute` (après le `path`), composer `CFrame.new(px, py, pz) * route.segRot[segmentIndex]`.

**20K CCU.** Leftover V63. 8 clients × 60 Hz × N camions en vol × 2 Vector3 lookAt. Pas d’autorité (pose cosmétique). Changer `path` sans adapter `segRot` casserait l’assiette aux virages.

**Faire.**

1. Dans `buildFactoryRoute` seulement, après construction de `path` (`#path >= 2` déjà), poser `segRot` : pour `i = 1 .. #path-1`, `d = path[i+1] - path[i]` ; si `d.Magnitude < 0.01` alors identité (ou réutiliser le précédent) ; sinon `CFrame.lookAt(Vector3.zero, d)`. Stocker `route.segRot = segRot` (array 1-indexé, même index que `segmentIndex` du hot path). Dans la boucle `route.delivery` de `stepInterpolation` : garder lerp `px/py/pz` (V57) ; poser `frame = CFrame.new(px, py, pz) * route.segRot[segmentIndex]`. Plus de `CFrame.lookAt` 60 Hz camion. Roues : `CFrame.Angles` **conservé**. Pièces non-roue : `frame * piece.offset` **inchangé**. `TRUCK_LIFT` **inchangé**. `path` Vector3 **inchangé** (posé à la construction). Voie sans `delivery` → `continue`, zéro alloc. Pulse / `Parent = nil` à l’arrivée **inchangés**. Unités lookAt **inchangé** (V56). Chantier `segment.rot` **inchangé** (V63). Lift / lerp nombres / câble / houle / feuillage **inchangés**. Extra missile **inchangé** (V52). `targetX` **inchangé** (V55).
2. Ne **pas** éditer `BuildingModels.luau` / `WorldRenderer.luau` / `UnitModels.luau` / `HUD.luau` / `WorldSpace.luau`. Ne pas recycler explosion / wake / splash (événement). Ne pas changer `ROUTE_BUILD_SPEED`. Après V63.
3. Ne pas porter Overlay chantier (V63 déjà) ni houle (V58) ni feuillage (V59) ni câble (V60) ni lift (V61) ni lerp nombres (V62 déjà). Ne pas convertir Radar / Flag / Boom (rotation visible). Ne pas « fermer » `Size` chantier (API). Ne pas « fermer » le lookAt **unités** (V56 — leftover distinct, le look suit `targetX` chaque frame).

**Contraintes.** Client-only. **V64 visual ≠ V63 (chantier) ≠ V57 (camion lerp) ≠ V56 (unités).** Non réentrant. Client 34/34 (banc « pose et capture » — dispatch → Parent + pulse, leftover V63 `rot` à l’origine / `rawequal` **doivent rester verts**). **Ne pas** éditer le serveur. 0 livraison → zéro alloc (déjà `continue`). `CFrame.new(px, py, pz) * rot` : l’assiette (look −Z le long du segment HV) doit rester identique à `lookAt(pos, pos+d)`. Virage à angle droit : `segmentIndex` change → `segRot` du nouveau segment, pas une interpolation d’assiette.

**Tester.** Banc client pose/capture **doit rester vert** : leftover V63 (`rot` origine, `rawequal` après deux frames, Y asphalt ≠ shoulder) **et** leftover V62 (`ox`/`dx` nombres) **et** leftover V61 (Parts stables) **et** leftover V57 (dispatch → Parent + pulse) **et** leftover V60 (câble Y ≠ rest) **doivent rester verts**. Après V64 : `segRot[segmentIndex]` `rawequal` d’un frame à l’autre tant que le camion reste sur le même segment. `./tests/run.sh`. Client 34/34.

**Fichiers.** `Overlay.luau` (`buildFactoryRoute` path + boucle `route.delivery` de `stepInterpolation` seulement). `tests/client.luau` **seulement si** un assert dans le check « pose et capture ». `BuildingModels.luau` **non**. `WorldRenderer.luau` **non**. `UnitModels.luau` **non**. `HUD.luau` **non**.

---

## Hors scope volontaire

- Merger feel `8f41`/`4a67` / hardening `2ea8` sur #45/#122.
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
- `Overlay.applyUnits` `Vector2.new` par unité 10 Hz — **fermé** (V55). V52 ne touche que `track` + `extra`. V54 ne touche que HUD sort.
- `HUD.update` ranked + records — **fermé** (V50). Comparateur sort — **fermé** (V54).
- `PlacementPreview.resolve` ctx hover — **fermé** (V51). Closures caller — **fermées** (V53).
- `Overlay.applyUnits` track + extra — **fermé** (V52).
- `RadialMenu` `entries` à l’ouverture — geste joueur, pas 10 Hz.
- `HUD.refreshDiplomacyPanel` `markers` — à la sélection, pas 10 Hz.
- `CFrame` / `Vector3` unités dans `stepInterpolation` 60 Hz — **fermé** (V56). V55 ne touche que les nombres cible / lerp. `CFrame.Angles` roulis navire **conservé** (sinon `UnitModels.place` perd le tangage). `CFrame.lookAt(Vector3.new, Vector3.new)` unités reste : leftover API distinct, pas V64. Camion lookAt — **ouvert** (V64).
- Camion `Vector3.new(0, 0.8, 0)` + `CFrame.new()` identité 60 Hz — **fermé** (V57). V56 ne touche que les unités. `CFrame.Angles` roues **conservé**. LookAt camion deux Vector3 — leftover V64 (distinct de V63 chantier).
- Houle océan `WorldRenderer.step` Vector3 60 Hz — **fermé** (V58). V57 ne touche que le camion. Rotation Y des glints (`CFrame.Angles` à `buildOcean`) n’est pas rejouée dans `step` : `CFrame.new(x,y,z)` pose l’identité — acceptable (vue stratégique, bandes minces).
- Feuillage `animatedFoliage` `CFrame.Angles` 60 Hz — **fermé** (V59). V58 ne touche que la houle.
- `BuildingModels.animate` `PortCraneCable` Vector3 60 Hz — **fermé** (V60). V59 ne touche que le feuillage. Radar / Flag / Boom `CFrame.Angles` = rotation réelle, leftover séparé (ne pas convertir en translation).
- `applyRouteProgress` Vector3 lift pendant chantier — **fermé** (V61). V60 ne touche que le câble. `part.Size = Vector3.new` = API, ne pas « fermer ».
- `applyRouteProgress` arithmétique `origin + direction * t` 60 Hz — **fermé** (V62). V61 ne touche que le lift cuit.
- `applyRouteProgress` lookAt deux Vector3 60 Hz — **fermé** (V63). V62 ne touche que le lerp nombres. `Size` = API, leftover après V63. LookAt camion / unités = leftover V64 / distinct.
- Overlay camion lookAt deux Vector3 60 Hz — **ouvert** (V64). V63 ne touche que le chantier. Unités lookAt = leftover distinct (look suit `targetX` chaque frame, pas cuisable par segment).
- `UnitModels.place` `Vector3.new` Size flamme missile — leftover séparé (API Size, ne pas éditer UnitModels dans V64). Radar / flag unité `CFrame.Angles` = rotation réelle.
- Explosion / wake / splash Vector3 — événement, pas 60 Hz.

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–45 inchangées (passe 46 = client-only).  
Invariants 5b–5f : index `buildingsBySlot` / `coolingBuildings` / `factoriesBySlot` / `portsByTile` / `navalBasesBySlot` vs hash, chaque 500 ticks.  
Client V48 : check « deltas de terrain et conquetes classees » — prise slot 2→1 classée en gain, delta vide `# == 0` + `rawequal` pools.  
Client V49 : check « etiquettes de faction : centre, contenu et disparition » — second refresh sans slot 1 détruit l’ancre (leftover `countBuf` interdirait ça).  
Client V50 : check « identite, ere, diplomatie et classement » — second `HUD.update` d’un seul slot → `#hud.ranked == 1` et `slot == 3`.  
Client V54 : même check — deux slots tuiles égales (100/100), troupes 10 vs 40 → `ranked[1].slot == 8` (tie-break troupes). Leftover V50 **doit rester vert**.  
Client V51 : check « accrochage du placement et bascule en amelioration » — deux `resolve` successifs même tuile / même status.  
Client V52 : check « navires, missiles et interpolation » — second `applyUnits` du même missile (`id=3`, `tx/ty` différents) → `extra.tx` = le second, `rawequal` du record extra ; navire `extra == nil` ; `applyUnits({}, {})` détruit.  
Client V53 : check « apercu de placement » + « accrochage » — inchangés (Preview n’est pas édité ; les closures stables sont dans init.client, hors bundle du check Preview).  
Client V55 : même check navires — `targetX`/`currentX` nombres ; second lot `x/y` différents → `targetX` mute + `rawequal` du record unité. Leftover V52 **doit rester vert**.  
Client V56 : même check navires — `stepInterpolation` après cible déplacée avance `currentX` **et** `currentY` (branche `mag > 0.01`, un lookAt). Premier `stepInterpolation` (unités immobiles, regard −Z) ne casse pas. Leftover V55 **doit rester vert**.  
Client V57 : check « pose et capture de chaque type de batiment » — `onTradeEvent("dispatch")` après voie unique → `truckModel.Parent == model` ; un frame plus tard delivery encore vivant ; 12 × 0.02 s → `delivery == nil`, `Parent == nil`, `DeliveryPulse` dans `overlay.root`. Leftover V56 **doit rester vert**. Le check « livraison : le gain s'affiche sur la gare » ne peut pas porter ça : la destruction en fin de pose vide `overlay.routes`.  
Client V58 : check « construction du monde 3D » — `#oceanRipples > 0` ; deux `world:step(1/60)` → `rawequal` Part, CFrame X ou Z ≠ `base`, Transparency dans `[0.64, 0.82]` ; `oceanRipples = {}` puis `step` ne lève pas. Leftover V57 **doit rester vert**.  
Client V59 : même check construction — `#animatedFoliage > 0` ; deux `world:step(1/60)` → `rawequal` Part, CFrame.Y ≠ `base` ; `animatedFoliage = {}` puis `step` ne lève pas. Leftover V58 **doit rester vert**.  
Client V60 : check « modeles procéduraux : le palier change la silhouette » — `Building.create(PORT)` + deux `animate(1)` / `animate(2)` → `rawequal` Part câble, CFrame.Y ≠ `RestCFrame.Y` ; `animate(FACTORY)` (0 câble) ne lève pas. Leftover V59 **doit rester vert**.  
Client V61 : check « pose et capture » — deux `stepInterpolation(1/60)` pendant chantier → `rawequal` Parts Shoulder/Road/CenterMark, `Road.CFrame.Y ≠ Shoulder.CFrame.Y` (lift cuit). Leftover V57 (dispatch) **et** leftover V60 (câble) **doivent rester verts**.  
Client V62 : même check pose/capture — `type(dx/oy) == "number"`, `oy` asphalt ≠ shoulder, `pavedLength` croît. Leftover V61 **doit rester vert**.  
Client V63 : même check pose/capture — `rot` à l’origine (`X/Y/Z == 0`), `rawequal` après deux `stepInterpolation`, Parts Shoulder/Road/CenterMark stables, Y asphalt ≠ shoulder. Leftover V62 **et** leftover V61 **et** leftover V57 (dispatch) **et** leftover V60 (câble) **doivent rester verts**.  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
