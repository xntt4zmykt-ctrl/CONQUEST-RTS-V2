# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 94)

Déclencheur : ouverture de la **PR #248** (`cursor/analyse-nocturne-du-codebase-1834`) — WorldRenderer.new ConquestWorld recycle (N184), specs N152 / N185.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-77d3`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#248. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

WorldRenderer `destroy` leftover `ConquestWorld` : `Parent = nil` + push `worldFree` existant (**N185**, Folder, skip take, skip park enfants, skip `Parent == nil`, skip `new()` N184, skip PlacementPreview, skip Overlay, skip `rebuildChunk` N106, skip `init.client`). WorldRenderer `new` leftover `ConquestWorld` : `Parent = nil` + push `worldFree` (**N184**, Folder, take n’importe quel Folder, Name `ConquestWorld`, Parent `Workspace`, park enfants **avant** `buildOcean`, Ground/Border → N106 `chunkGround`/`chunkBorder` existants, sinon `worldChildFree`, skip `Parent == nil`, skip PlacementPreview, skip Overlay, skip `rebuildChunk`). PlacementPreview `setKind` : `ghostFree` (**N183**). FactionLabels `refresh` + `clear` : `labelFree` (**N182**). Overlay `clear` routes : `parkRoute` (**N181**). Overlay `syncFactoryRoutes` : `routeFree` (**N180**). Overlay `clear` bâtiments : `buildingFree` (**N179**). Overlay `applyBuildingDelta` : `buildingFree` (**N178**). Overlay `clear` unités : `shipFree` / `ogiveFree` (**N177**). Overlay despawn ogive : `ogiveFree` (**N176**). Overlay despawn navire : `shipFree` (**N175**). HUD `Dismiss` : `dismissFree` (**N174**). VictoryScreen `Value` : `valueFree` (**N173**). MainMenu miniature : `previewFree` (**N172**). MainMenu drapeau : `flagFree` (**N171**). HUD chat : `chatFree` (**N170**). Effects `clearActionPreview` (**N169**). Effects `clearSelection` (**N168**). HUD feed : `feedFree` (**N167**). BuildingModels BuildRing : `ringFree` (**N166**). Overlay Blast / BlastSmoke / Shockwave : `blastFree` / `smokeFree` / `shockFree` (**N165–N163**). PointLight reste **enfant** de Blast / EngineFlame. **`Overlay.luau` n’a plus aucun `:Destroy()`.** **`FactionLabels.luau` n’a plus aucun `:Destroy()`.** **`PlacementPreview.setKind` n’a plus aucun `:Destroy()`** (`destroy()` `self.root:Destroy` **conservé**, leftover **N186**). **`WorldRenderer.luau` n’a plus aucun `:Destroy()`** (`new()` N184 + `destroy()` N185). UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #248 (passe 93) : claims vérifiés.** WorldRenderer.new leftover Parent=nil, `parkWorld`/`takeWorld`/`parkWorldChildren` hoistés, take n’importe quel Folder, Name `ConquestWorld`, Parent `Workspace`, park enfants **avant** `buildOcean`, Ground/Border → N106, sinon `worldChildFree`, skip `Parent == nil`, skip `destroy()`, skip PlacementPreview, skip Overlay, skip `rebuildChunk`. Check construction leftover N184 `world.root.Name == "ConquestWorld"` **sans** second `new()`. `WorldRenderer.new` zéro `:Destroy()`. PlacementPreview N183 inchangé. Overlay N181 inchangé. N152 non livré (freeze Size=API = visual V74, interdit). Stub `Disconnect` inchangé. **N185 livré ici.** Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **branche `a971`** passe 106 HUD `feedFree` — feel N167 **déjà**, **pas merger**. Visual **branche `340e`** passe 105 BuildRing `ringFree` — feel N166 **déjà**, **pas merger**. Visual **branche `58fe`** passe 104 conquestPulse `pulseFree` — feel N157 **déjà**, **pas merger**. Visual **branche `d555`** passe 103 tileFlash `flashFree` — feel N156 **déjà**, **pas merger**. Visual **branche `3437`** passe 102 floatingText `textFree` — feel N158 **déjà**, **pas merger**. Visual **branche `8cc5`** V119 goldPopup `goldFree` — feel N159 **déjà**, **pas merger**. Visual **branche `73e0`** V118 LaunchWake `wakeFree` — feel N160 **déjà**, **pas merger**. Visual **branche `87c1`** V117 LandingSplash `splashFree` — feel N161 **déjà**, **pas merger**. Visual **branche `eaa4`** V116 DeliveryPulse `deliveryFree` — feel N162 **déjà**, **pas merger**. Visual **branche `057c`** V115 Shockwave `shockFree` — feel N163 **déjà**, **pas merger**. Visual **branche `fb11`** V114 BlastSmoke `smokeFree` — feel N164 **déjà**, **pas merger**. Visual **branche `1aab`** V113 Blast `blastFree` — feel N165 **déjà**, **pas merger**. Visual **branche `3ba1`** V112 Ground/Border recycle — feel N106 **déjà**, **pas merger**. Visual **branche `9922`** V111 flame `frame.X` — feel `sin(time * 18)` **sans** phase spatiale **encore**, **pas merger** (N152 freeze **toujours** interdit).

Cette passe a **livré N185** (ce que #248 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #248

| Claim #248 | Réalité à l’ouverture |
|---|---|
| WorldRenderer.new leftover Parent=nil (N184) | Oui. `parkWorld`/`takeWorld`/`parkWorldChildren` hoistés, take n’importe quel Folder, Name `ConquestWorld`, Parent Workspace, park enfants **avant** `buildOcean`, Ground/Border → N106, sinon `worldChildFree`, skip `Parent == nil`, skip `destroy()`, skip PlacementPreview, skip Overlay, skip `rebuildChunk`. Check construction leftover N184 `Name == "ConquestWorld"` **sans** second `new()`. `WorldRenderer.new` zéro `:Destroy()`. PlacementPreview N183 inchangé. Overlay N181 inchangé. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N185 | **N185 livré ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #248, visuelles #245/`340e` passe 105 BuildRing / `58fe` passe 104 conquestPulse / `d555` passe 103 tileFlash / `3437` V120 floatingText / `8cc5` V119 goldPopup / `73e0` V118 LaunchWake / `87c1` V117 LandingSplash / `eaa4` V116 DeliveryPulse / `057c` V115 Shockwave / `fb11` V114 BlastSmoke / `1aab` V113 Blast / `3ba1` V112 Ground/Border / `9922` V111 flame. **#248 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `a971` / `340e` / `58fe` / `d555` / `3437` / `8cc5` / `73e0` / `87c1` / `eaa4` / `057c` / `fb11` / `1aab` / `3ba1` / `9922` ni hardening `41e2` / `93f6` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N185 est cosmétique monde (teardown Folder rematch). Risques documentés, non corrigés ici (hors N185) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip `rng > 0.12` seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. Aucun bug clair sûr hors N185. Overlay explosion n’a plus de `Destroy`. Overlay despawn ogive **poolé**. Overlay despawn navire delay **poolé**. Overlay `clear` unités live **poolé**. Overlay `applyBuildingDelta` destroy/rebuild **poolé**. Overlay `clear` bâtiments **poolé**. Overlay `syncFactoryRoutes` **poolé**. Overlay `clear` routes **poolé**. FactionLabels `refresh`/`clear` **poolé**. PlacementPreview Ghost **poolé**. WorldRenderer.new ConquestWorld **poolé**. WorldRenderer.destroy ConquestWorld **poolé**. UnitModels flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze — **non livré**). PlacementPreview.destroy `self.root:Destroy` encore (leftover **N186**).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N185 du rapport #248. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| WorldRenderer.destroy leftover `ConquestWorld:Destroy` rematch (N185) | `WorldRenderer.luau` (`destroy` → `parkWorld(self.root)` existant, skip `Parent == nil`, enfants **laissés**, skip take, skip `new()`, skip PlacementPreview, skip Overlay, skip `rebuildChunk` N106, skip `init.client`), `tests/client.luau` (check « construction du monde 3D » leftover N185 commentaire **sans** `destroy()` ; garder leftover N184 `Name` + leftover N106 `partCount` + leftover N112 `dirtyHead` + leftover N114 compact) | Leftover N184. Rematch `init.client` `world:destroy()` **puis** `WorldRenderer.new(seed)` × `Destroy` du Folder monde (Ocean + décor + chunks Ground/Border déjà poolés N106) alors que `new()` take + `parkWorldChildren` recyclent déjà. 8 clients. Pas d’autorité. **Skip Parent nil** sinon double-push. **Pas take** dans `destroy()` (`new()` déjà). **Pas park enfants** (`new()` déjà). **Pas Destroy** des free-lists. Skip `new()` (N184). Skip PlacementPreview. Skip Overlay. Skip `rebuildChunk` N106. Skip `init.client`. Cosmétique. Flame leftover N152 **alors**. PlacementPreview.destroy leftover N186 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), PlacementPreview.destroy Placement Destroy (**N186**), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, PlacementPreview Size rayon (visual V76, feel Size = API), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline** **et** N160 free-list, **pas merger**), visual V118 LaunchWake (feel N160 **déjà**, **pas merger** `73e0`), visual V116 DeliveryPulse (feel N162 **déjà**, **pas merger** `eaa4`), visual V123 BuildRing (feel N166 **déjà**, **pas merger** `340e`), tribus `humanTargetProtected`. WorldRenderer.new N184 **inchangé** (hors commentaire `destroy()`). PlacementPreview N183 **inchangé**. FactionLabels N182 **inchangé**. Overlay `clear` routes N181 **inchangé**. Overlay `syncFactoryRoutes` N180 **inchangé**. Overlay `clear` bâtiments N179 **inchangé**. Overlay `applyBuildingDelta` N178 **inchangé**. Overlay `clear` unités N177 **inchangé**. Overlay `clear` routes **poolé**. Flame **non**. Blast **non**. BlastSmoke **non**. Shockwave **non**. DeliveryPulse **non**. `routePart` **non**. Dismiss `table.remove(index)` **non**. HUD `chatFree` **inchangé**. HUD `feedFree` **inchangé**. HUD `dismissFree` **inchangé**. `shipFree` N175 despawn delay **inchangé**. `ogiveFree` N176 despawn immédiat **inchangé**. `previewTile` N154 skip **inchangé**. `clearSelection` N168 **inchangé**. `clearActionPreview` N169 **inchangé**. `refreshChatSheet` N170 **inchangé**. `drawFlag` N171 **inchangé**. `drawTerrainPreview` N172 **inchangé**. VictoryScreen `Value` N173 **inchangé**. HUD `Dismiss` N174 **inchangé**. `splashFree` N161 **inchangé**. `wakeFree` N160 **inchangé**. Recapture same kind+level **recolor inchangée**. `takeBuilding` / `poseBuilding` **inchangés**. `segRot` N115 **inchangé**. `truckModel.Parent = nil` N162 **conservé**. `takeRoute` / `poseRoute` N180 **inchangés**. `surveyTerritories` N96 **inchangé**. `labelFree` N182 **inchangé**. Footprint euler N129 **inchangé**. `destroy()` PlacementPreview **inchangé**. `ghostFree` N183 **inchangé**. `rebuildChunk` N106 **inchangé**. `takeWorld` / `parkWorldChildren` N184 **inchangés**. `init.client` **inchangé**.

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
- WorldRenderer.destroy leftover Folder poolé (**N185**, `worldFree` existant). WorldRenderer.new leftover Folder poolé (**N184**, `worldFree`). PlacementPreview `setKind` poolé (**N183**, `ghostFree`). FactionLabels `refresh`/`clear` poolé (**N182**, `labelFree`). Overlay `clear` routes poolé (**N181**, `routeFree` existant). Overlay `syncFactoryRoutes` poolé (**N180**, `routeFree`). Overlay `clear` bâtiments poolé (**N179**, `buildingFree` existant). Overlay `applyBuildingDelta` destroy/rebuild poolé (**N178**, `buildingFree`). Overlay `clear` unités live poolé (**N177**, `shipFree`/`ogiveFree` existants). Overlay despawn ogive immédiat poolé (**N176**, `ogiveFree`). Overlay despawn navire delay poolé (**N175**, `shipFree`). HUD `notify` delay `Dismiss` poolé (**N174**, `dismissFree`). VictoryScreen `show` `Value` poolé (**N173**, `valueFree`). MainMenu `drawTerrainPreview` poolé (**N172**, `previewFree`). MainMenu `drawFlag` poolé (**N171**, `flagFree`). HUD `refreshChatSheet` poolé (**N170**, `chatFree`). Effects `clearActionPreview` poolé (**N169**, un marqueur). Effects `clearSelection` poolé (**N168**, un marqueur). HUD `notify` free-list (**N167**). BuildingModels BuildRing free-list (**N166**). Overlay Blast sphère free-list (**N165**). Overlay BlastSmoke free-list (**N164**). Overlay Shockwave free-list (**N163**). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). PlacementPreview.destroy leftover `self.root:Destroy` encore (**N186**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N186)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N185** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N186** = leftover PlacementPreview.destroy `self.root:Destroy` rematch (take `new()` **requis**, `init.client` `preview:destroy()` **avant** `world:destroy()`, skip WorldRenderer N185, skip `ghostFree` N183, ≠ visual V76). **N185** fermé ici.

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover PlacementPreview.destroy `self.root:Destroy` = **N186** (`WorldRenderer.destroy` **zéro** Destroy après N185 ; `placeRootFree` Folder **pas** `ghostFree` / `worldFree` / `previewFree` MainMenu, skip `setKind`, skip footprint euler N129, skip Overlay, skip FactionLabels, skip `WorldRenderer`, skip `rebuildChunk` N106). Visual V124 HUD feed **fermée** sur `a971` (feel N167 **déjà** — ne pas merger). Visual V123 BuildRing **fermée** sur `340e` (feel N166 **déjà** — ne pas merger). Visual V121 tileFlash **fermée** sur `d555` (feel N156 **déjà** — ne pas merger). Visual passe 102 floatingText **fermée** sur `3437` (feel N158 **déjà** — ne pas merger). Ne pas merger visual `a971` / `340e` / `58fe` / `d555` / `3437` / `8cc5` / `73e0` / `87c1` / `eaa4` / `057c` / `fb11` / `1aab` / `3ba1` / `9922`.

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N185 (pools Overlay/Effects/BuildingModels/HUD/selection/preview/chat/drapeau/miniature/podium/Dismiss/navire/ogive/`clear` unités / `applyBuildingDelta` / `clear` bâtiments / `syncFactoryRoutes` / `Overlay.clear` routes / FactionLabels / PlacementPreview Ghost / WorldRenderer.new / WorldRenderer.destroy **déjà**). Distinct de N151 (trail Transparency), de N163–N185 (pools Overlay explosion / BuildRing / HUD feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview` / `Value` / `Dismiss` / modèle navire / ogive / `Overlay.clear` / `applyBuildingDelta` / `syncFactoryRoutes` / FactionLabels / Ghost / ConquestWorld Folder / rematch destroy), de N186 (PlacementPreview.destroy rematch), de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**. Ne pas toucher trail. Ne pas toucher `BuildingModels`. Ne pas toucher Overlay. Ne pas toucher HUD. Ne pas toucher Effects. Ne pas toucher MainMenu. Ne pas toucher VictoryScreen. Ne pas toucher FactionLabels. Ne pas toucher PlacementPreview. Ne pas toucher WorldRenderer.

**Problème :** N185 ferme le pool rematch Folder monde. N186 reste ouvert (Placement destroy rematch). N151 ferme le trail. N153–N184 ferment HUD préfixe / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview` / `Value` / `Dismiss` / modèle navire / ogive / `Overlay.clear` unités / `applyBuildingDelta` / `Overlay.clear` bâtiments / `syncFactoryRoutes` / `Overlay.clear` routes / FactionLabels / Ghost / ConquestWorld Folder. Reste, **chaque frame** (`UnitModels.place`, 60 Hz, une Part `EngineFlame` par ogive) :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (plus de pulse Size, `c0ec` / PR #151). Visual V111 (`9922`) a ajouté `frame.X * 0.1` dans le sin — **ne pas porter**. Feel **garde** le pulse Z `sin(time * 18)` **sans** phase spatiale. Ne pas porter `c0ec` ni `9922`. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**. Role `"flame"` **inchangé**. Shape `Ball` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. WorldRenderer.destroy **déjà** N185 — ne pas y revenir. WorldRenderer.new **déjà** N184. PlacementPreview **déjà** N183. FactionLabels **déjà** N182. Overlay `clear` routes **déjà** N181. Overlay `syncFactoryRoutes` **déjà** N180. Overlay `clear` bâtiments **déjà** N179. Overlay `applyBuildingDelta` **déjà** N178. Overlay `clear` unités **déjà** N177. Visual V74 freeze **interdit** (feel ≠ visual). **Passes 61–94 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse `1.8 + math.sin(time * 18) * 0.45`. **Ne pas** geler Size (visual V74 Option A, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)`. XY `0.62` / base `1.8` / freq `18` / amp `0.45` **inchangés**.

2. **Garder le pulse.** Ne **pas** poser Size = API. Ne **pas** porter V111 `frame.X`. Ne **pas** « fermer » trail / HUD / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview` / `Value` / `Dismiss` / modèle navire / ogive / `Overlay.clear` / `applyBuildingDelta` / `syncFactoryRoutes` / FactionLabels / Ghost / ConquestWorld Folder / rematch destroy (N151–N185 déjà). Ne **pas** lire `piece.part.Size` (alloc). Ne pas porter visual. Après N185. `BuildingModels` **non**. Overlay **non**. HUD **non**. Effects **non**. MainMenu **non**. VictoryScreen **non**. FactionLabels **non**. PlacementPreview **non**. WorldRenderer **non**. `createMissile` construction **non** (taille initiale `Vector3.new(0.62, 0.62, 2.3)` inchangée).

3. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N186 seulement.** N152 reste alors ouvert (feel-diverged vs V74). Ne pas inventer un cache Size. Ne pas skip-si-inchangé (N2, pas ici).

4. Tests « navires, missiles et interpolation » leftover N151 trail **et** leftover N148 mesh **et** leftover N147 Fin **doivent rester verts**. Tests « ecran de victoire » leftover N173 `valueFree` reuse **doivent rester verts**. Tests « pose et capture » leftover N180 `routeFree` reuse **et** leftover N178 `buildingFree` reuse **doivent rester verts**. Tests « vagues de conquete » leftover N181 `clear` routes reuse **et** leftover N179 `clear` bâtiments reuse **et** leftover N177 `clear` unités reuse **et** leftover N176 `ogiveFree` reuse **et** leftover N175 `shipFree` reuse **et** leftover N174 `dismissFree` reuse **et** leftover N167 `feedFree` reuse **doivent rester verts**. Tests « etiquettes de faction » leftover N182 `labelFree` reuse **et** leftover N96 **doivent rester verts**. Tests « apercu de placement » leftover N183 `ghostFree` reuse **et** leftover N129 **doivent rester verts**. Tests « construction du monde 3D » leftover N185 commentaire **et** leftover N184 `world.root.Name` **et** leftover N106 **doivent rester verts**. Tests « selection de chaque nation » leftover N171 `flagFree` reuse **et** leftover N172 `previewFree` reuse **doivent rester verts**. Tests « messages rapides » leftover N170 `chatFree` reuse **doivent rester verts**. Tests « calques d'entites, effets et apercu » leftover N169 `clearActionPreview` reuse **et** leftover N168 `clearSelection` reuse **et** leftover N155 `rawequal` 2000→2001 **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` flame **seulement**, **un** `elseif`) **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N152. Overlay **non**. FactionLabels **non**. PlacementPreview **non**. WorldRenderer **non**. **Ne pas** éditer le serveur. **Ne pas** toucher Shockwave ni BlastSmoke ni Blast sphère ni BuildRing ni HUD chat ni feed ni `Dismiss` ni `clearSelection` ni `clearActionPreview` ni `refreshChatSheet` ni `drawFlag` ni `drawTerrainPreview` ni VictoryScreen ni modèle navire ni ogive ni `Overlay.clear` ni `applyBuildingDelta` ni `syncFactoryRoutes` ni `labelFree` ni `ghostFree` ni `worldFree`.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ N151 (trail Z) ≠ visual V74 (freeze Size=API, ne pas merger) ≠ N163–N185 (pools Overlay/HUD/Effects/FactionLabels/Ghost/ConquestWorld/rematch déjà) ≠ N186 (PlacementPreview.destroy rematch) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N186 dans le même worker. Pulse Z **conservé** — ne pas figer à 1.8. Un `elseif` flame.

---

### ISSUE-N186 — PlacementPreview.destroy leftover `self.root:Destroy` rematch (feel)

**Priorité :** P3 alloc client PlacementPreview. Leftover explicite après N185 (WorldRenderer.destroy `worldFree` **déjà** ; `WorldRenderer.luau` **zéro** `:Destroy()`). Distinct de N152 (UnitModels Size), de N185 (WorldRenderer.destroy **déjà**), de N184 (WorldRenderer.new **déjà**), de N183 (`setKind` Ghost **déjà**), de visual V76 (Size rayon — **ne pas merger**). `PlacementPreview.destroy` `self.root:Destroy` **et** `PlacementPreview.new` take **et** `init.client` `preview:destroy()` **avant** `world:destroy()`. Ne pas toucher WorldRenderer (N185). Ne pas toucher `setKind` (N183). Ne pas toucher footprint euler N129. Ne pas toucher Overlay. Ne pas toucher FactionLabels. Ne pas toucher HUD. Ne pas toucher VictoryScreen. Ne pas toucher MainMenu. Ne pas toucher UnitModels.place. Ne pas toucher Effects. Ne pas retoucher `ghostFree` take Kind. Ne pas retoucher `worldFree`. Ne pas retoucher `rebuildChunk` N106.

**Problème :** N185 ferme le pool rematch Folder monde. N152 reste ouvert (freeze interdit). `WorldRenderer.luau` n’a plus de `Destroy`. Reste, **chaque rematch** (`PlacementPreview.destroy` n’est **jamais** appelé aujourd’hui : `init.client` fait `world:destroy()` **puis** `PlacementPreview.new` ; après N185 le Folder `Placement` est enfant de `ConquestWorld` parké, `parkWorldChildren` le `Parent = nil` **sans** pool, puis `new()` fait `Instance.new("Folder")`) :

```
function PlacementPreview.destroy(self: PlacementPreview)
	self.root:Destroy()
end
```

et

```
local root = Instance.new("Folder")
root.Name = "Placement"
root.Parent = parent
```

`Destroy` du Folder tue Footprint + Ghosts **déjà** poolés N183. Sans câbler `preview:destroy()` **avant** `world:destroy()`, N185 `parkWorldChildren` avale `Placement` (branche else : nested → `worldChildFree`, Folder `Parent = nil` **sans** liste) → `Instance.new("Folder")` + `Instance.new("Part")` Footprint à chaque rematch. Distinct de leftover N152 (`Size = Vector3.new` flamme). Distinct de leftover N185 (`destroy()` monde **déjà**). Distinct de leftover N183 (`setKind` Ghost **déjà**). Distinct de leftover N129 (euler footprint). **Rematch** `init.client` : `if preview then preview:destroy() end` **avant** `if world then world:destroy() end` **requis** (sinon N185 avale le Folder). `PlacementPreview.new` **après** `WorldRenderer.new` **conservé**.

**Piège liste :** nouvelle free-list module `placeRootFree` (Folder, **pas** `ghostFree` Model, **pas** `worldFree`, **pas** `previewFree` MainMenu tuiles, **pas** `worldChildFree`). Stocker le **Folder** `self.root` — pas une Part. Ne **pas** Destroy. Skip `Parent == nil`.

**Piège take :** **take dans `new()`**. `destroy()` parque seulement. Oubli = Folder disparu / `Instance.new` de secours à chaque rematch. **Si le seul patch est un park `destroy()` sans take `new()` : ne pas livrer N186. C’est une fuite.**

**Piège Parent nil :** skip si `self.root.Parent == nil` (déjà parké). Double-push = Folder dupliqué au take de `new()`.

**Piège enfants :** **laisser** Footprint + Ghosts sur le Folder. `new()` : `FindFirstChild("Footprint")` → reuse, sinon `Instance.new("Part")` construction **inchangée**. Ghost leftover (`Name == "Ghost"` ou `GetAttribute("Kind")`) → push `self.ghostFree` **existant** (N183, per-instance, se repeuple au take). **Oubli de reuse Footprint** = Part dupliquée. **Park Footprint dans `ghostFree`** = take Kind casse. **Vider `ghostFree` au destroy** = N183 cassé.

**Piège setKind / hide :** ne **pas** y toucher. `parkGhost` / `takeGhost` **conservés** (N183). **Si le seul patch est un retouch `setKind` : ne pas livrer. C’est N183.**

**Piège WorldRenderer :** ne **pas** y toucher. `parkWorld` / `takeWorld` / `parkWorldChildren` / `destroy()` N185 **conservés**. **Ne pas** skip `Placement` dans `parkWorldChildren` (retouch N184). **Si le seul patch est un retouch WorldRenderer : ne pas livrer.**

**Piège init.client :** `if preview then preview:destroy() end` **avant** `world:destroy()`. Ne **pas** nil `preview` avant destroy. Ne **pas** skip `PlacementPreview.new` après `WorldRenderer.new`. Overlay/Effects/labels recréés **après** `new()` — inchangé. **Si le seul patch est un retouch `init.client` sans take `new()` : ne pas livrer.**

**Piège visual V76 :** ne **pas** merger Size rayon. Footprint Size = API **conservé**. Euler N129 **conservé**.

**Piège tests existants :** check « apercu de placement » leftover N183 snapshot Ghost + Parent nil + restore — **garder**. **Ne pas** appeler `preview:destroy()` — volerait `preview.root` aux checks accrochage. Leftover N186 = commentaire **sans** `destroy()`. Check « construction du monde 3D » leftover N185 / N184 / N106 / N112 / N114 — **garder**, **sans** `world:destroy()`. **Si un `preview:destroy()` casse accrochage : ne pas livrer.**

**Pourquoi 20K CCU :** leftover N185. Rematch × `Destroy` (ou fuite `parkWorldChildren`) du Folder Placement (Footprint + Ghosts déjà poolés N183) alors que `new()` peut take. 8 clients. Pas d’autorité (cosmétique pose). WorldRenderer.destroy **déjà** N185 — ne pas y revenir. Overlay **déjà** N163–N181. FactionLabels **déjà** N182. PlacementPreview `setKind` **déjà** N183. Visual V76 Size rayon **interdit**. **Oubli de skip Parent nil** = double-push. **Park enfants dans destroy() vers `ghostFree` module** = mauvais type. **`preview:destroy()` dans le banc apercu** = accrochage cassé. **Si le seul patch est un merger visuel, un Destroy des free-lists, un retouch WorldRenderer, un retouch `setKind`, ou un park sans take : ne pas livrer.**

**Worker :**

1. Dans `PlacementPreview.destroy` : **ne plus** `Destroy` `self.root`. `Parent = nil` + push `placeRootFree` **module** (Folder, pas `ghostFree`), skip `Parent == nil`. Enfants **laissés**. Pas de delay.

2. Dans `PlacementPreview.new` : take `placeRootFree` ; Name `Placement` ; Parent `parent`. Footprint `FindFirstChild("Footprint")` reuse, sinon construction inchangée. Ghost leftover → `self.ghostFree`. `setKind` **inchangé**. WorldRenderer **inchangé**. Overlay **inchangé**.

3. Dans `init.client` rematch **seulement** : `if preview then preview:destroy() end` **avant** `world:destroy()`. `PlacementPreview.new` **après** `WorldRenderer.new` **conservé**. Ne **pas** nil `preview` avant destroy.

4. **Garder le fantôme.** Ne **pas** fusionner avec `ghostFree` / `worldFree` / `previewFree` MainMenu. Ne **pas** retoucher `setKind` N183. Ne **pas** retoucher WorldRenderer N184/N185. Ne **pas** retoucher Overlay N163–N181. Après N185. Flame Size **non** (N152). HUD **non**. Effects **non**. MainMenu **non**. VictoryScreen **non**. VisualDirector **non**. Minimap **non** (leftover N187).

5. Tests « apercu de placement » leftover N183 / leftover N129 **doivent rester verts**. **Ne pas** appeler `preview:destroy()`. Tests « accrochage du placement » **doivent rester verts**. Tests « construction du monde 3D » leftover N185 / N184 / N106 / N112 / N114 **doivent rester verts**. Tests « etiquettes de faction » leftover N182 **doivent rester verts**. Tests « vagues de conquete » leftover N181 / N179 / N177 / N176 / N175 / N174 / N167 / N166 / N162 **doivent rester verts**. Tests « pose et capture » leftover N180 / N178 / N136 / N132 / N166 **doivent rester verts**. Tests « navires » leftover N176 / leftover N152 flame Size **doivent rester verts**. Tests « ecran de victoire » leftover N173 **doivent rester verts**. Tests « selection de chaque nation » leftover N171 / N172 **doivent rester verts**. Tests « messages rapides » leftover N170 **doivent rester verts**. Tests « calques » leftover N169 / N168 / N155 **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

6. Fichiers : `PlacementPreview.luau` (`destroy` leftover Destroy + `new()` take `placeRootFree`, pas `setKind`, pas footprint euler, pas Overlay, pas WorldRenderer). `init.client.luau` **seulement** `preview:destroy()` avant `world:destroy()`. `tests/client.luau` **seulement** le check « apercu de placement » (commentaire leftover N186, **garder** N183 / N129). Overlay **non**. FactionLabels **non**. WorldRenderer **non**. `HUD.luau` **non**. `VictoryScreen.luau` **non**. `MainMenu.luau` **non**. `Effects.luau` **non**. `UnitModels.luau` **non**. `BuildingModels.luau` **non**. `Minimap.luau` **non**. `VisualDirector.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher flame Size ni Blast ni HUD chat ni `feedFree` ni `Dismiss` ni `clearSelection` ni `clearActionPreview` ni `flagFree` ni `previewFree` ni `valueFree` ni `splashFree` ni `wakeFree` ni `applyBuildingDelta` ni `syncFactoryRoutes` ni `Overlay.clear` ni `labelFree` ni `takeGhost` / `parkGhost` ni `takeWorld` / `parkWorldChildren` / `WorldRenderer.destroy`. **Ne pas** merger visual `a971` (passe 106). **Ne pas** merger visual `340e` (passe 105). **Ne pas** merger visual `58fe` (passe 104). **Ne pas** merger visual `d555` (passe 103). **Ne pas** merger visual `3437` (passe 102). **Ne pas** merger visual V119 (`8cc5`). **Ne pas** merger visual V118 (`73e0`). **Ne pas** merger visual V117 (`87c1`). **Ne pas** merger visual V116 (`eaa4`). **Ne pas** merger visual V115 (`057c`). **Ne pas** merger visual V114 (`fb11`). **Ne pas** merger visual V113 (`1aab`). **Ne pas** merger visual V112 (`3ba1`). **Ne pas** merger visual V111 (`9922`). **Ne pas** merger visual V76 Size rayon.

**Contraintes :** pas de RemoteFunction. **N186 feel ≠ N185 (WorldRenderer.destroy déjà) ≠ N184 (WorldRenderer.new déjà) ≠ N183 (`setKind` Ghost déjà) ≠ N182 (FactionLabels déjà) ≠ N129 (euler footprint déjà) ≠ N152 (flame Size, ne pas freeze V74) ≠ visual V76 (Size rayon, ne pas merger) ≠ visual passe 105 (BuildRing fermée `340e`, ne pas merger) ≠ N2 (skip-si-inchangé replication) ≠ N187 (Minimap.destroy rematch, alors).** Non réentrant. Ne pas fusionner avec N152 dans le même worker. **Pas Destroy** du Folder rematch. **Pas de parcours Overlay.** **Pas de parcours WorldRenderer.** **Pas de parcours `setKind`.** **Skip Parent nil.** Push `placeRootFree` **nouveau** (Folder). Enfants **laissés**. Take `new()` **obligatoire**. `init.client` `preview:destroy()` **avant** `world:destroy()` **obligatoire**. N183 `ghostFree` **obligatoire** inchangé (sauf repeuplement leftover Ghost au take). N185 `worldFree` **obligatoire** inchangé. **Si un park sans take, un retouch WorldRenderer, un Destroy des free-lists, un retouch `setKind`, ou un `preview:destroy()` dans le banc est le seul patch : ne pas livrer N186.** **Si Footprint `Instance.new` malgré `FindFirstChild` : ne pas livrer N186.**

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; WorldRenderer.destroy rematch → **N185 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; WorldRenderer.destroy rematch Destroy → **N185** ; Overlay explosion + chantier + fil clos ; PlacementPreview.destroy rematch Destroy = **N186**) |
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
| N34–N151, N153–N185 | (voir rapport #248) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–94) |
| N186 | PlacementPreview.destroy leftover `self.root:Destroy` rematch | P3 | **nouveau livrable** (`placeRootFree` Folder, take `new()`, `init.client` `preview:destroy()` avant `world:destroy()`, skip WorldRenderer N185, skip `setKind` N183, **≠** visual V76) |
| N187 | Minimap.destroy leftover `self.panel:Destroy` rematch | P3 | alors (après N186 ; rematch `init.client` `minimap:destroy()` **déjà** ; **≠** visual V69) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 / #169 / #171 / #173 / #176 / #178 / #181 / #183 / #185 / #187 / #189 / #191 / #193 / #195 / #197 / #200 / #202 / #204 / #206 / #208 / #210 / #213 / #214 / #216 / #219 / #221 / #223 / #225 / #227 / #229 / #232 / #234 / #236 / #238 / #240 / #242 / #244 / #246 / #248 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N185 `worldFree` rematch) |

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

Client : **35/35 OK** — dont `selection de chaque nation et de chaque mode` leftover N171 `flagFree` + leftover N172 `previewFree` ; `fil de notifications sature` leftover N153 / leftover N167 commentaire **sans** flush + leftover N174 **sans** flush ; `messages rapides` leftover N170 `chatFree` ; `calques d'entites, effets et apercu` leftover N155 / leftover N168 / leftover N169 ; `pose et capture de chaque type de batiment` leftover N180 `routeFree` snapshot factory→city + kind=0 Parent nil + reuse Parent `overlay.root` **ou** free-list puis park usine / leftover N178 `buildingFree` snapshot CITY L3 + reuse Parent `overlay.root` **ou** free-list / leftover N136 / leftover N132 / leftover N166 commentaire **sans** flush ; `navires, missiles et interpolation` leftover N151 trail / leftover N152 flame Size / leftover N160 wake **sans** flush / leftover N161 splash **sans** flush / leftover N175 commentaire **sans** flush / leftover N176 park immédiat snapshot Parent nil **sans** flush, skip retraite id=1 N56, extra missile `rawequal` **avant** despawn ; `vagues de conquete` N181 `overlay:clear()` snapshot voie N162 Parent nil + `routeFree`, N179 snapshot CITY N162 Parent nil + `buildingFree` Kind CITY, N177 spawn id=77/66 + reuse id=55/44 `rawequal` Parent `overlay.root` **ou** free-list, PointLight enfant, N176 `ogiveFree` reuse / N175 `shipFree` reuse / N174 `dismissFree` reuse / N167 `feedFree` reuse / leftover N166 `BuildRing` reuse / leftover N165 `Blast` reuse / leftover N164 `BlastSmoke` reuse / leftover N163 `Shockwave` reuse / leftover N162 `DeliveryPulse` reuse / leftover N161 `LandingSplash` reuse / leftover N160 `LaunchWake` reuse ; `etiquettes de faction` leftover N182 snapshot ancre slot 1 avant `refresh(emptied)` + Parent nil + `labelFree` + restore `refresh(owner)` reuse Parent `labels.root` **ou** free-list + leftover N96 carte neutre + `clear()` sans vider `labelFree` ; `apercu de placement pour chaque batiment` leftover N183 snapshot Ghost CITY avant `hide()` + Parent nil + `ghostFree` + restore `setKind(CITY)` reuse Parent `preview.root` **ou** free-list + leftover N129 euler + boucle `BUILDABLE` ; `construction du monde 3D` leftover N184 `world.root.Name == "ConquestWorld"` **sans** second `new()` + leftover N185 commentaire **sans** `destroy()` + leftover N106 `partCount` + leftover N112 `dirtyHead` + leftover N114 compact ; `ecran de victoire` leftover N173 `valueFree`. Serveur **non** touché cette passe. `UnitModels.luau` **non** touché. PlacementPreview **non** touché. HUD **non** touché. BuildingModels **non** touché. Effects **non** touché. MainMenu **non** touché. VictoryScreen **non** touché. Overlay **non** touché. FactionLabels **non** touché. `init.client` **non** touché. Pulse flamme Size **inchangé** (N152). PlacementPreview.destroy Placement Destroy **inchangé** (N186). WorldRenderer.destroy rematch Folder **poolé**. WorldRenderer.new leftover Folder **poolé**. PlacementPreview `setKind` **poolé**. FactionLabels `refresh`/`clear` **poolé**. Overlay `clear` routes **poolé**. Overlay `syncFactoryRoutes` **poolé**. Overlay `clear` bâtiments **poolé**. Overlay `applyBuildingDelta` destroy/rebuild **poolé**. Overlay `clear` unités live **poolé**. Overlay despawn ogive immédiat **poolé**. Overlay despawn navire delay **poolé**. HUD `Dismiss` delay **poolé**. VictoryScreen `Value` **poolé**. MainMenu `drawTerrainPreview` **poolé**. MainMenu `drawFlag` **poolé**. HUD `refreshChatSheet` **poolé**. Stub `Disconnect` **inchangé**. `Overlay.luau` **zéro** `:Destroy()`. `FactionLabels.luau` **zéro** `:Destroy()`. `PlacementPreview.setKind` **zéro** `:Destroy()`. `WorldRenderer.luau` **zéro** `:Destroy()`.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass94.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N185 est un recycle Folder monde rematch vérifié par le banc headless (`construction` Name `ConquestWorld` + N106 `partCount` inchangé, **sans** `world:destroy()`). Pulse flamme Size **inchangé** (N152). PlacementPreview.destroy Placement Destroy **inchangé** (N186).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N185 n’ajoute **pas** de require (`parkWorld` existant N184, local). Intro continue de `require` MainMenu pour `drawFlag` (déjà). N152 restera dans `UnitModels.place` flame. N186 restera dans `PlacementPreview.destroy` + `new()` take + `init.client` câblage.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Distinct trail N151. Distinct Overlay N163–N181 **déjà**. Distinct leftover N182 **déjà**. Distinct leftover N183 **déjà**. Distinct leftover N184 **déjà**. Distinct leftover N185 **déjà**. Distinct leftover N186. Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N177 : `Overlay.clear` boucle units seulement. **Pas** Destroy des Model live. Push `shipFree` / `ogiveFree` **existants** (pas de 3e liste). **Garder** `visual.pieces` / kind / PointLight. Kind+slot match **obligatoire**. Skip bâtiments. Skip routes. Skip `init.client`. Distinct N176 despawn applyUnits. Distinct visual V114 (fermée `fb11`, ne pas merger). **Ne pas** appeler `clear()` dans « navires ». **Ne pas** casser N176 ni N175 ni N174 ni N173 ni N172 ni N171 ni N170 ni N169 ni N168 ni N167 ni N161 ni N160 ni N98. `takeShip` / `takeOgive` **inchangés**. `rememberShipRest` hoisté au-dessus de `Overlay.clear`.

Piège N178 : `applyBuildingDelta` deux sites seulement. **Pas** Destroy des Model bâtiments. Free-list `buildingFree` (pas `shipFree`/`ogiveFree`/`ringFree`). **Garder** Kind+Level match. Name `Building{index}` + CFrame + Marker **réécrits**. Recapture same kind+level **recolor déjà**. Overlay `clear` bâtiments **aussi N179**. Skip routes. Distinct N177 `clear` unités. Distinct visual V116 (fermée `eaa4`, ne pas merger). **Ne pas** appeler `clear()` pour tester le pool pose. **Ne pas** casser N179 ni N177 ni N176 ni N175 ni N166 ni N162. `makeBuilding` construction **inchangée** si mismatch. `syncFactoryRoutes` kind==0 **avant** park.

Piège N179 : `Overlay.clear` boucle `self.buildings` seulement. **Pas** Destroy des Model live. Push `buildingFree` **existant** (N178). Skip `Parent == nil`. Skip unités (N177). Skip routes (N181). Distinct visual V116 (fermée `eaa4`, ne pas merger). **Ne pas** retoucher `applyBuildingDelta`. **Ne pas** casser N178 ni N177. **Ne pas** vider `buildingFree` au clear.

Piège N180 : `syncFactoryRoutes` seulement. **Pas** Destroy des Model voies. Free-list `routeFree` (pas `buildingFree`). Take key usine+ville **obligatoire**. `truckModel.Parent = nil` N162 **conservé**. `segRot` N115 **conservé**. Overlay `clear` routes **aussi N181**. Distinct visual V118 (fermée `73e0`, ne pas merger). **Ne pas** retoucher `buildingFree`. **Ne pas** casser N179 ni N178 ni N162. Relink 3→1 parque les villes tombées, take le couple restant.

Piège N181 : `Overlay.clear` boucle `self.routes` seulement. **Pas** Destroy des Model live. Push `routeFree` **existant** (N180) via `parkRoute` hoisté. Skip `Parent == nil`. Skip bâtiments (N179). Skip unités (N177). Skip `syncFactoryRoutes`. city depuis la clé si absent. Distinct visual V118 (fermée `73e0`, ne pas merger). **Ne pas** retoucher `takeRoute`. **Ne pas** casser N180 ni N179 ni N177 ni N162. **Ne pas** vider `routeFree` au clear. **Ne pas** insérer `applyBuildingDelta` après `clear()` dans vagues.

Piège N182 : `FactionLabels.refresh` deux sites + `clear`. **Pas** Destroy des Part ancres. Free-list `labelFree` (record entry, pas Overlay). Take n’importe quel entry, Name `FactionAnchor{slot}`. Skip `Parent == nil`. Skip Overlay. Skip `surveyTerritories` N96. Distinct visual passe 102 (fermée `3437`, ne pas merger). Distinct visual passe 103 (fermée `d555`, ne pas merger). **Ne pas** casser N181 ni N96. **Ne pas** vider `labelFree` au clear. **Ne pas** insérer `overlay:clear()` dans etiquettes.

Piège N183 : `PlacementPreview.setKind` seulement. **Pas** Destroy des Model Ghost. Free-list `ghostFree` (Model, pas FactionLabels). Take Kind match, Name `Ghost`, `SetAttribute("Kind", kind)` après create. Skip `Parent == nil`. Skip `destroy()` (N186). Skip footprint. Skip FactionLabels. Skip Overlay. Skip `BuildingModels.create`. Distinct visual V76 (Size rayon, ne pas merger). **Ne pas** casser N182 ni N129 ni N92. **Ne pas** vider `ghostFree` au `hide`. **Ne pas** insérer `overlay:clear()` ni `labels:clear()` dans apercu.

Piège N184 : `WorldRenderer.new` leftover seulement. **Pas** Destroy du Folder. Free-list `worldFree` (Folder, pas Ghost). Take n’importe quel Folder, Name `ConquestWorld`. Park enfants **avant** `buildOcean`. Ground/Border → N106. Skip `Parent == nil`. Skip PlacementPreview. Skip Overlay. Skip `rebuildChunk` N106. Distinct visual V112 (fermée `3ba1`, ne pas merger). Distinct visual passe 105 (fermée `340e`, ne pas merger). **Ne pas** casser N183 ni N106 ni N112 ni N114. **Ne pas** vider `worldFree` au `destroy()` (N185 push). **Ne pas** appeler un second `new()` sans restore du `world` global.

Piège N185 : `WorldRenderer.destroy` seulement. **Pas** Destroy du Folder. Push `worldFree` **existant** (N184). Skip take (N184 `new()` déjà). Skip park enfants (`new()` `parkWorldChildren` déjà). Skip `Parent == nil`. Skip `new()`. Skip PlacementPreview. Skip Overlay. Skip `rebuildChunk` N106. Skip `init.client`. Distinct visual V112 (fermée `3ba1`, ne pas merger). **Ne pas** casser N184 ni N183 ni N106 ni N112 ni N114. **Ne pas** appeler `world:destroy()` dans le banc. **Ne pas** vider `worldFree`.

Piège N186 (à venir) : `PlacementPreview.destroy` + `new()` take + `init.client` `preview:destroy()` avant `world:destroy()`. **Pas** Destroy du Folder. Free-list `placeRootFree` (Folder, pas `ghostFree`). Take Folder. Footprint `FindFirstChild`. Ghost leftover → `self.ghostFree`. Skip `Parent == nil`. Skip `setKind` N183. Skip WorldRenderer N185. Skip Overlay. Skip footprint euler N129. Distinct visual V76 (Size rayon, ne pas merger). **Ne pas** casser N185 ni N184 ni N183 ni N129. **Ne pas** appeler `preview:destroy()` dans le banc apercu. **Ne pas** vider `ghostFree`. **Si park sans take : ne pas livrer.**
