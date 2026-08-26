# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 39)

Déclencheur : ouverture de la **PR #118** (`cursor/analyse-nocturne-du-codebase-de1a`) — Overlay camion, recycle Parts, specs N107–N108.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-04b6`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#118.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. `WorldRenderer.step` pose un `CFrame.new` numérique par glint océan (N107) **et** par couronne (N108). Overlay camion (N105) et recycle Ground/Border par chunk (N106) restent.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #118 (passe 38) : claims vérifiés.** Overlay camion lerp/lookAt (N105) ; `rebuildChunk` recycle Ground/Border par chunk (N106). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #118 a documenté (N107, N108)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #118

| Claim #118 | Réalité à l’ouverture |
|---|---|
| Overlay camion lerp/lookAt (N105) | Oui. X/Y/Z en nombres (`path[i].Y + TRUCK_LIFT`), un `CFrame.lookAt` par camion. Pièces non-roue sans `CFrame.new()` identité. Roues : `CFrame.Angles` conservé. Recette visual V57, pas merger `b677`. |
| `rebuildChunk` recycle Parts (N106) | Oui. Pools `chunkGround`/`chunkBorder` **par chunk**. Leftover `Parent = nil`. `partCount` = visibles. `meshKeyAt` (N104) et loi greedy inchangés. Recette N85. |
| Specs N107–N108 | **Corrigés ici.** N107 = houle X/Z nombres + un `CFrame.new` (recette visual V58 déjà sur `5913` — **porté, pas mergé**). N108 = feuillage Y nombres **sans** `CFrame.Angles` (recette visual V59 déjà sur `6cec` — **porté, pas mergé**). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #116 (13ca), feel jusqu’à #118, visuelles #39/…/#115 (`5913` houle V58) / #117 (`6cec` feuillage V59). **#118 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#116) reste distincte. Ne pas merger visual `6cec` / `5913` / `b677` ni hardening `13ca` / `fb8c` sans rebase.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N107–N108 du rapport #118.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `WorldRenderer.step` houle `Vector3` 60 Hz (N107) | `WorldRenderer.luau` (`step` boucle `oceanRipples` seulement), `tests/client.luau` (asserts dans le check construction existant) | Leftover N105. Lire `base.X/.Y/.Z`, poser `CFrame.new(base.X + wave * 0.45, base.Y, base.Z + cos * 0.2)`. Plus de `Vector3.new` 60 Hz. Transparency inchangée (`0.73 + wave * 0.09`). `buildOcean` **inchangé**. Feuillage **inchangé** au moment de N107 (N108 juste après). Camion / unités **inchangés** (N105/N103). Recycle Parts **inchangé** (N106). Recette visual V58, **pas** merger `5913`. Cosmétique (pose). 0 glint → zéro alloc. |
| `WorldRenderer.step` feuillage `CFrame.Angles` 60 Hz (N108) | `WorldRenderer.luau` (`step` boucle `animatedFoliage` seulement), `tests/client.luau` (asserts dans le même check construction) | Leftover N107. Lire `leaf.base.X/.Y/.Z`, poser `CFrame.new(bx, by + sin * 0.018, bz)` **sans** `CFrame.Angles`. Amplitude 0.018 conservée en translation Y (Ball : tilt ≈ invisible). Houle **inchangée** (N107). Camion / unités **inchangés** (N105/N103). Recycle Parts **inchangé** (N106). Recette visual V59, **pas** merger `6cec`. Cosmétique (pose). 0 couronne → zéro alloc. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), câble PORT `Vector3` 60 Hz (**N109**), `applyRouteProgress` lift chantier (**N110**), `table.remove(dirtyQueue, 1)` O(n). `PlacementPreview.resolve` ctx déjà **N92**. `self.ranked` inner déjà **N97**. Overlay `trackUnit` extra déjà **N98**. Hover déjà **N99**. `rankByTiles` déjà **N100**. `targetX` déjà **N101**. `BORDER_PASSES` déjà **N102**. lookAt unités déjà **N103**. `meshKeyAt` déjà **N104**. Camion déjà **N105**. Parts Ground déjà **N106**. `else {}` overlay-nil hors passe.

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
- Overlay `stepInterpolation` X/Z monde + un `lookAt` unités (**N103**) **et** camion (**N105**). `rebuildChunk` hisse `meshKeyAt` (**N104**) et recycle Ground/Border par chunk (**N106**). Houle océan (**N107**) et feuillage (**N108**) = nombres + un `CFrame.new`. Câble PORT `Vector3` encore 60 Hz (**N109**). `applyRouteProgress` lift encore 60 Hz chantier (**N110**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N109–N110)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N108 = faits. N22 = **N67 fait**. N27 = doc only. **V58 / N107** fermés ici (portés, pas mergés). **V59 / N108** fermés ici (portés, pas mergés). **V60** livré visuel `a0d3` (passe 43, PR #120) — leftover feel = **N109** (porter, ne pas merger). **V61** ouvert visuel `a0d3` — leftover feel = **N110**.

---

### ISSUE-N109 — `BuildingModels.animate` câble `Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client 60 Hz. Leftover explicite de N108 (feuillage) / N107 (houle). Distinct de N108 (couronnes déjà) et de N105 (camion). Recette visual V60 déjà sur `a0d3` (passe 43, PR #120) — **porter, ne pas merger**. Ne pas toucher WorldRenderer (N103–N108) ni Overlay (N105).

**Problème :** N108 ferme `leaf.base * CFrame.Angles` **sur les couronnes**. Reste, **par PORT animé, à chaque frame** dans `BuildingModels.animate` : `child.CFrame = rest + Vector3.new(0, math.sin(time * 0.8) * 0.35, 0)` pour `PortCraneCable`. `rest` est déjà un CFrame (`RestCFrame` posé à la construction, pas 60 Hz). Distinct de N108 (feuillage), de N107 (houle), de N105 (camion), des allocs explosion / wake / splash (événement) et de `applyRouteProgress` (chantier de voie, 0.35–3 s). Radar / `CapitalFlag` / `PortCraneBoom` : `CFrame.Angles` **rotation réelle** — ne pas convertir en translation.

**Pourquoi 20K CCU :** leftover N108. 8 clients × 60 Hz × N ports × 1 `Vector3.new` + 1 add CFrame. Pas d’autorité (pose cosmétique). Changer `RestCFrame` sans adapter `animate` casserait l’ancre. 0 câble → zéro alloc (les autres branches `animate` restent).

**Worker :**

1. Dans `BuildingModels.animate` seulement, branche `PortCraneCable` : lire `rest.X/.Y/.Z` en nombres, poser `CFrame.new(rx, ry + math.sin(time * 0.8) * 0.35, rz)` **sans** `Vector3.new`. Amplitude 0.35 conservée. Radar / flag / boom `CFrame.Angles` **inchangés**. Transparency CityWindows / beacons / FactoryOutput / SiloWarning **inchangées**. Feuillage / houle / camion / unités **inchangés** (N108/N107/N105/N103 déjà). Extra missile **inchangé** (N98). `targetX` **inchangé** (N101).
2. Ne **pas** éditer `WorldRenderer.luau` / `Overlay.luau` / `UnitModels.luau` / `HUD.luau` / `WorldSpace.luau`. Ne pas recycler explosion / wake / splash (événement). Ne pas changer la pose initiale du câble (`RestCFrame`). Après N108. Recette visual V60 déjà sur `a0d3` — porter les **nombres sans Vector3**, pas merger visual.
3. Ne pas porter Overlay camion (N105 déjà) ni houle (N107 déjà) ni feuillage (N108 déjà) ni recycle Parts (N106 déjà). Ne pas toucher `applyRouteProgress` (leftover N110, chantier). Ne pas convertir Radar / Flag / Boom (rotation visible).
4. Test : bancs client « pose et capture de chaque type de batiment » **et** « modeles procéduraux : le palier change la silhouette » **doivent rester verts**. Leftover N107/N108 (houle + feuillage : deux `step(1/60)`, Part stable, CFrame ≠ base) **doit rester vert**. Créer un PORT, `BuildingModels.animate(model, t, 1/60)` deux fois → CFrame Y du câble distinct du `RestCFrame` sans recréer la Part. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
5. Fichiers : `BuildingModels.luau` (`animate` branche `PortCraneCable` seulement). `tests/client.luau` **seulement si** un assert dans le check pose/capture ou modèles procéduraux existant (ne **pas** ajouter un 36e). `WorldRenderer.luau` **non**. `Overlay.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur ni visual `a0d3`.

**Contraintes :** pas de RemoteFunction. Recette visual V60 (nombres, pas `Vector3.new`, déjà sur `a0d3`). **N109 feel ≠ N108 (feuillage) ≠ N107 (houle) ≠ N105 (camion) ≠ visual V60 (livré sur `a0d3`, ne pas merger).** Non réentrant. Ne pas fusionner avec N110 dans le même worker.

---

### ISSUE-N110 — `applyRouteProgress` lift `Vector3.new` chantier (feel)

**Priorité :** P3 alloc client chantier. Leftover explicite de N109 (câble PORT). Distinct de N109 (câble déjà) et de N105 (camion **livraison** — `TRUCK_LIFT` déjà cuit). Recette visual V61 **ouverte** sur `a0d3` (passe 43, PR #120) — **porter la recette, ne pas merger**. Ne pas toucher BuildingModels (N109) ni WorldRenderer (N107/N108).

**Problème :** N109 ferme `rest + Vector3.new` **sur le câble PORT**. Reste, **par calque de voie en chantier, à chaque frame** dans `Overlay.applyRouteProgress` : `part.CFrame = CFrame.lookAt(centre, centre + segment.direction) + Vector3.new(0, layer.lift, 0)`. `layer.lift` est constant (0 / `0.08 * k` / `0.18 * k`) posé une fois dans `buildFactoryRoute`. Distinct de N109 (câble), de N105 (camion livraison), de `part.Size = Vector3.new(width, thickness, shown)` (API Roblox, inévitable) et de Radar / Flag / Boom `CFrame.Angles` (rotation réelle). Recette N105/V57 : cuire le décalage constant à la construction, pas 60 Hz.

**Pourquoi 20K CCU :** leftover N109. 8 clients × 60 Hz × N voies en chantier (0.35–3 s, pas tout le match) × 3 calques × 1 `Vector3.new` + 1 add CFrame. Pas d’autorité (pose cosmétique). Changer `origin` sans adapter `applyRouteProgress` casserait l’assiette (chaussée / bande). 0 chantier (`construction == nil`) → zéro alloc (déjà `continue`).

**Worker :**

1. Dans `buildFactoryRoute` seulement, cuire `lift` dans un `origin` **par calque** (ex. `layer.origin = origin + Vector3.new(0, lift, 0)` à la construction, une fois). Dans `applyRouteProgress` : `centre = layer.origin + direction * (visible - shown / 2)` puis `CFrame.lookAt(centre, centre + direction)` **sans** `+ Vector3.new(0, lift, 0)`. LookAt **conservé** (sinon la chaussée perd son orientation). `part.Size = Vector3.new(...)` **inchangé**. Radar / flag / boom / câble **inchangés** (N109 déjà). Camion livraison / houle / feuillage / unités **inchangés** (N105/N107/N108/N103 déjà). Extra missile **inchangé** (N98). `targetX` **inchangé** (N101).
2. Ne **pas** éditer `BuildingModels.luau` / `WorldRenderer.luau` / `UnitModels.luau` / `HUD.luau` / `WorldSpace.luau`. Ne pas recycler explosion / wake / splash (événement). Ne pas changer `ROUTE_BUILD_SPEED` / durée 0.35–3 s. Après N109. Recette visual V61 **ouverte** sur `a0d3` — porter le **lift cuit**, pas merger visual.
3. Ne pas porter Overlay camion livraison (N105 déjà) ni houle (N107 déjà) ni feuillage (N108 déjà) ni câble (N109 déjà). Ne pas convertir Radar / Flag / Boom (rotation visible). Ne pas cuire `Size` (API).
4. Test : banc client « pose et capture de chaque type de batiment » **doit rester vert** : `pavedLength` croît, chantier nil après 30 × 0.2 s, leftover N105 (dispatch → Parent + pulse) **et** leftover N109 (câble Y ≠ rest, Part stable) **et** leftover N107/N108 (construction houle/feuillage) **doivent rester verts**. Deux `stepInterpolation` pendant chantier → Parts Road/Shoulder/CenterMark stables (`rawequal`), CFrame.Y asphalt ≠ shoulder (lift cuit). Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
5. Fichiers : `Overlay.luau` (`buildFactoryRoute` calques + `applyRouteProgress` seulement). `tests/client.luau` **seulement si** un assert dans le check pose/capture existant (ne **pas** ajouter un 36e). `BuildingModels.luau` **non**. `WorldRenderer.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur ni visual `a0d3`.

**Contraintes :** pas de RemoteFunction. Recette visual V61 (lift cuit à la pose, ouverte sur `a0d3`). **N110 feel ≠ N109 (câble PORT) ≠ N105 (camion livraison) ≠ visual V61 (spec ouverte, ne pas merger).** Non réentrant. Ne pas fusionner avec N109 dans le même worker si N109 est déjà mergé ici. `part.Size = Vector3.new` = API, ne pas « fermer ». `UnitModels.place` Size flamme = leftover séparé (API Size). `CFrame.lookAt(Vector3.new, Vector3.new)` unités/camion = leftover API Roblox.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; records stats → **N76 fait** ; `eraProgress` → **N77 fait** ; bateaux → **N70 fait** ; missiles → **N71 fait** ; owner indices → **N72 fait** ; bâtiments → **N73 fait** ; HUD fronts → **N74 fait** ; viewFor → **N78 fait** ; listes effets client → **N95 fait** ; ranked → **N97 fait** ; units extra → **N98 fait** ; hover → **N99 fait** ; sort → **N100 fait** ; targetX → **N101 fait** ; borders → **N102 fait** ; lookAt → **N103 fait** ; meshKeyAt → **N104 fait** ; camion → **N105 fait** ; Parts → **N106 fait** ; houle → **N107 fait** ; feuillage → **N108 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; lookAt → **N103 fait** ; meshKeyAt → **N104 fait** ; camion → **N105 fait** ; Parts → **N106 fait** ; houle → **N107 fait** ; feuillage → **N108 fait**) |
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
| N34–N106 | (voir rapport #118) | — | **faits** |
| N107 | `WorldRenderer.step` houle `Vector3` 60 Hz | P3 | **fait** cette passe (nombres + `CFrame.new`, recette visual V58) |
| N108 | `WorldRenderer.step` feuillage `CFrame.Angles` 60 Hz | P3 | **fait** cette passe (nombres sans Angles, recette visual V59) |
| N109 | `BuildingModels.animate` câble `Vector3` 60 Hz | P3 | **nouveau** (nombres sans Vector3, recette visual V60 déjà sur `a0d3`) |
| N110 | `applyRouteProgress` lift `Vector3` chantier | P3 | **nouveau** (lift cuit à la pose, recette visual V61 ouverte sur `a0d3`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 `NIGHTLY_REPORT.md` historique.

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
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.77
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `construction du monde 3D` (N106 leftover `partCount` / Ground recyclé ; N107 deux `step(1/60)` → `#oceanRipples` stable, `rawequal` Part, CFrame X ou Z ≠ `base`, Transparency dans `[0.64, 0.82]`, 0 glint sans erreur ; N108 deux `step` → CFrame.Y couronne ≠ `base`, 0 couronne sans erreur) ; `pose et capture de chaque type de batiment` (N105 dispatch → camion parenté, interpolation, arrivée `Parent = nil` + pulse) ; `navires, missiles et interpolation` (N98 extra `rawequal`, N101 `targetX`, N103 lerp `currentX`/`currentY` sous lookAt unique, navire `extra == nil`, `retreatTinted` conservé) ; `camera strategique` inchangé. `livraison : le gain s'affiche sur la gare` inchangé. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `init.client.luau` **non** touché. `Overlay.luau` **non** touché. `PlacementPreview.luau` **non** touché. `UnitModels.luau` **non** touché. `BuildingModels.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass39.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N107/N108 sont des hoists numériques client vérifiés par le banc headless.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N107/N108 n’ajoutent **pas** de require (nombres locaux dans `WorldRenderer.step`). N109 restera dans `BuildingModels.animate`. N110 restera dans `Overlay.buildFactoryRoute` / `applyRouteProgress`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N105 : lerp camion X/Y/Z en nombres, `TRUCK_LIFT` constante, un `lookAt`, pièces non-roue **sans** `CFrame.new()` identité. Ne pas changer `buildFactoryRoute` (path Vector3 à la pose). Unités N103 inchangées. Recette visual V57 déjà sur `b677` — porter, ne pas merger. Une voie sans `delivery` ne doit rien allouer. Le pulse d’arrivée (événement) **conserve** `Vector3` / `CFrame.Angles`.

Piège N106 : recycler Ground/Border **par folder de chunk**, pas un pool global. Truncate leftover `Parent = nil` avant return. Réécrire Color/Size/CFrame. Ne pas Destroy le folder entier. Ne pas fusionner Ground et Border dans la même liste. `meshKeyAt` / `borderTerrain` **inchangés** (N104/N102). Non réentrant : synchrone, un chunk à la fois. Un leftover `Color` d’un chunk précédent fusionnerait deux nations. `partCount` compte les visibles, pas `#GetChildren()`. Océan / SeaFloor / glints / foliage **hors N106** (construits une fois). `table.remove(dirtyQueue, 1)` O(n) hors passe. Collision serveur hors scope.

Piège N107 : X/Z glint en nombres depuis `ripple.base`, un `CFrame.new`. Ne pas changer `buildOcean`. Feuillage N108 inchangé au moment du port. Recette visual V58 déjà sur `5913` — porter, ne pas merger. La rotation Y des glints (`CFrame.Angles` à `buildOcean`) n’est **pas** rejouée dans `step` : `CFrame.new(x,y,z)` pose l’identité — acceptable, vue stratégique, bandes minces.

Piège N108 : translation Y nombres, **pas** `CFrame.Angles`. Ne pas changer `buildDecorations`. Houle N107 inchangée. Recette visual V59 déjà sur `6cec` — porter, ne pas merger.

Piège N109 (à venir) : Y câble en nombres depuis `RestCFrame`, **pas** `Vector3.new`. Ne pas convertir Radar / Flag / Boom. Recette visual V60 déjà sur `a0d3` — porter, ne pas merger.

Piège N110 (à venir) : cuire `layer.lift` dans `layer.origin` à `buildFactoryRoute`, pas 60 Hz. LookAt **conservé**. `part.Size` = API. Recette visual V61 ouverte sur `a0d3` — porter, ne pas merger.
