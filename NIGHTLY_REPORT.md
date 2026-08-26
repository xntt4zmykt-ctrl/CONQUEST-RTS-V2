# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 42)

Déclencheur : ouverture de la **PR #128** (`cursor/analyse-nocturne-du-codebase-04e7`) — `applyRouteProgress` nombres, `dirtyHead`, specs N113–N114.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-846c`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#128.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. `applyRouteProgress` compose `CFrame.new(cx, cy, cz) * segment.rot` (N113). `stepRebuilds` compacte le préfixe consommé de `dirtyQueue` au seuil 32 (N114). Nombres (N111), `dirtyHead` (N112), câble (N109), lift (N110), houle (N107), feuillage (N108), camion lerp (N105) et recycle Ground/Border (N106) restent.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #128 (passe 41) : claims vérifiés.** Interpolation nombres `ox/dx` (N111) ; curseur `dirtyHead` (N112). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #128 a documenté (N113, N114)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #128

| Claim #128 | Réalité à l’ouverture |
|---|---|
| `applyRouteProgress` nombres (N111) | Oui. `layer.ox/oy/oz` + `segment.dx/dy/dz` cuits à la pose. Hot path : `cx = ox + dx*t`. LookAt encore 60 Hz (leftover N113). Recette visual V62, pas merger `65f4`. |
| `stepRebuilds` `dirtyHead` (N112) | Oui. Curseur + `table.clear` quand la file est consommée. Plus de `table.remove(1)`. Préfixe mort tant que la vague n’est pas rattrapée (leftover N114). |
| Specs N113–N114 | **Corrigés ici.** N113 = `segment.rot` cuit, `CFrame.new * rot` (recette visual V63 déjà fermée sur `f5e9` — **porté, pas mergé**). N114 = compact in-place seuil 32, pas de `table.remove`. |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #127 (`46a1` / `e488`), feel jusqu’à #128, visuelles #39/…/#126 (`f5e9` V63 **fermé**) / `3062` (V64 camion `segRot` **fermé** + leftover V65 unités lookAt). **#128 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#127) reste distincte. Ne pas merger visual `3062` / `f5e9` / `65f4` ni hardening `e488` / `46a1` sans rebase.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N113–N114 du rapport #128.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `applyRouteProgress` lookAt deux Vector3 60 Hz (N113) | `Overlay.luau` (`buildFactoryRoute` calques + `applyRouteProgress`), `tests/client.luau` (asserts dans le check pose/capture existant) | Leftover N111. Cuire `segment.rot = CFrame.lookAt(Vector3.zero, direction)` à la pose. Hot path : `CFrame.new(cx, cy, cz) * segment.rot`. Plus de `CFrame.lookAt` 60 Hz. `part.Size` = API. Nombres / lift / câble / camion / houle / feuillage / unités **inchangés** (N111/N110/N109/N105/N107/N108/N103). Recette visual V63 déjà sur `f5e9`, **pas** merger. Cosmétique (pose). 0 chantier → zéro alloc. |
| `dirtyQueue` préfixe consommé non compacté (N114) | `WorldRenderer.luau` (`stepRebuilds` + `DIRTY_COMPACT_HEAD=32`), `tests/client.luau` (asserts dans construction + deltas existants) | Leftover N112. Après la boucle budget, si `dirtyHead > 32` et file non vide : copie in-place des restants vers l’index 1, nil du surplus, `dirtyHead = 1`. Plus de `table.remove`. Drain complet N112 **inchangé**. Recycle Ground/Border **inchangé** (N106). Pas d’autorité (file client). 0 dirty → zéro travail. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), lookAt camion deux Vector3 (**N115**), lookAt unités deux Vector3 (**N116**). `PlacementPreview.resolve` ctx déjà **N92**. `self.ranked` inner déjà **N97**. Overlay `trackUnit` extra déjà **N98**. Hover déjà **N99**. `rankByTiles` déjà **N100**. `targetX` déjà **N101**. `BORDER_PASSES` déjà **N102**. lookAt unités déjà **N103**. `meshKeyAt` déjà **N104**. Camion lerp déjà **N105**. Parts Ground déjà **N106**. Houle déjà **N107**. Feuillage déjà **N108**. Câble déjà **N109**. Lift déjà **N110**. Nombres déjà **N111**. `dirtyHead` déjà **N112**. `else {}` overlay-nil hors passe.

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
- Overlay `stepInterpolation` X/Z monde + un `lookAt` unités (**N103**) **et** camion lerp (**N105**). `rebuildChunk` hisse `meshKeyAt` (**N104**) et recycle Ground/Border par chunk (**N106**). Houle océan (**N107**) et feuillage (**N108**) = nombres + un `CFrame.new`. Câble PORT (**N109**) = nombres + un `CFrame.new`. Lift voie (**N110**) cuit dans `layer.origin`. Arithmétique `origin + direction * t` **fermée** (**N111**). `table.remove(dirtyQueue, 1)` **fermé** (**N112**). LookAt chantier **fermé** (**N113**). Compact préfixe `dirtyQueue` **fermé** (**N114**). LookAt camion deux Vector3 encore 60 Hz (**N115**). LookAt unités deux Vector3 encore 60 Hz (**N116**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N115–N116)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N114 = faits. N22 = **N67 fait**. N27 = doc only. **V63 / N113** fermés ici (portés, pas mergés ; V63 déjà livré visuel `f5e9`). **N114** fermé ici (pas d’équivalent visuel). **V64** fermé visuel `3062` — leftover feel = **N115** (porter `route.segRot`, ne pas merger). **V65** ouvert visuel — leftover feel = **N116**.

---

### ISSUE-N115 — Overlay camion lookAt deux Vector3 60 Hz (feel)

**Priorité :** P3 alloc client livraison. Leftover explicite de N113 (chantier `segment.rot` déjà). Distinct de N113 (voie en pose), de N105 (camion **lerp** déjà en nombres) et de N103 (unités lookAt — le look **change** chaque frame tant que `mag > 0.01`, pas la même recette). Recette visual V64 **fermée** sur `3062` (passe 47 visual, PR visual #126+) — **porter la recette, ne pas merger**. Ne pas toucher WorldRenderer (N114/N112/N106) ni BuildingModels (N109).

**Problème :** N113 ferme le lookAt chantier. Reste, **par camion en livraison, à chaque frame** : `CFrame.lookAt(Vector3.new(px, py, pz), Vector3.new(px+dx, py+dy, pz+dz))`. Deux allocs Vector3 **en plus** du `CFrame.Angles` roues (rotation réelle, inévitable). La direction d’un segment de `route.path` est constante (grille HV, assertée au banc, Y lift identique aux deux bouts). Distinct de N113 (chantier `segment.rot`), de N105 (lerp nombres camion), de N103 (unités). Recette : cuire `route.segRot[i] = CFrame.lookAt(Vector3.zero, path[i+1] - path[i])` à `buildFactoryRoute` (après le `path`), composer `CFrame.new(px, py, pz) * route.segRot[segmentIndex]`.

**Pourquoi 20K CCU :** leftover N113. 8 clients × 60 Hz × camions en livraison (pas tout le match) × 2 Vector3 lookAt. Pas d’autorité (pose cosmétique). Changer `path` sans adapter `segRot` casserait l’assiette au virage. 0 livraison (`delivery == nil`) → zéro alloc (déjà `continue`).

**Worker :**

1. Dans `buildFactoryRoute` seulement, **après** le `path` : poser `segRot` tableau, `segRot[i] = CFrame.lookAt(Vector3.zero, path[i+1] - path[i])` pour `i = 1 .. #path-1`. Stocker `segRot` sur le record `self.routes[...]`. Dans la boucle `route.delivery` de `stepInterpolation` : garder lerp `px/py/pz` (N105) ; poser `frame = CFrame.new(px, py, pz) * route.segRot[segmentIndex]`. Plus de `CFrame.lookAt` 60 Hz camion. `CFrame.Angles` roues **inchangé**. `piece.offset` **inchangé**. Construction initiale `truckPart` lookAt `from→to` **peut rester** (une fois, pas 60 Hz). Chantier `segment.rot` **inchangé** (N113). Nombres / lift / câble / houle / feuillage / unités **inchangés** (N111/N110/N109/N107/N108/N103). Extra missile **inchangé** (N98). `targetX` **inchangé** (N101). File dirtyHead / compact **inchangés** (N112/N114).
2. Ne **pas** éditer `BuildingModels.luau` / `WorldRenderer.luau` / `UnitModels.luau` / `HUD.luau` / `WorldSpace.luau`. Ne pas recycler explosion / wake / splash (événement). Ne pas changer la durée de livraison (`trajetTicks`). Après N113. Recette visual V64 **fermée** sur `3062` — porter `segRot`, pas merger visual.
3. Ne pas porter Overlay chantier (N113 déjà) ni houle (N107) ni feuillage (N108) ni câble (N109) ni lift (N110) ni lerp nombres (N111 déjà) ni dirtyHead (N112 déjà) ni compact (N114 déjà). Ne pas convertir Radar / Flag / Boom (rotation visible). Ne pas « fermer » `Size` chantier (API). Ne pas « fermer » le lookAt unités (N103 / leftover N116 — look change chaque frame, pas cuisable par segment HV).
4. Test : banc client « pose et capture de chaque type de batiment » **doit rester vert** : leftover N113 (`rot` origine, `rawequal` après deux frames) **et** leftover N111 (`ox`/`dx` nombres, `oy` asphalt ≠ shoulder) **et** leftover N110 (deux `stepInterpolation` → `rawequal` Parts, Y asphalt ≠ shoulder) **et** leftover N105 (dispatch → Parent + pulse) **et** leftover N109 (câble Y ≠ rest, Part stable) **doivent rester verts**. Après N115 : `segRot[segmentIndex]` `rawequal` d’un frame à l’autre tant que le camion reste sur le même segment. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé. `CFrame.new(px, py, pz) * rot` : l’assiette (look −Z le long du segment HV) doit rester identique à `lookAt(pos, pos+d)`. Virage à angle droit : `segmentIndex` change → `segRot` du nouveau segment, pas une interpolation d’assiette.
5. Fichiers : `Overlay.luau` (`buildFactoryRoute` path + boucle `route.delivery` de `stepInterpolation` seulement). `tests/client.luau` **seulement si** un assert dans le check pose/capture existant (ne **pas** ajouter un 36e). `BuildingModels.luau` **non**. `WorldRenderer.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur ni visual `3062`.

**Contraintes :** pas de RemoteFunction. Recette visual V64 (`segRot`, fermée sur `3062`). **N115 feel ≠ N113 (chantier rot) ≠ N114 (compact) ≠ N105 (camion lerp) ≠ visual V64 (déjà livré visuel, ne pas merger).** Non réentrant. Ne pas fusionner avec N116 dans le même worker.

---

### ISSUE-N116 — Overlay unités lookAt deux Vector3 60 Hz (feel)

**Priorité :** P3 alloc client unités. Leftover explicite de N103 (lookAt unique déjà, mais deux Vector3 par unité par frame). Distinct de N115 (camion **livraison**, direction HV cuisable) et de N113 (chantier). Recette visual V65 **ouverte** (leftover après V64 camion sur `3062` — le look **change** chaque frame tant que `mag > 0.01`, pas la même recette que `segRot`). Ne pas toucher WorldRenderer ni BuildingModels.

**Problème :** N103 hisse un seul `CFrame.lookAt` par unité. Reste, **par unité interpolée, à chaque frame** : `CFrame.lookAt(Vector3.new(worldX, py, worldZ), Vector3.new(worldX+lookX, py, worldZ+lookZ))`. Deux allocs Vector3 **en plus** du `CFrame.Angles` roulis navire (rotation réelle, inévitable). Immobile (`mag <= 0.01`) : `lookX=0`, `lookZ=-1` → équivalent à `CFrame.new(worldX, py, worldZ)` (regard −Z). En mouvement : le look suit `targetX - currentX` **chaque frame**, donc **pas** cuisable à la pose (contrairement au camion N115 / chantier N113). Distinct de N115 (HV constant), de N105 (camion lerp), de N113 (chantier).

**Pourquoi 20K CCU :** leftover N103. 8 clients × 60 Hz × (navires + missiles visibles, quelques dizaines) × 2 Vector3 lookAt. Pas d’autorité (pose cosmétique). Unifier le cas immobile sur `CFrame.new` coupe les allocs hors déplacement. Forcer une rot cuite casserait le suivi de cible. 0 unité → zéro alloc.

**Worker :**

1. Dans `Overlay.stepInterpolation` boucle `self.units` seulement : garder lerp `currentX/Y` (N101) et X/Z monde (N103). Si `mag <= 0.01` : `frame = CFrame.new(worldX, py, worldZ)` (plus de lookAt, regard −Z). Si `mag > 0.01` : **conserver** `CFrame.lookAt(Vector3.new(worldX, py, worldZ), Vector3.new(worldX+lookX, py, worldZ+lookZ))` — ne **pas** cuire une rot (look change). `CFrame.Angles` roulis navire **inchangé** (`mag > 0.01 and not unit.isMissile`). `UnitModels.place` **inchangé**. Extra missile **inchangé** (N98). `targetX` **inchangé** (N101). Camion / chantier / câble / houle / feuillage **inchangés** (N115 leftover / N113 / N109 / N107 / N108). File dirty **inchangée** (N114).
2. Ne **pas** éditer `UnitModels.luau` / `BuildingModels.luau` / `WorldRenderer.luau` / `HUD.luau` / `WorldSpace.luau`. Ne pas porter N115 (camion `segRot`) dans ce worker. Après N103. Pas de recette visual fermée — V64 est camion ; V56/N103 ont laissé le lookAt.
3. Ne pas convertir le lookAt **en mouvement** (orientation live). Ne pas « fermer » `Size` flamme missile (API, `UnitModels`). Ne pas toucher explosion / wake / splash (événement). Ne pas merger visual `1dbb` / `f5e9`.
4. Test : banc client « navires, missiles et interpolation » **doit rester vert** : leftover N103 (lerp `currentX`/`currentY` sous lookAt unique, navire `extra == nil`, `retreatTinted` conservé) **et** leftover N101 (`targetX`) **et** leftover N98 (extra `rawequal`) **doivent rester verts**. Immobile : pas d’erreur `CFrame.new`. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
5. Fichiers : `Overlay.luau` (boucle `self.units` de `stepInterpolation` seulement). `tests/client.luau` **seulement si** un assert dans le check navires existant (ne **pas** ajouter un 36e). `UnitModels.luau` **non**. `WorldRenderer.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. Immobile = `CFrame.new` ; mouvement = lookAt conservé. **N116 feel ≠ N115 (camion HV) ≠ N113 (chantier) ≠ N103 (lookAt unique déjà).** Non réentrant. Ne pas fusionner avec N115 dans le même worker.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; lookAt chantier → **N113 fait** ; compact dirty → **N114 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; lookAt chantier → **N113 fait** ; compact → **N114 fait**) |
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
| N34–N112 | (voir rapport #128) | — | **faits** |
| N113 | `applyRouteProgress` lookAt deux Vector3 60 Hz | P3 | **fait** cette passe (`segment.rot`, recette visual V63) |
| N114 | `dirtyQueue` préfixe consommé non compacté | P3 | **fait** cette passe (compact seuil 32) |
| N115 | Overlay camion lookAt deux Vector3 60 Hz | P3 | **nouveau** (`route.segRot`, recette visual V64 fermée sur `3062`) |
| N116 | Overlay unités lookAt deux Vector3 60 Hz | P3 | **nouveau** (immobile `CFrame.new` ; mouvement lookAt conservé ; leftover visual V65) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 `NIGHTLY_REPORT.md` historique.

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
| `CHUNK_REBUILDS_PER_FRAME` | 3 | n/a | oui (N102/N104/N106/N112/N114 compact seuil 32) |
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde, N103 X/Z, N105 TRUCK_LIFT monde) |
| `ROUTE_BUILD_SPEED` | — | n/a | oui (N110 lift, N111 nombres, N113 rot) |

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
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.33 p95TickMs=0.74
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `construction du monde 3D` (N114 compact 40 chunks → `dirtyHead == 1` et `#dirtyQueue == 7` puis drain ; leftover N112 `dirtyHead == 1` et `#dirtyQueue == 0` après drain initial ; N106 leftover `partCount` / Ground recyclé ; N107 deux `step(1/60)` → `#oceanRipples` stable, `rawequal` Part, CFrame X ou Z ≠ `base` ; N108 deux `step` → CFrame.Y couronne ≠ `base`) ; `pose et capture de chaque type de batiment` (N113 `rot` à l’origine, `rawequal` après deux frames ; N111 `ox`/`dx` nombres, `oy` asphalt ≠ shoulder ; N110 deux `stepInterpolation` pendant chantier → Parts Road/Shoulder/CenterMark `rawequal`, CFrame.Y asphalt ≠ shoulder ; N105 dispatch → camion parenté, interpolation, arrivée `Parent = nil` + pulse) ; `modeles procéduraux` (N109 `Building.create(PORT)` + deux `animate` → `rawequal` Part câble, CFrame.Y ≠ `RestCFrame.Y` ; `animate(FACTORY)` 0 câble sans erreur) ; `deltas de terrain et conquetes classees` (N114 `dirtyHead <= 32` tant que la file vit ; leftover N112 curseur) ; `navires, missiles et interpolation` (N98 extra `rawequal`, N101 `targetX`, N103 lerp `currentX`/`currentY` sous lookAt unique, navire `extra == nil`, `retreatTinted` conservé) ; `camera strategique` inchangé. `livraison : le gain s'affiche sur la gare` inchangé. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `init.client.luau` **non** touché. `BuildingModels.luau` **non** touché. `PlacementPreview.luau` **non** touché. `UnitModels.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass42.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N113/N114 sont un hoist d’orientation / compact client vérifiés par le banc headless.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N113 n’ajoute **pas** de require (`segment.rot` local dans Overlay). N114 n’ajoute **pas** de require (`DIRTY_COMPACT_HEAD` local dans WorldRenderer). N115 restera dans `Overlay.buildFactoryRoute` / `stepInterpolation`. N116 restera dans `Overlay.stepInterpolation` unités.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N113 : cuire `segment.rot` une fois. `CFrame.new(cx, cy, cz) * rot` doit garder l’assiette look −Z. Recette visual V63 déjà sur `f5e9` — porter, ne pas merger. `part.Size = Vector3.new` reste (API). Ne pas changer `ROUTE_BUILD_SPEED`.

Piège N114 : compact seuil 32, pas à chaque frame. Ne pas `table.remove(1)`. Ne pas compact sous `dirtyHead == 1`. Drain complet N112 **inchangé**. Copie avant nil du surplus (pas de trou). Recycle Parts N106 **inchangé**. Stale (`dirty` déjà nil) saute sans compter le budget, comme avant.

Piège N115 (à venir) : cuire `route.segRot` par segment de `path`, pas une rot unique. Virage = changement d’index, pas slerp. Recette visual V64 déjà sur `3062` — porter, ne pas merger. Roues `CFrame.Angles` **conservées**.

Piège N116 (à venir) : immobile = `CFrame.new` (regard −Z). Mouvement = lookAt conservé (look change). Ne pas cuire une rot unité. Roulis `CFrame.Angles` **conservé**. `UnitModels.place` **non** édité.
