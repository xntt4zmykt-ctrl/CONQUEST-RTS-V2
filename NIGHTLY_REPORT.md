# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 48)

Déclencheur : ouverture de la **PR #147** (`cursor/analyse-nocturne-du-codebase-71f0`) — Minimap nombres, Radar/Flag/Boom euler, specs N125–N126.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-396d`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#147.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. Camera overview : lerp mire `fx/fy/fz` (N121) ; champs `focusX/Y/Z` (N122) ; shake `sx/sy/sz` (N119) ; offset YXZ `ox/oy/oz` (N120) ; pose `CFrame.new * rotation` (N118). Minimap : `setFocus(x,y,z)` nombres (N123). Radar / Flag / Boom : `fromEulerAnglesYXZ` (N124). Overlay navire : roulis `fromEulerAnglesYXZ` (N125). Overlay camion : roues `fromEulerAnglesYXZ` (N126). `UnitModels.place` radar/flag `CFrame.Angles` encore 60 Hz (leftover N127–N128).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #147 (passe 47) : claims vérifiés.** Minimap `setFocus(x,y,z)` (N123) ; Radar/Flag/Boom euler (N124). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #147 a documenté (N125, N126)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #147

| Claim #147 | Réalité à l’ouverture |
|---|---|
| Minimap.setFocus nombres (N123) | Oui. `(x,y,z)`, y ignoré, origine → u=0.5/v=0.5. Recette visual V69 leftover minimap, pas merger `c5c9`. |
| BuildingModels Radar/Flag/Boom euler (N124) | Oui. `CFrame.new(rest.X,Y,Z) * fromEulerAnglesYXZ`. Recette visual V70, pas merger `06ee`. Overlay `CFrame.Angles` restait (leftover N125/N126). |
| Specs N125–N126 | **Corrigés ici.** N125 = Overlay navire roulis `fromEulerAnglesYXZ(rx, 0, rz)` (recette visual V71 déjà fermée sur `9ab9` / PR #143 — **porté, pas mergé**). N126 = Overlay camion roues `fromEulerAnglesYXZ(spin, 0, 0)` (leftover visual V72 déjà sur `9ab9` — **porté, pas mergé**). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #141/`24a7` (N97–N98), feel jusqu’à #147, visuelles #39/…/`9ab9` V71 **fermé** + leftover V72 roues (porté ici, pas mergé). **#147 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `9ab9` / `06ee` / `c5c9` ni hardening `4c70` / `24a7` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. N125/N126 sont cosmétique client. Risques documentés, non corrigés ici (hors N125/N126) : `JoinRequest` hors IntentValidator ; Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N125/N126.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N125–N126 du rapport #147. Commits séparés (N125 puis N126).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Overlay navire `CFrame.Angles` roulis 60 Hz (N125) | `Overlay.luau` (`stepInterpolation` branche `mag > 0.01 and not isMissile`), `tests/client.luau` (check navires) | Leftover N124. Locaux `rx`/`rz`, `frame * fromEulerAnglesYXZ`. Amplitude 0.018/0.035, fréquences 1.7/2.1 inchangées. Immobile / missile : zéro compose. Recette visual V71 déjà sur `9ab9`, **pas** merger. Cosmétique. Yaw N117 **inchangé**. |
| Overlay camion roues `CFrame.Angles` 60 Hz (N126) | `Overlay.luau` (`stepInterpolation` branche `Wheel`), `tests/client.luau` (check pose/capture) | Leftover N125. Local `spin = progress * π * 20`, `frame * offset * fromEulerAnglesYXZ`. Pièces non-Wheel inchangées. Recette visual V72 leftover déjà sur `9ab9`, **pas** merger. Cosmétique. `segRot` N115 **inchangé**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), `UnitModels.place` radar (**N127**), `UnitModels.place` flag (**N128**), tribus `humanTargetProtected`. BuildingModels / WorldRenderer / WorldCamera / HUD / UnitModels / Minimap / serveur **non édités**.

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
- Overlay interpolation X/Z + yaw euler (**N117**) **et** camion `segRot` (**N115**) **et** roulis navire (**N125**) **et** roues camion (**N126**). Camera : lerp nombres (**N121**) + champ `focusX/Y/Z` (**N122**) + shake (**N119**) + offset (**N120**) + pose (**N118**). Minimap `setFocus(x,y,z)` (**N123**). Radar/Flag/Boom euler (**N124**). `UnitModels.place` radar `CFrame.Angles` encore 60 Hz (**N127**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N127–N128)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N126 = faits. N22 = **N67 fait**. N27 = doc only. **V71 / N125** fermés ici (portés, pas mergés ; V71 déjà livré visuel `9ab9`). **V72 leftover / N126** fermés ici (portés, pas mergés ; leftover visual V72 déjà documenté sur `9ab9`). Leftover feel `UnitModels.place` radar = **N127** (pas encore de recette visual — visual `9ab9` l’a listé leftover, ne pas merger). Leftover feel `UnitModels.place` flag = **N128**.

---

### ISSUE-N127 — `UnitModels.place` radar `CFrame.Angles` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite de N126 (roues Overlay déjà). Distinct de N124 (BuildingModels Radar, `RestCFrame` identité, `time * 1.45`), de N125 (roulis Overlay sur le `frame` unité), de N128 (flag pièce). Visual `9ab9` a listé radar/flag leftover après V72 — **porter euler nombres, ne pas merger** `9ab9`. `UnitModels.place` branche `piece.role == "radar"` **seulement**. Ne pas toucher Overlay ni BuildingModels.

**Problème :** N126 ferme les roues camion Overlay. Reste, **une fois par frame par pièce radar de navire** dans `UnitModels.place` (appelé depuis `Overlay.stepInterpolation`) :

```
localFrame = piece.offset * CFrame.Angles(0, time * 2.2, 0)
```

Branche `piece.role == "radar"` seulement. `piece.offset` est posé à la construction (`CFrame.new(x, y, z)` translation, îlot carrier / cargo). `frame` Overlay a **déjà** translation × yaw (N117) × roulis (N125). Donc on compose `frame * (offset * euler)` — **ne pas** réduire le radar à `CFrame.new(offset.X,Y,Z) * euler` façon N124 (`RestCFrame` bâtiments) : garder `piece.offset * euler` pour ne pas casser un offset qui porterait déjà une rotation. `fromEulerAnglesYXZ(0, time * 2.2, 0)` ≡ `Angles(0, yaw, 0)` ici (seulement Y). Distinct de N124 (SAM Radar, `time * 1.45`, rest identité). Distinct de N125 (roulis `rx`/`rz` sur le `frame` unité). Distinct du flag `CFrame.Angles(sin, 0, 0)` (leftover N128). Distinct de `role == "flame"` `Size = Vector3.new` (leftover séparé, pas Angles). Wake / splash Overlay `CFrame.Angles` = événement, pas 60 Hz interpolation. Construction `addPart` `CFrame.Angles` (étrave, sillage) = pose unique, pas 60 Hz.

**Pourquoi 20K CCU :** leftover N126. 8 clients × 60 Hz × N navires (carrier + cargo) × 1 radar × `CFrame.Angles` + compose. Pas d’autorité (silhouette cosmétique). Un euler faux casserait le scan visuel des îlots. Missiles n’ont pas de pièce `radar` — ne pas en ajouter. `role` autres (hull, wake, flame, trail, light) **inchangés**.

**Worker :**

1. Dans `UnitModels.place` seulement, branche `piece.role == "radar"` : poser `localFrame = piece.offset * CFrame.fromEulerAnglesYXZ(0, time * 2.2, 0)`. Plus de `CFrame.Angles` 60 Hz sur le hot path radar. Facteur `time * 2.2` **inchangé**. Garde `role == "radar"` **inchangée**. `piece.part.CFrame = frame * localFrame` **inchangé**.

2. **Garder la rotation.** Ne **pas** convertir en translation (N108 feuillage). Ne **pas** cuire le yaw dans `piece.offset` (le `time` change chaque frame). Ne **pas** réduire à `CFrame.new(offset.X,Y,Z) * euler` (recette N124 bâtiments — offset pièce, pas RestCFrame). Ne pas « fermer » N125/N126 Overlay (déjà). Ne pas « fermer » flag (leftover N128). Ne pas « fermer » flamme `Size`. Ne pas porter BuildingModels. Après N126. Visual `9ab9` leftover radar/flag — porter euler, pas merger visual.

3. Tests « navires, missiles et interpolation » leftover N125/N117/N116 **et** leftover N126 pose/capture `segRot` **et** leftover N124 modeles radar/flag/boom **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client « navires, missiles et interpolation » **doit rester vert** : second `applyUnits` extra mute N98 ; `targetX` N101 ; `stepInterpolation` après cible déplacée avance `currentX` **et** `currentY` ; premier `stepInterpolation` unités immobiles ne casse pas (`currentX == targetX`, leftover N116). Leftover N125 yaw+roulis euler **doit rester vert**. Leftover N126 `segRot` pose/capture **doit rester vert**. Leftover N124 modeles procéduraux **doit rester vert**. Leftover N123 minimap **doit rester vert**. Leftover N122 camera `focusX` **doit rester vert**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` branche `role == "radar"` **seulement**). `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N127 (commentaire leftover, **garder** N125/N117/N116/N101/N98). `Overlay.luau` **non**. `BuildingModels.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. **N127 feel ≠ N124 (SAM Radar rest identité, `time * 1.45`) ≠ N125 (roulis Overlay `frame`) ≠ N126 (roues camion) ≠ N128 (flag pièce) ≠ visual leftover `9ab9` (ne pas merger).** Non réentrant. Ne pas fusionner avec N128 dans le même worker. Autres `role` : zéro compose Angles. Construction `addPart` `CFrame.Angles` **inchangée**.

---

### ISSUE-N128 — `UnitModels.place` flag `CFrame.Angles` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N127 (radar pièce). Distinct de N127 (radar Y), de N124 (CapitalFlag bâtiments, deux `sin`, rest identité), de N125 (roulis Overlay). Visual `9ab9` leftover flag — **porter euler nombres, ne pas merger** `9ab9`. `UnitModels.place` branche `piece.role == "flag"` **seulement**. Ne pas toucher Overlay ni BuildingModels.

**Problème :** N127 ferme le radar pièce. Reste, **une fois par frame par pièce flag de navire** dans `UnitModels.place` :

```
localFrame = piece.offset * CFrame.Angles(math.sin(time * 5) * 0.06, 0, 0)
```

Branche `piece.role == "flag"` seulement. `piece.offset` = `CFrame.new` translation (mât carrier / cargo). Même compose `frame * (offset * euler)` que N127 — **ne pas** réduire à `CFrame.new(offset.X,Y,Z) * euler` (recette N124). `fromEulerAnglesYXZ(rx, 0, 0)` ≡ `Angles(rx, 0, 0)` ici (seulement X). Distinct de N127 (radar Y `time * 2.2`). Distinct de N124 CapitalFlag (`sin(time*2.4)*0.045` + `sin(time*1.7)*0.035`, rest identité). Distinct de N125 (roulis Overlay deux `sin` sur le `frame`). Distinct de flamme `Size = Vector3.new` (leftover séparé). Amplitude **0.06**, fréquence **5** — ne **pas** convertir en translation.

**Pourquoi 20K CCU :** leftover N127. 8 clients × 60 Hz × N navires × 1 flag × `CFrame.Angles` + compose. Pas d’autorité (silhouette cosmétique). Un euler faux casserait le clapotis du tissu sur l’îlot. Missiles n’ont pas de pièce `flag`. Autres `role` **inchangés**.

**Worker :**

1. Dans `UnitModels.place` seulement, branche `piece.role == "flag"` : lire `math.sin(time * 5) * 0.06` dans un local `rx`, poser `localFrame = piece.offset * CFrame.fromEulerAnglesYXZ(rx, 0, 0)`. Plus de `CFrame.Angles` 60 Hz sur le hot path flag. Amplitude 0.06 et fréquence 5 **inchangées**. Garde `role == "flag"` **inchangée**. `piece.part.CFrame = frame * localFrame` **inchangé**. Radar N127 **inchangé**.

2. **Garder la rotation.** Ne **pas** convertir en translation (N108 feuillage). Ne **pas** cuire le `sin` dans `piece.offset`. Ne **pas** réduire à `CFrame.new(offset.X,Y,Z) * euler` (recette N124). Ne pas « fermer » N127 dans le même commit. Ne pas « fermer » flamme `Size`. Ne pas porter BuildingModels ni Overlay. Après N127. Visual `9ab9` leftover flag — porter, pas merger visual.

3. Tests « navires, missiles et interpolation » leftover N127/N125 **et** leftover N126 pose/capture **et** leftover N124 modeles **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client navires **doit rester vert** : leftover N116 immobile, leftover N125 yaw+roulis, leftover N127 radar euler. Check pose/capture leftover N126 `segRot`. Check modeles leftover N124 CapitalFlag (bâtiments, pas UnitModels). Check camera leftover N122. Check minimap leftover N123. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` branche `role == "flag"` **seulement**). `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N128 (commentaire leftover, **garder** N127/N125/N117). `Overlay.luau` **non**. `BuildingModels.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. **N128 feel ≠ N127 (radar Y) ≠ N124 (CapitalFlag rest identité, deux sin) ≠ N125 (roulis Overlay) ≠ visual leftover `9ab9` (ne pas merger).** Non réentrant. Ne pas fusionner avec N127 dans le même worker. Autres `role` : zéro compose Angles. Sans pièce flag (missile) : la branche n’est pas atteinte.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; Radar euler → **N124 fait** ; Overlay roulis → **N125 fait** ; Overlay roues → **N126 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; Overlay roues → **N126 fait**) |
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
| N34–N124 | (voir rapport #147) | — | **faits** |
| N125 | Overlay navire `CFrame.Angles` roulis 60 Hz | P3 | **fait** cette passe (recette visual V71) |
| N126 | Overlay camion roues `CFrame.Angles` 60 Hz | P3 | **fait** cette passe (leftover visual V72) |
| N127 | `UnitModels.place` radar `CFrame.Angles` 60 Hz | P3 | **nouveau** (visual `9ab9` leftover, ne pas merger) |
| N128 | `UnitModels.place` flag `CFrame.Angles` 60 Hz | P3 | **nouveau** (visual `9ab9` leftover, ne pas merger) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde, N103 X/Z, N105 TRUCK_LIFT monde, N115 segRot HV, N117 yaw tuile, N125/N126 euler Overlay) |

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

Client : **35/35 OK** — dont `construction du monde 3D` (N114 compact leftover, N112 `dirtyHead`, N106/N107/N108) ; `pose et capture de chaque type de batiment` (N126 roues `fromEulerAnglesYXZ`, leftover N115 `segRot`, leftover N113 `rot` chantier) ; `modeles procéduraux` (N124 radar/flag/boom `fromEulerAnglesYXZ`, leftover N109 câble Y, Parts stables, rotation visible CFrame ≠ RestCFrame, Y inchangé = pas une translation) ; `navires, missiles et interpolation` (N125 roulis `fromEulerAnglesYXZ` ; leftover N117 second frame lerp sous yaw euler ; leftover N116 navire immobile `currentX == targetX` ; leftover N103 lerp missile, N98 extra `rawequal`, N101 `targetX`, navire `extra == nil`, `retreatTinted` conservé) ; `camera strategique` (N122 `focusX` lerp avance sans sauter ; N121 œil `fx + ox` ; N120 formule `ox/oy/oz` à pitch défaut 58° ; N119 punch + décroissance ; leftover N118 `CFrame.X` nombre, leftover tactile pincement/torsion) ; `minimap` (N123 `setFocus(0,0,0)` → u=0.5, v=0.5 ; marqueur suit `focusX`/`focusZ`). `livraison : le gain s'affiche sur la gare` inchangé. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `WorldCamera.luau` **non** touché. `PlacementPreview.luau` **non** touché. `UnitModels.luau` **non** touché. `WorldRenderer.luau` **non** touché. `BuildingModels.luau` **non** touché. `Minimap.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass48.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N125/N126 sont un euler Overlay vérifié par le banc headless (compose `frame * euler` ; stubs `fromEulerAnglesYXZ` déjà présents).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N125 n’ajoute **pas** de require (nombres locaux Overlay). N126 n’ajoute **pas** de require (local `spin` Overlay). N127 restera dans `UnitModels.place`. N128 restera dans `UnitModels.place`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N125 : `frame` a déjà translation × yaw — **ne pas** réduire à `CFrame.new * euler`. Immobile = zéro compose. Missile = pas de roulis. Recette visual V71 déjà sur `9ab9` — porter, ne pas merger.

Piège N126 : spin réel `progress * π * 20` dans un local `spin`. `frame` a déjà `segRot`. Ne pas cuire le spin dans `piece.offset`. Recette visual V72 leftover déjà sur `9ab9` — porter, ne pas merger.

Piège N127 (à venir) : garder `piece.offset * euler`, **ne pas** réduire à `CFrame.new(offset.X,Y,Z) * euler` (recette N124 bâtiments). Distinct SAM Radar N124 (`time * 1.45`). Visual `9ab9` leftover — porter, ne pas merger.

Piège N128 (à venir) : amplitude 0.06 / fréquence 5. Distinct CapitalFlag N124 (deux sin, rest identité). Ne pas fusionner avec N127.
