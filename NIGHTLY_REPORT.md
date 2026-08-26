# Nightly report — passe 59 (revue PR #157)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-70a5` (PR #157, `66465f3`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-185a`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #157 (`PlacementPreview` Size rayon = kind — HEAD visuel, V76). Correctifs sûrs, sans merger feel `5655`/`396d` ni hardening `e291`/`0744`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `PlacementPreview.update` early-out si tuile + statut inchangés et déjà visible | `PlacementPreview.luau`, `tests/client.luau` | V77 |
| `update(nil)` nil `self.tile` / `self.status` / `self.shown` pour forcer le restore au retour souris | `PlacementPreview.luau` | piège hide |

`rankByTiles` / hover closures / `trackUnit` extra / `targetX`/`currentX` / unités monde nombres (V56) / camion lerp (V57) / houle (V58) / feuillage (V59) / câble PORT (V60) / lift cuit (V61) / interpolation nombres (V62) / `segment.rot` chantier (V63) / camion `segRot` (V64) / unités yaw (V65) / pose caméra translation (V66) / offset `ox/oy/oz` (V67) / lerp `focus` (V68) / champ `focusX/Y/Z` (V69) / Radar / Flag / Boom (V70) / roulis navire (V71) / roues camion (V72) / radar/flag unités (V73) / flame Size API (V74) / `footprintRot` / `pulseRot` (V75) / Size rayon kind (V76) / `previewCtxBuf` / `self.ranked` / `gainBuf` / `countBuf` / `destroyBuf` / `validTiles` pools / `parkedBuf` / `collapseRemainBuf` / `allyBuf` / `stripBuf` / `ctxBuf` / `doomedBuf` / `collapsingBuf` **conservés**. `seedBeachhead` / inbound recycle / `settledHumans` / `awaitingSpawn` **non touchés**. `CAPTURE_GUARD=80` visuel **inchangé**. Schéma filaire client **inchangé** (V14b reste ouvert). `HUD.luau` / `FactionLabels.luau` / `Overlay.luau` / `WorldSpace.luau` / `WorldRenderer.luau` / `WorldCamera.luau` / `Minimap.luau` / `BuildingModels.luau` / `UnitModels.luau` / `init.client.luau` **non édités**. Serveur **inchangé**. GameState ne require toujours pas Buildings / Research. Extra missile **inchangé** (V52). `targetX`/`currentX` **inchangés** (V55). Conversion monde unités **inchangée** (V56). Camion lerp **inchangé** (V57). Houle `oceanRipples` **inchangée** (V58). Feuillage `animatedFoliage` **inchangé** (V59). Câble `PortCraneCable` **inchangé** (V60). Lift `layer.origin` **inchangé** (V61). Lerp `ox/dx` **inchangé** (V62). `segment.rot` chantier **inchangé** (V63). Camion `segRot` **inchangé** (V64). Unités yaw **inchangées** (V65). Pose caméra `CFrame.new * rotation` **inchangée** (V66). Offset `ox/oy/oz` **inchangé** (V67). Lerp nombres **inchangé** (V68). Champ `focusX/Y/Z` **inchangé** (V69). Radar / Flag / Boom **inchangés** (V70). Roulis navire **inchangé** (V71). Roues camion **inchangées** (V72). Radar/flag unités **inchangés** (V73). Flame `Size = Vector3.new` **inchangé** (V74 API, pulse Z). `footprintRot` / `pulseRot` **inchangés** (V75). Size rayon **inchangé** (V76). Transparency CityWindows / beacons / FactoryOutput / SiloWarning **inchangées**. `RestCFrame` posé à la construction **inchangé**. Explosion / wake / splash **inchangés** (événement). `part.Size = Vector3.new` chantier **inchangé** (API). `targetFocus` Vector3 et pan/clamp **inchangés** (gestes). `self.focus` Vector3 **conservé** pour `focusTile(instant)` seulement. `resolve` / `previewCtxBuf` **inchangés** (V51). Hover closures **inchangées** (V53). Pulse livraison `CFrame.Angles` **inchangé** (événement, leftover V80). LaunchWake `CFrame.Angles` **inchangé** (leftover V78).

---

## Constatations PR #157 (à ne pas casser)

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
- **Empreinte placement rot :** `PlacementPreview.update` (V75). `footprintRot` / `pulseRot` cuits à `new` : `fromEulerAnglesYXZ(0, 0, rad(90))`. Hot path : `CFrame.new(base.X, ground + 0.42, base.Z) * self.footprintRot` et `CFrame.new(..., ground + 0.38, ...) * self.pulseRot` **seulement si la tuile a changé** (V77). Hauteurs `+0.42` / `+0.38` **inchangées**. Rotation constante — recette V63, **pas** V70 (`time` variable). **Pas réentrant**. Mode build seulement.
- **Empreinte placement Size :** `PlacementPreview.setKind` (V76). Rayon = kind seulement : `DEFENSE` → `DEFENSE_RADIUS * TILE_SIZE * 2` (144), sinon `TILE_SIZE * 3` (36). `pulseSize = radius * 1.08`. Size posé **une fois** au changement de kind. Hover ne réécrit plus Size. Placeholder `10×10` / `8×8` du `new` n’est pas le rayon réel. `setKind` same-kind early-out **conservé**. `hide()` cache aussi le pulse. Distinct de V74 (flame Z pulse `sin(time*18)`). Distinct de V75 (CFrame translation). Distinct de `part.Size` chantier (API largeur voie). **Pas réentrant**. Mode build seulement.
- **Empreinte placement hover :** `PlacementPreview.update` (V77). Early-out si `shown` et tuile **et** statut inchangés : zéro `WorldSpace` / Color / `CFrame.new`. Color seulement si statut a changé (ou restore). CFrame seulement si tuile a changé (V75). `update(nil)` pose `tile = nil`, `status = nil`, `shown = false` — sans ça le restore au retour souris serait avalé. `setKind` reset `shown`. Distinct de V76 (Size). Distinct de V75 (rot cuit, translation quand la tuile bouge). Distinct de V74 (flame Z **doit** changer). Distinct de CityWindows / beacons `sin(time)` (**ne pas** geler). **Pas réentrant**. Mode build seulement.
- **Chantier de voie :** `applyRouteProgress` lift + nombres + `segment.rot` (V61 + V62 + V63). `part.Size = Vector3.new` **inchangé** (API).
- **Caméra stratégique :** `WorldCamera.step` overview (V66 + V67 + V68 + V69). Champ `focusX/Y/Z`. Plus de `Vector3.new` idle 60 Hz.
- **Hover 60 Hz :** `previewOwnerAt` / `previewBuildingAt` module (V53).
- **Spawn clic :** terre libre + `isSpawnIsolated`. Snap `r=6` seulement si la tuile cliquée est **occupée**.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `GameState` ne require pas `Buildings` / `Research` / `Types`.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–18) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.
- **PR #157 :** Size rayon V76 intact. Banc apercu leftover V76 `rawequal(Size)` ville/bunker + leftover V75 hauteurs `+0.42/+0.38`. Rien à revert.

---

## Specs worker (reste)

Ne pas merger feel `5655`/`396d` ni hardening `e291`/`0744` sur cette branche sans rebase. Porter **une** recette à la fois. Feel N129 (footprint hauteur **0.4**, **pas** de pulse) ≠ visual V75/V76/V77 — ne pas merger.

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

### ISSUE-V78 — Overlay LaunchWake `CFrame.Angles` à l’apparition d’un navire

**Problème.** V77 ferme le hover 60 Hz si tuile+statut inchangés. Reste, à **chaque spawn navire** (`trackUnit`, pas missile) :

```
wake.CFrame = CFrame.new(origin.X, OCEAN_LEVEL + 0.12, origin.Z) * CFrame.Angles(0, 0, math.rad(90))
```

Rotation constante (cylindre plat) — même constante que V75 `footprintRot`. Feel N130 a déjà cuit `fromEulerAnglesYXZ` sur feel `5655` : **porter la recette, ne pas merger** (feel a `retreatTinted` / N56, Overlay visuel ne teinte pas la retraite). Distinct de V77 (Preview hover). Distinct de V75 (Preview, pas Overlay). Distinct de LandingSplash despawn (leftover V79 / feel N131, Y + 0.14). Distinct de DeliveryPulse (leftover V80 / feel N132, `route.to`). Distinct de `part.Size` tween (API, **ne pas** geler). Événement, pas 60 Hz interpolation — mais `CFrame.Angles` + `CFrame.new` à chaque apparition.

**20K CCU.** 8 clients × spawn bateau (vague + carriers). Pas d’autorité. Moins chaud que V77, prochaine constante cylindre à cuire.

**Faire.** Cuire `wakeRot = CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))` à `Overlay.new` (ou constante module). Hot path : `CFrame.new(origin.X, OCEAN_LEVEL + 0.12, origin.Z) * self.wakeRot`. Y + 0.12 **inchangé**. Tween Size/Transparency **inchangé**. `task.delay` destroy **inchangé**. Skip missiles **inchangé**. Ne **pas** porter LandingSplash ni DeliveryPulse dans le même commit.

**Contraintes.** Client-only. **V78 visual ≠ V77 (Preview hover) ≠ V75 (Preview rot).** Recette feel N130 — **ne pas merger** `5655`. Client 34/34 (check navires leftover V73 **doit rester vert**. Check apercu V77 CFrame `rawequal` + restore **doit rester vert**. Check pose/capture V72 **doit rester vert**). **Ne pas** éditer le serveur. **Ne pas** éditer `PlacementPreview.luau`. **Ne pas** éditer `UnitModels.luau`.

**Tester.** Check navires : wake spawn, `rawequal(wakeRot)` si cuit à `new`, Y = `OCEAN_LEVEL + 0.12`. Check apercu V77 **doit rester vert**. `./tests/run.sh`. Client 34/34.

**Fichiers.** `Overlay.luau` (`trackUnit` LaunchWake **seulement**). `tests/client.luau` commentaire leftover. `PlacementPreview.luau` **non**. `UnitModels.luau` **non**. `init.client.luau` **non**.

---

## Hors scope volontaire

- Merger feel `5655`/`396d` / hardening `e291`/`0744` sur #157.
- Feel N129 footprint hauteur 0.4 sans pulse — **ne pas** porter le Size visual V76 (pas de pulse feel).
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
- Overlay LaunchWake `CFrame.Angles` spawn navire — leftover V78 (recette feel N130, ne pas merger).
- Overlay LandingSplash `CFrame.Angles` despawn — leftover V79 (feel N131, Y + 0.14).
- Overlay DeliveryPulse `CFrame.Angles` — leftover V80 (feel N132, `route.to`).
- `CFrame.Angles` de construction (`addWake`, `Bow`, ailettes, `WorldRenderer` glint/tronc) — une fois, pas 60 Hz interpolation.
- Pulse livraison / wake / splash / explosion `CFrame.Angles` — événement (V78–V80).
- Transparency CityWindows / beacons / FactoryOutput / SiloWarning — leftover séparé (pas CFrame, animation `sin(time)`).
- Overlay `buildFactoryRoute` `CFrame.lookAt` (construction de voie / `segRot` / pose initiale camion) — une fois par route, pas 60 Hz.

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–58 inchangées (passe 59 = client-only).  
Invariants 5b–5f : index `buildingsBySlot` / `coolingBuildings` / `factoriesBySlot` / `portsByTile` / `navalBasesBySlot` vs hash, chaque 500 ticks.  
Client V75 : check « apercu de placement » — `footprintRot` / `pulseRot` cuits à `new`, `rawequal` après hover, hauteurs `+0.42/+0.38`. Leftover V51/V53 accrochage **doit rester vert**.  
Client V76 : même check apercu — `setKind(CITY)` Size `Y == TILE*3` (36), pulse `* 1.08` ; deux `update` → `rawequal(Size)` ; `setKind(DEFENSE)` Size `Y == DEFENSE_RADIUS*TILE*2` (144) ; hover ne perd pas le rayon bunker. Leftover V75 rot **doit rester vert**.  
Client V77 : même check apercu — deux `update(1000, "exact")` → `rawequal(CFrame)` ; `update(1000, "snap")` change Color, CFrame `rawequal` ; `update(nil)` Transparency == 1 puis restore < 1. Leftover V76 Size **doit rester vert**.  
Client V73 : check navires leftover **doit rester vert**.  
Client V72 : check pose/capture leftover **doit rester vert**.  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
