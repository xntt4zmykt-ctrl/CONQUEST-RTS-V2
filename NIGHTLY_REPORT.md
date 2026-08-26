# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 78)

Déclencheur : ouverture de la **PR #214** (`cursor/analyse-nocturne-du-codebase-a72c`) — Effects `clearSelection` recycle (N168), specs N152 / N169.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-e839`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#214. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

Effects `clearActionPreview` : `Parent = nil`, garder `self.actionPreview`, nil skip N154, reparent `previewTile` (**N169**). Effects `clearSelection` : `Parent = nil`, garder `self.selection` (**N168**). HUD `notify` : free-list `feedFree` (**N167**). BuildingModels BuildRing : free-list `ringFree` (**N166**). Overlay Blast sphère : free-list `blastFree` (**N165**). Overlay BlastSmoke : free-list `smokeFree` (**N164**). Overlay Shockwave : free-list `shockFree` (**N163**). PointLight reste **enfant** de Blast. UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). HUD `refreshChatSheet` Destroy encore (leftover **N170**, commentaire source : trop simple, **≠** visual, **≠** `feedFree`).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #214 (passe 77) : claims vérifiés.** Effects `clearSelection` Parent=nil, `self.selection` conservé, reparent `selectTile` `self.root` si Parent nil (N168). N155 reuse inter-clics inchangé. `clearActionPreview` Destroy encore au moment de l’ouverture (N169 **livré ici**). **N152 non livré** (freeze Size=API = visual V74, interdit). Spec N169 **livrée ici**. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #209** (`7188`) a **fermé V103** HUD préfixe — feel N153 **déjà**, **pas merger**. Visual **PR #211** (`8bb2`) FactoryOutput/SiloWarning phase rest — feel **déjà** `sin(time)` sans Position, **pas merger**. Visual **PR #212** (`2f2a`) feux navire `offset.X` — feel `sin(time * 3)` lockstep **encore**, **pas merger**. Visual **PR #215** (`35f5`) wake `offset.X` — feel N130/N160 **déjà**, **pas merger**. Visual **6c83** V102 compact — feel N114 **déjà**.

Cette passe a **livré N169** (ce que #214 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #214

| Claim #214 | Réalité à l’ouverture |
|---|---|
| Effects `clearSelection` Parent=nil (N168) | Oui. Un marqueur. `Parent = nil` si encore parenté, pas Destroy, pas `self.selection = nil`. `selectTile` reparent `self.root` si Parent nil **avant** Color / Tween. Name `SelectedTerritory`. N155 reuse inter-clics inchangé. Check calques : `rawequal` + Parent nil + reselect `effects.root`. `clearActionPreview` Destroy encore. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N169 | **N169 livré ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #214, visuelles #39/…/`7188` V103 **fermé** / `8bb2` V104 FactoryOutput / `2f2a` V105 feux navire / `35f5` V106 wake / `6c83` V102 compact. **#214 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `35f5` / `7188` / `8bb2` / `2f2a` / `6c83` / `fce3` / `b7e3` / `adfc` ni hardening `41e2` / `93f6` / `e291` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N169 est cosmétique client (marqueur de hover). Risques documentés, non corrigés ici (hors N169) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip `rng > 0.12` seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N169. Overlay `explosion` n’a plus de `Destroy` (Blast / Shockwave / BlastSmoke tous poolés). BuildingModels `playConstruction` BuildRing **poolé**. HUD `notify` TextLabel **poolé**. Effects `clearSelection` **poolé**. Effects `clearActionPreview` **poolé** (un marqueur, pas de tableau). HUD `refreshChatSheet` Destroy encore (leftover N170). UnitModels `place` flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze Size=API).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N169 du rapport #214. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Effects `clearActionPreview` Destroy+nil chaque sortie de mode (N169) | `Effects.luau` (`clearActionPreview` Parent=nil garder `self.actionPreview`, nil `actionPreviewIndex` / `Valid` / `Color`, `previewTile` reparent `self.root` si Parent nil **après** le skip N154 **avant** Color / Transparency / CFrame / pose des trois champs, N154 skip inter-hovers **inchangé**, `clearSelection` N168 **inchangé**), `tests/client.luau` (check calques leftover N169 : snapshot `previewMarker` **avant** clear, assert `rawequal` + Parent nil + Name + `actionPreviewIndex == nil`, puis re-preview `rawequal` Parent `effects.root` ; N155 `rawequal` 2000→2001 **avant** ; N168 clear/reselect **après**) | Leftover N168. Un seul marqueur — pas de tableau `previewFree`. `Parent = nil` si encore parenté, pas Destroy, pas `self.actionPreview = nil`. **Nil skip N154 obligatoire** sinon hover suivant `return` sur Parent nil. Parent = **`self.root`** (pas `hud.feed`, pas `overlay.root`). Name `ActionPreview` conservé. Cosmétique. Flame leftover N152 **alors**. HUD `refreshChatSheet` leftover N170 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), HUD `refreshChatSheet` Destroy (**N170**), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, PlacementPreview Size rayon (visual V76, feel Size = API), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline** **et** N160 free-list, **pas merger**), tribus `humanTargetProtected`. Overlay / BuildingModels / HUD / UnitModels / WorldCamera / WorldRenderer / serveur **non édités**. Flame **non**. Blast **non**. BlastSmoke **non**. Shockwave **non**. DeliveryPulse **non**. `routePart` **non**. Dismiss `table.remove(index)` **non**. HUD `feedFree` **inchangé**. Destroy du modèle navire **inchangé**. `previewTile` N154 skip **inchangé**. `clearSelection` N168 **inchangé**.

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
- Effects `clearActionPreview` poolé (**N169**, un marqueur). Effects `clearSelection` poolé (**N168**, un marqueur). HUD `notify` free-list (**N167**). BuildingModels BuildRing free-list (**N166**). Overlay Blast sphère free-list (**N165**). Overlay BlastSmoke free-list (**N164**). Overlay Shockwave free-list (**N163**). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). HUD `refreshChatSheet` Destroy encore (**N170**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N170)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N169** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N170** = nouveau. **N169** fermé ici.

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover feel HUD `refreshChatSheet` Destroy+`Instance.new` = **N170** (N167 `feedFree` **déjà**, N153 préfixe **déjà**, N169 `clearActionPreview` **déjà**, Dismiss delay Destroy **conservé**, **≠** visual V103, **≠** Effects `selection` / `actionPreview`). Visual V103 HUD préfixe **fermée** sur `7188` / PR #209 (feel N153 **déjà**, ne pas merger). Visual V104 FactoryOutput **ouverte** sur `8bb2` / PR #211 (feel **déjà** `sin(time)` sans Position — ne pas merger). Visual V105 feux navire **ouverte** sur `2f2a` / PR #212 (feel lockstep `sin(time * 3)` — ne pas merger). Visual V106 wake **ouverte** sur `35f5` / PR #215 (feel N130/N160 **déjà** — ne pas merger). Visual V102 compact préfixe **fermée** sur `6c83` (feel N114 **déjà**). Visual V101 `dirtyHead` **fermée** sur `fce3` (feel N112 **déjà**).

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N169 (pools Overlay/Effects/BuildingModels/HUD/selection/preview **déjà**). Distinct de N151 (trail Transparency), de N163–N169 (pools Overlay explosion / BuildRing / HUD feed / `clearSelection` / `clearActionPreview`), de N170 (`refreshChatSheet`), de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**. Ne pas toucher trail. Ne pas toucher `BuildingModels`. Ne pas toucher Overlay. Ne pas toucher HUD. Ne pas toucher Effects.

**Problème :** N169 ferme le pool `clearActionPreview`. N170 reste ouvert (`refreshChatSheet`). N151 ferme le trail. N153–N168 ferment HUD préfixe / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection`. Reste, **chaque frame** (`UnitModels.place`, 60 Hz, une Part `EngineFlame` par ogive) :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (plus de pulse Size, `c0ec` / PR #151). Feel **garde** le pulse Z. Ne pas porter `c0ec`. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**. Role `"flame"` **inchangé**. Shape `Ball` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. HUD feed **déjà** N167 — ne pas y revenir. `clearSelection` **déjà** N168. `clearActionPreview` **déjà** N169. Blast **déjà** N165. Visual V74 freeze **interdit** (feel ≠ visual). **Passes 61–78 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse `1.8 + math.sin(time * 18) * 0.45`. **Ne pas** geler Size (visual V74 Option A, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)`. XY `0.62` / base `1.8` / freq `18` / amp `0.45` **inchangés**.

2. **Garder le pulse.** Ne **pas** poser Size = API. Ne **pas** « fermer » trail / HUD / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection` / `clearActionPreview` (N151–N169 déjà). Ne **pas** lire `piece.part.Size` (alloc). Ne pas porter visual. Après N169. `BuildingModels` **non**. Overlay **non**. HUD **non**. Effects **non**. `createMissile` construction **non** (taille initiale `Vector3.new(0.62, 0.62, 2.3)` inchangée).

3. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N170 seulement.** N152 reste alors ouvert (feel-diverged vs V74). Ne pas inventer un cache Size. Ne pas skip-si-inchangé (N2, pas ici).

4. Tests « navires, missiles et interpolation » leftover N151 trail **et** leftover N148 mesh **et** leftover N147 Fin **doivent rester verts**. Tests « calques d'entites, effets et apercu » leftover N169 `clearActionPreview` reuse **et** leftover N168 `clearSelection` reuse **et** leftover N155 `rawequal` 2000→2001 **doivent rester verts**. Tests « vagues de conquete » leftover N167 `feedFree` reuse **doivent rester verts**. Tests « messages rapides » leftover N170 **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` flame **seulement**, **un** `elseif`) **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N152. Overlay **non**. **Ne pas** éditer le serveur. **Ne pas** toucher Shockwave ni BlastSmoke ni Blast sphère ni BuildRing ni HUD feed ni `clearSelection` ni `clearActionPreview` ni `refreshChatSheet`.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ N151 (trail Z) ≠ visual V74 (freeze Size=API, ne pas merger) ≠ N163 (Shockwave pool) ≠ N164 (BlastSmoke pool) ≠ N165 (Blast sphère pool) ≠ N166 (BuildRing pool) ≠ N167 (HUD feed pool) ≠ N168 (`clearSelection`) ≠ N169 (`clearActionPreview`) ≠ N170 (`refreshChatSheet`) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N170 dans le même worker. Pulse Z **conservé** — ne pas figer à 1.8. Un `elseif` flame.

---

### ISSUE-N170 — HUD `refreshChatSheet` Destroy+`Instance.new` (feel)

**Priorité :** P3 alloc client HUD. Leftover explicite après N169 (`clearActionPreview` déjà). Distinct de N152 (UnitModels Size), de N167 (`feedFree` notify **déjà**), de N153 (préfixe `feedEntries` **déjà**), de N169 (`clearActionPreview` Parent=nil **déjà**), de N168 (`clearSelection` **déjà**), de visual V103 (préfixe feed — **ne pas merger** `7188`). `HUD.refreshChatSheet` **seulement**. Ne pas toucher Effects (N169 **déjà**). Ne pas toucher HUD `notify` / `feedFree` (N167 **déjà**). Ne pas toucher Dismiss delay `cross:Destroy()` (N167 recréé si Destroy). Ne pas toucher Overlay. Ne pas toucher UnitModels. Ne pas toucher BuildingModels.

**Problème :** N169 ferme le pool `clearActionPreview`. N152 reste ouvert (freeze interdit). N167 recycle le fil `notify`. Reste, **chaque changement d’onglet / désignation de cible / Retour** (`HUD.refreshChatSheet`) :

```
for _, child in self.chatBody:GetChildren() do
    child:Destroy()
end
local grid = Instance.new("UIGridLayout")
-- puis button(self.chatBody, …) → Instance.new("TextButton") + Theme.corner + Theme.stroke + MouseEnter/Leave
```

Le commentaire source (« trop simple pour mériter un recyclage ») est **faux à 20K CCU** : 8 clients × (onglet + cible + retour) × Destroy de **tous** les enfants y compris le `UIGridLayout`, puis `Instance.new` + `Theme.corner` + `Theme.stroke` + deux connexions hover. Distinct de leftover N152 (`Size = Vector3.new` flamme). Distinct de leftover N169 (`self.actionPreview` **déjà** — **ne pas** partager). Distinct de leftover N167 (`feedFree` **déjà** — **ne pas** partager). Catalogue QuickChat **inchangé**. Cooldown local **inchangé**. `sendQuickChat` **inchangé**.

**Piège connexions :** `button()` pose `Activated:Connect` **et** MouseEnter/Leave. Un reuse sans `Disconnect` **double-fire** (test « messages rapides » rouge + spam serveur). Stocker la connexion `Activated` (attribut ou table parallèle) et `Disconnect` avant de rebrancher. MouseEnter/Leave peuvent **rester** (ils lisent `Selected` / `BaseColor`). **Ne pas** rappeler `Theme.corner` / `Theme.stroke` au reuse (comme N167).

**Piège UIGridLayout :** le Destroy actuel tue aussi le layout. **Garder** le `UIGridLayout` (le sauter dans la boucle, ou le créer une fois dans `buildChatSheet`). Un second `UIGridLayout` parenté = double grille, layout cassé, test rouge.

**Piège lookup test :** le check « messages rapides » cherche `child:IsA("TextButton") and child.Text == "Bien joue !"` / `"Attaquez ... !"` / `"Nation3"` puis `Activated:Fire()`. Après reuse, **Text** et **Activated** **doivent** matcher le mode courant (catalogue vs cibles). Leftover bouton d’un onglet précédent encore parenté = faux positif / mauvais envoi.

**Pourquoi 20K CCU :** leftover N167. 8 clients × ouverture fiche chat × Destroy+new de N boutons. Pas d’autorité (cosmétique HUD). `feedFree` **déjà** N167 — ne pas y revenir. `clearActionPreview` **déjà** N169. Visual V103 préfixe **interdit** (ne pas merger `7188`). **Oubli de Disconnect** = double envoi QuickChat (serveur rate-limite, UX cassée). **Oubli de garder UIGridLayout** = Destroy+new du layout à chaque refresh. **Si le seul patch est un merger V103 : ne pas livrer.**

**Worker :**

1. Dans `HUD.refreshChatSheet` seulement : **ne plus** `Destroy` les TextButton. `Parent = nil` + push `chatFree` (nommer **`chatFree`**, pas `feedFree` / `previewFree` / `flashFree`). Pop O(1) depuis la fin. Si vide : `button()` comme aujourd’hui (Theme.corner/stroke **une fois**). Au reuse : reset `Text` / `LayoutOrder` / `TextColor3` / `TextXAlignment` / `BackgroundColor3` depuis `BaseColor` / `AutoButtonColor` **inchangé**. `Parent = self.chatBody` (pas `self.feed`, pas `overlay.root`, pas `effects.root`). **Disconnect** l’ancienne `Activated` puis rebrancher. **Garder** le `UIGridLayout` (ne pas le Destroy, ne pas en recréer un). MouseEnter/Leave **conservés**. `setSelected` des tabs **inchangé**. Catalogue vs pending (Retour + roster) **inchangé**.

2. **Garder les boutons.** Ne **pas** recréer après refresh si `chatFree` a un exemplaire. Ne **pas** poser un Name obligatoire (les tests matchent sur `Text`, pas Name). Ne **pas** toucher N167 `feedFree`. Ne **pas** toucher N169 preview. Ne **pas** toucher Dismiss delay Destroy. Après N169. Flame **non** (N152). Overlay **non**. Effects **non**. `BuildingModels` **non**. Parent = **`self.chatBody`** obligatoire au reuse. **Disconnect Activated** — oubli = double-fire.

3. Tests « messages rapides : catalogue, designation de cible et envoi » **doivent rester verts** (social_gg sans cible, `Attaquez ... !` → pending, Nation3 → `attack_target` slot 3, feuille se referme). **Ajouter** (dans ce check, **sans** `testFlushDelays`) : snapshot un TextButton catalogue **avant** `refreshChatSheet` d’onglet, après refresh d’un **autre** onglet puis retour social, `rawequal` du bouton réparenté `hud.chatBody` **ou** `#chatFree` cohérent — au choix, mais **pas** d’assert Name. Tests « fil de notifications sature » leftover N153/N167 **sans** flush **doivent rester verts**. Tests « calques d'entites, effets et apercu » leftover N169 / N168 / N155 **doivent rester verts**. Tests « vagues de conquete » leftover N167 `feedFree` reuse **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client `messages rapides` **doit rester vert**. **Ne pas** `testFlushDelays` dans ce check. Check calques leftover N169 / N168. Check vagues leftover N167 / N166 / N165. Check notifications leftover N153/N167 sans flush. Check navires leftover N152 flame. **Ne pas** casser N169 (`self.actionPreview` conservé, Parent nil, re-preview `effects.root`). **Ne pas** casser N168 (`self.selection` conservé). **Ne pas** casser N167 (`feedFree` snapshot + reuse `rawequal` Parent `hud.feed`). **Ne pas** casser N154 (skip 2001→2002 **avant** clear). Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `HUD.luau` (`refreshChatSheet` **et** éventuellement helper reuse à côté de `button()`, **pas** `notify`). `tests/client.luau` **seulement** le check messages rapides (commentaire leftover N170, **ajouter** snapshot + reuse si possible, **garder** les asserts envoi). `Effects.luau` **non**. `Overlay.luau` **non**. `BuildingModels.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher flame ni Blast ni BuildRing ni HUD feed ni `clearSelection` ni `clearActionPreview`. **Ne pas** modifier le delay Dismiss. **Ne pas** merger visual V103.

**Contraintes :** pas de RemoteFunction. **N170 feel ≠ N169 (`clearActionPreview` déjà) ≠ N167 (HUD feed pool déjà) ≠ N153 (préfixe feed déjà) ≠ N168 (`clearSelection` déjà) ≠ visual V103 (préfixe, ne pas merger `7188`) ≠ N152 (flame Size, ne pas freeze V74) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N152 dans le même worker. Free-list **`chatFree`** — **pas** `feedFree`. **Pas Destroy** des TextButton. **Pas de second UIGridLayout**. **Disconnect Activated obligatoire.** Distinct `feedFree` / `flashFree` / `selection` / `actionPreview` — **ne pas** partager. Parent `self.chatBody` **obligatoire**. Effects N169 **obligatoire** inchangé. Dismiss delay Destroy **obligatoire** inchangé.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; HUD feed → **N167 fait** ; `clearSelection` → **N168 fait** ; `clearActionPreview` → **N169 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; HUD feed pool → **N167** ; `clearSelection` → **N168** ; `clearActionPreview` → **N169** ; Overlay explosion + chantier + fil clos ; `refreshChatSheet` = **N170**) |
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
| N34–N151, N153–N169 | (voir rapport #214) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–78) |
| N170 | HUD `refreshChatSheet` Destroy+`Instance.new` | P3 | **nouveau** (`chatFree`, garder UIGridLayout, Disconnect Activated, Parent `chatBody`, N167 feed **déjà**, N169 preview **déjà**, Dismiss delay Destroy **conservé**, **≠** visual V103) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 / #169 / #171 / #173 / #176 / #178 / #181 / #183 / #185 / #187 / #189 / #191 / #193 / #195 / #197 / #200 / #202 / #204 / #206 / #208 / #210 / #213 / #214 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N169 `clearActionPreview` pool) |

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

Client : **35/35 OK** — dont `fil de notifications sature` leftover N153 / leftover N167 commentaire **sans** flush ; `calques d'entites, effets et apercu` leftover N155 reuse / leftover N168 `clearSelection` Parent nil + reselect `effects.root` / leftover N169 `clearActionPreview` Parent nil + re-preview `effects.root` ; `hover spawn isolation` leftover N58 ; `construction du monde 3D` leftover N137/N138 ; `pose et capture de chaque type de batiment` leftover N136 / leftover N132 / leftover N162 commentaire **sans** flush / leftover N166 commentaire **sans** flush / leftover N167 commentaire ; `modeles procéduraux` leftover N150/N149 ; `apercu de placement pour chaque batiment` leftover N129 ; `livraison : le gain s'affiche sur la gare` leftover N159 **sans** flush ; `navires, missiles et interpolation` leftover N151 trail / leftover N152 flame Size / leftover N148 mesh / leftover N160 wake **sans** flush / leftover N161 splash **sans** flush / leftover N163 Shockwave **sans** flush / leftover N164 BlastSmoke **sans** flush / leftover N165 Blast **sans** flush, skip retraite id=1 N56 ; `vagues de conquete` N167 `feedFree` reuse (`testFlushDelays` → `#feedFree >= 1` **avant** N160, `hud:notify` texte nouveau `rawequal` Parent `hud.feed`, Dismiss recréé, `# == feedN - 1`) / leftover N166 `BuildRing` reuse / leftover N165 `Blast` reuse / leftover N164 `BlastSmoke` reuse / leftover N163 `Shockwave` reuse / leftover N162 `DeliveryPulse` reuse / leftover N161 `LandingSplash` reuse / leftover N160 `LaunchWake` reuse / leftover N159 `goldPopup` reuse / leftover N158 `floatingText` reuse / leftover N157 `conquestPulse` reuse / leftover N156 `tileFlash` reuse ; `messages rapides` leftover N170 Destroy encore. Serveur **non** touché cette passe. `UnitModels.luau` **non** touché. `WorldCamera.luau` **non** touché. `HUD.luau` **non** touché. `PlacementPreview.luau` **non** touché. Overlay **non** touché. BuildingModels **non** touché. Effects `clearActionPreview` **poolé**. Effects `clearSelection` **inchangé** (N168). Pulse flamme Size **inchangé** (N152). `refreshChatSheet` Destroy **inchangé** (N170).

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass78.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N169 est un recycle Part Effects vérifié par le banc headless (`calques` N154 skip 2001→2002 **avant** clear + Parent nil + re-preview `rawequal` Parent `effects.root` + N168 clear/reselect **après**). Pulse flamme Size **inchangé** (N152). `refreshChatSheet` Destroy **inchangé** (N170).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N169 n’ajoute **pas** de require (référence locale Effects `actionPreview`). N152 restera dans `UnitModels.place` flame. N170 restera dans `HUD.refreshChatSheet`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Distinct trail N151. Distinct Overlay N163–N165 **déjà**. Distinct BuildRing N166 **déjà**. Distinct HUD N167 **déjà**. Distinct `clearSelection` N168 **déjà**. Distinct `clearActionPreview` N169 **déjà**. Distinct `refreshChatSheet` leftover N170. Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N169 : `Effects.clearActionPreview` seulement. **Pas** Destroy. **Pas** `self.actionPreview = nil`. **Nil encore** `actionPreviewIndex` / `Valid` / `Color` (sinon skip N154 `return` sur Parent nil). `previewTile` reparent `self.root` si Parent nil, **après** le skip (le skip ne doit pas matcher). Name `ActionPreview` **conservé**. N154 skip inter-hovers **inchangé**. N168 selection **inchangé**. Distinct HUD leftover N167. Distinct flame leftover N152. Distinct HUD leftover N170. Distinct visual V77 (ne pas merger `185a`). **Snapshotter** `actionPreview` **avant** clear dans le check calques — **fait ici**. **Garder** les asserts N168. **Ne pas** flush. **Ne pas** casser N168 ni N167 ni N154 ni N155. HUD `refreshChatSheet` Destroy **conservé**. Un seul marqueur — **pas** de tableau `previewFree`.

Piège N170 (à venir) : `HUD.refreshChatSheet` seulement. **Pas** Destroy des TextButton. Free-list `chatFree` (pas `feedFree`). **Garder** le `UIGridLayout` (ne pas en recréer un). **Disconnect** `Activated` avant rebranchement (oubli = double-fire, test « messages rapides » rouge). Parent `self.chatBody`. Ne **pas** `Theme.corner` / `Theme.stroke` au reuse. MouseEnter/Leave **conservés**. Dismiss delay Destroy **conservé**. Distinct N167 `feedFree`. Distinct N169 preview. Distinct visual V103 (ne pas merger `7188`). **Ne pas** flush. **Ne pas** casser N169 ni N168 ni N167 ni N154. Catalogue vs pending **inchangé**.
