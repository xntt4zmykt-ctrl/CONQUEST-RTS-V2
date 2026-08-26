# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 56)

Déclencheur : ouverture de la **PR #167** (`cursor/analyse-nocturne-du-codebase-a8e1`) — BuildingModels `cylinder()` / toits usine euler, specs N141–N142.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-4885`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#167.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. Camera overview : lerp mire `fx/fy/fz` (N121) ; champs `focusX/Y/Z` (N122) ; shake `sx/sy/sz` (N119) ; offset YXZ `ox/oy/oz` (N120) ; pose `CFrame.new * rotation` (N118). Minimap : `setFocus(x,y,z)` nombres (N123). Radar / Flag / Boom : `fromEulerAnglesYXZ` (N124). Overlay navire : roulis `fromEulerAnglesYXZ` (N125). Overlay camion : roues `fromEulerAnglesYXZ` (N126). `UnitModels.place` radar : `fromEulerAnglesYXZ` (N127). `UnitModels.place` flag : `fromEulerAnglesYXZ` (N128). `PlacementPreview.update` footprint : `fromEulerAnglesYXZ` (N129). Overlay LaunchWake : `fromEulerAnglesYXZ` (N130, inline — **≠** visual V78 `wakeRot` cuit). Overlay LandingSplash : `fromEulerAnglesYXZ` (N131, inline — **≠** visual V79 `wakeRot`). Overlay DeliveryPulse : `fromEulerAnglesYXZ` (N132, inline — **≠** visual V80 `wakeRot` cuit sur `a597` / PR #166). Overlay Shockwave : `fromEulerAnglesYXZ` (N133). Effects `conquestPulse` ring : `fromEulerAnglesYXZ` (N134). WorldRenderer OceanGlint : `fromEulerAnglesYXZ` (N135). BuildingModels `BuildRing` : `fromEulerAnglesYXZ` (N136). WorldRenderer TreeTrunk / SavannaTrunk : `fromEulerAnglesYXZ` (N137). WorldRenderer Rock : `fromEulerAnglesYXZ` (N138). BuildingModels `cylinder()` : `fromEulerAnglesYXZ` (N139). BuildingModels toits usine : `fromEulerAnglesYXZ` (N140). BuildingModels portes silo : `fromEulerAnglesYXZ` (N141). BuildingModels rampes SAM : `fromEulerAnglesYXZ` (N142). UnitModels houle `addWake` `CFrame.Angles` encore construction (leftover N143). UnitModels proue `Bow` `CFrame.Angles` encore construction (leftover N144).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #167 (passe 55) : claims vérifiés.** BuildingModels helper `cylinder()` `CFrame.new(offset) * fromEulerAnglesYXZ(0, 0, math.rad(90))` (N139, cylindre Z=90, call sites `buildFactory`/`buildSilo` non édités) ; BuildingModels `buildFactory` toits `CFrame.new(x, roofY, 0) * fromEulerAnglesYXZ(0, 0, math.rad(-12))` (N140, Z=-12° fixe). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #154** (`c0ec`) a **fermé V75** — recette euler **portée** passes 50–56, **pas mergée**. Visual **PR #157** (`70a5`) a **fermé V76** Size rayon (feel Size = API, **pas merger**). Visual **PR #159** (`185a`) a **fermé V77** early-out hover (feel **pas merger**). Visual **PR #162** (`6183`) a **fermé V78** LaunchWake `wakeRot` cuit (feel N130 **inline**, **pas merger**). Visual **PR #164** (`54d6`) a **fermé V79** LandingSplash `wakeRot` (feel N131 **inline**, **pas merger**). Visual **PR #166** (`a597`) a **fermé V80** DeliveryPulse `wakeRot` (feel N132 **inline**, **pas merger**). Visual **`47c0`** a **fermé V81** Shockwave `wakeRot` (feel N133 **inline**, **pas merger**). Leftover visual V82 = Effects `conquestPulse` (feel N134 **inline**, **pas merger**).

Cette passe a **livré ce que #167 a documenté (N141, N142)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #167

| Claim #167 | Réalité à l’ouverture |
|---|---|
| BuildingModels `cylinder()` euler (N139) | Oui. `CFrame.new(offset) * fromEulerAnglesYXZ(0, 0, math.rad(90))`. Cylindre Z=90. Helper seulement. Call sites `buildFactory` / `buildSilo` non édités. Recette leftover N138, pas merger visual. |
| BuildingModels toits usine euler (N140) | Oui. `CFrame.new(x, roofY, 0) * fromEulerAnglesYXZ(0, 0, math.rad(-12))`. Z=-12° fixe. `teeth` / `x` / `roofY` / taille inchangés. Recette leftover N139, pas merger visual. |
| Specs N141–N142 | **Corrigés ici.** N141 = BuildingModels `buildSilo` portes `CFrame.new(-3.6, 1.3, 0) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(18))` et `CFrame.new(3.6, 1.3, 0) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(-18))`. N142 = BuildingModels `buildSam` Interceptor `CFrame.new(side * 1.45, 5.1, lane * 0.72) * CFrame.fromEulerAnglesYXZ(math.rad(-31), 0, 0)`. |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`93f6` (N105–N108), feel jusqu’à #167, visuelles #39/…/`c0ec` V75 **fermé** + `70a5` / PR #157 V76 **fermé** + `185a` / PR #159 V77 **fermé** + `6183` / PR #162 V78 **fermé** (`wakeRot`) + `54d6` / PR #164 V79 **fermé** (LandingSplash) + `a597` / PR #166 V80 **fermé** (DeliveryPulse `wakeRot`) + `47c0` V81 **fermé** (Shockwave `wakeRot`). **#167 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `47c0` / `a597` / `54d6` / `6183` / `185a` / `70a5` / `c0ec` / `1b5c` ni hardening `93f6` / `e291` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N141/N142 sont cosmétique client. Risques documentés, non corrigés ici (hors N141/N142) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N141/N142. Latent hors hot path : `buildCarrier` mesh (`CARRIER_MESH_ID ~= ""`) écrit `visual.parts` au lieu de `visual.pieces` — mort tant que l’id est `""`, **non corrigé** (hors spec). BuildingModels n’a plus de `CFrame.Angles` vivant. UnitModels construction encore `CFrame.Angles` (houle / proue / rampe / corps missile / ailettes).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N141–N142 du rapport #167. Commits séparés (N141 puis N142).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| BuildingModels portes silo `CFrame.Angles` construction (N141) | `BuildingModels.luau` (`buildSilo` portes **seulement**, **deux** sites), `tests/client.luau` (check modeles) | Leftover N140. `CFrame.new(-3.6, 1.3, 0) * fromEulerAnglesYXZ(0, 0, math.rad(18))` et `CFrame.new(3.6, 1.3, 0) * fromEulerAnglesYXZ(0, 0, math.rad(-18))`. Z=±18°. Offsets / taille / STEEL / `Name = "SiloDoor"` inchangés. Cosmétique. Rampes leftover N142 **alors** ; toits N140 / `cylinder()` N139 / `BuildRing` N136 **inchangés**. |
| BuildingModels rampes SAM `CFrame.Angles` construction (N142) | `BuildingModels.luau` (`buildSam` launchers **seulement**), `tests/client.luau` (check modeles) | Leftover N141. `CFrame.new(side * 1.45, 5.1, lane * 0.72) * fromEulerAnglesYXZ(math.rad(-31), 0, 0)`. Pitch X=-31° **fixe**. Quatre Interceptor (2×2). Offset / taille / nez / `Name = "Interceptor"` inchangés. Cosmétique. Portes N141 **inchangées**. UnitModels leftover N143 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels houle `addWake` (**N143**), UnitModels proue `Bow` (**N144**), UnitModels rampe / corps missile / ailettes leftover après N144, flamme `Size = Vector3.new` (Size = API, leftover visual V74 fermée Option A), PlacementPreview Size rayon (visual V76, feel Size = API), PlacementPreview early-out hover (visual V77, **pas merger**), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline**, **pas merger**), Overlay LandingSplash `wakeRot` (visual V79, feel N131 **inline**, **pas merger**), Overlay DeliveryPulse `wakeRot` (visual V80, feel N132 **inline**, **pas merger**), tribus `humanTargetProtected`. UnitModels / Overlay / Effects / WorldCamera / HUD / Minimap / PlacementPreview / WorldRenderer / serveur **non édités**. BuildingModels hors `buildSilo` portes / `buildSam` launchers **non édités**. `cylinder()` / toits / `playConstruction` / `animate` **non édités**.

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
- Overlay interpolation X/Z + yaw euler (**N117**) **et** camion `segRot` (**N115**) **et** roulis navire (**N125**) **et** roues camion (**N126**). Camera : lerp nombres (**N121**) + champ `focusX/Y/Z` (**N122**) + shake (**N119**) + offset (**N120**) + pose (**N118**). Minimap `setFocus(x,y,z)` (**N123**). Radar/Flag/Boom euler (**N124**). `UnitModels.place` radar euler (**N127**) **et** flag euler (**N128**). `PlacementPreview.update` footprint euler (**N129**). Overlay LaunchWake euler (**N130**). Overlay LandingSplash euler (**N131**). Overlay DeliveryPulse euler (**N132**). Overlay Shockwave euler (**N133**). Effects `conquestPulse` ring euler (**N134**). WorldRenderer OceanGlint euler (**N135**). BuildingModels `BuildRing` euler (**N136**). WorldRenderer trunks euler (**N137**). WorldRenderer Rock euler (**N138**). BuildingModels `cylinder()` euler (**N139**). BuildingModels toits usine euler (**N140**). BuildingModels portes silo euler (**N141**). BuildingModels rampes SAM euler (**N142**). UnitModels houle `addWake` `CFrame.Angles` encore construction (**N143**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N143–N144)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N142 = faits. N22 = **N67 fait**. N27 = doc only. **V73 / N127 / N128** fermés passe 49. **N129 / N130** fermés passe 50. **N131 / N132** fermés passe 51. **N133 / N134** fermés passe 52. **N135 / N136** fermés passe 53. **N137 / N138** fermés passe 54. **N139 / N140** fermés passe 55. **N141 / N142** fermés ici (portés, pas mergés ; visual V75 **fermée** sur `c0ec` via `footprintRot` + pulse — feel n’a ni pulse ni 0.42). Leftover feel UnitModels houle `addWake` = **N143**. Leftover feel UnitModels proue `Bow` = **N144**. UnitModels rampe / corps missile / ailettes = leftover après N144. Flamme `Size = Vector3.new` = leftover visual V74 **fermée** Option A sur `c0ec` (Size = API, ne pas en faire N143). PlacementPreview Size rayon = visual V76 **fermée** sur `70a5` (feel Size = API, ne pas merger). PlacementPreview early-out hover = visual V77 **fermée** sur `185a` (feel **pas merger**). Overlay LaunchWake `wakeRot` = visual V78 **fermée** sur `6183` (feel N130 **inline**, ne pas merger). Overlay LandingSplash `wakeRot` = visual V79 **fermée** sur `54d6` (feel N131 **inline**, ne pas merger). Overlay DeliveryPulse `wakeRot` = visual V80 **fermée** sur `a597` / PR #166 (feel N132 **inline**, ne pas merger). Overlay Shockwave `wakeRot` = visual V81 **fermée** sur `47c0` (feel N133 **inline**, ne pas merger). Effects `conquestPulse` leftover visual V82 (feel N134 **inline**, ne pas merger).

---

### ISSUE-N143 — UnitModels houle `addWake` `CFrame.Angles` construction (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite de N142 (rampes SAM déjà). Distinct de N142 (pitch X=-31° Interceptor), de N130 (LaunchWake Overlay insert, Y + 0.12, Z=90), de N125 (roulis navire 60 Hz). UnitModels `addWake` **Wake WedgePart seulement**. Ne pas toucher `Bow`. Ne pas toucher `LandingRamp`. Ne pas toucher `createMissile`. Ne pas toucher `place` radar/flag. Ne pas toucher Overlay / BuildingModels / WorldRenderer.

**Problème :** N142 ferme les rampes SAM. Reste, **une fois à la construction** (`addWake`, boucle `side = -1, 1, 2`, pas 60 Hz) :

```
CFrame.new(side * 2.15, -0.68, 5.5) * CFrame.Angles(0, math.rad(side * 11), 0)
```

`fromEulerAnglesYXZ(0, math.rad(side * 11), 0)` ≡ `Angles(0, ±11°, 0)`. **Yaw Y=±11°** (`side` = ±1), pas Z. Distinct de N142 (`pitch -31°` SAM). Distinct de N130 (LaunchWake Overlay `Z=90`, insert navire). Distinct de N125 (`stepInterpolation` roulis 60 Hz). Offset `(side * 2.15, -0.68, 5.5)` **inchangé**. Taille `Vector3.new(1.15, 0.08, 6.5)` / FOAM / Neon / `Transparency = 0.62` / `Name = "Wake"` / role `"wake"` **inchangés**. **Deux** call sites ensemble (`side` ±1), comme N141 portes.

**Pourquoi 20K CCU :** leftover N142. 8 clients × navires (transport + cargo + carrier) × 2 wakes × `CFrame.Angles` + compose à chaque spawn. Pas d’autorité (mesh cosmétique). Un euler faux (Z au lieu de Y) collerait la houle à la coque. Rampes SAM **déjà** N142 — ne pas y revenir. LaunchWake Overlay **déjà** N130 — ne pas y revenir. Radar/flag `place` **déjà** N127/N128 — ne pas y revenir.

**Worker :**

1. Dans `UnitModels.addWake` seulement, boucle `side` : poser `CFrame.new(side * 2.15, -0.68, 5.5) * CFrame.fromEulerAnglesYXZ(0, math.rad(side * 11), 0)`. Plus de `CFrame.Angles` sur ces Wake. Garder `Name = "Wake"`, role `"wake"`. Offset / taille / FOAM / Neon / Transparency **inchangés**.

2. **Garder yaw Y=`side * 11°`.** Ne **pas** figer à +11° des deux bords. Ne **pas** convertir en translation. Ne **pas** « fermer » `Bow` / rampe / missile dans le même commit (leftover N144 / après N144). Ne pas « fermer » N142. Ne pas porter visual. Après N142. `buildSam` **non** (N142 déjà). `buildSilo` **non** (N141 déjà). Overlay **non** (N130 déjà). `place` **non** (N127/N128 déjà). BuildingModels **non**. WorldRenderer **non**. `createMissile` **non**.

3. Tests « navires, missiles et interpolation » leftover N127 radar **et** leftover N128 flag **et** leftover N125 roulis **et** leftover N116 immobile **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client navires **doit rester vert** (`createBoat` kind 1/2/3 ; leftover N127/N128 `place` ; leftover N130 LaunchWake Overlay). Check modeles leftover N142 Interceptor **et** leftover N141 portes. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`addWake` **seulement**, **deux** sides). `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N143 (commentaire leftover, **garder** N127/N128/N125). `BuildingModels.luau` **non**. `Overlay.luau` **non**. `WorldRenderer.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher `Bow` ni rampe ni missile.

**Contraintes :** pas de RemoteFunction. **N143 feel ≠ N142 (rampes pitch -31°) ≠ N130 (LaunchWake Overlay Z=90) ≠ N144 (proue Y=π) ≠ visual V80 (`wakeRot` `a597`, ne pas merger).** Non réentrant. Ne pas fusionner avec N144 dans le même worker. Un couple : les deux sides — ne pas splitter babord / tribord. `side * 11` **variable** — ne pas figer.

---

### ISSUE-N144 — UnitModels proue `Bow` `CFrame.Angles` construction (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N143 (houle `addWake`). Distinct de N143 (yaw ±11° Wake), de N125 (roulis 60 Hz), de N116 (immobile `CFrame.new`). UnitModels `Bow` WedgePart **seulement** (carrier + transport/cargo). Ne pas toucher `addWake`. Ne pas toucher `LandingRamp`. Ne pas toucher `createMissile`. Ne pas toucher Overlay / BuildingModels.

**Problème :** N143 ferme la houle. Reste, **une fois à la construction** (`buildCarrier` **et** `createBoat` coque LPD/cargo, pas 60 Hz) :

```
CFrame.new(0, -0.2, -10.8) * CFrame.Angles(0, math.pi, 0)   -- carrier
CFrame.new(0, 0.05, -5.9) * CFrame.Angles(0, math.pi, 0)    -- transport/cargo
```

`fromEulerAnglesYXZ(0, math.pi, 0)` ≡ `Angles(0, π, 0)`. **Yaw Y=π**, pas pitch. Distinct de N143 (`±11°` Wake). Distinct de leftover rampe après N144 (`pitch -8°`, `LandingRamp`). Distinct de leftover missile (`Y=90` cylindre). Offsets `(0, -0.2, -10.8)` / `(0, 0.05, -5.9)` **inchangés**. Tailles `Vector3.new(5.6, 1.6, 3.6)` / `Vector3.new(4.8, 1.65, 3.3)` / NAVY / `Name = "Bow"` **inchangés**. **Deux** call sites ensemble, comme N141 portes / N137 trunks. Ne pas splitter carrier / transport.

**Pourquoi 20K CCU :** leftover N143. 8 clients × navires × 1 proue × `CFrame.Angles` + compose à chaque spawn. Pas d’autorité (mesh cosmétique). Un euler faux (pitch au lieu de Y) dresserait le coin avant — le LPD se confondrait avec un cube. Houle **déjà** N143 — ne pas y revenir. Radar/flag `place` **déjà** N127/N128 — ne pas y revenir.

**Worker :**

1. Dans `UnitModels.buildCarrier` **et** `UnitModels.createBoat` coque, les deux `Bow` : poser `CFrame.new(0, -0.2, -10.8) * CFrame.fromEulerAnglesYXZ(0, math.pi, 0)` (carrier) et `CFrame.new(0, 0.05, -5.9) * CFrame.fromEulerAnglesYXZ(0, math.pi, 0)` (transport/cargo). Plus de `CFrame.Angles` sur ces Bow. Garder `Name = "Bow"`. Offsets / tailles / NAVY **inchangés**.

2. **Garder yaw Y=π.** Ne **pas** convertir en translation. Ne **pas** « fermer » rampe / missile / ailettes dans le même commit (leftover après N144 : `LandingRamp` pitch -8°, `MissileBody` Y=90, ailettes `axis * π/2`). Ne pas « fermer » N143. Ne pas porter visual. Après N143. `addWake` **non** (N143 déjà). Overlay **non**. BuildingModels **non**. `place` **non**. `createMissile` **non**.

3. Tests « navires, missiles et interpolation » leftover N143 houle **et** leftover N127 radar **et** leftover N116 immobile **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client navires **doit rester vert** (carrier Bow + transport Bow ; leftover N143 Wake ; leftover N127/N128). Check modeles leftover N142 Interceptor. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`Bow` **seulement**, **deux** sites). `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N144 (commentaire leftover, **garder** N143/N127). `BuildingModels.luau` **non**. `Overlay.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher `addWake` ni rampe ni missile.

**Contraintes :** pas de RemoteFunction. **N144 feel ≠ N143 (Wake ±11°) ≠ N142 (SAM pitch -31°) ≠ leftover rampe (pitch -8°) ≠ visual V80 (ne pas merger).** Non réentrant. Ne pas fusionner avec N143 dans le même worker. Yaw **π fixe** — ne pas varier par `kind`. Un couple : carrier + transport/cargo — ne pas splitter.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; `cylinder()` → **N139 fait** ; toits → **N140 fait** ; portes → **N141 fait** ; rampes → **N142 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; portes → **N141 fait** ; rampes → **N142 fait**) |
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
| N34–N140 | (voir rapport #167) | — | **faits** |
| N141 | BuildingModels portes silo `CFrame.Angles` construction | P3 | **fait** cette passe (`buildSilo`, Z=±18°, deux sites) |
| N142 | BuildingModels rampes SAM `CFrame.Angles` construction | P3 | **fait** cette passe (`buildSam`, pitch X=-31°) |
| N143 | UnitModels houle `addWake` `CFrame.Angles` construction | P3 | **nouveau** (`addWake`, yaw Y=±11°, deux sides) |
| N144 | UnitModels proue `Bow` `CFrame.Angles` construction | P3 | **nouveau** (`buildCarrier` + `createBoat`, Y=π, deux sites) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde, N103 X/Z, N105 TRUCK_LIFT monde, N115 segRot HV, N117 yaw tuile, N125/N126 Overlay, N127/N128 UnitModels, N129 footprint, N130 LaunchWake, N131 splash, N132 pulse, N133 shockwave, N134 ring, N135 OceanGlint, N136 BuildRing, N137 trunks, N138 Rock, N139 `cylinder()`, N140 toits, N141 portes, N142 rampes) |

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
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.33 p95TickMs=0.83
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `construction du monde 3D` (N137 trunks `fromEulerAnglesYXZ` Z=90, N138 Rock `fromEulerAnglesYXZ` yaw `phase`, leftover N135 OceanGlint yaw `angle`, leftover N114 compact, leftover N112 `dirtyHead`, leftover N106/N107/N108) ; `pose et capture de chaque type de batiment` (N136 `BuildRing` `fromEulerAnglesYXZ`, leftover N132 DeliveryPulse, leftover N126 roues, leftover N115 `segRot`, leftover N113 `rot` chantier) ; `modeles procéduraux` (N142 rampes SAM Interceptor `fromEulerAnglesYXZ` pitch X=-31°, N141 portes silo `fromEulerAnglesYXZ` Z=±18°, leftover N140 toits usine Z=-12°, leftover N139 `cylinder()` Z=90, leftover N124 radar/flag/boom, leftover N109 câble Y, Parts stables, rotation visible CFrame ≠ RestCFrame, Y inchangé = pas une translation) ; `apercu de placement pour chaque batiment` (N129 footprint `fromEulerAnglesYXZ`, leftover N92 ctx, ghost visible / snap / upgrade, hauteur 0.4) ; `navires, missiles et interpolation` (N133 Shockwave `fromEulerAnglesYXZ` ; leftover N131 LandingSplash ; leftover N130 LaunchWake ; leftover N128 flag ; leftover N127 radar euler ; leftover N125 roulis ; leftover N117 second frame lerp sous yaw euler ; leftover N116 navire immobile `currentX == targetX` ; leftover N103 lerp missile, N98 extra `rawequal`, N101 `targetX`, navire `extra == nil`, `retreatTinted` conservé ; leftover N143 houle `CFrame.Angles` ; leftover N144 proue `CFrame.Angles` ; `overlay:explosion` N133) ; `livraison : le gain s'affiche sur la gare` leftover N20 ; `vagues de conquete` N134 `conquestPulse` `fromEulerAnglesYXZ`. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `WorldCamera.luau` **non** touché. `UnitModels.luau` **non** touché. `Overlay.luau` **non** touché. `Effects.luau` **non** touché. `PlacementPreview.luau` **non** touché. `Minimap.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché. `WorldRenderer.luau` **non** touché. BuildingModels hors `buildSilo` portes / `buildSam` launchers **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass56.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N141/N142 sont un euler BuildingModels vérifié par le banc headless (compose `CFrame.new * euler` ; stubs `fromEulerAnglesYXZ` déjà présents). Silhouette palier SILO / SAM **inchangée** (N141 garde Z=±18° ; N142 garde pitch -31°).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N141 n’ajoute **pas** de require (`fromEulerAnglesYXZ` local BuildingModels `buildSilo` portes). N142 n’ajoute **pas** de require (local BuildingModels `buildSam` launchers). N143 restera dans `UnitModels.addWake`. N144 restera dans `UnitModels` `Bow` (carrier + transport).

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

Piège N140 : `buildFactory` toits seulement. Z=-12° **fixe**. Distinct `cylinder()` N139 (Z=90). Distinct portes silo N141 (`±18°`). Distinct rampes SAM N142 (`pitch -31°`).

Piège N141 : `buildSilo` portes seulement. Z=+18° **et** Z=-18°. **Deux** sites ensemble. Ne pas splitter A/B. Distinct rampes N142 (pitch X). `cylinder()` **non**.

Piège N142 : `buildSam` launchers seulement. Pitch X=-31° **fixe**. Distinct portes N141 (Z). Distinct Radar `animate` N124. UnitModels leftover N143.

Piège N143 (à venir) : `addWake` seulement. Yaw Y=`side * 11°` **variable** — ne pas figer. **Deux** sides ensemble. Distinct proue leftover N144 (Y=π). Overlay LaunchWake **non** (N130 déjà).

Piège N144 (à venir) : `Bow` seulement. Yaw Y=π **fixe**. **Deux** sites ensemble (carrier + transport/cargo). Ne pas splitter. Distinct houle N143 (±11°). Distinct rampe leftover (pitch -8°).
