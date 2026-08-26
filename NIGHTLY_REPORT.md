# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 35)

Déclencheur : ouverture de la **PR #106** (`cursor/analyse-nocturne-du-codebase-c786`) — HUD.ranked, Overlay.trackUnit, specs N99–N100.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-4a67`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#106.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. `previewOwnerAt` / `previewBuildingAt` sont des fonctions module `init.client` (capturent `world` / `overlay`). `rankByTiles` est une fonction module HUD ; `self.ranked` reste un array d’instance.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #106 (passe 34) : claims vérifiés.** `HUD.update` recycle `self.ranked` + inner records (N97) ; `Overlay.applyUnits` hisse `trackUnit`, extra missile muté (N98). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #106 a documenté (N99, N100)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #106

| Claim #106 | Réalité à l’ouverture |
|---|---|
| `self.ranked` (N97) | Oui. Inner records mutés, truncate leftover **avant** `table.sort`, pas de `table.insert`. Recette visual V50, pas merger `2932`. |
| `trackUnit` (N98) | Oui. Hoist module. Extra missile posé une fois, `tx/ty` mutés (`rawequal`). Navire `extra` nil. Recette visual V52, pas merger `36bc`. |
| Specs N99–N100 | **Corrigés ici.** N100 = comparateur `rankByTiles` (recette visual V54), pas `buildChunkBorders` — ce leftover est **N102**. |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #104 (5f6c), feel jusqu’à #106, visuelles #39/…/#105 (`rankByTiles` V54). **#106 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#104) reste distincte. Ne pas merger visual `36bc` / `e3ed` ni hardening `5f6c` / `71d9` sans rebase.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N99–N100 du rapport #106.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `init.client` closures hover 60 Hz (N99) | `init.client.luau` (RenderStepped aperçu seulement) | Leftover N98. Hoist `previewOwnerAt` / `previewBuildingAt` module, capturent `world` / `overlay`. Overlay nil → `buildingAt` nil ; world nil → `ownerAt` 0. Recette visual V53, **pas** merger `36bc`. Cosmétique (le serveur re-résout). |
| `HUD.update` comparateur `table.sort` 10 Hz (N100) | `HUD.luau` (`HUD.update` sort seulement), `tests/client.luau` (commentaire check existant) | Leftover N97/N99. Hoist `rankByTiles` — même loi tuiles desc / troupes tie-break. Plus de `function` inline. Recette visual V54, **pas** merger `e3ed`. Cosmétique (victoire serveur). |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), Overlay `Vector2.new` cible (**N101**), `buildChunkBorders` ownerOf/emit/`BORDER_PASSES` (**N102**). `PlacementPreview.resolve` ctx déjà **N92**. `self.ranked` inner déjà **N97**. Overlay `trackUnit` déjà **N98**. `else {}` overlay-nil hors passe.

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
- **`samsOf`** = lit `samsBySlot` dans `samBuf` recyclé (N68). `tryIntercept` lit l’index directement (N57).
- **Score nuke bots** = flatten `buildingsBySlot` une fois (N69), puis 90 `scoreBlast`.
- **Inbound `removePlayer`** = snapshot `destroyBuf` (**N89**) → destroy → diplo + transports `kind==1` (100 %, lit **`owner[targetTile]`**) + missiles contrat B + cadran/colis + convois `kind==2` (coulés), **avant** `setOwner`.
- **Hover spawn** = `SpawnHint` (Shared) si `tiles==0`. Serveur = `claimSpawn` (N52+N55).
- **Réplication :** StateDelta (`dirtyIndexBuf` N72, HUD fronts N74 via N76, `buildPrices` N75, records stats N76, `eraProgress` N77) / UnitSnapshot (`retreating`, `boatSnapBuf` N70, `missileSnapBuf` N71) / BuildingDelta (`buildingSnapBuf` N73) / plunder / trade / explosions / notify&sfx déployés / Diplomacy.viewFor 1 Hz (N78). `path` / `homeTile` / `progress` **non** répliqués. Playing 10 Hz ; lobby vide et ended → 1 Hz. `Diplomacy.step` recycle `expiredBuf` (**N79**). `Bots.neighborFactions` recycle `contactBuf` (**N80**). `gatherSites` recycle `siteBuf` (**N81**). `stepElimination` recycle `elimBuf` (**N82**). `findSeaPath` walk scratch, retour unique (**N83**). `refreshRailNetwork` porteuses recyclées (**N84**). `Buildings.contextFor` recycle `ctxBuf` (**N85**). `ChantierB.cancelOpposingFronts` / wrap `stepAttacks` recyclent `doomedBuf` / `collapsingBuf` (**N86**). `BoatFront.launchAttack` recycle `parkedBuf` (**N87**). `collapseFaction` recycle `collapseRemainBuf` / `collapseLeftBuf` (**N88**). `removePlayer` recycle `destroyBuf` (**N89**). `Placement.validTiles` recycle blockers/candidates/queue (**N90**). `Bots.decideDiplomacy` recycle `allyBuf` (**N91**). `PlacementPreview.resolve` recycle `previewCtx` (**N92**). `stepDoomsday` recycle `stripBuf` (**N93**). `stripTerritory` `table.clear` in-place (**N94**). `WorldRenderer.applyDelta` recycle `gainBuf`/`lossBuf`/`otherBuf` (**N95**). `FactionLabels.surveyTerritories` recycle `sumXBuf`/`countBuf` (**N96**). `HUD.update` recycle `self.ranked` (**N97**). `Overlay.applyUnits` hisse `trackUnit`, extra missile muté (**N98**). `init.client` hisse `previewOwnerAt`/`previewBuildingAt` (**N99**). `HUD.update` hisse `rankByTiles` (**N100**). Overlay `unit.target = Vector2.new` encore 10 Hz (**N101**). `buildChunkBorders` alloue encore `ownerOf`/`emit`/`passes` par chunk sale (**N102**). `else {}` overlay-nil hors passe. N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N101–N102)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N100 = faits. N22 = **N67 fait**. N27 = doc only. **V51 / N92** (Preview ctx) déjà fermé. **V50 / N97**, **V52 / N98**, **V53 / N99**, **V54 / N100** fermés ici (portés, pas mergés).

---

### ISSUE-N101 — `Overlay.applyUnits` `Vector2.new` cible 10 Hz (feel)

**Priorité :** P3 alloc client 10 Hz. Leftover explicite de N98 (`trackUnit`) et de N100 (`rankByTiles`). Distinct de N98 (extra muté déjà) et de visual V55 (spec ouverte sur `e3ed` — **porter, ne pas merger**). Ne pas toucher HUD sort (N100) ni `init.client` (N99). `CFrame` / `Vector3` 60 Hz = hors cette passe.

**Problème :** N98 hisse `trackUnit` et mute `extra`, mais `unit.target = Vector2.new(x, y)` alloue **un Vector2 par unité, à chaque lot** (insert **et** update, 10 Hz). Vector2 Roblox est immuable : on ne peut pas muter `target.X`. `stepInterpolation` fait `unit.current += (unit.target - unit.current) * alpha` puis lit `.X` / `.Y`. Distinct de N98 (`track` / extra), de N70/N71 (payload serveur) et du 60 Hz `CFrame.lookAt`.

**Pourquoi 20K CCU :** leftover N100. 8 clients × 10 Hz × (navires + missiles en vol) × 1 Vector2. Pas d’autorité (interpolation cosmétique). Changer la représentation sans adapter `stepInterpolation` casserait la cloche missile.

**Worker :**

1. Sur le record unité : `targetX` / `targetY` nombres. Insert : poser une fois. Update : muter les nombres, **plus** de `Vector2.new` sur le chemin update. `current` peut rester Vector2 **ou** passer en `currentX`/`currentY` dans le **même** commit que `stepInterpolation` (sinon lerp cassé). Pas de RemoteFunction.
2. `stepInterpolation` : lerp numérique, puis `WorldSpace.tileToWorld` comme aujourd’hui. Extra missile **inchangé** (N98). Ne pas porter HUD `rankByTiles` (N100 déjà) ni hover (N99 déjà) ni `buildChunkBorders` (N102). Après N100. Recette visual V55.
3. Ne **pas** recycler `CFrame.lookAt` / `Vector3.new` au 60 Hz (hors passe). Ne pas retoucher `snapshotBoats` / `snapshotMissiles` serveur. Ne pas éditer `HUD.luau` ni `init.client.luau`.
4. Test : banc client « navires, missiles et interpolation » **doit rester vert** (pieces, Name, extra `rawequal`, navire `extra == nil`, `applyUnits({}, {})` détruit). Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
5. Fichiers : `Overlay.luau` (`trackUnit` / `stepInterpolation` seulement). `tests/client.luau` **seulement si** un assert dans le check existant (ne **pas** ajouter un 36e). `UnitModels.luau` **non**. `HUD.luau` **non**. **Ne pas** éditer le serveur ni visual `e3ed`.

**Contraintes :** pas de RemoteFunction. Recette visual V55 (nombres mutés, pas de table). **N101 feel ≠ N98 (`trackUnit` / extra) ≠ N100 (`rankByTiles`) ≠ N70/N71 (payload) ≠ visual V55 (spec ouverte sur `e3ed`) ≠ CFrame 60 Hz.** Non réentrant. Un leftover `current` Vector2 + `target` nombres sans adapter le lerp casserait l’interpolation. Ne pas fusionner avec N98 (extra) dans le même worker si N98 est déjà mergé ici.

---

### ISSUE-N102 — `WorldRenderer.buildChunkBorders` ownerOf/emit/`BORDER_PASSES` (feel)

**Priorité :** P3 alloc client par chunk sale. Leftover explicite de N95 (`gainBuf`) et de N101 (Vector2). Distinct de N95 (listes applyDelta) et de N100 (`rankByTiles`). Ne pas toucher Overlay Vector2 (N101) ni HUD (N100). Visual n’a **pas** encore ce hoist — recette N85 (`ctxState` + closures module).

**Problème :** chaque `buildChunkBorders` alloue deux closures (`ownerOf`, `emit`) et une table `passes` de 4 records. Un tick d’offensive salit des dizaines de chunks (budget 3 rebuilds / frame, file plus longue). `ownerOf` relit `self.terrain` / `self.owner` ; `emit` capture `folder` / `surface`. Distinct de N95 (gains/losses arrays) et du greedy mesh sol.

**Pourquoi 20K CCU :** leftover N101. 8 clients × chunks sales × 2 closures + 1 table. Pas d’autorité (voile politique cosmétique). Un `ownerOf` qui lirait le `self` d’un rebuild précédent colorerait la frontière du voisin.

**Worker :**

1. Hoister `ownerOf` / `emit` en fonctions module. Poser `borderTerrain` / `borderOwner` / `borderFolder` / `borderSurface` (upvalues module, recette N85 `ctxState`) **au début** de `buildChunkBorders`, les lire dans les closures. Constante module `BORDER_PASSES` = les quatre `{ dx, dy }` — plus de `local passes = { … }` par appel. Pas de RemoteFunction.
2. Ne **pas** changer la loi greedy (deux balayages, tour `innerTo+1`, `nil` mer/neutre, deux nations = deux lignes). Ne pas porter Overlay Vector2 (N101) ni HUD sort (N100). Après N101. Recette N85 (closures + state module), pas un hash de Parts.
3. Ne pas recycler les Parts frontière (hors passe). Ne pas toucher `applyDelta` / `gainBuf` (N95 déjà). Ne pas éditer `Overlay.luau` / `HUD.luau` / `init.client.luau`.
4. Test : bancs client « construction du monde 3D » et « deltas de terrain et conquetes classees » **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
5. Fichiers : `WorldRenderer.luau` (`buildChunkBorders` seulement). `tests/client.luau` **seulement si** un assert dans un check existant (ne **pas** ajouter un 36e). **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. Recette N85 (state + closures module). **N102 feel ≠ N95 (`gainBuf`) ≠ N101 (Vector2 Overlay) ≠ N100 (HUD sort) ≠ greedy mesh sol.** Non réentrant : un second `buildChunkBorders` **avant** la fin du premier (il n’y en a pas — synchrone) casserait `borderFolder`. Un leftover `self` d’un chunk précédent colorerait mal. Ne pas `table.clone` de `BORDER_PASSES`.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; records stats → **N76 fait** ; `eraProgress` → **N77 fait** ; bateaux → **N70 fait** ; missiles → **N71 fait** ; owner indices → **N72 fait** ; bâtiments → **N73 fait** ; HUD fronts → **N74 fait** ; viewFor → **N78 fait** ; listes effets client → **N95 fait** ; ranked → **N97 fait** ; units extra → **N98 fait** ; hover → **N99 fait** ; sort → **N100 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; `ChantierB` doomed/collapsing → **N86 fait** ; parked → **N87 fait** ; collapse remain → **N88 fait** ; destroyBuf → **N89 fait** ; validTiles → **N90 fait** ; allyBuf → **N91 fait** ; previewCtx → **N92 fait** ; stripBuf → **N93 fait** ; stripTerritory → **N94 fait** ; gainBuf → **N95 fait** ; surveyTerritories → **N96 fait** ; ranked → **N97 fait** ; trackUnit → **N98 fait** ; hover → **N99 fait** ; rankByTiles → **N100 fait**) |
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
| N21 | QuickChat 2-args | P3 | **fait** passe 5 |
| N22 | Warships O(carriers × boats) | P2 | **fait** passe 19 (**N67**) |
| N23 | `retreatAttack` premier front | P2 | **fait** passe 5 |
| N24 | notify/sfx `FireAllClients` | P2 | **fait** passe 5 |
| N25 | `MAX_BOATS_PER_PLAYER` 6 vs 3 | P3 | ouvert |
| N26 | SAM chance 0.55 vs 1.0 | P1 | **fait** Config=1.0 |
| N27 | Embargo land trade | P2 | **doc** maritime-only |
| N28 | `RequestSnapshot` mort client | P2 | ouvert (serveur rate-limite ; client n’envoie jamais) |
| N29 | Seq commitée avant apply | P3 | **fait** passe 9 |
| N30 | Stub `seedBeachhead` faux | P3 | **fait** `error(...)` |
| N31 | Scan bunkers O(B) | P1 | **fait** passe 10 (N42) |
| N32 | `viewFor` requests expirées | P3 | **fait** |
| N33 | `BOAT_LANDING_BONUS` mort | P2 | ouvert |
| N34–N98 | (voir rapport #106) | — | **faits** |
| N99 | `init.client` closures hover 60 Hz | P3 | **fait** cette passe (`previewOwnerAt`/`previewBuildingAt`, recette visual V53) |
| N100 | `HUD.update` comparateur `table.sort` | P3 | **fait** cette passe (`rankByTiles` module, recette visual V54) |
| N101 | Overlay `Vector2.new` cible 10 Hz | P3 | **nouveau** (`targetX`/`targetY` mutés, recette visual V55) |
| N102 | `buildChunkBorders` ownerOf/emit/`BORDER_PASSES` | P3 | **nouveau** (closures module + constante, recette N85) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 `NIGHTLY_REPORT.md` historique.

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
| `RAIL_RANGE` | 56 | n/a | oui (N84, tri + union-find inchangés) |
| `COLLAPSE_MIN_TILES` | 100 | 100 | oui (N86 wrap, N88 scan) |
| `BUILD_SNAP_RADIUS` | (Config) | n/a | oui (N90 BFS) |
| `BUILD_MIN_SPACING` | (Config) | n/a | oui (N90 blockers) |
| `COALITION_MIN_LEADER_TILES` | 250 | n/a | oui (N91 `dominantLeader`) |
| `SPAWN_RADIUS` | 3 | n/a | oui (N93 banc `keep=8`, N94 strip, N55 isolation) |
| `DOOMSDAY.WARN_SECONDS` | 20 | n/a | oui (N93 rot, N9 scan) |
| `DOOMSDAY.ROT_DEATH_SECONDS` | 90 | n/a | oui (`rotQuota` inchangé) |

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
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.33 p95TickMs=0.73
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `identite, ere, diplomatie et classement` (N97 leftover 12→1 slot, `#ranked == 1`, N100 même loi tiles desc) et `accrochage du placement` / `apercu de placement` (N92+N99 resolve inchangé). `navires, missiles et interpolation` (N98 extra `tx` muté) reste vert. Overlay `previewTile(valid=false)` ne lève pas. Serveur **non** touché cette passe. `PlacementPreview.luau` **non** touché. `VictoryScreen.luau` **non** touché (copie `row.Text` tout de suite). `Overlay.luau` **non** touché (Vector2 = N101).

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass35.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N99/N100 sont des hoists client vérifiés par le banc headless.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N99 n’ajoute **pas** de require (`previewOwnerAt` vit dans `init.client`). N100 n’ajoute **pas** de require (`rankByTiles` vit dans HUD). N101 restera dans Overlay. N102 restera dans WorldRenderer.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N80 : `contactBuf` n’est pas réentrant. Les 4 appelants (`decideDiplomacy` ×2, `decideNavy`, `decideAttack`) lisent puis abandonnent avant le prochain appel — ne pas `table.clone`. Slot 99 / sans joueur = map **vide**. Ne pas fusionner avec `allyBuf` (N91) : contacts = tuiles, allies = clés `state.alliances[slot]`.

Piège N85 : `ctxBuf` / `ctxState` ne sont pas réentrants. Ne **pas** `table.clone(ctxBuf)`. Ne pas toucher `PlacementPreview.luau` : le fantôme client a **son** ctx (**N92 fait**). GameState ne doit **pas** require Placement (cycle).

Piège N86 : `doomedBuf` / `collapsingBuf` / `collapseRecPool` ne sont pas réentrants. Distinct de N93 `stripBuf` (tuiles cadran) et de N8 (corps mort `GameState.stepAttacks` `local collapsing`).

Piège N89 : `destroyBuf` n’est pas réentrant et est **partagé entre toutes les instances** `GameState`. Distinct de N93 (tuiles rot) et de N94 (hashes spawn).

Piège N90 : `blockBuf` / `candBuf` / `queueBuf` / `visitBuf` / `emptyTileBuf` ne sont pas réentrants. Retourner `candBuf` (pas `table.clone`). Ne pas toucher `PlacementPreview` (N92 déjà).

Piège N91 : `allyBuf` n’est pas réentrant. `Bots.step` est séquentiel : un second `table.clear` au bot suivant est **voulu**. Copier les **clés** de `state.alliances[slot]`, pas itérer `state.alliances` global ni `state.players` (visual V42 fill via `areAllied` — **ne pas** porter ce fill). Garder `if not areAllied then continue` dans la boucle trahison (un pacte périmé peut encore être une clé). Ne pas `table.clone` de `state.alliances[slot]` (`breakAlliance` mute le hash live). Ne pas toucher `contactBuf` / `siteBuf` / `acceptChance` / `COALITION_*`. Overlay n’itère pas `allyBuf`. Un leftover sans `table.clear` ferait `breakAlliance` fantôme du bot précédent. `decideChat` itère encore `state.alliances[slot]` avec garde `if allies then` — **hors scope**.

Piège N92 : `previewCtx` n’est pas réentrant. `resolve` est synchrone (Heartbeat → `update` après). Réécrire **les six champs** à chaque hover, y compris `ownerAt` / `buildingAt` (une capture entre deux hovers doit recolorer). Ne **pas** `table.clone`. Ne pas cacher « ctx inchangé ». Ne pas fusionner avec `ctxBuf` Buildings (le client n’a pas de `GameState`). Ne pas retourner `candBuf` au HUD (`resolve` lit `tiles[1]` tout de suite). `setKind` / `update` / footprint inchangés. Un `ownerAt` du hover précédent ferait un fantôme vert chez le voisin.

Piège N93 : `stripBuf` n’est pas réentrant. Truncate leftover **avant** l’arrachage **et** à 0 **après** le slot (deuxième camp du même tick). Ne pas `table.clear` (array + `#`). Ne pas fermer N9 (scan carte). Ne pas skip `awaitingSpawn`. Banc feel : `keep=8` (`SPAWN_RADIUS=3`) — ne pas copier visual `shrinkTo 40` tel quel (disque visuel plus large). `ChantierB.stripBuf` exposé banc, pas de filaire. Un leftover sans truncate entre slots ferait `setOwner` d’une tuile du camp précédent.

Piège N94 : `table.clear(ps.border)` in-place. Ne **jamais** partager un `emptyBorderBuf` module — `setOwner` / `claimSpawn` muteraient tous les joueurs strippés. `rawequal` avant/après est la loi du banc. Ne pas `ps.border = nil` (les appelants itèrent la hash). Distinct de N93 (`stripBuf` array d’indices du rot).

Piège N95 : `gainBuf` / `lossBuf` / `otherBuf` ne sont pas réentrants. Trois bufs **séparés** (les trois listes vivent dans la même frame). Truncate leftover **avant** return. Early-out `count == 0` → pools vides, pas `{}`. `Effects.conquestWave` / `lossWave` itèrent tout de suite — ne pas cloner. Ne pas fusionner avec `dirtyIndexBuf` (serveur). Un leftover sans truncate rejouerait un splash. `Effects.lossWave` divise par `#conquests` : un leftover fausserait le barycentre.

Piège N96 : `sumXBuf` / `sumYBuf` / `countBuf` sont des **hash** (`table.clear`, pas truncate `#`). Un leftover sans clear afficherait une étiquette pour un slot éliminé. Ne pas fusionner avec N95 (arrays de tuiles) ni N80 (`contactBuf` serveur). Overlay n’itère pas ces hashes.

Piège N97 : `self.ranked` **est stocké**. Muter les records in-place, truncate **avant** sort. Ne pas `table.insert`. Ne pas remplacer `self.ranked` par une nouvelle table. Un leftover non truncaté ferait une ligne fantôme dans `VictoryScreen.show`. Distinct de N76 (records stats serveur). `VictoryScreen.show` copie `row.Text` tout de suite — il ne stocke pas l’identité du record.

Piège N98 : `trackUnit` n’est pas réentrant. Extra missile : allouer `{tx,ty}` **seulement** à l’insert (ou si `unit.extra` nil) ; ensuite muter les champs. Navire : `extra` **nil** — ne pas recréer `{ retreating = … }` 10 Hz (`retreatTinted` suffit, N56). Ne pas changer `Vector2` current/target (**N101**). Un leftover extra d’un id recyclé viserait un `tx/ty` fantôme. Distinct de N70/N71 (payload serveur, feel **avec** `retreating`).

Piège N99 : hoister les deux closures dans `init.client`, capturer `world`/`overlay` module (pas les locals `w`/`o` de la frame). Overlay nil → owner 0 / building nil. Ne pas toucher `previewCtx` (N92). Ne pas toucher SpawnHint hover attaque. Recette visual V53 déjà sur `36bc` — porter, ne pas merger. `init.client` n’est pas un `require` du banc : les checks Preview restent la preuve.

Piège N100 : hoister `rankByTiles` au module HUD. Même loi tiles desc / troupes tie-break. Ne pas retoucher les records N97. Ne pas porter Vector2 Overlay (N101). Recette visual V54 déjà sur `e3ed` — porter, ne pas merger. Un leftover non truncaté ferait toujours une ligne fantôme — N97 déjà.

Piège N101 (à venir) : muter `targetX`/`targetY` nombres. Adapter `stepInterpolation` dans le **même** commit. Extra missile inchangé (N98). Recette visual V55 (spec sur `e3ed`).

Piège N102 (à venir) : poser `borderTerrain` / `borderOwner` / `borderFolder` / `borderSurface` au début de `buildChunkBorders`. `BORDER_PASSES` constante module. Ne pas changer la loi greedy. Recette N85.
