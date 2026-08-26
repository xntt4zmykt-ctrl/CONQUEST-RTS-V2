# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 43)

Déclencheur : ouverture de la **PR #131** (`cursor/analyse-nocturne-du-codebase-846c`) — `applyRouteProgress` rot, compact `dirtyQueue`, specs N115–N116.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-ab04`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#131.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. `buildFactoryRoute` cuit `route.segRot` par segment HV ; `stepInterpolation` compose `CFrame.new(px, py, pz) * route.segRot[segmentIndex]` (N115). Unités immobiles (`mag <= 0.01`) : `CFrame.new(worldX, py, worldZ)` (N116). LookAt chantier (N113), compact dirty (N114), nombres (N111), `dirtyHead` (N112), câble (N109), lift (N110), houle (N107), feuillage (N108), camion lerp (N105) et recycle Ground/Border (N106) restent.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #131 (passe 42) : claims vérifiés.** `segment.rot` cuit, `CFrame.new * rot` (N113) ; compact `dirtyQueue` seuil 32 (N114). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #131 a documenté (N115, N116)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #131

| Claim #131 | Réalité à l’ouverture |
|---|---|
| `applyRouteProgress` rot (N113) | Oui. `segment.rot = CFrame.lookAt(Vector3.zero, direction)` à la pose. Hot path : `CFrame.new(cx, cy, cz) * segment.rot`. Plus de lookAt 60 Hz chantier. Recette visual V63, pas merger `f5e9`. |
| `stepRebuilds` compact (N114) | Oui. Après budget, si `dirtyHead > 32` et file non vide : copie in-place, nil du surplus, `dirtyHead = 1`. Drain N112 inchangé. Pas de `table.remove`. |
| Specs N115–N116 | **Corrigés ici.** N115 = `route.segRot` cuit, `CFrame.new * segRot` (recette visual V64 déjà fermée sur `3062` — **porté, pas mergé**). N116 = immobile `CFrame.new` ; mouvement lookAt conservé (leftover visual V65). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #130 (`e488`), feel jusqu’à #131, visuelles #39/…/#129 (`3062` V64 camion `segRot` **fermé** + leftover V65 unités lookAt). **#131 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#130) reste distincte. Ne pas merger visual `3062` / `f5e9` ni hardening `e488` / `46a1` sans rebase.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N115–N116 du rapport #131.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Overlay camion lookAt deux Vector3 60 Hz (N115) | `Overlay.luau` (`buildFactoryRoute` path + boucle `route.delivery` de `stepInterpolation`), `tests/client.luau` (asserts dans le check pose/capture existant) | Leftover N113. Cuire `route.segRot[i] = CFrame.lookAt(Vector3.zero, path[i+1]-path[i])` (Magnitude `< 0.01` → rot précédente / identité). Hot path : `CFrame.new(px, py, pz) * route.segRot[segmentIndex]`. Plus de `CFrame.lookAt` 60 Hz camion. `CFrame.Angles` roues **inchangé**. Construction initiale `truckPart` lookAt `from→to` **conservée** (une fois). Chantier `segment.rot` **inchangé** (N113). Recette visual V64 déjà sur `3062`, **pas** merger. Cosmétique (pose). 0 livraison → zéro alloc (déjà `continue`). |
| Overlay unités lookAt deux Vector3 60 Hz hors déplacement (N116) | `Overlay.luau` (boucle `self.units` de `stepInterpolation`), `tests/client.luau` (asserts dans le check navires existant) | Leftover N103. Immobile (`mag <= 0.01`) : `CFrame.new(worldX, py, worldZ)` (regard −Z). Mouvement : lookAt **conservé** (look change chaque frame, pas cuisable). Roulis `CFrame.Angles` **inchangé**. `UnitModels.place` **inchangé**. Extra missile **inchangé** (N98). Cosmétique. 0 unité → zéro alloc. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), lookAt unités **en mouvement** (**N117**), lookAt camera 60 Hz (**N118**). `PlacementPreview.resolve` ctx déjà **N92**. `self.ranked` inner déjà **N97**. Overlay `trackUnit` extra déjà **N98**. Hover déjà **N99**. `rankByTiles` déjà **N100**. `targetX` déjà **N101**. `BORDER_PASSES` déjà **N102**. lookAt unités unique déjà **N103**. `meshKeyAt` déjà **N104**. Camion lerp déjà **N105**. Parts Ground déjà **N106**. Houle déjà **N107**. Feuillage déjà **N108**. Câble déjà **N109**. Lift déjà **N110**. Nombres déjà **N111**. `dirtyHead` déjà **N112**. Rot chantier déjà **N113**. Compact déjà **N114**. `else {}` overlay-nil hors passe.

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
- Overlay `stepInterpolation` X/Z monde + un `lookAt` unités en mouvement (**N103**, leftover **N117**) **et** camion lerp (**N105**) + `segRot` (**N115**). `rebuildChunk` hisse `meshKeyAt` (**N104**) et recycle Ground/Border par chunk (**N106**). Houle océan (**N107**) et feuillage (**N108**) = nombres + un `CFrame.new`. Câble PORT (**N109**) = nombres + un `CFrame.new`. Lift voie (**N110**) cuit dans `layer.origin`. Arithmétique `origin + direction * t` **fermée** (**N111**). `table.remove(dirtyQueue, 1)` **fermé** (**N112**). LookAt chantier **fermé** (**N113**). Compact préfixe `dirtyQueue` **fermé** (**N114**). LookAt camion **fermé** (**N115**). LookAt unités immobile **fermé** (**N116**). LookAt unités en mouvement encore 60 Hz (**N117**). LookAt camera encore 60 Hz (**N118**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N117–N118)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N116 = faits. N22 = **N67 fait**. N27 = doc only. **V64 / N115** fermés ici (portés, pas mergés ; V64 déjà livré visuel `3062`). **N116** fermé ici (immobile seulement). **V65** fermé visuel `dc65` — leftover feel = **N117** (porter euler mouvement, ne pas merger). **V66** ouvert visuel — leftover feel = **N118**.

---

### ISSUE-N117 — Overlay unités lookAt en mouvement deux Vector3 60 Hz (feel)

**Priorité :** P3 alloc client unités. Leftover explicite de N116 (immobile `CFrame.new` déjà). Distinct de N116 (cas `mag <= 0.01` déjà), de N115 (camion **HV cuisable** via `segRot`) et de N113 (chantier). Recette visual V65 **fermée** sur `dc65` (passe 48 visual, après V64 camion) — `CFrame.new(worldX, py, worldZ) * CFrame.fromEulerAnglesYXZ(0, atan2(dx, -dy), 0)` (yaw monde, regard −Z). **Porter la recette, ne pas merger.** Ne pas toucher WorldRenderer ni BuildingModels ni WorldCamera.

**Problème :** N116 coupe le lookAt **immobile**. Reste, **par unité interpolée en mouvement, à chaque frame** : `CFrame.lookAt(Vector3.new(worldX, py, worldZ), Vector3.new(worldX+dx, py, worldZ+dy))`. Deux allocs Vector3 **en plus** du `CFrame.Angles` roulis navire (rotation réelle, inévitable). Le look suit `targetX - currentX` **chaque frame**, donc **pas** cuisable à la pose (contrairement au camion N115). `fromEulerAnglesYXZ(0, atan2(dx, -dy), 0)` produit la même assiette look −Z **sans** deux Vector3. Distinct de N116 (immobile déjà), de N115 (HV constant), de N105 (camion lerp), de N113 (chantier).

**Pourquoi 20K CCU :** leftover N116. 8 clients × 60 Hz × (navires + missiles en déplacement, quelques dizaines en pic) × 2 Vector3 lookAt. Pas d’autorité (pose cosmétique). Forcer une rot cuite à la pose casserait le suivi de cible. 0 unité en mouvement → zéro alloc (déjà `CFrame.new` N116).

**Worker :**

1. Dans `Overlay.stepInterpolation` boucle `self.units` seulement, branche `mag > 0.01` : garder lerp `currentX/Y` (N101) et X/Z monde (N103). Remplacer `CFrame.lookAt(deux Vector3)` par `frame = CFrame.new(worldX, py, worldZ) * CFrame.fromEulerAnglesYXZ(0, math.atan2(dx, -dy), 0)`. Immobile (`mag <= 0.01`) **inchangé** (`CFrame.new`, N116). `CFrame.Angles` roulis navire **inchangé** (`mag > 0.01 and not unit.isMissile`, **après** la compose yaw). `UnitModels.place` **inchangé**. Extra missile **inchangé** (N98). `targetX` **inchangé** (N101). Camion / chantier / câble / houle / feuillage **inchangés** (N115 / N113 / N109 / N107 / N108). File dirty **inchangée** (N114). Camera **inchangée** (N118 leftover).
2. Ne **pas** éditer `UnitModels.luau` / `BuildingModels.luau` / `WorldRenderer.luau` / `HUD.luau` / `WorldSpace.luau` / `WorldCamera.luau`. Ne pas porter N118 (camera lookAt) dans ce worker. Après N116. Recette visual V65 **fermée** sur `dc65` — porter `fromEulerAnglesYXZ`, pas merger visual `dc65` / `3062`.
3. Ne pas « fermer » `Size` flamme missile (API, `UnitModels`). Ne pas toucher explosion / wake / splash (événement). Ne pas merger visual `1dbb` / `3062`. Ne pas cuire une rot à l’insert (look change). `atan2(dx, -dy)` : `dx` = delta tuile X, `dy` = delta tuile Y = monde Z. Vérifier l’assiette vs lookAt (regard −Z vers la cible). Missile **sans** roulis : yaw seulement.
4. Test : banc client « navires, missiles et interpolation » **doit rester vert** : leftover N116 (navire immobile `currentX == targetX`) **et** leftover N103 (lerp `currentX`/`currentY` sous yaw, navire `extra == nil`, `retreatTinted` conservé) **et** leftover N101 (`targetX`) **et** leftover N98 (extra `rawequal`) **doivent rester verts**. Mouvement : pas d’erreur `fromEulerAnglesYXZ`. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
5. Fichiers : `Overlay.luau` (branche `mag > 0.01` de la boucle `self.units` de `stepInterpolation` seulement). `tests/client.luau` **seulement si** un assert dans le check navires existant (ne **pas** ajouter un 36e). `UnitModels.luau` **non**. `WorldCamera.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. Immobile = `CFrame.new` (N116) ; mouvement = `CFrame.new * fromEulerAnglesYXZ`. **N117 feel ≠ N116 (immobile déjà) ≠ N115 (camion HV) ≠ N113 (chantier) ≠ N103 (lookAt unique déjà) ≠ visual V65 (déjà livré visuel `dc65`, ne pas merger).** Non réentrant. Ne pas fusionner avec N118 dans le même worker.

---

### ISSUE-N118 — WorldCamera.step lookAt deux Vector3 60 Hz (feel)

**Priorité :** P3 alloc client camera. Leftover explicite après N116/N117 (Overlay unités). Distinct de N117 (unités monde) et de N103 (Overlay). Recette visual V66 **ouverte** (leftover après V65 unités). `WorldCamera.step` overview seulement. Ne pas toucher Overlay ni WorldRenderer.

**Problème :** N115/N116 ferment Overlay camion / unités immobile. Reste, **chaque frame overview** : `CFrame.lookAt(self.focus + offset + shake, self.focus + shake * 0.18)`. Deux Vector3 lookAt **en plus** de `Vector3.new` shake et de `VectorToWorldSpace(Vector3.new(0, 0, distance))`. `rotation = CFrame.fromEulerAnglesYXZ(-pitch, yaw, 0)` est **déjà** l’orientation camera. Si `shake == 0`, lookAt(eye, focus) ≡ `CFrame.new(ex, ey, ez) * rotation` (offset = rotation · (0,0,distance) = recul camera). Le biais `shake * 0.18` sur la cible est cosmétique (tremblement de visée). Distinct de N117 (unités), de N115 (camion).

**Pourquoi 20K CCU :** leftover Overlay. 8 clients × 60 Hz × 1 camera × 2 Vector3 lookAt (+ shake/offset Vector3). Pas d’autorité (pose camera). Changer le look target `shake * 0.18` sans documenter ferait dériver le shake visuel. Hors overview (`mode ~= "overview"`) → early-out déjà, zéro alloc pose.

**Worker :**

1. Dans `WorldCamera.step` seulement, après le calcul `rotation` / `offset` / `shake` : poser l’œil en nombres `ex, ey, ez` (`focus.X + offset.X + shake.X`, idem Y/Z). Remplacer `CFrame.lookAt(deux Vector3)` par `self.camera.CFrame = CFrame.new(ex, ey, ez) * rotation`. Documenter : le biais `lookAt(..., focus + shake * 0.18)` est abandonné (shake sur l’œil seulement ; `rotation` porte déjà yaw/pitch). `Vector3.new` shake **peut rester** cette passe (leftover, ne pas « fermer » offset/shake dans N118). Overlay unités / camion / chantier **inchangés** (N117 leftover / N116 / N115 / N113). Houle / feuillage / câble **inchangés**. `stepInput` **inchangé**. FOV **inchangé**.
2. Ne **pas** éditer `Overlay.luau` / `WorldRenderer.luau` / `UnitModels.luau` / `HUD.luau` / `BuildingModels.luau`. Ne pas porter N117 (unités euler) dans ce worker. Après N116. Recette visual V66 ouverte — porter compose `CFrame.new * rotation`, pas merger visual.
3. Ne pas convertir Radar / Flag / Boom. Ne pas toucher `Camera.ViewportPointToRay` (sélection). Ne pas changer MIN/MAX_DISTANCE. Ne pas « fermer » `Vector3.new` shake (passe suivante si besoin). Tests « camera strategique » et « camera tactile » **doivent rester verts**.
4. Test : banc client « camera strategique » **et** « camera tactile : panoramique, pincement et torsion » **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé. Overview : `CFrame.new * rotation` doit garder yaw/pitch identiques à lookAt hors shake. Shake non-zéro : l’œil tremble encore ; la visée ne bascule plus de `0.18 * shake` (choix documenté, cosmétique).
5. Fichiers : `WorldCamera.luau` (`step` overview seulement). `tests/client.luau` **seulement si** un assert dans le check camera existant (ne **pas** ajouter un 36e). `Overlay.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. Compose `CFrame.new(ex,ey,ez) * rotation` déjà calculée. **N118 feel ≠ N117 (unités euler) ≠ N116 (Overlay immobile) ≠ visual V66 (si livré visuel, ne pas merger).** Non réentrant. Ne pas fusionner avec N117 dans le même worker.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; lookAt camion → **N115 fait** ; unités immobile → **N116 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; lookAt camion → **N115 fait** ; unités immobile → **N116 fait**) |
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
| N34–N114 | (voir rapport #131) | — | **faits** |
| N115 | Overlay camion lookAt deux Vector3 60 Hz | P3 | **fait** cette passe (`route.segRot`, recette visual V64) |
| N116 | Overlay unités lookAt immobile | P3 | **fait** cette passe (`CFrame.new` si `mag <= 0.01`) |
| N117 | Overlay unités lookAt en mouvement | P3 | **nouveau** (`CFrame.new * fromEulerAnglesYXZ`, recette visual V65 fermée sur `dc65`) |
| N118 | WorldCamera.step lookAt deux Vector3 60 Hz | P3 | **nouveau** (`CFrame.new * rotation`, leftover visual V66) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde, N103 X/Z, N105 TRUCK_LIFT monde, N115 segRot HV) |
| `ROUTE_BUILD_SPEED` | — | n/a | oui (N110 lift, N111 nombres, N113 rot, N115 segRot) |

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
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.72
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `construction du monde 3D` (N114 compact leftover, N112 `dirtyHead`, N106/N107/N108) ; `pose et capture de chaque type de batiment` (N115 `segRot` à l’origine, `#segRot == #path-1`, `rawequal` après deux frames de livraison ; leftover N113 `rot` chantier ; leftover N111 `ox`/`dx` ; leftover N110 Parts `rawequal` ; leftover N105 dispatch → camion parenté, arrivée `Parent = nil` + pulse) ; `modeles procéduraux` (N109 câble) ; `deltas de terrain et conquetes classees` (N114 `dirtyHead <= 32`) ; `navires, missiles et interpolation` (N116 navire immobile `currentX == targetX` ; leftover N103 lerp missile, N98 extra `rawequal`, N101 `targetX`, navire `extra == nil`, `retreatTinted` conservé) ; `camera strategique` inchangé. `livraison : le gain s'affiche sur la gare` inchangé. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `init.client.luau` **non** touché. `BuildingModels.luau` **non** touché. `PlacementPreview.luau` **non** touché. `UnitModels.luau` **non** touché. `WorldRenderer.luau` **non** touché. `WorldCamera.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass43.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N115/N116 sont un hoist d’orientation / `CFrame.new` immobile vérifiés par le banc headless.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N115 n’ajoute **pas** de require (`route.segRot` local dans Overlay). N116 n’ajoute **pas** de require (`CFrame.new` immobile). N117 restera dans `Overlay.stepInterpolation` unités. N118 restera dans `WorldCamera.step`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N113 : cuire `segment.rot` une fois. `CFrame.new(cx, cy, cz) * rot` doit garder l’assiette look −Z. Recette visual V63 déjà sur `f5e9` — porter, ne pas merger. `part.Size = Vector3.new` reste (API). Ne pas changer `ROUTE_BUILD_SPEED`.

Piège N114 : compact seuil 32, pas à chaque frame. Ne pas `table.remove(1)`. Ne pas compact sous `dirtyHead == 1`. Drain complet N112 **inchangé**. Copie avant nil du surplus (pas de trou). Recycle Parts N106 **inchangé**. Stale (`dirty` déjà nil) saute sans compter le budget, comme avant.

Piège N115 : cuire `route.segRot` par segment de `path`, pas une rot unique. Magnitude `< 0.01` → rot précédente / identité (jamais lookAt dégénéré). Virage = changement d’index, pas slerp. Recette visual V64 déjà sur `3062` — porter, ne pas merger. Roues `CFrame.Angles` **conservées**. Construction initiale `truckPart` lookAt **conservée** (une fois).

Piège N116 : immobile = `CFrame.new` (regard −Z). Mouvement = lookAt conservé (look change). Ne pas cuire une rot unité. Roulis `CFrame.Angles` **conservé**. `UnitModels.place` **non** édité.

Piège N117 (à venir) : `fromEulerAnglesYXZ(0, atan2(dx, -dy), 0)` — `dy` tuile = monde Z. Compose **après** `CFrame.new`, **avant** le roulis navire. Recette visual V65 déjà sur `dc65` — porter, ne pas merger. Ne pas merger visual.

Piège N118 (à venir) : `CFrame.new(ex,ey,ez) * rotation` déjà calculée. Abandonner le biais `lookAt(..., focus + shake * 0.18)` (cosmétique, documenter). Ne pas « fermer » `Vector3.new` shake dans la même passe. Recette visual V66 ouverte.
