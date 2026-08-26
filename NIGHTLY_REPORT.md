# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 41)

Déclencheur : ouverture de la **PR #125** (`cursor/analyse-nocturne-du-codebase-5c7e`) — câble PORT, lift voie, specs N111–N112.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-04e7`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#125.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. `applyRouteProgress` interpolle `cx, cy, cz` en nombres (N111). `stepRebuilds` consomme via `dirtyHead` (N112). Câble (N109), lift (N110), houle (N107), feuillage (N108), camion (N105) et recycle Ground/Border (N106) restent.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #125 (passe 40) : claims vérifiés.** Câble PORT Y nombres (N109) ; lift cuit dans `layer.origin` (N110). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #125 a documenté (N111, N112)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #125

| Claim #125 | Réalité à l’ouverture |
|---|---|
| `BuildingModels.animate` câble (N109) | Oui. Y en nombres depuis `RestCFrame`, un `CFrame.new`. Plus de `Vector3.new` 60 Hz. Amplitude 0.35. Radar / flag / boom `CFrame.Angles` inchangés. Recette visual V60, pas merger `a0d3`. |
| `applyRouteProgress` lift (N110) | Oui. `layer.origin` cuit à la pose. Hot path sans `+ Vector3.new(0, lift, 0)`. LookAt conservé. Recette visual V61, pas merger `3e1a`. |
| Specs N111–N112 | **Corrigés ici.** N111 = ox/oy/oz + dx/dy/dz, interpolation nombres (recette visual V62 déjà fermée sur `65f4` — **porté, pas mergé**). N112 = `dirtyHead` + truncate, plus de `table.remove(1)`. |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #123 (`d317` / `46a1`), feel jusqu’à #125, visuelles #39/…/#124 (`65f4` V62) / `f5e9` (V63 `segment.rot` **fermé** + leftover V64). **#125 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#123) reste distincte. Ne pas merger visual `f5e9` / `65f4` / `3e1a` ni hardening `d317` / `46a1` sans rebase.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N111–N112 du rapport #125.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `applyRouteProgress` arithmétique Vector3 60 Hz (N111) | `Overlay.luau` (`buildFactoryRoute` calques + `applyRouteProgress`), `tests/client.luau` (asserts dans le check pose/capture existant) | Leftover N110. Cuire `layer.ox/oy/oz` et `segment.dx/dy/dz` à la pose. Hot path : `t = visible - shown / 2` ; `cx, cy, cz = ox + dx*t, …` ; `CFrame.lookAt(Vector3.new(cx,cy,cz), Vector3.new(cx+dx,…))`. LookAt conservé. `part.Size` = API. Lift / câble / camion / houle / feuillage **inchangés** (N110/N109/N105/N107/N108). Recette visual V62 déjà sur `65f4`, **pas** merger. Cosmétique (pose). 0 chantier → zéro alloc. |
| `stepRebuilds` `table.remove(1)` O(n) (N112) | `WorldRenderer.luau` (`new` + `stepRebuilds`), `tests/client.luau` (asserts dans construction + deltas existants) | Leftover N106. Curseur `dirtyHead`, truncate `table.clear` quand la file est consommée. Plus de `table.remove`. `markChunkDirty` / `table.insert` inchangés. Recycle Ground/Border **inchangé** (N106). `meshKeyAt` **inchangé** (N104). Houle / feuillage **inchangés** (N107/N108). Pas d’autorité (file client). 0 dirty → zéro travail. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), lookAt chantier deux Vector3 (**N113**), compact préfixe `dirtyQueue` (**N114**). `PlacementPreview.resolve` ctx déjà **N92**. `self.ranked` inner déjà **N97**. Overlay `trackUnit` extra déjà **N98**. Hover déjà **N99**. `rankByTiles` déjà **N100**. `targetX` déjà **N101**. `BORDER_PASSES` déjà **N102**. lookAt unités déjà **N103**. `meshKeyAt` déjà **N104**. Camion déjà **N105**. Parts Ground déjà **N106**. Houle déjà **N107**. Feuillage déjà **N108**. Câble déjà **N109**. Lift déjà **N110**. `else {}` overlay-nil hors passe.

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
- Overlay `stepInterpolation` X/Z monde + un `lookAt` unités (**N103**) **et** camion (**N105**). `rebuildChunk` hisse `meshKeyAt` (**N104**) et recycle Ground/Border par chunk (**N106**). Houle océan (**N107**) et feuillage (**N108**) = nombres + un `CFrame.new`. Câble PORT (**N109**) = nombres + un `CFrame.new`. Lift voie (**N110**) cuit dans `layer.origin`. Arithmétique `origin + direction * t` **fermée** (**N111**). `table.remove(dirtyQueue, 1)` **fermé** (**N112**). LookAt chantier deux Vector3 encore 60 Hz (**N113**). Préfixe consommé de `dirtyQueue` non compacté tant que la file n’est pas vide (**N114**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N113–N114)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N112 = faits. N22 = **N67 fait**. N27 = doc only. **V62 / N111** fermés ici (portés, pas mergés ; V62 déjà livré visuel `65f4`). **N112** fermé ici (pas d’équivalent visuel). **V63** fermé visuel `f5e9` — leftover feel = **N113** (porter `segment.rot`, ne pas merger).

---

### ISSUE-N113 — `applyRouteProgress` lookAt deux Vector3 60 Hz (feel)

**Priorité :** P3 alloc client chantier. Leftover explicite de N111 (lerp nombres). Distinct de N111 (nombres déjà), de N110 (lift déjà) et de N105 (camion **livraison** — lookAt conservé). Recette visual V63 **fermée** sur `f5e9` (passe 46, PR visual #124+) — **porter la recette, ne pas merger**. Ne pas toucher WorldRenderer (N112/N106) ni BuildingModels (N109).

**Problème :** N111 ferme `origin + direction * t`. Reste, **par calque de voie en chantier, à chaque frame** : `CFrame.lookAt(Vector3.new(cx, cy, cz), Vector3.new(cx+dx, cy+dy, cz+dz))`. Deux allocs Vector3 **en plus** du `Size = Vector3.new` (API, inévitable). La direction est constante (grille HV, cuit N111) : l’orientation peut être posée **une fois**. Distinct de N111 (lerp nombres), de N110 (lift), de N105 (camion déjà en nombres + lookAt conservé), de N103 (unités lookAt conservé). Recette : cuire `segment.rot` à la construction, composer `CFrame.new(cx, cy, cz) * rot`.

**Pourquoi 20K CCU :** leftover N111. 8 clients × 60 Hz × N voies en chantier (0.35–3 s, pas tout le match) × 3 calques × 2 Vector3 lookAt. Pas d’autorité (pose cosmétique). Changer `dx/dy/dz` sans adapter le look casserait l’assiette. 0 chantier (`construction == nil`) → zéro alloc (déjà `continue`).

**Worker :**

1. Dans `buildFactoryRoute` seulement, poser `segment.rot = CFrame.lookAt(Vector3.zero, direction)` **une fois** (direction déjà cuit N111 ; grille HV donc un axe ≈ 0). Dans `applyRouteProgress` : garder `t` / `cx, cy, cz` (N111) ; poser `part.CFrame = CFrame.new(cx, cy, cz) * segment.rot`. Plus de `CFrame.lookAt` 60 Hz. `part.Size = Vector3.new(...)` **inchangé**. `layer.ox/oy/oz` / `segment.dx/dy/dz` **inchangés** (N111). `layer.origin` / `segment.direction` **peuvent rester**. Radar / flag / boom / câble **inchangés** (N109 déjà). Camion / houle / feuillage / unités **inchangés** (N105/N107/N108/N103). Extra missile **inchangé** (N98). `targetX` **inchangé** (N101). Lift cuit **inchangé** (N110). Interpolation nombres **inchangée** (N111). File dirtyHead **inchangée** (N112).
2. Ne **pas** éditer `BuildingModels.luau` / `WorldRenderer.luau` / `UnitModels.luau` / `HUD.luau` / `WorldSpace.luau`. Ne pas recycler explosion / wake / splash (événement). Ne pas changer `ROUTE_BUILD_SPEED` / durée 0.35–3 s. Après N111. Recette visual V63 **fermée** sur `f5e9` — porter `segment.rot`, pas merger visual.
3. Ne pas porter Overlay camion (N105 déjà) ni houle (N107) ni feuillage (N108) ni câble (N109) ni lift (N110) ni lerp nombres (N111 déjà) ni dirtyHead (N112 déjà). Ne pas convertir Radar / Flag / Boom (rotation visible). Ne pas « fermer » `Size` (API). Ne pas « fermer » les lookAt unités / camion (N103/N105 — leftover API distinct, pas N113).
4. Test : banc client « pose et capture de chaque type de batiment » **doit rester vert** : leftover N111 (`ox`/`dx` nombres, `oy` asphalt ≠ shoulder) **et** leftover N110 (deux `stepInterpolation` → `rawequal` Parts, Y asphalt ≠ shoulder) **et** leftover N105 (dispatch → Parent + pulse) **et** leftover N109 (câble Y ≠ rest, Part stable) **doivent rester verts**. `pavedLength` croît, chantier nil après 30 × 0.2 s. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé. `CFrame.new(cx, cy, cz) * rot` : l’assiette (look −Z le long de `direction`) doit rester identique à `lookAt(centre, centre+dir)`.
5. Fichiers : `Overlay.luau` (`buildFactoryRoute` calques + `applyRouteProgress` seulement). `tests/client.luau` **seulement si** un assert dans le check pose/capture existant (ne **pas** ajouter un 36e). `BuildingModels.luau` **non**. `WorldRenderer.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur ni visual `f5e9`.

**Contraintes :** pas de RemoteFunction. Recette visual V63 (`segment.rot`, fermée sur `f5e9`). **N113 feel ≠ N111 (lerp) ≠ N112 (dirtyHead) ≠ visual V63 (déjà livré visuel, ne pas merger).** Non réentrant. Ne pas fusionner avec N114 dans le même worker.

---

### ISSUE-N114 — `dirtyQueue` préfixe consommé non compacté (feel)

**Priorité :** P3 mémoire client file. Leftover explicite de N112 (curseur — truncate seulement quand `dirtyHead > #queue`). Distinct de N112 (plus de `table.remove`) et de N106 (recycle Parts déjà). Pas d’équivalent visuel V63 (V63 = Overlay lookAt). Ne pas toucher Overlay (N113/N111) ni BuildingModels (N109).

**Problème :** N112 avance `dirtyHead` et ne `table.clear` que lorsque la file est **entièrement** consommée. Pendant une vague (p95 dirty chunks = 7 au banc 6000 ticks, budget = 3 / frame), la file ne se vide pas : le préfixe `1 .. dirtyHead-1` reste alloué, `table.insert` allonge la fin, et `#dirtyQueue` croît jusqu’à la fin de la vague. Distinct de N112 (identité du curseur), de N106 (identité des Parts), de N2 (skip payload). Recette : compact in-place des restants vers l’index 1 quand `dirtyHead > 32` (ou `dirtyHead * 2 > #queue`), puis `dirtyHead = 1`. Pas de `table.remove(1)`.

**Pourquoi 20K CCU :** leftover N112. 8 clients × vagues de conquête (maxChanged = 479 tuiles) × préfixe mort qui ne se libère que quand le budget rattrape la file. Pas d’autorité (file client). Un compact qui saute un index laisserait un trou visuel (chunk sale jamais reconstruit) ou un flash (chunk reconstruit deux fois). File vide → déjà truncate N112.

**Worker :**

1. Dans `WorldRenderer.stepRebuilds` seulement, **après** la boucle budget, si `dirtyHead > 1` et `dirtyHead <= #queue` et `dirtyHead > 32` : copier `queue[dirtyHead..#]` vers `1..n`, nil le surplus, `dirtyHead = 1`. Ne **pas** compact à chaque frame (coût O(restants) inutile si la tête avance de 3). Ne **pas** `table.remove`. `table.clear` du drain complet **inchangé** (N112). `markChunkDirty` / `table.insert` **inchangés**. `rebuildChunk` recycle Ground/Border **inchangé** (N106). `meshKeyAt` **inchangé** (N104). Houle / feuillage **inchangés** (N107/N108).
2. Ne **pas** éditer `Overlay.luau` / `BuildingModels.luau` / `UnitModels.luau` / `HUD.luau` / `WorldSpace.luau` / `GreedyMesh.luau`. Ne pas porter N113 (lookAt chantier). Après N112. Pas de recette visual — V63 est Overlay.
3. Ne pas fusionner Ground et Border. Ne pas Destroy le folder. `partCount` inchangé. Océan / SeaFloor / glints / foliage hors file. Seuil 32 = ~10 frames de budget 3 ; ne pas descendre à 1 (compact O(n) chaque frame = pire que N112).
4. Test : banc client « construction du monde 3D » **et** « deltas de terrain et conquetes classees » **et** « vagues de conquete » **doivent rester verts**. Leftover N112 (`dirtyHead == 1` et `#dirtyQueue == 0` après drain construction) **et** leftover N106 (`partCount` / Ground recyclé) **et** leftover N107/N108 (houle + feuillage) **doivent rester verts**. Deux `applyDelta` successifs → chunks reconstruits, pas de Part orpheline. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
5. Fichiers : `WorldRenderer.luau` (`stepRebuilds` seulement, éventuellement constante `DIRTY_COMPACT_HEAD`). `tests/client.luau` **seulement si** un assert dans le check construction ou deltas existant (ne **pas** ajouter un 36e). `Overlay.luau` **non**. `BuildingModels.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. Compact seuil, pas `table.remove(1)`, pas de deque module. **N114 feel ≠ N113 (lookAt Overlay) ≠ N112 (curseur) ≠ N106 (recycle Parts).** Non réentrant : synchrone, un chunk à la fois. Ne pas fusionner avec N113 dans le même worker.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; câble → **N109 fait** ; lift → **N110 fait** ; nombres chantier → **N111 fait** ; dirtyHead → **N112 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; câble → **N109 fait** ; lift → **N110 fait** ; nombres → **N111 fait** ; dirtyHead → **N112 fait**) |
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
| N34–N110 | (voir rapport #125) | — | **faits** |
| N111 | `applyRouteProgress` arithmétique Vector3 60 Hz | P3 | **fait** cette passe (nombres ox/dx, recette visual V62) |
| N112 | `stepRebuilds` `table.remove(dirtyQueue, 1)` O(n) | P3 | **fait** cette passe (curseur + truncate) |
| N113 | `applyRouteProgress` lookAt deux Vector3 60 Hz | P3 | **nouveau** (`segment.rot`, recette visual V63 fermée sur `f5e9`) |
| N114 | `dirtyQueue` préfixe consommé non compacté | P3 | **nouveau** (compact seuil 32, pas de recette visual) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 `NIGHTLY_REPORT.md` historique.

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
| `CHUNK_REBUILDS_PER_FRAME` | 3 | n/a | oui (N102/N104/N106/N112 leftover compact N114) |
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde, N103 X/Z, N105 TRUCK_LIFT monde) |
| `ROUTE_BUILD_SPEED` | — | n/a | oui (N110 lift, N111 nombres, leftover N113 lookAt) |

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

Client : **35/35 OK** — dont `construction du monde 3D` (N112 `dirtyHead == 1` et `#dirtyQueue == 0` après drain ; N106 leftover `partCount` / Ground recyclé ; N107 deux `step(1/60)` → `#oceanRipples` stable, `rawequal` Part, CFrame X ou Z ≠ `base` ; N108 deux `step` → CFrame.Y couronne ≠ `base`) ; `pose et capture de chaque type de batiment` (N111 `ox`/`dx` nombres, `oy` asphalt ≠ shoulder ; N110 deux `stepInterpolation` pendant chantier → Parts Road/Shoulder/CenterMark `rawequal`, CFrame.Y asphalt ≠ shoulder ; N105 dispatch → camion parenté, interpolation, arrivée `Parent = nil` + pulse) ; `modeles procéduraux` (N109 `Building.create(PORT)` + deux `animate` → `rawequal` Part câble, CFrame.Y ≠ `RestCFrame.Y` ; `animate(FACTORY)` 0 câble sans erreur) ; `deltas de terrain et conquetes classees` (N112 `dirtyHead >= 1` après deux `stepRebuilds`) ; `navires, missiles et interpolation` (N98 extra `rawequal`, N101 `targetX`, N103 lerp `currentX`/`currentY` sous lookAt unique, navire `extra == nil`, `retreatTinted` conservé) ; `camera strategique` inchangé. `livraison : le gain s'affiche sur la gare` inchangé. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `init.client.luau` **non** touché. `BuildingModels.luau` **non** touché. `PlacementPreview.luau` **non** touché. `UnitModels.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass41.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N111/N112 sont des hoists numériques / curseur client vérifiés par le banc headless.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N111 n’ajoute **pas** de require (nombres locaux dans Overlay). N112 n’ajoute **pas** de require (`dirtyHead` local dans WorldRenderer). N113 restera dans `Overlay.applyRouteProgress`. N114 restera dans `WorldRenderer.stepRebuilds`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N111 : interpoler `ox+dx*t` en nombres. Ne pas « fermer » `CFrame.lookAt(Vector3, Vector3)` (API, leftover N113). Recette visual V62 déjà sur `65f4` — porter, ne pas merger. `layer.origin` / `segment.direction` peuvent rester (construction). Ne pas changer `ROUTE_BUILD_SPEED`.

Piège N112 : curseur `dirtyHead`, `table.clear` seulement quand `head > #queue`. Ne pas `table.remove(1)`. Ne pas casser `markChunkDirty` / `self.dirty[chunk]`. Recycle Parts N106 **inchangé**. Stale (`dirty` déjà nil) saute sans compter le budget, comme avant.

Piège N113 (à venir) : cuire `segment.rot` une fois. `CFrame.new(cx, cy, cz) * rot` doit garder l’assiette look −Z. Recette visual V63 déjà sur `f5e9` — porter, ne pas merger.

Piège N114 (à venir) : compact seuil, pas à chaque frame. Ne pas `table.remove(1)`. Ne pas compact sous `dirtyHead == 1`. Drain complet N112 **inchangé**.
