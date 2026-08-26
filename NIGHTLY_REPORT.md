# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 54)

Déclencheur : ouverture de la **PR #163** (`cursor/analyse-nocturne-du-codebase-595e`) — WorldRenderer OceanGlint / BuildingModels BuildRing euler, specs N137–N138.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-c299`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#163.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. Camera overview : lerp mire `fx/fy/fz` (N121) ; champs `focusX/Y/Z` (N122) ; shake `sx/sy/sz` (N119) ; offset YXZ `ox/oy/oz` (N120) ; pose `CFrame.new * rotation` (N118). Minimap : `setFocus(x,y,z)` nombres (N123). Radar / Flag / Boom : `fromEulerAnglesYXZ` (N124). Overlay navire : roulis `fromEulerAnglesYXZ` (N125). Overlay camion : roues `fromEulerAnglesYXZ` (N126). `UnitModels.place` radar : `fromEulerAnglesYXZ` (N127). `UnitModels.place` flag : `fromEulerAnglesYXZ` (N128). `PlacementPreview.update` footprint : `fromEulerAnglesYXZ` (N129). Overlay LaunchWake : `fromEulerAnglesYXZ` (N130, inline — **≠** visual V78 `wakeRot` cuit). Overlay LandingSplash : `fromEulerAnglesYXZ` (N131). Overlay DeliveryPulse : `fromEulerAnglesYXZ` (N132). Overlay Shockwave : `fromEulerAnglesYXZ` (N133). Effects `conquestPulse` ring : `fromEulerAnglesYXZ` (N134). WorldRenderer OceanGlint : `fromEulerAnglesYXZ` (N135). BuildingModels `BuildRing` : `fromEulerAnglesYXZ` (N136). WorldRenderer TreeTrunk / SavannaTrunk : `fromEulerAnglesYXZ` (N137). WorldRenderer Rock : `fromEulerAnglesYXZ` (N138). BuildingModels `cylinder()` `CFrame.Angles` encore construction (leftover N139). BuildingModels toits usine `CFrame.Angles` encore construction (leftover N140).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #163 (passe 53) : claims vérifiés.** WorldRenderer OceanGlint `CFrame.new(world.X, OCEAN_LEVEL + 0.08, world.Z) * fromEulerAnglesYXZ(0, angle, 0)` (N135, yaw `angle` variable, plan Ocean / SeaFloor sans euler) ; BuildingModels `BuildRing` `CFrame.new(ground) * fromEulerAnglesYXZ(0, 0, math.rad(90))` (N136, Tween Size/Transparency inchangés). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #154** (`c0ec`) a **fermé V75** — recette euler **portée** passes 50–54, **pas mergée**. Visual **PR #157** (`70a5`) a **fermé V76** Size rayon (feel Size = API, **pas merger**). Visual **PR #159** (`185a`) a **fermé V77** early-out hover (feel **pas merger**). Visual **PR #162** (`6183`) a **fermé V78** LaunchWake `wakeRot` cuit (feel N130 **inline**, **pas merger**). Visual **PR #164** (`54d6`) a **fermé V79** LandingSplash `wakeRot` (feel N131 **inline**, **pas merger**).

Cette passe a **livré ce que #163 a documenté (N137, N138)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #163

| Claim #163 | Réalité à l’ouverture |
|---|---|
| WorldRenderer OceanGlint euler (N135) | Oui. `CFrame.new(world.X, OCEAN_LEVEL + 0.08, world.Z) * fromEulerAnglesYXZ(0, angle, 0)`. Yaw `angle` variable. Plan Ocean / SeaFloor sans euler. Recette leftover N134, pas merger visual. |
| BuildingModels `BuildRing` euler (N136) | Oui. `CFrame.new(ground) * fromEulerAnglesYXZ(0, 0, math.rad(90))`. Tween Size/Transparency inchangés. Recette leftover N135, pas merger visual. |
| Specs N137–N138 | **Corrigés ici.** N137 = WorldRenderer `buildDecorations` TreeTrunk **et** SavannaTrunk `CFrame.new(...) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))`. N138 = WorldRenderer `buildDecorations` Rock `CFrame.new(base.X, ground + 0.55, base.Z) * CFrame.fromEulerAnglesYXZ(0, phase, 0)`. |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`93f6` (N105–N108), feel jusqu’à #163, visuelles #39/…/`c0ec` V75 **fermé** + `70a5` / PR #157 V76 **fermé** + `185a` / PR #159 V77 **fermé** + `6183` / PR #162 V78 **fermé** (`wakeRot`) + `54d6` / PR #164 V79 **fermé** (LandingSplash). **#163 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `54d6` / `6183` / `185a` / `70a5` / `c0ec` / `1b5c` ni hardening `93f6` / `e291` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. N137/N138 sont cosmétique client. Risques documentés, non corrigés ici (hors N137/N138) : `JoinRequest` hors IntentValidator ; Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N137/N138. Latent hors hot path : `buildCarrier` mesh (`CARRIER_MESH_ID ~= ""`) écrit `visual.parts` au lieu de `visual.pieces` — mort tant que l’id est `""`, **non corrigé** (hors spec). WorldRenderer `buildDecorations` n’a plus de `CFrame.Angles` vivant.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N137–N138 du rapport #163. Commits séparés (N137 puis N138).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| WorldRenderer TreeTrunk / SavannaTrunk `CFrame.Angles` construction (N137) | `WorldRenderer.luau` (`buildDecorations` `TreeTrunk` **et** `SavannaTrunk`), `tests/client.luau` (check construction) | Leftover N136. `CFrame.new(...) * fromEulerAnglesYXZ(0, 0, math.rad(90))`. Cylindre Z=90 **deux** call sites. Couronnes Ball translation inchangées. Cosmétique. Rock leftover N138 **alors** ; OceanGlint N135 **inchangé**. |
| WorldRenderer Rock `CFrame.Angles` construction (N138) | `WorldRenderer.luau` (`buildDecorations` `Rock`), `tests/client.luau` (check construction) | Leftover N137. `CFrame.new(base.X, ground + 0.55, base.Z) * fromEulerAnglesYXZ(0, phase, 0)`. Yaw `phase` **variable**. WedgePart / taille / `CastShadow` inchangés. Cosmétique. Trunks N137 **inchangés**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), BuildingModels `cylinder()` (**N139**), BuildingModels toits usine (**N140**), portes silo / rampes SAM, flamme `Size = Vector3.new` (Size = API, leftover visual V74 fermée Option A), PlacementPreview Size rayon (visual V76, feel Size = API), PlacementPreview early-out hover (visual V77, **pas merger**), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline**, **pas merger**), tribus `humanTargetProtected`. UnitModels / Overlay / Effects / WorldCamera / HUD / Minimap / PlacementPreview / BuildingModels / Overlay après N136 / serveur **non édités**. WorldRenderer hors `buildDecorations` **non édité**. `buildOcean` / `step` **non édités**.

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
- **Réplication :** StateDelta / UnitSnapshot / BuildingDelta / plunder / trade / explosions / notify&sfx / Diplomacy.viewFor 1 Hz. Playing 10 Hz ; lobby vide et ended → 1 Hz.
- Overlay interpolation X/Z + yaw euler (**N117**) **et** camion `segRot` (**N115**) **et** roulis navire (**N125**) **et** roues camion (**N126**). Camera : lerp nombres (**N121**) + champ `focusX/Y/Z` (**N122**) + shake (**N119**) + offset (**N120**) + pose (**N118**). Minimap `setFocus(x,y,z)` (**N123**). Radar/Flag/Boom euler (**N124**). `UnitModels.place` radar euler (**N127**) **et** flag euler (**N128**). `PlacementPreview.update` footprint euler (**N129**). Overlay LaunchWake euler (**N130**). Overlay LandingSplash euler (**N131**). Overlay DeliveryPulse euler (**N132**). Overlay Shockwave euler (**N133**). Effects `conquestPulse` ring euler (**N134**). WorldRenderer OceanGlint euler (**N135**). BuildingModels `BuildRing` euler (**N136**). WorldRenderer trunks euler (**N137**). WorldRenderer Rock euler (**N138**). BuildingModels `cylinder()` `CFrame.Angles` encore construction (**N139**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N139–N140)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N138 = faits. N22 = **N67 fait**. N27 = doc only. **V73 / N127 / N128** fermés passe 49. **N129 / N130** fermés passe 50. **N131 / N132** fermés passe 51. **N133 / N134** fermés passe 52. **N135 / N136** fermés passe 53. **N137 / N138** fermés ici (portés, pas mergés ; visual V75 **fermée** sur `c0ec` via `footprintRot` + pulse — feel n’a ni pulse ni 0.42). Leftover feel BuildingModels `cylinder()` = **N139**. Leftover feel BuildingModels toits usine = **N140**. Portes silo / rampes SAM / UnitModels construction = leftover après N140. Flamme `Size = Vector3.new` = leftover visual V74 **fermée** Option A sur `c0ec` (Size = API, ne pas en faire N139). PlacementPreview Size rayon = visual V76 **fermée** sur `70a5` (feel Size = API, ne pas merger). PlacementPreview early-out hover = visual V77 **fermée** sur `185a` (feel **pas merger**). Overlay LaunchWake `wakeRot` = visual V78 **fermée** sur `6183` (feel N130 **inline**, ne pas merger).

---

### ISSUE-N139 — BuildingModels `cylinder()` `CFrame.Angles` construction (feel)

**Priorité :** P3 alloc client BuildingModels. Leftover explicite de N138 (Rock déjà). Distinct de N138 (WorldRenderer wedge yaw `phase`), de N137 (WorldRenderer cylindre décor Z=90), de N136 (`BuildRing` événement pose, `ground` Vector3). BuildingModels helper **`cylinder()` seulement**. Ne pas toucher `buildFactory` toits. Ne pas toucher portes silo. Ne pas toucher rampes SAM. Ne pas toucher `playConstruction`. Ne pas toucher `animate`. Ne pas toucher WorldRenderer / Overlay / Effects.

**Problème :** N138 ferme les wedges colline. Reste, **une fois à la construction** du mesh (helper `cylinder()`, pas 60 Hz — `animate` câble déjà N109) :

```
part.CFrame = CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90))
```

`fromEulerAnglesYXZ(0, 0, math.rad(90))` ≡ `Angles(0, 0, π/2)`. Même euler que N136 (`BuildRing`) **et** N137 (troncs) **mais** helper mesh usine/silo, pas décor monde ni événement pose. Call sites **via le helper seulement** : `buildFactory` cheminees A/B + réservoir ; `buildSilo` cuve / chemise / body / band. Ne **pas** inliner aux call sites. `block()` pose d’abord `CFrame.new(offset)` ; `cylinder` **écrase** ensuite — garder cet ordre. `Shape = Cylinder` **inchangé**. Commentaire « pointe le long de X » **conservé**. Distinct de N140 (toits `Angles(0, 0, -12°)`, pas le helper). Distinct de portes silo leftover après N140 (`±18°`). Distinct de rampes SAM leftover (`pitch -31°`). Distinct de UnitModels construction leftover.

**Pourquoi 20K CCU :** leftover N138. 8 clients × (usines + silos) × `CFrame.Angles` + compose à chaque pose/capture. Pas d’autorité (mesh cosmétique). Un euler faux (Y au lieu de Z) dresserait les cylindres horizontaux. Rock **déjà** N138 — ne pas y revenir. Trunks **déjà** N137 — ne pas y revenir. `BuildRing` **déjà** N136 — ne pas y revenir.

**Worker :**

1. Dans `BuildingModels.cylinder` seulement : poser `part.CFrame = CFrame.new(offset) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))`. Plus de `CFrame.Angles` dans ce helper. `block(...)` puis `Shape = Cylinder` **inchangés**. Signature `(parent, size, offset, color)` **inchangée**. Call sites `buildFactory` / `buildSilo` **non édités**.

2. **Garder la rotation Z=90.** Ne **pas** convertir en translation. Ne **pas** « fermer » les toits usine dans le même commit (leftover N140). Ne **pas** « fermer » portes silo / rampes SAM / UnitModels construction (leftover après N140). Ne pas « fermer » N138. Ne pas porter visual. Après N138. `playConstruction` **non** (N136 déjà). `animate` **non** (N109 déjà). WorldRenderer **non**. Overlay **non**. Effects **non**.

3. Tests « modeles procéduraux » leftover N124 radar/flag/boom **et** leftover N109 câble Y **et** leftover N136 pose **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client modeles **doit rester vert** (`placeBuilding` FACTORY + SILO ; leftover N136 `BuildRing` via pose/capture ; leftover N137 trunks / N138 Rock via construction monde). Check construction leftover N137/N138. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `BuildingModels.luau` (`cylinder` **seulement**). `tests/client.luau` **seulement si** le check modeles ne mentionne pas encore N139 (commentaire leftover, **garder** N136/N124/N109). `WorldRenderer.luau` **non**. `Overlay.luau` **non**. `Effects.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher `buildFactory` toits ni `buildSam` ni `buildSilo` portes.

**Contraintes :** pas de RemoteFunction. **N139 feel ≠ N138 (Rock yaw `phase`) ≠ N137 (trunks décor) ≠ N136 (`BuildRing` événement) ≠ N140 (toits -12°) ≠ visual V78 (`wakeRot` `6183`, ne pas merger).** Non réentrant. Ne pas fusionner avec N140 dans le même worker. Un seul site : le helper — ne pas splitter usine / silo.

---

### ISSUE-N140 — BuildingModels toits usine `CFrame.Angles` construction (feel)

**Priorité :** P3 alloc client BuildingModels. Leftover explicite après N139 (`cylinder()`). Distinct de N139 (helper cylindre Z=90), de N136 (`BuildRing` événement Z=90), de N137 (troncs décor). BuildingModels `buildFactory` **toits sheds seulement**. Ne pas toucher `cylinder()`. Ne pas toucher portes silo. Ne pas toucher rampes SAM. Ne pas toucher `playConstruction`. Ne pas toucher WorldRenderer / Overlay.

**Problème :** N139 ferme le helper cylindre. Reste, **une fois à la construction** (`buildFactory`, boucle `teeth = 1 + tier`, pas 60 Hz) :

```
roof.CFrame = CFrame.new(x, roofY, 0) * CFrame.Angles(0, 0, math.rad(-12))
```

`fromEulerAnglesYXZ(0, 0, math.rad(-12))` ≡ `Angles(0, 0, -12°)`. **Z=-12°**, pas Z=90. Distinct de N139 (`π/2` cylindre). Distinct de portes silo leftover après (`±18°` Z, `buildSilo`). Distinct de rampes SAM leftover (`pitch -31°`, `buildSam`). `x = (i - (teeth + 1) / 2) * 2.4 - 0.3` **inchangé**. `roofY = 0.7 + hallHeight` **inchangé**. `teeth = 1 + tier` **inchangé**. `block(...)` taille / couleur STEEL **inchangés**. Quai / convoyeur / `FactoryOutput` **inchangés**.

**Pourquoi 20K CCU :** leftover N139. 8 clients × usines × `teeth` (2..4) × `CFrame.Angles` + compose à chaque pose/upgrade. Pas d’autorité (mesh cosmétique). Un euler faux (Y au lieu de Z) aplatirait les sheds. `cylinder()` **déjà** N139 — ne pas y revenir. `BuildRing` **déjà** N136 — ne pas y revenir.

**Worker :**

1. Dans `BuildingModels.buildFactory` seulement, boucle toits : poser `roof.CFrame = CFrame.new(x, roofY, 0) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(-12))`. Plus de `CFrame.Angles` sur ces sheds. Garder `local teeth = 1 + tier` et le calcul `x`. Offset Y `roofY` **inchangé**. Taille `Vector3.new(2.3, 0.35, 7)` **inchangée**.

2. **Garder la rotation Z=-12°.** Ne **pas** convertir en translation. Ne **pas** « fermer » portes silo / rampes SAM / UnitModels construction dans le même commit (leftover après N140). Ne pas « fermer » N139. Ne pas porter visual. Après N139. `cylinder()` **non** (N139 déjà). `playConstruction` **non**. WorldRenderer **non**. Overlay **non**. Effects **non**. `buildSilo` **non**. `buildSam` **non**.

3. Tests « modeles procéduraux » leftover N139 cylinder **et** leftover N124 radar **et** leftover N109 câble **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client modeles **doit rester vert** (FACTORY palier change la silhouette ; leftover N139 cylinder cheminees ; leftover N136 `BuildRing`). Check construction leftover N137/N138. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `BuildingModels.luau` (`buildFactory` toits **seulement**). `tests/client.luau` **seulement si** le check modeles ne mentionne pas encore N140 (commentaire leftover, **garder** N139/N136/N109). `WorldRenderer.luau` **non**. `Overlay.luau` **non**. `Effects.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher `cylinder()` ni portes silo ni rampes SAM.

**Contraintes :** pas de RemoteFunction. **N140 feel ≠ N139 (`cylinder()` Z=90) ≠ N136 (`BuildRing` Z=90) ≠ portes silo leftover (`±18°`) ≠ rampes SAM leftover (`pitch -31°`) ≠ visual V78 (ne pas merger).** Non réentrant. Ne pas fusionner avec N139 dans le même worker. Z=-12° **fixe** — ne pas varier par `tier` au-delà de `teeth`. Distinct de N139 (helper vs toits).

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; Overlay Shockwave → **N133 fait** ; Effects ring → **N134 fait** ; OceanGlint → **N135 fait** ; BuildRing → **N136 fait** ; trunks → **N137 fait** ; Rock → **N138 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; Overlay Shockwave → **N133 fait** ; Effects ring → **N134 fait** ; OceanGlint → **N135 fait** ; BuildRing → **N136 fait** ; trunks → **N137 fait** ; Rock → **N138 fait**) |
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
| N34–N136 | (voir rapport #163) | — | **faits** |
| N137 | WorldRenderer TreeTrunk / SavannaTrunk `CFrame.Angles` construction | P3 | **fait** cette passe (`buildDecorations`, cylindre Z=90) |
| N138 | WorldRenderer Rock `CFrame.Angles` construction | P3 | **fait** cette passe (`buildDecorations`, yaw `phase`) |
| N139 | BuildingModels `cylinder()` `CFrame.Angles` construction | P3 | **nouveau** (helper mesh, cylindre Z=90) |
| N140 | BuildingModels toits usine `CFrame.Angles` construction | P3 | **nouveau** (`buildFactory`, Z=-12°) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde, N103 X/Z, N105 TRUCK_LIFT monde, N115 segRot HV, N117 yaw tuile, N125/N126 Overlay, N127/N128 UnitModels, N129 footprint, N130 LaunchWake, N131 splash, N132 pulse, N133 shockwave, N134 ring, N135 OceanGlint, N136 BuildRing, N137 trunks, N138 Rock) |

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

Client : **35/35 OK** — dont `construction du monde 3D` (N137 trunks `fromEulerAnglesYXZ` Z=90, N138 Rock `fromEulerAnglesYXZ` yaw `phase`, leftover N135 OceanGlint yaw `angle`, leftover N114 compact, leftover N112 `dirtyHead`, leftover N106/N107/N108) ; `pose et capture de chaque type de batiment` (N136 `BuildRing` `fromEulerAnglesYXZ`, leftover N132 DeliveryPulse, leftover N126 roues, leftover N115 `segRot`, leftover N113 `rot` chantier) ; `modeles procéduraux` (N124 radar/flag/boom `fromEulerAnglesYXZ`, leftover N109 câble Y, leftover N139 `cylinder()` `CFrame.Angles`, Parts stables, rotation visible CFrame ≠ RestCFrame, Y inchangé = pas une translation) ; `apercu de placement pour chaque batiment` (N129 footprint `fromEulerAnglesYXZ`, leftover N92 ctx, ghost visible / snap / upgrade, hauteur 0.4) ; `navires, missiles et interpolation` (N133 Shockwave `fromEulerAnglesYXZ` ; leftover N131 LandingSplash ; leftover N130 LaunchWake ; leftover N128 flag ; leftover N127 radar euler ; leftover N125 roulis ; leftover N117 second frame lerp sous yaw euler ; leftover N116 navire immobile `currentX == targetX` ; leftover N103 lerp missile, N98 extra `rawequal`, N101 `targetX`, navire `extra == nil`, `retreatTinted` conservé ; `overlay:explosion` N133) ; `livraison : le gain s'affiche sur la gare` leftover N20 ; `vagues de conquete` N134 `conquestPulse` `fromEulerAnglesYXZ`. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `WorldCamera.luau` **non** touché. `UnitModels.luau` **non** touché. `Overlay.luau` **non** touché. `Effects.luau` **non** touché. `PlacementPreview.luau` **non** touché. `Minimap.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché. `BuildingModels.luau` **non** touché. WorldRenderer hors `buildDecorations` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass54.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N137/N138 sont un euler WorldRenderer vérifié par le banc headless (compose `CFrame.new * euler` ; stubs `fromEulerAnglesYXZ` déjà présents).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N137 n’ajoute **pas** de require (`fromEulerAnglesYXZ` local WorldRenderer `buildDecorations` trunks). N138 n’ajoute **pas** de require (local WorldRenderer `buildDecorations` Rock). N139 restera dans `BuildingModels.cylinder`. N140 restera dans `BuildingModels.buildFactory` toits.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N125 : `frame` a déjà translation × yaw — **ne pas** réduire à `CFrame.new * euler`. Immobile = zéro compose. Missile = pas de roulis. Recette visual V71 déjà sur `9ab9` — porter, ne pas merger.

Piège N126 : spin réel `progress * π * 20` dans un local `spin`. `frame` a déjà `segRot`. Ne pas cuire le spin dans `piece.offset`. Recette visual V72 déjà sur `9793` — porter, ne pas merger.

Piège N127 : garder `piece.offset * euler`, **ne pas** réduire à `CFrame.new(offset.X,Y,Z) * euler` (recette N124 bâtiments). Distinct SAM Radar N124 (`time * 1.45`). Leftover visual V73 déjà fermé sur `1b5c` (`localFrame * euler`, équivalent) — porter, ne pas merger.

Piège N128 : amplitude 0.06 / fréquence 5. Distinct CapitalFlag N124 (deux sin, rest identité). Ne pas fusionner avec N127. Leftover visual V73 déjà fermé sur `1b5c` — porter, ne pas merger.

Piège N129 : cylindre à plat Z=90. Ne pas omettre l’euler (le cylindre se dresserait). Hauteur feel **0.4** ≠ visual 0.42. Ne pas inventer `self.pulse`. Size footprint **API**. Visual V75 **fermée** sur `c0ec` (`footprintRot` + pulse) — porter euler worker #153, pas merger.

Piège N130 : insert navire seulement, pas `stepInterpolation`. Offset Y `+ 0.12` ≠ splash `+ 0.14`. **Inline** `fromEulerAnglesYXZ` — **ne pas** porter visual V78 `wakeRot` cuit (`6183` / PR #162). Ne pas fusionner splash/pulse/shockwave.

Piège N131 : despawn non-retraite seulement. N56 skip retraite **conservé**. Distinct pulse N132 (`route.to` terre). Distinct wake N130 (`origin` spawn, Y `+ 0.12`). Visual V79 LandingSplash `wakeRot` **fermée** sur `54d6` (feel **déjà** N131 **inline** — ne pas merger `54d6` / `5aa9`).

Piège N132 : fin de `delivery` seulement, pas construction voie. `route.to` déjà Vector3 — ne pas `tileToWorld`. Distinct shockwave N133.

Piège N133 : `explosion` seulement. Sphère / fumée **sans** euler. Distinct Effects ring N134 (`Y = 3`). Distinct DeliveryPulse N132 (`route.to` gare). Distinct splash N131 (mer).

Piège N134 : `conquestPulse` seulement, pas Overlay. Caps flash **conservés**. Distinct OceanGlint N135 (yaw `angle`). Distinct Shockwave N133 (`PLAINS + 0.5`).

Piège N135 : `buildOcean` seulement. Yaw `angle` **variable** — ne pas figer. Distinct `BuildRing` N136 (Z=90). Distinct trunks N137. `step` **non** (N108 déjà). Plan Ocean / SeaFloor **sans** euler.

Piège N136 : `playConstruction` seulement, pas `animate`. Distinct trunks N137. Distinct OceanGlint N135 (yaw). Distinct `cylinder()` leftover N139.

Piège N137 : `buildDecorations` trunks seulement. Z=90 **deux** call sites ensemble. Distinct Rock N138 (yaw `phase`). `step` **non**.

Piège N138 : `buildDecorations` Rock seulement. Yaw `phase` **variable** — ne pas figer. Distinct trunks N137 (Z=90). Distinct BuildingModels `cylinder()` leftover N139.

Piège N139 (à venir) : helper `cylinder()` seulement. Z=90 **un** site. Ne pas inliner. Distinct toits leftover N140 (Z=-12°). `playConstruction` **non**.

Piège N140 (à venir) : `buildFactory` toits seulement. Z=-12° **fixe**. Distinct `cylinder()` N139 (Z=90). Distinct portes silo leftover (`±18°`). Distinct rampes SAM leftover (`pitch -31°`).
