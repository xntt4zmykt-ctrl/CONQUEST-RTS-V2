# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 96)

Déclencheur : ouverture de la **PR #252** (`cursor/analyse-nocturne-du-codebase-5de8`) — PlacementPreview.destroy Placement rematch recycle (N186), specs N152 / N187.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-257b`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#252. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

Minimap `destroy` leftover `Minimap` : `Parent = nil` + push `panelFree` (**N187**, Frame, peek leftover **avant** `CreateEditableImage`, take `new()` une fois l’image assurée, View / Focus `FindFirstChild` reuse, `CreateEditableImage` **seulement** si pas de leftover View+image, image `Parent = view` même si `Content.fromObject` a réussi, skip `Theme.panel` au reuse, skip reconnect hit, skip `Parent == nil`, skip `setFocus` N123, skip PlacementPreview N186, skip WorldRenderer N185, skip Overlay, skip `init.client`). `init.client` rematch : `minimap:destroy()` **déjà** (après `preview:destroy()` N186 et `world:destroy()` N185). PlacementPreview `destroy` leftover `Placement` : `placeRootFree` (**N186**). WorldRenderer `destroy` leftover `ConquestWorld` : `worldFree` (**N185**). WorldRenderer `new` leftover `ConquestWorld` : `worldFree` (**N184**). PlacementPreview `setKind` : `ghostFree` (**N183**). FactionLabels `refresh` + `clear` : `labelFree` (**N182**). Overlay `clear` routes : `parkRoute` (**N181**). Overlay `syncFactoryRoutes` : `routeFree` (**N180**). Overlay `clear` bâtiments : `buildingFree` (**N179**). Overlay `applyBuildingDelta` : `buildingFree` (**N178**). Overlay `clear` unités : `shipFree` / `ogiveFree` (**N177**). Overlay despawn ogive : `ogiveFree` (**N176**). Overlay despawn navire : `shipFree` (**N175**). HUD `Dismiss` : `dismissFree` (**N174**). VictoryScreen `Value` : `valueFree` (**N173**). MainMenu miniature : `previewFree` (**N172**). MainMenu drapeau : `flagFree` (**N171**). HUD chat : `chatFree` (**N170**). Effects `clearActionPreview` (**N169**). Effects `clearSelection` (**N168**). HUD feed : `feedFree` (**N167**). BuildingModels BuildRing : `ringFree` (**N166**). Overlay Blast / BlastSmoke / Shockwave : `blastFree` / `smokeFree` / `shockFree` (**N165–N163**). PointLight reste **enfant** de Blast / EngineFlame. **`Overlay.luau` n’a plus aucun `:Destroy()`.** **`FactionLabels.luau` n’a plus aucun `:Destroy()`.** **`PlacementPreview.luau` n’a plus aucun `:Destroy()`.** **`WorldRenderer.luau` n’a plus aucun `:Destroy()`.** **`Minimap.luau` n’a plus aucun `:Destroy()`** (`destroy()` N187). UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). RadialMenu `destroy` leftover `self.veil:Destroy` encore (leftover **N188**, `destroy` **non appelé** au rematch).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #252 (passe 95) : claims vérifiés.** PlacementPreview.destroy leftover Parent=nil, `parkPlaceRoot(self.root)`, take `new()`, Footprint `FindFirstChild`, leftover Ghost → `ghostFree` N183, skip `Parent == nil`, skip `setKind` N183, skip WorldRenderer N185, skip Overlay, skip euler N129. `init.client` `preview:destroy()` **avant** `world:destroy()`. `PlacementPreview.luau` zéro `:Destroy()`. WorldRenderer N185 inchangé. Overlay N181 inchangé. N152 non livré (freeze Size=API = visual V74, interdit). Stub `Disconnect` inchangé. **N187 livré ici.** Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **branche `f71e`** passe 108 `clearSelection` Parent=nil — feel N168 **déjà**, **pas merger**. Visual **branche `a18e`** passe 107 selectTile reuse — feel N155 **déjà**, **pas merger**. Visual **branche `a971`** passe 106 HUD `feedFree` — feel N167 **déjà**, **pas merger**. Visual **branche `340e`** passe 105 BuildRing `ringFree` — feel N166 **déjà**, **pas merger**. Visual **branche `58fe`** passe 104 conquestPulse `pulseFree` — feel N157 **déjà**, **pas merger**. Visual **branche `d555`** passe 103 tileFlash `flashFree` — feel N156 **déjà**, **pas merger**. Visual **branche `3437`** passe 102 floatingText `textFree` — feel N158 **déjà**, **pas merger**. Visual **branche `8cc5`** V119 goldPopup `goldFree` — feel N159 **déjà**, **pas merger**. Visual **branche `73e0`** V118 LaunchWake `wakeFree` — feel N160 **déjà**, **pas merger**. Visual **branche `87c1`** V117 LandingSplash `splashFree` — feel N161 **déjà**, **pas merger**. Visual **branche `eaa4`** V116 DeliveryPulse `deliveryFree` — feel N162 **déjà**, **pas merger**. Visual **branche `057c`** V115 Shockwave `shockFree` — feel N163 **déjà**, **pas merger**. Visual **branche `fb11`** V114 BlastSmoke `smokeFree` — feel N164 **déjà**, **pas merger**. Visual **branche `1aab`** V113 Blast `blastFree` — feel N165 **déjà**, **pas merger**. Visual **branche `3ba1`** V112 Ground/Border recycle — feel N106 **déjà**, **pas merger**. Visual **branche `9922`** V111 flame `frame.X` — feel `sin(time * 18)` **sans** phase spatiale **encore**, **pas merger** (N152 freeze **toujours** interdit).

Cette passe a **livré N187** (ce que #252 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #252

| Claim #252 | Réalité à l’ouverture |
|---|---|
| PlacementPreview.destroy leftover Parent=nil (N186) | Oui. `parkPlaceRoot(self.root)`, take `new()`, Footprint `FindFirstChild`, leftover Ghost → `ghostFree` N183, skip `Parent == nil`, skip `setKind`, skip WorldRenderer, skip Overlay, skip euler N129. `init.client` `preview:destroy()` avant `world:destroy()`. `PlacementPreview.luau` zéro `:Destroy()`. WorldRenderer N185 inchangé. Overlay N181 inchangé. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N187 | **N187 livré ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #252, visuelles #253/`f71e` passe 108 clearSelection / `a18e` passe 107 selectTile / `a971` passe 106 HUD feed / `340e` passe 105 BuildRing / `58fe` passe 104 conquestPulse / `d555` passe 103 tileFlash / `3437` V120 floatingText / `8cc5` V119 goldPopup / `73e0` V118 LaunchWake / `87c1` V117 LandingSplash / `eaa4` V116 DeliveryPulse / `057c` V115 Shockwave / `fb11` V114 BlastSmoke / `1aab` V113 Blast / `3ba1` V112 Ground/Border / `9922` V111 flame. **#252 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `f71e` / `a18e` / `a971` / `340e` / `58fe` / `d555` / `3437` / `8cc5` / `73e0` / `87c1` / `eaa4` / `057c` / `fb11` / `1aab` / `3ba1` / `9922` ni hardening `41e2` / `93f6` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N187 est cosmétique pose (teardown Frame rematch). Risques documentés, non corrigés ici (hors N187) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip `rng > 0.12` seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. Aucun bug clair sûr hors N187. Overlay explosion n’a plus de `Destroy`. Overlay despawn ogive **poolé**. Overlay despawn navire delay **poolé**. Overlay `clear` unités live **poolé**. Overlay `applyBuildingDelta` destroy/rebuild **poolé**. Overlay `clear` bâtiments **poolé**. Overlay `syncFactoryRoutes` **poolé**. Overlay `clear` routes **poolé**. FactionLabels `refresh`/`clear` **poolé**. PlacementPreview `setKind` Ghost **poolé**. WorldRenderer.new ConquestWorld **poolé**. WorldRenderer.destroy ConquestWorld **poolé**. PlacementPreview.destroy Placement **poolé**. Minimap.destroy panel **poolé**. UnitModels flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze — **non livré**). RadialMenu.destroy veil Destroy encore (leftover **N188**).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N187 du rapport #252. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Minimap.destroy leftover `panel:Destroy` rematch (N187) | `Minimap.luau` (`destroy` → `parkPanel(self.panel)`, `new()` peek leftover **avant** `CreateEditableImage`, take `panelFree` une fois l’image assurée, View / Focus `FindFirstChild` reuse, image `Parent = view` même si `Content.fromObject` a réussi, skip `Theme.panel` au reuse, skip reconnect hit, skip `Parent == nil`, skip `setFocus` N123, skip PlacementPreview, skip WorldRenderer, skip Overlay, skip euler, skip `init.client`), `tests/client.luau` (check « minimap » leftover N187 commentaire **sans** extra `new()` ; **garder** leftover N123 + `destroy()` existant) | Leftover N186. Rematch `init.client` `minimap:destroy()` **déjà** puis `Minimap.new` × `Destroy` du Frame (View + EditableImage 256×160 + Focus + hit) → `Theme.panel` + `CreateEditableImage`. 8 clients. `CreateEditableImage` est l’alloc la plus chère du HUD. Pas d’autorité. **Skip Parent nil** sinon double-push. **Take `new()` obligatoire** (park sans take = fuite). **Peek avant Create** (fail Create sans take = candidate reste dans `panelFree`). **`CreateEditableImage` seulement si pas de leftover View+image**. **Parent image→view obligatoire** sinon leftover View sans enfant → second Create = fuite GPU. **Pas Theme.panel au reuse**. **Pas setFocus** (N123). **Pas PlacementPreview** (N186). **Pas WorldRenderer** (N185). **Pas Overlay**. **Pas `init.client`**. Cosmétique. Flame leftover N152 **alors**. RadialMenu.destroy leftover N188 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), RadialMenu.destroy veil Destroy (**N188**), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, PlacementPreview Size rayon (visual V76, feel Size = API), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline** **et** N160 free-list, **pas merger**), visual V118 LaunchWake (feel N160 **déjà**, **pas merger** `73e0`), visual V116 DeliveryPulse (feel N162 **déjà**, **pas merger** `eaa4`), visual V123 BuildRing (feel N166 **déjà**, **pas merger** `340e`), visual V124 HUD feed (feel N167 **déjà**, **pas merger** `a971`), visual passe 108 clearSelection (feel N168 **déjà**, **pas merger** `f71e`), tribus `humanTargetProtected`. PlacementPreview.destroy N186 **inchangé**. WorldRenderer.new N184 **inchangé**. WorldRenderer.destroy N185 **inchangé**. PlacementPreview `setKind` N183 **inchangé**. FactionLabels N182 **inchangé**. Overlay `clear` routes N181 **inchangé**. Overlay `syncFactoryRoutes` N180 **inchangé**. Overlay `clear` bâtiments N179 **inchangé**. Overlay `applyBuildingDelta` N178 **inchangé**. Overlay `clear` unités N177 **inchangé**. Flame **non**. Blast **non**. BlastSmoke **non**. Shockwave **non**. DeliveryPulse **non**. `routePart` **non**. Dismiss `table.remove(index)` **non**. HUD `chatFree` **inchangé**. HUD `feedFree` **inchangé**. HUD `dismissFree` **inchangé**. `shipFree` N175 despawn delay **inchangé**. `ogiveFree` N176 despawn immédiat **inchangé**. `previewTile` N154 skip **inchangé**. `clearSelection` N168 **inchangé**. `clearActionPreview` N169 **inchangé**. `refreshChatSheet` N170 **inchangé**. `drawFlag` N171 **inchangé**. `drawTerrainPreview` N172 **inchangé**. VictoryScreen `Value` N173 **inchangé**. HUD `Dismiss` N174 **inchangé**. `splashFree` N161 **inchangé**. `wakeFree` N160 **inchangé**. Recapture same kind+level **recolor inchangée**. `takeBuilding` / `poseBuilding` **inchangés**. `segRot` N115 **inchangé**. `truckModel.Parent = nil` N162 **conservé**. `takeRoute` / `poseRoute` N180 **inchangés**. `surveyTerritories` N96 **inchangé**. `labelFree` N182 **inchangé**. Footprint euler N129 **inchangé**. `setKind` N183 **inchangé**. `ghostFree` N183 **inchangé**. `rebuildChunk` N106 **inchangé**. `takeWorld` / `parkWorldChildren` / `WorldRenderer.destroy` N184/N185 **inchangés**. `placeRootFree` / `parkPlaceRoot` / `init.client` `preview:destroy()` N186 **inchangés**. Overlay/Effects/labels/preview recréés **après** `new()` — inchangé. `init.client` `minimap:destroy()` **déjà**, **inchangé**. RadialMenu.destroy **inchangé**. `setFocus` N123 **inchangé**.

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
- Minimap.destroy leftover Frame poolé (**N187**, `panelFree`). PlacementPreview.destroy leftover Folder poolé (**N186**, `placeRootFree`). WorldRenderer.destroy leftover Folder poolé (**N185**, `worldFree` existant). WorldRenderer.new leftover Folder poolé (**N184**, `worldFree`). PlacementPreview `setKind` poolé (**N183**, `ghostFree`). FactionLabels `refresh`/`clear` poolé (**N182**, `labelFree`). Overlay `clear` routes poolé (**N181**, `routeFree` existant). Overlay `syncFactoryRoutes` poolé (**N180**, `routeFree`). Overlay `clear` bâtiments poolé (**N179**, `buildingFree` existant). Overlay `applyBuildingDelta` destroy/rebuild poolé (**N178**, `buildingFree`). Overlay `clear` unités live poolé (**N177**, `shipFree`/`ogiveFree` existants). Overlay despawn ogive immédiat poolé (**N176**, `ogiveFree`). Overlay despawn navire delay poolé (**N175**, `shipFree`). HUD `notify` delay `Dismiss` poolé (**N174**, `dismissFree`). VictoryScreen `show` `Value` poolé (**N173**, `valueFree`). MainMenu `drawTerrainPreview` poolé (**N172**, `previewFree`). MainMenu `drawFlag` poolé (**N171**, `flagFree`). HUD `refreshChatSheet` poolé (**N170**, `chatFree`). Effects `clearActionPreview` poolé (**N169**, un marqueur). Effects `clearSelection` poolé (**N168**, un marqueur). HUD `notify` free-list (**N167**). BuildingModels BuildRing free-list (**N166**). Overlay Blast sphère free-list (**N165**). Overlay BlastSmoke free-list (**N164**). Overlay Shockwave free-list (**N163**). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). RadialMenu.destroy leftover `self.veil:Destroy` encore (**N188**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N188)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N187** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N188** = leftover RadialMenu.destroy `self.veil:Destroy` rematch (`destroy` **non appelé** au rematch — `radial` unique `init.client`, **ne pas** l’ajouter, take `new()` **requis**, skip Minimap N187, skip PlacementPreview N186, skip WorldRenderer N185, ≠ visual). **N187** fermé ici.

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover RadialMenu.destroy `self.veil:Destroy` = **N188** (`Minimap.luau` **zéro** Destroy après N187 ; `veilFree` TextButton **pas** `panelFree` / `placeRootFree` / `ghostFree` / `worldFree`, skip `init.client` rematch, skip Overlay, skip Minimap, skip PlacementPreview). Visual passe 108 clearSelection **fermée** sur `f71e` (feel N168 **déjà** — ne pas merger). Visual V124 HUD feed **fermée** sur `a971` (feel N167 **déjà** — ne pas merger). Visual V123 BuildRing **fermée** sur `340e` (feel N166 **déjà** — ne pas merger). Ne pas merger visual `f71e` / `a18e` / `a971` / `340e` / `58fe` / `d555` / `3437` / `8cc5` / `73e0` / `87c1` / `eaa4` / `057c` / `fb11` / `1aab` / `3ba1` / `9922`.

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N187 (pools Overlay/Effects/BuildingModels/HUD/selection/preview/chat/drapeau/miniature/podium/Dismiss/navire/ogive/`clear` unités / `applyBuildingDelta` / `clear` bâtiments / `syncFactoryRoutes` / `Overlay.clear` routes / FactionLabels / PlacementPreview Ghost / WorldRenderer.new / WorldRenderer.destroy / PlacementPreview.destroy / Minimap.destroy **déjà**). Distinct de N151 (trail Transparency), de N163–N187 (pools Overlay explosion / BuildRing / HUD feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview` / `Value` / `Dismiss` / modèle navire / ogive / `Overlay.clear` / `applyBuildingDelta` / `syncFactoryRoutes` / FactionLabels / Ghost / ConquestWorld Folder / rematch destroy monde / rematch destroy Placement / rematch destroy Minimap), de N188 (RadialMenu.destroy rematch), de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**. Ne pas toucher trail. Ne pas toucher `BuildingModels`. Ne pas toucher Overlay. Ne pas toucher HUD. Ne pas toucher Effects. Ne pas toucher MainMenu. Ne pas toucher VictoryScreen. Ne pas toucher FactionLabels. Ne pas toucher PlacementPreview. Ne pas toucher WorldRenderer. Ne pas toucher Minimap. Ne pas toucher RadialMenu.

**Problème :** N187 ferme le pool rematch Frame Minimap. N188 reste ouvert (RadialMenu destroy rematch). N151 ferme le trail. N153–N186 ferment HUD préfixe / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview` / `Value` / `Dismiss` / modèle navire / ogive / `Overlay.clear` unités / `applyBuildingDelta` / `Overlay.clear` bâtiments / `syncFactoryRoutes` / `Overlay.clear` routes / FactionLabels / Ghost / ConquestWorld Folder / rematch destroy monde / rematch destroy Placement. Reste, **chaque frame** (`UnitModels.place`, 60 Hz, une Part `EngineFlame` par ogive) :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (plus de pulse Size, `c0ec` / PR #151). Visual V111 (`9922`) a ajouté `frame.X * 0.1` dans le sin — **ne pas porter**. Feel **garde** le pulse Z `sin(time * 18)` **sans** phase spatiale. Ne pas porter `c0ec` ni `9922`. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**. Role `"flame"` **inchangé**. Shape `Ball` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. Minimap.destroy **déjà** N187 — ne pas y revenir. PlacementPreview.destroy **déjà** N186. WorldRenderer.destroy **déjà** N185. WorldRenderer.new **déjà** N184. PlacementPreview **déjà** N183. FactionLabels **déjà** N182. Overlay `clear` routes **déjà** N181. Overlay `syncFactoryRoutes` **déjà** N180. Overlay `clear` bâtiments **déjà** N179. Overlay `applyBuildingDelta` **déjà** N178. Overlay `clear` unités **déjà** N177. Visual V74 freeze **interdit** (feel ≠ visual). **Passes 61–96 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse `1.8 + math.sin(time * 18) * 0.45`. **Ne pas** geler Size (visual V74 Option A, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)`. XY `0.62` / base `1.8` / freq `18` / amp `0.45` **inchangés**.

2. **Garder le pulse.** Ne **pas** poser Size = API. Ne **pas** porter V111 `frame.X`. Ne **pas** « fermer » trail / HUD / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview` / `Value` / `Dismiss` / modèle navire / ogive / `Overlay.clear` / `applyBuildingDelta` / `syncFactoryRoutes` / FactionLabels / Ghost / ConquestWorld Folder / rematch destroy monde / rematch destroy Placement / rematch destroy Minimap (N151–N187 déjà). Ne **pas** lire `piece.part.Size` (alloc). Ne pas porter visual. Après N187. `BuildingModels` **non**. Overlay **non**. HUD **non**. Effects **non**. MainMenu **non**. VictoryScreen **non**. FactionLabels **non**. PlacementPreview **non**. WorldRenderer **non**. Minimap **non**. RadialMenu **non**. `createMissile` construction **non** (taille initiale `Vector3.new(0.62, 0.62, 2.3)` inchangée).

3. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N188 seulement.** N152 reste alors ouvert (feel-diverged vs V74). Ne pas inventer un cache Size. Ne pas skip-si-inchangé (N2, pas ici).

4. Tests « navires, missiles et interpolation » leftover N151 trail **et** leftover N148 mesh **et** leftover N147 Fin **doivent rester verts**. Tests « ecran de victoire » leftover N173 `valueFree` reuse **doivent rester verts**. Tests « pose et capture » leftover N180 `routeFree` reuse **et** leftover N178 `buildingFree` reuse **doivent rester verts**. Tests « vagues de conquete » leftover N181 `clear` routes reuse **et** leftover N179 `clear` bâtiments reuse **et** leftover N177 `clear` unités reuse **et** leftover N176 `ogiveFree` reuse **et** leftover N175 `shipFree` reuse **et** leftover N174 `dismissFree` reuse **et** leftover N167 `feedFree` reuse **doivent rester verts**. Tests « etiquettes de faction » leftover N182 `labelFree` reuse **et** leftover N96 **doivent rester verts**. Tests « apercu de placement » leftover N186 commentaire **et** leftover N183 `ghostFree` reuse **et** leftover N129 **doivent rester verts**. Tests « construction du monde 3D » leftover N185 commentaire **et** leftover N184 `world.root.Name` **et** leftover N106 **doivent rester verts**. Tests « minimap » leftover N187 commentaire **et** leftover N123 setFocus **doivent rester verts**. Tests « selection de chaque nation » leftover N171 `flagFree` reuse **et** leftover N172 `previewFree` reuse **doivent rester verts**. Tests « messages rapides » leftover N170 `chatFree` reuse **doivent rester verts**. Tests « calques d'entites, effets et apercu » leftover N169 `clearActionPreview` reuse **et** leftover N168 `clearSelection` reuse **et** leftover N155 `rawequal` 2000→2001 **doivent rester verts**. Tests « menu radial » leftover N188 **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` flame **seulement**, **un** `elseif`) **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N152. Overlay **non**. FactionLabels **non**. PlacementPreview **non**. WorldRenderer **non**. Minimap **non**. RadialMenu **non**. **Ne pas** éditer le serveur. **Ne pas** toucher Shockwave ni BlastSmoke ni Blast sphère ni BuildRing ni HUD chat ni feed ni `Dismiss` ni `clearSelection` ni `clearActionPreview` ni `refreshChatSheet` ni `drawFlag` ni `drawTerrainPreview` ni VictoryScreen ni modèle navire ni ogive ni `Overlay.clear` ni `applyBuildingDelta` ni `syncFactoryRoutes` ni `labelFree` ni `ghostFree` ni `worldFree` ni `placeRootFree` ni `panelFree`.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ N151 (trail Z) ≠ visual V74 (freeze Size=API, ne pas merger) ≠ N163–N187 (pools Overlay/HUD/Effects/FactionLabels/Ghost/ConquestWorld/rematch monde/rematch Placement/rematch Minimap déjà) ≠ N188 (RadialMenu.destroy rematch) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N188 dans le même worker. Pulse Z **conservé** — ne pas figer à 1.8. Un `elseif` flame.

---

### ISSUE-N188 — RadialMenu.destroy leftover `self.veil:Destroy` rematch (feel)

**Priorité :** P3 alloc client RadialMenu. Leftover explicite après N187 (Minimap.destroy `panelFree` **déjà** ; `Minimap.luau` **zéro** `:Destroy()`). Distinct de N152 (UnitModels Size), de N187 (Minimap.destroy **déjà**), de N186 (PlacementPreview.destroy **déjà**), de N185 (WorldRenderer.destroy **déjà**), de N184 (WorldRenderer.new **déjà**). `RadialMenu.destroy` `self.veil:Destroy` **et** `RadialMenu.new` take. `init.client` : `radial = RadialMenu.new(screenGui)` **unique** (ligne ~354) — `radial:destroy()` **n’est pas appelé** au rematch. **Ne pas** l’ajouter. Ne pas toucher Minimap (N187). Ne pas toucher PlacementPreview (N186). Ne pas toucher `setKind` (N183). Ne pas toucher WorldRenderer (N185). Ne pas toucher Overlay. Ne pas toucher FactionLabels. Ne pas toucher HUD. Ne pas toucher VictoryScreen. Ne pas toucher MainMenu. Ne pas toucher UnitModels.place. Ne pas toucher Effects. Ne pas retoucher `panelFree`. Ne pas retoucher `placeRootFree`. Ne pas retoucher `ghostFree`. Ne pas retoucher `worldFree`. Ne pas retoucher `setFocus` N123. Ne pas retoucher `rebuildChunk` N106.

**Problème :** N187 ferme le pool rematch Frame Minimap. N152 reste ouvert (freeze interdit). `Minimap.luau` n’a plus de `Destroy`. `PlacementPreview.luau` n’a plus de `Destroy`. `WorldRenderer.luau` n’a plus de `Destroy`. Reste, **chaque `destroy()`** (`tests/client` n’appelle pas `destroy()` aujourd’hui ; la méthode existe et un futur teardown la frappera) :

```
function RadialMenu.destroy(self: RadialMenu)
	self.veil:Destroy()
end
```

et

```
local veil = Instance.new("TextButton")
veil.Name = "RadialMenu"
-- + Ring Frame + UIScale + Hub TextButton + petals (max(6, #BUILDABLE))
-- + veil.Activated + hub.Activated + petal.Activated (une fois)
```

`Destroy` du voile tue Ring / Hub / petals / connexions **et** `Instance.new` × (1 + 1 + 1 + N petals) à chaque `new()`. Distinct de leftover N152 (`Size = Vector3.new` flamme). Distinct de leftover N187 (`destroy()` Minimap **déjà**). Distinct de leftover N186 (`destroy()` Placement **déjà**). **Rematch** `init.client` : `radial` **unique**, **pas** de `radial:destroy()`. **Ne pas** ajouter `radial:destroy()` au rematch. **Ne pas** recréer `RadialMenu.new` au rematch.

**Piège liste :** nouvelle free-list module `veilFree` (TextButton, **pas** `panelFree` Frame, **pas** `placeRootFree` Folder, **pas** `ghostFree` Model, **pas** `worldFree`, **pas** `previewFree` MainMenu, **pas** `flagFree`). Stocker le **TextButton** `self.veil` — pas le Ring seul. Ne **pas** Destroy. Skip `Parent == nil`.

**Piège take :** **take dans `new()`**. `destroy()` parque seulement. Oubli = voile disparu / `Instance.new("TextButton")` de secours à chaque `new()`. **Si le seul patch est un park `destroy()` sans take `new()` : ne pas livrer N188. C’est une fuite.**

**Piège Parent nil :** skip si `self.veil.Parent == nil` (déjà parké). Double-push = voile dupliqué au take de `new()`.

**Piège Theme / Name :** ne **pas** rappeler `Theme.corner` / `Theme.stroke` au reuse (UICorner + UIStroke dupliqués). Name `RadialMenu` ; Parent `parent` ; Size `UDim2.fromScale(1, 1)` / BackgroundTransparency 1 / Text `""` / AutoButtonColor false / Visible false / ZIndex 20 **réécrits**. Pas `Theme.panel` (ce n’est pas un Frame Theme).

**Piège Activated :** leftover veil / hub / petals : **ne pas** reconnecter `Activated` si déjà connecté (double-fire close / page / action — le fichier commente déjà « connexion unique, posée une seule fois »). **Reconnecter un petale = le bug historique Batir→premier bâtiment**.

**Piège enfants :** **laisser** Ring / Hub / UIScale / petals sur le voile. `new()` : `FindFirstChild("Ring")` → reuse, sinon construction Frame **inchangée**. `FindFirstChild("Hub")` → reuse, sinon construction **inchangée**. Petals leftover : **ne pas** recréer la boucle `petal(ring)` si `#self.petals` leftover (réutiliser les boutons enfants). **Oubli de reuse Ring** = Frame dupliquée. **Park Ring dans `veilFree`** = mauvais type. **Vider `veilFree` au destroy** = fuite. **Recréer les petals malgré leftover** = double Activated.

**Piège init.client :** `radial` **unique**. `radial:destroy()` **absent** du rematch. **Ne pas** l’ajouter. Overlay/Effects/labels/preview/minimap recréés **après** `WorldRenderer.new` — inchangé. **Si le seul patch est un `radial:destroy()` dans `init.client` : ne pas livrer.**

**Piège tests existants :** check « menu radial » `RadialMenu.new(screenGui)` **sans** `destroy()` — **ne pas** appeler `destroy()` (volerait le voile). Leftover N188 = commentaire **sans** extra `destroy()` / **sans** extra `new()`. Check « minimap » leftover N187 / N123 — **garder**, **garder** `minimap:destroy()` existant, **sans** extra `Minimap.new`. Check « apercu de placement » leftover N186 / N183 / N129 — **garder**, **sans** `preview:destroy()`. Check « construction du monde 3D » leftover N185 / N184 / N106 / N112 / N114 — **garder**, **sans** `world:destroy()`. **Si un `menu:destroy()` ou un second `RadialMenu.new` casse le check : ne pas livrer.**

**Pourquoi 20K CCU :** leftover N187. `destroy()` × `Destroy` du voile RadialMenu (Ring + Hub + N petals + 1+1+N Activated) alors que `new()` peut take. 8 clients. Pas d’autorité (cosmétique menu). Minimap.destroy **déjà** N187 — ne pas y revenir. PlacementPreview.destroy **déjà** N186. WorldRenderer.destroy **déjà** N185. Overlay **déjà** N163–N181. FactionLabels **déjà** N182. **Oubli de skip Parent nil** = double-push. **Reconnecter Activated** = double-fire. **Si le seul patch est un merger visuel, un Destroy des free-lists, un `radial:destroy()` au rematch, un retouch Minimap, ou un park sans take : ne pas livrer.**

**Worker :**

1. Dans `RadialMenu.destroy` : **ne plus** `Destroy` `self.veil`. `Parent = nil` + push `veilFree` **module** (TextButton, pas `panelFree`), skip `Parent == nil`. Enfants **laissés**. Pas de delay.

2. Dans `RadialMenu.new` : take `veilFree` ; Name `RadialMenu` ; Parent `parent` ; Size / Transparency / Text / AutoButtonColor / Visible / ZIndex **réécrits**. Ring / Hub / petals leftover reuse, sinon construction inchangée. `Activated` **seulement** si pas de leftover. Minimap **inchangé**. PlacementPreview **inchangé**. WorldRenderer **inchangé**. Overlay **inchangé**. `init.client` **inchangé**.

3. **Garder le marqueur.** Ne **pas** fusionner avec `panelFree` / `placeRootFree` / `ghostFree` / `worldFree` / `previewFree` MainMenu. Ne **pas** ajouter `radial:destroy()` au rematch. Ne **pas** retoucher Minimap N187. Ne **pas** retoucher PlacementPreview N186. Ne **pas** retoucher WorldRenderer N184/N185. Ne **pas** retoucher Overlay N163–N181. Après N187. Flame Size **non** (N152). HUD **non**. Effects **non**. MainMenu **non**. VictoryScreen **non**. VisualDirector **non** (leftover N189, `effect()` Destroy class mismatch).

4. Tests « menu radial » leftover **doivent rester verts**. **Ne pas** `menu:destroy()`. **Ne pas** second `new()`. Tests « minimap » leftover N187 / N123 **doivent rester verts**. **Garder** `minimap:destroy()` en fin de check. Tests « apercu de placement » leftover N186 / N183 / N129 **doivent rester verts**. Tests « accrochage du placement » **doivent rester verts**. Tests « construction du monde 3D » leftover N185 / N184 / N106 / N112 / N114 **doivent rester verts**. Tests « etiquettes de faction » leftover N182 **doivent rester verts**. Tests « vagues de conquete » leftover N181 / N179 / N177 / N176 / N175 / N174 / N167 / N166 / N162 **doivent rester verts**. Tests « pose et capture » leftover N180 / N178 / N136 / N132 / N166 **doivent rester verts**. Tests « navires » leftover N176 / leftover N152 flame Size **doivent rester verts**. Tests « ecran de victoire » leftover N173 **doivent rester verts**. Tests « selection de chaque nation » leftover N171 / N172 **doivent rester verts**. Tests « messages rapides » leftover N170 **doivent rester verts**. Tests « calques » leftover N169 / N168 / N155 **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `RadialMenu.luau` (`destroy` leftover Destroy + `new()` take `veilFree`, pas Overlay, pas Minimap, pas PlacementPreview, pas WorldRenderer, pas `init.client`). `tests/client.luau` **seulement** le check « menu radial » (commentaire leftover N188, **sans** `destroy()`, **sans** extra `new()`). Overlay **non**. FactionLabels **non**. PlacementPreview **non**. WorldRenderer **non**. Minimap **non**. `init.client.luau` **non**. `HUD.luau` **non**. `VictoryScreen.luau` **non**. `MainMenu.luau` **non**. `Effects.luau` **non**. `UnitModels.luau` **non**. `BuildingModels.luau` **non**. `VisualDirector.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher flame Size ni Blast ni HUD chat ni `feedFree` ni `Dismiss` ni `clearSelection` ni `clearActionPreview` ni `flagFree` ni `previewFree` ni `valueFree` ni `splashFree` ni `wakeFree` ni `applyBuildingDelta` ni `syncFactoryRoutes` ni `Overlay.clear` ni `labelFree` ni `takeGhost` / `parkGhost` ni `placeRootFree` / `parkPlaceRoot` ni `takeWorld` / `parkWorldChildren` / `WorldRenderer.destroy` ni `panelFree` / `parkPanel`. **Ne pas** merger visual `f71e` (passe 108). **Ne pas** merger visual `a18e` (passe 107). **Ne pas** merger visual `a971` (passe 106). **Ne pas** merger visual `340e` (passe 105). **Ne pas** merger visual `58fe` (passe 104). **Ne pas** merger visual `d555` (passe 103). **Ne pas** merger visual `3437` (passe 102). **Ne pas** merger visual V119 (`8cc5`). **Ne pas** merger visual V118 (`73e0`). **Ne pas** merger visual V117 (`87c1`). **Ne pas** merger visual V116 (`eaa4`). **Ne pas** merger visual V115 (`057c`). **Ne pas** merger visual V114 (`fb11`). **Ne pas** merger visual V113 (`1aab`). **Ne pas** merger visual V112 (`3ba1`). **Ne pas** merger visual V111 (`9922`). **Ne pas** merger visual V69 setFocus.

**Contraintes :** pas de RemoteFunction. **N188 feel ≠ N187 (Minimap.destroy déjà) ≠ N186 (PlacementPreview.destroy déjà) ≠ N185 (WorldRenderer.destroy déjà) ≠ N184 (WorldRenderer.new déjà) ≠ N183 (`setKind` Ghost déjà) ≠ N152 (flame Size, ne pas freeze V74) ≠ visual passe 108 (clearSelection fermée `f71e`, ne pas merger) ≠ N2 (skip-si-inchangé replication) ≠ N189 (VisualDirector `effect()` Destroy class mismatch, alors).** Non réentrant. Ne pas fusionner avec N152 dans le même worker. **Pas Destroy** du voile. **Pas de parcours Overlay.** **Pas de parcours Minimap.** **Pas de parcours PlacementPreview.** **Pas de parcours WorldRenderer.** **Pas de parcours `init.client`.** **Skip Parent nil.** Push `veilFree` **nouveau** (TextButton). Enfants **laissés**. Take `new()` **obligatoire**. `Activated` **seulement** si pas de leftover. **Si un park sans take, un `radial:destroy()` au rematch, un Destroy des free-lists, un retouch Minimap, ou un `menu:destroy()` dans le banc est le seul patch : ne pas livrer N188.** **Si Ring `Instance.new` malgré `FindFirstChild` : ne pas livrer N188.** **Si reconnecter Activated leftover : ne pas livrer N188.**

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; Minimap.destroy rematch → **N187 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; Minimap.destroy rematch Destroy → **N187** ; Overlay explosion + chantier + fil clos ; RadialMenu.destroy rematch Destroy = **N188**) |
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
| N34–N151, N153–N187 | (voir rapport #252) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–96) |
| N188 | RadialMenu.destroy leftover `self.veil:Destroy` rematch | P3 | **nouveau livrable** (`veilFree` TextButton, take `new()`, `init.client` `radial:destroy()` **absent** — **ne pas** l’ajouter, skip Minimap N187, skip PlacementPreview N186, skip WorldRenderer N185) |
| N189 | VisualDirector `effect()` leftover `existing:Destroy` class mismatch | P3 | alors (après N188 ; `FindFirstChild` reuse **déjà** si class match ; Destroy seulement class mismatch + Clouds) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 / #169 / #171 / #173 / #176 / #178 / #181 / #183 / #185 / #187 / #189 / #191 / #193 / #195 / #197 / #200 / #202 / #204 / #206 / #208 / #210 / #213 / #214 / #216 / #219 / #221 / #223 / #225 / #227 / #229 / #232 / #234 / #236 / #238 / #240 / #242 / #244 / #246 / #248 / #250 / #252 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N187 `panelFree` rematch) |

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

Client : **35/35 OK** — dont `selection de chaque nation et de chaque mode` leftover N171 `flagFree` + leftover N172 `previewFree` ; `fil de notifications sature` leftover N153 / leftover N167 commentaire **sans** flush + leftover N174 **sans** flush ; `messages rapides` leftover N170 `chatFree` ; `calques d'entites, effets et apercu` leftover N155 / leftover N168 / leftover N169 ; `pose et capture de chaque type de batiment` leftover N180 `routeFree` snapshot factory→city + kind=0 Parent nil + reuse Parent `overlay.root` **ou** free-list puis park usine / leftover N178 `buildingFree` snapshot CITY L3 + reuse Parent `overlay.root` **ou** free-list / leftover N136 / leftover N132 / leftover N166 commentaire **sans** flush ; `navires, missiles et interpolation` leftover N151 trail / leftover N152 flame Size / leftover N160 wake **sans** flush / leftover N161 splash **sans** flush / leftover N175 commentaire **sans** flush / leftover N176 park immédiat snapshot Parent nil **sans** flush, skip retraite id=1 N56, extra missile `rawequal` **avant** despawn ; `vagues de conquete` N181 `overlay:clear()` snapshot voie N162 Parent nil + `routeFree`, N179 snapshot CITY N162 Parent nil + `buildingFree` Kind CITY, N177 spawn id=77/66 + reuse id=55/44 `rawequal` Parent `overlay.root` **ou** free-list, PointLight enfant, N176 `ogiveFree` reuse / N175 `shipFree` reuse / N174 `dismissFree` reuse / N167 `feedFree` reuse / leftover N166 `BuildRing` reuse / leftover N165 `Blast` reuse / leftover N164 `BlastSmoke` reuse / leftover N163 `Shockwave` reuse / leftover N162 `DeliveryPulse` reuse / leftover N161 `LandingSplash` reuse / leftover N160 `LaunchWake` reuse ; `etiquettes de faction` leftover N182 snapshot ancre slot 1 avant `refresh(emptied)` + Parent nil + `labelFree` + restore `refresh(owner)` reuse Parent `labels.root` **ou** free-list + leftover N96 carte neutre + `clear()` sans vider `labelFree` ; `apercu de placement pour chaque batiment` leftover N186 commentaire **sans** `destroy()` + leftover N183 snapshot Ghost CITY avant `hide()` + Parent nil + `ghostFree` + restore `setKind(CITY)` reuse Parent `preview.root` **ou** free-list + leftover N129 euler + boucle `BUILDABLE` ; `construction du monde 3D` leftover N184 `world.root.Name == "ConquestWorld"` **sans** second `new()` + leftover N185 commentaire **sans** `destroy()` + leftover N106 `partCount` + leftover N112 `dirtyHead` + leftover N114 compact ; `ecran de victoire` leftover N173 `valueFree` ; `minimap` leftover N187 commentaire **sans** extra `new()` + leftover N123 setFocus + `destroy()` existant. Serveur **non** touché cette passe. `UnitModels.luau` **non** touché. Overlay **non** touché. FactionLabels **non** touché. WorldRenderer **non** touché. PlacementPreview **non** touché. HUD **non** touché. BuildingModels **non** touché. Effects **non** touché. MainMenu **non** touché. VictoryScreen **non** touché. RadialMenu **non** touché. `init.client` **non** touché. Pulse flamme Size **inchangé** (N152). RadialMenu.destroy veil Destroy **inchangé** (N188). Minimap.destroy rematch Frame **poolé**. PlacementPreview.destroy rematch Folder **poolé**. WorldRenderer.destroy rematch Folder **poolé**. WorldRenderer.new leftover Folder **poolé**. PlacementPreview `setKind` **poolé**. FactionLabels `refresh`/`clear` **poolé**. Overlay `clear` routes **poolé**. Overlay `syncFactoryRoutes` **poolé**. Overlay `clear` bâtiments **poolé**. Overlay `applyBuildingDelta` destroy/rebuild **poolé**. Overlay `clear` unités live **poolé**. Overlay despawn ogive immédiat **poolé**. Overlay despawn navire delay **poolé**. HUD `Dismiss` delay **poolé**. VictoryScreen `Value` **poolé**. MainMenu `drawTerrainPreview` **poolé**. MainMenu `drawFlag` **poolé**. HUD `refreshChatSheet` **poolé**. Stub `Disconnect` **inchangé**. `Overlay.luau` **zéro** `:Destroy()`. `FactionLabels.luau` **zéro** `:Destroy()`. `PlacementPreview.luau` **zéro** `:Destroy()`. `WorldRenderer.luau` **zéro** `:Destroy()`. `Minimap.luau` **zéro** `:Destroy()`.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass96.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N187 est un recycle Frame Minimap rematch vérifié par le banc headless (`minimap` leftover N123 `setFocus` inchangé, `destroy()` existant **gardé**, **sans** extra `new()`). Pulse flamme Size **inchangé** (N152). RadialMenu.destroy veil Destroy **inchangé** (N188).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N187 n’ajoute **pas** de require (`parkPanel` local). Intro continue de `require` MainMenu pour `drawFlag` (déjà). N152 restera dans `UnitModels.place` flame. N188 restera dans `RadialMenu.destroy` + `new()` take (pas `init.client`).

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Distinct trail N151. Distinct Overlay N163–N181 **déjà**. Distinct leftover N182 **déjà**. Distinct leftover N183 **déjà**. Distinct leftover N184 **déjà**. Distinct leftover N185 **déjà**. Distinct leftover N186 **déjà**. Distinct leftover N187 **déjà**. Distinct leftover N188. Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N187 : `Minimap.destroy` + `new()` take. **Pas** Destroy du Frame. Free-list `panelFree` (Frame, pas `placeRootFree`). Peek leftover **avant** Create. Take Frame une fois l’image assurée. View/Focus `FindFirstChild`. `CreateEditableImage` **seulement** si pas de leftover View+image. Image `Parent = view` même si `Content.fromObject` a réussi. Skip `Theme.panel` au reuse. Skip reconnect hit. Skip `Parent == nil`. Skip `setFocus` N123. Skip PlacementPreview N186. Skip WorldRenderer N185. Skip Overlay. Skip `init.client` (`minimap:destroy()` **déjà**). Distinct visual V69 (setFocus, ne pas merger). **Ne pas** casser N186 ni N185 ni N183 ni N123. **Ne pas** second `Minimap.new` dans le banc. **Ne pas** vider `panelFree`. **Si park sans take : ne pas livrer.** **Si Theme.panel au reuse : ne pas livrer.** **Si second CreateEditableImage au reuse : ne pas livrer.**

Piège N188 (à venir) : `RadialMenu.destroy` + `new()` take. **Pas** Destroy du voile. Free-list `veilFree` (TextButton, pas `panelFree`). Take TextButton. Ring/Hub `FindFirstChild`. `Activated` **seulement** si pas de leftover. Skip `Parent == nil`. Skip `init.client` (`radial:destroy()` **absent** — **ne pas** l’ajouter). Skip Minimap N187. Skip PlacementPreview N186. Skip WorldRenderer N185. Skip Overlay. **Ne pas** casser N187 ni N186 ni N123. **Ne pas** `menu:destroy()` dans le banc. **Ne pas** vider `veilFree`. **Si park sans take : ne pas livrer.** **Si reconnecter Activated leftover : ne pas livrer.**
