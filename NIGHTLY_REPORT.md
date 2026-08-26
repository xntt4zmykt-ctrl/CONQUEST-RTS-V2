# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 44)

Déclencheur : ouverture de la **PR #133** (`cursor/analyse-nocturne-du-codebase-ab04`) — Overlay `segRot` camion, unités immobile, specs N117–N118.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-bec6`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#135.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. Unités en mouvement : `CFrame.new(worldX, py, worldZ) * CFrame.fromEulerAnglesYXZ(0, atan2(dx, -dy), 0)` (N117). Camera overview : `CFrame.new(ex, ey, ez) * rotation` (N118) ; le biais `lookAt(..., focus + shake * 0.18)` est abandonné (shake sur l’œil seulement). `segRot` camion (N115), immobile `CFrame.new` (N116), rot chantier (N113) et compact dirty (N114) restent.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #133 (passe 43) : claims vérifiés.** `route.segRot` cuit, `CFrame.new * segRot` (N115) ; unités `mag <= 0.01` : `CFrame.new` (N116). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #133 a documenté (N117, N118)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #133

| Claim #133 | Réalité à l’ouverture |
|---|---|
| Overlay camion `segRot` (N115) | Oui. `buildFactoryRoute` cuit `route.segRot[i]`. Hot path : `CFrame.new(px, py, pz) * route.segRot[segmentIndex]`. Plus de lookAt 60 Hz camion. Recette visual V64, pas merger `3062`. |
| Overlay unités immobile (N116) | Oui. `mag <= 0.01` : `CFrame.new(worldX, py, worldZ)`. Mouvement : lookAt conservé (leftover N117). |
| Specs N117–N118 | **Corrigés ici.** N117 = `CFrame.new * fromEulerAnglesYXZ` (recette visual V65 déjà fermée sur `dc65` / PR #132 — **porté, pas mergé**). N118 = `CFrame.new(ex,ey,ez) * rotation` (recette visual V66 déjà fermée sur `926d` / PR #134 — **porté, pas mergé** ; shake Vector3 **conservé** cette passe, leftover N119). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #135 (`e9e5` N93–N94), feel jusqu’à #133, visuelles #39/…/#134 (`926d` V66 camera lookAt **fermé** + leftover V67 offset). **#133 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#135) reste distincte. Ne pas merger visual `926d` / `dc65` ni hardening `e9e5` / `e488` sans rebase.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N117–N118 du rapport #133.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Overlay unités lookAt deux Vector3 60 Hz en mouvement (N117) | `Overlay.luau` (branche `mag > 0.01` de la boucle `self.units` de `stepInterpolation`), `tests/client.luau` (asserts dans le check navires existant) | Leftover N116. `CFrame.new * fromEulerAnglesYXZ(0, atan2(dx, -dy), 0)`. Plus de lookAt deux Vector3. Immobile `CFrame.new` **inchangé** (N116). Roulis `CFrame.Angles` **après** la compose yaw, **inchangé**. Recette visual V65 déjà sur `dc65`, **pas** merger. Cosmétique. 0 unité en mouvement → zéro alloc (déjà `CFrame.new` N116). |
| WorldCamera.step lookAt deux Vector3 60 Hz (N118) | `WorldCamera.luau` (`step` overview), `tests/client.luau` (asserts dans le check camera existant) | Leftover Overlay. Œil en nombres `ex, ey, ez` ; pose `CFrame.new(ex, ey, ez) * rotation`. Biais `shake * 0.18` abandonné (documenté). `Vector3.new` offset/shake **restent** (leftover N119 / N120). Recette visual V66 déjà sur `926d` (visual a aussi fermé shake — **ne pas** porter shake ici). Cosmétique. Hors overview → early-out déjà. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), offset camera Vector3 (**N120**), shake camera Vector3 (**N119**). `PlacementPreview.resolve` ctx déjà **N92**. `self.ranked` inner déjà **N97**. Overlay `trackUnit` extra déjà **N98**. Hover déjà **N99**. `rankByTiles` déjà **N100**. `targetX` déjà **N101**. `BORDER_PASSES` déjà **N102**. lookAt unités unique déjà **N103**. `meshKeyAt` déjà **N104**. Camion lerp déjà **N105**. Parts Ground déjà **N106**. Houle déjà **N107**. Feuillage déjà **N108**. Câble déjà **N109**. Lift déjà **N110**. Nombres déjà **N111**. `dirtyHead` déjà **N112**. Rot chantier déjà **N113**. Compact déjà **N114**. Camion `segRot` déjà **N115**. Unités immobile déjà **N116**. `else {}` overlay-nil hors passe.

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
- Overlay `stepInterpolation` X/Z monde + yaw euler unités en mouvement (**N117**) **et** camion lerp (**N105**) + `segRot` (**N115**). Immobile `CFrame.new` (**N116**). `rebuildChunk` hisse `meshKeyAt` (**N104**) et recycle Ground/Border par chunk (**N106**). Houle océan (**N107**) et feuillage (**N108**) = nombres + un `CFrame.new`. Câble PORT (**N109**) = nombres + un `CFrame.new`. Lift voie (**N110**) cuit dans `layer.origin`. Arithmétique `origin + direction * t` **fermée** (**N111**). `table.remove(dirtyQueue, 1)` **fermé** (**N112**). LookAt chantier **fermé** (**N113**). Compact préfixe `dirtyQueue` **fermé** (**N114**). LookAt camion **fermé** (**N115**). LookAt unités immobile **fermé** (**N116**). LookAt unités en mouvement **fermé** (**N117**). LookAt camera **fermé** (**N118**). Shake camera Vector3 encore 60 Hz (**N119**). Offset camera `Vector3.new(0,0,distance)` encore 60 Hz (**N120**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N119–N120)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N118 = faits. N22 = **N67 fait**. N27 = doc only. **V65 / N117** fermés ici (portés, pas mergés ; V65 déjà livré visuel `dc65`). **V66 / N118** fermés ici (portés, pas mergés ; V66 déjà livré visuel `926d` **avec** shake nombres — feel garde Vector3 shake, leftover **N119**). **V67** ouvert visuel — leftover feel = **N120**.

---

### ISSUE-N119 — WorldCamera.step shake `Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client camera. Leftover explicite de N118 (pose `CFrame.new * rotation` déjà). Distinct de N118 (lookAt déjà), de N120 (offset `(0,0,distance)`), de N117 (unités Overlay). Recette visual V66 **fermée** sur `926d` (passe 49 visual) a **déjà** posé `sx/sy/sz` en nombres — **porter les trois lignes shake, ne pas merger** `926d`. Ne pas toucher Overlay ni WorldRenderer.

**Problème :** N118 coupe le lookAt. Reste, **chaque frame overview** : `Vector3.new(sin(clock*31)*shake*0.65, cos(clock*37)*shake*0.42, sin(clock*23)*shake*0.5)` puis `.X/.Y/.Z` pour l’œil. Un Vector3 par frame **en plus** de l’offset leftover N120. Les coeffs 0.65 / 0.42 / 0.5 et les fréquences 31 / 37 / 23 sont la signature du tremblement. Distinct de N118 (compose déjà), de N120 (offset local).

**Pourquoi 20K CCU :** leftover N118. 8 clients × 60 Hz × 1 Vector3 shake. Pas d’autorité (cosmétique). Changer un coeff ferait dériver le kick visuel vs Studio. `shake == 0` → zéros, alloc quand même tant que `Vector3.new` reste.

**Worker :**

1. Dans `WorldCamera.step` seulement, après `rotation` / `offset` : remplacer le `Vector3.new` shake par `sx = math.sin(self.clock * 31) * self.shake * 0.65`, `sy = math.cos(self.clock * 37) * self.shake * 0.42`, `sz = math.sin(self.clock * 23) * self.shake * 0.5`. Œil : `ex = self.focus.X + offset.X + sx` (idem Y/Z). Pose **inchangée** : `CFrame.new(ex, ey, ez) * rotation` (N118). Offset `VectorToWorldSpace(Vector3.new(0, 0, distance))` **inchangé** (leftover N120). FOV / lissage / `stepInput` **inchangés**. Overlay unités / camion / chantier **inchangés** (N117 / N116 / N115 / N113).
2. Ne **pas** éditer `Overlay.luau` / `WorldRenderer.luau` / `UnitModels.luau` / `HUD.luau` / `BuildingModels.luau`. Ne pas porter N120 (offset trig) dans ce worker. Après N118. Recette visual V66 déjà sur `926d` (shake nombres **dans** V66) — porter `sx/sy/sz`, pas merger visual `926d` / `dc65`.
3. Ne pas convertir Radar / Flag / Boom. Ne pas toucher `Camera.ViewportPointToRay`. Ne pas changer MIN/MAX_DISTANCE. Ne pas « fermer » offset `(0,0,d)` (N120). Tests « camera strategique » et « camera tactile » **doivent rester verts**.
4. Test : banc client « camera strategique » **et** « camera tactile : panoramique, pincement et torsion » **doivent rester verts**. Leftover N118 (`CFrame.X` nombre) **et** leftover N117 (lerp missile sous yaw, navire immobile) **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
5. Fichiers : `WorldCamera.luau` (`step` overview seulement, bloc shake). `tests/client.luau` **seulement si** un assert dans le check camera existant (ne **pas** ajouter un 36e). `Overlay.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. Coeffs 0.65 / 0.42 / 0.5 et fréquences 31 / 37 / 23 **identiques**. **N119 feel ≠ N118 (lookAt déjà) ≠ N120 (offset) ≠ visual V66 (déjà livré visuel `926d` avec shake, ne pas merger).** Non réentrant. Ne pas fusionner avec N120 dans le même worker.

---

### ISSUE-N120 — WorldCamera.step offset `Vector3.new(0, 0, distance)` 60 Hz (feel)

**Priorité :** P3 alloc client camera. Leftover explicite après N118/N119. Distinct de N119 (shake nombres) et de N118 (pose lookAt). Recette visual V67 **ouverte** (leftover après V66). `WorldCamera.step` overview seulement. Ne pas toucher Overlay ni WorldRenderer.

**Problème :** N118/N119 ferment lookAt + shake. Reste, **chaque frame overview** : `rotation:VectorToWorldSpace(Vector3.new(0, 0, self.distance))`. Un Vector3 d’entrée + un Vector3 de sortie (API). `rotation = CFrame.fromEulerAnglesYXZ(-self.pitch, self.yaw, 0)` **existe déjà** et doit rester (compose N118). `fromEulerAnglesYXZ(-pitch, yaw, 0):VectorToWorldSpace((0,0,d))` ≡

```
ox = d * math.cos(pitch) * math.sin(yaw)
oy = d * math.sin(pitch)
oz = d * math.cos(pitch) * math.cos(yaw)
```

(YXZ, `rz=0`. Vérifier : pitch=0 yaw=0 → `(0,0,d)` ; pitch=`π/2` yaw=0 → `(0,d,0)` ; pitch=0 yaw=`π/2` → `(d,0,0)`.) Distinct de N119 (shake), de N118 (pose).

**Pourquoi 20K CCU :** leftover N118. 8 clients × 60 Hz × 2 Vector3. Pas d’autorité (offset cosmétique). Un yaw/pitch faux casserait le cap stratégique et le pincement tactile. Hors overview → early-out déjà.

**Worker :**

1. Dans `WorldCamera.step` seulement (branche `mode == "overview"`) : garder `rotation = CFrame.fromEulerAnglesYXZ(-self.pitch, self.yaw, 0)`. Calculer `ox/oy/oz` en nombres (formule ci-dessus, `d = self.distance`). `ex = self.focus.X + ox + sx` (idem Y/Z) — si N119 n’est pas encore passé, `sx = shake.X` (Vector3 leftover). Pose **inchangée** : `CFrame.new(ex, ey, ez) * rotation` (N118). Plus de `Vector3.new(0, 0, self.distance)` ni `VectorToWorldSpace` 60 Hz. Shake **inchangé** (N119 leftover ou déjà nombres). FOV / lissage **inchangés**. Overlay unités / camion **inchangés** (N117 / N115).
2. Ne **pas** éditer `Overlay.luau` / `WorldRenderer.luau` / `UnitModels.luau` / `HUD.luau` / `BuildingModels.luau`. Ne pas porter N119 (shake nombres) dans ce worker si N119 est un autre agent. Après N118. Recette visual V67 ouverte — porter trig, pas merger visual `926d`.
3. Ne pas « fermer » `self.focus += (target - focus) * alpha` (lerp Vector3 — leftover, événement de lissage natif). Ne pas « fermer » pan/clamp Vector3 (gestes, pas 60 Hz idle). Ne pas changer MIN/MAX_DISTANCE. Vérifier les trois identités trig ci-dessus.
4. Test : banc client « camera strategique » **et** « camera tactile » **doivent rester verts**. Overview stub : VectorToWorldSpace identité dans `guistubs` renvoyait `(0,0,d)` — après trig, yaw=0 pitch=58° **n’est plus** `(0,0,d)` en Studio, mais le stub `fromEulerAnglesYXZ` ignore les angles : `ox/oy/oz` nombres ne cassent pas `CFrame.X` (compose `__mul` = translation). Ne **pas** assert `Z == focus.Z + distance` (ce serait un assert visual 34/34, pas feel 35/35). Leftover N118 / N117 / N116 **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
5. Fichiers : `WorldCamera.luau` (`step` overview seulement). `tests/client.luau` **seulement si** un assert dans le check camera existant (ne **pas** ajouter un 36e). `Overlay.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. Formule YXZ `rz=0` ci-dessus. **N120 feel ≠ N119 (shake) ≠ N118 (lookAt déjà) ≠ visual V67 (si livré visuel, ne pas merger).** Non réentrant. Ne pas fusionner avec N119 dans le même worker.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; lookAt unités mouvement → **N117 fait** ; camera lookAt → **N118 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; lookAt unités mouvement → **N117 fait** ; camera lookAt → **N118 fait**) |
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
| N34–N116 | (voir rapport #133) | — | **faits** |
| N117 | Overlay unités lookAt en mouvement | P3 | **fait** cette passe (`fromEulerAnglesYXZ`, recette visual V65) |
| N118 | WorldCamera.step lookAt deux Vector3 60 Hz | P3 | **fait** cette passe (`CFrame.new * rotation`, recette visual V66 pose ; shake Vector3 **conservé**) |
| N119 | WorldCamera.step shake `Vector3.new` 60 Hz | P3 | **nouveau** (`sx/sy/sz` nombres, recette visual V66 leftover shake, ne pas merger `926d`) |
| N120 | WorldCamera.step offset `Vector3.new(0,0,distance)` 60 Hz | P3 | **nouveau** (trig YXZ, recette visual V67 ouverte) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde, N103 X/Z, N105 TRUCK_LIFT monde, N115 segRot HV, N117 yaw tuile) |

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

Client : **35/35 OK** — dont `construction du monde 3D` (N114 compact leftover, N112 `dirtyHead`, N106/N107/N108) ; `pose et capture de chaque type de batiment` (N115 `segRot` leftover, N113 `rot` chantier) ; `navires, missiles et interpolation` (N117 second frame lerp sous yaw euler ; leftover N116 navire immobile `currentX == targetX` ; leftover N103 lerp missile, N98 extra `rawequal`, N101 `targetX`, navire `extra == nil`, `retreatTinted` conservé) ; `camera strategique` (N118 `CFrame.X` nombre, leftover tactile pincement/torsion). `livraison : le gain s'affiche sur la gare` inchangé. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `init.client.luau` **non** touché. `BuildingModels.luau` **non** touché. `PlacementPreview.luau` **non** touché. `UnitModels.luau` **non** touché. `WorldRenderer.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass44.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N117/N118 sont un hoist d’orientation / compose camera vérifiés par le banc headless.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N117 n’ajoute **pas** de require (`fromEulerAnglesYXZ` local Overlay). N118 n’ajoute **pas** de require (`CFrame.new * rotation` local WorldCamera). N119 restera dans `WorldCamera.step` shake. N120 restera dans `WorldCamera.step` offset.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N117 : `fromEulerAnglesYXZ(0, atan2(dx, -dy), 0)` — `dy` tuile = monde Z. Compose **après** `CFrame.new`, **avant** le roulis navire. Recette visual V65 déjà sur `dc65` — porter, ne pas merger. Immobile reste `CFrame.new` (N116), pas `atan2(0, 1)`. Ne pas merger visual.

Piège N118 : `CFrame.new(ex,ey,ez) * rotation` déjà calculée. Abandonner le biais `lookAt(..., focus + shake * 0.18)` (cosmétique, documenté). Ne pas « fermer » `Vector3.new` shake ni offset dans la même passe. Recette visual V66 déjà sur `926d` **inclut** shake nombres — feel N118 **ne porte pas** shake (leftover N119). Ne pas merger visual.

Piège N119 (à venir) : coeffs 0.65 / 0.42 / 0.5 et fréquences 31 / 37 / 23 **identiques**. Porter `sx/sy/sz` de visual V66, pas merger `926d`. Ne pas fermer offset.

Piège N120 (à venir) : trig YXZ `ox = d*cos(pitch)*sin(yaw)` etc. Pitch feel défaut `math.rad(58)` ≠ 0 : l’œil n’est plus à `focus.Z + distance`. Ne pas assert `Z == focus.Z + distance` (assert visual stub). Ne pas merger visual V67.
