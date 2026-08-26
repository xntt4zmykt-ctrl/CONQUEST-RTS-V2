# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 98)

Déclencheur : ouverture de la **PR #256** (`cursor/analyse-nocturne-du-codebase-913d`) — RadialMenu.destroy veil rematch recycle (N188), specs N152 / N189.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-01f4`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#257. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

VisualDirector `effect()` leftover class mismatch : `Parent = nil` + push `effectFree[ClassName]` réelle (**N189**, map `className` → `{ Instance }`, take du **ClassName voulu**, chemin class match **inchangé**, Clouds leftover hors Clouds → `effectFree` pas `cloudFree`, take `cloudFree` **ou** `Instance.new("Clouds")`, skip `Parent == nil`, skip RadialMenu N188, skip Minimap N187, skip Overlay, skip `init.client` — `apply()` **unique**, **ne pas** l’ajouter au rematch, ScreenGui stale = leftover **N190**). `VisualDirector.luau` **zéro** `:Destroy()`. RadialMenu `destroy` leftover `RadialMenu` : `veilFree` (**N188**). Minimap `destroy` leftover `Minimap` : `panelFree` (**N187**). PlacementPreview `destroy` leftover `Placement` : `placeRootFree` (**N186**). WorldRenderer `destroy` leftover `ConquestWorld` : `worldFree` (**N185**). WorldRenderer `new` leftover `ConquestWorld` : `worldFree` (**N184**). PlacementPreview `setKind` : `ghostFree` (**N183**). FactionLabels `refresh` + `clear` : `labelFree` (**N182**). Overlay `clear` routes : `parkRoute` (**N181**). Overlay `syncFactoryRoutes` : `routeFree` (**N180**). Overlay `clear` bâtiments : `buildingFree` (**N179**). Overlay `applyBuildingDelta` : `buildingFree` (**N178**). Overlay `clear` unités : `shipFree` / `ogiveFree` (**N177**). Overlay despawn ogive : `ogiveFree` (**N176**). Overlay despawn navire : `shipFree` (**N175**). HUD `Dismiss` : `dismissFree` (**N174**). VictoryScreen `Value` : `valueFree` (**N173**). MainMenu miniature : `previewFree` (**N172**). MainMenu drapeau : `flagFree` (**N171**). HUD chat : `chatFree` (**N170**). Effects `clearActionPreview` (**N169**). Effects `clearSelection` (**N168**). HUD feed : `feedFree` (**N167**). BuildingModels BuildRing : `ringFree` (**N166**). Overlay Blast / BlastSmoke / Shockwave : `blastFree` / `smokeFree` / `shockFree` (**N165–N163**). PointLight reste **enfant** de Blast / EngineFlame. **`Overlay.luau` n’a plus aucun `:Destroy()`.** **`FactionLabels.luau` n’a plus aucun `:Destroy()`.** **`PlacementPreview.luau` n’a plus aucun `:Destroy()`.** **`WorldRenderer.luau` n’a plus aucun `:Destroy()`.** **`Minimap.luau` n’a plus aucun `:Destroy()`.** **`RadialMenu.luau` n’a plus aucun `:Destroy()`.** **`VisualDirector.luau` n’a plus aucun `:Destroy()`** (`effect()` N189). UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). `init.client` leftover ScreenGui stale `child:Destroy` encore (leftover **N190**, Rojo reload, **hors bundle**).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #256 (passe 97) : claims vérifiés.** RadialMenu.destroy leftover Parent=nil, `parkVeil(self.veil)`, take `new()`, Ring / Hub `FindFirstChild` reuse, petals leftover `leftoverPetal`, `Activated` **seulement** si pas de leftover, skip `Parent == nil`, skip `init.client` (`radial:destroy()` **absent**), skip Minimap N187, skip PlacementPreview N186, skip WorldRenderer N185, skip Overlay. `RadialMenu.luau` zéro `:Destroy()`. Minimap N187 inchangé. PlacementPreview N186 inchangé. WorldRenderer N185 inchangé. Overlay N181 inchangé. N152 non livré (freeze Size=API = visual V74, interdit). Stub `Disconnect` inchangé. **N189 livré ici.** Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **branche `1b6b`** passe 110 `refreshChatSheet` Parent=nil — feel N170 **déjà**, **pas merger**. Visual **branche `c6c6`** passe 109 `clearActionPreview` Parent=nil — feel N169 **déjà**, **pas merger**. Visual **branche `f71e`** passe 108 `clearSelection` Parent=nil — feel N168 **déjà**, **pas merger**. Ne pas merger visual `1b6b` / `c6c6` / `f71e` / `a18e` / `a971` / `340e` / `58fe` / `d555` / `3437` / `8cc5` / `73e0` / `87c1` / `eaa4` / `057c` / `fb11` / `1aab` / `3ba1` / `9922` ni hardening `41e2` / `93f6`.

Cette passe a **livré N189** (ce que #256 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #256

| Claim #256 | Réalité à l’ouverture |
|---|---|
| RadialMenu.destroy leftover Parent=nil (N188) | Oui. `parkVeil(self.veil)`, take `new()`, Ring / Hub `FindFirstChild` reuse, petals leftover `leftoverPetal`, `Activated` **seulement** si pas de leftover, skip `Parent == nil`, skip `init.client`, skip Minimap, skip PlacementPreview, skip WorldRenderer, skip Overlay. `RadialMenu.luau` zéro `:Destroy()`. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N189 | **N189 livré ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #256, visuelles #257/`1b6b` passe 110 chat / `c6c6` passe 109 clearActionPreview / `f71e` passe 108 clearSelection / `a18e` passe 107 selectTile / `a971` passe 106 HUD feed / `340e` passe 105 BuildRing / `58fe` passe 104 conquestPulse / `d555` passe 103 tileFlash / `3437` V120 floatingText / `8cc5` V119 goldPopup. **#256 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `1b6b` / `c6c6` / `f71e` / `a18e` / `a971` / `340e` / `58fe` / `d555` / `3437` / `8cc5` ni hardening `41e2` / `93f6` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N189 est cosmétique éclairage (Lighting / Terrain leftover). Risques documentés, non corrigés ici (hors N189) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip `rng > 0.12` seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. Aucun bug clair sûr hors N189. Overlay explosion n’a plus de `Destroy`. RadialMenu.destroy rematch **poolé**. VisualDirector.effect mismatch **poolé**. UnitModels flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze — **non livré**). `init.client` ScreenGui stale Destroy encore (leftover **N190**). WorldBuilder `ConquestCollision:Destroy` encore (leftover **N191**, serveur).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N189 du rapport #256. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer). Stub `FindFirstChildOfClass` ajouté (manquait ; `apply()` Terrain + WorldCamera Humanoid).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| VisualDirector `effect()` leftover `existing:Destroy` class mismatch (N189) | `VisualDirector.luau` (`effect()` park `effectFree[ClassName]`, take du ClassName voulu, Clouds `parkCloudsLeftover` + `cloudFree`, chemin match inchangé, skip RadialMenu, skip Minimap, skip Overlay, skip `init.client`), `tests/guistubs.luau` (`FindFirstChildOfClass`), `tests/client.luau` (check « direction visuelle » leftover N189 ; **garder** `menu:destroy()` existant, **sans** extra `RadialMenu.new`) | Leftover N188. Rojo / Play Solo enfant Lighting homonyme mauvaise classe → `Destroy` + `Instance.new`. 8 clients. Pas d’autorité (éclairage). **Skip Parent nil** sinon double-push. **Take ClassName voulu obligatoire** (park sans take = fuite). **Pas park du match** (Bloom empilé). **Pas `apply()` au rematch** (`apply()` unique). **Pas RadialMenu** (N188). **Pas ScreenGui** (N190). Clouds leftover Part → `effectFree["Part"]` **pas** `cloudFree` (sinon take Clouds recevrait un Part). Cosmétique. Flame leftover N152 **alors**. ScreenGui leftover N190 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), `init.client` ScreenGui stale Destroy (**N190**), WorldBuilder `ConquestCollision:Destroy` (**N191**), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, tribus `humanTargetProtected`. RadialMenu.destroy N188 **inchangé**. Minimap.destroy N187 **inchangé**. PlacementPreview.destroy N186 **inchangé**. WorldRenderer N184/N185 **inchangés**. Overlay **inchangé**. `init.client` **inchangé** (`apply()` unique, ScreenGui Destroy conservé). `UnitModels.luau` **non** touché.

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
- VisualDirector `effect()` mismatch poolé (**N189**, `effectFree[className]` / `cloudFree`). RadialMenu.destroy leftover TextButton poolé (**N188**, `veilFree`). Minimap.destroy leftover Frame poolé (**N187**, `panelFree`). … (N163–N186 inchangés). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). `init.client` ScreenGui stale Destroy encore (**N190**). WorldBuilder `ConquestCollision:Destroy` encore (**N191**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N190 / N191)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N189** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N189** fermé ici. **N190** = leftover `init.client` ScreenGui stale `child:Destroy` Rojo reload (`guiFree` ScreenGui, **hors bundle**, Lua state neuf → **piège livrabilité**, skip VisualDirector N189). **N191** = leftover serveur `WorldBuilder.build` `ConquestCollision:Destroy` (recette N184, même Lua state, livrable si N190 skip).

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover `init.client` ScreenGui Destroy = **N190**. Leftover WorldBuilder collision Destroy = **N191**. Visual passe 110 chat **fermée** sur `1b6b` (feel N170 **déjà** — ne pas merger). Visual passe 109 clearActionPreview **fermée** sur `c6c6` (feel N169 **déjà** — ne pas merger). Ne pas merger visual `1b6b` / `c6c6` / `f71e` / `a18e` / `a971` / `340e` / `58fe` / `d555` / `3437` / `8cc5`.

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N189 (pools Overlay/Effects/BuildingModels/HUD/selection/preview/chat/drapeau/miniature/podium/Dismiss/navire/ogive/`clear` / Ghost / ConquestWorld / rematch destroy / RadialMenu / VisualDirector **déjà**). Distinct de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**.

**Problème :** N189 ferme le pool mismatch Lighting. Reste, **chaque frame** :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (`c0ec` / PR #151). Feel **garde** le pulse Z `sin(time * 18)` **sans** phase spatiale. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. VisualDirector **déjà** N189 — ne pas y revenir. **Passes 61–98 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder la ligne actuelle.

2. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N190 ou N191 seulement.** N152 reste alors ouvert. Ne pas inventer un cache Size.

3. Tests « navires » leftover N151 / N152 **doivent rester verts**. Tests « direction visuelle » leftover N189 **doivent rester verts**. Client **36/36**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Fichiers : `UnitModels.luau` **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. VisualDirector **non**. `init.client` **non**. WorldBuilder **non**.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ visual V74 (freeze, ne pas merger) ≠ N189 (VisualDirector déjà) ≠ N190 (ScreenGui) ≠ N191 (WorldBuilder).** Non réentrant. Pulse Z **conservé**.

---

### ISSUE-N190 — `init.client` leftover ScreenGui stale `child:Destroy` Rojo reload (feel)

**Priorité :** P3 alloc client init. Leftover explicite après N189 (`VisualDirector.luau` **zéro** `:Destroy()`). Distinct de N189 (Lighting mismatch **déjà**), de N188 (RadialMenu.destroy **déjà**), de N152 (flame Size). `init.client` lignes ~77–88 : `child:Destroy()` si `Name == "ConquestRTS"` **ou** `FindFirstChild("MainMenu", true)`. `apply()` **unique** hors rematch — **ne pas** l’ajouter. Ne pas toucher VisualDirector (N189). Ne pas toucher RadialMenu (N188). Ne pas toucher Overlay. Ne pas retoucher `effectFree`. **`init.client` est hors bundle** (`tests/bundle.js` EXCLUDE).

**Problème :** N189 ferme le pool Lighting. `StarterPlayerScripts/Client/*.luau` n’a plus de `Destroy` **sauf** `init.client` :

```
for _, child in playerGui:GetChildren() do
	if not child:IsA("ScreenGui") then
		continue
	end
	local hasOldMenu = child.Name == "ConquestRTS" or child:FindFirstChild("MainMenu", true) ~= nil
	if hasOldMenu then
		warn(`[CONQUEST UI] removing stale interface {child:GetFullName()}`)
		child:Destroy()
	end
end
local screenGui = Instance.new("ScreenGui")
```

Rojo / Play Solo relance le LocalScript ; l’ancien `ConquestRTS` reste dans `PlayerGui`. `Destroy` tue l’arbre HUD/menu/intro/victory/radial.

**Piège Lua state neuf :** au reload, **tous** les modules sont réinstanciés. `veilFree` / `effectFree` / `feedFree` sont **vides**. Les enfants du ScreenGui stale **ne peuvent pas** être take via les pools N167–N188. `Parent = nil` du ScreenGui puis take **sans** strip = `HUD.new` **duplique** l’arbre. Strip `child.Parent = nil` **sans** Destroy = orphelins DataModel (fuite nette vs Destroy). **Destroy du ScreenGui stale EST le contrat Rojo** (Lua state neuf, pools vides).

**Piège hors bundle :** `init.client` n’est **pas** dans le banc. `__require("init.client")` impossible. **Ne pas** extraire un helper juste pour le test. `FindFirstChild(name, true)` récursif : le stub ignore le 2e arg — ne pas s’en servir comme preuve.

**Piège apply() :** `VisualDirector.apply()` **unique** ligne ~160. **Ne pas** l’ajouter au rematch MapInit. ScreenGui ≠ Lighting.

**Pourquoi 20K CCU :** leftover N189. 8 clients × reload Studio. Pas d’autorité. VisualDirector **déjà** N189. **Oubli de strip** = double HUD. **Park sans take** = fuite. **Take avec enfants** = double construction.

**Worker :**

1. Lire le piège Lua state. **Si le seul patch est Parent=nil sans take, un take qui garde les enfants, un strip qui orpheline l’arbre, un `apply()` au rematch, ou un retouch VisualDirector : ne pas livrer N190. Laisser `child:Destroy()`. Livrer N191 seulement.** N190 reste alors ouvert (reload-diverged, comme N152 freeze).

2. Si une recette **sûre** existe (même run, take ScreenGui **vide**, enfants déjà `destroy()` via N186/N187 **avant** — ce n’est **pas** le chemin Rojo reload) : `guiFree` `{ ScreenGui }`, skip `Parent == nil`, skip non-ScreenGui, take **avant** `Instance.new`, Name `ConquestRTS`, Parent `playerGui`. **Pas** VisualDirector. **Pas** RadialMenu. Warn `GetFullName` **conservé**.

3. Tests « direction visuelle » leftover N189 **doivent rester verts**. Tests « menu radial » leftover N188 **garder** `menu:destroy()`. Client **36/36**. `./tests/run.sh`. **Pas** de check `init.client` (hors bundle).

4. Fichiers : `init.client.luau` **seulement si** livrable. VisualDirector **non**. RadialMenu **non**. Overlay **non**. WorldBuilder **non**. `tests/client.luau` **non** (hors bundle). **Ne pas** merger visual `1b6b` (passe 110 chat = feel N170 **déjà**).

**Contraintes :** pas de RemoteFunction. **N190 feel ≠ N189 (VisualDirector déjà) ≠ N188 (RadialMenu déjà) ≠ N152 (flame) ≠ N191 (WorldBuilder serveur) ≠ visual passe 110 (chat fermée `1b6b`, ne pas merger).** Non réentrant. **Si N190 non livrable : livrer N191. Ne pas fusionner N190 et N191.**

---

### ISSUE-N191 — WorldBuilder `build` leftover `ConquestCollision:Destroy` (feel)

**Priorité :** P3 alloc serveur collision. Leftover explicite si N190 skip (dernier `:Destroy()` **client** = init.client ; dernier `:Destroy()` **serveur** hors tests = `WorldBuilder`). Distinct de N190 (ScreenGui client), de N189 (Lighting client), de N184 (WorldRenderer **client** `ConquestWorld` Folder **déjà**). Recette analogique N184 (`worldFree` Folder) **sans** merger visual. `WorldBuilder.build` `existing:Destroy()` si `FindFirstChild("ConquestCollision")`. `WorldBuilder.clearDefaultScene` Baseplate/SpawnLocation Destroy = **N192**, pas ici. `Workspace.Terrain:Clear()` **inchangé**.

**Problème :** N189/N188 ferment le client. Reste, **chaque rebuild collision** (nouvelle partie, même Lua state serveur) :

```
local existing = Workspace:FindFirstChild("ConquestCollision")
if existing then
	existing:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "ConquestCollision"
```

`Destroy` du Folder tue N Ground + 4 murs. `new()` peut take. Distinct leftover N184 (client `ConquestWorld`, **déjà**). Distinct leftover N190 (client ScreenGui).

**Piège liste :** `collisionFree` `{ Folder }` **nouveau**, **pas** `worldFree` (client), **pas** `effectFree`, **pas** `guiFree`. Take **avant** `Instance.new`. Skip `Parent == nil`. Skip `ClassName ~= "Folder"`.

**Piège enfants :** leftover Ground / murs. Recette N184 `parkWorldChildren` : park Ground → pool parts (nouveau `collisionPartFree`, pas `chunkGround` client N106), leftover autre `Parent = nil`. **Take Folder sans park enfants = leftover Ground empilés + nouveaux blocs.** **Si park Folder sans take : ne pas livrer (fuite).** **Si take sans park enfants : ne pas livrer.**

**Piège Terrain:Clear :** `Workspace.Terrain:Clear()` **conservé** (SmoothTerrain partie précédente). Ne pas le retirer. Ne pas le pooler.

**Piège clearDefaultScene :** Baseplate / SpawnLocation Destroy = **N192**. **Ne pas** y toucher.

**Piège client :** WorldRenderer N184/N185 **inchangés**. Pas merger `worldFree`. Visual **non**.

**Pourquoi 20K CCU :** leftover client Destroy **épuisé** hors N190 non livrable. 1 Folder + O(blocs) Parts Destroy à chaque match. Même process serveur, pools module **vivants** (≠ N190 reload). Pas d’autorité (collision invisible). **Oubli de park enfants** = Parts fantômes CanCollide. **Park sans take** = fuite Folder.

**Worker :**

1. Dans `WorldBuilder.build` : **ne plus** `Destroy` le leftover Folder. `Parent = nil` + push `collisionFree`, skip `Parent == nil`, skip non-Folder. Park enfants Ground/murs **avant** take. Puis take `collisionFree` **ou** `Instance.new("Folder")`. Name `ConquestCollision`. `Terrain:Clear()` **inchangé**. `clearDefaultScene` **inchangé**. VisualDirector **inchangé**. `init.client` **inchangé**.

2. **Garder le marqueur.** Ne **pas** fusionner avec `worldFree` client. Ne **pas** livrer N190 dans le même worker. Après N189. Flame **non**. Overlay **non**.

3. Tests serveur collision (`cout du monde 3D` / `collision serveur : N blocs`) **doivent rester verts**. Client **36/36** inchangé (WorldBuilder est dans le bundle **serveur**). `./tests/run.sh`. 6000 ticks inchangé. Si check leftover N191 : deux `WorldBuilder.build`, `rawequal` Folder **ou** leftover Parent nil + take.

4. Fichiers : `WorldBuilder.luau` (`build()` leftover park + take, park enfants, pas `clearDefaultScene`, pas Terrain:Clear sémantique). `tests/simulate.luau` **seulement** si check collision leftover. VisualDirector **non**. `init.client` **non**. WorldRenderer **non**. Overlay **non**. **Ne pas** merger visual `1b6b`. **Ne pas** éditer le client.

**Contraintes :** pas de RemoteFunction. **N191 feel ≠ N190 (ScreenGui client) ≠ N189 (VisualDirector déjà) ≠ N184 (WorldRenderer client déjà) ≠ N152 (flame) ≠ N192 (`clearDefaultScene` Baseplate, alors).** Non réentrant. **Pas Destroy** du Folder leftover. **Skip Parent nil.** Take Folder **obligatoire**. Park enfants **obligatoire**. **Si park sans take ou take sans park enfants : ne pas livrer N191.**

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; VisualDirector mismatch → **N189 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; VisualDirector class mismatch → **N189** ; Overlay/RadialMenu/Minimap clos ; ScreenGui stale = **N190** ; WorldBuilder collision = **N191**) |
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
| N34–N151, N153–N189 | (voir rapport #256) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–98) |
| N190 | `init.client` leftover ScreenGui stale `child:Destroy` Rojo reload | P3 | **nouveau** (hors bundle ; Lua state neuf / pools vides → **peut être non livrable**, comme N152 ; si skip → N191) |
| N191 | WorldBuilder `build` leftover `ConquestCollision:Destroy` | P3 | **nouveau livrable** si N190 skip (recette N184, `collisionFree` Folder, park enfants, pas `clearDefaultScene` = N192, pas `worldFree` client) |
| N192 | `WorldBuilder.clearDefaultScene` Baseplate/SpawnLocation Destroy | P3 | alors (après N191) |

Textes worker-ready N1–N25, N28, N33 : PR #21 … #256 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N189 `effectFree` mismatch) |

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

Client : **36/36 OK** — dont **nouveau** `direction visuelle : reuse et mismatch` leftover N189 (`apply()` × 2 `rawequal` Atmosphere, Frame `ConquestBloom` Parent nil, take `BloomEffect` leftover, Part `ConquestClouds` Parent nil + Clouds `rawequal`) ; `menu radial` leftover N188 commentaire **sans** extra `new()` + `destroy()` existant **gardé** ; `minimap` leftover N187 ; `apercu de placement` leftover N186 / N183 ; `construction du monde 3D` leftover N185 / N184 / N106 ; `etiquettes de faction` leftover N182 ; `vagues de conquete` leftover N181–N160 ; `pose et capture` leftover N180 / N178 ; `navires` leftover N152 flame Size **inchangé** ; `calques` leftover N169 / N168 / N155. Serveur **non** touché cette passe (hors stub client `FindFirstChildOfClass`). `UnitModels.luau` **non** touché. Overlay **non** touché. FactionLabels **non** touché. WorldRenderer **non** touché. PlacementPreview **non** touché. Minimap **non** touché. RadialMenu **non** touché. HUD **non** touché. BuildingModels **non** touché. Effects **non** touché. MainMenu **non** touché. VictoryScreen **non** touché. `init.client` **non** touché. WorldBuilder **non** touché. Pulse flamme Size **inchangé** (N152). ScreenGui stale Destroy **inchangé** (N190). VisualDirector.effect mismatch **poolé**. `VisualDirector.luau` **zéro** `:Destroy()`. Stub `FindFirstChildOfClass` **ajouté**. Stub `Disconnect` **inchangé**.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass98.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N189 est un recycle Lighting/Terrain class mismatch vérifié par le banc headless (`direction visuelle` leftover N189). Pulse flamme Size **inchangé** (N152). `init.client` ScreenGui Destroy **inchangé** (N190).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N189 n’ajoute **pas** de require (`parkEffect` local). VisualDirector ne require que Lighting / Workspace. Intro continue de `require` MainMenu pour `drawFlag` (déjà). N152 restera dans `UnitModels.place` flame. N190 restera dans `init.client` (hors bundle). N191 restera dans `WorldBuilder.build` (serveur).

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N189 : `VisualDirector.effect` mismatch + Clouds. **Pas** Destroy du mismatch. Free-list `effectFree[className]` (pas `veilFree`). Take du **ClassName voulu**. Chemin class match **inchangé**. Clouds leftover non-Clouds → `effectFree` **pas** `cloudFree`. Skip `Parent == nil`. Skip `init.client` (`apply()` **unique**). Skip RadialMenu N188. Skip ScreenGui stale (**N190**). **Ne pas** vider `effectFree`. **Si park sans take : ne pas livrer.** **Si park du match : ne pas livrer.**

Piège N190 (à venir) : `init.client` ScreenGui stale. **Hors bundle.** Lua state neuf au reload → pools vides, enfants non takeables. **Si take avec enfants / strip orphelin / park sans take : ne pas livrer.** Destroy stale **peut rester** le contrat Rojo. Alors livrer **N191**.

Piège N191 (à venir) : `WorldBuilder.build` Folder. **Pas** Destroy. `collisionFree` (pas `worldFree` client). Park enfants **avant** take. `Terrain:Clear()` conservé. `clearDefaultScene` = **N192**. **Si park sans take ou take sans park enfants : ne pas livrer.**
