# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 46)

Déclencheur : ouverture de la **PR #140** (`cursor/analyse-nocturne-du-codebase-b19e`) — WorldCamera shake/offset nombres, specs N121–N122.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-4d8e`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#142.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. Camera overview : lerp mire `fx/fy/fz` (N121) ; champs `focusX/Y/Z` (N122) ; shake `sx/sy/sz` (N119) ; offset YXZ `ox/oy/oz` (N120) ; pose `CFrame.new * rotation` (N118). `init.client` reconstruit encore un Vector3 pour `Minimap.setFocus` (leftover N123).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #140 (passe 45) : claims vérifiés.** Shake `sx/sy/sz` (N119) ; offset trig `ox/oy/oz` (N120). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #140 a documenté (N121, N122)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #140

| Claim #140 | Réalité à l’ouverture |
|---|---|
| WorldCamera shake nombres (N119) | Oui. `sx/sy/sz`, coeffs 0.65 / 0.42 / 0.5, fréq. 31 / 37 / 23. Recette visual V66 leftover shake, pas merger `926d`. |
| WorldCamera offset trig (N120) | Oui. `ox/oy/oz` YXZ. Plus de `VectorToWorldSpace`. Recette visual V67, pas merger `b2f1`. Lerp `focus` Vector3 leftover N121. |
| Specs N121–N122 | **Corrigés ici.** N121 = lerp `fx/fy/fz` (recette visual V68 déjà fermée sur `0231` / PR #139 — **porté, pas mergé**). N122 = champ `focusX/Y/Z` (recette visual V69 champs déjà fermée sur `c5c9` / PR #142 — **porté, pas mergé** ; `Minimap.setFocus(x,y,z)` **non** porté — leftover N123). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #141 (`4c70` N97–N98), feel jusqu’à #140, visuelles #39/…/`c5c9` V69 **fermé** ; `06ee` V70 Radar **fermé** + leftover V71 roulis navire. **#140 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#141) reste distincte. Ne pas merger visual `c5c9` / `0231` ni hardening `4c70` / `2c0f` sans rebase.

**Revue autorité (sous-agent isolé) :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. Risques documentés, non corrigés ici (hors N121/N122) : `JoinRequest` hors IntentValidator ; Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco (sous-agent isolé) :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N121/N122.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N121–N122 du rapport #140. Commits séparés (N121 puis N122).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| WorldCamera.step lerp `focus` Vector3 60 Hz (N121) | `WorldCamera.luau` (`step` overview, bloc lerp), `tests/client.luau` (asserts dans le check camera existant) | Leftover N120. `fx/fy/fz` nombres + un `Vector3.new` d’écriture. Œil `ex = fx + ox + sx`. Recette visual V68 déjà sur `0231`, **pas** merger. Cosmétique. Offset / shake / pose **inchangés**. |
| WorldCamera.step `self.focus = Vector3.new` idle (N122) | `WorldCamera.luau` (`new` + `focusTile` instant + `step`), `init.client.luau` (`setFocus` RenderStepped), `tests/client.luau` (asserts `focusX`) | Leftover N121. Champs `focusX/Y/Z`. Plus de Vector3 idle dans `step`. `focusTile(instant)` synchronise nombres **et** `self.focus` (geste). Recette visual V69 champs déjà sur `c5c9`, **pas** merger. `Minimap.setFocus` reste Vector3 (reconstruction au lecteur — leftover N123). Cosmétique. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), `Minimap.setFocus` nombres (**N123**), Radar/Flag/Boom `CFrame.Angles` (**N124**), tribus `humanTargetProtected`. Overlay / WorldRenderer / BuildingModels / HUD / UnitModels / serveur **non édités** (hors `init.client` lecteur minimap N122).

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
- Overlay interpolation X/Z + yaw euler (**N117**) **et** camion `segRot` (**N115**). Camera : lerp nombres (**N121**) + champ `focusX/Y/Z` (**N122**) + shake (**N119**) + offset (**N120**) + pose (**N118**). `Minimap.setFocus` Vector3 encore 60 Hz (**N123**). Radar/Flag/Boom `CFrame.Angles` encore 60 Hz (**N124**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N123–N124)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N122 = faits. N22 = **N67 fait**. N27 = doc only. **V68 / N121** fermés ici (portés, pas mergés ; V68 déjà livré visuel `0231`). **V69 champs / N122** fermés ici (portés, pas mergés ; V69 déjà livré visuel `c5c9` **y compris** `Minimap.setFocus(x,y,z)` — feel a porté les champs seulement). **V70** déjà fermé visuel `06ee` — leftover feel = **N124** (porter, ne pas merger). Leftover feel Minimap = **N123** (leftover visual V69 minimap déjà sur `c5c9`).

---

### ISSUE-N123 — Minimap.setFocus nombres 60 Hz (feel)

**Priorité :** P3 alloc client camera. Leftover explicite de N122 (champs `focusX/Y/Z` déjà). Distinct de N122 (stockage camera), de N121 (lerp). Recette visual V69 leftover minimap **déjà fermée** sur `c5c9` (passe 52 visual) — **porter `setFocus(x,y,z)`, ne pas merger** `c5c9`. Ne pas toucher Overlay ni WorldRenderer.

**Problème :** N122 ferme le Vector3 idle dans `WorldCamera.step`. Reste, **chaque RenderStepped** : `init.client` fait `m:setFocus(Vector3.new(camera.focusX, camera.focusY, camera.focusZ))`. `Minimap.setFocus` lit encore `worldPosition.X/.Z`. Un Vector3 par frame idle au lecteur. Distinct de N122 (camera step déjà sans Vector3). Distinct de N124 (Radar/Flag/Boom).

**Pourquoi 20K CCU :** leftover N122. 8 clients × 60 Hz × 1 Vector3. Pas d’autorité (marqueur minimap cosmétique). Un `setFocus` nombres faux casserait le point de mire (u/v hors [0,1] ou axes X/Z inversés).

**Worker :**

1. Dans `Minimap.setFocus` seulement : signature `(x: number, y: number, z: number)` (y ignoré pour u/v, comme `.Y` aujourd’hui). `u = clamp((x + WORLD_WIDTH/2) / WORLD_WIDTH, 0, 1)`, `v = clamp((z + WORLD_DEPTH/2) / WORLD_DEPTH, 0, 1)`. Plus de `worldPosition.X/.Z`. Dans `init.client` RenderStepped : `m:setFocus(camera.focusX, camera.focusY, camera.focusZ)` — **plus de** `Vector3.new`. `WorldCamera.step` / `focusX/Y/Z` **inchangés** (N122). Lerp / offset / shake / pose **inchangés**. Overlay unités / camion **inchangés**.

2. Ne **pas** éditer `Overlay.luau` / `WorldRenderer.luau` / `UnitModels.luau` / `HUD.luau` / `BuildingModels.luau` / `WorldCamera.luau`. Ne pas « fermer » Radar/Flag/Boom (leftover N124). Ne pas splitter `targetFocus`. Après N122. Recette visual V69 minimap déjà sur `c5c9` — porter `setFocus(x,y,z)`, pas merger visual `c5c9` / `0231`.

3. Le check « minimap » appelle aujourd’hui `setFocus(Vector3.new(0, 0, 0))` : le passer en `setFocus(0, 0, 0)`. Marqueur à `(0,0,0)` monde → u=0.5, v=0.5. Tests « camera strategique » leftover N122 (`focusX` avance, `rawequal` pas requis — feel n’assert **pas** `rawequal(camera.focus)` après `step`, c’est un assert visual) **et** « camera tactile » **doivent rester verts**.

4. Test : banc client « minimap » **et** « camera strategique » **et** « camera tactile » **doivent rester verts**. Leftover N122 / N121 / N120 / N119 / N117 **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `Minimap.luau` (`setFocus`). `init.client.luau` (RenderStepped). `tests/client.luau` **seulement si** le check minimap / camera (ne **pas** ajouter un 36e). `WorldCamera.luau` **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. **N123 feel ≠ N122 (champs déjà) ≠ N124 (Radar Angles) ≠ visual V69 (déjà livré visuel `c5c9` y compris minimap, ne pas merger).** Non réentrant. Ne pas fusionner avec N124 dans le même worker. Axes : X→u, Z→v (pas Y).

---

### ISSUE-N124 — BuildingModels Radar / Flag / Boom `CFrame.Angles` 60 Hz (feel)

**Priorité :** P3 alloc client bâtiments. Leftover explicite après N122 (camera chain). Distinct de N123 (Minimap). Recette visual V70 **fermée** sur `06ee` (passe 53 visual) — **porter euler nombres, ne pas merger** `06ee`. `BuildingModels.animate` seulement. Ne pas toucher Overlay ni WorldCamera.

**Problème :** N122/N123 ferment la caméra Vector3 idle. Reste, **une fois par frame par pièce animée** dans `BuildingModels.animate` : `rest * CFrame.Angles(...)`. Trois branches :

- `Radar` : `rest * CFrame.Angles(0, time * 1.45, 0)`
- `CapitalFlag` : `rest * CFrame.Angles(sin(time*2.4)*0.045, 0, sin(time*1.7)*0.035)`
- `PortCraneBoom` : `rest * CFrame.Angles(0, sin(time*0.35)*0.12, 0)`

`RestCFrame` de ces trois pièces est une **translation pure** (`block()` pose `CFrame.new(offset)`). Donc `rest * Angles(rx,ry,rz)` ≡ `CFrame.new(rest.X, rest.Y, rest.Z) * Angles(rx,ry,rz)`. Distinct de N109 (câble = translation Y, **pas** une rotation). Distinct des roues camion `CFrame.Angles` (spin réel, leftover séparé).

**Pourquoi 20K CCU :** leftover N109. 8 clients × 60 Hz × (1 radar SAM + 1 drapeau capitale + 1 grue PORT) × `CFrame.Angles` + compose. Pas d’autorité (silhouette cosmétique). Un euler faux casserait la rotation du radar / le clapotis du drapeau / le lacet de la grue.

**Worker :**

1. Dans `BuildingModels.animate` seulement : Radar / CapitalFlag / PortCraneBoom lisent `rest.X/.Y/.Z` en nombres, posent `CFrame.new(rx, ry, rz) * CFrame.fromEulerAnglesYXZ(ax, ay, az)` avec **les mêmes trois nombres** actuellement passés à `CFrame.Angles` (Radar : `(0, time*1.45, 0)` ; Flag : `(sin*0.045, 0, sin*0.035)` ; Boom : `(0, sin*0.12, 0)`). `fromEulerAnglesYXZ` ≡ `Angles` ici : Radar/Boom n’ont que Y ; Flag a `ry=0` donc X puis Z. Plus de `CFrame.Angles` 60 Hz sur ces trois noms.

2. **Garder la rotation.** Ne **pas** convertir en translation (N108 feuillage / N109 câble). Amplitude et fréquences **inchangées**. Ne **pas** splitter `RestCFrame`. Ne pas « fermer » Transparency CityWindows / beacons / FactoryOutput / SiloWarning. Ne pas « fermer » `PortCraneCable` (N109 déjà). Ne pas porter Overlay. Ne pas « fermer » `Size` chantier (API). Ne pas « fermer » `CFrame.Angles` roues camion (spin réel). Après N123. Recette visual V70 déjà sur `06ee` — porter euler nombres, pas merger visual.

3. Ne pas changer MIN/MAX_DISTANCE. Tests « modeles procéduraux » **et** leftover N109 câble Y **doivent rester verts**. Leftover N122 camera `focusX` **doit rester vert**. Après N123. Recette visual V70 déjà sur `06ee` — porter euler nombres, pas merger visual `06ee` / `c5c9`.

4. Test : banc client « modeles procéduraux : le palier change la silhouette » **doit rester vert** : deux `animate` successifs, Parts stables, rotation visible (CFrame ≠ RestCFrame pour Radar/Flag/Boom). Check câble leftover N109. Check camera leftover N122 / N121. Check navires leftover N117. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `BuildingModels.luau` (`animate` branches Radar / CapitalFlag / PortCraneBoom **seulement**). `tests/client.luau` **seulement si** le check « modeles procéduraux » ne distingue pas encore boom/radar/drapeau (ajouter des asserts rotation, **garder** le câble N109, ne **pas** ajouter un 36e). `WorldCamera.luau` **non**. `Minimap.luau` **non**. `init.client.luau` **non**. Overlay **non**. **Ne pas** éditer le serveur.

**Contraintes :** pas de RemoteFunction. **N124 feel ≠ N123 (Minimap) ≠ N122 (focusX) ≠ visual V70 (déjà livré visuel `06ee`, ne pas merger).** Non réentrant. Ne pas fusionner avec N123 dans le même worker. `RestCFrame` identité rotation **doit rester vrai** pour ces trois pièces — si un futur `block()` pose une rotation, cuire `RestRot` à `create` **dans le même commit**.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; lerp camera → **N121 fait** ; champ focus → **N122 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; champ focus → **N122 fait**) |
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
| N34–N120 | (voir rapport #140) | — | **faits** |
| N121 | WorldCamera.step lerp `focus` Vector3 60 Hz | P3 | **fait** cette passe (`fx/fy/fz`, recette visual V68) |
| N122 | WorldCamera.step champ `focusX/Y/Z` | P3 | **fait** cette passe (champs, recette visual V69 ; Minimap nombres **non**) |
| N123 | Minimap.setFocus nombres 60 Hz | P3 | **nouveau** (recette visual V69 leftover minimap déjà sur `c5c9`, ne pas merger) |
| N124 | BuildingModels Radar/Flag/Boom `CFrame.Angles` 60 Hz | P3 | **nouveau** (recette visual V70 déjà sur `06ee`, ne pas merger) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 `NIGHTLY_REPORT.md` historique.

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

Client : **35/35 OK** — dont `construction du monde 3D` (N114 compact leftover, N112 `dirtyHead`, N106/N107/N108) ; `pose et capture de chaque type de batiment` (N115 `segRot` leftover, N113 `rot` chantier) ; `navires, missiles et interpolation` (N117 second frame lerp sous yaw euler ; leftover N116 navire immobile `currentX == targetX` ; leftover N103 lerp missile, N98 extra `rawequal`, N101 `targetX`, navire `extra == nil`, `retreatTinted` conservé) ; `camera strategique` (N122 `focusX` lerp avance sans sauter ; N121 œil `fx + ox` ; N120 formule `ox/oy/oz` à pitch défaut 58° ; N119 punch + décroissance ; leftover N118 `CFrame.X` nombre, leftover tactile pincement/torsion) ; `minimap` (`setFocus` Vector3 encore — leftover N123). `livraison : le gain s'affiche sur la gare` inchangé. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `BuildingModels.luau` **non** touché. `PlacementPreview.luau` **non** touché. `UnitModels.luau` **non** touché. `WorldRenderer.luau` **non** touché. `Overlay.luau` **non** touché. `Minimap.luau` **non** touché (API Vector3 conservée). `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass46.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N121/N122 sont un hoist lerp / champ camera vérifiés par le banc headless.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N121 n’ajoute **pas** de require (nombres locaux WorldCamera). N122 n’ajoute **pas** de require (champs `focusX/Y/Z`). N123 restera dans `Minimap.setFocus`. N124 restera dans `BuildingModels.animate`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N121 : un seul `Vector3.new` d’écriture pour `self.focus` (API pan/minimap) — **fermé ensuite** en N122. Utiliser `fx/fy/fz` pour l’œil (`ex = fx + ox + sx`), pas `self.focus.X` après le write. Recette visual V68 déjà sur `0231` — porter, ne pas merger.

Piège N122 : splitter `focusX/Y/Z` sans casser `camera.focus` Vector3 au geste `focusTile(instant)`. Ne pas splitter `targetFocus`. Ne pas réécrire `self.focus` 60 Hz (stale après lerp — les asserts live lisent `focusX`). Recette visual V69 champs déjà sur `c5c9` — porter les champs, **pas** `Minimap.setFocus(x,y,z)` (leftover N123). Ne pas merger visual.

Piège N123 (à venir) : X→u, Z→v. Le check minimap `setFocus(Vector3.new(0,0,0))` doit passer en nombres. Recette visual V69 leftover minimap déjà sur `c5c9` — porter, ne pas merger.

Piège N124 (à venir) : **garder la rotation** (pas une translation façon N109 câble). `fromEulerAnglesYXZ` ≡ `Angles` si ry=0 (Flag) ou seulement Y (Radar/Boom). Recette visual V70 déjà sur `06ee` — porter, ne pas merger.
