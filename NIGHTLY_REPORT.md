# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 99)

Déclencheur : ouverture de la **PR #258** (`cursor/analyse-nocturne-du-codebase-01f4`) — VisualDirector.effect class-mismatch recycle (N189), specs N152 / N190 / N191.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-39b0`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#258. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

WorldBuilder `build()` leftover `ConquestCollision` : `Parent = nil` + push `collisionFree` (**N191**, Folder, take n’importe quel Folder, Name `ConquestCollision`, Parent Workspace, enfants Ground / Seabed / murs → `collisionPartFree` **avant** take, leftover non-Folder `Parent = nil`, skip `Parent == nil`, skip `init.client` N190, skip VisualDirector N189, skip WorldRenderer `worldFree` N184, `Terrain:Clear()` **inchangé**, `clearDefaultScene` = leftover **N192**). `WorldBuilder.build` **zéro** `:Destroy()`. VisualDirector `effect()` leftover class mismatch : `effectFree[ClassName]` (**N189**). RadialMenu `destroy` leftover `RadialMenu` : `veilFree` (**N188**). Minimap `destroy` leftover `Minimap` : `panelFree` (**N187**). PlacementPreview `destroy` leftover `Placement` : `placeRootFree` (**N186**). WorldRenderer `destroy` leftover `ConquestWorld` : `worldFree` (**N185**). WorldRenderer `new` leftover `ConquestWorld` : `worldFree` (**N184**). … (N163–N183 inchangés). **`WorldBuilder.build` n’a plus aucun `:Destroy()`.** **`VisualDirector.luau` n’a plus aucun `:Destroy()`.** UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). `init.client` leftover ScreenGui stale `child:Destroy` encore (leftover **N190**, Rojo reload, **hors bundle**, Lua state neuf / pools vides → **skip** cette passe, comme N152 freeze).

**N190 non livré :** au reload Rojo le Lua state est **neuf**, `guiFree` / `feedFree` / `veilFree` sont **vides**, les enfants du ScreenGui stale ne sont pas takeables. `Parent = nil` sans take = fuite. Take avec enfants = double HUD. Strip orphelin = fuite DataModel. Destroy du stale **est** le contrat Rojo. Spec : si le seul patch est unsafe, **ne pas livrer**. Livrer N191 seulement.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #258 (passe 98) : claims vérifiés.** VisualDirector.effect leftover Parent=nil, `parkEffect` / `effectFree[ClassName]`, take du ClassName voulu, chemin match **inchangé**, Clouds leftover non-Clouds → `effectFree` pas `cloudFree`, skip `Parent == nil`, skip RadialMenu N188, skip `init.client` (`apply()` **unique**). `VisualDirector.luau` zéro `:Destroy()`. RadialMenu N188 inchangé. N152 non livré (freeze Size=API = visual V74, interdit). Stub `FindFirstChildOfClass` déjà. **N191 livré ici.** Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **branche `737c`** passe 112 Overlay `clear` Parent=nil — feel N179 **déjà**, **pas merger**. Visual **branche `8d07`** passe 111 `applyBuildingDelta` Parent=nil — feel N178 **déjà**, **pas merger**. Visual **branche `1b6b`** passe 110 `refreshChatSheet` Parent=nil — feel N170 **déjà**, **pas merger**. Ne pas merger visual `737c` / `8d07` / `1b6b` / `c6c6` / `f71e` / `a18e` / `a971` / `340e` / `58fe` / `d555` / `3437` / `8cc5` ni hardening `41e2` / `93f6`.

Cette passe a **livré N191** (ce que #258 a documenté si N190 skip). **N152 non livré**. **N190 non livré** (reload-diverged).

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #258

| Claim #258 | Réalité à l’ouverture |
|---|---|
| VisualDirector.effect leftover Parent=nil (N189) | Oui. `parkEffect` / `effectFree[ClassName]`, take du ClassName voulu, Clouds leftover non-Clouds → `effectFree` pas `cloudFree`, chemin match inchangé, skip `Parent == nil`, skip RadialMenu, skip `init.client`. `VisualDirector.luau` zéro `:Destroy()`. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N190 / N191 | **N191 livré ici.** N190 **skip** (Lua state neuf, hors bundle). N152 **laissé ouvert**. |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #258, visuelles #259/`737c` passe 112 Overlay.clear / #257/`8d07` passe 111 applyBuildingDelta / `1b6b` passe 110 chat. **#258 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `737c` / `8d07` / `1b6b` ni hardening `41e2` / `93f6` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N191 est cosmétique collision invisible (serveur, non cliquable). Risques documentés, non corrigés ici (hors N191) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip `rng > 0.12` seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. Aucun bug clair sûr hors N191. Overlay explosion n’a plus de `Destroy`. VisualDirector.effect mismatch **déjà** poolé. WorldBuilder.build leftover **poolé**. UnitModels flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze — **non livré**). `init.client` ScreenGui stale Destroy encore (leftover **N190**, skip). WorldBuilder `clearDefaultScene` Baseplate Destroy encore (leftover **N192**).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N191 du rapport #258 (si N190 skip). N152 **non livré**. N190 **non livré**. Stub Workspace Instance + `Terrain:Clear` (manquait ; `build()` FindFirstChild / Parent / Terrain).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| WorldBuilder `build()` leftover `existing:Destroy` ConquestCollision (N191) | `WorldBuilder.luau` (`build()` park `collisionFree`, take Folder, park enfants `collisionPartFree` avant take, leftover non-Folder Parent=nil, skip `Parent == nil`, skip `clearDefaultScene` N192, skip `Terrain:Clear` sémantique, skip VisualDirector, skip `init.client`, skip WorldRenderer), `tests/stubs.luau` (Workspace Instance + Terrain:Clear), `tests/simulate.luau` (check collision leftover N191 ; **garder** seuils 1500 blocs / client 9000) | Leftover N189. Nouvelle partie, **même** Lua state serveur → pools module **vivants** (≠ N190 reload). 1 Folder + O(blocs) Parts Destroy à chaque match. Pas d’autorité (collision invisible, CanQuery false). **Skip Parent nil** sinon double-push. **Take Folder obligatoire** (park sans take = fuite). **Park enfants obligatoire** (take sans park = Ground empilés). **Pas `worldFree` client** (N184). **Pas ScreenGui** (N190). **Pas `clearDefaultScene`** (N192). Cosmétique collision. Flame leftover N152 **alors**. ScreenGui leftover N190 **alors** (skip). |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), `init.client` ScreenGui stale Destroy (**N190**, skip), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, tribus `humanTargetProtected`. VisualDirector N189 **inchangé**. RadialMenu.destroy N188 **inchangé**. Minimap.destroy N187 **inchangé**. PlacementPreview.destroy N186 **inchangé**. WorldRenderer N184/N185 **inchangés**. Overlay **inchangé**. `init.client` **inchangé** (`apply()` unique, ScreenGui Destroy conservé). `UnitModels.luau` **non** touché. `clearDefaultScene` **inchangé** (N192).

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
- WorldBuilder `build` leftover Folder poolé (**N191**, `collisionFree` / `collisionPartFree`). VisualDirector `effect()` mismatch poolé (**N189**, `effectFree[className]` / `cloudFree`). RadialMenu.destroy leftover TextButton poolé (**N188**, `veilFree`). … (N163–N190 inchangés hors N190 skip). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). `init.client` ScreenGui stale Destroy encore (**N190**). WorldBuilder `clearDefaultScene` Destroy encore (**N192**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N190 skip + N192)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N189**, **N191** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N189** fermé passe 98. **N190** skip ici (reload-diverged, hors bundle). **N191** fermé ici. **N192** = leftover `WorldBuilder.clearDefaultScene` Baseplate / SpawnLocation `child:Destroy` (jamais recréés, **peut skip** comme N190).

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover `init.client` ScreenGui Destroy = **N190** (skip passe 99). Leftover WorldBuilder collision Destroy = **N191** (**fermé**). Leftover `clearDefaultScene` = **N192**. Visual passe 112 Overlay.clear **fermée** sur `737c` (feel N179 **déjà** — ne pas merger). Visual passe 111 applyBuildingDelta **fermée** sur `8d07` (feel N178 **déjà** — ne pas merger). Visual passe 110 chat **fermée** sur `1b6b` (feel N170 **déjà** — ne pas merger). Ne pas merger visual `737c` / `8d07` / `1b6b` / `c6c6` / `f71e` / `a18e`.

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N191 (pools Overlay/Effects/BuildingModels/HUD/selection/preview/chat/drapeau/miniature/podium/Dismiss/navire/ogive/`clear` / Ghost / ConquestWorld / rematch destroy / RadialMenu / VisualDirector / WorldBuilder collision **déjà**). Distinct de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**.

**Problème :** N191 ferme le pool collision serveur. Reste, **chaque frame** :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (`c0ec` / PR #151). Feel **garde** le pulse Z `sin(time * 18)` **sans** phase spatiale. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. WorldBuilder **déjà** N191 — ne pas y revenir. **Passes 61–99 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder la ligne actuelle.

2. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N192 seulement (ou skip N192 si Destroy Studio est le contrat).** N152 reste alors ouvert. Ne pas inventer un cache Size.

3. Tests « navires » leftover N151 / N152 **doivent rester verts**. Tests collision leftover N191 **doivent rester verts**. Client **36/36**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Fichiers : `UnitModels.luau` **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. WorldBuilder **non**. `init.client` **non**. VisualDirector **non**.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ visual V74 (freeze, ne pas merger) ≠ N191 (WorldBuilder déjà) ≠ N190 (ScreenGui skip) ≠ N192 (clearDefaultScene).** Non réentrant. Pulse Z **conservé**.

---

### ISSUE-N190 — `init.client` leftover ScreenGui stale `child:Destroy` Rojo reload (feel) — SKIP passe 99

**Priorité :** P3 alloc client init. **Non livré passe 99** (Lua state neuf / hors bundle). Distinct de N191 (WorldBuilder **déjà**), de N189 (Lighting **déjà**), de N152 (flame Size). `init.client` lignes ~77–88 : `child:Destroy()` si `Name == "ConquestRTS"` **ou** `FindFirstChild("MainMenu", true)`. `apply()` **unique** hors rematch — **ne pas** l’ajouter. Ne pas toucher WorldBuilder (N191). Ne pas toucher VisualDirector (N189). **`init.client` est hors bundle** (`tests/bundle.js` EXCLUDE).

**Problème / piège (inchangé depuis #258) :** au reload, **tous** les modules sont réinstanciés. `veilFree` / `effectFree` / `feedFree` / `collisionFree` sont **vides**. Les enfants du ScreenGui stale **ne peuvent pas** être take via les pools N167–N191. `Parent = nil` du ScreenGui puis take **sans** strip = `HUD.new` **duplique** l’arbre. Strip `child.Parent = nil` **sans** Destroy = orphelins DataModel. **Destroy du ScreenGui stale EST le contrat Rojo.**

**Pourquoi skip 20K CCU :** leftover N189 documenté. 8 clients × reload Studio. Pas d’autorité. **Oubli de strip** = double HUD. **Park sans take** = fuite. La passe 99 a choisi le skip **sûr** et livré N191 (même Lua state serveur).

**Worker :**

1. Relire le piège Lua state. **Si le seul patch est Parent=nil sans take, un take qui garde les enfants, un strip qui orpheline l’arbre, un `apply()` au rematch, ou un retouch VisualDirector / WorldBuilder : ne pas livrer N190. Laisser `child:Destroy()`. Livrer N192 seulement.** N190 reste ouvert (reload-diverged, comme N152 freeze).

2. Tests « direction visuelle » leftover N189 **doivent rester verts**. Collision leftover N191 **vert**. Client **36/36**. `./tests/run.sh`. **Pas** de check `init.client` (hors bundle).

3. Fichiers : `init.client.luau` **seulement si** livrable. WorldBuilder **non**. VisualDirector **non**. Overlay **non**. `tests/client.luau` **non**. **Ne pas** merger visual `8d07`.

**Contraintes :** pas de RemoteFunction. **N190 feel ≠ N191 (WorldBuilder déjà) ≠ N189 (VisualDirector déjà) ≠ N152 (flame) ≠ N192 (clearDefaultScene) ≠ visual passe 111 (applyBuildingDelta fermée `8d07`, ne pas merger).** Non réentrant. **Ne pas fusionner N190 et N192.**

---

### ISSUE-N192 — `WorldBuilder.clearDefaultScene` leftover Baseplate / SpawnLocation `Destroy` (feel)

**Priorité :** P3 alloc serveur Studio defaults. Leftover explicite après N191 (`WorldBuilder.build` **zéro** `:Destroy()`). Distinct de N191 (Folder collision **déjà**), de N190 (ScreenGui client skip), de N184 (WorldRenderer client **déjà**). `WorldBuilder.clearDefaultScene` : `child:Destroy()` si `Name == "Baseplate"` **ou** `IsA("SpawnLocation")`. `Terrain:Clear()` **inchangé** (N191). `build()` **inchangé** (N191). `init.client` **inchangé** (N190).

**Problème :** N191 ferme le pool collision. Reste, **une fois au boot Studio** :

```
for _, child in Workspace:GetChildren() do
	if child.Name == "Baseplate" or child:IsA("SpawnLocation") then
		child:Destroy()
	end
end
```

`Destroy` tue la dalle Studio + le spawn par défaut. **Jamais recréés** dans CONQUEST (pas de `Instance.new("Baseplate")`, pas de `Instance.new("SpawnLocation")` gameplay — le spawn joueur est `PivotTo` capitale).

**Piège jamais recréé :** `collisionFree` / `collisionPartFree` sont des Parts de collision **recyclées à chaque match**. Un Baseplate parké dans `collisionPartFree` serait take comme Ground → dalle Studio 512² au milieu de la carte. **Ne pas** pousser Baseplate dans `collisionPartFree`. **Ne pas** pousser dans `collisionFree` (Folder).

**Piège Parent=nil sans take :** Baseplate `Parent = nil` sans référence Lua → le collecteur Roblox peut le ramasser, **mais** `Destroy` coupe aussi les connexions et verrouille l’instance. Pour un objet **jamais repris**, Destroy **est** le contrat Studio (comme N190 Destroy stale). **Si le seul patch est Parent=nil sans take : ne pas livrer N192. Laisser `child:Destroy()`.**

**Piège N191 :** ne **pas** retoucher `build()`. Ne **pas** retirer `Terrain:Clear()`. Ne **pas** merger `worldFree` client.

**Pourquoi 20K CCU :** leftover N191. 1 Baseplate + 1 SpawnLocation Destroy **une fois** par serveur, pas par match. Impact CCU **négligeable** vs N191 (O(blocs) chaque match). Documenté pour épuiser la chaîne `:Destroy()` production. Pas d’autorité.

**Worker :**

1. Lire le piège jamais recréé. **Si le seul patch est Parent=nil sans take, un push vers `collisionPartFree` / `collisionFree`, ou un retouch `build()` : ne pas livrer N192. Laisser `child:Destroy()`.** N192 reste alors ouvert (boot-once, comme N190 reload).

2. Si une recette **sûre** existe (pool **dédié** `studioFree` jamais take dans `build`, skip `Parent == nil`, skip non-Baseplate / non-SpawnLocation) : `Parent = nil` + push, **aucun** take dans `build()`. Tests collision leftover N191 **doivent rester verts** (`rawequal` Folder, Ground recycle). Client **36/36**. `./tests/run.sh`. 6000 ticks inchangé.

3. Fichiers : `WorldBuilder.luau` (`clearDefaultScene()` **seulement**). `build()` **non**. `tests/simulate.luau` **seulement** si check Baseplate leftover **sans** casser N191. VisualDirector **non**. `init.client` **non**. WorldRenderer **non**. Overlay **non**. **Ne pas** merger visual `8d07`. **Ne pas** éditer le client.

**Contraintes :** pas de RemoteFunction. **N192 feel ≠ N191 (build déjà) ≠ N190 (ScreenGui skip) ≠ N189 (VisualDirector déjà) ≠ N184 (WorldRenderer client déjà) ≠ N152 (flame).** Non réentrant. **Pas Destroy** seulement si pool dédié **sans** take dans `build`. **Si park sans isolation d’avec `collisionPartFree` : ne pas livrer.** **Si N192 non livrable : ne pas inventer un N193 Destroy. Enchaîner N2 skip-si-inchangé (P1) ou N6 DataStore.**

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; VisualDirector mismatch → **N189 fait** ; WorldBuilder collision → **N191 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; VisualDirector class mismatch → **N189** ; WorldBuilder collision → **N191** ; Overlay/RadialMenu/Minimap clos ; ScreenGui stale = **N190** skip ; clearDefaultScene = **N192**) |
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
| N34–N151, N153–N189, N191 | (voir rapport #258) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–99) |
| N190 | `init.client` leftover ScreenGui stale `child:Destroy` Rojo reload | P3 | **ouvert skip** (hors bundle ; Lua state neuf / pools vides ; Destroy = contrat Rojo) |
| N192 | `WorldBuilder.clearDefaultScene` Baseplate/SpawnLocation Destroy | P3 | **nouveau** (boot-once, jamais recréés ; **peut skip** si Parent=nil sans take ou mix `collisionPartFree` ; alors N2 P1) |

Textes worker-ready N1–N25, N28, N33 : PR #21 … #258 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N191 `collisionFree` Folder) |

---

## 7. Preuve tests

`./tests/run.sh` → **exit 0**.

Serveur :

```
seed 7 / 99991 / 31337 / 1234567 : 18 factions, invariants OK
factions : 18
collision leftover : Folder rawequal, Ground recycle, mismatch Part (N191)
intentions : sequence, idempotence, apply immediat, rate limit OK
stripBuf : rot sous quota, deux camps, tiles vs buffer (N93)
stripTerritory : table.clear in-place, voisin intact (N94)
allyBuf : bot sans pacte, next nil (N91)
validTiles : deux resolve CITY, tile identique (N90)
destroyBuf : leftover A→B, CITY B survit (N89)
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.75
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **36/36 OK** — dont `direction visuelle : reuse et mismatch` leftover N189 **inchangé** ; `menu radial` leftover N188 ; `minimap` leftover N187 ; `apercu de placement` leftover N186 / N183 ; `construction du monde 3D` leftover N185 / N184 / N106 ; `etiquettes de faction` leftover N182 ; `vagues de conquete` leftover N181–N160 ; `pose et capture` leftover N180 / N178 ; `navires` leftover N152 flame Size **inchangé** ; `calques` leftover N169 / N168 / N155. Client **non** touché cette passe. `UnitModels.luau` **non** touché. Overlay **non** touché. FactionLabels **non** touché. WorldRenderer **non** touché. PlacementPreview **non** touché. Minimap **non** touché. RadialMenu **non** touché. HUD **non** touché. BuildingModels **non** touché. Effects **non** touché. MainMenu **non** touché. VictoryScreen **non** touché. VisualDirector **non** touché. `init.client` **non** touché. Pulse flamme Size **inchangé** (N152). ScreenGui stale Destroy **inchangé** (N190 skip). WorldBuilder.build leftover **poolé**. `WorldBuilder.build` **zéro** `:Destroy()`. Stub Workspace Instance + `Terrain:Clear` **ajouté**. Stub `FindFirstChildOfClass` **inchangé**. Stub `Disconnect` **inchangé**.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass99.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N191 est un recycle Folder/Parts collision vérifié par le banc headless (`collision leftover` N191 : deux `build`, `rawequal` Folder, Ground recycle, Part mismatch Parent nil). Pulse flamme Size **inchangé** (N152). `init.client` ScreenGui Destroy **inchangé** (N190).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N191 n’ajoute **pas** de require (`parkCollision` local). WorldBuilder require `Config` + `MapGen` + `GreedyMesh` + `WorldSpace` seulement. Intro continue de `require` MainMenu pour `drawFlag` (déjà). N152 restera dans `UnitModels.place` flame. N190 restera dans `init.client` (hors bundle). N192 restera dans `WorldBuilder.clearDefaultScene` (serveur).

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N190 (ouvert, skip) : `init.client` ScreenGui stale. **Hors bundle.** Lua state neuf au reload → pools vides, enfants non takeables. **Si take avec enfants / strip orphelin / park sans take : ne pas livrer.** Destroy stale **est** le contrat Rojo.

Piège N191 (fermé ici) : `WorldBuilder.build` Folder. **Pas** Destroy. `collisionFree` (pas `worldFree` client). Park enfants **avant** take. `Terrain:Clear()` conservé. `clearDefaultScene` = **N192**. **Pas park sans take.** **Pas take sans park enfants.**

Piège N192 (à venir) : `clearDefaultScene` Baseplate / SpawnLocation. **Jamais recréés.** **Pas** `collisionPartFree` (take Ground recevrait un Baseplate). **Si Parent=nil sans take : ne pas livrer** (Destroy = contrat Studio, comme N190).
