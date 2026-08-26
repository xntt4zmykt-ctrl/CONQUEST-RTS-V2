# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 47)

Déclencheur : ouverture de la **PR #144** (`cursor/analyse-nocturne-du-codebase-4d8e`) — WorldCamera lerp/champ focus, specs N123–N124.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-71f0`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#144.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. Camera overview : lerp mire `fx/fy/fz` (N121) ; champs `focusX/Y/Z` (N122) ; shake `sx/sy/sz` (N119) ; offset YXZ `ox/oy/oz` (N120) ; pose `CFrame.new * rotation` (N118). Minimap : `setFocus(x,y,z)` nombres (N123). Radar / Flag / Boom : `fromEulerAnglesYXZ` (N124). Overlay navire : `CFrame.Angles` roulis encore 60 Hz (leftover N125).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #144 (passe 46) : claims vérifiés.** Lerp `fx/fy/fz` (N121) ; champs `focusX/Y/Z` (N122). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #144 a documenté (N123, N124)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #144

| Claim #144 | Réalité à l’ouverture |
|---|---|
| WorldCamera lerp focus nombres (N121) | Oui. `fx/fy/fz`, un `Vector3.new` d’écriture fermé ensuite en N122. Recette visual V68, pas merger `0231`. |
| WorldCamera champ `focusX/Y/Z` (N122) | Oui. Plus de Vector3 idle dans `step`. `focusTile(instant)` synchronise nombres **et** `self.focus`. Recette visual V69 champs, pas merger `c5c9`. `Minimap.setFocus` restait Vector3 (leftover N123). |
| Specs N123–N124 | **Corrigés ici.** N123 = `Minimap.setFocus(x,y,z)` (recette visual V69 leftover minimap déjà fermée sur `c5c9` / PR #142 — **porté, pas mergé**). N124 = Radar/Flag/Boom `fromEulerAnglesYXZ` (recette visual V70 déjà fermée sur `06ee` / PR #143 — **porté, pas mergé**). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #141/`24a7` (N97–N98), feel jusqu’à #144, visuelles #39/…/`c5c9` V69 **fermé** ; `06ee` V70 Radar **fermé** ; `9ab9` V71 roulis Overlay **fermé** + leftover V72 roues camion. **#144 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `9ab9` / `06ee` / `c5c9` ni hardening `4c70` / `24a7` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. N123/N124 sont cosmétique client. Risques documentés, non corrigés ici (hors N123/N124) : `JoinRequest` hors IntentValidator ; Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N123/N124.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N123–N124 du rapport #144. Commits séparés (N123 puis N124).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Minimap.setFocus Vector3 60 Hz (N123) | `Minimap.luau` (`setFocus`), `init.client.luau` (RenderStepped), `tests/client.luau` (check minimap) | Leftover N122. `(x,y,z)` nombres, y ignoré. Origine monde → u=0.5, v=0.5. Recette visual V69 leftover minimap déjà sur `c5c9`, **pas** merger. Cosmétique. Camera `focusX/Y/Z` **inchangés**. |
| BuildingModels Radar/Flag/Boom `CFrame.Angles` 60 Hz (N124) | `BuildingModels.luau` (`animate` trois branches), `tests/client.luau` (check modeles procéduraux) | Leftover N109. `CFrame.new(rest.X,Y,Z) * fromEulerAnglesYXZ`. Amplitude/fréquences inchangées. Recette visual V70 déjà sur `06ee`, **pas** merger. Cosmétique. Câble N109 **conservé**. Overlay **non**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), Overlay navire roulis (**N125**), Overlay camion roues (**N126**), tribus `humanTargetProtected`. Overlay / WorldRenderer / WorldCamera / HUD / UnitModels / serveur **non édités**.

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
- Overlay interpolation X/Z + yaw euler (**N117**) **et** camion `segRot` (**N115**). Camera : lerp nombres (**N121**) + champ `focusX/Y/Z` (**N122**) + shake (**N119**) + offset (**N120**) + pose (**N118**). Minimap `setFocus(x,y,z)` (**N123**). Radar/Flag/Boom euler (**N124**). Overlay navire `CFrame.Angles` roulis encore 60 Hz (**N125**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N125–N126)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N124 = faits. N22 = **N67 fait**. N27 = doc only. **V69 leftover minimap / N123** fermés ici (portés, pas mergés ; V69 déjà livré visuel `c5c9` y compris minimap). **V70 / N124** fermés ici (portés, pas mergés ; V70 déjà livré visuel `06ee`). Leftover feel Overlay roulis = **N125** (recette visual V71 **déjà fermée** sur `9ab9` / passe 54 visual — porter, ne pas merger). Leftover feel camion roues = **N126** (leftover visual V72 déjà sur `9ab9`, ne pas merger).

---

### ISSUE-N125 — Overlay navire `CFrame.Angles` roulis 60 Hz (feel)

**Priorité :** P3 alloc client Overlay. Leftover explicite de N124 (Radar/Flag/Boom déjà). Distinct de N124 (BuildingModels, rest identité), de N117 (yaw pose), de N126 (roues camion). Recette visual V71 **déjà fermée** sur `9ab9` (passe 54 visual) — **porter euler nombres, ne pas merger** `9ab9`. `Overlay.stepInterpolation` seulement. Ne pas toucher BuildingModels ni WorldCamera.

**Problème :** N124 ferme Radar / Flag / Boom. Reste, **une fois par frame par navire en mouvement** dans `Overlay.stepInterpolation` :

```
frame *= CFrame.Angles(math.sin(now * 1.7 + unit.phase) * 0.018, 0, math.sin(now * 2.1 + unit.phase) * 0.035)
```

Branche `mag > 0.01 and not unit.isMissile` seulement. `frame` a **déjà** translation × yaw (N117) : ce n’est **pas** un `RestCFrame` identité. Donc on ne peut **pas** réduire à `CFrame.new(x,y,z) * euler` (recette N124). `fromEulerAnglesYXZ(rx, 0, rz)` ≡ `Angles(rx, 0, rz)` ici (`ry=0` → X puis Z). Distinct de N124 (BuildingModels, rest identité). Distinct de N117 (yaw `atan2`, immobile). Distinct des roues camion `CFrame.Angles` (spin `progress * π * 20`, leftover N126). Distinct de `UnitModels.place` radar/flag (offset pièce, leftover séparé). Wake / splash / pulse `CFrame.Angles` = événement, pas 60 Hz interpolation.

**Pourquoi 20K CCU :** leftover N117. 8 clients × 60 Hz × N navires en mer × `CFrame.Angles` + compose. Pas d’autorité (silhouette cosmétique). Un euler faux casserait le clapotis des transports / porte-avions en route. Missiles (`isMissile`) n’ont pas ce roulis — ne pas l’ajouter.

**Worker :**

1. Dans `Overlay.stepInterpolation` seulement, branche navire en mouvement : lire les deux `sin` dans des locaux `rx` / `rz`, poser `frame = frame * CFrame.fromEulerAnglesYXZ(rx, 0, rz)`. Plus de `CFrame.Angles` 60 Hz sur le hot path unités. Amplitude 0.018 / 0.035 et fréquences 1.7 / 2.1 **inchangées**. Garde `mag > 0.01 and not unit.isMissile` **inchangée**.

2. **Garder la rotation.** Ne **pas** convertir en translation (N108 feuillage). Ne **pas** cuire un `segRot` d’unité (le look change chaque frame — N117). Ne pas « fermer » le yaw `fromEulerAnglesYXZ(0, atan2, 0)` (N117 déjà). Ne pas « fermer » roues camion (leftover N126). Ne pas « fermer » `UnitModels.place` radar/flag/flamme. Ne pas porter BuildingModels. Après N124. Recette visual V71 déjà sur `9ab9` — porter euler nombres, pas merger visual.

3. Ne pas changer MIN/MAX_DISTANCE. Tests « navires, missiles et interpolation » **et** leftover N124 modeles radar/flag/boom **et** leftover N123 minimap **et** leftover N122 camera `focusX` **doivent rester verts**. Après N124. Recette visual V71 déjà sur `9ab9` — porter, pas merger visual `9ab9` / `06ee` / `c5c9`.

4. Test : banc client « navires, missiles et interpolation » **doit rester vert** : second `applyUnits` extra mute N98 ; `targetX` N101 ; `stepInterpolation` après cible déplacée avance `currentX` **et** `currentY` ; premier `stepInterpolation` unités immobiles ne casse pas (`currentX == targetX`, leftover N116). Leftover N124 modeles procéduraux (radar/flag/boom + câble N109) **doit rester vert**. Leftover N115 `segRot` pose/capture **doit rester vert**. Leftover N123 minimap **doit rester vert**. Leftover N122 camera `focusX` **doit rester vert**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `Overlay.luau` (`stepInterpolation` branche `mag > 0.01 and not unit.isMissile` **seulement**). `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N125 (commentaire leftover, **garder** N117/N116/N101/N98). `BuildingModels.luau` **non**. `UnitModels.luau` **non**. `WorldCamera.luau` **non**. `Minimap.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. **N125 feel ≠ N124 (Radar/Flag/Boom rest identité) ≠ N117 (yaw pose) ≠ N126 (roues camion) ≠ visual V71 (déjà livré visuel `9ab9`, ne pas merger).** Non réentrant. Ne pas fusionner avec N126 dans le même worker. Immobile (`mag <= 0.01`) : **zéro** compose roulis — leftover N116 **doit rester vert**. Missile : pas de roulis.

---

### ISSUE-N126 — Overlay camion `CFrame.Angles` roues 60 Hz (feel)

**Priorité :** P3 alloc client Overlay. Leftover explicite après N125 (roulis navire). Distinct de N125 (navire), de N115 (`segRot` déjà), de N124 (bâtiments). Recette visual V72 leftover **déjà documentée** sur `9ab9` (passe 54 visual) — **porter euler nombres, ne pas merger** `9ab9`. `Overlay.stepInterpolation` boucle camion **seulement**. Ne pas toucher BuildingModels ni UnitModels.

**Problème :** N125 ferme le roulis navire. Reste, **une fois par frame par roue de camion** dans `Overlay.stepInterpolation` :

```
piece.part.CFrame = frame * piece.offset * CFrame.Angles(delivery.progress * math.pi * 20, 0, 0)
```

Branche `piece.part.Name == "Wheel"` seulement. `frame` a **déjà** translation × `segRot` (N115) : ce n’est **pas** un `RestCFrame` identité. Donc on ne peut **pas** réduire à `CFrame.new(x,y,z) * euler` (recette N124). `fromEulerAnglesYXZ(rx, 0, 0)` ≡ `Angles(rx, 0, 0)` ici (seulement X). Distinct de N125 (navire `ry=0` X+Z). Distinct de N115 (`segRot` cuit à la pose). Distinct de `UnitModels.place` radar/flag (offset pièce, leftover séparé). Spin **réel** : `progress * π * 20` — ne **pas** convertir en translation.

**Pourquoi 20K CCU :** leftover N115. 8 clients × 60 Hz × N camions × 4 roues × `CFrame.Angles` + compose. Pas d’autorité (silhouette cosmétique). Un euler faux casserait le roulement des camions usine→gare. Pièces non-roue (`frame * offset` sans Angles) **inchangées**.

**Worker :**

1. Dans `Overlay.stepInterpolation` seulement, branche camion `Wheel` : lire `delivery.progress * math.pi * 20` dans un local `spin`, poser `piece.part.CFrame = frame * piece.offset * CFrame.fromEulerAnglesYXZ(spin, 0, 0)`. Plus de `CFrame.Angles` 60 Hz sur le hot path camion. Facteur `π * 20` **inchangé**. Garde `Name == "Wheel"` **inchangée**. Pièces non-Wheel : `frame * offset` **inchangé**. `segRot` / interpolation nombres / lift **inchangés** (N115/N111/N110).

2. **Garder la rotation.** Ne **pas** convertir en translation (N108 feuillage). Ne **pas** cuire le spin dans `piece.offset` (le progress change chaque frame — N115 a cuit le **look**, pas le spin). Ne pas « fermer » `segRot` (N115 déjà). Ne pas « fermer » N125 dans le même commit. Ne pas « fermer » `UnitModels.place` radar/flag/flamme. Ne pas porter BuildingModels. Après N125. Recette visual V72 leftover déjà sur `9ab9` — porter, pas merger visual.

3. Tests « pose et capture de chaque type de batiment » leftover N115 `segRot` **et** leftover N125 navires **et** leftover N124 modeles **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client pose/capture **doit rester vert** : `segRot` taille, origine, `rawequal`. Check navires leftover N125/N117. Check modeles leftover N124. Check camera leftover N122. Check minimap leftover N123. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `Overlay.luau` (`stepInterpolation` branche `Wheel` **seulement**). `tests/client.luau` **seulement si** le check pose/capture ne mentionne pas encore N126 (commentaire leftover, **garder** N115 `segRot`). `BuildingModels.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. **N126 feel ≠ N125 (roulis navire) ≠ N115 (segRot déjà) ≠ N124 (Radar rest identité) ≠ visual V72 (leftover `9ab9`, ne pas merger).** Non réentrant. Ne pas fusionner avec N125 dans le même worker. Pièces non-roue : zéro compose Angles. Sans `delivery` : la branche camion n’est pas atteinte.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; Minimap nombres → **N123 fait** ; Radar euler → **N124 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; Radar euler → **N124 fait**) |
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
| N34–N122 | (voir rapport #144) | — | **faits** |
| N123 | Minimap.setFocus nombres 60 Hz | P3 | **fait** cette passe (recette visual V69 leftover minimap) |
| N124 | BuildingModels Radar/Flag/Boom `CFrame.Angles` 60 Hz | P3 | **fait** cette passe (recette visual V70) |
| N125 | Overlay navire `CFrame.Angles` roulis 60 Hz | P3 | **nouveau** (recette visual V71 déjà sur `9ab9`, ne pas merger) |
| N126 | Overlay camion roues `CFrame.Angles` 60 Hz | P3 | **nouveau** (leftover visual V72 déjà sur `9ab9`, ne pas merger) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 `NIGHTLY_REPORT.md` historique.

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

Client : **35/35 OK** — dont `construction du monde 3D` (N114 compact leftover, N112 `dirtyHead`, N106/N107/N108) ; `pose et capture de chaque type de batiment` (N115 `segRot` leftover, N113 `rot` chantier) ; `modeles procéduraux` (N124 radar/flag/boom `fromEulerAnglesYXZ`, leftover N109 câble Y, Parts stables, rotation visible CFrame ≠ RestCFrame, Y inchangé = pas une translation) ; `navires, missiles et interpolation` (N117 second frame lerp sous yaw euler ; leftover N116 navire immobile `currentX == targetX` ; leftover N103 lerp missile, N98 extra `rawequal`, N101 `targetX`, navire `extra == nil`, `retreatTinted` conservé) ; `camera strategique` (N122 `focusX` lerp avance sans sauter ; N121 œil `fx + ox` ; N120 formule `ox/oy/oz` à pitch défaut 58° ; N119 punch + décroissance ; leftover N118 `CFrame.X` nombre, leftover tactile pincement/torsion) ; `minimap` (N123 `setFocus(0,0,0)` → u=0.5, v=0.5 ; marqueur suit `focusX`/`focusZ`). `livraison : le gain s'affiche sur la gare` inchangé. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `WorldCamera.luau` **non** touché. `PlacementPreview.luau` **non** touché. `UnitModels.luau` **non** touché. `WorldRenderer.luau` **non** touché. `Overlay.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass47.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N123/N124 sont un hoist signature minimap / euler bâtiments vérifiés par le banc headless.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N123 n’ajoute **pas** de require (signature Minimap). N124 n’ajoute **pas** de require (nombres locaux BuildingModels). N125 restera dans `Overlay.stepInterpolation`. N126 restera dans la boucle camion Overlay.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N123 : X→u, Z→v (pas Y). Le check minimap `setFocus(Vector3.new(0,0,0))` est passé en nombres. Recette visual V69 leftover minimap déjà sur `c5c9` — porter, ne pas merger.

Piège N124 : **garder la rotation** (pas une translation façon N109 câble). `fromEulerAnglesYXZ` ≡ `Angles` si ry=0 (Flag) ou seulement Y (Radar/Boom). Recette visual V70 déjà sur `06ee` — porter, ne pas merger. `RestCFrame` identité rotation **doit rester vrai** pour ces trois pièces.

Piège N125 (à venir) : `frame` a déjà translation × yaw — **ne pas** réduire à `CFrame.new * euler`. Immobile = zéro compose. Missile = pas de roulis. Recette visual V71 déjà sur `9ab9` — porter, ne pas merger.

Piège N126 (à venir) : spin réel `progress * π * 20` dans un local `spin`. `frame` a déjà `segRot`. Ne pas cuire le spin dans `piece.offset`. Recette visual V72 leftover déjà sur `9ab9` — porter, ne pas merger.
