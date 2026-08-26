# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 77)

Déclencheur : ouverture de la **PR #213** (`cursor/analyse-nocturne-du-codebase-9914`) — HUD notify TextLabel free-list (N167), specs N152 / N168.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-a72c`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#213. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

Effects `clearSelection` : `Parent = nil`, garder `self.selection` (**N168**). HUD `notify` : free-list `feedFree` (**N167**). BuildingModels BuildRing : free-list `ringFree` (**N166**). Overlay Blast sphère : free-list `blastFree` (**N165**). Overlay BlastSmoke : free-list `smokeFree` (**N164**). Overlay Shockwave : free-list `shockFree` (**N163**). PointLight reste **enfant** de Blast. UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). Effects `clearActionPreview` Destroy+nil encore (leftover **N169**, N154 skip **déjà**, N168 selection **déjà**, **≠** visual V77).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #213 (passe 76) : claims vérifiés.** HUD `notify` TextLabel free-list (N167, `feedFree` pop O(1), `Parent = nil` + push si encore parenté, pas Destroy, Parent = **`self.feed`** pas `overlay.root`, reset Text + couleurs + LayoutOrder avant Parent, pas `Theme.corner` au reuse, recréer Dismiss si Destroy par delay, garde `LayoutOrder ~= born`, N153 while-shift **inchangé**, Dismiss `table.remove(index)` **inchangé**). **N152 non livré** (freeze Size=API = visual V74, interdit). Spec N168 **livrée ici**. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #209** (`7188`) a **fermé V103** HUD préfixe — feel N153 **déjà**, **pas merger**. Visual **PR #211** (`8bb2`) FactoryOutput/SiloWarning phase rest — feel **déjà** `sin(time)` sans Position, **pas merger**. Visual **PR #212** (`2f2a`) feux navire `offset.X` — feel `sin(time * 3)` lockstep **encore**, **pas merger**. Visual **6c83** V102 compact — feel N114 **déjà**.

Cette passe a **livré N168** (ce que #213 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #213

| Claim #213 | Réalité à l’ouverture |
|---|---|
| HUD `notify` TextLabel free-list (N167) | Oui. `feedFree` pop O(1). `Parent = nil` + push si encore parenté, pas Destroy. Parent = `self.feed`. Reset Text + couleurs + transparences + LayoutOrder avant Parent. Pas `Theme.corner` / `Theme.stroke` au reuse. Recréer Dismiss si Destroy par le delay. Garde `LayoutOrder ~= born`. N153 while-shift inchangé. Dismiss `table.remove(index)` inchangé. Overlay explosion / BuildRing / `clearSelection` inchangés. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N168 | **N168 livré ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #213, visuelles #39/…/`7188` V103 **fermé** / `8bb2` V104 FactoryOutput / `2f2a` V105 feux navire / `6c83` V102 compact. **#213 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `7188` / `8bb2` / `2f2a` / `6c83` / `fce3` / `b7e3` / `adfc` ni hardening `41e2` / `93f6` / `e291` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N168 est cosmétique client (marqueur de tuile). Risques documentés, non corrigés ici (hors N168) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip `rng > 0.12` seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N168. Overlay `explosion` n’a plus de `Destroy` (Blast / Shockwave / BlastSmoke tous poolés). BuildingModels `playConstruction` BuildRing **poolé**. HUD `notify` TextLabel **poolé**. Effects `clearSelection` **poolé** (un marqueur, pas de tableau). Effects `clearActionPreview` Destroy encore (leftover N169). UnitModels `place` flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze Size=API).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N168 du rapport #213. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Effects `clearSelection` Destroy+nil chaque désélection (N168) | `Effects.luau` (`clearSelection` Parent=nil garder `self.selection`, `selectTile` reparent `self.root` si Parent nil **avant** Color / Transparency / Size / CFrame / Tween, N155 reuse inter-clics **inchangé**, `clearActionPreview` Destroy **inchangé**), `tests/client.luau` (check calques leftover N168 : assert `rawequal` + Parent nil + Name, puis reselect `rawequal` Parent `effects.root` ; N155 `rawequal` 2000→2001 **avant** clear) | Leftover N167. Un seul marqueur — pas de tableau `selectionFree`. `Parent = nil` si encore parenté, pas Destroy, pas `self.selection = nil`. Parent = **`self.root`** (pas `hud.feed`, pas `overlay.root`). Name `SelectedTerritory` conservé. Tween pulse Transparency/Size conservé. Cosmétique. Flame leftover N152 **alors**. `clearActionPreview` leftover N169 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), Effects `clearActionPreview` Destroy+nil (**N169**), HUD `refreshChatSheet` Destroy (commentaire source : trop simple), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, PlacementPreview Size rayon (visual V76, feel Size = API), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline** **et** N160 free-list, **pas merger**), tribus `humanTargetProtected`. Overlay / BuildingModels / HUD / UnitModels / WorldCamera / WorldRenderer / serveur **non édités**. Flame **non**. Blast **non**. BlastSmoke **non**. Shockwave **non**. DeliveryPulse **non**. `routePart` **non**. Dismiss `table.remove(index)` **non**. HUD `feedFree` **inchangé**. Destroy du modèle navire **inchangé**. `previewTile` N154 skip **inchangé**. `clearActionPreview` Destroy **inchangé**.

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
- Effects `clearSelection` poolé (**N168**, un marqueur). HUD `notify` free-list (**N167**). BuildingModels BuildRing free-list (**N166**). Overlay Blast sphère free-list (**N165**). Overlay BlastSmoke free-list (**N164**). Overlay Shockwave free-list (**N163**). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). Effects `clearActionPreview` Destroy+nil (**N169**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N169)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N168** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N169** = nouveau. **N168** fermé ici.

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover feel Effects `clearActionPreview` Destroy+nil = **N169** (N154 skip **déjà**, N168 selection **déjà**, nil `actionPreviewIndex`/`Valid`/`Color` **obligatoire** sinon skip N154 laisse le marqueur invisible, HUD `refreshChatSheet` Destroy **conservé**, **≠** visual V77 PlacementPreview, **≠** HUD `feedFree` / Effects `selection`). Visual V103 HUD préfixe **fermée** sur `7188` / PR #209 (feel N153 **déjà**, ne pas merger). Visual V104 FactoryOutput **ouverte** sur `8bb2` / PR #211 (feel **déjà** `sin(time)` sans Position — ne pas merger). Visual V105 feux navire **ouverte** sur `2f2a` / PR #212 (feel lockstep `sin(time * 3)` — ne pas merger). Visual V102 compact préfixe **fermée** sur `6c83` (feel N114 **déjà**). Visual V101 `dirtyHead` **fermée** sur `fce3` (feel N112 **déjà**).

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N168 (pools Overlay/Effects/BuildingModels/HUD/selection **déjà**). Distinct de N151 (trail Transparency), de N163–N168 (pools Overlay explosion / BuildRing / HUD feed / `clearSelection`), de N169 (`clearActionPreview`), de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**. Ne pas toucher trail. Ne pas toucher `BuildingModels`. Ne pas toucher Overlay. Ne pas toucher HUD. Ne pas toucher Effects.

**Problème :** N168 ferme le pool `clearSelection`. N169 reste ouvert (`clearActionPreview`). N151 ferme le trail. N153–N167 ferment HUD préfixe / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed. Reste, **chaque frame** (`UnitModels.place`, 60 Hz, une Part `EngineFlame` par ogive) :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (plus de pulse Size, `c0ec` / PR #151). Feel **garde** le pulse Z. Ne pas porter `c0ec`. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**. Role `"flame"` **inchangé**. Shape `Ball` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. HUD feed **déjà** N167 — ne pas y revenir. `clearSelection` **déjà** N168. Blast **déjà** N165. Visual V74 freeze **interdit** (feel ≠ visual). **Passes 61–77 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse `1.8 + math.sin(time * 18) * 0.45`. **Ne pas** geler Size (visual V74 Option A, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)`. XY `0.62` / base `1.8` / freq `18` / amp `0.45` **inchangés**.

2. **Garder le pulse.** Ne **pas** poser Size = API. Ne **pas** « fermer » trail / HUD / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed / `clearSelection` (N151–N168 déjà). Ne **pas** lire `piece.part.Size` (alloc). Ne pas porter visual. Après N168. `BuildingModels` **non**. Overlay **non**. HUD **non**. Effects **non**. `createMissile` construction **non** (taille initiale `Vector3.new(0.62, 0.62, 2.3)` inchangée).

3. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N169 seulement.** N152 reste alors ouvert (feel-diverged vs V74). Ne pas inventer un cache Size. Ne pas skip-si-inchangé (N2, pas ici).

4. Tests « navires, missiles et interpolation » leftover N151 trail **et** leftover N148 mesh **et** leftover N147 Fin **doivent rester verts**. Tests « calques d'entites, effets et apercu » leftover N168 `clearSelection` reuse **et** leftover N155 `rawequal` 2000→2001 **doivent rester verts**. Tests « vagues de conquete » leftover N167 `feedFree` reuse **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` flame **seulement**, **un** `elseif`) **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N152. Overlay **non**. **Ne pas** éditer le serveur. **Ne pas** toucher Shockwave ni BlastSmoke ni Blast sphère ni BuildRing ni HUD feed ni `clearSelection` ni `clearActionPreview`.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ N151 (trail Z) ≠ visual V74 (freeze Size=API, ne pas merger) ≠ N163 (Shockwave pool) ≠ N164 (BlastSmoke pool) ≠ N165 (Blast sphère pool) ≠ N166 (BuildRing pool) ≠ N167 (HUD feed pool) ≠ N168 (`clearSelection`) ≠ N169 (`clearActionPreview`) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N169 dans le même worker. Pulse Z **conservé** — ne pas figer à 1.8. Un `elseif` flame.

---

### ISSUE-N169 — Effects `clearActionPreview` Destroy+nil (feel)

**Priorité :** P3 alloc client Effects. Leftover explicite après N168 (`clearSelection` déjà). Distinct de N152 (UnitModels Size), de N154 (`previewTile` skip index+valid+color **déjà** tant que `self.actionPreview` vit), de N168 (`clearSelection` Parent=nil **déjà**), de N155 (`selectTile` reuse **déjà**), de visual V77 (PlacementPreview early-out — **ne pas merger** `185a`). `Effects.clearActionPreview` **seulement**. Ne pas toucher `clearSelection` (N168 **déjà**). Ne pas toucher HUD `refreshChatSheet` (Destroy **conservé**, leftover séparé). Ne pas toucher Overlay. Ne pas toucher UnitModels. Ne pas toucher BuildingModels.

**Problème :** N168 ferme le pool `clearSelection`. N152 reste ouvert (freeze interdit). N154 réutilise la Part `ActionPreview` d’un hover à l’autre **tant que** `self.actionPreview` n’est pas nil, et skip si index+valid+color inchangés. Reste, **chaque sortie de mode** (`Effects.clearActionPreview`, changement de mode / fermeture fiche / raycast perdu) :

```
if self.actionPreview then
    self.actionPreview:Destroy()
    self.actionPreview = nil
    self.actionPreviewIndex = nil
    self.actionPreviewValid = nil
    self.actionPreviewColor = nil
end
```

Le hover suivant (`previewTile`) refait `Instance.new("Part")`. N154 est **gaspillé** dès qu’on quitte le mode. Distinct de leftover N152 (`Size = Vector3.new` flamme). Distinct de leftover N168 (`self.selection` **déjà** — **ne pas** partager). Distinct de leftover N167 (`feedFree` **déjà**). Name `ActionPreview` **inchangé**. Skip N154 **inchangé**. Caps flash **inchangés**.

**Piège skip N154 :** il **faut** encore nil `actionPreviewIndex` / `actionPreviewValid` / `actionPreviewColor` au clear. Si on garde les trois champs, le hover suivant (même tuile + valid + color) `return` **avant** le reparent — marqueur invisible (`Parent` nil). Oubli = bug visuel + test rouge.

Le banc `calques d'entites, effets et apercu` **appelle aujourd’hui** `clearActionPreview` **avant** `clearSelection` **sans** capturer `actionPreview` — **il faudra** snapshotter la Part **avant** le clear, changer l’absence d’assert, puis `previewTile` reselect **avant** les asserts N168 (N168 `rawequal` selection **après** le re-preview, **ne pas** les retirer).

**Pourquoi 20K CCU :** leftover N154. 8 clients × (changement de mode / hover perdu / reclic) × `Instance.new("Part")` + Destroy. Le raycast tourne 60 Hz ; sortir du mode attaque/build est fréquent. Pas d’autorité (cosmétique Effects). `clearSelection` **déjà** N168 — ne pas y revenir. HUD feed **déjà** N167. Visual V77 early-out **interdit** (ne pas merger `185a`). **Oubli de reparent `Parent = self.root` au reuse** = aperçu invisible. **Oubli de garder `self.actionPreview`** = N154 retombe sur Instance.new. **Oubli de nil les trois champs skip** = N154 `return` sur un Parent nil. **Si le seul patch est un merger V77 : ne pas livrer.**

**Worker :**

1. Dans `Effects.clearActionPreview` seulement : **ne plus** `Destroy`. **Ne plus** `self.actionPreview = nil`. Si `self.actionPreview` et `self.actionPreview.Parent` : `Parent = nil` (un second clear ne double-unparent pas). **Garder** la référence `self.actionPreview`. **Nil encore** `self.actionPreviewIndex` / `self.actionPreviewValid` / `self.actionPreviewColor` (N154 skip **ne doit pas** matcher après clear). Dans `Effects.previewTile`, après le `if not marker then` N154 (création inchangée, Name `ActionPreview`) : si `marker.Parent == nil` alors `marker.Parent = self.root` **avant** Color / Transparency / CFrame / pose des trois champs skip. **Ne pas** retirer le skip index+valid+color **avant** ce reparent (si skip fire, le marqueur resterait unparented). Reset Color + Transparency `0.5`/`0.72` + CFrame **déjà** écrits par N154 — **ne pas** les retirer. Name `ActionPreview` **conservé**. `clearSelection` N168 **conservé**. `selectTile` N155 **conservé**. `tileFlash` N156 **conservé**. Pas de free-list tableau (un seul marqueur — ce n’est **pas** `feedFree` / `flashFree` / `selection`).

2. **Garder le marqueur.** Ne **pas** recréer après clear. Ne **pas** poser un Name différent. Ne **pas** toucher N154 skip inter-hovers (déjà 2001→2002). Ne **pas** toucher N168 selection. Ne **pas** geler Size (pas N152). Après N168. Flame **non** (N152). Overlay **non**. HUD **non**. `BuildingModels` **non**. Parent = **`self.root`** obligatoire au reuse (pas `overlay.root`, pas `hud.feed`). **Nil les trois champs skip** — oubli = aperçu invisible.

3. Tests « calques d'entites, effets et apercu » leftover N155 `rawequal` 2000→2001 **et** leftover N168 `clearSelection` Parent nil + reselect **doivent rester verts**. **Ajouter** : après `previewTile(2002, …)`, `local previewMarker = effects.actionPreview` ; après `clearActionPreview`, `rawequal(effects.actionPreview, previewMarker)` **et** `previewMarker.Parent == nil` **et** Name `ActionPreview` **et** `effects.actionPreviewIndex == nil`. Puis `previewTile(2001, …)` → `rawequal(effects.actionPreview, previewMarker)` **et** `rawequal(previewMarker.Parent, effects.root)`. **Ensuite** les asserts N168 `clearSelection` (déjà). Tests « fil de notifications sature » leftover N153/N167 **sans** flush **doivent rester verts**. Tests « vagues de conquete » leftover N167 `feedFree` reuse **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client `calques` **doit rester vert** (N155 reuse 2000→2001, N154 preview 2001→2002, **nouveau** clearActionPreview puis re-preview `rawequal`, **puis** N168 clearSelection). **Ne pas** `testFlushDelays` dans ce check. Check vagues leftover N167 / N166 / N165. Check notifications leftover N153/N167 sans flush. Check navires leftover N152 flame. **Ne pas** casser N168 (`self.selection` conservé, Parent nil, reselect `effects.root`). **Ne pas** casser N167 (`feedFree` snapshot + reuse `rawequal` Parent `hud.feed`). **Ne pas** casser N154 (skip 2001→2002 **avant** clear). Assert `effects.actionPreview ~= nil` après clear. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `Effects.luau` (`clearActionPreview` **et** reparent dans `previewTile` si Parent nil). `tests/client.luau` **seulement** le check calques (commentaire leftover N169, **ajouter** snapshot + asserts preview, **garder** N155 `rawequal` 2000→2001 **et** N168 clear/reselect). `HUD.luau` **non**. `Overlay.luau` **non**. `BuildingModels.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher flame ni Blast ni BuildRing ni HUD feed ni `clearSelection`. **Ne pas** modifier `refreshChatSheet`. **Ne pas** merger visual V77.

**Contraintes :** pas de RemoteFunction. **N169 feel ≠ N168 (`clearSelection` déjà) ≠ N154 (previewTile skip déjà, Destroy encore) ≠ N155 (selectTile reuse) ≠ N167 (HUD feed pool) ≠ visual V77 (PlacementPreview early-out, ne pas merger `185a`) ≠ N152 (flame Size, ne pas freeze V74) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N152 dans le même worker. Un seul marqueur — **pas** de tableau `previewFree`. **Pas Destroy**. **Pas `self.actionPreview = nil`**. **Nil `actionPreviewIndex` / `Valid` / `Color` obligatoire.** Reparent `self.root` au `previewTile` suivant, **après** le skip (le skip ne doit pas matcher). Distinct `feedFree` / `flashFree` / `selection` — **ne pas** partager. Name `ActionPreview` **obligatoire**. `clearSelection` N168 **obligatoire** inchangé. HUD `refreshChatSheet` Destroy **obligatoire** inchangé.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; HUD feed → **N167 fait** ; `clearSelection` → **N168 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; HUD feed pool → **N167** ; `clearSelection` → **N168** ; Overlay explosion + chantier + fil clos ; `clearActionPreview` = **N169**) |
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
| N34–N151, N153–N168 | (voir rapport #213) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–77) |
| N169 | Effects `clearActionPreview` Destroy+nil | P3 | **nouveau** (`Parent = nil`, garder `self.actionPreview`, nil skip N154, reparent `previewTile`, N154 skip **déjà**, N168 selection **déjà**, HUD `refreshChatSheet` Destroy **conservé**, **≠** visual V77) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 / #169 / #171 / #173 / #176 / #178 / #181 / #183 / #185 / #187 / #189 / #191 / #193 / #195 / #197 / #200 / #202 / #204 / #206 / #208 / #210 / #213 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N168 `clearSelection` pool) |

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
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.34 p95TickMs=0.91
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `fil de notifications sature` leftover N153 / leftover N167 commentaire **sans** flush ; `calques d'entites, effets et apercu` leftover N155 reuse / leftover N168 `clearSelection` Parent nil + reselect `effects.root` / leftover N169 Destroy encore ; `hover spawn isolation` leftover N58 ; `construction du monde 3D` leftover N137/N138 ; `pose et capture de chaque type de batiment` leftover N136 / leftover N132 / leftover N162 commentaire **sans** flush / leftover N166 commentaire **sans** flush / leftover N167 commentaire ; `modeles procéduraux` leftover N150/N149 ; `apercu de placement pour chaque batiment` leftover N129 ; `livraison : le gain s'affiche sur la gare` leftover N159 **sans** flush ; `navires, missiles et interpolation` leftover N151 trail / leftover N152 flame Size / leftover N148 mesh / leftover N160 wake **sans** flush / leftover N161 splash **sans** flush / leftover N163 Shockwave **sans** flush / leftover N164 BlastSmoke **sans** flush / leftover N165 Blast **sans** flush, skip retraite id=1 N56 ; `vagues de conquete` N167 `feedFree` reuse (`testFlushDelays` → `#feedFree >= 1` **avant** N160, `hud:notify` texte nouveau `rawequal` Parent `hud.feed`, Dismiss recréé, `# == feedN - 1`) / leftover N166 `BuildRing` reuse / leftover N165 `Blast` reuse / leftover N164 `BlastSmoke` reuse / leftover N163 `Shockwave` reuse / leftover N162 `DeliveryPulse` reuse / leftover N161 `LandingSplash` reuse / leftover N160 `LaunchWake` reuse / leftover N159 `goldPopup` reuse / leftover N158 `floatingText` reuse / leftover N157 `conquestPulse` reuse / leftover N156 `tileFlash` reuse. Serveur **non** touché cette passe. `UnitModels.luau` **non** touché. `WorldCamera.luau` **non** touché. `HUD.luau` **non** touché. `PlacementPreview.luau` **non** touché. Overlay **non** touché. BuildingModels **non** touché. Effects `clearSelection` **poolé**. Pulse flamme Size **inchangé** (N152). `clearActionPreview` Destroy **inchangé** (N169).

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass77.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N168 est un recycle Part Effects vérifié par le banc headless (`calques` N155 `rawequal` 2000→2001 **avant** clear + Parent nil + reselect `rawequal` Parent `effects.root`). Pulse flamme Size **inchangé** (N152). `clearActionPreview` Destroy **inchangé** (N169).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N168 n’ajoute **pas** de require (référence locale Effects `selection`). N152 restera dans `UnitModels.place` flame. N169 restera dans `Effects.clearActionPreview`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Distinct trail N151. Distinct Overlay N163–N165 **déjà**. Distinct BuildRing N166 **déjà**. Distinct HUD N167 **déjà**. Distinct `clearSelection` N168 **déjà**. Distinct `clearActionPreview` leftover N169. Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N168 : `Effects.clearSelection` seulement. **Pas** Destroy. **Pas** `self.selection = nil`. `selectTile` reparent `self.root` si Parent nil **avant** Color / Tween. Name `SelectedTerritory` **conservé**. N155 reuse inter-clics **inchangé**. `clearActionPreview` Destroy **inchangé** (leftover N169). Distinct HUD leftover N167. Distinct flame leftover N152. Distinct visual V83 (ne pas merger `0b3d`). **Changer** l’assert `selection == nil` du check calques (sinon rouge) — **fait ici**. **Ne pas** flush. **Ne pas** casser N167 ni N155 ni N154. Un seul marqueur — **pas** de tableau `selectionFree`.

Piège N169 (à venir) : `Effects.clearActionPreview` seulement. **Pas** Destroy. **Pas** `self.actionPreview = nil`. **Nil encore** `actionPreviewIndex` / `Valid` / `Color` (sinon skip N154 `return` sur Parent nil). `previewTile` reparent `self.root` si Parent nil, **après** le skip (le skip ne doit pas matcher). Name `ActionPreview` **conservé**. N154 skip inter-hovers **inchangé**. N168 selection **inchangé**. Distinct HUD leftover N167. Distinct flame leftover N152. Distinct visual V77 (ne pas merger `185a`). **Snapshotter** `actionPreview` **avant** clear dans le check calques. **Garder** les asserts N168. **Ne pas** flush. **Ne pas** casser N168 ni N167 ni N154 ni N155. HUD `refreshChatSheet` Destroy **conservé**.
