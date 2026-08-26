# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 38)

Déclencheur : ouverture de la **PR #114** (`cursor/analyse-nocturne-du-codebase-5bbf`) — Overlay.lookAt, meshKeyAt, specs N105–N106.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-de1a`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#115.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. `stepInterpolation` pose un `CFrame.lookAt` unique par unité (N103) **et** par camion en livraison (N105). `rebuildChunk` recycle les Parts Ground/Border **par folder de chunk** (N106) ; `meshKeyAt` reste hissé (N104).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #114 (passe 37) : claims vérifiés.** Overlay lookAt unités (N103) ; `meshKeyAt` + upvalues dédiées (N104). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #114 a documenté (N105, N106)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #114

| Claim #114 | Réalité à l’ouverture |
|---|---|
| Overlay lookAt unités (N103) | Oui. X/Z monde en nombres, un `CFrame.lookAt` par unité. Immobile = regard −Z. Extra missile N98, `targetX` N101, `retreatTinted` N56 conservés. Recette visual V56, pas merger `1dbb`. |
| `meshKeyAt` (N104) | Oui. Upvalues `meshTerrain`/`meshOwner` dédiées, distinctes de `borderTerrain` N102. Même loi que `chunkKeyAt`. Recette N85. Parts Ground/Border encore Destroy+new. |
| Specs N105–N106 | **Corrigés ici.** N105 = camion lerp X/Y/Z + un `lookAt` (recette visual V57 déjà sur `b677` — **porté, pas mergé**). N106 = recycle Ground/Border **par chunk**, leftover `Parent = nil`. |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #112 (2ea8), feel jusqu’à #114, visuelles #39/…/#113 (`b677` camion V57) / #115 (`5913` houle V58). **#114 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#112) reste distincte. Ne pas merger visual `5913` / `b677` / `1dbb` ni hardening `2ea8` / `a0f9` sans rebase.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N105–N106 du rapport #114.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Overlay camion `Vector3`/`CFrame` 60 Hz (N105) | `Overlay.luau` (`stepInterpolation` boucle `route.delivery` seulement), `tests/client.luau` (asserts dans le check pose/capture existant) | Leftover N103. Lerp X/Y/Z en nombres (`path[i].Y + TRUCK_LIFT`), un `CFrame.lookAt` par camion. Pièces non-roue **sans** `CFrame.new()` identité. Roues : `CFrame.Angles` conservé. Unités **inchangées** (N103). Extra missile **inchangé** (N98). `targetX` **inchangé** (N101). `retreatTinted` N56 **conservé**. Recette visual V57, **pas** merger `b677`. Cosmétique (pose). Une voie sans `delivery` ne rentre pas dans la boucle. |
| `rebuildChunk` recycle Parts Ground/Border (N106) | `WorldRenderer.luau` (`rebuildChunk` / `emit` / `buildChunkBorders` seulement), `tests/client.luau` (asserts dans construction + deltas existants) | Leftover N104. Plus de `Destroy()` du folder. Pools `chunkGround`/`chunkBorder` **par chunk** (pas un pool global). Réécrit Size/CFrame/Color. Leftover `Parent = nil` avant return. `partCount` = visibles, pas `#GetChildren()`. `meshKeyAt` **inchangé** (N104). Loi greedy **inchangée**. Recette N85. Cosmétique (géométrie). Collision serveur (541 blocs) **hors scope**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), houle océan `Vector3` 60 Hz (**N107**), feuillage `CFrame.Angles` 60 Hz (**N108**), `table.remove(dirtyQueue, 1)` O(n). `PlacementPreview.resolve` ctx déjà **N92**. `self.ranked` inner déjà **N97**. Overlay `trackUnit` extra déjà **N98**. Hover déjà **N99**. `rankByTiles` déjà **N100**. `targetX` déjà **N101**. `BORDER_PASSES` déjà **N102**. lookAt unités déjà **N103**. `meshKeyAt` déjà **N104**. `else {}` overlay-nil hors passe.

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
- Overlay `stepInterpolation` X/Z monde + un `lookAt` unités (**N103**) **et** camion (**N105**). `rebuildChunk` hisse `meshKeyAt` (**N104**) et recycle Ground/Border par chunk (**N106**). Houle océan `Vector3` encore 60 Hz (**N107**). Feuillage `CFrame.Angles` encore 60 Hz (**N108**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N107–N108)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N106 = faits. N22 = **N67 fait**. N27 = doc only. **V57 / N105** fermés ici (portés, pas mergés). **N106** n’a pas d’équivalent visuel encore. **V58** livré visuel `5913` (PR #115) — leftover feel = **N107** (porter, ne pas merger). **V59** livré visuel `6cec` (passe 42) — leftover feel = **N108** (porter, ne pas merger).

---

### ISSUE-N107 — `WorldRenderer.step` houle `Vector3` 60 Hz (feel)

**Priorité :** P3 alloc client 60 Hz. Leftover explicite de N105 (camion) / N103 (unités). Distinct de N105 (camion déjà) et de N106 (Parts Ground). Recette visual V58 déjà sur `5913` (passe 41, PR #115) — **porter, ne pas merger**. Ne pas toucher Overlay (N103/N105) ni `rebuildChunk` (N104/N106) ni le feuillage (N108).

**Problème :** N105 ferme camion `Vector3`/`CFrame.new()` identité **sur les livraisons**. Reste, **par glint océan, à chaque frame** : `ripple.base + Vector3.new(wave * 0.45, 0, math.cos(time + ripple.phase) * 0.2)`. `ripple.base` est déjà un CFrame (posé à `buildOcean`, pas 60 Hz). Distinct de N105 (camion), de N103 (unités), de N106 (Parts chunk) et des allocs explosion / wake / splash (événement).

**Pourquoi 20K CCU :** leftover N105. 8 clients × 60 Hz × N glints × 1 `Vector3.new` + 1 add CFrame. Pas d’autorité (pose cosmétique). Changer `ripple.base` sans adapter `step` casserait l’ancre. 0 glint → zéro alloc.

**Worker :**

1. Dans `WorldRenderer.step` seulement, boucle `oceanRipples` : lire `base.X` / `base.Y` / `base.Z` en nombres, poser `CFrame.new(base.X + wave * 0.45, base.Y, base.Z + math.cos(time + ripple.phase) * 0.2)`. Plus de `Vector3.new` 60 Hz. Transparency inchangée (`0.73 + wave * 0.09`). Feuillage **inchangé** (N108). Camion / unités **inchangés** (N105/N103). `rebuildChunk` **inchangé** (N106). Extra missile **inchangé** (N98). `targetX` **inchangé** (N101).
2. Ne **pas** éditer `Overlay.luau` / `UnitModels.luau` / `HUD.luau` / `WorldSpace.luau` / `init.client.luau`. Ne pas changer `buildOcean` (`ripple.base` posé une fois ; `CFrame.Angles` Y à la construction n’est **pas** rejoué dans `step` : `CFrame.new(x,y,z)` pose l’identité — acceptable, vue stratégique, bandes minces). Après N106. Recette visual V58 déjà sur `5913` — porter les **nombres + CFrame.new**, pas merger visual.
3. Ne pas porter Overlay camion (N105 déjà) ni recycle Parts (N106 déjà). Ne pas toucher `animatedFoliage` (N108).
4. Test : bancs client « construction du monde 3D » **et** « camera strategique » **doivent rester verts**. Leftover N106 (`partCount` / Ground recyclé) **doit rester vert**. Deux `world:step(1/60)` → `#oceanRipples` stable, `rawequal` du Part, CFrame X ou Z ≠ `base`, Transparency dans `[0.64, 0.82]`. 0 glint → `step` sans erreur. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
5. Fichiers : `WorldRenderer.luau` (`step` boucle `oceanRipples` seulement). `tests/client.luau` **seulement si** un assert dans le check construction existant (ne **pas** ajouter un 36e). `Overlay.luau` **non**. **Ne pas** éditer le serveur ni visual `5913`.

**Contraintes :** pas de RemoteFunction. Recette visual V58 (nombres, un `CFrame.new`, déjà sur `5913`). **N107 feel ≠ N105 (camion) ≠ N103 (unités lookAt) ≠ N106 (Parts Ground) ≠ N108 (feuillage) ≠ visual V58 (livré sur `5913`, ne pas merger).** Non réentrant. Ne pas fusionner avec N108 dans le même worker.

---

### ISSUE-N108 — `WorldRenderer.step` feuillage `CFrame.Angles` 60 Hz (feel)

**Priorité :** P3 alloc client 60 Hz. Leftover explicite de N107 (houle). Distinct de N107 (glints déjà) et de N105 (camion). Recette visual V59 déjà sur `6cec` (passe 42) — **porter, ne pas merger**. Ne pas toucher Overlay (N103/N105) ni `rebuildChunk` (N104/N106) ni la houle (N107).

**Problème :** N107 ferme `ripple.base + Vector3.new` **sur les glints océan**. Reste, **par couronne animée, à chaque frame** : `leaf.base * CFrame.Angles(math.sin(time * 1.2 + leaf.phase) * 0.018, 0, math.cos(time + leaf.phase) * 0.014)`. `leaf.base` est déjà un CFrame (posé à `buildDecorations`, pas 60 Hz). Les couronnes sont des `Ball` : le tilt ~1° est quasi invisible en vue stratégique. Distinct de N107 (houle), de N105 (camion), des allocs explosion / wake / splash (événement) et de `applyRouteProgress` (chantier de voie, 0.35–3 s).

**Pourquoi 20K CCU :** leftover N107. 8 clients × 60 Hz × N couronnes × 1 `CFrame.Angles` + 1 mul. Pas d’autorité (pose cosmétique). Changer `leaf.base` sans adapter `step` casserait l’ancre. 0 couronne → zéro alloc.

**Worker :**

1. Dans `WorldRenderer.step` seulement, boucle `animatedFoliage` : lire `leaf.base.X/.Y/.Z` en nombres, poser `CFrame.new(bx, by + math.sin(time * 1.2 + leaf.phase) * 0.018, bz)` **sans** `CFrame.Angles`. Amplitude 0.018 conservée en translation Y (Ball : tilt ≈ invisible). Houle / camion / unités **inchangés** (N107/N105/N103 déjà). Extra missile **inchangé** (N98). `targetX` **inchangé** (N101). `rebuildChunk` **inchangé** (N106).
2. Ne **pas** éditer `Overlay.luau` / `UnitModels.luau` / `HUD.luau` / `WorldSpace.luau`. Ne pas recycler explosion / wake / splash (événement). Ne pas changer `buildDecorations` (couronnes posées une fois). Après N107. Recette visual V59 déjà sur `6cec` — porter les **nombres sans Angles**, pas merger visual.
3. Ne pas porter Overlay camion (N105 déjà) ni houle (N107 déjà) ni recycle Parts (N106 déjà). Ne pas toucher `applyRouteProgress` (leftover séparé, chantier).
4. Test : bancs client « construction du monde 3D » **et** « camera strategique » **doivent rester verts**. Leftover N107 (houle : deux `step(1/60)`, Part stable, CFrame ≠ base) **doit rester vert**. `world:step(1/60)` deux fois → CFrame des couronnes distinct du `base` (Y a bougé) sans recréer les Parts. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
5. Fichiers : `WorldRenderer.luau` (`step` boucle `animatedFoliage` seulement). `tests/client.luau` **seulement si** un assert dans le check construction existant (ne **pas** ajouter un 36e). `Overlay.luau` **non**. **Ne pas** éditer le serveur ni visual `6cec`.

**Contraintes :** pas de RemoteFunction. Recette visual V59 (nombres, pas `CFrame.Angles`, déjà sur `6cec`). **N108 feel ≠ N107 (houle) ≠ N105 (camion) ≠ N103 (unités lookAt) ≠ N106 (Parts) ≠ visual V59 (livré sur `6cec`, ne pas merger).** Non réentrant. Ne pas fusionner avec N107 dans le même worker si N107 est déjà mergé ici. `BuildingModels.animate` / `UnitModels.place` Size flamme = leftovers séparés.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; records stats → **N76 fait** ; `eraProgress` → **N77 fait** ; bateaux → **N70 fait** ; missiles → **N71 fait** ; owner indices → **N72 fait** ; bâtiments → **N73 fait** ; HUD fronts → **N74 fait** ; viewFor → **N78 fait** ; listes effets client → **N95 fait** ; ranked → **N97 fait** ; units extra → **N98 fait** ; hover → **N99 fait** ; sort → **N100 fait** ; targetX → **N101 fait** ; borders → **N102 fait** ; lookAt → **N103 fait** ; meshKeyAt → **N104 fait** ; camion → **N105 fait** ; Parts → **N106 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; lookAt → **N103 fait** ; meshKeyAt → **N104 fait** ; camion → **N105 fait** ; Parts → **N106 fait**) |
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
| N34–N104 | (voir rapport #114) | — | **faits** |
| N105 | Overlay camion `Vector3`/`CFrame` 60 Hz | P3 | **fait** cette passe (nombres + un `lookAt`, recette visual V57) |
| N106 | `rebuildChunk` recycle Parts Ground/Border | P3 | **fait** cette passe (pool par chunk, pas global) |
| N107 | `WorldRenderer.step` houle `Vector3` 60 Hz | P3 | **nouveau** (nombres + `CFrame.new`, recette visual V58 déjà sur `5913`) |
| N108 | `WorldRenderer.step` feuillage `CFrame.Angles` 60 Hz | P3 | **nouveau** (nombres sans Angles, recette visual V59 déjà sur `6cec`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 `NIGHTLY_REPORT.md` historique.

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
| `CHUNK_REBUILDS_PER_FRAME` | 3 | n/a | oui (N102/N104/N106 leftover Parts) |
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde, N103 X/Z, N105 TRUCK_LIFT monde) |

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

Client : **35/35 OK** — dont `pose et capture de chaque type de batiment` (N105 dispatch → camion parenté, interpolation, arrivée `Parent = nil` + pulse) ; `navires, missiles et interpolation` (N98 extra `rawequal`, N101 `targetX`, N103 lerp `currentX`/`currentY` sous lookAt unique, navire `extra == nil`, `retreatTinted` conservé) ; `construction du monde 3D` / `deltas de terrain et conquetes classees` (N95 leftover truncate, N106 `partCount` = visibles, Ground `rawequal` après `rebuildChunk`, leftover `Parent = nil`). `livraison : le gain s'affiche sur la gare` inchangé. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `init.client.luau` **non** touché. `PlacementPreview.luau` **non** touché. `UnitModels.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass38.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N105/N106 sont des hoists / recyclages client vérifiés par le banc headless.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N105 n’ajoute **pas** de require (`TRUCK_LIFT` constante Overlay). N106 n’ajoute **pas** de require (pools sur `WorldRenderer`). N107/N108 resteront dans WorldRenderer.step.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N105 : lerp camion X/Y/Z en nombres, `TRUCK_LIFT` constante, un `lookAt`, pièces non-roue **sans** `CFrame.new()` identité. Ne pas changer `buildFactoryRoute` (path Vector3 à la pose). Unités N103 inchangées. Recette visual V57 déjà sur `b677` — porter, ne pas merger. Une voie sans `delivery` ne doit rien allouer. Le pulse d’arrivée (événement) **conserve** `Vector3` / `CFrame.Angles`.

Piège N106 : recycler Ground/Border **par folder de chunk**, pas un pool global. Truncate leftover `Parent = nil` avant return. Réécrire Color/Size/CFrame. Ne pas Destroy le folder entier. Ne pas fusionner Ground et Border dans la même liste. `meshKeyAt` / `borderTerrain` **inchangés** (N104/N102). Non réentrant : synchrone, un chunk à la fois. Un leftover `Color` d’un chunk précédent fusionnerait deux nations. `partCount` compte les visibles, pas `#GetChildren()`. Océan / SeaFloor / glints / foliage **hors passe** (construits une fois). `table.remove(dirtyQueue, 1)` O(n) hors passe. Collision serveur hors scope.

Piège N107 (à venir) : X/Z glint en nombres depuis `ripple.base`, un `CFrame.new`. Ne pas changer `buildOcean`. Feuillage N108 inchangé. Recette visual V58 déjà sur `5913` — porter, ne pas merger. La rotation Y des glints (`CFrame.Angles` à `buildOcean`) n’est pas rejouée dans `step`.

Piège N108 (à venir) : translation Y nombres, **pas** `CFrame.Angles`. Ne pas changer `buildDecorations`. Houle N107 inchangée. Recette visual V59 déjà sur `6cec` — porter, ne pas merger.
