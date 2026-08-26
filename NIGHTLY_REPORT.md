# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 45)

Déclencheur : ouverture de la **PR #136** (`cursor/analyse-nocturne-du-codebase-bec6`) — Overlay yaw unités, WorldCamera compose, specs N119–N120.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-b19e`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#138.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. Unités en mouvement : `CFrame.new(worldX, py, worldZ) * CFrame.fromEulerAnglesYXZ(0, atan2(dx, -dy), 0)` (N117). Camera overview : `CFrame.new(ex, ey, ez) * rotation` (N118) ; shake `sx/sy/sz` nombres (N119) ; offset YXZ `ox/oy/oz` nombres (N120). `segRot` camion (N115), immobile `CFrame.new` (N116), rot chantier (N113) et compact dirty (N114) restent.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #136 (passe 44) : claims vérifiés.** Overlay yaw euler (N117) ; camera pose `CFrame.new * rotation` (N118). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #136 a documenté (N119, N120)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #136

| Claim #136 | Réalité à l’ouverture |
|---|---|
| Overlay unités yaw (N117) | Oui. `mag > 0.01` : `CFrame.new * fromEulerAnglesYXZ(0, atan2(dx, -dy), 0)`. Immobile `CFrame.new` (N116). Recette visual V65, pas merger `dc65`. |
| WorldCamera compose (N118) | Oui. Œil en nombres ; pose `CFrame.new(ex, ey, ez) * rotation`. Biais lookAt shake 18 % abandonné. Shake/offset Vector3 leftover N119/N120. Recette visual V66 pose, pas merger `926d`. |
| Specs N119–N120 | **Corrigés ici.** N119 = `sx/sy/sz` nombres (recette visual V66 leftover shake déjà fermée sur `926d` / PR #134 — **porté, pas mergé**). N120 = offset trig YXZ (recette visual V67 déjà fermée sur `b2f1` — **porté, pas mergé** ; lerp `focus` Vector3 **conservé** cette passe, leftover N121 = recette visual V68 déjà fermée sur `0231`, ne pas merger). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #138 (`2c0f` N95–N96), feel jusqu’à #136, visuelles #39/…/`b2f1` V67 offset **fermé** ; `0231` V68 lerp **fermé** + leftover V69 champ `focusX/Y/Z`. **#136 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#138) reste distincte. Ne pas merger visual `0231` / `b2f1` / `926d` ni hardening `2c0f` / `e9e5` sans rebase.

**Revue autorité (sous-agent isolé) :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. Risques documentés, non corrigés ici (hors N119/N120) : `IntentValidator.flush` contournerait enqueue si la queue vivait ; `JoinRequest` hors IntentValidator ; Persistence `math.max` perd les +1 concurrents (N6).

**Revue combat/éco (sous-agent isolé) :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N119–N120 du rapport #136. Commits séparés (N119 puis N120).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| WorldCamera.step shake `Vector3.new` 60 Hz (N119) | `WorldCamera.luau` (`step` overview, bloc shake), `tests/client.luau` (asserts dans le check camera existant) | Leftover N118. `sx/sy/sz` nombres. Coeffs 0.65 / 0.42 / 0.5 et fréquences 31 / 37 / 23 **identiques**. Pose `CFrame.new * rotation` **inchangée** (N118). Offset `VectorToWorldSpace` **fermé ensuite** (N120, commit suivant). Recette visual V66 leftover shake déjà sur `926d`, **pas** merger. Cosmétique. `shake == 0` → zéros, plus d’alloc. |
| WorldCamera.step offset `Vector3.new(0,0,distance)` 60 Hz (N120) | `WorldCamera.luau` (`step` overview, bloc offset), `tests/client.luau` (formule à pitch défaut 58°) | Leftover N118/N119. `ox = d*cos(pitch)*sin(yaw)`, `oy = d*sin(pitch)`, `oz = d*cos(pitch)*cos(yaw)`. Plus de `VectorToWorldSpace`. Shake nombres **inchangé** (N119). Recette visual V67 déjà sur `b2f1`, **pas** merger. Cosmétique. Hors overview → early-out déjà. **Pas** d’assert `Z == focus.Z + distance` (assert visual 34/34, pas feel 35/35). |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), lerp `focus` Vector3 (**N121**), champ `focusX/Y/Z` (**N122**), tribus `humanTargetProtected`. `PlacementPreview.resolve` ctx déjà **N92**. `self.ranked` inner déjà **N97**. Overlay `trackUnit` extra déjà **N98**. Hover déjà **N99**. `rankByTiles` déjà **N100**. `targetX` déjà **N101**. `BORDER_PASSES` déjà **N102**. lookAt unités unique déjà **N103**. `meshKeyAt` déjà **N104**. Camion lerp déjà **N105**. Parts Ground déjà **N106**. Houle déjà **N107**. Feuillage déjà **N108**. Câble déjà **N109**. Lift déjà **N110**. Nombres déjà **N111**. `dirtyHead` déjà **N112**. Rot chantier déjà **N113**. Compact déjà **N114**. Camion `segRot` déjà **N115**. Unités immobile déjà **N116**. Yaw unités déjà **N117**. Compose camera déjà **N118**. `else {}` overlay-nil hors passe. Overlay / WorldRenderer / BuildingModels / HUD / UnitModels / serveur **non édités**.

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
- Overlay `stepInterpolation` X/Z monde + yaw euler unités en mouvement (**N117**) **et** camion lerp (**N105**) + `segRot` (**N115**). Immobile `CFrame.new` (**N116**). `rebuildChunk` hisse `meshKeyAt` (**N104**) et recycle Ground/Border par chunk (**N106**). Houle océan (**N107**) et feuillage (**N108**) = nombres + un `CFrame.new`. Câble PORT (**N109**) = nombres + un `CFrame.new`. Lift voie (**N110**) cuit dans `layer.origin`. Arithmétique `origin + direction * t` **fermée** (**N111**). `table.remove(dirtyQueue, 1)` **fermé** (**N112**). LookAt chantier **fermé** (**N113**). Compact préfixe `dirtyQueue` **fermé** (**N114**). LookAt camion **fermé** (**N115**). LookAt unités immobile **fermé** (**N116**). LookAt unités en mouvement **fermé** (**N117**). LookAt camera **fermé** (**N118**). Shake camera nombres **fermé** (**N119**). Offset camera trig **fermé** (**N120**). Lerp `focus` Vector3 encore 60 Hz (**N121**). `self.focus = Vector3.new` restant (**N122**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N121–N122)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N120 = faits. N22 = **N67 fait**. N27 = doc only. **V66 leftover shake / N119** fermés ici (portés, pas mergés ; V66 déjà livré visuel `926d`). **V67 / N120** fermés ici (portés, pas mergés ; V67 déjà livré visuel `b2f1`). **V68** déjà fermé visuel `0231` — leftover feel = **N121** (porter, ne pas merger). **V69** ouvert visuel — leftover feel = **N122**.

---

### ISSUE-N121 — WorldCamera.step lerp `focus` Vector3 60 Hz (feel)

**Priorité :** P3 alloc client camera. Leftover explicite de N120 (offset trig déjà). Distinct de N120 (offset `ox/oy/oz`), de N119 (shake), de N118 (pose). Recette visual V68 **fermée** sur `0231` (passe 51 visual) — **porter le lerp nombres, ne pas merger** `0231`. `WorldCamera.step` overview seulement. Ne pas toucher Overlay ni WorldRenderer.

**Problème :** N119/N120 ferment shake + offset. Reste, **chaque frame overview** : `self.focus += (self.targetFocus - self.focus) * alpha`. Trois Vector3 (sub, mul, add) même à l’idle. `distance` / `yaw` / `pitch` sont déjà des nombres. `targetFocus` reste un Vector3 (écrit aux gestes, pas 60 Hz idle). Distinct de N120 (offset local).

**Pourquoi 20K CCU :** leftover N120. 8 clients × 60 Hz × 3 Vector3. Pas d’autorité (lissage cosmétique). Un lerp faux casserait le cap stratégique et le pincement tactile (la mire ne rattraperait plus `targetFocus`).

**Worker :**

1. Dans `WorldCamera.step` seulement (branche `mode == "overview"`), après `alpha` :

```
local fx = self.focus.X + (self.targetFocus.X - self.focus.X) * alpha
local fy = self.focus.Y + (self.targetFocus.Y - self.focus.Y) * alpha
local fz = self.focus.Z + (self.targetFocus.Z - self.focus.Z) * alpha
self.focus = Vector3.new(fx, fy, fz)
```

Utiliser `fx/fy/fz` pour l’œil (`ex = fx + ox + sx`, idem Y/Z). Un seul `Vector3.new` (écriture du champ — `panByScreenDelta` / `clampFocus` / minimap lisent encore `self.focus`). Plus de `+=` / `-` / `*` Vector3 60 Hz. Offset `ox/oy/oz` **inchangé** (N120). Shake `sx/sy/sz` **inchangé** (N119). Pose `CFrame.new(ex, ey, ez) * rotation` **inchangée** (N118). Overlay unités / camion **inchangés** (N117 / N115). `alpha = 1 - math.exp(-12 * dt)` **inchangé**.

2. Ne **pas** éditer `Overlay.luau` / `WorldRenderer.luau` / `UnitModels.luau` / `HUD.luau` / `BuildingModels.luau`. Ne pas « fermer » le `Vector3.new` restant (leftover N122 : stocker `focusX/Y/Z`). Ne pas « fermer » pan/clamp Vector3 (gestes, pas 60 Hz idle). Ne pas splitter `targetFocus`. Après N120. Recette visual V68 déjà sur `0231` — porter `fx/fy/fz` + `ex = fx + ox + sx` (pas `self.focus.X` après le write), pas merger visual `0231` / `b2f1`.

3. Ne pas convertir Radar / Flag / Boom. Ne pas toucher `Camera.ViewportPointToRay`. Ne pas changer MIN/MAX_DISTANCE. Tests « camera strategique » et « camera tactile » **doivent rester verts**. Leftover N120 (formule `ox/oy/oz` à pitch 58°) **et** leftover N119 (punch + décroissance) **doivent rester verts**.

4. Test : banc client « camera strategique » **et** « camera tactile : panoramique, pincement et torsion » **doivent rester verts**. Ne **pas** assert `Z == focus.Z + distance` (assert visual 34/34, pas feel 35/35). Leftover N117 (lerp missile sous yaw, navire immobile) **doit rester vert**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `WorldCamera.luau` (`step` overview seulement, bloc lerp focus). `tests/client.luau` **seulement si** un assert dans le check camera existant (ne **pas** ajouter un 36e). `Overlay.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. **N121 feel ≠ N120 (offset déjà) ≠ N122 (champ nombres) ≠ visual V68 (déjà livré visuel `0231`, ne pas merger).** Non réentrant. Ne pas fusionner avec N122 dans le même worker. Œil : `ex = fx + ox + sx` (utiliser les locaux, pas `self.focus.X` après `Vector3.new`).

---

### ISSUE-N122 — WorldCamera.step `self.focus = Vector3.new` restant 60 Hz (feel)

**Priorité :** P3 alloc client camera. Leftover explicite après N121. Distinct de N121 (lerp nombres déjà, un Vector3 d’écriture). Recette visual V69 **ouverte** (leftover après V68). `WorldCamera.step` overview seulement. Ne pas toucher Overlay ni WorldRenderer.

**Problème :** N121 coupe le `+=` Vector3. Reste, **chaque frame overview** : `self.focus = Vector3.new(fx, fy, fz)` pour tenir l’API Vector3 (`clampFocus`, pan, minimap). Un Vector3 par frame idle. Distinct de N121 (arithmétique déjà), de N120 (offset), des gestes pan/clamp (pas 60 Hz idle).

**Pourquoi 20K CCU :** leftover N121. 8 clients × 60 Hz × 1 Vector3. Pas d’autorité. Stocker `focusX/Y/Z` (et garder `self.focus` reconstruit seulement aux lecteurs événementiels, ou exposer les scalaires) supprime l’alloc idle. Un split incomplet casserait `camera.focus.X` dans Overlay / Minimap / `tileAtScreen`.

**Worker :**

1. Dans `WorldCamera` : champs `focusX` / `focusY` / `focusZ` (nombres), initialisés comme `self.focus`. Dans `step` overview : lerp et œil **uniquement** via ces scalaires. Plus de `Vector3.new` 60 Hz idle. `self.focus` : soit reconstruit aux **lecteurs** (minimap, clamp, pan — événements), soit un getter. Ne pas splitter `targetFocus` (écrit aux gestes). Offset / shake / pose **inchangés** (N120 / N119 / N118). Overlay unités / camion **inchangés** (N117 / N115).

2. Ne **pas** éditer `Overlay.luau` / `WorldRenderer.luau` / `UnitModels.luau` / `HUD.luau` / `BuildingModels.luau` sauf si un lecteur `camera.focus` casse — alors adapter le lecteur à `.X/.Y/.Z` existants **sans** changer Overlay interpolation. Ne pas « fermer » pan/clamp Vector3 (gestes). Après N121. Recette visual V69 ouverte — porter champ nombres, pas merger visual.

3. Ne pas changer MIN/MAX_DISTANCE. Vérifier `focusTile` / `setDistance` / `punch` / toggleMode. Tests « camera strategique » (formule N120 + punch N119) **et** « camera tactile » **doivent rester verts**. `Minimap.setFocus` si appelé avec `camera.focus` doit rester Vector3.

4. Test : banc client « camera strategique » **et** « camera tactile » **doivent rester verts**. Leftover N120 / N119 / N117 / N116 **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `WorldCamera.luau` (champs + `step` overview). `tests/client.luau` **seulement si** un assert dans le check camera existant (ne **pas** ajouter un 36e). Lecteurs `camera.focus` seulement si le split casse le banc. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. **N122 feel ≠ N121 (lerp déjà) ≠ N120 (offset) ≠ visual V69 (si livré visuel, ne pas merger).** Non réentrant. Ne pas fusionner avec N121 dans le même worker.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; shake camera → **N119 fait** ; offset camera → **N120 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; shake camera → **N119 fait** ; offset camera → **N120 fait**) |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | ouvert |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 factions) | P1 | ouvert |
| N13 | Parité combat (ère / cost factor / constantes mortes) | P2 | ouvert |
| N14 | Apply immédiat vs lockstep (feel #19) | P1 | ouvert (produit) |
| N15 | `PREPARATION_DURATION=0` vs gardes `combatUnlocked` | P2 | ouvert |
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 | **N37+N42+N45 faits** ; path résultat → **N83 fait** |
| N17 | Humains éliminés occupent le cap | P2 | ouvert |
| N18 | Heap AimFront ≠ ChantierB / BoatFront | P2 | ouvert (frontier mixte mag vs TERRAIN_COST) |
| N19 | Embargo allié + tribus auto-accept | P2 | ouvert ; **tribus n’appellent pas `humanTargetProtected`** (écart feel vs hardening/visual — ne pas porter sans spec dédiée) |
| N20 | `railIncome` vs `deliveryValue` | P2 | **fait** `stopBonus` ; reste niveau live vs snapshot colis |
| N21–N24, N26, N29–N32 | (fermés passes 5–10) | — | **faits** |
| N25 | `MAX_BOATS_PER_PLAYER` 6 vs 3 | P3 | ouvert |
| N27 | Embargo land trade | P2 | **doc** maritime-only |
| N28 | `RequestSnapshot` mort client | P2 | ouvert (serveur rate-limite ; client n’envoie jamais) |
| N33 | `BOAT_LANDING_BONUS` mort | P2 | ouvert |
| N34–N118 | (voir rapport #136) | — | **faits** |
| N119 | WorldCamera.step shake `Vector3.new` 60 Hz | P3 | **fait** cette passe (`sx/sy/sz`, recette visual V66 leftover shake) |
| N120 | WorldCamera.step offset `Vector3.new(0,0,distance)` 60 Hz | P3 | **fait** cette passe (trig YXZ, recette visual V67) |
| N121 | WorldCamera.step lerp `focus` Vector3 60 Hz | P3 | **nouveau** (nombres + un `Vector3.new` d’écriture, recette visual V68 déjà sur `0231`, ne pas merger) |
| N122 | WorldCamera.step champ `focusX/Y/Z` | P3 | **nouveau** (plus de Vector3 idle, recette visual V69 ouverte) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 `NIGHTLY_REPORT.md` historique.

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
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.73
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `construction du monde 3D` (N114 compact leftover, N112 `dirtyHead`, N106/N107/N108) ; `pose et capture de chaque type de batiment` (N115 `segRot` leftover, N113 `rot` chantier) ; `navires, missiles et interpolation` (N117 second frame lerp sous yaw euler ; leftover N116 navire immobile `currentX == targetX` ; leftover N103 lerp missile, N98 extra `rawequal`, N101 `targetX`, navire `extra == nil`, `retreatTinted` conservé) ; `camera strategique` (N120 formule `ox/oy/oz` à pitch défaut 58° ; N119 punch + décroissance ; leftover N118 `CFrame.X` nombre, leftover tactile pincement/torsion). `livraison : le gain s'affiche sur la gare` inchangé. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `init.client.luau` **non** touché. `BuildingModels.luau` **non** touché. `PlacementPreview.luau` **non** touché. `UnitModels.luau` **non** touché. `WorldRenderer.luau` **non** touché. `Overlay.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass45.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N119/N120 sont un hoist shake / offset camera vérifiés par le banc headless.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N119 n’ajoute **pas** de require (nombres locaux WorldCamera). N120 n’ajoute **pas** de require (`math.cos`/`sin` locaux). N121 restera dans `WorldCamera.step` lerp. N122 restera dans `WorldCamera` champs focus.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N117 : `fromEulerAnglesYXZ(0, atan2(dx, -dy), 0)` — `dy` tuile = monde Z. Compose **après** `CFrame.new`, **avant** le roulis navire. Recette visual V65 déjà sur `dc65` — porter, ne pas merger. Immobile reste `CFrame.new` (N116), pas `atan2(0, 1)`. Ne pas merger visual.

Piège N118 : `CFrame.new(ex,ey,ez) * rotation` déjà calculée. Abandonner le biais `lookAt(..., focus + shake * 0.18)` (cosmétique, documenté). Recette visual V66 déjà sur `926d` **inclut** shake nombres — feel N118 **a porté** la pose seulement ; N119 porte le shake.

Piège N119 : coeffs 0.65 / 0.42 / 0.5 et fréquences 31 / 37 / 23 **identiques**. Porter `sx/sy/sz` de visual V66, pas merger `926d`. Ne pas fermer offset dans le même commit (fait en N120 ensuite).

Piège N120 : trig YXZ `ox = d*cos(pitch)*sin(yaw)` etc. Pitch feel défaut `math.rad(58)` ≠ 0 : l’œil n’est plus à `focus.Z + distance`. Ne pas assert `Z == focus.Z + distance` (assert visual stub). Recette visual V67 déjà sur `b2f1` — porter, ne pas merger.

Piège N121 (à venir) : un seul `Vector3.new` d’écriture pour `self.focus` (API pan/minimap). Utiliser `fx/fy/fz` pour l’œil (`ex = fx + ox + sx`), pas `self.focus.X` après le write. Recette visual V68 déjà sur `0231` — porter, ne pas merger.

Piège N122 (à venir) : splitter `focusX/Y/Z` sans casser `camera.focus` Vector3 lu par Minimap / clamp. Ne pas splitter `targetFocus`. Recette visual V69 ouverte. Ne pas merger visual.
