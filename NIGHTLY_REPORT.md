# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 51)

Déclencheur : ouverture de la **PR #155** (`cursor/analyse-nocturne-du-codebase-5655`) — PlacementPreview footprint / Overlay LaunchWake euler, specs N131–N132.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-5aa9`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#155.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. Camera overview : lerp mire `fx/fy/fz` (N121) ; champs `focusX/Y/Z` (N122) ; shake `sx/sy/sz` (N119) ; offset YXZ `ox/oy/oz` (N120) ; pose `CFrame.new * rotation` (N118). Minimap : `setFocus(x,y,z)` nombres (N123). Radar / Flag / Boom : `fromEulerAnglesYXZ` (N124). Overlay navire : roulis `fromEulerAnglesYXZ` (N125). Overlay camion : roues `fromEulerAnglesYXZ` (N126). `UnitModels.place` radar : `fromEulerAnglesYXZ` (N127). `UnitModels.place` flag : `fromEulerAnglesYXZ` (N128). `PlacementPreview.update` footprint : `fromEulerAnglesYXZ` (N129). Overlay LaunchWake : `fromEulerAnglesYXZ` (N130). Overlay LandingSplash : `fromEulerAnglesYXZ` (N131). Overlay DeliveryPulse : `fromEulerAnglesYXZ` (N132). Overlay Shockwave `CFrame.Angles` encore événement (leftover N133). Effects `conquestPulse` ring `CFrame.Angles` événement (leftover N134).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #155 (passe 50) : claims vérifiés.** `PlacementPreview.update` footprint `CFrame.new(base.X, ground + 0.4, base.Z) * fromEulerAnglesYXZ(0, 0, math.rad(90))` (N129) ; Overlay LaunchWake `CFrame.new(origin.X, OCEAN_LEVEL + 0.12, origin.Z) * fromEulerAnglesYXZ(0, 0, math.rad(90))` (N130). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #154** (`c0ec`) a **fermé V75** — recette euler **portée** passe 50, **pas mergée**. Visual **PR #157** (`70a5`) a **fermé V76** Size rayon (feel Size = API, **pas merger**).

Cette passe a **livré ce que #155 a documenté (N131, N132)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #155

| Claim #155 | Réalité à l’ouverture |
|---|---|
| `PlacementPreview.update` footprint euler (N129) | Oui. `CFrame.new(base.X, ground + 0.4, base.Z) * fromEulerAnglesYXZ(0, 0, math.rad(90))`. Hauteur 0.4, pas de pulse. Recette visual V75 leftover, pas merger `c0ec`. |
| Overlay LaunchWake euler (N130) | Oui. `CFrame.new(origin.X, OCEAN_LEVEL + 0.12, origin.Z) * fromEulerAnglesYXZ(0, 0, math.rad(90))`. Insert spawn navire seulement. Splash / pulse / shockwave restaient (leftover N131/N132). |
| Specs N131–N132 | **Corrigés ici.** N131 = Overlay `applyUnits` despawn `LandingSplash` `CFrame.new(last.X, OCEAN_LEVEL + 0.14, last.Z) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))` (skip retraite N56). N132 = Overlay `stepInterpolation` fin de `delivery` `CFrame.new(route.to) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))`. |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #156/`e291` (N103–N106), feel jusqu’à #155, visuelles #39/…/`c0ec` V75 **fermé** + `70a5` / PR #157 V76 **fermé**. **#155 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `70a5` / `c0ec` / `1b5c` ni hardening `e291` / `0744` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. N131/N132 sont cosmétique client. Risques documentés, non corrigés ici (hors N131/N132) : `JoinRequest` hors IntentValidator ; Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N131/N132. Latent hors hot path : `buildCarrier` mesh (`CARRIER_MESH_ID ~= ""`) écrit `visual.parts` au lieu de `visual.pieces` — mort tant que l’id est `""`, **non corrigé** (hors spec).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N131–N132 du rapport #155. Commits séparés (N131 puis N132).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Overlay LandingSplash `CFrame.Angles` événement (N131) | `Overlay.luau` (`applyUnits` despawn `LandingSplash`), `tests/client.luau` (check navires) | Leftover N130. `CFrame.new(last.X, OCEAN_LEVEL + 0.14, last.Z) * fromEulerAnglesYXZ(0, 0, math.rad(90))`. Gardes `not isMissile` / `not retreating` (N56) inchangées. Cosmétique. LaunchWake N130 **inchangé**. |
| Overlay DeliveryPulse `CFrame.Angles` événement (N132) | `Overlay.luau` (`stepInterpolation` fin de `delivery`), `tests/client.luau` (check pose/capture) | Leftover N131. `CFrame.new(route.to) * fromEulerAnglesYXZ(0, 0, math.rad(90))`. `route.to` déjà Vector3. `truckModel.Parent = nil` inchangé. Cosmétique. Splash N131 **inchangé**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), Overlay Shockwave (**N133**), Effects `conquestPulse` ring (**N134**), WorldRenderer glints, BuildingModels `BuildRing`, flamme `Size = Vector3.new` (Size = API, leftover visual V74 fermée Option A), PlacementPreview Size rayon (visual V76, feel Size = API), tribus `humanTargetProtected`. UnitModels / BuildingModels / WorldRenderer / WorldCamera / HUD / Minimap / PlacementPreview / serveur **non édités**.

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
- Overlay interpolation X/Z + yaw euler (**N117**) **et** camion `segRot` (**N115**) **et** roulis navire (**N125**) **et** roues camion (**N126**). Camera : lerp nombres (**N121**) + champ `focusX/Y/Z` (**N122**) + shake (**N119**) + offset (**N120**) + pose (**N118**). Minimap `setFocus(x,y,z)` (**N123**). Radar/Flag/Boom euler (**N124**). `UnitModels.place` radar euler (**N127**) **et** flag euler (**N128**). `PlacementPreview.update` footprint euler (**N129**). Overlay LaunchWake euler (**N130**). Overlay LandingSplash euler (**N131**). Overlay DeliveryPulse euler (**N132**). Overlay Shockwave `CFrame.Angles` encore événement (**N133**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N133–N134)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N132 = faits. N22 = **N67 fait**. N27 = doc only. **V73 / N127 / N128** fermés passe 49. **N129 / N130** fermés passe 50. **N131 / N132** fermés ici (portés, pas mergés ; visual V75 **fermée** sur `c0ec` via `footprintRot` + pulse — feel n’a ni pulse ni 0.42). Leftover feel Overlay Shockwave = **N133**. Leftover feel Effects `conquestPulse` ring = **N134**. WorldRenderer OceanGlint / BuildingModels `BuildRing` / décor trunks = leftover après N134. Flamme `Size = Vector3.new` = leftover visual V74 **fermée** Option A sur `c0ec` (Size = API, ne pas en faire N133). PlacementPreview Size rayon = visual V76 **fermée** sur `70a5` (feel Size = API, ne pas merger).

---

### ISSUE-N133 — Overlay Shockwave `CFrame.Angles` événement (feel)

**Priorité :** P3 alloc client Overlay. Leftover explicite de N132 (DeliveryPulse insert déjà). Visual V75 **distingue** wake / splash / pulse Overlay (événement) ; shockwave est le dernier `CFrame.Angles` Overlay. Distinct de N132 (DeliveryPulse gare), de N131 (LandingSplash mer), de N130 (LaunchWake spawn). Overlay `explosion` **seulement**. Ne pas toucher `applyUnits`. Ne pas toucher `stepInterpolation`. Ne pas toucher Effects.

**Problème :** N132 ferme le pulse livraison. Reste, **une fois par frappe** (`Overlay.explosion`, pas 60 Hz interpolation, même `CFrame.Angles(0, 0, π/2)` cylindre à plat) :

```
shockwave.CFrame = CFrame.new(ground.X, Config.TERRAIN_HEIGHT[Config.TERRAIN.PLAINS] + 0.5, ground.Z) * CFrame.Angles(0, 0, math.rad(90))
```

`ground` vient de `WorldSpace.tileToWorld(x, y)`. `fromEulerAnglesYXZ(0, 0, math.rad(90))` ≡ `Angles(0, 0, π/2)`. Distinct de N132 (`route.to` gare, pas hauteur plains). Distinct de Effects `conquestPulse` ring (`Y = 3`, leftover N134). Distinct de sphère Blast (`CFrame.new(ground.X, 14, ground.Z)` **sans** rotation — ne pas y toucher). Distinct de fumée (`CFrame.new` translation). Distinct de Tween `Size = Vector3.new` (API). `worldRadius * 2.5` **inchangé**.

**Pourquoi 20K CCU :** leftover N132. 8 clients × N frappes × `CFrame.Angles` + compose. Pas d’autorité (onde cosmétique). Un euler faux dresserait le disque de portée. Sphere / smoke / light : pas de `CFrame.Angles`. Interpolation 60 Hz **déjà** N125/N126 — ne pas y revenir. Insert pulse **déjà** N132 — ne pas y revenir.

**Worker :**

1. Dans `Overlay.explosion` seulement, `Shockwave` : poser `CFrame.new(ground.X, Config.TERRAIN_HEIGHT[Config.TERRAIN.PLAINS] + 0.5, ground.Z) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))`. Plus de `CFrame.Angles` sur cette onde. Hauteur `PLAINS + 0.5` **inchangée**. Tween Size/Transparency **inchangé**. Sphère / fumée / PointLight **inchangés**. `task.delay` Destroy **inchangé**.

2. **Garder la rotation.** Ne **pas** convertir en translation. Ne **pas** « fermer » Effects ring / WorldRenderer glints / BuildingModels `BuildRing` dans le même commit (leftover N134 / après). Ne pas « fermer » N132. Ne pas « fermer » flamme `Size`. Ne pas porter visual. Après N132. `applyUnits` **non**. `stepInterpolation` **non**.

3. Tests « navires, missiles et interpolation » leftover N131/N130/N128/N127/N125 **et** leftover N132 pose/capture **et** leftover N129 apercu **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client navires **doit rester vert** (`overlay:explosion(50, 50, 9)` en fin de check ne lève pas ; leftover N131 splash despawn ; leftover N130 wake spawn ; leftover N116 immobile ; leftover N125 yaw+roulis). Check pose leftover N132 pulse. Check apercu leftover N129. Check modeles leftover N124. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `Overlay.luau` (`explosion` `Shockwave` **seulement**). `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N133 (commentaire leftover, **garder** N131/N130/N56). `Effects.luau` **non**. `PlacementPreview.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. **N133 feel ≠ N132 (DeliveryPulse gare) ≠ N131 (LandingSplash mer) ≠ N130 (LaunchWake spawn) ≠ N134 (Effects ring Y=3) ≠ visual V75 (leftover `1b5c`, ne pas merger).** Non réentrant. Ne pas fusionner avec N134 dans le même worker. Sphere / smoke **sans** euler.

---

### ISSUE-N134 — Effects `conquestPulse` ring `CFrame.Angles` événement (feel)

**Priorité :** P3 alloc client Effects. Leftover explicite après N133 (shockwave Overlay). Distinct de N133 (Overlay nuke, `PLAINS + 0.5`), de N132 (DeliveryPulse gare Overlay), de N95 (`applyDelta` pools). Effects `conquestPulse` **seulement**. Ne pas toucher Overlay. Ne pas toucher WorldRenderer. Ne pas toucher `conquestWave` barycentre / caps.

**Problème :** N133 ferme le shockwave nuke. Reste, **une fois par vague de conquête / perte** (`Effects.conquestPulse`, appelé depuis `conquestWave` / `lossWave`, pas 60 Hz interpolation, même `CFrame.Angles(0, 0, π/2)` cylindre à plat) :

```
ring.CFrame = CFrame.new(ground.X, 3, ground.Z) * CFrame.Angles(0, 0, math.rad(90))
```

`ground` vient de `WorldSpace.tileToWorld(x, y)`. `fromEulerAnglesYXZ(0, 0, math.rad(90))` ≡ `Angles(0, 0, π/2)`. Distinct de N133 (`PLAINS + 0.5`, Overlay). Distinct de WorldRenderer OceanGlint (`CFrame.Angles(0, angle, 0)` yaw variable, leftover après N134). Distinct de BuildingModels `BuildRing` (`CFrame.new(ground) * Angles(0, 0, π/2)`, leftover après). Distinct de Tween `Size = Vector3.new` (API). Caps `MAX_FLASHES_PER_WAVE` / `MAX_LIVE_FLASHES` **inchangés**. Hauteur `Y = 3` **inchangée**.

**Pourquoi 20K CCU :** leftover N133. 8 clients × N vagues × `CFrame.Angles` + compose. Pas d’autorité (anneau cosmétique). Un euler faux dresserait l’onde de conquête. Flashes de tuile : pas de `CFrame.Angles`. Interpolation Overlay 60 Hz **déjà** N125/N126 — ne pas y revenir. Shockwave Overlay **déjà** N133 — ne pas y revenir.

**Worker :**

1. Dans `Effects.conquestPulse` seulement, ring : poser `CFrame.new(ground.X, 3, ground.Z) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))`. Plus de `CFrame.Angles` sur cet anneau. Hauteur `Y = 3` **inchangée**. Tween Size/Transparency **inchangé**. `task.delay` Destroy **inchangé**. Caps flash **inchangés**. `conquestWave` / `lossWave` barycentre **inchangés**.

2. **Garder la rotation.** Ne **pas** convertir en translation. Ne **pas** « fermer » WorldRenderer glints / décor trunks / BuildingModels `BuildRing` dans le même commit (leftover après N134). Ne pas « fermer » N133. Ne pas « fermer » flamme `Size`. Ne pas porter visual. Après N133. Overlay **non**. WorldRenderer **non**.

3. Tests « vagues de conquete » leftover N95 **et** leftover N133 navires (`explosion`) **et** leftover N132 pose **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client vagues **doit rester vert** (`conquestWave` 200 tuiles + `lossWave` + vague 1 tuile ne lèvent pas). Check navires leftover N133 shockwave / N131 splash. Check pose leftover N132 pulse. Check apercu leftover N129. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `Effects.luau` (`conquestPulse` ring **seulement**). `tests/client.luau` **seulement si** le check vagues ne mentionne pas encore N134 (commentaire leftover). `Overlay.luau` **non**. `WorldRenderer.luau` **non**. `BuildingModels.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. **N134 feel ≠ N133 (Overlay Shockwave plains) ≠ N132 (DeliveryPulse Overlay) ≠ WorldRenderer glints (leftover après) ≠ visual V75 (ne pas merger).** Non réentrant. Ne pas fusionner avec N133 dans le même worker. Caps flash **inchangés**.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; Overlay DeliveryPulse → **N132 fait** ; Overlay LandingSplash → **N131 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; Overlay LandingSplash → **N131 fait** ; Overlay DeliveryPulse → **N132 fait**) |
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
| N34–N130 | (voir rapport #155) | — | **faits** |
| N131 | Overlay LandingSplash `CFrame.Angles` événement | P3 | **fait** cette passe (despawn navire, Y + 0.14, skip retraite N56) |
| N132 | Overlay DeliveryPulse `CFrame.Angles` événement | P3 | **fait** cette passe (fin de trajet camion, `route.to`) |
| N133 | Overlay Shockwave `CFrame.Angles` événement | P3 | **nouveau** (`explosion`, `PLAINS + 0.5`) |
| N134 | Effects `conquestPulse` ring `CFrame.Angles` événement | P3 | **nouveau** (vague de conquête, `Y = 3`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde, N103 X/Z, N105 TRUCK_LIFT monde, N115 segRot HV, N117 yaw tuile, N125/N126 Overlay, N127/N128 UnitModels, N129 footprint, N130 LaunchWake, N131 splash, N132 pulse) |

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

Client : **35/35 OK** — dont `construction du monde 3D` (N114 compact leftover, N112 `dirtyHead`, N106/N107/N108) ; `pose et capture de chaque type de batiment` (N132 DeliveryPulse `fromEulerAnglesYXZ`, leftover N126 roues, leftover N115 `segRot`, leftover N113 `rot` chantier) ; `modeles procéduraux` (N124 radar/flag/boom `fromEulerAnglesYXZ`, leftover N109 câble Y, Parts stables, rotation visible CFrame ≠ RestCFrame, Y inchangé = pas une translation) ; `apercu de placement pour chaque batiment` (N129 footprint `fromEulerAnglesYXZ`, leftover N92 ctx, ghost visible / snap / upgrade, hauteur 0.4) ; `navires, missiles et interpolation` (N131 LandingSplash `fromEulerAnglesYXZ` ; leftover N130 LaunchWake ; leftover N128 flag ; leftover N127 radar euler ; leftover N125 roulis ; leftover N117 second frame lerp sous yaw euler ; leftover N116 navire immobile `currentX == targetX` ; leftover N103 lerp missile, N98 extra `rawequal`, N101 `targetX`, navire `extra == nil`, `retreatTinted` conservé ; `overlay:explosion` leftover N133) ; `livraison : le gain s'affiche sur la gare` leftover N20 ; `vagues de conquete` leftover N134. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `WorldCamera.luau` **non** touché. `UnitModels.luau` **non** touché. `WorldRenderer.luau` **non** touché. `BuildingModels.luau` **non** touché. `PlacementPreview.luau` **non** touché. `Effects.luau` **non** touché. `Minimap.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass51.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N131/N132 sont un euler Overlay vérifié par le banc headless (compose `CFrame.new * euler` ; stubs `fromEulerAnglesYXZ` déjà présents).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N131 n’ajoute **pas** de require (`fromEulerAnglesYXZ` local Overlay despawn). N132 n’ajoute **pas** de require (local Overlay delivery). N133 restera dans `Overlay.explosion`. N134 restera dans `Effects.conquestPulse`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N125 : `frame` a déjà translation × yaw — **ne pas** réduire à `CFrame.new * euler`. Immobile = zéro compose. Missile = pas de roulis. Recette visual V71 déjà sur `9ab9` — porter, ne pas merger.

Piège N126 : spin réel `progress * π * 20` dans un local `spin`. `frame` a déjà `segRot`. Ne pas cuire le spin dans `piece.offset`. Recette visual V72 déjà sur `9793` — porter, ne pas merger.

Piège N127 : garder `piece.offset * euler`, **ne pas** réduire à `CFrame.new(offset.X,Y,Z) * euler` (recette N124 bâtiments). Distinct SAM Radar N124 (`time * 1.45`). Leftover visual V73 déjà fermé sur `1b5c` (`localFrame * euler`, équivalent) — porter, ne pas merger.

Piège N128 : amplitude 0.06 / fréquence 5. Distinct CapitalFlag N124 (deux sin, rest identité). Ne pas fusionner avec N127. Leftover visual V73 déjà fermé sur `1b5c` — porter, ne pas merger.

Piège N129 : cylindre à plat Z=90. Ne pas omettre l’euler (le cylindre se dresserait). Hauteur feel **0.4** ≠ visual 0.42. Ne pas inventer `self.pulse`. Size footprint **API**. Visual V75 **fermée** sur `c0ec` (`footprintRot` + pulse) — porter euler worker #153, pas merger.

Piège N130 : insert navire seulement, pas `stepInterpolation`. Offset Y `+ 0.12` ≠ splash `+ 0.14`. Ne pas fusionner splash/pulse/shockwave.

Piège N131 : despawn non-retraite seulement. N56 skip retraite **conservé**. Distinct pulse N132 (`route.to` terre). Distinct wake N130 (`origin` spawn, Y `+ 0.12`).

Piège N132 : fin de `delivery` seulement, pas construction voie. `route.to` déjà Vector3 — ne pas `tileToWorld`. Distinct shockwave leftover N133.

Piège N133 (à venir) : `explosion` seulement. Sphère / fumée **sans** euler. Distinct Effects ring N134 (`Y = 3`).

Piège N134 (à venir) : `conquestPulse` seulement, pas Overlay. Caps flash **conservés**. Distinct WorldRenderer glints leftover.
