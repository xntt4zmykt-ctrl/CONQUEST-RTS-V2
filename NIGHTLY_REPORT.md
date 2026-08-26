# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 101)

Déclencheur : ouverture de la **PR #262** (`cursor/analyse-nocturne-du-codebase-573c`) — WorldBuilder.clearDefaultScene recycle (N192), specs N152 / N190 / N2.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-02ab`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#262. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

`init.server` `replicate()` skip UnitSnapshot vide-vide si le dernier envoi était déjà vide (**N2** UnitSnapshot, `lastUnitEmpty`, premier vide **DOIT** fire, reset `startMatch`, `#boats` / `#missiles` après truncate N70/N71, **pas** skip StateDelta). WorldBuilder `clearDefaultScene` leftover Baseplate / SpawnLocation : `Parent = nil` + `studioFree` (**N192**). WorldBuilder `build()` leftover `ConquestCollision` : `collisionFree` / `collisionPartFree` (**N191**). VisualDirector `effect()` leftover class mismatch : `effectFree[ClassName]` (**N189**). … (N163–N192 inchangés hors N2). UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré**). `init.client` leftover ScreenGui stale `child:Destroy` encore (leftover **N190**, Rojo reload, **hors bundle**, Lua state neuf / pools vides → **skip** cette passe).

**N190 non livré :** au reload Rojo le Lua state est **neuf**, `guiFree` / `feedFree` / `veilFree` / `studioFree` sont **vides**. Destroy du stale **est** le contrat Rojo. Spec : si le seul patch est unsafe, **ne pas livrer**.

**N152 non livré :** freeze Size=API = visual V74, interdit. L’API `Size` exige un `Vector3`.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #262 (passe 100) : claims vérifiés.** WorldBuilder.clearDefaultScene leftover Parent=nil, `parkStudioDefault` / `studioFree`, jamais take dans `build()`, skip `Parent == nil`, skip non-Baseplate / non-SpawnLocation, **pas** `collisionPartFree` / `collisionFree`, skip N190, skip VisualDirector N189, skip N191 `build`, `Terrain:Clear()` inchangé. Stub `SpawnLocation` IsA BasePart. Check studio leftover. `WorldBuilder.luau` zéro `:Destroy()`. N152 non livré. N190 skip. Spec N2 **livrée ici** (UnitSnapshot vide-vide seulement). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **branche `d863`** passe 113 Overlay `syncFactoryRoutes` Parent=nil — feel N180 **déjà**, **pas merger**. Visual **branche `737c`** passe 112 Overlay `clear` Parent=nil — feel N179 **déjà**, **pas merger**. Visual **branche `8d07`** passe 111 `applyBuildingDelta` Parent=nil — feel N178 **déjà**, **pas merger**. Ne pas merger visual `d863` / `737c` / `8d07` / `1b6b` / `c6c6` / `f71e` / `a18e` / `a971` / `340e` / `58fe` / `d555` / `3437` / `8cc5` ni hardening `41e2` / `93f6`.

Cette passe a **livré N2 UnitSnapshot** (skip vide-vide, premier vide fire). **N152 non livré**. **N190 non livré**. **N2 StateDelta non livré** (empreinte sans clone = leftover). **Pas de N193 Destroy** : hors `init.client` N190 skip, la chaîne production `:Destroy()` est épuisée.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #262

| Claim #262 | Réalité à l’ouverture |
|---|---|
| WorldBuilder.clearDefaultScene leftover Parent=nil (N192) | Oui. `parkStudioDefault` / `studioFree`, jamais take dans `build()`, skip `Parent == nil`, skip non-Baseplate / non-SpawnLocation, pas `collisionPartFree`. `WorldBuilder.luau` zéro `:Destroy()`. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| N190 skip | Oui. `init.client` `child:Destroy()` ScreenGui stale conservé (hors bundle). |
| Specs N152 / N190 / N2 | **N2 UnitSnapshot livré ici.** N190 **skip**. N152 **laissé ouvert**. N2 StateDelta **laissé ouvert**. |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #262, visuelles #260/`d863` passe 113 syncFactoryRoutes / `737c` passe 112 Overlay.clear / `8d07` passe 111 applyBuildingDelta. **#262 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `d863` / `737c` / `8d07` ni hardening `41e2` / `93f6` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N2 UnitSnapshot est un skip **FireClient** : la sim snapshotte toujours (buffers N70/N71 inchangés). Premier vide après navire **conservé** (contrat Overlay `applyUnits({}, {})`). Risques documentés, non corrigés ici (hors N2 UnitSnapshot) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet ; StateDelta encore fire 10 Hz même inchangé (N2 restant).

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip `rng > 0.12` seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. Aucun bug clair sûr hors N2 UnitSnapshot. Overlay explosion n’a plus de `Destroy`. VisualDirector.effect mismatch **déjà** poolé. WorldBuilder **déjà** N191+N192. UnitModels flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze — **non livré**). `init.client` ScreenGui stale Destroy encore (leftover **N190**, skip). **Plus aucun `:Destroy()` hors `init.client` N190.**

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N2 du rapport #262 (skip UnitSnapshot vide-vide seulement). N152 **non livré**. N190 **non livré**. StateDelta **toujours fire**.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| UnitSnapshot fire 10 Hz même mer vide (N2) | `init.server.luau` (`lastUnitEmpty`, skip si `#boats==0` et `#missiles==0` **et** dernier envoi déjà vide, poser `lastUnitEmpty` **après** chaque envoi, reset `false` au `startMatch`), `tests/simulate.luau` (commentaire contrat `#` N70/N71 ; **garder** truncate 2→1→0 / 1→0→1) | Leftover N192. 8 clients × 10 Hz × tables bateaux+missiles **vides** (lobby + mer calme). Pas d’autorité (skip n’altère pas la sim). **Premier vide DOIT fire** sinon fantôme Overlay. **Pas** skip StateDelta (HUD `hud:update` vit dessus ; gold/troupes bougent en playing). **Pas** comparer l’identité `boatSnapBuf` (muté in-place). `init.server` **hors bundle** — N70/N71 `#==0` est le contrat testable. Flame leftover N152 **alors**. ScreenGui leftover N190 **alors** (skip). **Pas N193 Destroy.** |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), skip StateDelta (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), `init.client` ScreenGui stale Destroy (**N190**, skip), tribus `humanTargetProtected`. VisualDirector N189 **inchangé**. RadialMenu.destroy N188 **inchangé**. Minimap.destroy N187 **inchangé**. PlacementPreview.destroy N186 **inchangé**. WorldRenderer N184/N185 **inchangés**. Overlay **inchangé**. `init.client` **inchangé**. `UnitModels.luau` **non** touché. WorldBuilder **inchangé** (N191/N192). GameState snapshot **inchangé** (N70/N71). `Terrain:Clear()` **inchangé**.

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
              fireDeployed StateDelta toujours,
              snapshotBoats, snapshotMissiles,
              UnitSnapshot skip vide-vide si lastUnitEmpty,
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
- **Réplication :** StateDelta **toujours** / UnitSnapshot skip vide-vide (N2) / BuildingDelta early-out / plunder / trade / explosions / notify&sfx / Diplomacy.viewFor 1 Hz. Playing 10 Hz ; lobby vide et ended → 1 Hz.
- WorldBuilder `clearDefaultScene` leftover poolé (**N192**). WorldBuilder `build` leftover Folder poolé (**N191**). VisualDirector `effect()` mismatch poolé (**N189**). … (N163–N191 inchangés hors N190 skip). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). `init.client` ScreenGui stale Destroy encore (**N190**). N2 restant = skip StateDelta si `ownerDelta == nil` **et** empreinte stats.

---

## 5. Issues worker-ready (N152 restant + N190 skip + N2 StateDelta)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N189**, **N191–N192**, **N2 UnitSnapshot** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N190** skip ici (reload-diverged, hors bundle). **N192** fermé passe 100. **N2 UnitSnapshot** fermé ici. **Pas de N193 Destroy.** Enchaîner **N2 StateDelta skip-si-inchangé**.

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover `init.client` ScreenGui Destroy = **N190** (skip). Leftover StateDelta fire 10 Hz = **N2 restant**. Visual passe 113 syncFactoryRoutes **fermée** sur `d863` (feel N180 **déjà** — ne pas merger). Visual passe 112 Overlay.clear **fermée** sur `737c` (feel N179 **déjà** — ne pas merger). Ne pas merger visual `d863` / `737c` / `8d07` / `1b6b` / `c6c6` / `f71e` / `a18e`.

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N192 (pools Overlay/Effects/BuildingModels/HUD/selection/preview/chat/drapeau/miniature/podium/Dismiss/navire/ogive/`clear` / Ghost / ConquestWorld / rematch destroy / RadialMenu / VisualDirector / WorldBuilder collision **et** Studio defaults **déjà**), N2 UnitSnapshot **déjà**. Distinct de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**.

**Problème :** N2 ferme le skip UnitSnapshot. Reste, **chaque frame** :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (`c0ec` / PR #151). Feel **garde** le pulse Z `sin(time * 18)` **sans** phase spatiale. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. UnitSnapshot **déjà** N2 — ne pas y revenir. **Passes 61–101 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder la ligne actuelle.

2. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N2 StateDelta seulement.** N152 reste alors ouvert. Ne pas inventer un cache Size. **Ne pas inventer un N193 Destroy.**

3. Tests « navires » leftover N151 / N152 **doivent rester verts**. Tests boatSnapBuf N70 / missileSnapBuf N71 **doivent rester verts**. Tests collision leftover N191 **doivent rester verts**. Tests studio leftover N192 **doivent rester verts**. Client **36/36**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Fichiers : `UnitModels.luau` **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `init.server` **non**. WorldBuilder **non**. `init.client` **non**.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ visual V74 (freeze, ne pas merger) ≠ N2 (UnitSnapshot déjà / StateDelta leftover) ≠ N190 (ScreenGui skip) ≠ N192 (clearDefaultScene déjà).** Non réentrant. Pulse Z **conservé**.

---

### ISSUE-N190 — `init.client` leftover ScreenGui stale `child:Destroy` Rojo reload (feel) — SKIP passe 101

**Priorité :** P3 alloc client init. **Non livré passe 101** (Lua state neuf / hors bundle). Distinct de N192 (WorldBuilder Studio **déjà**), de N191 (WorldBuilder collision **déjà**), de N189 (Lighting **déjà**), de N152 (flame Size), de N2 (UnitSnapshot **déjà**). `init.client` lignes ~77–88 : `child:Destroy()` si `Name == "ConquestRTS"` **ou** `FindFirstChild("MainMenu", true)`. `apply()` **unique** hors rematch — **ne pas** l’ajouter. Ne pas toucher `init.server` (N2). Ne pas toucher WorldBuilder (N191/N192). **`init.client` est hors bundle** (`tests/bundle.js` EXCLUDE).

**Problème / piège (inchangé depuis #258) :** au reload, **tous** les modules sont réinstanciés. `veilFree` / `effectFree` / `feedFree` / `collisionFree` / `studioFree` sont **vides**. Les enfants du ScreenGui stale **ne peuvent pas** être take via les pools N167–N192. `Parent = nil` du ScreenGui puis take **sans** strip = `HUD.new` **duplique** l’arbre. Strip `child.Parent = nil` **sans** Destroy = orphelins DataModel. **Destroy du ScreenGui stale EST le contrat Rojo.**

**Pourquoi skip 20K CCU :** leftover N189 documenté. 8 clients × reload Studio. Pas d’autorité. **Oubli de strip** = double HUD. **Park sans take** = fuite. La passe 101 a choisi le skip **sûr** et livré N2 (FireClient mer calme).

**Worker :**

1. Relire le piège Lua state. **Si le seul patch est Parent=nil sans take, un take qui garde les enfants, un strip qui orpheline l’arbre, un `apply()` au rematch, ou un retouch VisualDirector / WorldBuilder / init.server : ne pas livrer N190. Laisser `child:Destroy()`. Livrer N2 StateDelta seulement.** N190 reste ouvert (reload-diverged, comme N152 freeze). **Ne pas inventer un N193 Destroy.**

2. Tests « direction visuelle » leftover N189 **doivent rester verts**. Collision leftover N191 **vert**. Studio leftover N192 **vert**. boatSnapBuf N70 / missileSnapBuf N71 **verts**. Client **36/36**. `./tests/run.sh`. **Pas** de check `init.client` (hors bundle).

3. Fichiers : `init.client.luau` **seulement si** livrable. WorldBuilder **non**. VisualDirector **non**. Overlay **non**. `init.server` **non**. `tests/client.luau` **non**. **Ne pas** merger visual `8d07`.

**Contraintes :** pas de RemoteFunction. **N190 feel ≠ N2 (UnitSnapshot déjà) ≠ N192 (WorldBuilder Studio déjà) ≠ N191 (WorldBuilder collision déjà) ≠ N189 (VisualDirector déjà) ≠ N152 (flame).** Non réentrant. **Ne pas fusionner N190 et N2 StateDelta.**

---

### ISSUE-N2 — skip-si-inchangé StateDelta (P1 restant)

**Priorité :** P1 bandwidth 10 Hz. Leftover explicite après N2 UnitSnapshot (vide-vide **déjà**, payloads StateDelta **encore fire** chaque tick). Distinct de N192 (Studio **déjà**), de N190 (ScreenGui skip), de N152 (flame). `init.server` `replicate()` : `fireDeployed(stateDelta, ownerDelta, stats)` **toujours** ; UnitSnapshot skip vide-vide **déjà**. `flushBuildingDelta` **déjà** early-out nil (ne pas y toucher). `init.client` StateDelta appelle `hud:update(stats, roster)` à chaque lot.

**Problème :** N2 UnitSnapshot épuise le fire mer calme. Reste, **chaque tick playing** (10 Hz × 8 commandants) **et** lobby occupé :

```
fireDeployed(stateDelta, ownerDelta, stats)   -- stats même si ownerDelta nil
```

`BuildingDelta` skip déjà si dirty vide. UnitSnapshot skip déjà si vide-vide répété. StateDelta **non**.

**Piège HUD heartbeat :** `hud:update` vit sur StateDelta. Skip StateDelta avec gold / troupes / tiles / era / fronts qui ont bougé = HUD figé. Ne **pas** skip sur `ownerDelta == nil` seul.

**Piège buffers recyclés :** `statsBuf` / `statsRecPool[slot]` sont **mutés** in-place. Comparer l’identité de table est faux. Empreinte = nombres (pas `table.clone`). Ne pas hasher `buildPrices` (table recyclée N75) ni `attackTargets` (référence live N74) dans cette slice.

**Piège playing :** gold/troupes bougent presque chaque tick → skip StateDelta **rare** en combat. Le gain CCU est surtout **lobby waiting** (économie gelée, `stepOnce` n’appelle pas `state:step`) + écran `ended` 1 Hz déjà.

**Pourquoi 20K CCU :** 8 clients × 10 Hz × table stats même lobby figé. Pas d’autorité (skip n’altère pas la sim). UnitSnapshot **déjà** N2 — ne pas y revenir.

**Worker :**

1. Dans `init.server` `replicate()` seulement : skip StateDelta si `ownerDelta == nil` **et** empreinte inchangée. Empreinte = par slot, dans l’ordre des clés `stats` : `slot`, `troops`, `gold`, `tiles`, `era`, `activeAttacks`, `committedTroops`. Plier en `lastStatsFp` (string concat ou xor-fold **nombres**). Slot qui apparaît / disparaît = mismatch (fire). Reset `lastStatsFp = nil` au `startMatch`. Poser l’empreinte **après** chaque envoi (comme `lastUnitEmpty`). **Ne pas** skip UnitSnapshot (déjà). **Ne pas** skip BuildingDelta (déjà early-out). **Si le seul patch skip StateDelta sans empreinte gold/troops, ou compare `rawequal(stats, lastStats)` : ne pas le livrer.** Lobby waiting sans `ownerDelta` + mêmes 7 nombres → skip. Playing avec gold qui bouge → fire.

2. Tests snapshot bateaux N70 / missiles N71 **doivent rester verts**. Tests collision N191 **verts**. Tests studio N192 **verts**. Client **36/36** (dont HUD `update` / « navires » applyUnits vide retire le modèle). `./tests/run.sh`. 6000 ticks inchangé.

3. Fichiers : `init.server.luau` (`replicate()` + reset `startMatch`). GameState **non** (N70/N71/N76 buffers inchangés). Overlay **non**. HUD **non**. WorldBuilder **non**. `init.client` **non**. **Ne pas** merger visual. **Ne pas inventer un N193 Destroy.**

**Contraintes :** pas de RemoteFunction. **N2 StateDelta ≠ N2 UnitSnapshot (déjà) ≠ N192 (Studio déjà) ≠ N191 (collision déjà) ≠ N190 (ScreenGui skip) ≠ N152 (flame).** Non réentrant. Feel #19 conservé. Instantané vide **après** navire **conservé**. BuildingDelta early-out **conservé**. `lastUnitEmpty` **conservé**.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | **UnitSnapshot vide-vide fait** ; reste skip StateDelta — spec ci-dessus |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; ScreenGui stale = **N190** skip ; flame Size = **N152**) |
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
| N34–N151, N153–N189, N191–N192 | (voir rapport #262) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–101) |
| N190 | `init.client` leftover ScreenGui stale `child:Destroy` Rojo reload | P3 | **ouvert skip** (hors bundle ; Lua state neuf / pools vides ; Destroy = contrat Rojo ; **dernier** `:Destroy()` production) |
| N192 | `WorldBuilder.clearDefaultScene` Baseplate/SpawnLocation Destroy | P3 | **fermé** passe 100 (studioFree, jamais take dans `build`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 … #262 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N192 `studioFree`) |

---

## 7. Preuve tests

`./tests/run.sh` → **exit 0**.

Serveur :

```
seed 7 / 99991 / 31337 / 1234567 : 18 factions, invariants OK
factions : 18
collision leftover : Folder rawequal, Ground recycle, mismatch Part (N191)
studio leftover : Baseplate/Spawn park, skip decoy, pas take build (N192)
boatSnapBuf : 1 carrier + 1 transport, retreating, pas de path (N70)
boatSnapBuf : truncate 2→1→0 (N70)
missileSnapBuf : 1 ogive, tx/ty, pas de progress (N71)
missileSnapBuf : truncate 1→0→1 (N71)
intentions : sequence, idempotence, apply immediat, rate limit OK
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.72
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **36/36 OK** — dont `direction visuelle : reuse et mismatch` leftover N189 **inchangé** ; `menu radial` leftover N188 ; `minimap` leftover N187 ; `apercu de placement` leftover N186 / N183 ; `construction du monde 3D` leftover N185 / N184 / N106 ; `etiquettes de faction` leftover N182 ; `vagues de conquete` leftover N181–N160 ; `pose et capture` leftover N180 / N178 ; `navires` leftover N152 flame Size **inchangé** + `applyUnits({}, {})` retire le modèle (contrat premier vide N2) ; `calques` leftover N169 / N168 / N155. Overlay **non** touché. `UnitModels.luau` **non** touché. FactionLabels **non** touché. WorldRenderer **non** touché. PlacementPreview **non** touché. Minimap **non** touché. RadialMenu **non** touché. HUD **non** touché. BuildingModels **non** touché. Effects **non** touché. MainMenu **non** touché. VictoryScreen **non** touché. VisualDirector **non** touché. `init.client` **non** touché. GameState snapshot **non** touché (N70/N71). Pulse flamme Size **inchangé** (N152). ScreenGui stale Destroy **inchangé** (N190 skip). WorldBuilder **inchangé** (N191/N192). `init.server` UnitSnapshot skip **livré**. Stub `SpawnLocation` **inchangé**. Stub Workspace Instance + `Terrain:Clear` **inchangé**.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass101.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N2 est un skip FireClient vérifié par contrat `#` N70/N71 (truncate → 0) + client « navires » `applyUnits({}, {})` retire le modèle. Pulse flamme Size **inchangé** (N152). `init.client` ScreenGui Destroy **inchangé** (N190). Collision leftover N191 **inchangé**. Studio leftover N192 **inchangé**.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N2 n’ajoute **pas** de require (`lastUnitEmpty` local). WorldBuilder require `Config` + `MapGen` + `GreedyMesh` + `WorldSpace` seulement. Intro continue de `require` MainMenu pour `drawFlag` (déjà). N152 restera dans `UnitModels.place` flame. N190 restera dans `init.client` (hors bundle). N2 StateDelta restera dans `init.server` `replicate()`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N190 (ouvert, skip) : `init.client` ScreenGui stale. **Hors bundle.** Lua state neuf au reload → pools vides, enfants non takeables. **Si take avec enfants / strip orphelin / park sans take : ne pas livrer.** Destroy stale **est** le contrat Rojo. **Dernier** `:Destroy()` production.

Piège N191 (fermé passe 99) : `WorldBuilder.build` Folder. **Pas** Destroy. `collisionFree` (pas `worldFree` client). Park enfants **avant** take. `Terrain:Clear()` conservé.

Piège N192 (fermé passe 100) : `clearDefaultScene` Baseplate / SpawnLocation. **Jamais recréés.** `studioFree` **sans** take dans `build`. **Pas** `collisionPartFree`.

Piège N2 UnitSnapshot (fermé ici) : skip vide-vide seulement. **Premier vide après navire DOIT fire.** `#` après truncate N70/N71. Reset `startMatch`. **Pas** identité de table.

Piège N2 StateDelta (à venir) : skip seulement si `ownerDelta == nil` **et** empreinte 7 nombres. Skip sans empreinte = HUD figé. **Pas N193 Destroy.**
