# Nightly report — passe 56 (revue PR #148)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-9793` (PR #148, `72a1d65`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-1b5c`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #148 (`Overlay.stepInterpolation` roues camion — HEAD visuel, V72). Correctifs sûrs, sans merger feel `4d8e`/`b19e`/`bec6`/`71f0` ni hardening `4c70`/`24a7`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `UnitModels.place` radar / flag : `localFrame * fromEulerAnglesYXZ(...)`, plus de `CFrame.Angles` 60 Hz | `UnitModels.luau`, `tests/client.luau` | V73 |

`rankByTiles` / hover closures / `trackUnit` extra / `targetX`/`currentX` / unités monde nombres (V56) / camion lerp (V57) / houle (V58) / feuillage (V59) / câble PORT (V60) / lift cuit (V61) / interpolation nombres (V62) / `segment.rot` chantier (V63) / camion `segRot` (V64) / unités yaw (V65) / pose caméra translation (V66) / offset `ox/oy/oz` (V67) / lerp `focus` nombres (V68) / champ `focusX/Y/Z` (V69) / Radar / Flag / Boom (V70) / roulis navire (V71) / roues camion (V72) / `previewCtxBuf` / `self.ranked` / `gainBuf` / `countBuf` / `destroyBuf` / `validTiles` pools / `parkedBuf` / `collapseRemainBuf` / `allyBuf` / `stripBuf` / `ctxBuf` / `doomedBuf` / `collapsingBuf` **conservés**. `seedBeachhead` / inbound recycle / `settledHumans` / `awaitingSpawn` **non touchés**. `CAPTURE_GUARD=80` visuel **inchangé**. Schéma filaire client **inchangé** (V14b reste ouvert). `HUD.luau` / `PlacementPreview.luau` / `FactionLabels.luau` / `Overlay.luau` / `WorldSpace.luau` / `WorldRenderer.luau` / `WorldCamera.luau` / `Minimap.luau` / `BuildingModels.luau` / `init.client.luau` **non édités**. Serveur **inchangé**. GameState ne require toujours pas Buildings / Research. Extra missile **inchangé** (V52). `targetX`/`currentX` **inchangés** (V55). Conversion monde unités **inchangée** (V56). Camion lerp **inchangé** (V57). Houle `oceanRipples` **inchangée** (V58). Feuillage `animatedFoliage` **inchangé** (V59). Câble `PortCraneCable` **inchangé** (V60). Lift `layer.origin` **inchangé** (V61). Lerp `ox/dx` **inchangé** (V62). `segment.rot` chantier **inchangé** (V63). Camion `segRot` **inchangé** (V64) — leftover pose/capture **vert**. Unités yaw **inchangées** (V65). Pose caméra `CFrame.new * rotation` **inchangée** (V66). Offset `ox/oy/oz` **inchangé** (V67). Lerp nombres **inchangé** (V68). Champ `focusX/Y/Z` **inchangé** (V69) — leftover camera **vert**. Radar / Flag / Boom **inchangés** (V70) — leftover modeles **vert**. Roulis navire **inchangé** (V71) — leftover navires **vert**. Roues camion **inchangées** (V72) — leftover pose/capture **vert**. Transparency CityWindows / beacons / FactoryOutput / SiloWarning **inchangées**. `RestCFrame` posé à la construction **inchangé**. Explosion / wake / splash **inchangés** (événement). `part.Size = Vector3.new` chantier **inchangé** (API). `targetFocus` Vector3 et pan/clamp **inchangés** (gestes). `self.focus` Vector3 **conservé** pour `focusTile(instant)` seulement. Flame `Size = Vector3.new` **inchangé** (leftover V74). Pulse livraison `CFrame.Angles` **inchangé** (événement, pas 60 Hz interpolation).

---

## Constatations PR #148 (à ne pas casser)

- **Autorité :** le client n’évalue aucune règle de combat/économie. Ordres = remotes + sequence. `Placement` est partagé : Preview et serveur exécutent le même `resolve` ; la vérité reste `Buildings.build` côté serveur.
- **Vérité runtime :** `SystemsBootstrap.install()` → `ChantierB.apply(Config)`. Ne pas tuner `Config.luau` seul.
- **Combat vivant :** `ChantierB.stepAttacks`. Guard = `ChantierB.CAPTURE_GUARD` (80), **pas** `Config.MAX_TILES_PER_TICK` (56 après apply, 400 brut).
- **Posted DEFENSE :** `bunkersBySlot` + `attackLogic`. Buffer `defense` mort. Plus d’écritures `applyDefenseAura`.
- **Posted SAM :** `samsBySlot` + `tryIntercept` / `samsOf`. Slot sans SAM ne rescane plus le hash. `samsOf` recycle un buffer — **pas réentrant**.
- **Posted SILO :** `silosBySlot` + `Nukes.launch`. Fantôme hors index ignoré.
- **Cooldown 10 Hz :** `coolingBuildings` + `armCooldown` (SAM **et** silos). SAM-only gèlerait `SILO_COOLDOWN`.
- **Posted tous kinds :** `buildingsBySlot`. Bots upgrade / score nuke / rail collect via l’index.
- **Posted FACTORY :** `factoriesBySlot` (sous-ensemble, 10 Hz Trade). Ne pas itérer `buildingsBySlot` pour les colis.
- **Posted PORT :** `portsByTile` `{slot, level}`. Distinct de `_carriersDirty` (NAVAL_BASE). Vague = `TRADE_SHIP_INTERVAL` 45, pas 10 Hz. **Loi manhattan visuelle inchangée.**
- **Posted NAVAL_BASE :** `navalBasesBySlot`. Spawn seulement si `_carriersDirty`. Un PORT n’est jamais un carrier.
- **Têtes de pont :** `launchAttack` recycle `parkedBuf` (V44). Truncate leftover **avant** `origLaunch`. Réinsert `1..n`. 0 pont → 1 front terre ; 2 `seedBeachhead` + terre → 3 Attack, mêmes objets. **Pas réentrant.** `seedBeachhead` visuel inchangé.
- **Effondrement :** `collapseFaction` recycle `collapseRemainBuf` / `collapseLeftBuf` / `collapseScratch` (V45). Truncate **avant** plunder et **avant** swap. Slot 99 / victime à 0 inerte. **Pas réentrant.**
- **Élimination bâtiments :** `removePlayer` recycle `destroyBuf` (V46). Snapshot **avant** `destroyBuilding`. Fallback hash si `buildingsBySlot` nil. Truncate leftover **avant** la boucle destroy. Distinct de V37 / V41 / V45. `GameState.destroyBuf` exposé banc.
- **Placement partagé :** `validTiles` recycle `blockBuf` / `candBuf` / `queueBuf` / `visitBuf` / `emptyTileBuf` (V47). Early-out kind/index/owner → `emptyTileBuf`. Retourne `candBuf`. Preview n’appelle pas `validTiles`.
- **Deltas owner client :** `applyDelta` recycle `gainBuf` / `lossBuf` / `otherBuf` (V48). Truncate leftover **avant** return. Early-out `count == 0` → pools à `# == 0`.
- **Étiquettes :** `surveyTerritories` recycle `sumXBuf` / `sumYBuf` / `countBuf` (V49). `table.clear` **avant** le scan.
- **Classement HUD :** `HUD.update` recycle `self.ranked` + inner records (V50). Comparateur `rankByTiles` module (V54).
- **Fantôme placement :** `PlacementPreview.resolve` recycle `previewCtxBuf` (V51). Closures `ownerAt` / `buildingAt` stables (V53).
- **Unités Overlay :** `applyUnits` hoist `trackUnit` (V52). Cible `targetX`/`currentX` (V55). Pose 60 Hz : X/Z monde + yaw `fromEulerAnglesYXZ` (V56 + V65). Roulis navire : `frame * fromEulerAnglesYXZ(rx, 0, rz)` (V71). Extra missile **inchangé**.
- **Camion Overlay :** lerp X/Y/Z + `route.segRot` (V57 + V64). Roues : `frame * offset * fromEulerAnglesYXZ(spin, 0, 0)` (V72). `spin = progress * π * 20`. Garde `Name == "Wheel"`. Pièces non-Wheel : `frame * offset` seul.
- **Houle / feuillage :** `WorldRenderer.step` nombres (V58 / V59).
- **Câble PORT :** `BuildingModels.animate` Y nombres (V60). Amplitude 0.35. **Pas** une rotation.
- **Radar / Flag / Boom :** `BuildingModels.animate` (V70). `RestCFrame` translation pure. Hot path : `CFrame.new(rest.X, rest.Y, rest.Z) * CFrame.fromEulerAnglesYXZ(ax, ay, az)` avec les **mêmes trois nombres** qu’avant. Plus de `CFrame.Angles` 60 Hz sur ces trois noms. Amplitude et fréquences **inchangées**. Ne **pas** convertir en translation (distinct de V60). **Pas réentrant**. Transparency **inchangée**. Distinct de V71 (roulis navire Overlay, `frame` a déjà yaw). Distinct de V72 (roues camion Overlay, `frame` a déjà `segRot`). Distinct de V73 (`UnitModels.place` radar/flag unités — **autre module**, `piece.offset` n’est pas un `RestCFrame` identité).
- **Roulis navire Overlay :** `Overlay.stepInterpolation` (V71). Branche `mag > 0.01 and not unit.isMissile` seulement. `frame` a **déjà** translation × yaw (V65) : ce n’est **pas** un `RestCFrame` identité, donc compose `frame * euler` (pas `CFrame.new * euler` recette V70). Locaux `rx` / `rz` = `sin(now*1.7+phase)*0.018` / `sin(now*2.1+phase)*0.035`. `fromEulerAnglesYXZ(rx, 0, rz)` ≡ `Angles(rx, 0, rz)` (`ry=0` → X puis Z). Amplitude et fréquences **inchangées**. Immobile (`mag <= 0.01`) : **zéro** compose roulis — `atan2(0, 1) = 0` reste l’identité (leftover V65 **doit rester vert**). Missile : pas de roulis. **Pas réentrant** (un `stepInterpolation` / Overlay / frame). Distinct de V70 (BuildingModels, rest identité). Distinct de V65 (yaw `atan2`). Distinct de V72 (roues camion, un axe X, `progress`). Distinct de V73 (`UnitModels.place` radar/flag, `place` **tourne même immobile**). Wake / splash / pulse `CFrame.Angles` = événement, pas 60 Hz interpolation.
- **Roues camion Overlay :** `Overlay.stepInterpolation` (V72). Branche `piece.part.Name == "Wheel"` seulement, pendant `route.delivery`. `frame` a **déjà** translation × `route.segRot[segmentIndex]` (V64) : ce n’est **pas** un `RestCFrame` identité, donc compose `frame * offset * euler` (pas `CFrame.new * euler` recette V70). Local `spin` = `delivery.progress * math.pi * 20` (un spin pour toutes les roues du camion). `fromEulerAnglesYXZ(spin, 0, 0)` ≡ `Angles(spin, 0, 0)` (`ry=0`, `rz=0` → X seul). Facteur `π × 20` **inchangé**. Garde `Name == "Wheel"` **inchangée**. Pièces non-Wheel : `frame * offset` **inchangé** — ne pas y ajouter de spin. Sans `delivery` : la branche camion n’est pas atteinte (`continue` après pulse). **Pas réentrant** (un `stepInterpolation` / Overlay / frame). Distinct de V71 (roulis navire, deux `sin`, compose sur le `frame` unité). Distinct de V64 (`segRot` cuit, look de la voie). Distinct de V70 (BuildingModels, rest identité). Distinct de V73 (`UnitModels.place`). Distinct de wake / splash / pulse `CFrame.Angles` (événement).
- **Radar / flag unités :** `UnitModels.place` (V73). Branches `role == "radar"` et `role == "flag"` seulement. `frame` Overlay a **déjà** translation × yaw (V65) ± roulis (V71). `piece.offset` est une pose construction. Donc compose `frame * (offset * euler)` — **pas** un `RestCFrame` identité BuildingModels, **pas** un `frame * euler` Overlay. Radar : `fromEulerAnglesYXZ(0, time * 2.2, 0)` ≡ `Angles(0, yaw, 0)` (`rx=0`, `rz=0` → Y seul). Flag : `fromEulerAnglesYXZ(sin(time*5)*0.06, 0, 0)` ≡ `Angles(pitch, 0, 0)` (`ry=0`, `rz=0` → X seul). Fréquences 2.2 / 5 et amplitude flag 0.06 **inchangées**. Appelé depuis `Overlay.stepInterpolation` pour **chaque** unité interpolée, **y compris immobile** (distinct V71 : zéro compose roulis si `mag <= 0.01`). Autres rôles (wake Transparency, flame Size, trail, light) **inchangés**. **Pas réentrant** (`place` une fois / pièce / frame, un appelant = Overlay). Sans unité interpolée : `place` n’est pas atteint. Distinct de V70 (BuildingModels Radar/Flag/Boom, rest identité, noms `"Radar"` / `"CapitalFlag"` / `"PortCraneBoom"`). Distinct de V71 (roulis navire Overlay, deux `sin`, compose sur le `frame` unité). Distinct de V72 (roues camion Overlay, `Name == "Wheel"`, `progress * π * 20`). Distinct des `CFrame.Angles` de **construction** (`addWake`, `Bow`, ailettes missile) — une fois à `create`, pas 60 Hz. Distinct de `piece.role == "flame"` `Size = Vector3.new` (leftover V74). Distinct de wake Transparency / trail / light (pas CFrame).
- **Chantier de voie :** `applyRouteProgress` lift + nombres + `segment.rot` (V61 + V62 + V63). `part.Size = Vector3.new` **inchangé** (API).
- **Caméra stratégique :** `WorldCamera.step` overview (V66 + V67 + V68 + V69). Champ `focusX/Y/Z`. Plus de `Vector3.new` idle 60 Hz. `self.focus` Vector3 seulement au geste `focusTile(instant)`. Minimap `setFocus(x,y,z)`.
- **Hover 60 Hz :** `previewOwnerAt` / `previewBuildingAt` module (V53).
- **Spawn clic :** terre libre + `isSpawnIsolated`. Snap `r=6` seulement si la tuile cliquée est **occupée**.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `GameState` ne require pas `Buildings` / `Research` / `Types`.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–18) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.
- **PR #148 :** roues camion `fromEulerAnglesYXZ` (V72) intact. Banc pose/capture leftover V64 / V57 + garde Wheel. Roulis navire V71 intact. Radar/Flag/Boom V70 intact. Camera V69 intact. Rien à revert.

---

## Specs worker (reste)

Ne pas merger feel `4d8e`/`b19e`/`bec6`/`ab04`/`71f0` ni hardening `4c70`/`24a7` sur cette branche sans rebase. Porter **une** recette à la fois.

### ISSUE-V1 — Packing spawn 18 factions

**Problème.** `SPAWN_RADIUS=18` + `SPAWN_MIN_PLAYER_DISTANCE=30` : les seeds 7 / 99991 / 1234567 / 424242 placent 11–15 factions sur 18. Les tribus sautent. `spawnCenter` et `isSpawnIsolated` sont vivants mais le disque 21² reste trop large : occupancy ≫ minDist.

**20K CCU.** Un salon Classique sous-peuplé fausse l’éco, les bots et le climax nucléaire.

**Faire.** Recherche spirale / rejet plus souple pour `isTribe` (dist min 20) **ou** `TRIBE_SPAWN_RADIUS` plus petit. Ne pas réduire le disque humain. Ne pas re-poser `isSpawnIsolated` / `spawnCenter`.

**Contraintes.** Server-only. `addPlayer` rollback si `findSpawn` nil. `stripTerritory` doit continuer d’effacer `spawnCenter`.

**Tester.** `EXTRA_SEEDS` + seed 424242 : `spawned == BOT_COUNT + TRIBE_COUNT`. `./tests/run.sh`.

### ISSUE-V7 — `findSpawn` / `claimSpawn` anti-splash

**Problème.** Spawn ignore cratère ogive / fallout chaud. Un humain peut (re)naître dans le splash. Isolation clic (V16b) ne couvre **pas** le fallout.

**Faire.** Recette feel N50/N52 : `isSpawnSafe` partagé `findSpawn` + `claimSpawn` (C1+C2), **en plus** de `isSpawnIsolated`. Contrat B missiles inbound **inchangé**.

**Tester.** MIRV existant + capitale sous fallout → refus / autre tuile. Isolation clic (passe 19) reste verte.

### ISSUE-V9b — Persistence debounce 30 s

**Problème.** `Persistence.record()` marque dirty **puis** appelle `save()` tout de suite (`UpdateAsync` / humain). Le double-write `release`/`BindToClose` est corrigé ; la tempête de fin de match (8 writes synchrones) reste.

**20K CCU.** N salons × 8 humains × `endMatch` = burst DataStore.

**Faire.** `record()` marque dirty **sans** `save`. Flush 30 s + `endMatch` + `release` + `BindToClose`. Une écriture / userId / match.

**Contraintes.** Ne pas perdre l’XP d’un éliminé si le salon crash avant flush : flush immédiat sur `settledHumans` **ou** accepter ≤1 write / éliminé. Hors bundle (`Persistence`).

**Tester.** Studio : 8 humains `endMatch` = ≤8 writes, disconnect après `record` = 0 write supplémentaire.

### ISSUE-V13 — Rot doomsday O(carte)

**Problème.** `ChantierB.stepDoomsday` parcourt `TILE_COUNT` par joueur marqué pour arracher `quota` tuiles. V43 recycle seulement la **liste temporaire** (`stripBuf`) : le scan 40 960 reste.

**20K CCU.** 10 Hz × 40 960 lectures buffer quand le cadran tourne = pic en fin de partie.

**Faire.** Liste incrémentale des tuiles par slot (même structure que `border`) **ou** reservoir sampling sur un index compact. Ne pas changer la formule `Doomsday.rotQuota`. Ne pas retoucher `stripBuf` (V43 déjà).

**Tester.** Cadran existant + 1 humain sous quota. Invariants `tiles` vs buffer. Banc V43 (deux camps, chacun perd le sien) **doit rester vert**.

### ISSUE-V14b — En-tête de compteur pour `flushOwnerDelta`

**Problème.** Passe 17 recycle `deltaIndices` mais `buffer.create(count * 5)` reste obligatoire : un tampon trop grand serait lu comme des tuiles fantômes (slot 0). Feel N72 a `dirtyIndexBuf` (liste d’indices, pas l’en-tête filaire). V48 recycle les **listes d’effets** Overlay, pas le payload.

**20K CCU.** 10 Hz playing × alloc buffer = pression GC sur 8 clients.

**Faire.** Préfixer le payload `[u32 count][u32 index][u8 slot]…` **ou** RemoteEvent séparé pour la longueur. Adapter le client (`WorldRenderer` / init.client). Growth-only ensuite. Ne pas porter feel N72 seul : ça ne ferme pas l’alloc `buffer.create`.

**Contraintes.** Changer client **et** serveur dans le même commit. Ne pas casser `RequestSnapshot` (carte entière, autre remote). Ne pas retoucher `gainBuf` (V48 déjà).

**Tester.** Match 6000 ticks, P0 metrics. Client 34/34.

### ISSUE-V74 — `UnitModels.place` flame `Size = Vector3.new` 60 Hz

**Problème.** V73 ferme le `CFrame.Angles` radar/flag. Reste, **une fois par frame par missile interpolé** dans `UnitModels.place` (appelé depuis `Overlay.stepInterpolation`) :

```
elseif piece.role == "flame" then
    piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

X/Y constants `0.62`. Z pulse `1.8 + sin(time * 18) * 0.45`. Fréquence 18 et amplitude 0.45 **inchangées**. Distinct de V73 (radar/flag, CFrame, pas Size). Distinct de V72 (roues camion Overlay, CFrame). Distinct de `part.Size = Vector3.new` chantier `applyRouteProgress` (API largeur voie, **ne pas y toucher**). Distinct de wake / trail / light (Transparency, pas Size). Distinct des `Vector3.new` de **construction** (`createMissile` EngineFlame / Exhaust) — une fois à `create`, pas 60 Hz. Navires / porte-avions n’ont pas de `role == "flame"` — ne pas l’ajouter.

**20K CCU.** Leftover V73. 8 clients × 60 Hz × N missiles en vol × `Vector3.new`. Pas d’autorité (silhouette cosmétique). Un Z faux casserait le pulse du réacteur (sin × 18, ±0.45). Roblox `Size` est une valeur : on **doit** assigner un Vector3. Ne pas « muter » un Vector3 existant (immutable). Option A : laisser l’alloc (fermer V74 comme API, comme le Size chantier) et prendre V75. Option B : n’assigner que si `|z - lastZ|` dépasse un epsilon (réduit les writes, pas l’alloc native). **Ne pas** convertir en CFrame. **Ne pas** cuire Z dans `piece.offset`.

**Faire.**

1. Dans `UnitModels.place` seulement, branche `role == "flame"` : **soit** documenter + fermer comme API (Option A, alors V75 devient la recette de cette passe), **soit** garder `Vector3.new(0.62, 0.62, 1.8 + sin(time * 18) * 0.45)` avec les **mêmes trois nombres** (Option B n’est un gain que si le runtime élide les writes identiques — mesurer, ne pas inventer un pool Vector3). Fréquence / amplitude **inchangées**. Autres rôles (radar/flag V73, wake Transparency, trail, light) **inchangés**.

2. **Garder le pulse Z.** Ne **pas** geler Size à la construction. Ne **pas** « fermer » radar/flag (V73 déjà). Ne pas « fermer » Overlay roues (V72 déjà). Ne pas « fermer » Overlay roulis (V71 déjà). Ne pas « fermer » BuildingModels Radar/Flag/Boom (V70 déjà). Ne pas toucher `applyRouteProgress` Size.

3. Ne **pas** éditer `Overlay.luau` (V71 / V72 déjà). Ne pas « fermer » les `CFrame.Angles` de construction (`addWake`, `Bow`, missile). Ne pas merger feel.

**Contraintes.** Client-only. **V74 visual ≠ V73 (radar/flag CFrame) ≠ V72 (roues camion Overlay) ≠ Size chantier (API).** Non réentrant (`place` une fois / pièce / frame, un appelant = Overlay). Sans missile interpolé : la branche flame n’est pas atteinte. Client 34/34 (banc « navires, missiles et interpolation » leftover V73 / V71 / V65 / V55 / V52 **doit rester vert** — le premier `stepInterpolation` immobile compose radar/flag ; `not rawequal(part.CFrame, offset)` + `rawequal` Part/offset au second frame **doivent rester verts**. Banc « pose et capture » leftover V72 / V64 / V57 **doit rester vert**. Check modeles V70 **doit rester vert**. Check camera V69 **doit rester vert**). **Ne pas** éditer le serveur.

**Tester.** Banc client navires **doit rester vert** (V73 `not rawequal` radar/flag + `rawequal` Part). Check pose/capture V72 **doit rester vert**. Check modeles V70 **doit rester vert**. Check camera V69 **doit rester vert**. `./tests/run.sh`. Client 34/34.

**Fichiers.** `UnitModels.luau` (`place` branche `role == "flame"` **seulement**, ou rapport Option A sans code). `tests/client.luau` **seulement si** le check navires ne mentionne pas encore V74 (commentaire leftover, **garder** V73/V71/V65). `Overlay.luau` **non**. `BuildingModels.luau` **non**. `WorldCamera.luau` **non**.

### ISSUE-V75 — `PlacementPreview.update` footprint / pulse `CFrame.Angles` 60 Hz

**Problème.** V74 est Size missile. Reste, **chaque frame en mode build** (`init.client` RenderStepped → `preview:update`) :

```
self.footprint.CFrame = CFrame.new(base.X, ground + 0.42, base.Z) * CFrame.Angles(0, 0, math.rad(90))
self.pulse.CFrame = CFrame.new(base.X, ground + 0.38, base.Z) * CFrame.Angles(0, 0, math.rad(90))
```

Rotation **constante** `(0, 0, 90°)` (cylindre plat). Distinct de V73 (unités, `time` variable). Distinct des `CFrame.Angles` de construction (`addWake`, `Bow`) — ici c’est le hot path hover, pas `create`. Distinct de wake / splash / pulse livraison Overlay (événement). `self.tile ~= tile` ne garde que le repositionnement du **modèle** fantôme ; footprint/pulse sont réécrits **chaque** `update`, même tuile inchangée.

**20K CCU.** 8 clients × 60 Hz × 2 `CFrame.Angles` + 2 `CFrame.new` tant que le mode build est armé. Pas d’autorité (`Placement.resolve` déjà partagé ; la vérité reste `Buildings.build`). Un euler faux (≠ 90° Z) coucherait mal le disque d’empreinte.

**Faire.** Recette V70/V73 : `CFrame.new(x, y, z) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))` **ou** (mieux, rotation constante) cuire un `footprintRot` / `pulseRot` une fois à `new` et composer `CFrame.new(x, y, z) * rot` (recette V63 `segment.rot`). Hauteurs `+ 0.42` / `+ 0.38` **inchangées**. `Size = Vector3.new` footprint/pulse **inchangé** cette passe (API rayon, leftover séparé). Ne pas toucher `resolve` / `previewCtxBuf` (V51). Ne pas toucher hover closures (V53).

**Contraintes.** Client-only. **V75 visual ≠ V74 (flame Size) ≠ V73 (UnitModels radar/flag).** Mode build seulement. Client 34/34 (checks « apercu de placement » / « accrochage » V51/V53 **doivent rester verts**. Leftover V73 navires **doit rester vert**). **Ne pas** éditer le serveur. **Ne pas** éditer `UnitModels.luau`.

**Tester.** Checks placement **doivent rester verts**. `./tests/run.sh`. Client 34/34.

**Fichiers.** `PlacementPreview.luau` (`update` footprint/pulse CFrame **seulement**). `tests/client.luau` commentaire leftover. `UnitModels.luau` **non**. `Overlay.luau` **non**. `init.client.luau` **non**.

---

## Hors scope volontaire

- Merger feel `4d8e`/`b19e`/`bec6`/`ab04`/`71f0` / hardening `4c70`/`24a7` sur #148/#146.
- Spatial hash warships / `bunkerCells` (hardening N41) — `bunkersBySlot` + `carrierBuf` suffisent.
- Pairing convois simplifié hardening N40 (poids = level only) — la loi visuelle manhattan/alliance/`longCap` reste.
- `MODE_KEYS` mort (digits 1–4 = bâtiments). Cosmétique.
- Fallout disque = rayon **inner** seulement (OF outer = spec produit).
- Brancher les clés Config mortes (`ATTACK_SPEND_RATE`, `FRONT_TILES_PER_CONTACT`, `BOAT_LANDING_BONUS`).
- `combatUnlocked` forcé à `true` chaque tick playing (`init.server`) : prep=0, pas un leak client.
- Hover client `SpawnHint` (feel N58) — isolation serveur d’abord (V16b livré).
- Buffers déjà livrés réentrants : un seul appelant chacun (sauf `viewFor` **par slot** — c’est voulu). Dupliquer le buffer si un second appelant apparaît. `playerStatsForReplicate` appelle `frontHudForReplicate` — ne pas rappeler le HUD dans `replicate()`.
- Feel N70 `retreating` sur le snapshot — Overlay visuel ne teinte pas la retraite.
- Feel N20 `TRAIN_STOP_BONUS` dans `refreshRailNetwork` — HUD visuel lit l’espérance **sans** ce multiplicateur ; `Trade.deliveryValue` l’applique déjà. Ne pas porter.
- `delivery.level` snapshot à l’arrivée (feel) : le header Trade dit « niveau à l’arrivée » ; dispatch stocke déjà `level` mais `resolve` lit `factory.level`. Produit, pas un bug d’index.
- `dirtyIndexBuf` (feel N72 / hardening N53) — ne ferme pas l’alloc `buffer.create` (voir V14b).
- `buildRoster` (`init.server`, hors bundle) — 10 Hz playing, leftover N2 skip-si-inchangé.
- Feel `neighborScratch` dans `seedBeachhead` : visuel itère `priorityScratch` que `frontPriority` écrase. Ne pas le porter. Leftover séparé.
- `Nukes.splitMirv` `targets` — par MIRV, pas le hot path.
- `Overlay.applyUnits` `Vector2.new` par unité 10 Hz — **fermé** (V55). V52 ne touche que `track` + `extra`. V54 ne touche que HUD sort.
- `HUD.update` ranked + records — **fermé** (V50). Comparateur sort — **fermé** (V54).
- `PlacementPreview.resolve` ctx hover — **fermé** (V51). Closures caller — **fermées** (V53).
- `Overlay.applyUnits` track + extra — **fermé** (V52).
- `RadialMenu` `entries` à l’ouverture — geste joueur, pas 10 Hz.
- `HUD.refreshDiplomacyPanel` `markers` — à la sélection, pas 10 Hz.
- `CFrame` / `Vector3` unités dans `stepInterpolation` 60 Hz — **fermé** (V56). LookAt unités deux Vector3 — **fermé** (V65). Camion lookAt — **fermé** (V64).
- Camion `Vector3.new(0, 0.8, 0)` + `CFrame.new()` identité 60 Hz — **fermé** (V57). LookAt camion deux Vector3 — **fermé** (V64).
- Houle océan `WorldRenderer.step` Vector3 60 Hz — **fermé** (V58).
- Feuillage `animatedFoliage` `CFrame.Angles` 60 Hz — **fermé** (V59).
- `BuildingModels.animate` `PortCraneCable` Vector3 60 Hz — **fermé** (V60). Radar / Flag / Boom `CFrame.Angles` — **fermé** (V70). Ne pas reconvertir en translation.
- `applyRouteProgress` Vector3 lift / arithmétique / lookAt — **fermés** (V61 / V62 / V63).
- Overlay camion lookAt — **fermé** (V64). Unités lookAt — **fermé** (V65). Camera lookAt — **fermé** (V66).
- Camera offset / lerp focus / champ `focusX/Y/Z` — **fermés** (V67 / V68 / V69).
- Radar / `CapitalFlag` / `PortCraneBoom` `CFrame.Angles` 60 Hz — **fermé** (V70). V69 ne touche que le stockage mire. Roulis navire Overlay — **fermé** (V71).
- Overlay navire `CFrame.Angles` roulis 60 Hz — **fermé** (V71). V70 ne touche que BuildingModels. Ne pas convertir en translation. Ne pas cuire un `segRot` d’unité.
- Overlay camion roues `CFrame.Angles` spin 60 Hz — **fermé** (V72). V71 ne touche que le roulis navire. Ne pas convertir en translation. Ne pas cuire le spin dans `piece.offset`.
- `UnitModels.place` radar/flag `CFrame.Angles` 60 Hz — **fermé** (V73). V72 ne touche que les roues camion Overlay. Ne pas convertir en translation. Ne pas cuire l’euler dans `piece.offset`.
- `UnitModels.place` flame `Size = Vector3.new` 60 Hz — leftover V74 (ne pas éditer flame dans V73 — V73 est fermé, V74 est la prochaine passe).
- `PlacementPreview.update` footprint / pulse `CFrame.Angles` 60 Hz — leftover V75 (ne pas éditer PlacementPreview dans V74).
- `CFrame.Angles` de construction (`addWake`, `Bow`, ailettes, `WorldRenderer` glint/tronc) — une fois, pas 60 Hz interpolation.
- Pulse livraison / wake / splash / explosion `CFrame.Angles` — événement, pas 60 Hz.
- Transparency CityWindows / beacons / FactoryOutput / SiloWarning — leftover séparé (pas CFrame).
- Overlay `buildFactoryRoute` `CFrame.lookAt` (construction de voie / `segRot` / pose initiale camion) — une fois par route, pas 60 Hz.

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–55 inchangées (passe 56 = client-only).  
Invariants 5b–5f : index `buildingsBySlot` / `coolingBuildings` / `factoriesBySlot` / `portsByTile` / `navalBasesBySlot` vs hash, chaque 500 ticks.  
Client V48 : check « deltas de terrain et conquetes classees » — prise slot 2→1 classée en gain, delta vide `# == 0` + `rawequal` pools.  
Client V49 : check « etiquettes de faction : centre, contenu et disparition » — second refresh sans slot 1 détruit l’ancre.  
Client V50 : check « identite, ere, diplomatie et classement » — second `HUD.update` d’un seul slot → `#hud.ranked == 1` et `slot == 3`.  
Client V54 : même check — deux slots tuiles égales (100/100), troupes 10 vs 40 → `ranked[1].slot == 8`. Leftover V50 **doit rester vert**.  
Client V51 : check « accrochage du placement et bascule en amelioration » — deux `resolve` successifs même tuile / même status.  
Client V52 : check « navires, missiles et interpolation » — second `applyUnits` du même missile → `extra.tx` = le second, `rawequal` du record extra ; navire `extra == nil`.  
Client V53 : check « apercu de placement » + « accrochage » — inchangés.  
Client V55 : même check navires — `targetX`/`currentX` nombres ; second lot `x/y` différents → `targetX` mute + `rawequal` du record unité. Leftover V52 **doit rester vert**.  
Client V56 : même check navires — `stepInterpolation` après cible déplacée avance `currentX` **et** `currentY`. Leftover V55 **doit rester vert**.  
Client V57 : check « pose et capture de chaque type de batiment » — `onTradeEvent("dispatch")` → `truckModel.Parent == model` ; 12 × 0.02 s → `delivery == nil`, pulse. Leftover V56 **doit rester vert**.  
Client V58 : check « construction du monde 3D » — `#oceanRipples > 0` ; deux `world:step(1/60)` → `rawequal` Part, CFrame X ou Z ≠ `base`. Leftover V57 **doit rester vert**.  
Client V59 : même check construction — `#animatedFoliage > 0` ; deux `world:step` → CFrame.Y ≠ `base`. Leftover V58 **doit rester vert**.  
Client V60 : check « modeles procéduraux : le palier change la silhouette » — `Building.create(PORT)` + deux `animate` → `rawequal` Part câble, CFrame.Y ≠ `RestCFrame.Y` ; `animate(FACTORY)` (0 câble) ne lève pas. Leftover V59 **doit rester vert**.  
Client V61–V64 : check pose/capture — lift / `dx/oy` / `segment.rot` / `segRot` camion. Leftovers V60 câble **et** V57 dispatch **doivent rester verts**.  
Client V65 : même check navires — yaw `fromEulerAnglesYXZ`, plus de lookAt deux Vector3. Leftover V56 / V55 / V52 / V64 **doivent rester verts**.  
Client V66–V69 : check « camera strategique » — pose / offset / lerp / champ `focusX/Y/Z`. Leftover tactile **et** leftover V65 **et** leftover V64 **doivent rester verts**.  
Client V70 : même check modeles — `Building.create(PORT)` boom `CFrame.Y == RestCFrame.Y` (pas une translation) + `not rawequal(CFrame, RestCFrame)` ; `Building.create(SAM)` radar `Y` inchangé + Part stable ; `Building.create(CAPITAL)` drapeau `CFrame ~= RestCFrame` + Part stable. Leftover V60 câble Y **doit rester vert**. Leftover V69 camera `focusX` / `rawequal focus` **doit rester vert**. Leftover V65 navires **doit rester vert**. Leftover V64 `segRot` **doit rester vert**.  
Client V71 : même check navires — roulis `fromEulerAnglesYXZ(rx, 0, rz)`, plus de `CFrame.Angles` 60 Hz. Premier `stepInterpolation` (unités immobiles) ne compose pas le roulis. Leftover V70 modeles **doit rester vert**. Leftover V65 / V55 / V52 **doivent rester verts**. Leftover V64 `segRot` **doit rester vert**. Leftover V69 camera `focusX` **doit rester vert**.  
Client V72 : même check pose/capture — roues `fromEulerAnglesYXZ(spin, 0, 0)`, plus de `CFrame.Angles` 60 Hz. Leftover V64 `rawequal(segRot)` pendant la livraison **doit rester vert**. Leftover V57 dispatch → Parent + 12 × 0.02 s → `delivery == nil` + pulse **doit rester vert**. Leftover V71 navires **doit rester vert**. Leftover V70 modeles **doit rester vert**. Leftover V69 camera `focusX` **doit rester vert**.  
Client V73 : même check navires — radar/flag `fromEulerAnglesYXZ`, plus de `CFrame.Angles` 60 Hz. Premier `stepInterpolation` (unités immobiles) compose `UnitModels.place` : `not rawequal(part.CFrame, offset)` radar **et** flag. Second `stepInterpolation` (missile en mouvement) : `rawequal` Part + `rawequal` offset. Leftover V71 roulis **doit rester vert**. Leftover V65 / V55 / V52 **doivent rester verts**. Leftover V72 pose/capture **doit rester vert**. Leftover V70 modeles **doit rester vert**. Leftover V69 camera `focusX` **doit rester vert**.  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
