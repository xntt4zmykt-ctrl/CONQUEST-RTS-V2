# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 49)

Déclencheur : ouverture de la **PR #150** (`cursor/analyse-nocturne-du-codebase-396d`) — Overlay roulis/roues euler, specs N127–N128.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-5bde`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#150.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. Camera overview : lerp mire `fx/fy/fz` (N121) ; champs `focusX/Y/Z` (N122) ; shake `sx/sy/sz` (N119) ; offset YXZ `ox/oy/oz` (N120) ; pose `CFrame.new * rotation` (N118). Minimap : `setFocus(x,y,z)` nombres (N123). Radar / Flag / Boom : `fromEulerAnglesYXZ` (N124). Overlay navire : roulis `fromEulerAnglesYXZ` (N125). Overlay camion : roues `fromEulerAnglesYXZ` (N126). `UnitModels.place` radar : `fromEulerAnglesYXZ` (N127). `UnitModels.place` flag : `fromEulerAnglesYXZ` (N128). `PlacementPreview.update` footprint `CFrame.Angles` encore 60 Hz (leftover N129). Overlay LaunchWake `CFrame.Angles` événement (leftover N130).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #150 (passe 48) : claims vérifiés.** Overlay roulis `fromEulerAnglesYXZ(rx, 0, rz)` (N125) ; Overlay roues `fromEulerAnglesYXZ(spin, 0, 0)` (N126). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #151** (`1b5c`) a **fermé V73** en parallèle (`localFrame * fromEulerAnglesYXZ`) — recette **portée** ici via `piece.offset * euler` (équivalent, **pas mergée**).

Cette passe a **livré ce que #150 a documenté (N127, N128)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #150

| Claim #150 | Réalité à l’ouverture |
|---|---|
| Overlay navire roulis euler (N125) | Oui. `frame * fromEulerAnglesYXZ(rx, 0, rz)`. Recette visual V71, pas merger `9ab9`. |
| Overlay camion roues euler (N126) | Oui. `frame * offset * fromEulerAnglesYXZ(spin, 0, 0)`. Recette visual V72, pas merger `9793`. UnitModels `CFrame.Angles` restait (leftover N127/N128). |
| Specs N127–N128 | **Corrigés ici.** N127 = `UnitModels.place` radar `piece.offset * fromEulerAnglesYXZ(0, time * 2.2, 0)` (leftover visual V73 — **porté, pas mergé** ; visual `1b5c` / PR #151 a fermé V73 avec `localFrame * euler`, équivalent). N128 = `UnitModels.place` flag `piece.offset * fromEulerAnglesYXZ(rx, 0, 0)` (même leftover V73, **porté, pas mergé**). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #149/`f593` (N99–N102), feel jusqu’à #150, visuelles #39/…/`9793` V72 **fermé** ; `1b5c` / PR #151 V73 **fermé** (porté ici, pas mergé) + leftover V74 flame Size / V75 PlacementPreview. **#150 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `1b5c` / `9793` / `9ab9` ni hardening `24a7` / `f593` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. N127/N128 sont cosmétique client. Risques documentés, non corrigés ici (hors N127/N128) : `JoinRequest` hors IntentValidator ; Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N127/N128. Latent hors hot path : `buildCarrier` mesh (`CARRIER_MESH_ID ~= ""`) écrit `visual.parts` au lieu de `visual.pieces` — mort tant que l’id est `""`, **non corrigé** (hors spec).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N127–N128 du rapport #150. Commits séparés (N127 puis N128).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `UnitModels.place` radar `CFrame.Angles` 60 Hz (N127) | `UnitModels.luau` (`place` branche `role == "radar"`), `tests/client.luau` (check navires) | Leftover N126. `piece.offset * fromEulerAnglesYXZ(0, time * 2.2, 0)`. Facteur 2.2 inchangé. Pas `CFrame.new(offset.X,Y,Z) * euler` (recette N124). Leftover visual V73 déjà sur `9793`, **pas** merger. Cosmétique. Overlay N125 **inchangé**. |
| `UnitModels.place` flag `CFrame.Angles` 60 Hz (N128) | `UnitModels.luau` (`place` branche `role == "flag"`), `tests/client.luau` (check navires) | Leftover N127. Local `rx = sin(time * 5) * 0.06`, `piece.offset * fromEulerAnglesYXZ(rx, 0, 0)`. Amplitude 0.06 / fréquence 5 inchangées. Leftover visual V73 déjà sur `9793`, **pas** merger. Cosmétique. Radar N127 **inchangé**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), `PlacementPreview` footprint (**N129**), Overlay LaunchWake (**N130**), flamme `Size = Vector3.new` (Size = API), tribus `humanTargetProtected`. Overlay / BuildingModels / WorldRenderer / WorldCamera / HUD / Minimap / serveur **non édités**.

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
- Overlay interpolation X/Z + yaw euler (**N117**) **et** camion `segRot` (**N115**) **et** roulis navire (**N125**) **et** roues camion (**N126**). Camera : lerp nombres (**N121**) + champ `focusX/Y/Z` (**N122**) + shake (**N119**) + offset (**N120**) + pose (**N118**). Minimap `setFocus(x,y,z)` (**N123**). Radar/Flag/Boom euler (**N124**). `UnitModels.place` radar euler (**N127**) **et** flag euler (**N128**). `PlacementPreview.update` footprint `CFrame.Angles` encore 60 Hz (**N129**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N129–N130)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N128 = faits. N22 = **N67 fait**. N27 = doc only. **V73 / N127 / N128** fermés ici (portés, pas mergés ; V73 déjà livré visuel `1b5c` / PR #151). Leftover feel `PlacementPreview.update` footprint = **N129** (leftover visual V75 déjà sur `1b5c`, porter ne pas merger ; feel **n’a pas** `self.pulse`, hauteur **0.4** ≠ visual 0.42). Leftover feel Overlay LaunchWake = **N130** (V75 distingue les événements Overlay). Flamme `Size = Vector3.new` = leftover visual V74 (Size = API, Option A : ne pas convertir en CFrame, ne pas en faire N129).

---

### ISSUE-N129 — `PlacementPreview.update` footprint `CFrame.Angles` 60 Hz (feel)

**Priorité :** P3 alloc client PlacementPreview. Leftover explicite de N128 (flag pièce déjà). Leftover visual V75 **déjà documenté** sur `1b5c` (passe 56 visual) — **porter euler, ne pas merger** `1b5c`. Distinct de N124 (BuildingModels Radar, rest identité), de N125 (roulis Overlay `frame`), de N127/N128 (`UnitModels.place` pièces navire). Distinct de visual V74 (flame Size API). `PlacementPreview.update` **seulement**. Ne pas toucher Overlay ni UnitModels ni BuildingModels. Feel **n’a pas** `self.pulse` (visual V75 en a un) — **ne pas l’inventer**. Hauteur feel `ground + 0.4` ≠ visual `+ 0.42` — **garder 0.4**.

**Problème :** N128 ferme le flag pièce. Reste, **une fois par frame pendant le hover placement** (`init.client` `RenderStepped` → `p:update(landing, status)`) :

```
self.footprint.CFrame = CFrame.new(base.X, ground + 0.4, base.Z) * CFrame.Angles(0, 0, math.rad(90))
```

Cylindre à plat (rayon bunker / tuile). `fromEulerAnglesYXZ(0, 0, math.rad(90))` ≡ `Angles(0, 0, π/2)` ici (seulement Z). Distinct de N108 feuillage (translation Y, plus de tilt). Distinct de N124 Boom (`sin(time * 0.35) * 0.12`, rest identité, 60 Hz animate). Distinct des `CFrame.Angles` Overlay LaunchWake / splash / pulse / shockwave (événements, leftover N130). Distinct de flamme `Size = Vector3.new` (Size = API). `self.footprint.Size = Vector3.new(0.3, radius, radius)` **inchangé** (Size = API, leftover séparé). `self.tile ~= tile` repositionnement `Vector3.new(base.X, ground, base.Z)` **inchangé** (seulement si tuile change, pas 60 Hz idle).

**Pourquoi 20K CCU :** leftover N128. 8 clients × 60 Hz × 1 footprint × `CFrame.Angles` + compose **pendant tout le mode construction**. Pas d’autorité (ghost cosmétique). Un euler faux coucherait le disque (cylindre debout au lieu de plat). Hors placement (`kind` nil / `hide`) : early-out Transparency, la ligne n’est pas atteinte — ne pas l’ajouter.

**Worker :**

1. Dans `PlacementPreview.update` seulement, ligne `self.footprint.CFrame` : poser `CFrame.new(base.X, ground + 0.4, base.Z) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))`. Plus de `CFrame.Angles` 60 Hz sur le hot path footprint. Angle `math.rad(90)` **inchangé**. Garde `kind` / `tile` / `status` **inchangée**. `Size = Vector3.new` **inchangé** (API).

2. **Garder la rotation.** Ne **pas** convertir en translation (N108 feuillage). Ne **pas** cuire le Z=90 dans un `RestCFrame` (le `base` change à chaque tuile). Ne **pas** réduire à `CFrame.new` sans euler (le cylindre se dresserait). Option visual V75 `footprintRot` cuit à `new` (recette N113 `segment.rot`) **autorisée**. Ne pas « fermer » N127/N128 UnitModels (déjà). Ne pas « fermer » Overlay LaunchWake (leftover N130). Ne pas « fermer » flamme `Size` (leftover visual V74, Size = API). Ne pas inventer `self.pulse`. Ne pas merger visual `1b5c`. Après N128. Leftover visual V75 déjà sur `1b5c` — porter euler, pas merger visual.

3. Tests « apercu de placement pour chaque batiment » **et** leftover N124 modeles **et** leftover N127/N128 navires **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client « apercu de placement » **doit rester vert** (ghost visible, snap, upgrade). Check « pose et capture » leftover N126 `segRot` **doit rester vert**. Check navires leftover N128 flag / N127 radar / N125 roulis / N116 immobile **doivent rester verts**. Check modeles leftover N124. Check camera leftover N122. Check minimap leftover N123. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `PlacementPreview.luau` (`update` ligne `footprint.CFrame` **seulement**). `tests/client.luau` **seulement si** le check apercu ne mentionne pas encore N129 (commentaire leftover, **garder** N92 ctx). `UnitModels.luau` **non**. `Overlay.luau` **non**. `BuildingModels.luau` **non**. `init.client.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. **N129 feel ≠ N127/N128 (pièces navire) ≠ N124 (SAM Radar rest identité) ≠ N125 (roulis Overlay) ≠ N130 (LaunchWake événement) ≠ visual V75 (leftover `1b5c`, pulse + 0.42 — ne pas merger) ≠ visual V74 (flame Size).** Non réentrant. Ne pas fusionner avec N130 dans le même worker. `previewCtx` N92 **inchangé**. Closures hover N99 **inchangées**.

---

### ISSUE-N130 — Overlay LaunchWake `CFrame.Angles` événement (feel)

**Priorité :** P3 alloc client Overlay. Leftover explicite après N129 (footprint hover). Visual V75 **distingue** wake / splash / pulse livraison Overlay (événement, pas hover). Distinct de N129 (PlacementPreview 60 Hz), de N125 (roulis interpolation), de N126 (roues). Overlay `applyUnits` branche insert navire **seulement**. Ne pas toucher `stepInterpolation`. Ne pas toucher UnitModels ni PlacementPreview.

**Problème :** N129 ferme le footprint hover. Reste, **une fois par navire spawn** (pas 60 Hz interpolation, mais même `CFrame.Angles(0, 0, π/2)` cylindre à plat) :

```
wake.CFrame = CFrame.new(origin.X, Config.OCEAN_LEVEL + 0.12, origin.Z) * CFrame.Angles(0, 0, math.rad(90))
```

Branche `if not isMissile` à l’insert. `fromEulerAnglesYXZ(0, 0, math.rad(90))` ≡ `Angles(0, 0, π/2)`. Distinct de N129 (même euler, autre fichier, 60 Hz vs événement). Distinct de splash retraite (`last.X` / `+ 0.14`, leftover après N130). Distinct de pulse livraison (`route.to`, leftover). Distinct de shockwave nuke (`TERRAIN_HEIGHT[PLAINS] + 0.5`, leftover). Distinct de Tween `Size = Vector3.new` (API). Wake Overlay `role` UnitModels Transparency **inchangé** (N127/N128 n’y touchent pas).

**Pourquoi 20K CCU :** leftover N129. 8 clients × N spawns navire × `CFrame.Angles` + compose. Pas d’autorité (splash cosmétique). Un euler faux dresserait le sillage. Missiles : la branche n’est pas atteinte. Interpolation 60 Hz **déjà** N125/N126/N127/N128 — ne pas y revenir.

**Worker :**

1. Dans `Overlay.applyUnits` seulement, insert navire `LaunchWake` : poser `CFrame.new(origin.X, Config.OCEAN_LEVEL + 0.12, origin.Z) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))`. Plus de `CFrame.Angles` sur ce spawn. Offset Y `OCEAN_LEVEL + 0.12` **inchangé**. Garde `not isMissile` **inchangée**. Tween Size/Transparency **inchangé**. `task.delay` Destroy **inchangé**.

2. **Garder la rotation.** Ne **pas** convertir en translation. Ne **pas** « fermer » splash / pulse / shockwave dans le même commit (leftover après N130). Ne pas « fermer » N129. Ne pas « fermer » flamme `Size`. Ne pas porter visual. Après N129. `stepInterpolation` **non**.

3. Tests « navires, missiles et interpolation » leftover N128/N127/N125 **et** leftover N126 pose/capture **et** leftover N129 apercu **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client navires **doit rester vert** (insert + wake spawn ne lève pas ; leftover N116 immobile ; leftover N125 yaw+roulis ; leftover N127/N128 euler pièces). Check pose/capture leftover N126. Check apercu leftover N129. Check modeles leftover N124. Check camera leftover N122. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `Overlay.luau` (`applyUnits` insert `LaunchWake` **seulement**). `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N130 (commentaire leftover, **garder** N128/N127/N125). `UnitModels.luau` **non**. `PlacementPreview.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. **N130 feel ≠ N129 (footprint 60 Hz) ≠ N125 (roulis interpolation) ≠ N126 (roues) ≠ splash/pulse/shockwave (leftover après).** Non réentrant. Ne pas fusionner avec N129 dans le même worker. Construction `addWake` UnitModels `CFrame.Angles` **inchangée** (une fois à `create`).

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; Overlay roues → **N126 fait** ; UnitModels radar → **N127 fait** ; UnitModels flag → **N128 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; UnitModels flag → **N128 fait**) |
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
| N34–N126 | (voir rapport #150) | — | **faits** |
| N127 | `UnitModels.place` radar `CFrame.Angles` 60 Hz | P3 | **fait** cette passe (leftover visual V73, porté pas mergé) |
| N128 | `UnitModels.place` flag `CFrame.Angles` 60 Hz | P3 | **fait** cette passe (leftover visual V73, porté pas mergé) |
| N129 | `PlacementPreview.update` footprint `CFrame.Angles` 60 Hz | P3 | **nouveau** (leftover visual V75 déjà sur `1b5c`, ne pas merger ; feel hauteur 0.4, pas de pulse) |
| N130 | Overlay LaunchWake `CFrame.Angles` événement | P3 | **nouveau** (V75 distingue les événements Overlay) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde, N103 X/Z, N105 TRUCK_LIFT monde, N115 segRot HV, N117 yaw tuile, N125/N126 Overlay, N127/N128 UnitModels) |

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

Client : **35/35 OK** — dont `construction du monde 3D` (N114 compact leftover, N112 `dirtyHead`, N106/N107/N108) ; `pose et capture de chaque type de batiment` (N126 roues `fromEulerAnglesYXZ`, leftover N115 `segRot`, leftover N113 `rot` chantier) ; `modeles procéduraux` (N124 radar/flag/boom `fromEulerAnglesYXZ`, leftover N109 câble Y, Parts stables, rotation visible CFrame ≠ RestCFrame, Y inchangé = pas une translation) ; `navires, missiles et interpolation` (N128 flag `fromEulerAnglesYXZ` ; leftover N127 radar euler ; leftover N125 roulis ; leftover N117 second frame lerp sous yaw euler ; leftover N116 navire immobile `currentX == targetX` ; leftover N103 lerp missile, N98 extra `rawequal`, N101 `targetX`, navire `extra == nil`, `retreatTinted` conservé) ; `camera strategique` (N122 `focusX` lerp avance sans sauter ; N121 œil `fx + ox` ; N120 formule `ox/oy/oz` à pitch défaut 58° ; N119 punch + décroissance ; leftover N118 `CFrame.X` nombre, leftover tactile pincement/torsion) ; `minimap` (N123 `setFocus(0,0,0)` → u=0.5, v=0.5 ; marqueur suit `focusX`/`focusZ`). `livraison : le gain s'affiche sur la gare` inchangé. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `WorldCamera.luau` **non** touché. `PlacementPreview.luau` **non** touché. `Overlay.luau` **non** touché. `WorldRenderer.luau` **non** touché. `BuildingModels.luau` **non** touché. `Minimap.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass49.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N127/N128 sont un euler UnitModels vérifié par le banc headless (compose `offset * euler` ; stubs `fromEulerAnglesYXZ` déjà présents).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N127 n’ajoute **pas** de require (`fromEulerAnglesYXZ` local UnitModels). N128 n’ajoute **pas** de require (local `rx` UnitModels). N129 restera dans `PlacementPreview.update`. N130 restera dans `Overlay.applyUnits`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N125 : `frame` a déjà translation × yaw — **ne pas** réduire à `CFrame.new * euler`. Immobile = zéro compose. Missile = pas de roulis. Recette visual V71 déjà sur `9ab9` — porter, ne pas merger.

Piège N126 : spin réel `progress * π * 20` dans un local `spin`. `frame` a déjà `segRot`. Ne pas cuire le spin dans `piece.offset`. Recette visual V72 déjà sur `9793` — porter, ne pas merger.

Piège N127 : garder `piece.offset * euler`, **ne pas** réduire à `CFrame.new(offset.X,Y,Z) * euler` (recette N124 bâtiments). Distinct SAM Radar N124 (`time * 1.45`). Leftover visual V73 déjà fermé sur `1b5c` (`localFrame * euler`, équivalent) — porter, ne pas merger.

Piège N128 : amplitude 0.06 / fréquence 5. Distinct CapitalFlag N124 (deux sin, rest identité). Ne pas fusionner avec N127. Leftover visual V73 déjà fermé sur `1b5c` — porter, ne pas merger.

Piège N129 (à venir) : cylindre à plat Z=90. Ne pas omettre l’euler. Distinct LaunchWake N130 (événement). Size footprint **API**.

Piège N130 (à venir) : insert navire seulement, pas `stepInterpolation`. Ne pas fusionner splash/pulse/shockwave. Distinct N129 (60 Hz hover).
