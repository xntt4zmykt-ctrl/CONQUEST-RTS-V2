# Nightly report — passe 68 (revue PR #175)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-7be5` (PR #175, `0c3dd26`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-75ce`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #175 (`BuildingModels` BuildRing `fromEulerAnglesYXZ` — HEAD visuel, V85). Correctifs sûrs, sans merger feel `c299`/`595e`/`bfcc` ni hardening `41e2`/`93f6`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| WorldRenderer `buildDecorations` TreeTrunk / SavannaTrunk `fromEulerAnglesYXZ` (Z=90° fixe, deux sites, inline) ; plus de `CFrame.Angles` | `WorldRenderer.luau`, `tests/client.luau` | V86 |

`rankByTiles` / hover closures / `trackUnit` extra / `targetX`/`currentX` / unités monde nombres (V56) / camion lerp (V57) / houle (V58) / feuillage (V59) / câble PORT (V60) / lift cuit (V61) / interpolation nombres (V62) / `segment.rot` chantier (V63) / camion `segRot` (V64) / unités yaw (V65) / pose caméra translation (V66) / offset `ox/oy/oz` (V67) / lerp `focus` (V68) / champ `focusX/Y/Z` (V69) / Radar / Flag / Boom (V70) / roulis navire (V71) / roues camion (V72) / radar/flag unités (V73) / flame Size API (V74) / `footprintRot` / `pulseRot` Preview (V75) / Size rayon kind (V76) / early-out hover (V77) / LaunchWake `wakeRot` (V78) / LandingSplash `wakeRot` (V79) / DeliveryPulse `wakeRot` (V80) / Shockwave `wakeRot` (V81) / Effects `conquestPulse` `pulseRot` (V82) / Effects `selectTile` `pulseRot` (V83) / `previewCtxBuf` / `self.ranked` / `gainBuf` / `countBuf` / `destroyBuf` / `validTiles` pools / `parkedBuf` / `collapseRemainBuf` / `allyBuf` / `stripBuf` / `ctxBuf` / `doomedBuf` / `collapsingBuf` **conservés**. `seedBeachhead` / inbound recycle / `settledHumans` / `awaitingSpawn` **non touchés**. `CAPTURE_GUARD=80` visuel **inchangé**. Schéma filaire client **inchangé** (V14b reste ouvert). `HUD.luau` / `FactionLabels.luau` / `WorldSpace.luau` / `WorldCamera.luau` / `Minimap.luau` / `BuildingModels.luau` / `UnitModels.luau` / `PlacementPreview.luau` / `Overlay.luau` / `Effects.luau` / `init.client.luau` **non édités**. `WorldRenderer.luau` **seulement** `buildDecorations` (TreeTrunk / SavannaTrunk). Serveur **inchangé**. GameState ne require toujours pas Buildings / Research. Extra missile **inchangé** (V52). `targetX`/`currentX` **inchangés** (V55). Conversion monde unités **inchangée** (V56). Camion lerp **inchangé** (V57). Houle `oceanRipples` **inchangée** (V58, 60 Hz). Feuillage `animatedFoliage` **inchangé** (V59). Câble `PortCraneCable` **inchangé** (V60). Lift `layer.origin` **inchangé** (V61). Lerp `ox/dx` **inchangé** (V62). `segment.rot` chantier **inchangé** (V63). Camion `segRot` **inchangé** (V64). Unités yaw **inchangées** (V65). Pose caméra `CFrame.new * rotation` **inchangée** (V66). Offset `ox/oy/oz` **inchangé** (V67). Lerp nombres **inchangé** (V68). Champ `focusX/Y/Z` **inchangé** (V69). Radar / Flag / Boom **inchangés** (V70). Roulis navire **inchangé** (V71). Roues camion **inchangées** (V72). Radar/flag unités **inchangés** (V73). Flame `Size = Vector3.new` **inchangé** (V74 API, pulse Z). `footprintRot` / `pulseRot` Preview **inchangés** (V75). Size rayon **inchangé** (V76). Early-out hover **inchangé** (V77). LaunchWake spawn Y + 0.12 **inchangé** (V78). LandingSplash despawn Y + 0.14 **inchangé** (V79). Pulse livraison `route.to` **inchangé** (V80). Shockwave explosion `PLAINS + 0.5` **inchangé** (V81). Effects `conquestPulse` height surface + 0.8 **inchangé** (V82). Effects `selectTile` height surface + 0.48 **inchangé** (V83). `OceanGlint` yaw `angle` **inchangé** (V84). `BuildRing` Z=90° **inchangé** (V85). Transparency CityWindows / beacons / FactoryOutput / SiloWarning **inchangées**. `RestCFrame` posé à la construction **inchangé**. `part.Size = Vector3.new` chantier **inchangé** (API). `targetFocus` Vector3 et pan/clamp **inchangés** (gestes). `self.focus` Vector3 **conservé** pour `focusTile(instant)` seulement. `resolve` / `previewCtxBuf` **inchangés** (V51). Hover closures **inchangées** (V53). `TreeTrunk`/`SavannaTrunk` `CFrame.Angles` **fermé** (V86). `Rock` `CFrame.Angles` **inchangé** (leftover V87, yaw `phase`).

---

## Constatations PR #175 (à ne pas casser)

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
- **Radar / Flag / Boom :** `BuildingModels.animate` (V70). `RestCFrame` translation pure. Hot path : `CFrame.new(rest.X, rest.Y, rest.Z) * CFrame.fromEulerAnglesYXZ(ax, ay, az)`. Plus de `CFrame.Angles` 60 Hz sur ces trois noms.
- **Roulis navire Overlay :** `Overlay.stepInterpolation` (V71). Branche `mag > 0.01 and not unit.isMissile` seulement. Immobile : **zéro** compose roulis.
- **Roues camion Overlay :** `Overlay.stepInterpolation` (V72). Branche `piece.part.Name == "Wheel"` seulement, pendant `route.delivery`.
- **Radar / flag unités :** `UnitModels.place` (V73). Compose `frame * (offset * euler)`. Appelé même immobile.
- **Flame missile :** `UnitModels.place` (V74 Option A). `Size = Vector3.new(0.62, 0.62, 1.8 + sin(time * 18) * 0.45)` **conservé**. Pulse Z **vivant**. Distinct de V76 (Preview Size rayon constant).
- **Empreinte placement rot :** `PlacementPreview.update` (V75). `footprintRot` / `pulseRot` cuits à `new`. **Pas réentrant**. Mode build seulement. Distinct de Effects `pulseRot` (V82, autre objet).
- **Empreinte placement Size :** `PlacementPreview.setKind` (V76). Rayon = kind seulement. Distinct de V74 (flame Z pulse).
- **Empreinte placement hover :** `PlacementPreview.update` (V77). Early-out si `shown` et tuile **et** statut inchangés.
- **Overlay LaunchWake :** `trackUnit` insert navire (V78). `wakeRot` cuit à `Overlay.new`. Y + 0.12. **Pas réentrant**. Événement spawn, pas 60 Hz.
- **Overlay LandingSplash :** `applyUnits` id absent, pas missile (V79). Réutilise `self.wakeRot`. Y + 0.14. Skip retraite N56 **n’existe pas** sur visual.
- **Overlay DeliveryPulse :** `stepInterpolation` fin de trajet camion (V80). Réutilise `self.wakeRot`. `route.to` **déjà** un Vector3.
- **Overlay Shockwave :** `Overlay.explosion` (V81). Réutilise `self.wakeRot`. Hot path : `CFrame.new(ground.X, PLAINS + 0.5, ground.Z) * self.wakeRot`. Y = PLAINS + 0.5 **inchangé**. Tween Size/Transparency **inchangé**. Sphère Blast / fumée **inchangées**. Recette feel N133 — **pas** merger `bfcc`. Distinct de V78 (spawn, Y + 0.12). Distinct de V79 (despawn, Y + 0.14). Distinct de V80 (arrivée camion). Distinct de Effects `conquestPulse` (V82, surface + 0.8 visuel, **pas** `Y = 3` feel). **Pas réentrant**. Événement explosion, pas 60 Hz.
- **Effects `conquestPulse` :** `Effects.conquestPulse` (V82). `pulseRot` cuit à `Effects.new` : `fromEulerAnglesYXZ(0, 0, rad(90))`. Hot path : `CFrame.new(ground.X, height, ground.Z) * self.pulseRot`. `height` = `surfaceHeight + 0.8` (fallback `3` hors carte) **inchangé**. Name `ConquestPulse`. Tween Size/Transparency **inchangé**. `MAX_LIVE_PULSES=8` **inchangé**. Caps flash **inchangés**. `lossWave` passe par le même site. Recette feel N134 — **pas** merger `bfcc`, **pas** `Y = 3`. Distinct de V81 (explosion Overlay). Distinct de `SelectionRing` (V83, surface + 0.48). Distinct de `PlacementPreview.pulseRot` (autre objet). **Pas réentrant**. Événement vague, pas 60 Hz. **Ne pas** inventer un champ Overlay.
- **Effects `selectTile` :** `Effects.selectTile` (V83). Réutilise `self.pulseRot` (V82 déjà). Hot path : `CFrame.new(base.X, height + 0.48, base.Z) * self.pulseRot`. `height` = `WorldSpace.surfaceHeight(terrain, index)` (**sans** +0.8), puis `+ 0.48` **inchangé**. Name `SelectionRing` **inchangé**. Tweens Transparency/Size **inchangés**. Marker `SelectedTerritory` **inchangé** (translation seule, Y + 0.58). `clearSelection` **inchangé**. Distinct de V82 (onde, surface+0.8, Name=`ConquestPulse`). Distinct de `ActionPreview` (pas de cylindre, translation seule). Distinct de Overlay Shockwave (V81, `PLAINS + 0.5`). Distinct de `PlacementPreview.pulseRot` (autre objet). Geste joueur (`selectTile`), pas 60 Hz interpolation. Recette V82 `pulseRot` — **pas** merger feel `bfcc`, **pas** inventer `selectionRot`. **Pas réentrant**. **Ne pas** changer `conquestPulse` (V82 déjà). **Ne pas** changer `previewTile`. **Ne pas** porter Overlay. **PR #172 intact** — rien à revert.
- **WorldRenderer `buildOcean` OceanGlint :** `WorldRenderer.buildOcean` (V84). Hot path : `CFrame.new(world.X, Config.OCEAN_LEVEL + 0.08, world.Z) * CFrame.fromEulerAnglesYXZ(0, angle, 0)`. `angle = math.rad(-18 + (i % 9) * 4)` **inchangé** (yaw **variable**, **pas** un rot cuit). Y = `OCEAN_LEVEL + 0.08` **inchangé**. Size / Transparency / Color / Name `OceanGlint` **inchangés**. `table.insert(self.oceanRipples, { part, base = glint.CFrame, phase })` **après** la pose — `base` = CFrame posée (V58 lit `base`). Distinct de V58 (houle 60 Hz : X/Z nombres depuis `base`, **pas** la pose initiale). Distinct de V83 (geste `selectTile`, `pulseRot`, Y = surface+0.48). Distinct de V82 (onde, `pulseRot`, Y = surface+0.8). Distinct de V81 (explosion Overlay, `wakeRot`, Y = PLAINS+0.5). Distinct de V85 (BuildRing chantier, Z=90° fixe). Distinct de V86 (TreeTrunk, Z=90° fixe, `buildDecorations`). Construction de chunk, **pas** 60 Hz interpolation. Recette feel N135 — **pas** merger `595e`. **Pas réentrant**. **Ne pas** changer `WorldRenderer.step` (V58 déjà). **Ne pas** changer `Effects.luau` (V82/V83 déjà). **Ne pas** porter Overlay. **Ne pas** inventer `glintRot`. **PR #174 intact** — rien à revert.
- **BuildingModels `playConstruction` BuildRing :** `BuildingModels.playConstruction` (V85). Hot path : `CFrame.new(ground) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))`. Z **fixe** 90° (cylindre plat). `ground` Vector3 **inchangé**. Size `0.5, 4, 4` **inchangé**. Tween vers `0.5, 18, 18` + Transparency 1 **inchangé**. Name `BuildRing` / Color / Material / PointLight **inchangés**. **Pas** de `ringRot` cuit (événement unique, recette feel N136 **inline**). **Pas** `Effects.pulseRot`. Distinct de V84 (OceanGlint yaw `angle` variable). Distinct de V86 (TreeTrunk, `WorldRenderer.buildDecorations`). Distinct de V83 (SelectionRing, `pulseRot`, Y = surface+0.48). Distinct de V82 (onde, `pulseRot`, Y = surface+0.8). Distinct de V75 (`PlacementPreview.pulseRot`, hover 60 Hz). Événement construction, **pas** 60 Hz interpolation. Recette feel N136 — **pas** merger `595e`. **Pas réentrant**. **Ne pas** changer `BuildingModels.animate` (V60/V70 déjà). **Ne pas** changer `Effects.luau`. **Ne pas** porter Overlay. **PR #175 intact** — rien à revert.
- **WorldRenderer `buildDecorations` TreeTrunk / SavannaTrunk :** `WorldRenderer.buildDecorations` (V86). Hot path TreeTrunk : `CFrame.new(base.X, ground + height / 2, base.Z) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))`. Hot path SavannaTrunk : `CFrame.new(base.X, ground + 1.6, base.Z) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))`. Z **fixe** 90° (cylindre Roblox pointe X, on redresse). `height` / `base` / `ground` / Size / Color / Material / Name **inchangés**. `Shape = Cylinder` **posé après**, **inchangé**. Couronne `TreeCrown` / `SavannaCrown` **sans** Angles (translation seule) — **non touchée**. `animatedFoliage` enregistre la couronne, **pas** le tronc. **Pas** de `trunkRot` cuit (translations distinctes, recette feel N137 **inline**). Distinct de V85 (BuildRing, `BuildingModels.playConstruction`). Distinct de V84 (OceanGlint yaw `angle` **variable**, `buildOcean`). Distinct de V59 (feuillage 60 Hz, Y nombres depuis `base`, **pas** la pose du tronc). Distinct de V58 (houle 60 Hz). Distinct de V87 leftover (`Rock` yaw `phase` variable). Construction de chunk, **pas** 60 Hz interpolation. Recette feel N137 — **pas** merger `c299`. **Pas réentrant**. **Ne pas** changer `WorldRenderer.step` (V58/V59 déjà). **Ne pas** changer `BuildingModels.luau` (V85 déjà). **Ne pas** changer `Effects.luau`. **Ne pas** changer `buildOcean`. **Ne pas** éditer `Rock`.
- **Chantier de voie :** `applyRouteProgress` lift + nombres + `segment.rot` (V61 + V62 + V63). `part.Size = Vector3.new` **inchangé** (API).
- **Caméra stratégique :** `WorldCamera.step` overview (V66 + V67 + V68 + V69). Champ `focusX/Y/Z`. Plus de `Vector3.new` idle 60 Hz.
- **Hover 60 Hz :** `previewOwnerAt` / `previewBuildingAt` module (V53).
- **Spawn clic :** terre libre + `isSpawnIsolated`. Snap `r=6` seulement si la tuile cliquée est **occupée**.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `GameState` ne require pas `Buildings` / `Research` / `Types`.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–18) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.
- **PR #175 :** V85 intact (`fromEulerAnglesYXZ` Z=90° fixe, `BuildRing` Y == 2, pas de `ringRot`). OceanGlint V84 / SelectionRing V83 / ConquestPulse V82 / Shockwave V81 / DeliveryPulse V80 / LandingSplash V79 / LaunchWake V78 / early-out V77 / Size V76 / rot V75 **non retouchés**. Rien à revert.

---

## Specs worker (reste)

Ne pas merger feel `c299`/`595e`/`bfcc` ni hardening `41e2`/`93f6` sur cette branche sans rebase. Porter **une** recette à la fois. Feel N129 (footprint hauteur **0.4**, **pas** de pulse) ≠ visual V75/V76/V77 — ne pas merger. Feel N134 `Y = 3` **non** porté (visuel = surface + 0.8). Feel N135 OceanGlint **fermée** (V84) — **ne pas merger** `595e`. Feel N136 BuildRing **fermée** (V85, PR #175) — **ne pas merger** `595e`. Feel N137 TreeTrunk **fermée** ici (V86 inline) — **ne pas merger** `c299`. Feel N138 Rock — **ne pas merger** `c299`.

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

### ISSUE-V87 — WorldRenderer `buildDecorations` Rock `CFrame.Angles`

**Problème.** V86 ferme `CFrame.Angles` sur les **troncs** (`TreeTrunk` / `SavannaTrunk`, Z=90° fixe). Reste, **même fonction** `buildDecorations`, le rocher :

```
CFrame.new(base.X, ground + 0.55, base.Z) * CFrame.Angles(0, phase, 0)
```

Un site : `Rock` (`WedgePart`, `terrain >= HILLS`). Yaw **variable** `phase = (px * 0.37 + py * 0.61) % (math.pi * 2)` — **pas** un Z=90° fixe. Distinct de V86 (troncs cylindre, Z=90° fixe). Distinct de V85 (BuildRing, `BuildingModels`). Distinct de V84 (OceanGlint yaw `angle` variable, **`buildOcean`**, formule `angle` différente). Distinct de V59 (feuillage 60 Hz, couronne, **pas** le rocher). Construction de chunk, **pas** 60 Hz interpolation. `CastShadow = true` **déjà** posé après. Troncs V86 **déjà** `fromEulerAnglesYXZ` — **ne pas** y retoucher.

**20K CCU.** 8 clients × rebuild décorations (chargement + chunks). Pas d’autorité. Même classe que feel N138 (Angles → `fromEulerAnglesYXZ` inline, yaw `phase` variable — **ne pas** cuire un rot, yaw distinct par rocher, comme V84 `glintRot` interdit).

**Faire.** Remplacer `CFrame.Angles(0, phase, 0)` par `CFrame.fromEulerAnglesYXZ(0, phase, 0)`. Hot path : `CFrame.new(base.X, ground + 0.55, base.Z) * CFrame.fromEulerAnglesYXZ(0, phase, 0)`. `phase` / `base` / `ground` / Size / Color / Material / Name **inchangés**. `CastShadow = true` **inchangé**. ClassName `WedgePart` **inchangé**. Ne **pas** cuire un `rockRot` (yaw distinct par instance, recette feel N138 **inline** — même raison que V84 `glintRot`). Ne **pas** toucher `TreeTrunk` / `SavannaTrunk` (V86 déjà). Ne **pas** changer `WorldRenderer.step` (V58/V59 déjà). Ne **pas** changer `BuildingModels.luau` (V85 déjà). Ne **pas** changer `Effects.luau`. Ne **pas** merger feel `c299`.

**Contraintes.** Client-only. **V87 visual ≠ V86 (TreeTrunk Z=90°) ≠ V84 (OceanGlint `buildOcean`) ≠ V59 (feuillage 60 Hz).** Recette feel N138 — **ne pas merger** `c299`. Client 34/34 (check construction du monde **doit rester vert**. Check TreeTrunk V86 cylindre **doit rester vert**. Check modeles V85 **doit rester vert**. Check calques V83 **doit rester vert**. Check vagues V82 **doit rester vert**. V58 houle **doit rester vert**. V59 feuillage **doit rester vert**). **Ne pas** éditer le serveur. **Ne pas** éditer `BuildingModels.luau`. **Ne pas** éditer `Effects.luau`. **Ne pas** éditer `Overlay.luau`. **Ne pas** éditer `UnitModels.luau`. **Ne pas** éditer `buildOcean`. **Ne pas** éditer TreeTrunk / SavannaTrunk.

**Tester.** Check « construction du monde 3D » : après rebuild, au moins un Part `Name == Rock` dans `world.decorations` ; `ClassName == WedgePart`. V86 TreeTrunk/SavannaTrunk cylindre **doit rester vert**. V84 OceanGlint Y = `OCEAN_LEVEL + 0.08` **doit rester vert**. V58 (Part glint stable, X/Z bougent) **doit rester vert**. V59 (couronne Y bouge) **doit rester vert**. Check modeles V85 (`BuildRing` Y == 2) **doit rester vert**. `./tests/run.sh`. Client 34/34.

**Fichiers.** `WorldRenderer.luau` (`buildDecorations` **seulement**, la ligne `Rock`). `tests/client.luau` check construction + commentaire leftover. `BuildingModels.luau` **non**. `Effects.luau` **non**. `Overlay.luau` **non**. `playConstruction` **non**. `buildOcean` **non**. TreeTrunk / SavannaTrunk **non**. `init.client.luau` **non**.

---

## Hors scope volontaire

- Merger feel `c299`/`595e`/`bfcc` / hardening `41e2`/`93f6` sur #175.
- Feel N129 footprint hauteur 0.4 sans pulse — **ne pas** porter le Size visual V76 (pas de pulse feel).
- Feel N134 `Y = 3` — **non** porté (visuel = surface + 0.8).
- Feel N135 OceanGlint — **fermée** (V84, PR #174, yaw variable, **pas** merger `595e`).
- Feel N136 BuildRing — **fermée** (V85, PR #175, Z=90° fixe, **pas** merger `595e`).
- Feel N137 TreeTrunk — **porté ici** (V86 inline, Z=90° fixe, deux sites, **pas** merger `c299`).
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
- `Overlay.applyUnits` `Vector2.new` par unité 10 Hz — **fermé** (V55).
- `HUD.update` ranked + records — **fermé** (V50). Comparateur sort — **fermé** (V54).
- `PlacementPreview.resolve` ctx hover — **fermé** (V51). Closures caller — **fermées** (V53).
- `Overlay.applyUnits` track + extra — **fermé** (V52).
- `RadialMenu` `entries` à l’ouverture — geste joueur, pas 10 Hz.
- `HUD.refreshDiplomacyPanel` `markers` — à la sélection, pas 10 Hz.
- `CFrame` / `Vector3` unités dans `stepInterpolation` 60 Hz — **fermé** (V56). LookAt unités — **fermé** (V65). Camion lookAt — **fermé** (V64).
- Camion `Vector3.new(0, 0.8, 0)` + `CFrame.new()` identité 60 Hz — **fermé** (V57).
- Houle océan / feuillage / câble PORT — **fermés** (V58 / V59 / V60).
- Radar / Flag / Boom `CFrame.Angles` — **fermé** (V70).
- Overlay navire roulis / roues camion / radar-flag unités — **fermés** (V71 / V72 / V73).
- `UnitModels.place` flame `Size = Vector3.new` 60 Hz — **fermé** (V74 Option A, API). Pulse Z conservé. Ne pas inventer un pool Vector3.
- `PlacementPreview.update` footprint / pulse `CFrame.Angles` 60 Hz — **fermé** (V75). Rot cuit à `new`. Ne pas cuire la translation (le curseur bouge).
- `PlacementPreview.setKind` footprint / pulse `Size = Vector3.new` — **fermé** (V76). Rayon = kind. Ne pas geler Size au `new` initial (`10×10` placeholder).
- `PlacementPreview.update` Color / Transparency / `CFrame.new` si tuile+statut inchangés — **fermé** (V77). `update(nil)` nil le tile.
- Overlay LaunchWake `CFrame.Angles` spawn navire — **fermé** (V78). `wakeRot` cuit à `new`.
- Overlay LandingSplash `CFrame.Angles` despawn — **fermé** (V79). Réutilise `wakeRot`.
- Overlay DeliveryPulse `CFrame.Angles` — **fermé** (V80). Réutilise `wakeRot`.
- Overlay Shockwave `CFrame.Angles` — **fermé** (V81). Réutilise `wakeRot`.
- Effects `conquestPulse` `CFrame.Angles` — **fermé** (V82). `pulseRot` cuit à `Effects.new`. Height visuel = surface + 0.8, **pas** `Y = 3`.
- Effects `selectTile` SelectionRing `CFrame.Angles` — **fermé** (V83). Réutilise `pulseRot` V82, height = surface + 0.48.
- WorldRenderer `buildOcean` OceanGlint `CFrame.Angles` — **fermé** (V84). Yaw `angle` variable, `fromEulerAnglesYXZ`, **pas** un rot cuit.
- BuildingModels `playConstruction` BuildRing `CFrame.Angles` — **fermé** (V85). Z=90° fixe, `fromEulerAnglesYXZ` inline, **pas** un rot cuit, **pas** `Effects.pulseRot`.
- WorldRenderer `buildDecorations` TreeTrunk / SavannaTrunk `CFrame.Angles` — **fermé** (V86). Z=90° fixe, deux sites, `fromEulerAnglesYXZ` inline, **pas** un rot cuit, **pas** merger `c299`.
- WorldRenderer `buildDecorations` Rock `CFrame.Angles` — leftover V87 (yaw `phase` variable, un site, `fromEulerAnglesYXZ` inline, recette feel N138, **pas** un rot cuit, **pas** merger `c299`).
- `CFrame.Angles` de construction restants (`addWake`, `Bow`, ailettes, toits usine, portes silo, rampes SAM, `cylinder()`) — une fois, pas 60 Hz interpolation. Prochaine après V87 = BuildingModels `cylinder()` (feel N139, Z=90° helper).
- Transparency CityWindows / beacons / FactoryOutput / SiloWarning — leftover séparé (pas CFrame, animation `sin(time)`).
- Overlay `buildFactoryRoute` `CFrame.lookAt` (construction de voie / `segRot` / pose initiale camion) — une fois par route, pas 60 Hz.

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–67 inchangées (passe 68 = client-only).  
Invariants 5b–5f : index `buildingsBySlot` / `coolingBuildings` / `factoriesBySlot` / `portsByTile` / `navalBasesBySlot` vs hash, chaque 500 ticks.  
Client V75 : check « apercu de placement » — `footprintRot` / `pulseRot` cuits à `new`, `rawequal` après hover, hauteurs `+0.42/+0.38`. Leftover V51/V53 accrochage **doit rester vert**.  
Client V76 : même check apercu — `setKind(CITY)` Size `Y == TILE*3` (36), pulse `* 1.08` ; deux `update` → `rawequal(Size)` ; `setKind(DEFENSE)` Size `Y == DEFENSE_RADIUS*TILE*2` (144) ; hover ne perd pas le rayon bunker. Leftover V75 rot **doit rester vert**.  
Client V77 : même check apercu — deux `update(1000, "exact")` → `rawequal(CFrame)` ; `update(1000, "snap")` change Color, CFrame `rawequal` ; `update(nil)` Transparency == 1 puis restore < 1. Leftover V76 Size **doit rester vert**.  
Client V78 : check « navires, missiles et interpolation » — `wakeRot` cuit à `new`, 3 navires + 1 missile → 3 `LaunchWake`, Y = `OCEAN_LEVEL + 0.12`, relot `rawequal`. Leftover V73 radar/flag **doit rester vert**.  
Client V79 : même check navires — `applyUnits({}, {})` → 3 `LandingSplash`, missile skip, Y = `OCEAN_LEVEL + 0.14`, `rawequal(wakeRot)`. Leftover V78 LaunchWake **doit rester vert**.  
Client V80 : check « pose et capture » — après `delivery == nil`, DeliveryPulse présent, `rawequal(overlay.wakeRot, bakedWake)` (capturé **avant** le dispatch). Leftover V79 LandingSplash **doit rester vert**.  
Client V81 : check « navires, missiles et interpolation » — après `overlay:explosion(50, 50, 9)`, Shockwave présent, `Y == PLAINS + 0.5`, `rawequal(wakeRot)`. Leftover V80 DeliveryPulse **doit rester vert**. Leftover V79 LandingSplash **doit rester vert**.  
Client V82 : check « vagues de conquete » — `pulseRot` cuit à `new`, après `conquestWave({5})` ConquestPulse présent, `Y == surfaceHeight(5) + 0.8`, `Y ~= 3`, `rawequal(effects.pulseRot)`. Leftover V81 Shockwave **doit rester vert**.  
Client V83 : check « calques d'entites, effets et apercu » — `pulseRot` capturé **avant** `selectTile` ; après `selectTile(2000, …)`, `SelectionRing` présent, `Y == surfaceHeight(2000) + 0.48`, `rawequal(effects.pulseRot)` ; `clearSelection` retire le ring. Leftover V82 ConquestPulse **doit rester vert**.  
Client V84 : check « construction du monde 3D » — après rebuild, `#oceanRipples > 0`, premier Part `Name == OceanGlint`, `Y == OCEAN_LEVEL + 0.08` ; puis `world:step` deux fois — V58 **doit rester vert** (Part stable, X/Z bougent, Transparency bande). Leftover V83 SelectionRing **doit rester vert**. Leftover V82 ConquestPulse **doit rester vert**.  
Client V85 : check « modeles procéduraux : le palier change la silhouette » — après `Building.create` + `Building.playConstruction(model, Vector3.new(0, 2, 0))`, `BuildRing` présent, `math.abs(ring.CFrame.Y - 2) < 1e-6`. Silhouette palier **doit rester verte**. Leftover V84 OceanGlint **doit rester vert**. Leftover V83 SelectionRing **doit rester vert**.  
Client V86 : check « construction du monde 3D » — après rebuild, au moins un Part `Name == TreeTrunk` ou `SavannaTrunk` dans `world.decorations` ; `Shape == Enum.PartType.Cylinder`. V84 OceanGlint Y **doit rester vert**. V58 houle **doit rester vert**. V59 feuillage **doit rester vert**. Check modeles V85 (`BuildRing` Y == 2) **doit rester vert**. Leftover V87 Rock **non testé ici**.  
Client V73 : check navires leftover **doit rester vert**.  
Client V72 : check pose/capture leftover **doit rester vert**.  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
