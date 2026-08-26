# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 84)

Déclencheur : ouverture de la **PR #227** (`cursor/analyse-nocturne-du-codebase-5d4b`) — HUD `notify` delay `Dismiss` recycle (N174), specs N152 / N175.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-89ac`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#227. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

Overlay `applyUnits` delay modèle navire : free-list `shipFree` (**N175**). HUD `notify` delay `Dismiss` : free-list `dismissFree` (**N174**). VictoryScreen `show` `Value` : free-list `valueFree` (**N173**). MainMenu `drawTerrainPreview` : free-list `previewFree` (**N172**). MainMenu `drawFlag` : free-list `flagFree` (**N171**). HUD `refreshChatSheet` : free-list `chatFree` (**N170**). Effects `clearActionPreview` : `Parent = nil`, garder `self.actionPreview` (**N169**). Effects `clearSelection` : `Parent = nil`, garder `self.selection` (**N168**). HUD `notify` TextLabel : free-list `feedFree` (**N167**). BuildingModels BuildRing : free-list `ringFree` (**N166**). Overlay Blast sphère : free-list `blastFree` (**N165**). Overlay BlastSmoke : free-list `smokeFree` (**N164**). Overlay Shockwave : free-list `shockFree` (**N163**). PointLight reste **enfant** de Blast. UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). Overlay missiles Destroy immédiat encore (leftover **N176**). Overlay `clear` Destroy live encore (hors N176).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #227 (passe 83) : claims vérifiés.** HUD `notify` delay Parent=nil, `dismissFree`, Name `Dismiss` conservé, Disconnect `Activated` avant rebranchement, Parent `entry`, delay vs clic distincts, Reset AnchorPoint/Position/Size/BackgroundTransparency/FontFace/TextSize/TextColor3/Text/ZIndex. Check vagues : snapshot + reuse `rawequal` Parent `pooledFeed` **ou** `#dismissFree`. VictoryScreen `valueFree` N173 déjà. N152 non livré (freeze Size=API = visual V74, interdit). Stub `Disconnect` inchangé. **N175 livré ici.** Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **branche `1aab`** V113 Blast `blastFree` — feel N165 **déjà**, **pas merger**. Visual **branche `3ba1`** V112 Ground/Border recycle — feel N106 **déjà**, **pas merger**. Visual **branche `9922`** V111 flame `frame.X` — feel `sin(time * 18)` **sans** phase spatiale **encore**, **pas merger** (N152 freeze **toujours** interdit). Visual **PR #222** (`9726`) V110 PortCraneCable — feel lockstep `sin(time * 0.8)` **encore**, **pas merger**. Visual **PR #220** (`c6b5`) V109 PortCraneBoom — feel lockstep **encore**, **pas merger**. Visual **PR #218** (`d46a`) V108 CapitalFlag — feel lockstep **encore**, **pas merger**. Visual **PR #217** (`ee95`) V107 flag pitch — feel `sin(time * 5)` lockstep **encore**, **pas merger**. Visual **PR #215** (`35f5`) wake `offset.X` — feel N130/N160 **déjà**, **pas merger**. Visual **PR #209** (`7188`) HUD préfixe — feel N153 **déjà**, **pas merger**. Visual **PR #211** (`8bb2`) FactoryOutput — feel **déjà**, **pas merger**. Visual **PR #212** (`2f2a`) feux navire — feel lockstep **encore**, **pas merger**.

Cette passe a **livré N175** (ce que #227 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #227

| Claim #227 | Réalité à l’ouverture |
|---|---|
| HUD `notify` delay Parent=nil (N174) | Oui. TextButton `Dismiss`. `Parent = nil` + `dismissFree`, pas Destroy. Name `Dismiss` conservé. Disconnect `Activated`. Parent `entry`. Delay vs clic distincts. Check vagues : snapshot + reuse `rawequal` Parent `pooledFeed` **ou** `#dismissFree`. `valueFree` N173 déjà. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N175 | **N175 livré ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #227, visuelles #39/…/`1aab` V113 Blast / `3ba1` V112 Ground/Border / `9922` V111 flame / `9726` V110 PortCraneCable / `c6b5` V109 PortCraneBoom / `d46a` V108 CapitalFlag / `ee95` V107 flag / `35f5` V106 wake / `7188` V103 **fermé** / `8bb2` V104 FactoryOutput / `2f2a` V105 feux / `6c83` V102 compact. **#227 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `1aab` / `3ba1` / `9922` / `9726` / `c6b5` / `d46a` / `ee95` / `35f5` / `7188` / `8bb2` / `2f2a` / `6c83` / `fce3` / `b7e3` / `adfc` ni hardening `41e2` / `93f6` / `e291` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N175 est cosmétique monde (despawn navire). Risques documentés, non corrigés ici (hors N175) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip `rng > 0.12` seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N175. Overlay `explosion` n’a plus de `Destroy` (Blast / Shockwave / BlastSmoke tous poolés). BuildingModels `playConstruction` BuildRing **poolé**. HUD `notify` TextLabel **poolé**. Effects `clearSelection` **poolé**. Effects `clearActionPreview` **poolé**. HUD `refreshChatSheet` TextButton **poolé**. MainMenu `drawFlag` Frame **poolé**. MainMenu `drawTerrainPreview` Frame **poolé**. VictoryScreen `Value` **poolé**. HUD `Dismiss` delay **poolé**. Overlay despawn navire delay **poolé**. UnitModels flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze — **non livré**). Overlay missiles Destroy immédiat encore (leftover N176).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N175 du rapport #227. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Overlay `applyUnits` delay Destroy+`createBoat` chaque despawn navire 0.95 s (N175) | `Overlay.luau` (`rememberShipRest` / `restoreShip` / `takeShip`, `Parent = nil` + `shipFree`, kind+slot match, Reset Transparency/Color construction, skip missiles, skip `Overlay.clear`, Parent `self.root`), `tests/client.luau` (check vagues leftover N175 : snapshot Visual `kind==1` `slot==1` **après** le premier `testFlushDelays`, `applyUnits` id=99 `rawequal` Parent `overlay.root` **ou** `#shipFree`) | Leftover N174. Destroy+`createBoat` × despawn 10 Hz (dizaines de Parts). Pas de tableau partagé avec `splashFree` / `wakeFree` / `dismissFree` / `feedFree`. `Parent = nil` si Model navire, pas Destroy. **Kind match obligatoire** sinon silhouette fantôme. **Slot match obligatoire** (recolor non sûr + teinte retraite N56). **Reset Transparency obligatoire** sinon navire invisible. Skip missiles. Skip `Overlay.clear`. Cosmétique. Flame leftover N152 **alors**. Overlay ogives leftover N176 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), Overlay missiles Destroy immédiat (**N176**), Overlay `existing:Destroy` bâtiments, Overlay `route.model:Destroy`, Overlay `clear` Destroy live, flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, PlacementPreview Size rayon (visual V76, feel Size = API), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline** **et** N160 free-list, **pas merger**), tribus `humanTargetProtected`. Overlay `clear` / BuildingModels / Effects / UnitModels / WorldCamera / WorldRenderer / MainMenu / VictoryScreen / HUD / serveur **non édités** hors `Overlay.applyUnits` + `trackUnit` insert bateau. Flame **non**. Blast **non**. BlastSmoke **non**. Shockwave **non**. DeliveryPulse **non**. `routePart` **non**. Dismiss `table.remove(index)` **non**. HUD `chatFree` **inchangé**. HUD `feedFree` **inchangé**. HUD `dismissFree` **inchangé**. Destroy des ogives **inchangé**. `previewTile` N154 skip **inchangé**. `clearSelection` N168 **inchangé**. `clearActionPreview` N169 **inchangé**. `refreshChatSheet` N170 **inchangé**. `drawFlag` N171 **inchangé**. `drawTerrainPreview` N172 **inchangé**. VictoryScreen `Value` N173 **inchangé**. HUD `Dismiss` N174 **inchangé**. `splashFree` N161 **inchangé**. `wakeFree` N160 **inchangé**.

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
- Overlay despawn navire delay poolé (**N175**, `shipFree`). HUD `notify` delay `Dismiss` poolé (**N174**, `dismissFree`). VictoryScreen `show` `Value` poolé (**N173**, `valueFree`). MainMenu `drawTerrainPreview` poolé (**N172**, `previewFree`). MainMenu `drawFlag` poolé (**N171**, `flagFree`). HUD `refreshChatSheet` poolé (**N170**, `chatFree`). Effects `clearActionPreview` poolé (**N169**, un marqueur). Effects `clearSelection` poolé (**N168**, un marqueur). HUD `notify` free-list (**N167**). BuildingModels BuildRing free-list (**N166**). Overlay Blast sphère free-list (**N165**). Overlay BlastSmoke free-list (**N164**). Overlay Shockwave free-list (**N163**). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). Overlay missiles Destroy immédiat encore (**N176**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N176)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N175** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N176** = nouveau. **N175** fermé ici.

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover feel Overlay `applyUnits` missile Destroy immédiat = **N176** (N175 `shipFree` **déjà**, N174 `dismissFree` **déjà**, N161 `splashFree` **déjà**, N160 `wakeFree` **déjà**, Name modèle **conservé**, **≠** visual V113 Blast fermée `1aab`, **≠** `shipFree`). Visual V113 Blast **fermée** sur `1aab` / PR #228 (feel N165 **déjà** — ne pas merger). Visual V112 Ground/Border **fermée** sur `3ba1` / PR #226 (feel N106 **déjà** — ne pas merger). Visual V111 flame `frame.X` **fermée** sur `9922` (feel `sin(time * 18)` **sans** phase — ne pas merger, **≠** N152 freeze). Visual leftover V1 packing spawn / V7 anti-splash / V9b Persistence / V13 rot doomsday / V14b flushOwnerDelta en-tête. Ne pas merger visual `1aab` / `3ba1` / `9922` / `9726`.

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N175 (pools Overlay/Effects/BuildingModels/HUD/selection/preview/chat/drapeau/miniature/podium/Dismiss/navire **déjà**). Distinct de N151 (trail Transparency), de N163–N175 (pools Overlay explosion / BuildRing / HUD feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview` / `Value` / `Dismiss` / modèle navire), de N176 (ogive Destroy immédiat), de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**. Ne pas toucher trail. Ne pas toucher `BuildingModels`. Ne pas toucher Overlay. Ne pas toucher HUD. Ne pas toucher Effects. Ne pas toucher MainMenu. Ne pas toucher VictoryScreen.

**Problème :** N175 ferme le pool `shipFree`. N176 reste ouvert (Destroy ogive immédiat). N151 ferme le trail. N153–N174 ferment HUD préfixe / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview` / `Value` / `Dismiss`. Reste, **chaque frame** (`UnitModels.place`, 60 Hz, une Part `EngineFlame` par ogive) :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (plus de pulse Size, `c0ec` / PR #151). Visual V111 (`9922`) a ajouté `frame.X * 0.1` dans le sin — **ne pas porter**. Feel **garde** le pulse Z `sin(time * 18)` **sans** phase spatiale. Ne pas porter `c0ec` ni `9922`. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**. Role `"flame"` **inchangé**. Shape `Ball` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. HUD chat **déjà** N170 — ne pas y revenir. `drawFlag` **déjà** N171. `drawTerrainPreview` **déjà** N172. `Value` **déjà** N173. `Dismiss` **déjà** N174. Navire **déjà** N175. Blast **déjà** N165. Visual V74 freeze **interdit** (feel ≠ visual). **Passes 61–84 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse `1.8 + math.sin(time * 18) * 0.45`. **Ne pas** geler Size (visual V74 Option A, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)`. XY `0.62` / base `1.8` / freq `18` / amp `0.45` **inchangés**.

2. **Garder le pulse.** Ne **pas** poser Size = API. Ne **pas** porter V111 `frame.X`. Ne **pas** « fermer » trail / HUD / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection` / `clearActionPreview` / `refreshChatSheet` / `drawFlag` / `drawTerrainPreview` / `Value` / `Dismiss` / modèle navire (N151–N175 déjà). Ne **pas** lire `piece.part.Size` (alloc). Ne pas porter visual. Après N175. `BuildingModels` **non**. Overlay **non**. HUD **non**. Effects **non**. MainMenu **non**. VictoryScreen **non**. `createMissile` construction **non** (taille initiale `Vector3.new(0.62, 0.62, 2.3)` inchangée).

3. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N176 seulement.** N152 reste alors ouvert (feel-diverged vs V74). Ne pas inventer un cache Size. Ne pas skip-si-inchangé (N2, pas ici).

4. Tests « navires, missiles et interpolation » leftover N151 trail **et** leftover N148 mesh **et** leftover N147 Fin **doivent rester verts**. Tests « ecran de victoire » leftover N173 `valueFree` reuse **doivent rester verts**. Tests « vagues de conquete » leftover N175 `shipFree` reuse **et** leftover N174 `dismissFree` reuse **et** leftover N167 `feedFree` reuse **doivent rester verts**. Tests « selection de chaque nation » leftover N171 `flagFree` reuse **et** leftover N172 `previewFree` reuse **doivent rester verts**. Tests « messages rapides » leftover N170 `chatFree` reuse **doivent rester verts**. Tests « calques d'entites, effets et apercu » leftover N169 `clearActionPreview` reuse **et** leftover N168 `clearSelection` reuse **et** leftover N155 `rawequal` 2000→2001 **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` flame **seulement**, **un** `elseif`) **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N152. Overlay **non**. **Ne pas** éditer le serveur. **Ne pas** toucher Shockwave ni BlastSmoke ni Blast sphère ni BuildRing ni HUD chat ni feed ni `Dismiss` ni `clearSelection` ni `clearActionPreview` ni `refreshChatSheet` ni `drawFlag` ni `drawTerrainPreview` ni VictoryScreen ni modèle navire ni ogive.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ N151 (trail Z) ≠ visual V74 (freeze Size=API, ne pas merger) ≠ N163 (Shockwave pool) ≠ N164 (BlastSmoke pool) ≠ N165 (Blast sphère pool) ≠ N166 (BuildRing pool) ≠ N167 (HUD feed pool) ≠ N168 (`clearSelection`) ≠ N169 (`clearActionPreview`) ≠ N170 (`refreshChatSheet` déjà) ≠ N171 (`drawFlag` déjà) ≠ N172 (`drawTerrainPreview` déjà) ≠ N173 (`VictoryScreen` `Value` déjà) ≠ N174 (`Dismiss` delay déjà) ≠ N175 (modèle navire delay déjà) ≠ N176 (ogive Destroy immédiat) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N176 dans le même worker. Pulse Z **conservé** — ne pas figer à 1.8. Un `elseif` flame.

---

### ISSUE-N176 — Overlay `applyUnits` missile Destroy immédiat (feel)

**Priorité :** P3 alloc client Overlay. Leftover explicite après N175 (`shipFree` déjà). Distinct de N152 (UnitModels Size), de N175 (`shipFree` modèle navire delay **déjà**), de N174 (`dismissFree` croix **déjà**), de N161 (`splashFree` despawn cylindre **déjà**), de N160 (`wakeFree` spawn cylindre **déjà**), de visual V113 (Blast sphère **fermée** sur `1aab` — **ne pas merger**), de visual V112 (Ground/Border chunk **fermée** sur `3ba1` — **ne pas merger**). `Overlay.applyUnits` **branche `unit.isMissile` Destroy immédiat seulement**. Ne pas toucher HUD. Ne pas toucher VictoryScreen. Ne pas toucher MainMenu. Ne pas toucher UnitModels.place. Ne pas toucher Effects. Ne pas retoucher `shipFree` / `splashFree` / `wakeFree`.

**Problème :** N175 ferme le pool `shipFree`. N152 reste ouvert (freeze interdit). Reste, **chaque despawn ogive** (`applyUnits`, `unit.isMissile`, **immédiat**, pas de splash, pas de tween 0.95 s) :

```
else
    unit.visual.model:Destroy()
end
```

`Overlay.clear` Destroy — **hors scope** (teardown, leftover suivant). `syncFactoryRoutes` `route.model:Destroy` — **hors scope**. `applyBuildingDelta` `existing:Destroy` — **hors scope**. Distinct de leftover N152 (`Size = Vector3.new` flamme). Distinct de leftover N175 (`shipFree` **déjà** — **ne pas** partager). Distinct de leftover N161 (`splashFree` cylindre **déjà**). Kind `createMissile` **inchangé**. `visual.pieces` **conservé**. PointLight enfant de `EngineFlame` **conservé** (`FindFirstChildWhichIsA` au reuse, ne pas en recréer un). Extra `tx`/`ty` N98 **conservé** (record mute, pas sur le Visual). `isMissile == true` **obligatoire** pour entrer dans `ogiveFree`.

**Piège nom :** nommer **`ogiveFree`**, pas `missileFree` (clash sémantique avec `Nukes.missileFree` serveur, hors bundle client), pas `shipFree` / `splashFree` / `wakeFree`. Ne **pas** pousser un `createBoat` dans `ogiveFree`. Ne **pas** pop `ogiveFree` pour un navire.

**Piège kind / slot :** `UnitModels.createMissile(root, slot, kind)` teinte Warhead / GuidanceBand via `Theme.factionColor(slot)`. Au reuse **exiger** `visual.kind == kind` **et** `visual.slot == slot` (recolor non sûr, même règle que N175). Kind/slot différent = laisser dans la free-list, `createMissile` comme aujourd’hui.

**Piège Transparency :** `place()` anime trail (`Transparency + sin`) et flame Size (N152, **ne pas geler**). Au park, Transparency n’est **pas** tweenée à 1 (Destroy immédiat, pas le chemin navire). Quand même **snapshot** rest Transparency/Color à l’insert (`remember` analogique N175, tableau parallèle sur le Visual, **pas** muter le type `Piece`). Au reuse **reset** chaque piece à rest. Oubli trail = trainee fantôme. Ne **pas** lire Size (N152). Ne **pas** recréer `visual.pieces`. Ne **pas** recréer le PointLight (enfant de `EngineFlame`, survit au `Parent = nil`).

**Piège extra N98 :** `unit.extra` `{tx, ty}` vit sur le **record unité**, pas sur le Visual. Au reuse : nouveau record `unit` + `extra` frais depuis le snapshot (comme `createMissile` aujourd’hui). Ne **pas** recycler `unit.extra` dans `ogiveFree`. Tests navires `rawequal(extra)` **avant** le despawn `applyUnits({}, {})` **doivent rester verts**.

**Piège trackUnit insert :** `if not unit then` et `isMissile` : pop `ogiveFree` O(1) depuis la fin **si** kind+slot match. Sinon scan court **ou** `createMissile`. Parent = `self.root`. Reset CFrame via le lerp existant (N101/N103/N117 **inchangés**). `self.units[id] = unit` **conservé**. Pas de LaunchWake (garde `not isMissile` N160 **inchangée**).

**Piège navires :** delay 0.95 s `shipFree` **inchangé** (N175). Ne **pas** pousser un bateau dans `ogiveFree`. Ne **pas** pop `ogiveFree` pour un transport. Skip retraite splash N56 **conservé**. Check navires `id=1` retraite **sans** splash **doit rester vert**.

**Piège Overlay.clear :** teardown de partie. Destroy **conservé** (y compris live ogives). Ne pas transformer clear en pool. `ogiveFree` Parent=nil peut survivre (comme `shipFree`) — acceptable. Ne pas Destroy `ogiveFree` sauf si le worker vide explicitement + Destroy (alors le test reuse ne doit pas s’appuyer sur clear).

**Pourquoi 20K CCU :** leftover N175. 8 clients × despawn ogives (10 Hz snapshot, Destroy immédiat) × `createMissile` (corps + 4 fins + flamme + 3 trails + PointLight). Pas d’autorité (cosmétique monde). `shipFree` **déjà** N175 — ne pas y revenir. Visual V113 Blast **interdit** (fermée sur `1aab`, ne pas merger). **Oubli de kind/slot match** = teinte / silhouette fantôme. **Oubli PointLight** = flamme sans halo. **Si le seul patch est un merger visuel ou un pool partagé avec `shipFree` : ne pas livrer.**

**Worker :**

1. Dans `Overlay.applyUnits` branche `unit.isMissile` **seulement** : **ne plus** `Destroy` le `unit.visual.model`. `Parent = nil` + push `ogiveFree` (nommer **`ogiveFree`**, pas `shipFree` / `missileFree` / `splashFree`). Stocker le `Visual` entier (`model` + `pieces` + `kind` + `isMissile` + rest Transparency/Color + `slot`). Pop O(1) depuis la fin au `trackUnit` insert **missile** **si** `visual.kind == kind` et `visual.slot == slot`. Si vide / mismatch : `UnitModels.createMissile` **une fois** comme aujourd’hui. Au reuse : reset Transparency/Color pieces, Parent `self.root`. **Sauter** navires. Pas de delay (immédiat, comme aujourd’hui). Garde `isMissile` **conservée**.

2. **Garder les silhouettes.** Ne **pas** fusionner ogive / navire. Ne **pas** toucher N175 `shipFree`. Ne **pas** toucher N174 `dismissFree`. Ne **pas** toucher MainMenu. Après N175. Flame Size **non** (N152). HUD **non**. Effects **non**. `BuildingModels` **non**. VictoryScreen **non**. Parent = **`self.root`** obligatoire au reuse. `createMissile` construction **non** retouchée (offsets EngineFlame / Fin / trail **inchangés**, PointLight enfant **inchangé**).

3. Tests « navires, missiles et interpolation » leftover N175 navire **sans** flush **et** leftover N161 splash **et** leftover N160 wake **et** leftover N151 trail **et** leftover N152 flame Size **doivent rester verts** (skip retraite id=1 N56 **obligatoire**, extra missile `rawequal` **avant** despawn **obligatoire**). **Ajouter** si possible : après `applyUnits({}, {})` du check navires (park **immédiat**, **pas** de `testFlushDelays`) snapshot le Visual ogive id=3 (`isMissile`, Parent nil **ou** `#ogiveFree`) ; reuse dans « vagues de conquete » via `applyUnits({}, { { id = …, slot = 1, x, y, tx, ty, kind = 1 } })` : `rawequal` du modèle réparenté **ou** présence dans `ogiveFree`. **Pas** d’assert autre Name, **pas** `#ogiveFree == 1`. Ne **pas** réutiliser l’id=3 encore vivant avant le despawn. Tests « vagues de conquete » leftover N175 / N174 / N167 **doivent rester verts**. Tests « fil de notifications sature » leftover N153 / N167 **sans** flush. Tests « ecran de victoire » leftover N173 **doivent rester verts**. Tests « selection de chaque nation » leftover N171 **et** leftover N172 **doivent rester verts**. Tests « messages rapides » leftover N170 **doivent rester verts**. Tests « calques d'entites, effets et apercu » leftover N169 / N168 / N155 **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client `navires` **et** `vagues de conquete` **doivent rester verts**. Check fil leftover N153 / N167 **sans** flush. Check ecran leftover N173. Check selection leftover N172 / N171. Check messages rapides leftover N170. Check calques leftover N169 / N168. Check navires leftover N152 flame. **Ne pas** casser N175 (`shipFree` snapshot + reuse `rawequal` Parent `overlay.root` **ou** free-list). **Ne pas** casser N174 (`dismissFree`). **Ne pas** casser N173 (`valueFree`). **Ne pas** casser N172 (`previewFree`). **Ne pas** casser N171 (`flagFree`). **Ne pas** casser N170 (`chatFree`). **Ne pas** casser N169 (`self.actionPreview`). **Ne pas** casser N168 (`self.selection`). **Ne pas** casser N167 (`feedFree`). **Ne pas** casser N161 (`splashFree`). **Ne pas** casser N160 (`wakeFree`). **Ne pas** casser N98 extra missile `rawequal`. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `Overlay.luau` (`applyUnits` branche missile **et** `trackUnit` insert missile, helper reuse à côté de `takeShip` — **liste séparée** `ogiveFree`). `tests/client.luau` **seulement** le check « navires, missiles et interpolation » **et/ou** « vagues de conquete » (commentaire leftover N176, **ajouter** snapshot + reuse si possible, **garder** skip retraite id=1 + leftover N175/N161/N160 existants). `HUD.luau` **non**. `VictoryScreen.luau` **non**. `MainMenu.luau` **non**. `Effects.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher flame Size ni Blast ni HUD chat ni `feedFree` ni `Dismiss` ni `clearSelection` ni `clearActionPreview` ni `flagFree` ni `previewFree` ni `valueFree` ni `splashFree` ni `wakeFree` ni `shipFree`. **Ne pas** merger visual V113 (`1aab`). **Ne pas** merger visual V112 (`3ba1`). **Ne pas** merger visual V111 (`9922`).

**Contraintes :** pas de RemoteFunction. **N176 feel ≠ N175 (`shipFree` déjà) ≠ N174 (`Dismiss` déjà) ≠ N173 (`VictoryScreen` `Value` déjà) ≠ N172 (`drawTerrainPreview` déjà) ≠ N171 (`drawFlag` déjà) ≠ N170 (`refreshChatSheet` déjà) ≠ N167 (HUD feed pool déjà) ≠ N161 (LandingSplash déjà) ≠ N160 (LaunchWake déjà) ≠ N152 (flame Size, ne pas freeze V74) ≠ visual V113 (Blast fermée `1aab`, ne pas merger) ≠ visual V112 (Ground/Border fermée `3ba1`, ne pas merger) ≠ Nukes.missileFree (serveur, hors bundle) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N152 dans le même worker. Free-list **`ogiveFree`** — **pas** `shipFree`. **Pas Destroy** des Model ogive au despawn applyUnits. **Pas de parcours de `self.units` hors le despawn existant.** **Reset Transparency / kind+slot match.** Distinct `shipFree` / `dismissFree` / `valueFree` / `previewFree` / `flagFree` / `chatFree` / `feedFree` / `splashFree` / `wakeFree` — **ne pas** partager. Parent `self.root` **obligatoire**. Kind+slot match **obligatoire**. PointLight enfant **obligatoire** inchangé. HUD N174 `dismissFree` **obligatoire** inchangé. `shipFree` N175 **obligatoire** inchangé. `Value` N173 **obligatoire** inchangé. Skip retraite splash N56 **obligatoire** inchangé. Extra missile N98 **obligatoire** inchangé. Delay navire 0.95 s **obligatoire** inchangé. **Si le pool sans kind/slot match ou partagé avec `shipFree` est le seul patch : ne pas livrer N176.**

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; HUD feed → **N167 fait** ; `clearSelection` → **N168 fait** ; `clearActionPreview` → **N169 fait** ; `refreshChatSheet` → **N170 fait** ; `drawFlag` → **N171 fait** ; `drawTerrainPreview` → **N172 fait** ; `Value` → **N173 fait** ; `Dismiss` → **N174 fait** ; navire delay → **N175 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; HUD feed pool → **N167** ; `clearSelection` → **N168** ; `clearActionPreview` → **N169** ; `refreshChatSheet` → **N170** ; `drawFlag` → **N171** ; `drawTerrainPreview` → **N172** ; `Value` → **N173** ; `Dismiss` → **N174** ; Overlay navire delay → **N175** ; Overlay explosion + chantier + fil clos ; Overlay ogive Destroy = **N176**) |
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
| N34–N151, N153–N175 | (voir rapport #227) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–84) |
| N176 | Overlay `applyUnits` missile Destroy immédiat | P3 | **nouveau** (`ogiveFree`, pas `shipFree` / `missileFree`, kind+slot match, Reset Transparency, skip navires, skip `Overlay.clear`, N175 navire **déjà**, **≠** visual V113 fermée `1aab`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 / #169 / #171 / #173 / #176 / #178 / #181 / #183 / #185 / #187 / #189 / #191 / #193 / #195 / #197 / #200 / #202 / #204 / #206 / #208 / #210 / #213 / #214 / #216 / #219 / #221 / #223 / #225 / #227 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N175 `shipFree` pool) |

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

Client : **35/35 OK** — dont `selection de chaque nation et de chaque mode` leftover N171 `flagFree` snapshot Frame `playerFlag` + reuse Parent **ou** free-list + UICorner parent intact + Rotation diagonal→vertical = 0 **et** leftover N172 `previewFree` snapshot Frame `featuredPreview` + reuse Parent **ou** free-list + shade frère UIGradient intact / Nations+GameModes **gardés** ; `salon : la carte en direct` `setLobby` × 4 (refreshFeatured via pool) ; `fil de notifications sature` leftover N153 / leftover N167 commentaire **sans** flush + leftover N174 **sans** flush ; `messages rapides` leftover N170 `chatFree` snapshot + reuse Parent `hud.chatBody` + un `UIGridLayout` + envoi `social_gg` / `attack_target` slot 3 ; `calques d'entites, effets et apercu` leftover N155 reuse / leftover N168 `clearSelection` Parent nil + reselect `effects.root` / leftover N169 `clearActionPreview` Parent nil + re-preview `effects.root` ; `hover spawn isolation` leftover N58 ; `construction du monde 3D` leftover N137/N138 ; `pose et capture de chaque type de batiment` leftover N136 / leftover N132 / leftover N162 commentaire **sans** flush / leftover N166 commentaire **sans** flush / leftover N167 commentaire ; `modeles procéduraux` leftover N150/N149 ; `apercu de placement pour chaque batiment` leftover N129 ; `livraison : le gain s'affiche sur la gare` leftover N159 **sans** flush ; `navires, missiles et interpolation` leftover N151 trail / leftover N152 flame Size / leftover N148 mesh / leftover N160 wake **sans** flush / leftover N161 splash **sans** flush / leftover N163 Shockwave **sans** flush / leftover N164 BlastSmoke **sans** flush / leftover N165 Blast **sans** flush / leftover N175 commentaire **sans** flush, skip retraite id=1 N56 ; `vagues de conquete` N175 `shipFree` reuse (`testFlushDelays` → snapshot Visual `kind==1` `slot==1`, `applyUnits` id=99 `rawequal` Parent `overlay.root` **ou** `#shipFree`) / N174 `dismissFree` reuse (`testFlushDelays` après `hud:notify("n167 reuse")` → snapshot TextButton `Dismiss`, `hud:notify("n174 reuse")` `rawequal` Parent `pooledFeed` **ou** `#dismissFree`) / N167 `feedFree` reuse (`hud:notify` texte nouveau `rawequal` Parent `hud.feed`, Dismiss présent, `# == feedN - 1`) / leftover N166 `BuildRing` reuse / leftover N165 `Blast` reuse / leftover N164 `BlastSmoke` reuse / leftover N163 `Shockwave` reuse / leftover N162 `DeliveryPulse` reuse / leftover N161 `LandingSplash` reuse / leftover N160 `LaunchWake` reuse / leftover N159 `goldPopup` reuse / leftover N158 `floatingText` reuse / leftover N157 `conquestPulse` reuse / leftover N156 `tileFlash` reuse ; `ecran de victoire` leftover N173 `valueFree` snapshot TextLabel `Value` `rows[1]` + reuse Parent row **ou** free-list, deux `show` + `hide` + `setCountdown`. Serveur **non** touché cette passe. `UnitModels.luau` **non** touché. `WorldCamera.luau` **non** touché. HUD **non** touché. BuildingModels **non** touché. Effects **non** touché. MainMenu **non** touché. VictoryScreen **non** touché. Pulse flamme Size **inchangé** (N152). Overlay missiles Destroy immédiat **inchangé** (N176). Overlay despawn navire delay **poolé**. HUD `Dismiss` delay **poolé**. VictoryScreen `Value` **poolé**. MainMenu `drawTerrainPreview` **poolé**. MainMenu `drawFlag` **poolé**. HUD `refreshChatSheet` **poolé**. Stub `Disconnect` **inchangé**.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass84.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N175 est un recycle Model Overlay vérifié par le banc headless (`vagues de conquete` snapshot + reuse Parent `overlay.root` **ou** `shipFree`). Pulse flamme Size **inchangé** (N152). Overlay missiles Destroy immédiat **inchangé** (N176).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N175 n’ajoute **pas** de require (référence locale Overlay `shipFree`). Intro continue de `require` MainMenu pour `drawFlag` (déjà). N152 restera dans `UnitModels.place` flame. N176 restera dans `Overlay.applyUnits` branche missile.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Distinct trail N151. Distinct Overlay N163–N165 **déjà**. Distinct BuildRing N166 **déjà**. Distinct HUD N167 **déjà**. Distinct `clearSelection` N168 **déjà**. Distinct `clearActionPreview` N169 **déjà**. Distinct `refreshChatSheet` N170 **déjà**. Distinct MainMenu `drawFlag` N171 **déjà**. Distinct MainMenu `drawTerrainPreview` N172 **déjà**. Distinct leftover N173 **déjà**. Distinct leftover N174 **déjà**. Distinct leftover N175 **déjà**. Distinct leftover N176. Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N170 : `HUD.refreshChatSheet` seulement. **Pas** Destroy des TextButton. Free-list `chatFree` (pas `feedFree`). **Garder** le `UIGridLayout` (ne pas en recréer un). **Disconnect** `Activated` avant rebranchement (oubli = double-fire, test « messages rapides » rouge). Parent `self.chatBody`. Ne **pas** `Theme.corner` / `Theme.stroke` au reuse. MouseEnter/Leave **conservés**. Dismiss delay parque **déjà** (N174). Distinct N167 `feedFree`. Distinct N169 preview. Distinct visual V103 (ne pas merger `7188`). **Ne pas** flush. **Ne pas** casser N169 ni N168 ni N167 ni N154. Catalogue vs pending **inchangé**. Stub banc : `Disconnect` **doit** retirer le handler (no-op = Fire accumule).

Piège N171 : `MainMenu.drawFlag` seulement. **Pas** Destroy des Frame bandes. Free-list `flagFree` (pas `chatFree`). **Garder** le UICorner du parent (filtre `IsA("Frame")`). **Reset Rotation** (diagonal `-30` vs vertical `0`). Parent = argument `parent` (quatre call sites + Intro). Distinct N170 `chatFree`. Distinct N172 `previewFree`. Distinct visual V107 (ne pas merger `ee95`). **Ne pas** flush. **Ne pas** casser N170 ni N169 ni N168 ni N167. Motifs **inchangés**.

Piège N172 : `MainMenu.drawTerrainPreview` seulement. **Pas** Destroy des Frame tuiles. Free-list `previewFree` (pas `flagFree`). **Ne pas** parcourir la carte / `shade` (frère du preview). **Reset Size / ZIndex**. Parent = argument `frame`. Océan non dessiné. Distinct N171 `flagFree`. Distinct visual V108 (ne pas merger `d46a`). **Ne pas** flush. **Ne pas** casser N171 ni N170 ni N169 ni N168 ni N167. `MapGen.generate` **conservé**.

Piège N173 : `VictoryScreen.show` seulement. **Pas** Destroy des TextLabel `Value`. Free-list `valueFree` (pas `previewFree`). **Garder** `Name = "Value"`. **Reset TextXAlignment = Right**. Parent = `row` (`self.rows[i]`). Early-out Visible **conservé**. Ligne sans item : parker `Value`. Distinct N172 `previewFree`. Distinct visual V110 (fermée `9726`, ne pas merger). **Ne pas** flush. **Ne pas** casser N172 ni N171 ni N170 ni N169 ni N168 ni N167. `hide` **inchangé**.

Piège N174 : `HUD.notify` delay seulement. **Pas** Destroy des TextButton `Dismiss`. Free-list `dismissFree` (pas `feedFree`). **Garder** `Name = "Dismiss"`. **Disconnect** Activated avant rebranchement. Parent = `entry` (le TextLabel). Delay vs clic **distincts** (clic laisse Dismiss enfant). Distinct N173 `valueFree`. Distinct visual V103 (fermée `7188`, ne pas merger). **Ne pas** flush dans « fil de notifications sature ». **Ne pas** casser N173 ni N172 ni N171 ni N170 ni N169 ni N168 ni N167. `removeEntry` **inchangé**. Check vagues `FindFirstChild("Dismiss") ~= nil` **obligatoire**.

Piège N175 : `Overlay.applyUnits` delay navire seulement. **Pas** Destroy des Model navire. Free-list `shipFree` (pas `splashFree`). **Garder** `visual.pieces` / `visual.kind`. **Reset Transparency / Color** au reuse (snapshot à l’insert, pas à Transparency=1). Kind+slot match **obligatoire**. Skip missiles. Skip `Overlay.clear`. Skip retraite splash N56. Distinct N174 `dismissFree`. Distinct visual V112 (fermée `3ba1`, ne pas merger). **Ne pas** flush dans « navires » (reuse dans vagues après despawn flush, id=99 kind=1 slot=1). **Ne pas** casser N174 ni N173 ni N172 ni N171 ni N170 ni N169 ni N168 ni N167 ni N161 ni N160. `trackUnit` insert pop. `createBoat` construction **inchangée**.

Piège N176 (à venir) : `Overlay.applyUnits` branche missile seulement. **Pas** Destroy des Model ogive. Free-list `ogiveFree` (pas `shipFree`, pas `Nukes.missileFree`). **Garder** `visual.pieces` / `visual.kind` / PointLight enfant. **Reset Transparency / Color** au reuse. Kind+slot match **obligatoire**. Skip navires. Skip `Overlay.clear`. Extra `tx`/`ty` sur le record unité, pas le Visual. Distinct N175 `shipFree`. Distinct visual V113 (fermée `1aab`, ne pas merger). **Ne pas** flush dans « navires » (park **immédiat**). **Ne pas** casser N175 ni N174 ni N173 ni N172 ni N171 ni N170 ni N169 ni N168 ni N167 ni N161 ni N160 ni N98. `trackUnit` insert missile pop. `createMissile` construction **inchangée**.
