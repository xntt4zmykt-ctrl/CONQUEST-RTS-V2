# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 75)

Déclencheur : ouverture de la **PR #208** (`cursor/analyse-nocturne-du-codebase-6512`) — Overlay Blast sphère free-list (N165), specs N152 / N166.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-90f0`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#208. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

BuildingModels BuildRing : free-list `ringFree` (**N166**). Overlay Blast sphère : free-list `blastFree` (**N165**). Overlay BlastSmoke : free-list `smokeFree` (**N164**). Overlay Shockwave : free-list `shockFree` (**N163**). PointLight reste **enfant** de Blast. UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). HUD `notify` TextLabel Instance.new+Destroy (leftover **N167**, N153 préfixe **déjà**, Dismiss `table.remove(index)` **conservé**, **≠** visual V103 préfixe — **fermé** sur `7188` / PR #207, **pas merger**).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #208 (passe 74) : claims vérifiés.** Overlay Blast sphère free-list (N165, `blastFree` pop O(1), `Parent = nil` + push si encore parenté, pas Destroy, Name `Blast` conservé, Size `(4, 4, 4)` + Transparency `0.15` + Color + CFrame avant Tween, PointLight enfant `FindFirstChildWhichIsA`). **N152 non livré** (freeze Size=API = visual V74, interdit). Spec N166 **livrée ici**. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #207** (`7188`) a **fermé V103** HUD préfixe — feel N153 **déjà**, **pas merger**. Visual **6c83** V102 compact — feel N114 **déjà**. Visual **fce3** V101 `dirtyHead` — feel N112 **déjà**.

Cette passe a **livré N166** (ce que #208 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #208

| Claim #208 | Réalité à l’ouverture |
|---|---|
| Overlay Blast sphère free-list (N165) | Oui. `blastFree` pop O(1). `Parent = nil` + push si encore parenté, pas Destroy. Name `Blast`. Reset Size `(4, 4, 4)` + Transparency `0.15` + Color + CFrame avant Tween. PointLight enfant. BlastSmoke N164 / Shockwave N163 inchangés. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N166 | **N166 livré ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #208, visuelles #39/…/`7188` V103 **fermé** / `6c83` V102 compact / leftover V104 FactoryOutput. **#208 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `7188` / `6c83` / `fce3` / `b7e3` / `adfc` ni hardening `41e2` / `93f6` / `e291` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N166 est cosmétique client (bague chantier BuildingModels). Risques documentés, non corrigés ici (hors N166) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N166. Overlay `explosion` n’a plus de `Destroy` (Blast / Shockwave / BlastSmoke tous poolés). BuildingModels `playConstruction` BuildRing **poolé**. HUD `notify` TextLabel **Destroy** encore (leftover N167). UnitModels `place` flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze Size=API).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N166 du rapport #208. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| BuildingModels `playConstruction` BuildRing Instance.new+Destroy chaque chantier (N166) | `BuildingModels.luau` (`playConstruction` bague BuildRing **seulement**, drop / sort Y / `animate` / `create` inchangés), `tests/client.luau` (commentaire leftover pose **sans** flush + snapshot + reuse 1 bague dans vagues) | Leftover N165. Free-list `BuildingModels.ringFree`, pop O(1). `Parent = nil` + push si encore parenté, pas Destroy. Name `BuildRing` conservé. Parent = **`model`** (pas `overlay.root`). Reset Size `(0.4, 3, 3)` + Transparency `0.4` + Color `255,214,130` + CFrame `CFrame.new(ground) * fromEulerAnglesYXZ(0, 0, math.rad(90))` **avant** Tween. Euler N136 **inline**. Tween Quad Out conservé. Overlay explosion N163–N165 **inchangé**. Cosmétique. Flame leftover N152 **alors**. HUD feed leftover N167 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), HUD `notify` TextLabel Instance.new+Destroy (**N167**), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, PlacementPreview Size rayon (visual V76, feel Size = API), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline** **et** N160 free-list, **pas merger**), tribus `humanTargetProtected`. Effects / UnitModels / WorldCamera / WorldRenderer / Overlay / HUD / serveur **non édités**. Flame **non**. Blast **non**. BlastSmoke **non**. Shockwave **non**. DeliveryPulse **non**. `routePart` **non**. Dismiss `table.remove(index)` **non**. `clearSelection` Destroy **inchangé**. Destroy du modèle navire **inchangé**.

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
- BuildingModels BuildRing free-list (**N166**). Overlay Blast sphère free-list (**N165**). Overlay BlastSmoke free-list (**N164**). Overlay Shockwave free-list (**N163**). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). HUD `notify` TextLabel Instance.new+Destroy (**N167**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N167)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N166** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N167** = nouveau. **N166** fermé ici.

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover feel HUD `notify` TextLabel Instance.new+Destroy = **N167** (N153 préfixe **déjà**, Dismiss `table.remove(index)` **conservé**, **≠** visual V103 préfixe fermé sur `7188`, **≠** Overlay `blastFree` / `smokeFree` / `shockFree` / `ringFree`). Visual V103 HUD préfixe **fermée** sur `7188` / PR #207 (feel N153 **déjà**, ne pas merger). Visual V104 FactoryOutput leftover (feel **déjà** `sin(time)` sans Position — ne pas merger). Visual V102 compact préfixe **fermée** sur `6c83` (feel N114 **déjà**). Visual V101 `dirtyHead` **fermée** sur `fce3` (feel N112 **déjà**).

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N166 (pools Overlay/Effects/BuildingModels **déjà**). Distinct de N151 (trail Transparency), de N163–N166 (pools Overlay explosion / BuildRing), de N167 (HUD feed pool), de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**. Ne pas toucher trail. Ne pas toucher `BuildingModels`. Ne pas toucher Overlay. Ne pas toucher HUD. Ne pas toucher Effects.

**Problème :** N166 ferme le pool BuildRing. N167 reste ouvert (HUD feed). N151 ferme le trail. N153–N165 ferment HUD préfixe / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast. Reste, **chaque frame** (`UnitModels.place`, 60 Hz, une Part `EngineFlame` par ogive) :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (plus de pulse Size, `c0ec` / PR #151). Feel **garde** le pulse Z. Ne pas porter `c0ec`. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**. Role `"flame"` **inchangé**. Shape `Ball` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. BuildRing **déjà** N166 — ne pas y revenir. Blast **déjà** N165 — ne pas y revenir. Visual V74 freeze **interdit** (feel ≠ visual). **Passes 61–75 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse `1.8 + math.sin(time * 18) * 0.45`. **Ne pas** geler Size (visual V74 Option A, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)`. XY `0.62` / base `1.8` / freq `18` / amp `0.45` **inchangés**.

2. **Garder le pulse.** Ne **pas** poser Size = API. Ne **pas** « fermer » trail / HUD / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing (N151–N166 déjà). Ne **pas** lire `piece.part.Size` (alloc). Ne pas porter visual. Après N166. `BuildingModels` **non**. Overlay **non**. HUD **non**. Effects **non**. `createMissile` construction **non** (taille initiale `Vector3.new(0.62, 0.62, 2.3)` inchangée).

3. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N167 seulement.** N152 reste alors ouvert (feel-diverged vs V74). Ne pas inventer un cache Size. Ne pas skip-si-inchangé (N2, pas ici).

4. Tests « navires, missiles et interpolation » leftover N151 trail **et** leftover N148 mesh **et** leftover N147 Fin **doivent rester verts**. Tests « vagues de conquete » leftover N166 `BuildRing` reuse **et** leftover N165 `Blast` reuse **et** leftover N164 `BlastSmoke` reuse **et** leftover N163 `Shockwave` reuse **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` flame **seulement**, **un** `elseif`) **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N152. Overlay **non**. **Ne pas** éditer le serveur. **Ne pas** toucher Shockwave ni BlastSmoke ni Blast sphère ni BuildRing ni HUD feed.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ N151 (trail Z) ≠ visual V74 (freeze Size=API, ne pas merger) ≠ N163 (Shockwave pool) ≠ N164 (BlastSmoke pool) ≠ N165 (Blast sphère pool) ≠ N166 (BuildRing pool) ≠ N167 (HUD feed pool) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N167 dans le même worker. Pulse Z **conservé** — ne pas figer à 1.8. Un `elseif` flame.

---

### ISSUE-N167 — HUD `notify` TextLabel Instance.new+Destroy (feel)

**Priorité :** P3 alloc client HUD. Leftover explicite après N166 (BuildRing free-list déjà). Distinct de N152 (UnitModels Size), de N153 (décalage préfixe `feedEntries` **déjà**), de N154–N166 (pools Overlay/Effects/BuildingModels), de visual V103 (préfixe feed **fermé** sur `7188` / PR #207 — **ne pas merger**). `HUD.notify` entrée `TextLabel` **seulement**. Ne pas toucher le décalage N153. Ne pas toucher Dismiss `table.remove(index)`. Ne pas toucher Overlay.explosion. Ne pas toucher BuildRing. Ne pas toucher UnitModels. Ne pas toucher Effects.

**Problème :** N166 ferme le pool BuildRing. N152 reste ouvert (freeze interdit). Reste, **chaque message** (`HUD.notify`, fil tactique, plafond `MAX_FEED_ENTRIES = 3`) :

```
local entry = Instance.new("TextLabel")
entry.Size = UDim2.new(1, 0, 0, FEED_ENTRY_HEIGHT)
entry.BackgroundColor3 = C.surface
entry.BackgroundTransparency = 0.14
entry.BorderSizePixel = 0
entry.FontFace = F.bold
entry.TextSize = T.small
entry.TextColor3 = FEED_COLORS[kind] or C.text
entry.Text = text
entry.TextTruncate = Enum.TextTruncate.AtEnd
entry.LayoutOrder = self.feedCounter
entry.Parent = self.feed
Theme.corner(entry, Theme.radius.sm)
Theme.stroke(entry, FEED_COLORS[kind] or C.line, 1)
-- UIPadding PaddingRight 20
-- TextButton Name "Dismiss" …
task.delay(4.5, function()
    -- Destroy Dismiss, tween transparences, removeEntry → Destroy
end)
```

Instance.new TextLabel + UIPadding + Dismiss + Destroy (plafond N153 **et** expiration 4.5 s **et** croix) par notify. Overlay explosion **et** BuildRing **réutilisent déjà**. Distinct de leftover N152 (`Size = Vector3.new` flamme). Distinct de leftover N153 (décalage préfixe **déjà** — **ne pas** y revenir). Distinct de leftover N166 (`ringFree` **déjà** — **ne pas** partager). Groupement même `text` **inchangé** (compteur, pas une 2e entrée). `MAX_FEED_ENTRIES = 3` **inchangé**. Dismiss `table.remove(index)` **inchangé** (leftover séparé). N153 while-shift **inchangé**.

**Pourquoi 20K CCU :** leftover N166. 8 clients × notify (prises, trahisons, nukes, chat) × `Instance.new` TextLabel + UIPadding + Dismiss + Destroy 4.5 s. Une offensive produit des dizaines de messages ; le plafond N153 Destroy encore. Pas d’autorité (cosmétique HUD). BuildRing **déjà** N166 — ne pas y revenir. Blast **déjà** N165. Visual V103 préfixe **interdit** (feel N153 **déjà**, ne pas merger `7188` / `ee71`). **Oubli de reset Text / couleurs / transparences au reuse** = message fantôme / croix absente (le delay **Destroy** la croix). **Theme.corner / Theme.stroke au reuse** = 2e UICorner / UIStroke empilés. **Si le seul patch est un merger V103 : ne pas livrer.**

**Worker :**

1. Dans `HUD.notify` création de l’entrée seulement : free-list d’ancres (`self.feedFree` tableau **instance**, pop O(1), lazy-init dans `notify` — **pas** `HUD.new` obligatoire, **pas** `BuildingModels.ringFree`). **Pas** `ringFree` (c’est BuildingModels N166). **Pas** `blastFree` / `smokeFree` / `shockFree` / `textFree` (Effects N158). Si un TextLabel libre : **réutiliser** (pas `Instance.new`). Writes **avant** Parent : `Text = text`, `TextColor3 = FEED_COLORS[kind] or C.text`, `BackgroundColor3 = C.surface`, `BackgroundTransparency = 0.14`, `TextTransparency = 0`, `LayoutOrder = self.feedCounter`, `Size = UDim2.new(1, 0, 0, FEED_ENTRY_HEIGHT)`. Parent = **`self.feed`**. **Ne pas** `Theme.corner` / `Theme.stroke` au reuse (`FindFirstChildWhichIsA("UICorner")` / `UIStroke` déjà là — un 2e empile). Recolor le stroke existant (`Color = FEED_COLORS[kind] or C.line`). UIPadding : `FindFirstChildWhichIsA("UIPadding")`, sinon `Instance.new`. Dismiss : `FindFirstChild("Dismiss")` — si absent (le delay **Destroy** la croix) : recréer le TextButton Name `Dismiss` **identique** (Activated → `removeEntry(entry)`). **Ne pas** Destroy l’entrée dans `removeEntry` : `Parent = nil` + push free-list (`if target.Parent` devient push seulement si encore parenté — un second delay fantôme ne double-push pas). Sinon : création inchangée (`Instance.new` TextLabel, corner/stroke une fois). `task.delay(4.5)` **conservé**. Groupement `feedGroups[text]` **conservé**. N153 while-shift **conservé** (appelle `removeEntry` **après** le shift). Dismiss `table.remove(index)` **conservé**. Pas de `self.live`. **Ne pas** wrapper un record. **Ne pas** partager `ringFree` / `blastFree` / `textFree` / `pulseFree`. Un pop par `notify` qui n’est pas un groupement.

2. **Garder le fil.** Ne **pas** recréer au reuse. Ne **pas** poser Name (pas de Name aujourd’hui — comme N158 textFree, **pas** `FeedEntry` obligatoire). Ne **pas** toucher N153. Ne **pas** toucher Overlay N165/N164/N163. Ne **pas** toucher BuildRing N166. Ne **pas** geler Size (pas N152). Après N166. Flame **non** (N152). Overlay **non**. `UnitModels` **non**. Effects **non**. `BuildingModels` **non**. Parent = **`self.feed`** obligatoire (pas `overlay.root`).

3. Tests « fil de notifications sature » leftover N153 préfixe **et** Dismiss Activated **doivent rester verts**. **Ne pas** `testFlushDelays` dans ce check (le harnais stubbe `task.delay` pour le rejet — les 40 notify ont des delays en file jusqu’aux vagues). Tests « vagues de conquete » leftover N166 `BuildRing` reuse **et** leftover N165 `Blast` reuse **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client `fil de notifications` **doit rester vert** (N153 shift, Dismiss, groupement, **pas** de flush). Après flush des delays **dans le check vagues** (déjà un `testFlushDelays` — les 3 entrées encore parentées du plafond y tombent), `hud.feedFree` `# >= 1` ; snapshot `pooledFeed` **avant** `applyUnits` N160 **et avant** N166 `applyBuildingDelta`. Réparente (`rawequal` Parent = `hud.feed`, **pas** `overlay.root`). `hud:notify` d’un texte **nouveau** (pas un groupement) consomme 1. **Réécrire** Text + couleurs + transparences + LayoutOrder **avant** Parent — oubli = message fantôme. Recréer Dismiss si `FindFirstChild("Dismiss")` nil. **Ne pas** `Theme.corner` au reuse. **Ne pas** casser N166 (`ringFree` snapshot + reuse `rawequal` Parent model, Name `BuildRing`). **Ne pas** casser N165 (`blastFree` snapshot + reuse Name `Blast`). **Ne pas** casser N164 / N163 / N162. Assert `pooledFeed ~= pooledBuildRing`. Assert `pooledFeed ~= pooledBlast`. Assert `pooledFeed ~= pooledText` (Effects `textFree`). Check vagues leftover N166 / N165 / N164 / N163. Check notifications leftover N153 sans flush. Check pose leftover N166 sans flush. Check navires leftover N152 flame. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `HUD.luau` (`notify` entrée TextLabel **seulement**, `removeEntry` Parent=nil). `tests/client.luau` **seulement si** le check notifications ne mentionne pas encore N167 (commentaire leftover, **garder** N153 préfixe / Dismiss). `Overlay.luau` **non**. `Effects.luau` **non**. `BuildingModels.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher flame ni Blast ni BlastSmoke ni Shockwave ni BuildRing. **Ne pas** modifier le décalage N153. **Ne pas** changer Dismiss `table.remove(index)`.

**Contraintes :** pas de RemoteFunction. **N167 feel ≠ N166 (BuildRing pool) ≠ N165 (Blast sphère pool) ≠ N153 (préfixe feed déjà) ≠ visual V103 (préfixe fermé `7188`, ne pas merger) ≠ visual V104 (FactoryOutput, feel déjà `sin(time)` sans Position) ≠ N152 (flame Size, ne pas freeze V74) ≠ N158 (Effects textFree, ne pas partager) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N152 dans le même worker. Free-list — ne pas skip Text si le message change. Un `notify` — ne pas splitter le groupement. `task.delay(4.5)` **conservé**. Ne pas `table.remove` la free-list (pop O(1) depuis la fin). Ancre `Parent = nil` **pas** Destroy. Distinct `ringFree` / `blastFree` / `smokeFree` / `shockFree` / `textFree` / `pulseFree` — **ne pas** partager. **Reset Text + couleurs + transparences avant Parent** — oubli = fantôme. **Pas Theme.corner au reuse**. Recréer Dismiss si Destroy par le delay. Parent = **`self.feed`** **obligatoire**. N153 while-shift **obligatoire** inchangé. Nommer `feedFree` **pas** `ringFree` **pas** `textFree` **pas** `blastFree`. Exposer `hud.feedFree` (instance, le banc y lit).

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; BuildRing → **N166 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; BuildRing pool → **N166** ; Overlay explosion + chantier clos ; HUD feed pool = **N167**) |
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
| N34–N151, N153–N166 | (voir rapport #208) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–75) |
| N167 | HUD `notify` TextLabel Instance.new+Destroy | P3 | **nouveau** (`notify` entrée free-list `feedFree`, N153 préfixe **déjà**, Dismiss `table.remove(index)` **conservé**, **≠** visual V103 préfixe, **≠** Effects `textFree`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 / #169 / #171 / #173 / #176 / #178 / #181 / #183 / #185 / #187 / #189 / #191 / #193 / #195 / #197 / #200 / #202 / #204 / #206 / #208 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N166 BuildRing pool) |

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

Client : **35/35 OK** — dont `fil de notifications sature` leftover N153 ; `calques d'entites, effets et apercu` leftover N155 reuse ; `hover spawn isolation` leftover N58 ; `construction du monde 3D` leftover N137/N138 ; `pose et capture de chaque type de batiment` leftover N136 / leftover N132 / leftover N162 commentaire **sans** flush / leftover N166 commentaire **sans** flush ; `modeles procéduraux` leftover N150/N149 ; `apercu de placement pour chaque batiment` leftover N129 ; `livraison : le gain s'affiche sur la gare` leftover N159 **sans** flush ; `navires, missiles et interpolation` leftover N151 trail / leftover N152 flame Size / leftover N148 mesh / leftover N160 wake **sans** flush / leftover N161 splash **sans** flush / leftover N163 Shockwave **sans** flush / leftover N164 BlastSmoke **sans** flush / leftover N165 Blast **sans** flush, skip retraite id=1 N56 ; `vagues de conquete` N166 `BuildRing` reuse (`testFlushDelays` → `#ringFree >= 1` **avant** N160, `applyBuildingDelta` CITY+FACTORY `rawequal` Parent model, Name `BuildRing`, `# == max(0, ringN - 2)`) / leftover N165 `Blast` reuse / leftover N164 `BlastSmoke` reuse / leftover N163 `Shockwave` reuse / leftover N162 `DeliveryPulse` reuse / leftover N161 `LandingSplash` reuse / leftover N160 `LaunchWake` reuse / leftover N159 `goldPopup` reuse / leftover N158 `floatingText` reuse / leftover N157 `conquestPulse` reuse / leftover N156 `tileFlash` reuse. Serveur **non** touché cette passe. `UnitModels.luau` **non** touché. `WorldCamera.luau` **non** touché. `Effects.luau` **non** touché. `PlacementPreview.luau` **non** touché. `HUD.luau` **non** touché. Overlay **non** touché. BuildingModels BuildRing **poolé**.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass75.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N166 est un pool bague BuildRing vérifié par le banc headless (`pose` sans flush + `vagues de conquete` flush + `applyBuildingDelta` CITY+FACTORY reuse `rawequal` Parent model). Pulse flamme Size **inchangé** (N152). HUD feed **inchangé** (N167).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N166 n’ajoute **pas** de require (free-list locale BuildingModels `playConstruction`). N152 restera dans `UnitModels.place` flame. N167 restera dans `HUD.notify`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Distinct trail N151. Distinct Overlay N163–N165 **déjà**. Distinct BuildRing N166 **déjà**. Distinct HUD leftover N167. Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N166 : `BuildingModels.playConstruction` bague BuildRing seulement. Free-list `BuildingModels.ringFree` **séparée** de Overlay `blastFree` / `smokeFree` / `shockFree`. Tween Size/Transparency **conservé**. `Parent = nil` + push, **pas** Destroy. Name `BuildRing` **conservé**. Parent = **`model`** (**pas** `overlay.root`). Reset Size `(0.4, 3, 3)` + Transparency `0.4` + Color `255,214,130` + CFrame `CFrame.new(ground) * fromEulerAnglesYXZ(0, 0, math.rad(90))` **avant** Tween (`ground` **varie**). Euler N136 **inline** — **ne pas** cuire un rot. Distinct Blast N165. Distinct flame N152. Distinct HUD leftover N167. `task.delay(total + 0.2)` conservé. Lazy-init `ringFree` dans `playConstruction` (pas `BuildingModels.create`). **Ne pas** modifier Overlay.explosion. **Ne pas** flush dans le check pose (N162 DeliveryPulse). Snapshot **avant** N162 `applyBuildingDelta` (CITY+FACTORY `animateFrom = 0` consomme 2). **Ne pas** nommer `blastFree` **ni** `smokeFree` **ni** `shockFree` **ni** `pulseFree`. **Ne pas** casser N165 ni N164 ni N163 ni N162. Le banc stubs Destroy parent **non récursif** : le delay pousse quand même (`ring.Parent` encore le model détruit).

Piège N167 (à venir) : `HUD.notify` entrée TextLabel seulement. Free-list `self.feedFree` **séparée** de Effects `textFree` / BuildingModels `ringFree`. `Parent = nil` + push, **pas** Destroy. Parent = **`self.feed`**. Reset Text + couleurs + transparences + LayoutOrder **avant** Parent. **Pas** `Theme.corner` / `Theme.stroke` au reuse (2e UICorner). Recréer Dismiss si `FindFirstChild("Dismiss")` nil (le delay Destroy la croix). N153 while-shift **inchangé**. Dismiss `table.remove(index)` **inchangé**. Groupement **inchangé**. Distinct BuildRing N166. Distinct flame N152. Distinct visual V103 (préfixe, ne pas merger `7188`). `task.delay(4.5)` conservé. Lazy-init `feedFree` dans `notify`. **Ne pas** flush dans le check notifications (N153 Dismiss stubbe `task.delay`). Snapshot **après** le `testFlushDelays` des vagues. **Ne pas** nommer `textFree` **ni** `ringFree`. **Ne pas** casser N166 ni N165 ni N153.
