# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 50)

Déclencheur : ouverture de la **PR #153** (`cursor/analyse-nocturne-du-codebase-5bde`) — UnitModels radar/flag euler, specs N129–N130.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-5655`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#153.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. Camera overview : lerp mire `fx/fy/fz` (N121) ; champs `focusX/Y/Z` (N122) ; shake `sx/sy/sz` (N119) ; offset YXZ `ox/oy/oz` (N120) ; pose `CFrame.new * rotation` (N118). Minimap : `setFocus(x,y,z)` nombres (N123). Radar / Flag / Boom : `fromEulerAnglesYXZ` (N124). Overlay navire : roulis `fromEulerAnglesYXZ` (N125). Overlay camion : roues `fromEulerAnglesYXZ` (N126). `UnitModels.place` radar : `fromEulerAnglesYXZ` (N127). `UnitModels.place` flag : `fromEulerAnglesYXZ` (N128). `PlacementPreview.update` footprint : `fromEulerAnglesYXZ` (N129). Overlay LaunchWake : `fromEulerAnglesYXZ` (N130). Overlay LandingSplash `CFrame.Angles` encore événement (leftover N131). Overlay DeliveryPulse `CFrame.Angles` événement (leftover N132).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #153 (passe 49) : claims vérifiés.** `UnitModels.place` radar `piece.offset * fromEulerAnglesYXZ(0, time * 2.2, 0)` (N127) ; flag `piece.offset * fromEulerAnglesYXZ(rx, 0, 0)` (N128). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #151** (`1b5c`) a **fermé V73** — recette **portée** passe 49, **pas mergée**. Visual **PR #154** (`c0ec`) a **fermé V75** en parallèle (`CFrame.new * footprintRot`, pulse + 0.42) — feel N129 **porte** l’euler `fromEulerAnglesYXZ` du worker #153 (**pas** merger `c0ec` : pas de pulse, hauteur **0.4**).

Cette passe a **livré ce que #153 a documenté (N129, N130)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #153

| Claim #153 | Réalité à l’ouverture |
|---|---|
| `UnitModels.place` radar euler (N127) | Oui. `piece.offset * fromEulerAnglesYXZ(0, time * 2.2, 0)`. Recette visual V73 leftover, pas merger `1b5c`. |
| `UnitModels.place` flag euler (N128) | Oui. `piece.offset * fromEulerAnglesYXZ(rx, 0, 0)` avec `rx = sin(time * 5) * 0.06`. Recette visual V73 leftover, pas merger `1b5c`. PlacementPreview `CFrame.Angles` restait (leftover N129). Overlay LaunchWake `CFrame.Angles` restait (leftover N130). |
| Specs N129–N130 | **Corrigés ici.** N129 = `PlacementPreview.update` footprint `CFrame.new(base.X, ground + 0.4, base.Z) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))` (leftover visual V75 **fermée** sur `c0ec` via `footprintRot` — **porté euler worker #153, pas mergé** ; feel hauteur **0.4**, **pas** de `self.pulse`). N130 = Overlay `applyUnits` insert `LaunchWake` `CFrame.new(origin.X, OCEAN_LEVEL + 0.12, origin.Z) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))` (`c0ec` n’édite pas Overlay ; leftover événements). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #152/`0744` (N101–N104), feel jusqu’à #153, visuelles #39/…/`1b5c` V73 **fermé** + `c0ec` / PR #154 V74/V75 **fermés**. **#153 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `c0ec` / `1b5c` / `9793` ni hardening `0744` / `f593` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. N129/N130 sont cosmétique client. Risques documentés, non corrigés ici (hors N129/N130) : `JoinRequest` hors IntentValidator ; Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N129/N130. Latent hors hot path : `buildCarrier` mesh (`CARRIER_MESH_ID ~= ""`) écrit `visual.parts` au lieu de `visual.pieces` — mort tant que l’id est `""`, **non corrigé** (hors spec).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N129–N130 du rapport #153. Commits séparés (N129 puis N130).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `PlacementPreview.update` footprint `CFrame.Angles` 60 Hz (N129) | `PlacementPreview.luau` (`update` ligne `footprint.CFrame`), `tests/client.luau` (check apercu) | Leftover N128. `CFrame.new(base.X, ground + 0.4, base.Z) * fromEulerAnglesYXZ(0, 0, math.rad(90))`. Angle 90° / hauteur 0.4 inchangés. Pas de pulse. Pas `footprintRot` cuit (`c0ec` V75, **pas mergé** — `base` change à chaque tuile). Cosmétique. UnitModels N127/N128 **inchangés**. |
| Overlay LaunchWake `CFrame.Angles` événement (N130) | `Overlay.luau` (`applyUnits` insert `LaunchWake`), `tests/client.luau` (check navires) | Leftover N129. `CFrame.new(origin.X, OCEAN_LEVEL + 0.12, origin.Z) * fromEulerAnglesYXZ(0, 0, math.rad(90))`. Offset Y + 0.12 / garde `not isMissile` / Tween Size inchangés. `stepInterpolation` **non** touché. Splash / pulse / shockwave **non** fermés (leftover N131/N132). Cosmétique. PlacementPreview N129 **inchangé**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), Overlay LandingSplash (**N131**), Overlay DeliveryPulse (**N132**), Overlay Shockwave, flamme `Size = Vector3.new` (Size = API, leftover visual V74), tribus `humanTargetProtected`. UnitModels / BuildingModels / WorldRenderer / WorldCamera / HUD / Minimap / serveur **non édités**.

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
- Overlay interpolation X/Z + yaw euler (**N117**) **et** camion `segRot` (**N115**) **et** roulis navire (**N125**) **et** roues camion (**N126**). Camera : lerp nombres (**N121**) + champ `focusX/Y/Z` (**N122**) + shake (**N119**) + offset (**N120**) + pose (**N118**). Minimap `setFocus(x,y,z)` (**N123**). Radar/Flag/Boom euler (**N124**). `UnitModels.place` radar euler (**N127**) **et** flag euler (**N128**). `PlacementPreview.update` footprint euler (**N129**). Overlay LaunchWake euler (**N130**). Overlay LandingSplash `CFrame.Angles` encore événement (**N131**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N131–N132)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N130 = faits. N22 = **N67 fait**. N27 = doc only. **V73 / N127 / N128** fermés passe 49. **N129 / N130** fermés ici (portés, pas mergés ; visual V75 **fermée** sur `c0ec` via `footprintRot` + pulse — feel n’a ni pulse ni 0.42). Leftover feel Overlay LandingSplash = **N131**. Leftover feel Overlay DeliveryPulse = **N132**. Overlay Shockwave / Effects ring / WorldRenderer glints = leftover après N132. Flamme `Size = Vector3.new` = leftover visual V74 **fermée** Option A sur `c0ec` (Size = API, ne pas en faire N131).

---

### ISSUE-N131 — Overlay LandingSplash `CFrame.Angles` événement (feel)

**Priorité :** P3 alloc client Overlay. Leftover explicite de N130 (LaunchWake insert déjà). Visual V75 **distingue** wake / splash / pulse Overlay (événement, pas hover). Distinct de N130 (LaunchWake spawn), de N129 (PlacementPreview 60 Hz), de N125 (roulis interpolation). Overlay `applyUnits` branche despawn navire **seulement**. Ne pas toucher `trackUnit` insert. Ne pas toucher `stepInterpolation`. Ne pas toucher PlacementPreview ni UnitModels.

**Problème :** N130 ferme le wake spawn. Reste, **une fois par navire despawn non-retraite** (pas 60 Hz interpolation, même `CFrame.Angles(0, 0, π/2)` cylindre à plat) :

```
splash.CFrame = CFrame.new(last.X, Config.OCEAN_LEVEL + 0.14, last.Z) * CFrame.Angles(0, 0, math.rad(90))
```

Branche `if not unit.isMissile` + `if not retreating` (N56 : retraite auto ne joue pas le splash d’arrivée). `fromEulerAnglesYXZ(0, 0, math.rad(90))` ≡ `Angles(0, 0, π/2)`. Distinct de N130 (même euler, autre insert, `origin` spawn vs `last` despawn, Y `+ 0.12` vs `+ 0.14`). Distinct de pulse livraison (`route.to`, leftover N132). Distinct de shockwave nuke (`TERRAIN_HEIGHT[PLAINS] + 0.5`, leftover après N132). Distinct de Tween `Size = Vector3.new` (API). Garde `retreatTinted` / `unit.extra.retreating` **inchangée**.

**Pourquoi 20K CCU :** leftover N130. 8 clients × N despawns navire × `CFrame.Angles` + compose. Pas d’autorité (splash cosmétique). Un euler faux dresserait le disque d’arrivée. Retraite / missiles : la branche n’est pas atteinte. Interpolation 60 Hz **déjà** N125/N126 — ne pas y revenir. Insert wake **déjà** N130 — ne pas y revenir.

**Worker :**

1. Dans `Overlay.applyUnits` seulement, despawn navire `LandingSplash` : poser `CFrame.new(last.X, Config.OCEAN_LEVEL + 0.14, last.Z) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))`. Plus de `CFrame.Angles` sur ce despawn. Offset Y `OCEAN_LEVEL + 0.14` **inchangé**. Gardes `not isMissile` / `not retreating` **inchangées**. Tween Size/Transparency **inchangé**. `task.delay` Destroy **inchangé**. Teinte retraite N56 **inchangée**.

2. **Garder la rotation.** Ne **pas** convertir en translation. Ne **pas** « fermer » pulse / shockwave dans le même commit (leftover N132 / après). Ne pas « fermer » N130 (déjà). Ne pas « fermer » flamme `Size`. Ne pas porter visual. Après N130. `stepInterpolation` **non**. `trackUnit` insert **non**.

3. Tests « navires, missiles et interpolation » leftover N130/N128/N127/N125 **et** leftover N129 apercu **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client navires **doit rester vert** (despawn `applyUnits({}, {})` ne lève pas ; leftover N116 immobile ; leftover N125 yaw+roulis ; leftover N127/N128 euler pièces ; leftover N130 wake spawn). Check apercu leftover N129. Check pose/capture leftover N126. Check modeles leftover N124. Check camera leftover N122. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `Overlay.luau` (`applyUnits` despawn `LandingSplash` **seulement**). `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N131 (commentaire leftover, **garder** N130/N128/N56). `PlacementPreview.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. **N131 feel ≠ N130 (LaunchWake spawn) ≠ N129 (footprint 60 Hz) ≠ N125 (roulis interpolation) ≠ N132 (DeliveryPulse) ≠ visual V75 (leftover `1b5c`, ne pas merger).** Non réentrant. Ne pas fusionner avec N132 dans le même worker. N56 retraite skip splash **inchangé**.

---

### ISSUE-N132 — Overlay DeliveryPulse `CFrame.Angles` événement (feel)

**Priorité :** P3 alloc client Overlay. Leftover explicite après N131 (splash despawn). Visual V75 **distingue** pulse livraison Overlay (événement fin de trajet camion, pas hover, pas navire). Distinct de N131 (splash mer), de N130 (wake spawn), de N126 (roues interpolation). Overlay `stepInterpolation` boucle `self.routes` delivery **seulement**. Ne pas toucher `applyUnits`. Ne pas toucher `applyRouteProgress`. Ne pas toucher PlacementPreview.

**Problème :** N131 ferme le splash despawn. Reste, **une fois par livraison arrivée** (`delivery.progress >= 1`, pas 60 Hz interpolation, même `CFrame.Angles(0, 0, π/2)` cylindre à plat) :

```
pulse.CFrame = CFrame.new(route.to) * CFrame.Angles(0, 0, math.rad(90))
```

`route.to` est déjà un `Vector3` monde (gare). `fromEulerAnglesYXZ(0, 0, math.rad(90))` ≡ `Angles(0, 0, π/2)`. Distinct de N131 (`last.X` / `OCEAN_LEVEL + 0.14`, mer). Distinct de shockwave nuke (`TERRAIN_HEIGHT[PLAINS] + 0.5`, leftover après N132). Distinct de Tween `Size = Vector3.new` (API). Camion `Parent = nil` **inchangé**. Construction voie `applyRouteProgress` **inchangée** (N113/N115). Roues N126 **inchangées**.

**Pourquoi 20K CCU :** leftover N131. 8 clients × N livraisons × `CFrame.Angles` + compose. Pas d’autorité (pulse cosmétique). Un euler faux dresserait l’onde gare. Livraison en cours (`progress < 1`) : la ligne n’est pas atteinte. Interpolation camion 60 Hz **déjà** N126/N115 — ne pas y revenir.

**Worker :**

1. Dans `Overlay.stepInterpolation` seulement, fin de `route.delivery` `DeliveryPulse` : poser `CFrame.new(route.to) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))`. Plus de `CFrame.Angles` sur ce pulse. `route.to` **inchangé** (déjà Vector3). Tween Size/Transparency **inchangé**. `task.delay` Destroy **inchangé**. `route.truckModel.Parent = nil` **inchangé**.

2. **Garder la rotation.** Ne **pas** convertir en translation. Ne **pas** « fermer » shockwave / Effects ring / WorldRenderer glints dans le même commit (leftover après N132). Ne pas « fermer » N131. Ne pas « fermer » flamme `Size`. Ne pas porter visual. Après N131. `applyUnits` **non**. `applyRouteProgress` **non**.

3. Tests « livraison : le gain s'affiche sur la gare » leftover N20 **et** leftover N131 navires **et** leftover N129 apercu **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client livraison **doit rester vert** (pulse spawn ne lève pas ; leftover N126 roues ; leftover N115 `segRot`). Check navires leftover N131 splash / N130 wake / N128 flag. Check apercu leftover N129. Check pose/capture leftover N126. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `Overlay.luau` (`stepInterpolation` `DeliveryPulse` **seulement**). `tests/client.luau` **seulement si** le check livraison ne mentionne pas encore N132 (commentaire leftover, **garder** N20). `PlacementPreview.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. **N132 feel ≠ N131 (LandingSplash mer) ≠ N130 (LaunchWake spawn) ≠ N126 (roues 60 Hz) ≠ shockwave (leftover après) ≠ visual V75 (leftover `1b5c`, ne pas merger).** Non réentrant. Ne pas fusionner avec N131 dans le même worker. `applyRouteProgress` N113/N111 **inchangé**.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; Overlay LaunchWake → **N130 fait** ; PlacementPreview footprint → **N129 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; PlacementPreview footprint → **N129 fait** ; Overlay LaunchWake → **N130 fait**) |
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
| N34–N128 | (voir rapport #153) | — | **faits** |
| N129 | `PlacementPreview.update` footprint `CFrame.Angles` 60 Hz | P3 | **fait** cette passe (leftover visual V75, porté euler pas mergé ; hauteur 0.4, pas de pulse) |
| N130 | Overlay LaunchWake `CFrame.Angles` événement | P3 | **fait** cette passe (V75 distingue les événements Overlay) |
| N131 | Overlay LandingSplash `CFrame.Angles` événement | P3 | **nouveau** (despawn navire, Y + 0.14, skip retraite N56) |
| N132 | Overlay DeliveryPulse `CFrame.Angles` événement | P3 | **nouveau** (fin de trajet camion, `route.to`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde, N103 X/Z, N105 TRUCK_LIFT monde, N115 segRot HV, N117 yaw tuile, N125/N126 Overlay, N127/N128 UnitModels, N129 footprint, N130 LaunchWake) |

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
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.74
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `construction du monde 3D` (N114 compact leftover, N112 `dirtyHead`, N106/N107/N108) ; `pose et capture de chaque type de batiment` (N126 roues `fromEulerAnglesYXZ`, leftover N115 `segRot`, leftover N113 `rot` chantier) ; `modeles procéduraux` (N124 radar/flag/boom `fromEulerAnglesYXZ`, leftover N109 câble Y, Parts stables, rotation visible CFrame ≠ RestCFrame, Y inchangé = pas une translation) ; `apercu de placement pour chaque batiment` (N129 footprint `fromEulerAnglesYXZ`, leftover N92 ctx, ghost visible / snap / upgrade, hauteur 0.4) ; `navires, missiles et interpolation` (N130 LaunchWake `fromEulerAnglesYXZ` ; leftover N128 flag ; leftover N127 radar euler ; leftover N125 roulis ; leftover N117 second frame lerp sous yaw euler ; leftover N116 navire immobile `currentX == targetX` ; leftover N103 lerp missile, N98 extra `rawequal`, N101 `targetX`, navire `extra == nil`, `retreatTinted` conservé) ; `camera strategique` (N122 `focusX` lerp avance sans sauter ; N121 œil `fx + ox` ; N120 formule `ox/oy/oz` à pitch défaut 58° ; N119 punch + décroissance ; leftover N118 `CFrame.X` nombre, leftover tactile pincement/torsion) ; `minimap` (N123 `setFocus(0,0,0)` → u=0.5, v=0.5 ; marqueur suit `focusX`/`focusZ`). `livraison : le gain s'affiche sur la gare` inchangé. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `WorldCamera.luau` **non** touché. `UnitModels.luau` **non** touché. `WorldRenderer.luau` **non** touché. `BuildingModels.luau` **non** touché. `Minimap.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass50.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N129/N130 sont un euler PlacementPreview / Overlay vérifié par le banc headless (compose `CFrame.new * euler` ; stubs `fromEulerAnglesYXZ` déjà présents).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N129 n’ajoute **pas** de require (`fromEulerAnglesYXZ` local PlacementPreview). N130 n’ajoute **pas** de require (local Overlay insert). N131 restera dans `Overlay.applyUnits` despawn. N132 restera dans `Overlay.stepInterpolation` delivery.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N125 : `frame` a déjà translation × yaw — **ne pas** réduire à `CFrame.new * euler`. Immobile = zéro compose. Missile = pas de roulis. Recette visual V71 déjà sur `9ab9` — porter, ne pas merger.

Piège N126 : spin réel `progress * π * 20` dans un local `spin`. `frame` a déjà `segRot`. Ne pas cuire le spin dans `piece.offset`. Recette visual V72 déjà sur `9793` — porter, ne pas merger.

Piège N127 : garder `piece.offset * euler`, **ne pas** réduire à `CFrame.new(offset.X,Y,Z) * euler` (recette N124 bâtiments). Distinct SAM Radar N124 (`time * 1.45`). Leftover visual V73 déjà fermé sur `1b5c` (`localFrame * euler`, équivalent) — porter, ne pas merger.

Piège N128 : amplitude 0.06 / fréquence 5. Distinct CapitalFlag N124 (deux sin, rest identité). Ne pas fusionner avec N127. Leftover visual V73 déjà fermé sur `1b5c` — porter, ne pas merger.

Piège N129 : cylindre à plat Z=90. Ne pas omettre l’euler (le cylindre se dresserait). Hauteur feel **0.4** ≠ visual 0.42. Ne pas inventer `self.pulse`. Size footprint **API**. Visual V75 **fermée** sur `c0ec` (`footprintRot` + pulse) — porter euler worker #153, pas merger.

Piège N130 : insert navire seulement, pas `stepInterpolation`. Offset Y `+ 0.12` ≠ splash `+ 0.14`. Ne pas fusionner splash/pulse/shockwave.

Piège N131 (à venir) : despawn non-retraite seulement. N56 skip retraite **conservé**. Distinct pulse N132 (`route.to` terre).

Piège N132 (à venir) : fin de `delivery` seulement, pas construction voie. `route.to` déjà Vector3 — ne pas `tileToWorld`. Distinct shockwave leftover.
