# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 100)

Déclencheur : ouverture de la **PR #261** (`cursor/analyse-nocturne-du-codebase-39b0`) — WorldBuilder.ConquestCollision recycle (N191), specs N152 / N190 / N192.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-573c`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#261. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

WorldBuilder `clearDefaultScene` leftover Baseplate / SpawnLocation : `Parent = nil` + push `studioFree` (**N192**, jamais take dans `build()`, skip `Parent == nil`, skip non-Baseplate / non-SpawnLocation, **pas** `collisionPartFree` / `collisionFree`, skip `init.client` N190, skip VisualDirector N189, skip WorldBuilder `build` N191, `Terrain:Clear()` **inchangé**). `WorldBuilder.luau` **zéro** `:Destroy()`. WorldBuilder `build()` leftover `ConquestCollision` : `collisionFree` / `collisionPartFree` (**N191**). VisualDirector `effect()` leftover class mismatch : `effectFree[ClassName]` (**N189**). RadialMenu `destroy` leftover `RadialMenu` : `veilFree` (**N188**). … (N163–N191 inchangés). UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). `init.client` leftover ScreenGui stale `child:Destroy` encore (leftover **N190**, Rojo reload, **hors bundle**, Lua state neuf / pools vides → **skip** cette passe, comme N152 freeze).

**N190 non livré :** au reload Rojo le Lua state est **neuf**, `guiFree` / `feedFree` / `veilFree` / `studioFree` sont **vides**, les enfants du ScreenGui stale ne sont pas takeables. `Parent = nil` sans take = fuite. Take avec enfants = double HUD. Strip orphelin = fuite DataModel. Destroy du stale **est** le contrat Rojo. Spec : si le seul patch est unsafe, **ne pas livrer**. Livrer N192 seulement.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #261 (passe 99) : claims vérifiés.** WorldBuilder.build leftover Parent=nil, `parkCollision` / `collisionFree`, take Folder, park enfants `collisionPartFree` **avant** take, leftover non-Folder Parent=nil, skip `Parent == nil`, skip `clearDefaultScene` N192, skip `Terrain:Clear` sémantique, skip VisualDirector, skip `init.client`, skip WorldRenderer `worldFree`. `WorldBuilder.build` zéro `:Destroy()`. N152 non livré (freeze Size=API = visual V74, interdit). N190 skip (Lua state neuf, hors bundle). Stub Workspace Instance + `Terrain:Clear` déjà. **N192 livré ici.** Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **branche `737c`** passe 112 Overlay `clear` Parent=nil — feel N179 **déjà**, **pas merger**. Visual **branche `8d07`** passe 111 `applyBuildingDelta` Parent=nil — feel N178 **déjà**, **pas merger**. Visual **branche `1b6b`** passe 110 `refreshChatSheet` Parent=nil — feel N170 **déjà**, **pas merger**. Ne pas merger visual `737c` / `8d07` / `1b6b` / `c6c6` / `f71e` / `a18e` / `a971` / `340e` / `58fe` / `d555` / `3437` / `8cc5` ni hardening `41e2` / `93f6`.

Cette passe a **livré N192** (ce que #261 a documenté si Parent=nil + pool dédié sans take dans `build`). **N152 non livré**. **N190 non livré** (reload-diverged). **Pas de N193 Destroy** : hors `init.client` N190 skip, la chaîne production `:Destroy()` est épuisée.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #261

| Claim #261 | Réalité à l’ouverture |
|---|---|
| WorldBuilder.build leftover Parent=nil (N191) | Oui. `parkCollision` / `collisionFree`, take Folder, park enfants `collisionPartFree` avant take, leftover non-Folder Parent=nil, chemin match inchangé, skip `Parent == nil`, skip `clearDefaultScene`, skip `init.client`. `WorldBuilder.build` zéro `:Destroy()`. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| N190 skip | Oui. `init.client` `child:Destroy()` ScreenGui stale conservé (hors bundle). |
| Specs N152 / N190 / N192 | **N192 livré ici.** N190 **skip**. N152 **laissé ouvert**. |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #261, visuelles #259/`737c` passe 112 Overlay.clear / #257/`8d07` passe 111 applyBuildingDelta / `1b6b` passe 110 chat. **#261 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `737c` / `8d07` / `1b6b` ni hardening `41e2` / `93f6` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N192 est cosmétique Studio boot (serveur, Baseplate jamais gameplay). Risques documentés, non corrigés ici (hors N192) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet ; StateDelta/UnitSnapshot encore fire 10 Hz même inchangés (N2 restant).

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip `rng > 0.12` seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. Aucun bug clair sûr hors N192. Overlay explosion n’a plus de `Destroy`. VisualDirector.effect mismatch **déjà** poolé. WorldBuilder.build leftover **déjà** poolé. WorldBuilder.clearDefaultScene leftover **poolé**. UnitModels flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze — **non livré**). `init.client` ScreenGui stale Destroy encore (leftover **N190**, skip). **Plus aucun `:Destroy()` hors `init.client` N190.**

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N192 du rapport #261 (pool dédié `studioFree` jamais take dans `build`). N152 **non livré**. N190 **non livré**. Stub `SpawnLocation` → `BasePart` (manquait ; `IsA("SpawnLocation")`).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| WorldBuilder `clearDefaultScene` leftover `child:Destroy` Baseplate / SpawnLocation (N192) | `WorldBuilder.luau` (`clearDefaultScene()` park `studioFree`, skip `Parent == nil`, skip non-Baseplate / non-SpawnLocation, **aucun** take dans `build()`, skip N191 `collisionPartFree`, skip `Terrain:Clear` sémantique, skip VisualDirector, skip `init.client`, skip WorldRenderer), `tests/stubs.luau` (`SpawnLocation` IsA BasePart), `tests/simulate.luau` (check studio leftover N192 ; **garder** N191 rawequal Folder / Ground recycle ; **garder** seuils 1500 blocs / client 9000) | Leftover N191. Boot Studio **une fois** par serveur (≠ N191 O(blocs) chaque match). Impact CCU **négligeable**, mais épuise la chaîne `:Destroy()` production. Pas d’autorité (Baseplate jamais repris). **Skip Parent nil** sinon double-push. **Pool dédié obligatoire** (park dans `collisionPartFree` = dalle 512² take comme Ground). **Aucun take dans `build`** (objets jamais recréés). **Pas ScreenGui** (N190). **Pas `build()` N191**. Cosmétique Studio. Flame leftover N152 **alors**. ScreenGui leftover N190 **alors** (skip). **Pas N193 Destroy.** |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), `init.client` ScreenGui stale Destroy (**N190**, skip), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, tribus `humanTargetProtected`. VisualDirector N189 **inchangé**. RadialMenu.destroy N188 **inchangé**. Minimap.destroy N187 **inchangé**. PlacementPreview.destroy N186 **inchangé**. WorldRenderer N184/N185 **inchangés**. Overlay **inchangé**. `init.client` **inchangé** (`apply()` unique, ScreenGui Destroy conservé). `UnitModels.luau` **non** touché. `WorldBuilder.build` **inchangé** (N191). `Terrain:Clear()` **inchangé**.

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
- WorldBuilder `clearDefaultScene` leftover poolé (**N192**, `studioFree`, jamais take). WorldBuilder `build` leftover Folder poolé (**N191**, `collisionFree` / `collisionPartFree`). VisualDirector `effect()` mismatch poolé (**N189**, `effectFree[className]` / `cloudFree`). RadialMenu.destroy leftover TextButton poolé (**N188**, `veilFree`). … (N163–N191 inchangés hors N190 skip). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). `init.client` ScreenGui stale Destroy encore (**N190**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N190 skip + N2 P1)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N189**, **N191–N192** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N191** fermé passe 99. **N190** skip ici (reload-diverged, hors bundle). **N192** fermé ici. **Pas de N193 Destroy** : hors N190 skip, plus de `:Destroy()` production. Enchaîner **N2 skip-si-inchangé (P1)**.

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover `init.client` ScreenGui Destroy = **N190** (skip passe 100). Leftover WorldBuilder collision Destroy = **N191** (**fermé**). Leftover `clearDefaultScene` = **N192** (**fermé**). Visual passe 112 Overlay.clear **fermée** sur `737c` (feel N179 **déjà** — ne pas merger). Visual passe 111 applyBuildingDelta **fermée** sur `8d07` (feel N178 **déjà** — ne pas merger). Visual passe 110 chat **fermée** sur `1b6b` (feel N170 **déjà** — ne pas merger). Ne pas merger visual `737c` / `8d07` / `1b6b` / `c6c6` / `f71e` / `a18e`.

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N192 (pools Overlay/Effects/BuildingModels/HUD/selection/preview/chat/drapeau/miniature/podium/Dismiss/navire/ogive/`clear` / Ghost / ConquestWorld / rematch destroy / RadialMenu / VisualDirector / WorldBuilder collision **et** Studio defaults **déjà**). Distinct de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**.

**Problème :** N192 ferme le pool Studio. Reste, **chaque frame** :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (`c0ec` / PR #151). Feel **garde** le pulse Z `sin(time * 18)` **sans** phase spatiale. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. WorldBuilder **déjà** N191+N192 — ne pas y revenir. **Passes 61–100 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder la ligne actuelle.

2. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N2 seulement (skip-si-inchangé).** N152 reste alors ouvert. Ne pas inventer un cache Size. **Ne pas inventer un N193 Destroy.**

3. Tests « navires » leftover N151 / N152 **doivent rester verts**. Tests collision leftover N191 **doivent rester verts**. Tests studio leftover N192 **doivent rester verts**. Client **36/36**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Fichiers : `UnitModels.luau` **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. WorldBuilder **non**. `init.client` **non**. VisualDirector **non**.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ visual V74 (freeze, ne pas merger) ≠ N191 (WorldBuilder build déjà) ≠ N190 (ScreenGui skip) ≠ N192 (clearDefaultScene déjà).** Non réentrant. Pulse Z **conservé**.

---

### ISSUE-N190 — `init.client` leftover ScreenGui stale `child:Destroy` Rojo reload (feel) — SKIP passe 100

**Priorité :** P3 alloc client init. **Non livré passe 100** (Lua state neuf / hors bundle). Distinct de N192 (WorldBuilder Studio **déjà**), de N191 (WorldBuilder collision **déjà**), de N189 (Lighting **déjà**), de N152 (flame Size). `init.client` lignes ~77–88 : `child:Destroy()` si `Name == "ConquestRTS"` **ou** `FindFirstChild("MainMenu", true)`. `apply()` **unique** hors rematch — **ne pas** l’ajouter. Ne pas toucher WorldBuilder (N191/N192). Ne pas toucher VisualDirector (N189). **`init.client` est hors bundle** (`tests/bundle.js` EXCLUDE).

**Problème / piège (inchangé depuis #258) :** au reload, **tous** les modules sont réinstanciés. `veilFree` / `effectFree` / `feedFree` / `collisionFree` / `studioFree` sont **vides**. Les enfants du ScreenGui stale **ne peuvent pas** être take via les pools N167–N192. `Parent = nil` du ScreenGui puis take **sans** strip = `HUD.new` **duplique** l’arbre. Strip `child.Parent = nil` **sans** Destroy = orphelins DataModel. **Destroy du ScreenGui stale EST le contrat Rojo.**

**Pourquoi skip 20K CCU :** leftover N189 documenté. 8 clients × reload Studio. Pas d’autorité. **Oubli de strip** = double HUD. **Park sans take** = fuite. La passe 100 a choisi le skip **sûr** et livré N192 (même Lua state serveur, pool dédié jamais take).

**Worker :**

1. Relire le piège Lua state. **Si le seul patch est Parent=nil sans take, un take qui garde les enfants, un strip qui orpheline l’arbre, un `apply()` au rematch, ou un retouch VisualDirector / WorldBuilder : ne pas livrer N190. Laisser `child:Destroy()`. Livrer N2 seulement.** N190 reste ouvert (reload-diverged, comme N152 freeze). **Ne pas inventer un N193 Destroy.**

2. Tests « direction visuelle » leftover N189 **doivent rester verts**. Collision leftover N191 **vert**. Studio leftover N192 **vert**. Client **36/36**. `./tests/run.sh`. **Pas** de check `init.client` (hors bundle).

3. Fichiers : `init.client.luau` **seulement si** livrable. WorldBuilder **non**. VisualDirector **non**. Overlay **non**. `tests/client.luau` **non**. **Ne pas** merger visual `8d07`.

**Contraintes :** pas de RemoteFunction. **N190 feel ≠ N192 (WorldBuilder Studio déjà) ≠ N191 (WorldBuilder collision déjà) ≠ N189 (VisualDirector déjà) ≠ N152 (flame) ≠ visual passe 111 (applyBuildingDelta fermée `8d07`, ne pas merger).** Non réentrant. **Ne pas fusionner N190 et N2.**

---

### ISSUE-N2 — skip-si-inchangé StateDelta / UnitSnapshot (P1 restant)

**Priorité :** P1 bandwidth 10 Hz. Leftover explicite après N72–N76 (buffers recyclés, payloads **encore fire** chaque tick). Distinct de N192 (Studio **déjà**), de N190 (ScreenGui skip), de N152 (flame). `init.server` `replicate()` : `fireDeployed(stateDelta, ownerDelta, stats)` **toujours** ; `fireDeployed(unitSnapshot, boats, missiles)` **toujours**. `flushBuildingDelta` **déjà** early-out nil (ne pas y toucher). `init.client` StateDelta appelle `hud:update(stats, roster)` à chaque lot ; UnitSnapshot `overlay:applyUnits` — **l’instantané vide retire le dernier navire**.

**Problème :** N192 épuise `:Destroy()` production. Reste, **chaque tick playing** (10 Hz × 8 commandants) :

```
fireDeployed(stateDelta, ownerDelta, stats)   -- stats même si ownerDelta nil
fireDeployed(unitSnapshot, boats, missiles)   -- y compris deux listes vides
```

`BuildingDelta` skip déjà si dirty vide. StateDelta/UnitSnapshot **non**. Commentaire vivant : « L'instantane vide est important lui aussi : c'est lui qui retire le dernier navire ».

**Piège premier vide :** skip UnitSnapshot si `boats` et `missiles` vides **et** le dernier envoi était déjà vide. **Le premier tick vide après un navire DOIT fire** (sinon fantôme Overlay). Skip StateDelta seulement si `ownerDelta == nil` **et** empreinte stats inchangée (troops/gold/tiles/era/activeAttacks/committedTroops). Pendant `playing`, gold/troupes bougent presque chaque tick → skip StateDelta **rare** ; le gain CCU est surtout UnitSnapshot mer calme + lobby.

**Piège HUD heartbeat :** `hud:update` vit sur StateDelta. Skip StateDelta avec gold qui a bougé = HUD figé. Ne **pas** skip sur `ownerDelta == nil` seul.

**Piège buffers recyclés :** `boatSnapBuf` / `statsBuf` sont **mutés** in-place. Comparer l’identité de table est faux. Empreinte = counts + ids (bateaux) / tuple numériques (stats). Ne pas `table.clone` le payload.

**Pourquoi 20K CCU :** 8 clients × 10 Hz × tables stats+unités même mer vide. Pas d’autorité (skip n’altère pas la sim). WorldBuilder **déjà** N191+N192 — ne pas y revenir.

**Worker :**

1. Dans `init.server` `replicate()` seulement : skip UnitSnapshot si les deux listes sont vides **et** `lastUnitEmpty == true`. Poser `lastUnitEmpty` après chaque envoi (true ssi n=0 et nMissiles=0). Premier vide → fire. Reset `lastUnitEmpty = false` au `startMatch`. **Ne pas** skip StateDelta dans cette slice si l’empreinte stats n’est pas triviale à poser sans clone. **Si le seul patch skip StateDelta sans empreinte : ne pas le livrer.** Livrer le skip UnitSnapshot vide-vide seulement.

2. Tests snapshot bateaux N70 / missiles N71 **doivent rester verts**. Tests collision N191 **verts**. Tests studio N192 **verts**. Client **36/36** (dont « navires » applyUnits vide retire le modèle). `./tests/run.sh`. 6000 ticks inchangé.

3. Fichiers : `init.server.luau` (`replicate()` + reset `startMatch`). GameState **non** (N70/N71 buffers inchangés). Overlay **non**. WorldBuilder **non**. `init.client` **non**. **Ne pas** merger visual. **Ne pas inventer un N193 Destroy.**

**Contraintes :** pas de RemoteFunction. **N2 ≠ N192 (Studio déjà) ≠ N191 (collision déjà) ≠ N190 (ScreenGui skip) ≠ N152 (flame).** Non réentrant. Feel #19 conservé. Instantané vide **après** navire **conservé**. BuildingDelta early-out **conservé**.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; VisualDirector mismatch → **N189 fait** ; WorldBuilder collision → **N191 fait** ; Studio defaults → **N192 fait** ; reste skip-si-inchangé — spec ci-dessus) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; VisualDirector class mismatch → **N189** ; WorldBuilder collision → **N191** ; Studio defaults → **N192** ; Overlay/RadialMenu/Minimap clos ; ScreenGui stale = **N190** skip) |
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
| N34–N151, N153–N189, N191–N192 | (voir rapport #261) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–100) |
| N190 | `init.client` leftover ScreenGui stale `child:Destroy` Rojo reload | P3 | **ouvert skip** (hors bundle ; Lua state neuf / pools vides ; Destroy = contrat Rojo ; **dernier** `:Destroy()` production) |
| N192 | `WorldBuilder.clearDefaultScene` Baseplate/SpawnLocation Destroy | P3 | **fermé** (studioFree, jamais take dans `build`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 … #261 `NIGHTLY_REPORT.md` historique.

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

Client : **36/36 OK** — dont `direction visuelle : reuse et mismatch` leftover N189 **inchangé** ; `menu radial` leftover N188 ; `minimap` leftover N187 ; `apercu de placement` leftover N186 / N183 ; `construction du monde 3D` leftover N185 / N184 / N106 ; `etiquettes de faction` leftover N182 ; `vagues de conquete` leftover N181–N160 ; `pose et capture` leftover N180 / N178 ; `navires` leftover N152 flame Size **inchangé** ; `calques` leftover N169 / N168 / N155. Client **non** touché cette passe. `UnitModels.luau` **non** touché. Overlay **non** touché. FactionLabels **non** touché. WorldRenderer **non** touché. PlacementPreview **non** touché. Minimap **non** touché. RadialMenu **non** touché. HUD **non** touché. BuildingModels **non** touché. Effects **non** touché. MainMenu **non** touché. VictoryScreen **non** touché. VisualDirector **non** touché. `init.client` **non** touché. Pulse flamme Size **inchangé** (N152). ScreenGui stale Destroy **inchangé** (N190 skip). WorldBuilder.build leftover **inchangé** (N191). WorldBuilder.clearDefaultScene leftover **poolé**. `WorldBuilder.luau` **zéro** `:Destroy()`. Stub `SpawnLocation` **ajouté**. Stub Workspace Instance + `Terrain:Clear` **inchangé**. Stub `FindFirstChildOfClass` **inchangé**. Stub `Disconnect` **inchangé**.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass100.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N192 est un park Baseplate/SpawnLocation vérifié par le banc headless (`studio leftover` N192 : Parent nil, decoy intact, Terrain intact, ConquestCollision intact, `build()` ne take pas Baseplate). Pulse flamme Size **inchangé** (N152). `init.client` ScreenGui Destroy **inchangé** (N190). Collision leftover N191 **inchangé**.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N192 n’ajoute **pas** de require (`parkStudioDefault` local). WorldBuilder require `Config` + `MapGen` + `GreedyMesh` + `WorldSpace` seulement. Intro continue de `require` MainMenu pour `drawFlag` (déjà). N152 restera dans `UnitModels.place` flame. N190 restera dans `init.client` (hors bundle). N2 restera dans `init.server` `replicate()`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N190 (ouvert, skip) : `init.client` ScreenGui stale. **Hors bundle.** Lua state neuf au reload → pools vides, enfants non takeables. **Si take avec enfants / strip orphelin / park sans take : ne pas livrer.** Destroy stale **est** le contrat Rojo. **Dernier** `:Destroy()` production.

Piège N191 (fermé passe 99) : `WorldBuilder.build` Folder. **Pas** Destroy. `collisionFree` (pas `worldFree` client). Park enfants **avant** take. `Terrain:Clear()` conservé. `clearDefaultScene` = **N192 fermé**. **Pas park sans take.** **Pas take sans park enfants.**

Piège N192 (fermé ici) : `clearDefaultScene` Baseplate / SpawnLocation. **Jamais recréés.** `studioFree` **sans** take dans `build`. **Pas** `collisionPartFree` (take Ground recevrait un Baseplate). **Pas Parent=nil sans push.**

Piège N2 (à venir) : skip UnitSnapshot vide-vide seulement. **Premier vide après navire DOIT fire.** Skip StateDelta sans empreinte = HUD figé. **Pas N193 Destroy.**
