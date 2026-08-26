# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 40)

Déclencheur : ouverture de la **PR #121** (`cursor/analyse-nocturne-du-codebase-04b6`) — WorldRenderer houle/feuillage, specs N109–N110.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-5c7e`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#121.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. `BuildingModels.animate` pose un `CFrame.new` numérique par câble PORT (N109). `applyRouteProgress` lit `layer.origin` déjà cuit (N110). Houle (N107), feuillage (N108), camion (N105) et recycle Ground/Border (N106) restent.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #121 (passe 39) : claims vérifiés.** Houle X/Z nombres (N107) ; feuillage Y nombres sans `CFrame.Angles` (N108). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #121 a documenté (N109, N110)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #121

| Claim #121 | Réalité à l’ouverture |
|---|---|
| Houle `WorldRenderer.step` (N107) | Oui. X/Z en nombres depuis `ripple.base`, un `CFrame.new`. Plus de `Vector3.new` 60 Hz. Transparency inchangée. Recette visual V58, pas merger `5913`. |
| Feuillage `WorldRenderer.step` (N108) | Oui. Y en nombres depuis `leaf.base`, plus de `CFrame.Angles`. Amplitude 0.018 en translation Y. Recette visual V59, pas merger `6cec`. |
| Specs N109–N110 | **Corrigés ici.** N109 = câble PORT Y nombres + un `CFrame.new` (recette visual V60 déjà sur `a0d3` — **porté, pas mergé**). N110 = lift cuit dans `layer.origin` (recette visual V61 déjà fermée sur `3e1a` — **porté, pas mergé**). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #119 (`13ca` / `d317`), feel jusqu’à #121, visuelles #39/…/#120 (`a0d3` câble V60) / `3e1a` (lift V61 + leftover V62). **#121 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#119) reste distincte. Ne pas merger visual `3e1a` / `a0d3` / `6cec` ni hardening `d317` / `13ca` sans rebase.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N109–N110 du rapport #121.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `BuildingModels.animate` câble `Vector3` 60 Hz (N109) | `BuildingModels.luau` (`animate` branche `PortCraneCable` seulement), `tests/client.luau` (asserts dans le check modèles procéduraux existant) | Leftover N108. Lire `rest.X/.Y/.Z`, poser `CFrame.new(rx, ry + sin(time * 0.8) * 0.35, rz)`. Plus de `rest + Vector3.new`. Amplitude 0.35 conservée. Radar / flag / boom `CFrame.Angles` **inchangés**. Transparency inchangée. `RestCFrame` posé à la construction **inchangé**. Houle / feuillage / camion / unités **inchangés** (N107/N108/N105/N103). Recette visual V60, **pas** merger `a0d3`. Cosmétique (pose). 0 câble → zéro alloc. |
| `applyRouteProgress` lift `Vector3` chantier (N110) | `Overlay.luau` (`buildFactoryRoute` calques + `applyRouteProgress`), `tests/client.luau` (asserts dans le check pose/capture existant) | Leftover N109. Cuire `layer.origin = origin + Vector3.new(0, lift, 0)` à la pose. Hot path : `centre = layer.origin + direction * t` puis `CFrame.lookAt` **sans** `+ Vector3.new(0, lift, 0)`. LookAt conservé. `part.Size` = API. Câble / camion / houle / feuillage **inchangés** (N109/N105/N107/N108). Recette visual V61 déjà sur `3e1a`, **pas** merger. Cosmétique (pose). 0 chantier → zéro alloc. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), arithmétique `origin + direction * t` 60 Hz (**N111**), `table.remove(dirtyQueue, 1)` O(n) (**N112**). `PlacementPreview.resolve` ctx déjà **N92**. `self.ranked` inner déjà **N97**. Overlay `trackUnit` extra déjà **N98**. Hover déjà **N99**. `rankByTiles` déjà **N100**. `targetX` déjà **N101**. `BORDER_PASSES` déjà **N102**. lookAt unités déjà **N103**. `meshKeyAt` déjà **N104**. Camion déjà **N105**. Parts Ground déjà **N106**. Houle déjà **N107**. Feuillage déjà **N108**. `else {}` overlay-nil hors passe.

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (seq obligatoire en playing, apply immédiat) → tick :
  Bots.step → Navy.step (syncCarriers si dirty, spawn via navalBasesBySlot ;
    stepCarriers via carrierBuf/targetBuf, early-out 0 carrier / 0 autre slot ;
    coule TRADE si PORT absent ; TRANSPORT retraite si owner ~= targetSlot ;
    spawnTradeShips si tick % 45 == 0, via portsByTile ;
    findSeaPath via pathWalkBuf, retour unique) → Nukes.step
              (stepCooldowns SAM+silo indexés ; tryIntercept via samsBySlot ;
               launch via silosBySlot) → Trade.step (factoriesBySlot + factoryBuf)
              → Diplomacy.step (expiredBuf N79) → GameState.step → replicate(
                flushOwnerDelta via dirtyIndexBuf,
                playerStatsForReplicate + pricesFor + Research.progress (min courant),
                fireDeployed, snapshotBoats, snapshotMissiles,
                flushBuildingDelta via buildingSnapBuf)
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom,
    cancelOpposingFronts via doomedBuf, collapsingBuf 10 Hz,
    stepDoomsday via stripBuf, stripTerritory table.clear), BoatFront
    (park isBeachhead via parkedBuf), AimFront,
    tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`. Stub = `error(...)`. Deux débarquements du même couple = **deux** tas (N5 ouvert). Wrap `launchAttack` gare via `parkedBuf` (**N87**).
- **`areAllied`** = deux directions **et** `tick < expiry` (`true` legacy tests reste vivant).
- **AimFront wrap** = re-visée du front terre du couple ; jamais `isBeachhead`.
- **`tryAnnex`** = BFS depuis les voisins défenseur du seed déjà capturé ; océan abort ; pool N37-like.
- **Carriers** = spawn/despawn/slot sur dirty NAVAL_BASE, spawn via `navalBasesBySlot` (N65). Ciblage obus = `carrierBuf`/`targetBuf` recyclés **(N67)**. Pas de spatial hash.
- **Posted bunker** = index `bunkersBySlot`. **Posted SAM** = `samsBySlot`. **Posted SILO** = `silosBySlot`. **Posted FACTORY** = `factoriesBySlot`. **Tous** = `buildingsBySlot`. **PORT** = `portsByTile`. **Posted NAVAL_BASE** = `navalBasesBySlot`.
- **Réplication :** StateDelta (`dirtyIndexBuf` N72, HUD fronts N74 via N76, `buildPrices` N75, records stats N76, `eraProgress` N77) / UnitSnapshot (`retreating`, `boatSnapBuf` N70, `missileSnapBuf` N71) / BuildingDelta (`buildingSnapBuf` N73) / plunder / trade / explosions / notify&sfx déployés / Diplomacy.viewFor 1 Hz (N78). Playing 10 Hz ; lobby vide et ended → 1 Hz.
- Overlay `stepInterpolation` X/Z monde + un `lookAt` unités (**N103**) **et** camion (**N105**). `rebuildChunk` hisse `meshKeyAt` (**N104**) et recycle Ground/Border par chunk (**N106**). Houle océan (**N107**) et feuillage (**N108**) = nombres + un `CFrame.new`. Câble PORT (**N109**) = nombres + un `CFrame.new`. Lift voie (**N110**) cuit dans `layer.origin`. Arithmétique `origin + direction * t` encore 60 Hz (**N111**). `table.remove(dirtyQueue, 1)` O(n) (**N112**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N111–N112)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N110 = faits. N22 = **N67 fait**. N27 = doc only. **V60 / N109** fermés ici (portés, pas mergés). **V61 / N110** fermés ici (portés, pas mergés ; V61 déjà livré visuel `3e1a`). **V62** ouvert visuel `3e1a` (memories : fermé sur `65f4` si cette PR visual a atterri) — leftover feel = **N111** (porter les nombres, ne pas merger).

---

### ISSUE-N111 — `applyRouteProgress` arithmétique Vector3 60 Hz (feel)

**Priorité :** P3 alloc client chantier. Leftover explicite de N110 (lift cuit). Distinct de N110 (lift déjà) et de N105 (camion **livraison** — nombres déjà). Recette visual V62 **ouverte** sur `3e1a` (passe 44, PR visual #120+) — **porter la recette, ne pas merger**. Ne pas toucher BuildingModels (N109) ni WorldRenderer (N107/N108).

**Problème :** N110 ferme `+ Vector3.new(0, lift, 0)` **sur le lift**. Reste, **par calque de voie en chantier, à chaque frame** : `centre = layer.origin + segment.direction * (visible - shown / 2)` puis `CFrame.lookAt(centre, centre + segment.direction)`. Deux allocs Vector3 (mul/add + add direction) **en plus** du `Size = Vector3.new` (API, inévitable) et des deux Vector3 que `CFrame.lookAt` exige. Distinct de N110 (lift cuit), de N105 (camion déjà en nombres), de N103 (unités déjà en nombres). Recette N103/N105 : cuire `ox/oy/oz` et `dx/dy/dz` à la construction, interpoler en nombres.

**Pourquoi 20K CCU :** leftover N110. 8 clients × 60 Hz × N voies en chantier (0.35–3 s, pas tout le match) × 3 calques × 2 Vector3 arithmétiques. Pas d’autorité (pose cosmétique). Changer `layer.origin` sans adapter `applyRouteProgress` casserait l’assiette. 0 chantier (`construction == nil`) → zéro alloc (déjà `continue`).

**Worker :**

1. Dans `buildFactoryRoute` seulement, poser `layer.ox/oy/oz` (depuis `layer.origin.X/.Y/.Z` déjà cuit N110) et `segment.dx/dy/dz` (depuis `direction.X/.Y/.Z`, une fois — grille HV donc un axe ≈ 0). Dans `applyRouteProgress` : `t = visible - shown / 2` ; `cx, cy, cz = ox + dx*t, oy + dy*t, oz + dz*t` ; `CFrame.lookAt(Vector3.new(cx, cy, cz), Vector3.new(cx+dx, cy+dy, cz+dz))`. LookAt **conservé**. `part.Size = Vector3.new(...)` **inchangé**. `layer.origin` / `segment.origin` / `segment.direction` **peuvent rester** (construction, pas le hot path) ou être retirés s’ils ne servent plus. Radar / flag / boom / câble **inchangés** (N109 déjà). Camion / houle / feuillage / unités **inchangés** (N105/N107/N108/N103 déjà). Extra missile **inchangé** (N98). `targetX` **inchangé** (N101). Lift cuit **inchangé** (N110).
2. Ne **pas** éditer `BuildingModels.luau` / `WorldRenderer.luau` / `UnitModels.luau` / `HUD.luau` / `WorldSpace.luau`. Ne pas recycler explosion / wake / splash (événement). Ne pas changer `ROUTE_BUILD_SPEED` / durée 0.35–3 s. Après N110. Recette visual V62 **ouverte** sur `3e1a` — porter les **nombres**, pas merger visual.
3. Ne pas porter Overlay camion (N105 déjà) ni houle (N107) ni feuillage (N108) ni câble (N109) ni lift (N110 déjà). Ne pas convertir Radar / Flag / Boom (rotation visible). Ne pas « fermer » `Size` (API). Ne pas « fermer » les deux Vector3 de `CFrame.lookAt` (API Roblox) — leftover après N111, pas N111.
4. Test : banc client « pose et capture de chaque type de batiment » **doit rester vert** : leftover N110 (deux `stepInterpolation` → `rawequal` Parts, Y asphalt ≠ shoulder) **et** leftover N105 (dispatch → Parent + pulse) **et** leftover N109 (câble Y ≠ rest, Part stable) **et** leftover N107/N108 (construction houle/feuillage) **doivent rester verts**. `pavedLength` croît, chantier nil après 30 × 0.2 s. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
5. Fichiers : `Overlay.luau` (`buildFactoryRoute` calques + `applyRouteProgress` seulement). `tests/client.luau` **seulement si** un assert dans le check pose/capture existant (ne **pas** ajouter un 36e). `BuildingModels.luau` **non**. `WorldRenderer.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur ni visual `3e1a`.

**Contraintes :** pas de RemoteFunction. Recette visual V62 (nombres, ouverte sur `3e1a`). **N111 feel ≠ N110 (lift) ≠ N109 (câble) ≠ visual V62 (spec ouverte, ne pas merger).** Non réentrant. Ne pas fusionner avec N112 dans le même worker.

---

### ISSUE-N112 — `WorldRenderer.stepRebuilds` `table.remove(dirtyQueue, 1)` O(n) (feel)

**Priorité :** P3 file client O(n). Leftover explicite de N111 (arithmétique chantier) **et** de N106 (recycle Parts — la file n’a pas bougé). Distinct de N106 (pools Ground/Border déjà) et de N104 (`meshKeyAt` déjà). Pas d’équivalent visuel V62 (V62 = arithmétique Overlay). Ne pas toucher Overlay (N111/N110) ni BuildingModels (N109).

**Problème :** N106 recycle les Parts **d’un chunk**. Reste, **à chaque rebuild dans le budget** (`CHUNK_REBUILDS_PER_FRAME = 3`) : `table.remove(self.dirtyQueue, 1)` décale tout le tableau. Une vague de conquête (p95 dirty chunks = 7 au banc 6000 ticks, maxChanged = 479 tuiles) enfile des dizaines de chunks ; chaque pop tête est O(n). Distinct de N106 (identité des Parts), de N2 (skip payload), de `dirtyIndexBuf` serveur (N72). Recette : curseur `dirtyHead` + truncate quand la file est consommée, pas `table.remove(1)`.

**Pourquoi 20K CCU :** leftover N106. 8 clients × 60 Hz × jusqu’à 3 pops O(n) pendant les vagues. Pas d’autorité (file client). Un `table.remove` mal recalé sauterait un chunk sale (trou visuel) ou reconstruirait deux fois (flash). File vide → zéro travail (déjà).

**Worker :**

1. Dans `WorldRenderer.stepRebuilds` seulement : poser `self.dirtyHead` (init 1 dans le constructeur). Boucle : tant que `done < budget` et `dirtyHead <= #dirtyQueue`, lire `dirtyQueue[dirtyHead]`, incrémenter `dirtyHead`, traiter `if chunk and self.dirty[chunk]` comme aujourd’hui (`dirty[chunk] = nil`, `rebuildChunk`). Quand `dirtyHead > #dirtyQueue`, truncate `dirtyQueue[i] = nil` pour `i = 1..#` **ou** `#dirtyQueue = 0` + `dirtyHead = 1`. Ne **pas** `table.remove`. Ne pas changer `markDirty` / `table.insert(dirtyQueue, chunk)`. `rebuildChunk` recycle Ground/Border **inchangé** (N106). `meshKeyAt` **inchangé** (N104). Houle / feuillage **inchangés** (N107/N108).
2. Ne **pas** éditer `Overlay.luau` / `BuildingModels.luau` / `UnitModels.luau` / `HUD.luau` / `WorldSpace.luau` / `GreedyMesh.luau`. Ne pas porter N111 (arithmétique chantier). Après N111 si N111 est déjà mergé ici, sinon après N110. Pas de recette visual — V62 est Overlay.
3. Ne pas fusionner Ground et Border. Ne pas Destroy le folder. `partCount` inchangé. Océan / SeaFloor / glints / foliage hors file.
4. Test : banc client « construction du monde 3D » **et** « deltas de terrain et conquetes classees » **et** « vagues de conquete » **doivent rester verts**. Leftover N106 (`partCount` / Ground recyclé) **et** leftover N107/N108 (houle + feuillage) **doivent rester verts**. Deux `applyDelta` successifs → chunks reconstruits, pas de Part orpheline. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
5. Fichiers : `WorldRenderer.luau` (`new` + `stepRebuilds` seulement). `tests/client.luau` **seulement si** un assert dans le check construction ou deltas existant (ne **pas** ajouter un 36e). `Overlay.luau` **non**. `BuildingModels.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. Curseur + truncate, pas `table.remove(1)`, pas de deque module. **N112 feel ≠ N111 (arithmétique Overlay) ≠ N106 (recycle Parts) ≠ visual V62.** Non réentrant : synchrone, un chunk à la fois. Ne pas fusionner avec N111 dans le même worker.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; câble → **N109 fait** ; lift → **N110 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; câble → **N109 fait** ; lift → **N110 fait**) |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | ouvert |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 factions) | P1 | ouvert |
| N13 | Parité combat (ère / cost factor / constantes mortes) | P2 | ouvert |
| N14 | Apply immédiat vs lockstep (feel #19) | P1 | ouvert (produit) |
| N15 | `PREPARATION_DURATION=0` vs gardes `combatUnlocked` | P2 | ouvert |
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 | **N37+N42+N45 faits** ; path résultat → **N83 fait** |
| N17 | Humains éliminés occupent le cap | P2 | ouvert |
| N18 | Heap AimFront ≠ ChantierB / BoatFront | P2 | ouvert (frontier mixte mag vs TERRAIN_COST) |
| N19 | Embargo allié + tribus auto-accept | P2 | ouvert |
| N20 | `railIncome` vs `deliveryValue` | P2 | **fait** `stopBonus` ; reste niveau live vs snapshot colis |
| N21–N24, N26, N29–N32 | (fermés passes 5–10) | — | **faits** |
| N25 | `MAX_BOATS_PER_PLAYER` 6 vs 3 | P3 | ouvert |
| N27 | Embargo land trade | P2 | **doc** maritime-only |
| N28 | `RequestSnapshot` mort client | P2 | ouvert (serveur rate-limite ; client n’envoie jamais) |
| N33 | `BOAT_LANDING_BONUS` mort | P2 | ouvert |
| N34–N108 | (voir rapport #121) | — | **faits** |
| N109 | `BuildingModels.animate` câble `Vector3` 60 Hz | P3 | **fait** cette passe (nombres + `CFrame.new`, recette visual V60) |
| N110 | `applyRouteProgress` lift `Vector3` chantier | P3 | **fait** cette passe (lift cuit à la pose, recette visual V61) |
| N111 | `applyRouteProgress` arithmétique Vector3 60 Hz | P3 | **nouveau** (nombres ox/dx, recette visual V62 ouverte sur `3e1a`) |
| N112 | `stepRebuilds` `table.remove(dirtyQueue, 1)` O(n) | P3 | **nouveau** (curseur + truncate, pas de recette visual) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 `NIGHTLY_REPORT.md` historique.

---

## 6. Drift Config → `ChantierB.apply` (extrait)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | formule custom |
| `MAX_TILES_PER_TICK` | 400 | 56 | **non** (`guard<80`) |
| `DEFENSE_RADIUS` | 6 | 30 | index bunkers (N42), plus d’écritures buffer (N45) |
| `BOAT_TROOP_RATIO` | 0.2 | 0.2 | oui |
| `RETREAT_LOSS` | 0.25 | 0.25 | oui |
| `SAM_INTERCEPT_CHANCE` | **1.0** | 1.0 | oui (N26 clos) |
| `SAM_RANGE` | 34 | 70 | oui |
| `SAM_COOLDOWN` | 90 | 75 | oui |
| `SILO_COOLDOWN` | 90 | **90** (apply ne le touche pas) | oui (`Nukes.launch` + `stepCooldowns`) |
| `TRUCK_GOLD_BASE` | 10 | 14 | oui |
| `TRAIN_STOP_BONUS` | **0.12** | 0.12 | Trade + HUD (N20) |
| `BOAT_LANDING_BONUS` | 1.35 | 1.35 | **non** (N33) |
| `MAX_BOATS_PER_PLAYER` | 6 | 6 | oui (N25) |
| `PREPARATION_DURATION` | 0 | 0 | forcé true |
| `ALLIANCE_DURATION` | 3000 | 3000 | oui (`areAllied` + `Diplomacy.step`) |
| `ALLOW_UNSEQUENCED_INTENTS` | **false** | n/a | oui (N41) |
| `TRADE_SHIP_INTERVAL` | 45 | n/a | oui (N63, pas 10 Hz) |
| `MAX_TRADE_SHIPS` | 24 | n/a | oui (early-out N63) |
| `WARSHIP_SHELL_RATE` | 20 | 20 | oui (N67) |
| `RAIL_RANGE` | 56 | n/a | oui (N84) |
| `COLLAPSE_MIN_TILES` | 100 | 100 | oui (N86 wrap, N88 scan) |
| `SPAWN_RADIUS` | 3 | n/a | oui (N93 banc `keep=8`, N94 strip, N55 isolation) |
| `CHUNK_REBUILDS_PER_FRAME` | 3 | n/a | oui (N102/N104/N106 leftover file N112) |
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde, N103 X/Z, N105 TRUCK_LIFT monde) |
| `ROUTE_BUILD_SPEED` | — | n/a | oui (N110 lift, leftover N111 arithmétique) |

---

## 7. Preuve tests

`./tests/run.sh` → **exit 0**.

Serveur :

```
seed 7 / 99991 / 31337 / 1234567 : 18 factions, invariants OK
factions : 18
intentions : sequence, idempotence, apply immediat, rate limit OK
stripBuf : rot sous quota, deux camps, tiles vs buffer (N93)
stripTerritory : table.clear in-place, voisin intact (N94)
allyBuf : bot sans pacte, next nil (N91)
validTiles : deux resolve CITY, tile identique (N90)
destroyBuf : leftover A→B, CITY B survit (N89)
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.73
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `construction du monde 3D` (N106 leftover `partCount` / Ground recyclé ; N107 deux `step(1/60)` → `#oceanRipples` stable, `rawequal` Part, CFrame X ou Z ≠ `base` ; N108 deux `step` → CFrame.Y couronne ≠ `base`) ; `pose et capture de chaque type de batiment` (N110 deux `stepInterpolation` pendant chantier → Parts Road/Shoulder/CenterMark `rawequal`, CFrame.Y asphalt ≠ shoulder ; N105 dispatch → camion parenté, interpolation, arrivée `Parent = nil` + pulse) ; `modeles procéduraux` (N109 `Building.create(PORT)` + deux `animate` → `rawequal` Part câble, CFrame.Y ≠ `RestCFrame.Y` ; `animate(FACTORY)` 0 câble sans erreur) ; `navires, missiles et interpolation` (N98 extra `rawequal`, N101 `targetX`, N103 lerp `currentX`/`currentY` sous lookAt unique, navire `extra == nil`, `retreatTinted` conservé) ; `camera strategique` inchangé. `livraison : le gain s'affiche sur la gare` inchangé. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `init.client.luau` **non** touché. `WorldRenderer.luau` **non** touché. `PlacementPreview.luau` **non** touché. `UnitModels.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass40.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N109/N110 sont des hoists numériques client vérifiés par le banc headless.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N109 n’ajoute **pas** de require (nombres locaux dans `BuildingModels.animate`). N110 n’ajoute **pas** de require (`layer.origin` local dans Overlay). N111 restera dans `Overlay.applyRouteProgress`. N112 restera dans `WorldRenderer.stepRebuilds`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N109 : Y câble en nombres depuis `RestCFrame`, **pas** `Vector3.new`. `CFrame.new(x,y,z)` pose l’identité — le câble `block()` est déjà identité à `create`, donc équivalent à `rest + offset`. Ne pas convertir Radar / Flag / Boom. Recette visual V60 déjà sur `a0d3` — porter, ne pas merger. Factory sans câble : la branche n’alloue rien.

Piège N110 : cuire `layer.lift` dans `layer.origin` à `buildFactoryRoute`, pas 60 Hz. LookAt **conservé**. `part.Size` = API. Recette visual V61 déjà sur `3e1a` — porter, ne pas merger. `segment.origin` peut rester (construction). Ne pas changer `ROUTE_BUILD_SPEED`.

Piège N111 (à venir) : interpoler `ox+dx*t` en nombres. Ne pas « fermer » `CFrame.lookAt(Vector3, Vector3)` (API). Recette visual V62 ouverte sur `3e1a` — porter, ne pas merger.

Piège N112 (à venir) : curseur `dirtyHead`, truncate quand la file est vide. Ne pas `table.remove(1)`. Ne pas casser `markDirty` / `self.dirty[chunk]`. Recycle Parts N106 **inchangé**.
