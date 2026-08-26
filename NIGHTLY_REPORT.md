# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 55)

Déclencheur : ouverture de la **PR #165** (`cursor/analyse-nocturne-du-codebase-c299`) — WorldRenderer TreeTrunk/SavannaTrunk / Rock euler, specs N139–N140.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-a8e1`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#166.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. Camera overview : lerp mire `fx/fy/fz` (N121) ; champs `focusX/Y/Z` (N122) ; shake `sx/sy/sz` (N119) ; offset YXZ `ox/oy/oz` (N120) ; pose `CFrame.new * rotation` (N118). Minimap : `setFocus(x,y,z)` nombres (N123). Radar / Flag / Boom : `fromEulerAnglesYXZ` (N124). Overlay navire : roulis `fromEulerAnglesYXZ` (N125). Overlay camion : roues `fromEulerAnglesYXZ` (N126). `UnitModels.place` radar : `fromEulerAnglesYXZ` (N127). `UnitModels.place` flag : `fromEulerAnglesYXZ` (N128). `PlacementPreview.update` footprint : `fromEulerAnglesYXZ` (N129). Overlay LaunchWake : `fromEulerAnglesYXZ` (N130, inline — **≠** visual V78 `wakeRot` cuit). Overlay LandingSplash : `fromEulerAnglesYXZ` (N131, inline — **≠** visual V79 `wakeRot`). Overlay DeliveryPulse : `fromEulerAnglesYXZ` (N132, inline — **≠** visual V80 `wakeRot` cuit sur `a597` / PR #166). Overlay Shockwave : `fromEulerAnglesYXZ` (N133). Effects `conquestPulse` ring : `fromEulerAnglesYXZ` (N134). WorldRenderer OceanGlint : `fromEulerAnglesYXZ` (N135). BuildingModels `BuildRing` : `fromEulerAnglesYXZ` (N136). WorldRenderer TreeTrunk / SavannaTrunk : `fromEulerAnglesYXZ` (N137). WorldRenderer Rock : `fromEulerAnglesYXZ` (N138). BuildingModels `cylinder()` : `fromEulerAnglesYXZ` (N139). BuildingModels toits usine : `fromEulerAnglesYXZ` (N140). BuildingModels portes silo `CFrame.Angles` encore construction (leftover N141). BuildingModels rampes SAM `CFrame.Angles` encore construction (leftover N142).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #165 (passe 54) : claims vérifiés.** WorldRenderer TreeTrunk / SavannaTrunk `CFrame.new(...) * fromEulerAnglesYXZ(0, 0, math.rad(90))` (N137, cylindre Z=90, deux call sites, couronnes Ball translation inchangées) ; WorldRenderer Rock `CFrame.new(base.X, ground + 0.55, base.Z) * fromEulerAnglesYXZ(0, phase, 0)` (N138, yaw `phase` variable). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #154** (`c0ec`) a **fermé V75** — recette euler **portée** passes 50–55, **pas mergée**. Visual **PR #157** (`70a5`) a **fermé V76** Size rayon (feel Size = API, **pas merger**). Visual **PR #159** (`185a`) a **fermé V77** early-out hover (feel **pas merger**). Visual **PR #162** (`6183`) a **fermé V78** LaunchWake `wakeRot` cuit (feel N130 **inline**, **pas merger**). Visual **PR #164** (`54d6`) a **fermé V79** LandingSplash `wakeRot` (feel N131 **inline**, **pas merger**). Visual **PR #166** (`a597`) a **fermé V80** DeliveryPulse `wakeRot` (feel N132 **inline**, **pas merger**).

Cette passe a **livré ce que #165 a documenté (N139, N140)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #165

| Claim #165 | Réalité à l’ouverture |
|---|---|
| WorldRenderer TreeTrunk / SavannaTrunk euler (N137) | Oui. `CFrame.new(...) * fromEulerAnglesYXZ(0, 0, math.rad(90))`. Cylindre Z=90. Deux call sites. Couronnes Ball translation inchangées. Recette leftover N136, pas merger visual. |
| WorldRenderer Rock euler (N138) | Oui. `CFrame.new(base.X, ground + 0.55, base.Z) * fromEulerAnglesYXZ(0, phase, 0)`. Yaw `phase` variable. WedgePart / taille / CastShadow inchangés. Recette leftover N137, pas merger visual. |
| Specs N139–N140 | **Corrigés ici.** N139 = BuildingModels helper `cylinder()` `CFrame.new(offset) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))`. N140 = BuildingModels `buildFactory` toits `CFrame.new(x, roofY, 0) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(-12))`. |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`93f6` (N105–N108), feel jusqu’à #165, visuelles #39/…/`c0ec` V75 **fermé** + `70a5` / PR #157 V76 **fermé** + `185a` / PR #159 V77 **fermé** + `6183` / PR #162 V78 **fermé** (`wakeRot`) + `54d6` / PR #164 V79 **fermé** (LandingSplash) + `a597` / PR #166 V80 **fermé** (DeliveryPulse `wakeRot`). **#165 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `a597` / `54d6` / `6183` / `185a` / `70a5` / `c0ec` / `1b5c` ni hardening `93f6` / `e291` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. N139/N140 sont cosmétique client. Risques documentés, non corrigés ici (hors N139/N140) : `JoinRequest` hors IntentValidator ; Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N139/N140. Latent hors hot path : `buildCarrier` mesh (`CARRIER_MESH_ID ~= ""`) écrit `visual.parts` au lieu de `visual.pieces` — mort tant que l’id est `""`, **non corrigé** (hors spec). BuildingModels `cylinder()` / toits usine n’ont plus de `CFrame.Angles` vivant. Portes silo / rampes SAM encore `CFrame.Angles`.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N139–N140 du rapport #165. Commits séparés (N139 puis N140).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| BuildingModels `cylinder()` `CFrame.Angles` construction (N139) | `BuildingModels.luau` (`cylinder` **seulement**), `tests/client.luau` (check modeles) | Leftover N138. `CFrame.new(offset) * fromEulerAnglesYXZ(0, 0, math.rad(90))`. Cylindre Z=90 **un** helper. Call sites `buildFactory` / `buildSilo` **non édités**. Cosmétique. Toits leftover N140 **alors** ; trunks N137 / Rock N138 / `BuildRing` N136 **inchangés**. |
| BuildingModels toits usine `CFrame.Angles` construction (N140) | `BuildingModels.luau` (`buildFactory` toits **seulement**), `tests/client.luau` (check modeles) | Leftover N139. `CFrame.new(x, roofY, 0) * fromEulerAnglesYXZ(0, 0, math.rad(-12))`. Z=-12° **fixe**. `teeth` / `x` / `roofY` / taille inchangés. Cosmétique. `cylinder()` N139 **inchangé**. Portes silo leftover N141 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), BuildingModels portes silo (**N141**), BuildingModels rampes SAM (**N142**), UnitModels construction leftover, flamme `Size = Vector3.new` (Size = API, leftover visual V74 fermée Option A), PlacementPreview Size rayon (visual V76, feel Size = API), PlacementPreview early-out hover (visual V77, **pas merger**), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline**, **pas merger**), Overlay LandingSplash `wakeRot` (visual V79, feel N131 **inline**, **pas merger**), Overlay DeliveryPulse `wakeRot` (visual V80, feel N132 **inline**, **pas merger**), tribus `humanTargetProtected`. UnitModels / Overlay / Effects / WorldCamera / HUD / Minimap / PlacementPreview / WorldRenderer / serveur **non édités**. BuildingModels hors `cylinder` / toits `buildFactory` **non édités**. `playConstruction` / `animate` **non édités**.

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
- Overlay interpolation X/Z + yaw euler (**N117**) **et** camion `segRot` (**N115**) **et** roulis navire (**N125**) **et** roues camion (**N126**). Camera : lerp nombres (**N121**) + champ `focusX/Y/Z` (**N122**) + shake (**N119**) + offset (**N120**) + pose (**N118**). Minimap `setFocus(x,y,z)` (**N123**). Radar/Flag/Boom euler (**N124**). `UnitModels.place` radar euler (**N127**) **et** flag euler (**N128**). `PlacementPreview.update` footprint euler (**N129**). Overlay LaunchWake euler (**N130**). Overlay LandingSplash euler (**N131**). Overlay DeliveryPulse euler (**N132**). Overlay Shockwave euler (**N133**). Effects `conquestPulse` ring euler (**N134**). WorldRenderer OceanGlint euler (**N135**). BuildingModels `BuildRing` euler (**N136**). WorldRenderer trunks euler (**N137**). WorldRenderer Rock euler (**N138**). BuildingModels `cylinder()` euler (**N139**). BuildingModels toits usine euler (**N140**). BuildingModels portes silo `CFrame.Angles` encore construction (**N141**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N141–N142)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N140 = faits. N22 = **N67 fait**. N27 = doc only. **V73 / N127 / N128** fermés passe 49. **N129 / N130** fermés passe 50. **N131 / N132** fermés passe 51. **N133 / N134** fermés passe 52. **N135 / N136** fermés passe 53. **N137 / N138** fermés passe 54. **N139 / N140** fermés ici (portés, pas mergés ; visual V75 **fermée** sur `c0ec` via `footprintRot` + pulse — feel n’a ni pulse ni 0.42). Leftover feel BuildingModels portes silo = **N141**. Leftover feel BuildingModels rampes SAM = **N142**. UnitModels construction (houle / proue / rampe / corps missile / ailettes) = leftover après N142. Flamme `Size = Vector3.new` = leftover visual V74 **fermée** Option A sur `c0ec` (Size = API, ne pas en faire N141). PlacementPreview Size rayon = visual V76 **fermée** sur `70a5` (feel Size = API, ne pas merger). PlacementPreview early-out hover = visual V77 **fermée** sur `185a` (feel **pas merger**). Overlay LaunchWake `wakeRot` = visual V78 **fermée** sur `6183` (feel N130 **inline**, ne pas merger). Overlay LandingSplash `wakeRot` = visual V79 **fermée** sur `54d6` (feel N131 **inline**, ne pas merger). Overlay DeliveryPulse `wakeRot` = visual V80 **fermée** sur `a597` / PR #166 (feel N132 **inline**, ne pas merger).

---

### ISSUE-N141 — BuildingModels portes silo `CFrame.Angles` construction (feel)

**Priorité :** P3 alloc client BuildingModels. Leftover explicite de N140 (toits déjà). Distinct de N140 (toits usine Z=-12°), de N139 (helper cylindre Z=90), de N136 (`BuildRing` événement pose). BuildingModels `buildSilo` **portes seulement**. Ne pas toucher `cylinder()`. Ne pas toucher toits usine. Ne pas toucher rampes SAM. Ne pas toucher `playConstruction`. Ne pas toucher `animate`. Ne pas toucher WorldRenderer / Overlay / Effects / UnitModels.

**Problème :** N140 ferme les sheds usine. Reste, **une fois à la construction** (`buildSilo`, deux portes, pas 60 Hz) :

```
doorA.CFrame = CFrame.new(-3.6, 1.3, 0) * CFrame.Angles(0, 0, math.rad(18))
doorB.CFrame = CFrame.new(3.6, 1.3, 0) * CFrame.Angles(0, 0, math.rad(-18))
```

`fromEulerAnglesYXZ(0, 0, math.rad(18))` ≡ `Angles(0, 0, 18°)` ; `fromEulerAnglesYXZ(0, 0, math.rad(-18))` ≡ `Angles(0, 0, -18°)`. **Z=±18°**, pas Z=90 ni Z=-12°. Distinct de N140 (`-12°` sheds). Distinct de N139 (`π/2` cylindre). Distinct de rampes SAM leftover N142 (`pitch -31°`, `buildSam`). Offsets `(-3.6, 1.3, 0)` / `(3.6, 1.3, 0)` **inchangés**. `block(...)` taille `Vector3.new(4.4, 0.45, 6.5)` / couleur STEEL / `Name = "SiloDoor"` **inchangés**. `warningStrip` **inchangé**. Cuve / chemise / body / band via `cylinder()` **déjà** N139 — ne pas y revenir. **Deux** call sites ensemble, comme N137 trunks.

**Pourquoi 20K CCU :** leftover N140. 8 clients × silos × 2 portes × `CFrame.Angles` + compose à chaque pose/capture. Pas d’autorité (mesh cosmétique). Un euler faux (Y au lieu de Z) aplatirait les portes ouvertes. Toits **déjà** N140 — ne pas y revenir. `cylinder()` **déjà** N139 — ne pas y revenir. `BuildRing` **déjà** N136 — ne pas y revenir.

**Worker :**

1. Dans `BuildingModels.buildSilo` seulement, les deux portes : poser `doorA.CFrame = CFrame.new(-3.6, 1.3, 0) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(18))` et `doorB.CFrame = CFrame.new(3.6, 1.3, 0) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(-18))`. Plus de `CFrame.Angles` sur ces portes. Garder `Name = "SiloDoor"`. Offsets / taille / STEEL **inchangés**.

2. **Garder Z=+18° et Z=-18°.** Ne **pas** convertir en translation. Ne **pas** « fermer » rampes SAM / UnitModels construction dans le même commit (leftover N142 / après N142). Ne pas « fermer » N140. Ne pas porter visual. Après N140. `cylinder()` **non** (N139 déjà). `buildFactory` **non** (N140 déjà). `playConstruction` **non**. WorldRenderer **non**. Overlay **non**. Effects **non**. `buildSam` **non**.

3. Tests « modeles procéduraux » leftover N140 toits **et** leftover N139 cylinder **et** leftover N124 radar **et** leftover N109 câble **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client modeles **doit rester vert** (`placeBuilding` SILO ; leftover N140 toits FACTORY ; leftover N139 cylinder cheminees ; leftover N136 `BuildRing`). Check construction leftover N137/N138. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `BuildingModels.luau` (`buildSilo` portes **seulement**, **deux** sites). `tests/client.luau` **seulement si** le check modeles ne mentionne pas encore N141 (commentaire leftover, **garder** N140/N139/N136/N109). `WorldRenderer.luau` **non**. `Overlay.luau` **non**. `Effects.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher `cylinder()` ni toits ni rampes SAM.

**Contraintes :** pas de RemoteFunction. **N141 feel ≠ N140 (toits -12°) ≠ N139 (`cylinder()` Z=90) ≠ N142 (rampes pitch -31°) ≠ visual V80 (`wakeRot` `a597`, ne pas merger).** Non réentrant. Ne pas fusionner avec N142 dans le même worker. Un couple : les deux portes — ne pas splitter A / B.

---

### ISSUE-N142 — BuildingModels rampes SAM `CFrame.Angles` construction (feel)

**Priorité :** P3 alloc client BuildingModels. Leftover explicite après N141 (portes silo). Distinct de N141 (portes Z=±18°), de N139 (helper cylindre Z=90), de N124 (`animate` Radar 60 Hz). BuildingModels `buildSam` **launchers Interceptor seulement**. Ne pas toucher portes silo. Ne pas toucher `cylinder()`. Ne pas toucher `playConstruction`. Ne pas toucher WorldRenderer / Overlay / UnitModels.

**Problème :** N141 ferme les portes silo. Reste, **une fois à la construction** (`buildSam`, boucle `side × lane`, pas 60 Hz) :

```
launcher.CFrame = CFrame.new(side * 1.45, 5.1, lane * 0.72) * CFrame.Angles(math.rad(-31), 0, 0)
```

`fromEulerAnglesYXZ(math.rad(-31), 0, 0)` ≡ `Angles(-31°, 0, 0)`. **Pitch X=-31°**, pas Z. Distinct de N141 (`±18°` Z). Distinct de N139 (`π/2` Z cylindre). Distinct de N124 (`animate` Radar yaw `time * 1.45`, RestCFrame). Offset `side * 1.45, 5.1, lane * 0.72` **inchangé**. `Name = "Interceptor"` **inchangé**. Taille `Vector3.new(0.72, 5.8, 0.72)` / MISSILE **inchangés**. Nez neon **inchangé**. Socle / rampes acier / Radar **inchangés**. Quatre missiles (2×2) **ensemble**.

**Pourquoi 20K CCU :** leftover N141. 8 clients × SAM × 4 interceptors × `CFrame.Angles` + compose à chaque pose/capture. Pas d’autorité (mesh cosmétique). Un euler faux (Z au lieu de X) dresserait les missiles à la verticale — la batterie se confondrait avec le silo. Portes silo **déjà** N141 — ne pas y revenir. Radar `animate` **déjà** N124 — ne pas y revenir.

**Worker :**

1. Dans `BuildingModels.buildSam` seulement, boucle launchers : poser `launcher.CFrame = CFrame.new(side * 1.45, 5.1, lane * 0.72) * CFrame.fromEulerAnglesYXZ(math.rad(-31), 0, 0)`. Plus de `CFrame.Angles` sur ces Interceptor. Garder `Name = "Interceptor"`. Offset / taille / nez **inchangés**.

2. **Garder le pitch X=-31°.** Ne **pas** convertir en translation. Ne **pas** « fermer » UnitModels construction dans le même commit (leftover après N142 : houle `addWake` yaw ±11°, proue `π`, rampe -8°, corps missile Y=90, ailettes `axis * π/2`). Ne pas « fermer » N141. Ne pas porter visual. Après N141. `buildSilo` **non** (N141 déjà). `cylinder()` **non**. `playConstruction` **non**. `animate` **non** (N124 déjà). WorldRenderer **non**. Overlay **non**. Effects **non**. UnitModels **non**.

3. Tests « modeles procéduraux » leftover N141 portes **et** leftover N124 radar SAM **doivent rester verts** (`radar.CFrame.Y == radarRest.Y`, pas une translation). Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client modeles **doit rester vert** (SAM Interceptor + Radar N124 ; leftover N141 portes SILO ; leftover N140 toits FACTORY). Check navires leftover N127/N128. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `BuildingModels.luau` (`buildSam` launchers **seulement**). `tests/client.luau` **seulement si** le check modeles ne mentionne pas encore N142 (commentaire leftover, **garder** N141/N140/N124). `WorldRenderer.luau` **non**. `Overlay.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher portes silo ni Radar `animate`.

**Contraintes :** pas de RemoteFunction. **N142 feel ≠ N141 (portes ±18° Z) ≠ N139 (`cylinder()` Z=90) ≠ N124 (Radar 60 Hz) ≠ visual V80 (ne pas merger).** Non réentrant. Ne pas fusionner avec N141 dans le même worker. Pitch **-31° fixe** — ne pas varier par `level`. Distinct de N141 (silo vs SAM).

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; trunks → **N137 fait** ; Rock → **N138 fait** ; `cylinder()` → **N139 fait** ; toits → **N140 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; trunks → **N137 fait** ; Rock → **N138 fait** ; `cylinder()` → **N139 fait** ; toits → **N140 fait**) |
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
| N34–N138 | (voir rapport #165) | — | **faits** |
| N139 | BuildingModels `cylinder()` `CFrame.Angles` construction | P3 | **fait** cette passe (helper mesh, cylindre Z=90) |
| N140 | BuildingModels toits usine `CFrame.Angles` construction | P3 | **fait** cette passe (`buildFactory`, Z=-12°) |
| N141 | BuildingModels portes silo `CFrame.Angles` construction | P3 | **nouveau** (`buildSilo`, Z=±18°, deux sites) |
| N142 | BuildingModels rampes SAM `CFrame.Angles` construction | P3 | **nouveau** (`buildSam`, pitch X=-31°) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde, N103 X/Z, N105 TRUCK_LIFT monde, N115 segRot HV, N117 yaw tuile, N125/N126 Overlay, N127/N128 UnitModels, N129 footprint, N130 LaunchWake, N131 splash, N132 pulse, N133 shockwave, N134 ring, N135 OceanGlint, N136 BuildRing, N137 trunks, N138 Rock, N139 `cylinder()`, N140 toits) |

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
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.71
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `construction du monde 3D` (N137 trunks `fromEulerAnglesYXZ` Z=90, N138 Rock `fromEulerAnglesYXZ` yaw `phase`, leftover N135 OceanGlint yaw `angle`, leftover N114 compact, leftover N112 `dirtyHead`, leftover N106/N107/N108) ; `pose et capture de chaque type de batiment` (N136 `BuildRing` `fromEulerAnglesYXZ`, leftover N132 DeliveryPulse, leftover N126 roues, leftover N115 `segRot`, leftover N113 `rot` chantier) ; `modeles procéduraux` (N140 toits usine `fromEulerAnglesYXZ` Z=-12°, N139 `cylinder()` `fromEulerAnglesYXZ` Z=90, leftover N124 radar/flag/boom, leftover N109 câble Y, leftover N141 portes silo `CFrame.Angles`, Parts stables, rotation visible CFrame ≠ RestCFrame, Y inchangé = pas une translation) ; `apercu de placement pour chaque batiment` (N129 footprint `fromEulerAnglesYXZ`, leftover N92 ctx, ghost visible / snap / upgrade, hauteur 0.4) ; `navires, missiles et interpolation` (N133 Shockwave `fromEulerAnglesYXZ` ; leftover N131 LandingSplash ; leftover N130 LaunchWake ; leftover N128 flag ; leftover N127 radar euler ; leftover N125 roulis ; leftover N117 second frame lerp sous yaw euler ; leftover N116 navire immobile `currentX == targetX` ; leftover N103 lerp missile, N98 extra `rawequal`, N101 `targetX`, navire `extra == nil`, `retreatTinted` conservé ; `overlay:explosion` N133) ; `livraison : le gain s'affiche sur la gare` leftover N20 ; `vagues de conquete` N134 `conquestPulse` `fromEulerAnglesYXZ`. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `WorldCamera.luau` **non** touché. `UnitModels.luau` **non** touché. `Overlay.luau` **non** touché. `Effects.luau` **non** touché. `PlacementPreview.luau` **non** touché. `Minimap.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché. `WorldRenderer.luau` **non** touché. BuildingModels hors `cylinder` / toits `buildFactory` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass55.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N139/N140 sont un euler BuildingModels vérifié par le banc headless (compose `CFrame.new * euler` ; stubs `fromEulerAnglesYXZ` déjà présents). Silhouette palier FACTORY **inchangée** (N140 garde Z=-12°).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N139 n’ajoute **pas** de require (`fromEulerAnglesYXZ` local BuildingModels `cylinder`). N140 n’ajoute **pas** de require (local BuildingModels `buildFactory` toits). N141 restera dans `BuildingModels.buildSilo` portes. N142 restera dans `BuildingModels.buildSam` launchers.

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

Piège N132 : fin de `delivery` seulement, pas construction voie. `route.to` déjà Vector3 — ne pas `tileToWorld`. Distinct shockwave N133. Visual V80 DeliveryPulse `wakeRot` **fermée** sur `a597` / PR #166 (feel **déjà** N132 **inline** — ne pas merger `a597` / `5aa9`).

Piège N133 : `explosion` seulement. Sphère / fumée **sans** euler. Distinct Effects ring N134 (`Y = 3`). Distinct DeliveryPulse N132 (`route.to` gare). Distinct splash N131 (mer).

Piège N134 : `conquestPulse` seulement, pas Overlay. Caps flash **conservés**. Distinct OceanGlint N135 (yaw `angle`). Distinct Shockwave N133 (`PLAINS + 0.5`).

Piège N135 : `buildOcean` seulement. Yaw `angle` **variable** — ne pas figer. Distinct `BuildRing` N136 (Z=90). Distinct trunks N137. `step` **non** (N108 déjà). Plan Ocean / SeaFloor **sans** euler.

Piège N136 : `playConstruction` seulement, pas `animate`. Distinct trunks N137. Distinct OceanGlint N135 (yaw). Distinct `cylinder()` N139.

Piège N137 : `buildDecorations` trunks seulement. Z=90 **deux** call sites ensemble. Distinct Rock N138 (yaw `phase`). `step` **non**.

Piège N138 : `buildDecorations` Rock seulement. Yaw `phase` **variable** — ne pas figer. Distinct trunks N137 (Z=90). Distinct BuildingModels `cylinder()` N139.

Piège N139 : helper `cylinder()` seulement. Z=90 **un** site. Ne pas inliner. Distinct toits N140 (Z=-12°). `playConstruction` **non**. Call sites `buildFactory` / `buildSilo` **non édités**.

Piège N140 : `buildFactory` toits seulement. Z=-12° **fixe**. Distinct `cylinder()` N139 (Z=90). Distinct portes silo leftover N141 (`±18°`). Distinct rampes SAM leftover N142 (`pitch -31°`).

Piège N141 (à venir) : `buildSilo` portes seulement. Z=+18° **et** Z=-18°. **Deux** sites ensemble. Ne pas splitter A/B. Distinct rampes leftover N142 (pitch X). `cylinder()` **non**.

Piège N142 (à venir) : `buildSam` launchers seulement. Pitch X=-31° **fixe**. Distinct portes N141 (Z). Distinct Radar `animate` N124. UnitModels construction leftover après.
