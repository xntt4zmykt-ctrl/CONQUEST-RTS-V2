# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 87)

Déclencheur : ouverture de la **PR #234** (`cursor/analyse-nocturne-du-codebase-cfc7`) — Overlay `clear` unités live recycle (N177), specs N152 / N178.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-14ea`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#234. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

Overlay `applyBuildingDelta` destroy/rebuild : `Parent = nil` + push `buildingFree` (**N178**, Kind+Level match, Name/CFrame/Marker au reuse). Overlay `clear` unités live : `Parent = nil` + push `shipFree` / `ogiveFree` existants (**N177**). Overlay `applyUnits` missile Destroy immédiat : free-list `ogiveFree` (**N176**). Overlay `applyUnits` delay modèle navire : free-list `shipFree` (**N175**). HUD `notify` delay `Dismiss` : free-list `dismissFree` (**N174**). VictoryScreen `show` `Value` : free-list `valueFree` (**N173**). MainMenu `drawTerrainPreview` : free-list `previewFree` (**N172**). MainMenu `drawFlag` : free-list `flagFree` (**N171**). HUD `refreshChatSheet` : free-list `chatFree` (**N170**). Effects `clearActionPreview` : `Parent = nil`, garder `self.actionPreview` (**N169**). Effects `clearSelection` : `Parent = nil`, garder `self.selection` (**N168**). HUD `notify` TextLabel : free-list `feedFree` (**N167**). BuildingModels BuildRing : free-list `ringFree` (**N166**). Overlay Blast sphère : free-list `blastFree` (**N165**). Overlay BlastSmoke : free-list `smokeFree` (**N164**). Overlay Shockwave : free-list `shockFree` (**N163**). PointLight reste **enfant** de Blast / EngineFlame. UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). Overlay `clear` bâtiments `part:Destroy()` encore (leftover **N179**). Overlay `syncFactoryRoutes` `route.model:Destroy` encore (leftover **N180**).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #234 (passe 86) : claims vérifiés.** Overlay `clear` unités live Parent=nil, push `shipFree`/`ogiveFree` existants, kind+slot match, `rememberShipRest` hoisté, skip `Parent == nil`, skip bâtiments/routes, skip `init.client`. Check vagues : spawn id=77/66 + `overlay:clear()` + reuse id=55/44 `rawequal` Parent `overlay.root` **ou** free-list, PointLight enfant. `ogiveFree` N176 déjà. `shipFree` N175 déjà. N152 non livré (freeze Size=API = visual V74, interdit). Stub `Disconnect` inchangé. **N178 livré ici.** Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **branche `87c1`** V117 LandingSplash `splashFree` — feel N161 **déjà**, **pas merger**. Visual **branche `eaa4`** V116 DeliveryPulse `deliveryFree` — feel N162 **déjà**, **pas merger**. Visual **branche `057c`** V115 Shockwave `shockFree` — feel N163 **déjà**, **pas merger**. Visual **branche `fb11`** V114 BlastSmoke `smokeFree` — feel N164 **déjà**, **pas merger**. Visual **branche `1aab`** V113 Blast `blastFree` — feel N165 **déjà**, **pas merger**. Visual **branche `3ba1`** V112 Ground/Border recycle — feel N106 **déjà**, **pas merger**. Visual **branche `9922`** V111 flame `frame.X` — feel `sin(time * 18)` **sans** phase spatiale **encore**, **pas merger** (N152 freeze **toujours** interdit).

Cette passe a **livré N178** (ce que #234 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #234

| Claim #234 | Réalité à l’ouverture |
|---|---|
| Overlay `clear` unités live Parent=nil (N177) | Oui. Boucle `self.units` seulement. `Parent = nil` + push `shipFree` si `not unit.isMissile` / `ogiveFree` si `unit.isMissile`. `rememberShipRest` hoisté. Skip `Parent == nil`. Skip bâtiments/routes. Check vagues spawn + `clear` + reuse `rawequal` Parent `overlay.root` **ou** free-list. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N178 | **N178 livré ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #234, visuelles #39/…/`87c1` V117 LandingSplash / `eaa4` V116 DeliveryPulse / `057c` V115 Shockwave / `fb11` V114 BlastSmoke / `1aab` V113 Blast / `3ba1` V112 Ground/Border / `9922` V111 flame. **#234 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `87c1` / `eaa4` / `057c` / `fb11` / `1aab` / `3ba1` / `9922` ni hardening `41e2` / `93f6` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N178 est cosmétique monde (delta Overlay). Risques documentés, non corrigés ici (hors N178) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip `rng > 0.12` seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. Aucun bug clair sûr hors N178. Overlay `explosion` n’a plus de `Destroy` (Blast / Shockwave / BlastSmoke tous poolés). Overlay despawn ogive **poolé**. Overlay despawn navire delay **poolé**. Overlay `clear` unités live **poolé**. Overlay `applyBuildingDelta` destroy/rebuild **poolé**. Overlay `clear` bâtiments Destroy encore (leftover N179). UnitModels flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze — **non livré**).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N178 du rapport #234. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Overlay `applyBuildingDelta` Destroy Model destroy/rebuild (N178) | `Overlay.luau` (`applyBuildingDelta` seulement : `Parent = nil` + push `buildingFree`, take Kind+Level, `poseBuilding` Name/CFrame/Marker/Slot, recapture same kind+level **recolor inchangée**, `syncFactoryRoutes` kind==0 **avant** park, skip `Parent == nil`, skip `Overlay.clear` bâtiments, skip routes), `tests/client.luau` (check « pose et capture » leftover N178 **après** recapture slot=2 : snapshot CITY L3, kind=0, Parent nil + `buildingFree`, reuse autre index `rawequal` Parent `overlay.root` **ou** free-list, Name `Building{index}`, inspecteur kind/slot/level ; garder routes nil + leftover N166) | Leftover N177. `BuildingModels.create` (halle + toits + Marker) × capture/destruction 10 Hz alors que recapture recolore déjà et `buildingFree` n’existait pas. Pas d’autorité. **Kind+Level match obligatoire** sinon silhouette palier fantôme (N140). **Name/CFrame/Marker obligatoires** sinon bâtiment sur la mauvaise tuile. Skip `Overlay.clear` bâtiments. Skip routes. Skip `init.client`. Cosmétique. Flame leftover N152 **alors**. Overlay `clear` bâtiments leftover N179 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), Overlay `clear` bâtiments Destroy (**N179**), Overlay `route.model:Destroy` (**N180**), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, PlacementPreview Size rayon (visual V76, feel Size = API), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline** **et** N160 free-list, **pas merger**), visual V116 DeliveryPulse (feel N162 **déjà**, **pas merger** `eaa4`), tribus `humanTargetProtected`. Overlay `clear` unités N177 **inchangé**. Overlay despawn `applyUnits` **inchangé**. Overlay `clear` bâtiments / routes **Destroy conservé**. Flame **non**. Blast **non**. BlastSmoke **non**. Shockwave **non**. DeliveryPulse **non**. `routePart` **non**. Dismiss `table.remove(index)` **non**. HUD `chatFree` **inchangé**. HUD `feedFree` **inchangé**. HUD `dismissFree` **inchangé**. `shipFree` N175 despawn delay **inchangé**. `ogiveFree` N176 despawn immédiat **inchangé**. `previewTile` N154 skip **inchangé**. `clearSelection` N168 **inchangé**. `clearActionPreview` N169 **inchangé**. `refreshChatSheet` N170 **inchangé**. `drawFlag` N171 **inchangé**. `drawTerrainPreview` N172 **inchangé**. VictoryScreen `Value` N173 **inchangé**. HUD `Dismiss` N174 **inchangé**. `splashFree` N161 **inchangé**. `wakeFree` N160 **inchangé**. Recapture same kind+level **recolor inchangée**.

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
- Overlay `applyBuildingDelta` destroy/rebuild poolé (**N178**, `buildingFree`). Overlay `clear` unités live poolé (**N177**, `shipFree`/`ogiveFree` existants). Overlay despawn ogive immédiat poolé (**N176**, `ogiveFree`). Overlay despawn navire delay poolé (**N175**, `shipFree`). HUD `notify` delay `Dismiss` poolé (**N174**, `dismissFree`). VictoryScreen `show` `Value` poolé (**N173**, `valueFree`). MainMenu `drawTerrainPreview` poolé (**N172**, `previewFree`). MainMenu `drawFlag` poolé (**N171**, `flagFree`). HUD `refreshChatSheet` poolé (**N170**, `chatFree`). Effects `clearActionPreview` poolé (**N169**, un marqueur). Effects `clearSelection` poolé (**N168**, un marqueur). HUD `notify` free-list (**N167**). BuildingModels BuildRing free-list (**N166**). Overlay Blast sphère free-list (**N165**). Overlay BlastSmoke free-list (**N164**). Overlay Shockwave free-list (**N163**). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). Overlay `clear` bâtiments Destroy encore (**N179**). Overlay `syncFactoryRoutes` Destroy encore (**N180**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N179)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N178** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N179** = nouveau (`Overlay.clear` bâtiments). **N180** = leftover routes (hors N179). **N178** fermé ici.

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover feel Overlay `clear` bâtiments `part:Destroy()` = **N179** (N178 `buildingFree` **déjà**, N177 `clear` unités **déjà**, Kind+Level **déjà** sur le Model, **≠** visual V116 DeliveryPulse fermée `eaa4`, **≠** `ogiveFree`). Leftover `syncFactoryRoutes` `route.model:Destroy` = **N180** (hors N179). Visual V116 DeliveryPulse **fermée** sur `eaa4` (feel N162 **déjà** — ne pas merger). Visual V115 Shockwave **fermée** sur `057c` (feel N163 **déjà** — ne pas merger). Visual V114 BlastSmoke **fermée** sur `fb11` (feel N164 **déjà** — ne pas merger). Visual leftover V1 packing spawn / V7 anti-splash / V9b Persistence / V13 rot doomsday / V14b flushOwnerDelta en-tête / V118 LaunchWake. Visual V117 LandingSplash **fermée** sur `87c1` (feel N161 **déjà** — ne pas merger). Ne pas merger visual `87c1` / `eaa4` / `057c` / `fb11` / `1aab` / `3ba1` / `9922`.

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N178 (pools Overlay/Effects/BuildingModels/HUD/selection/preview/chat/drapeau/miniature/podium/Dismiss/navire/ogive/`clear` unités / `applyBuildingDelta` **déjà**). Distinct de N151 (trail Transparency), de N163–N178 (pools Overlay explosion / BuildRing / HUD feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview` / `Value` / `Dismiss` / modèle navire / ogive / `Overlay.clear` unités / `applyBuildingDelta`), de N179 (`Overlay.clear` bâtiments Destroy), de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**. Ne pas toucher trail. Ne pas toucher `BuildingModels`. Ne pas toucher Overlay. Ne pas toucher HUD. Ne pas toucher Effects. Ne pas toucher MainMenu. Ne pas toucher VictoryScreen.

**Problème :** N178 ferme le pool `applyBuildingDelta`. N179 reste ouvert (`Overlay.clear` bâtiments Destroy). N151 ferme le trail. N153–N177 ferment HUD préfixe / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview` / `Value` / `Dismiss` / modèle navire / ogive / `Overlay.clear` unités. Reste, **chaque frame** (`UnitModels.place`, 60 Hz, une Part `EngineFlame` par ogive) :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (plus de pulse Size, `c0ec` / PR #151). Visual V111 (`9922`) a ajouté `frame.X * 0.1` dans le sin — **ne pas porter**. Feel **garde** le pulse Z `sin(time * 18)` **sans** phase spatiale. Ne pas porter `c0ec` ni `9922`. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**. Role `"flame"` **inchangé**. Shape `Ball` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. Overlay `applyBuildingDelta` **déjà** N178 — ne pas y revenir. Overlay `clear` unités **déjà** N177. `ogiveFree` **déjà** N176. Visual V74 freeze **interdit** (feel ≠ visual). **Passes 61–87 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse `1.8 + math.sin(time * 18) * 0.45`. **Ne pas** geler Size (visual V74 Option A, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)`. XY `0.62` / base `1.8` / freq `18` / amp `0.45` **inchangés**.

2. **Garder le pulse.** Ne **pas** poser Size = API. Ne **pas** porter V111 `frame.X`. Ne **pas** « fermer » trail / HUD / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview` / `Value` / `Dismiss` / modèle navire / ogive / `Overlay.clear` / `applyBuildingDelta` (N151–N178 déjà). Ne **pas** lire `piece.part.Size` (alloc). Ne pas porter visual. Après N178. `BuildingModels` **non**. Overlay **non**. HUD **non**. Effects **non**. MainMenu **non**. VictoryScreen **non**. `createMissile` construction **non** (taille initiale `Vector3.new(0.62, 0.62, 2.3)` inchangée).

3. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N179 seulement.** N152 reste alors ouvert (feel-diverged vs V74). Ne pas inventer un cache Size. Ne pas skip-si-inchangé (N2, pas ici).

4. Tests « navires, missiles et interpolation » leftover N151 trail **et** leftover N148 mesh **et** leftover N147 Fin **doivent rester verts**. Tests « ecran de victoire » leftover N173 `valueFree` reuse **doivent rester verts**. Tests « pose et capture » leftover N178 `buildingFree` reuse **doivent rester verts**. Tests « vagues de conquete » leftover N177 `clear` reuse **et** leftover N176 `ogiveFree` reuse **et** leftover N175 `shipFree` reuse **et** leftover N174 `dismissFree` reuse **et** leftover N167 `feedFree` reuse **doivent rester verts**. Tests « selection de chaque nation » leftover N171 `flagFree` reuse **et** leftover N172 `previewFree` reuse **doivent rester verts**. Tests « messages rapides » leftover N170 `chatFree` reuse **doivent rester verts**. Tests « calques d'entites, effets et apercu » leftover N169 `clearActionPreview` reuse **et** leftover N168 `clearSelection` reuse **et** leftover N155 `rawequal` 2000→2001 **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` flame **seulement**, **un** `elseif`) **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N152. Overlay **non**. **Ne pas** éditer le serveur. **Ne pas** toucher Shockwave ni BlastSmoke ni Blast sphère ni BuildRing ni HUD chat ni feed ni `Dismiss` ni `clearSelection` ni `clearActionPreview` ni `refreshChatSheet` ni `drawFlag` ni `drawTerrainPreview` ni VictoryScreen ni modèle navire ni ogive ni `Overlay.clear` ni `applyBuildingDelta`.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ N151 (trail Z) ≠ visual V74 (freeze Size=API, ne pas merger) ≠ N163–N178 (pools Overlay/HUD/Effects déjà) ≠ N179 (`Overlay.clear` bâtiments Destroy) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N179 dans le même worker. Pulse Z **conservé** — ne pas figer à 1.8. Un `elseif` flame.

---

### ISSUE-N179 — Overlay `clear` bâtiments `part:Destroy()` (feel)

**Priorité :** P3 alloc client Overlay. Leftover explicite après N178 (`applyBuildingDelta` `buildingFree` déjà). Distinct de N152 (UnitModels Size), de N178 (`applyBuildingDelta` **déjà**), de N177 (`clear` unités **déjà**), de N176 (`ogiveFree` **déjà**), de N175 (`shipFree` **déjà**), de visual V116 (DeliveryPulse **fermée** sur `eaa4` — **ne pas merger**), de visual V115 (Shockwave **fermée** sur `057c` — **ne pas merger**). `Overlay.clear` boucle `self.buildings` **seulement** (`part:Destroy()`). Ne pas toucher HUD. Ne pas toucher VictoryScreen. Ne pas toucher MainMenu. Ne pas toucher UnitModels.place. Ne pas toucher Effects. Ne pas retoucher `buildingFree` take/pose `applyBuildingDelta`. Ne pas retoucher `Overlay.clear` unités. Ne pas toucher `syncFactoryRoutes` `route.model:Destroy` (leftover **N180**).

**Problème :** N178 ferme le pool destroy/rebuild `applyBuildingDelta`. N152 reste ouvert (freeze interdit). Reste, **chaque rematch / teardown Overlay** (`Overlay.clear`, **pas** `applyBuildingDelta` kind==0 qui parque déjà) :

```
for _, part in self.buildings do
	part:Destroy()
end
table.clear(self.buildings)
```

`buildingFree` existe déjà (N178). Recycle pour que le teardown ne `Destroy` plus les Model live : `Parent = nil` + push `buildingFree` (liste **existante**, pas `shipFree`/`ogiveFree`/`ringFree`). `syncFactoryRoutes` / `route.model:Destroy()` — **hors scope** (leftover N180). Distinct de leftover N152 (`Size = Vector3.new` flamme). Distinct de leftover N178 (`applyBuildingDelta` **déjà**). Distinct de leftover N177 (`clear` unités **déjà**). Kind / Level **déjà** attributs. Billboard `Marker` **conservé**.

**Piège liste :** réutiliser `buildingFree`. Ne **pas** nommer `buildFree` / `modelFree` / `clearFree`. Ne **pas** pousser un navire. Stocker le **Model** (attributs Kind/Level/Slot/Index/Tint déjà dessus).

**Piège Parent nil :** skip si `Parent == nil` (déjà parké par N178 kind==0). Double-push = silhouette dupliquée au take.

**Piège Overlay.clear unités :** N177 **inchangé** (`shipFree`/`ogiveFree`). Ne **pas** fusionner les listes. Skip routes. `table.clear(self.buildings)` **après** le park, comme aujourd’hui.

**Piège take :** `takeBuilding` Kind+Level **déjà** N178. Ne **pas** le réécrire. Un Model parké au `clear` a encore Kind+Level — le take N178 le retrouve. Oubli Level = hall usine palier 3 recyclé en palier 1.

**Piège tests existants :** check « pose et capture » leftover N178 snapshot + reuse **sans** `clear()` — **ne pas y toucher**. Check « vagues de conquete » appelle `overlay:clear()` **après** N162 CITY+FACTORY live **et** spawn unités N177. **Garder** `next(overlay.buildings)==nil` et `next(overlay.routes)==nil` après clear. **Ajouter** si possible : snapshot `overlay.buildings[cityIndex]` (CITY N162) **avant** `clear()`, Parent nil **ou** présence `buildingFree`, **sans** insérer un `applyBuildingDelta` dans le bloc N177 unités (reuse id=55/44 **après** clear). Ne **pas** Destroy `buildingFree` au clear. Check « modeles procéduraux » `BuildingModels.create` **direct** — ne **pas** y toucher.

**Pourquoi 20K CCU :** leftover N178. Rematch / teardown × `BuildingModels.create` (halle + toits + Marker) alors que `buildingFree` existe déjà. Pas d’autorité (cosmétique monde). `applyBuildingDelta` **déjà** N178 — ne pas y revenir. `clear` unités **déjà** N177 — ne pas y revenir. Visual V116 DeliveryPulse **interdit** (fermée sur `eaa4`, ne pas merger). **Oubli de skip Parent nil** = double-push. **Destroy des free-lists** = N178 cassé. **Si le seul patch est un merger visuel, un Destroy des free-lists, un pool routes, ou un retouch `applyBuildingDelta` : ne pas livrer.**

**Worker :**

1. Dans `Overlay.clear` boucle `self.buildings` **seulement** : **ne plus** `Destroy`. `Parent = nil` + push `buildingFree` (liste **N178 existante**) si encore parenté. `table.clear(self.buildings)` après. Unités N177 **inchangées**. Routes Destroy **conservé** (N180). Pas de delay. Pas de 3e liste.

2. **Garder les silhouettes.** Ne **pas** fusionner kind. Ne **pas** retoucher `applyBuildingDelta` N178. Ne **pas** retoucher `Overlay.clear` unités N177. Ne **pas** toucher N176 `ogiveFree` despawn. Ne **pas** toucher N175 `shipFree` delay. Après N178. Flame Size **non** (N152). HUD **non**. Effects **non**. `BuildingModels.create` / `playConstruction` **non**. `init.client` **non**. `syncFactoryRoutes` **non**.

3. Tests « pose et capture de chaque type de batiment » leftover N178 / N136 / N132 / N166 **doivent rester verts** (recapture slot=2 **sans** recreate, destroy kind=0 `routes` nil, snapshot + reuse `buildingFree` **sans** `clear()`). Tests « vagues de conquete » leftover N177 / N176 / N175 / N174 / N167 / N166 / N162 **doivent rester verts**. **Ajouter** si possible snapshot CITY N162 avant `clear()` + Parent nil **ou** `buildingFree` (**ne pas** insérer un `applyBuildingDelta` dans le bloc N177 unités). Tests « navires » leftover N176 park immédiat **sans** `clear` **et** leftover N152 flame Size **doivent rester verts**. Tests « ecran de victoire » leftover N173 **doivent rester verts**. Tests « selection de chaque nation » leftover N171 / N172 **doivent rester verts**. Tests « messages rapides » leftover N170 **doivent rester verts**. Tests « calques » leftover N169 / N168 / N155 **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client `pose et capture` **et** `vagues de conquete` **doivent rester verts**. Check pose leftover N178 **sans** `clear()`. Check vagues leftover N177 **avec** `clear()` unités. Check navires leftover N152 flame. **Ne pas** casser N178 (`buildingFree` snapshot + reuse `rawequal` Parent `overlay.root` **ou** free-list). **Ne pas** casser N177 (`clear` snapshot + reuse). **Ne pas** casser N176 (`ogiveFree`). **Ne pas** casser N175 (`shipFree`). **Ne pas** casser N174 (`dismissFree`). **Ne pas** casser N173 (`valueFree`). **Ne pas** casser N172 (`previewFree`). **Ne pas** casser N171 (`flagFree`). **Ne pas** casser N170 (`chatFree`). **Ne pas** casser N169 (`self.actionPreview`). **Ne pas** casser N168 (`self.selection`). **Ne pas** casser N167 (`feedFree`). **Ne pas** casser N166 (`ringFree`). **Ne pas** casser N161 (`splashFree`). **Ne pas** casser N160 (`wakeFree`). **Ne pas** casser N98 extra missile `rawequal`. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `Overlay.luau` (`Overlay.clear` boucle `self.buildings` **seulement**, `buildingFree` existant, pas `applyBuildingDelta`, pas `syncFactoryRoutes`). `tests/client.luau` **seulement** le check « vagues de conquete » (commentaire leftover N179, **ajouter** snapshot CITY avant `clear` si possible, **garder** N177 spawn + reuse unités + leftover N166). `HUD.luau` **non**. `VictoryScreen.luau` **non**. `MainMenu.luau` **non**. `Effects.luau` **non**. `UnitModels.luau` **non**. `BuildingModels.luau` **non**. `init.client.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher flame Size ni Blast ni HUD chat ni `feedFree` ni `Dismiss` ni `clearSelection` ni `clearActionPreview` ni `flagFree` ni `previewFree` ni `valueFree` ni `splashFree` ni `wakeFree` ni `applyBuildingDelta` ni le despawn `applyUnits`. **Ne pas** merger visual V116 (`eaa4`). **Ne pas** merger visual V115 (`057c`). **Ne pas** merger visual V114 (`fb11`). **Ne pas** merger visual V113 (`1aab`). **Ne pas** merger visual V112 (`3ba1`). **Ne pas** merger visual V111 (`9922`).

**Contraintes :** pas de RemoteFunction. **N179 feel ≠ N178 (`applyBuildingDelta` déjà) ≠ N177 (`Overlay.clear` unités déjà) ≠ N176 (`ogiveFree` déjà) ≠ N175 (`shipFree` déjà) ≠ N166 (BuildRing déjà) ≠ N152 (flame Size, ne pas freeze V74) ≠ visual V116 (DeliveryPulse fermée `eaa4`, ne pas merger) ≠ `syncFactoryRoutes` Destroy (leftover N180) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N152 dans le même worker. **Pas Destroy** des Model bâtiments au `Overlay.clear`. **Pas de parcours hors `self.buildings`.** **Skip Parent nil.** Distinct `buildingFree` — **ne pas** partager avec `shipFree`/`ogiveFree`/`ringFree`. Overlay `clear` unités N177 **obligatoire** inchangé. Overlay `applyBuildingDelta` N178 **obligatoire** inchangé. Overlay `clear` routes Destroy **obligatoire** inchangé. **Si le pool routes, un Destroy des free-lists, ou un retouch `applyBuildingDelta` est le seul patch : ne pas livrer N179.**

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; Overlay `applyBuildingDelta` → **N178 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; Overlay `applyBuildingDelta` → **N178** ; Overlay explosion + chantier + fil clos ; Overlay `clear` bâtiments Destroy = **N179**) |
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
| N34–N151, N153–N178 | (voir rapport #234) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–87) |
| N179 | Overlay `clear` bâtiments `part:Destroy` | P3 | **nouveau** (`buildingFree` **déjà** N178, Kind+Level **déjà**, skip unités N177, skip routes N180, **≠** visual V116 fermée `eaa4`) |
| N180 | Overlay `syncFactoryRoutes` `route.model:Destroy` | P3 | leftover (hors N179) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 / #169 / #171 / #173 / #176 / #178 / #181 / #183 / #185 / #187 / #189 / #191 / #193 / #195 / #197 / #200 / #202 / #204 / #206 / #208 / #210 / #213 / #214 / #216 / #219 / #221 / #223 / #225 / #227 / #229 / #232 / #234 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N178 `buildingFree`) |

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

Client : **35/35 OK** — dont `selection de chaque nation et de chaque mode` leftover N171 `flagFree` + leftover N172 `previewFree` ; `fil de notifications sature` leftover N153 / leftover N167 commentaire **sans** flush + leftover N174 **sans** flush ; `messages rapides` leftover N170 `chatFree` ; `calques d'entites, effets et apercu` leftover N155 / leftover N168 / leftover N169 ; `pose et capture de chaque type de batiment` leftover N178 `buildingFree` snapshot CITY L3 + reuse Parent `overlay.root` **ou** free-list / leftover N136 / leftover N132 / leftover N166 commentaire **sans** flush ; `navires, missiles et interpolation` leftover N151 trail / leftover N152 flame Size / leftover N160 wake **sans** flush / leftover N161 splash **sans** flush / leftover N175 commentaire **sans** flush / leftover N176 park immédiat snapshot Parent nil **sans** flush, skip retraite id=1 N56, extra missile `rawequal` **avant** despawn ; `vagues de conquete` N177 `overlay:clear()` spawn id=77/66 + reuse id=55/44 `rawequal` Parent `overlay.root` **ou** free-list, PointLight enfant, bâtiments/routes Destroy leftover N179 / N176 `ogiveFree` reuse / N175 `shipFree` reuse / N174 `dismissFree` reuse / N167 `feedFree` reuse / leftover N166 `BuildRing` reuse / leftover N165 `Blast` reuse / leftover N164 `BlastSmoke` reuse / leftover N163 `Shockwave` reuse / leftover N162 `DeliveryPulse` reuse / leftover N161 `LandingSplash` reuse / leftover N160 `LaunchWake` reuse ; `ecran de victoire` leftover N173 `valueFree`. Serveur **non** touché cette passe. `UnitModels.luau` **non** touché. `WorldCamera.luau` **non** touché. HUD **non** touché. BuildingModels **non** touché (sauf `recolor` déjà appelé). Effects **non** touché. MainMenu **non** touché. VictoryScreen **non** touché. Pulse flamme Size **inchangé** (N152). Overlay `clear` bâtiments Destroy **inchangé** (N179). Overlay `applyBuildingDelta` destroy/rebuild **poolé**. Overlay `clear` unités live **poolé**. Overlay despawn ogive immédiat **poolé**. Overlay despawn navire delay **poolé**. HUD `Dismiss` delay **poolé**. VictoryScreen `Value` **poolé**. MainMenu `drawTerrainPreview` **poolé**. MainMenu `drawFlag` **poolé**. HUD `refreshChatSheet` **poolé**. Stub `Disconnect` **inchangé**.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass87.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N178 est un recycle Model Overlay vérifié par le banc headless (`pose et capture` snapshot + kind=0 + reuse Parent `overlay.root` **ou** free-list). Pulse flamme Size **inchangé** (N152). Overlay `clear` bâtiments Destroy **inchangé** (N179).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N178 n’ajoute **pas** de require (`parkBuilding` / `takeBuilding` / `poseBuilding` locaux Overlay). Intro continue de `require` MainMenu pour `drawFlag` (déjà). N152 restera dans `UnitModels.place` flame. N179 restera dans `Overlay.clear` bâtiments.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Distinct trail N151. Distinct Overlay N163–N178 **déjà**. Distinct leftover N179. Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N177 : `Overlay.clear` boucle units seulement. **Pas** Destroy des Model live. Push `shipFree` / `ogiveFree` **existants** (pas de 3e liste). **Garder** `visual.pieces` / kind / PointLight. Kind+slot match **obligatoire**. Skip bâtiments. Skip routes. Skip `init.client`. Distinct N176 despawn applyUnits. Distinct visual V114 (fermée `fb11`, ne pas merger). **Ne pas** appeler `clear()` dans « navires ». **Ne pas** casser N176 ni N175 ni N174 ni N173 ni N172 ni N171 ni N170 ni N169 ni N168 ni N167 ni N161 ni N160 ni N98. `takeShip` / `takeOgive` **inchangés**. `rememberShipRest` hoisté au-dessus de `Overlay.clear`.

Piège N178 : `applyBuildingDelta` deux sites seulement. **Pas** Destroy des Model bâtiments. Free-list `buildingFree` (pas `shipFree`/`ogiveFree`/`ringFree`). **Garder** Kind+Level match. Name `Building{index}` + CFrame + Marker **réécrits**. Recapture same kind+level **recolor déjà**. Skip `Overlay.clear` bâtiments. Skip routes. Distinct N177 `clear` unités. Distinct visual V116 (fermée `eaa4`, ne pas merger). **Ne pas** appeler `clear()` pour tester le pool pose. **Ne pas** casser N177 ni N176 ni N175 ni N166 ni N162. `makeBuilding` construction **inchangée** si mismatch. `syncFactoryRoutes` kind==0 **avant** park.

Piège N179 (à venir) : `Overlay.clear` boucle `self.buildings` seulement. **Pas** Destroy des Model live. Push `buildingFree` **existant** (N178). Skip `Parent == nil`. Skip unités (N177). Skip routes (N180). Distinct visual V116 (fermée `eaa4`, ne pas merger). **Ne pas** retoucher `applyBuildingDelta`. **Ne pas** casser N178 ni N177. **Ne pas** vider `buildingFree` au clear.
