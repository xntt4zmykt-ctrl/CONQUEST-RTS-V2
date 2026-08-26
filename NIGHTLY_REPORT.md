# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 76)

Déclencheur : ouverture de la **PR #210** (`cursor/analyse-nocturne-du-codebase-90f0`) — BuildingModels BuildRing free-list (N166), specs N152 / N167.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-9914`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#210. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

HUD `notify` : free-list `feedFree` (**N167**). BuildingModels BuildRing : free-list `ringFree` (**N166**). Overlay Blast sphère : free-list `blastFree` (**N165**). Overlay BlastSmoke : free-list `smokeFree` (**N164**). Overlay Shockwave : free-list `shockFree` (**N163**). PointLight reste **enfant** de Blast. UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). Effects `clearSelection` Destroy+nil encore (leftover **N168**, N155 reuse **déjà** tant que la Part reste, **≠** visual V83 pulseRot).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #210 (passe 75) : claims vérifiés.** BuildingModels BuildRing free-list (N166, `ringFree` pop O(1), `Parent = nil` + push si encore parenté, pas Destroy, Name `BuildRing` conservé, Parent = **model** pas `overlay.root`, Size `(0.4, 3, 3)` + Transparency `0.4` + Color + CFrame euler N136 **avant** Tween). **N152 non livré** (freeze Size=API = visual V74, interdit). Spec N167 **livrée ici**. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #209** (`7188`) a **fermé V103** HUD préfixe — feel N153 **déjà**, **pas merger**. Visual **PR #211** (`8bb2`) FactoryOutput/SiloWarning phase rest — feel **déjà** `sin(time)` sans Position, **pas merger**. Visual **6c83** V102 compact — feel N114 **déjà**.

Cette passe a **livré N167** (ce que #210 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #210

| Claim #210 | Réalité à l’ouverture |
|---|---|
| BuildingModels BuildRing free-list (N166) | Oui. `ringFree` pop O(1). `Parent = nil` + push si encore parenté, pas Destroy. Name `BuildRing`. Parent = model. Reset Size `(0.4, 3, 3)` + Transparency `0.4` + Color + CFrame euler N136 avant Tween. Overlay explosion N163–N165 inchangés. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N167 | **N167 livré ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #210, visuelles #39/…/`7188` V103 **fermé** / `8bb2` V104 FactoryOutput / `6c83` V102 compact. **#210 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `7188` / `8bb2` / `6c83` / `fce3` / `b7e3` / `adfc` ni hardening `41e2` / `93f6` / `e291` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N167 est cosmétique client (fil HUD). Risques documentés, non corrigés ici (hors N167) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N167. Overlay `explosion` n’a plus de `Destroy` (Blast / Shockwave / BlastSmoke tous poolés). BuildingModels `playConstruction` BuildRing **poolé**. HUD `notify` TextLabel **poolé**. Effects `clearSelection` Destroy encore (leftover N168). UnitModels `place` flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze Size=API).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N167 du rapport #210. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| HUD `notify` TextLabel Instance.new+Destroy chaque message (N167) | `HUD.luau` (`notify` entrée TextLabel **seulement**, `removeEntry` Parent=nil, N153 while-shift **inchangé**, Dismiss `table.remove(index)` **inchangé**), `tests/client.luau` (commentaire leftover notifications **sans** flush + snapshot + reuse 1 entrée dans vagues) | Leftover N166. Free-list `self.feedFree`, pop O(1). `Parent = nil` + push si encore parenté, pas Destroy. Parent = **`self.feed`** (pas `overlay.root`). Reset Text + couleurs + transparences + LayoutOrder **avant** Parent. Pas `Theme.corner` / `Theme.stroke` au reuse. Recolor UIStroke. Recréer Dismiss si Destroy par le delay. Garde `LayoutOrder ~= born` dans le delay (plafond recycle avant 4.5 s). Overlay explosion / BuildRing **inchangés**. Cosmétique. Flame leftover N152 **alors**. `clearSelection` leftover N168 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), Effects `clearSelection` Destroy+nil (**N168**), `clearActionPreview` Destroy (**N169** leftover), HUD `refreshChatSheet` Destroy (commentaire source : trop simple), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, PlacementPreview Size rayon (visual V76, feel Size = API), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline** **et** N160 free-list, **pas merger**), tribus `humanTargetProtected`. Effects / UnitModels / WorldCamera / WorldRenderer / Overlay / BuildingModels / serveur **non édités**. Flame **non**. Blast **non**. BlastSmoke **non**. Shockwave **non**. DeliveryPulse **non**. `routePart` **non**. Dismiss `table.remove(index)` **non**. `clearSelection` Destroy **inchangé**. Destroy du modèle navire **inchangé**.

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
- HUD `notify` free-list (**N167**). BuildingModels BuildRing free-list (**N166**). Overlay Blast sphère free-list (**N165**). Overlay BlastSmoke free-list (**N164**). Overlay Shockwave free-list (**N163**). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). Effects `clearSelection` Destroy+nil (**N168**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N168)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N167** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N168** = nouveau. **N167** fermé ici.

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover feel Effects `clearSelection` Destroy+nil = **N168** (N155 reuse **déjà** tant que la Part vit, `clearActionPreview` Destroy **conservé**, **≠** visual V83 pulseRot, **≠** HUD `feedFree` / Overlay `blastFree` / `ringFree`). Visual V103 HUD préfixe **fermée** sur `7188` / PR #209 (feel N153 **déjà**, ne pas merger). Visual V104 FactoryOutput **ouverte** sur `8bb2` / PR #211 (feel **déjà** `sin(time)` sans Position — ne pas merger). Visual V102 compact préfixe **fermée** sur `6c83` (feel N114 **déjà**). Visual V101 `dirtyHead` **fermée** sur `fce3` (feel N112 **déjà**).

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N167 (pools Overlay/Effects/BuildingModels/HUD **déjà**). Distinct de N151 (trail Transparency), de N163–N167 (pools Overlay explosion / BuildRing / HUD feed), de N168 (`clearSelection`), de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**. Ne pas toucher trail. Ne pas toucher `BuildingModels`. Ne pas toucher Overlay. Ne pas toucher HUD. Ne pas toucher Effects.

**Problème :** N167 ferme le pool HUD feed. N168 reste ouvert (`clearSelection`). N151 ferme le trail. N153–N166 ferment HUD préfixe / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing. Reste, **chaque frame** (`UnitModels.place`, 60 Hz, une Part `EngineFlame` par ogive) :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (plus de pulse Size, `c0ec` / PR #151). Feel **garde** le pulse Z. Ne pas porter `c0ec`. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**. Role `"flame"` **inchangé**. Shape `Ball` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. HUD feed **déjà** N167 — ne pas y revenir. BuildRing **déjà** N166. Blast **déjà** N165. Visual V74 freeze **interdit** (feel ≠ visual). **Passes 61–76 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse `1.8 + math.sin(time * 18) * 0.45`. **Ne pas** geler Size (visual V74 Option A, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)`. XY `0.62` / base `1.8` / freq `18` / amp `0.45` **inchangés**.

2. **Garder le pulse.** Ne **pas** poser Size = API. Ne **pas** « fermer » trail / HUD / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast / BuildRing / feed (N151–N167 déjà). Ne **pas** lire `piece.part.Size` (alloc). Ne pas porter visual. Après N167. `BuildingModels` **non**. Overlay **non**. HUD **non**. Effects **non**. `createMissile` construction **non** (taille initiale `Vector3.new(0.62, 0.62, 2.3)` inchangée).

3. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N168 seulement.** N152 reste alors ouvert (feel-diverged vs V74). Ne pas inventer un cache Size. Ne pas skip-si-inchangé (N2, pas ici).

4. Tests « navires, missiles et interpolation » leftover N151 trail **et** leftover N148 mesh **et** leftover N147 Fin **doivent rester verts**. Tests « vagues de conquete » leftover N167 `feedFree` reuse **et** leftover N166 `BuildRing` reuse **et** leftover N165 `Blast` reuse **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` flame **seulement**, **un** `elseif`) **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N152. Overlay **non**. **Ne pas** éditer le serveur. **Ne pas** toucher Shockwave ni BlastSmoke ni Blast sphère ni BuildRing ni HUD feed ni `clearSelection`.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ N151 (trail Z) ≠ visual V74 (freeze Size=API, ne pas merger) ≠ N163 (Shockwave pool) ≠ N164 (BlastSmoke pool) ≠ N165 (Blast sphère pool) ≠ N166 (BuildRing pool) ≠ N167 (HUD feed pool) ≠ N168 (`clearSelection`) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N168 dans le même worker. Pulse Z **conservé** — ne pas figer à 1.8. Un `elseif` flame.

---

### ISSUE-N168 — Effects `clearSelection` Destroy+nil (feel)

**Priorité :** P3 alloc client Effects. Leftover explicite après N167 (HUD `feedFree` déjà). Distinct de N152 (UnitModels Size), de N155 (`selectTile` reuse Part **déjà** tant que `self.selection` vit), de N154 (`previewTile` skip **déjà**), de N156 (`flashFree` **déjà**), de visual V83 (`SelectionRing` pulseRot — **ne pas merger** `0b3d`). `Effects.clearSelection` **seulement**. Ne pas toucher `clearActionPreview` (Destroy **conservé**, leftover séparé). Ne pas toucher HUD. Ne pas toucher Overlay. Ne pas toucher UnitModels. Ne pas toucher BuildingModels.

**Problème :** N167 ferme le pool HUD feed. N152 reste ouvert (freeze interdit). N155 réutilise la Part `SelectedTerritory` d’un clic à l’autre **tant que** `self.selection` n’est pas nil. Reste, **chaque désélection** (`Effects.clearSelection`, clic vide / changement de mode / fermeture fiche) :

```
if self.selection then
    self.selection:Destroy()
    self.selection = nil
end
```

Le clic suivant (`selectTile`) refait `Instance.new("Part")`. N155 est **gaspillé** dès qu’on décoche. Distinct de leftover N152 (`Size = Vector3.new` flamme). Distinct de leftover N167 (`feedFree` **déjà** — **ne pas** partager). Distinct de leftover N154 (`previewTile` skip, `clearActionPreview` Destroy **encore**). Name `SelectedTerritory` **inchangé**. Tween pulse Transparency/Size **inchangé**. Caps flash **inchangés**.

Le banc `calques d'entites, effets et apercu` **assert aujourd’hui** `effects.selection == nil` après `clearSelection` — **il faudra le changer** (Parent nil, `self.selection` **conservé**, `rawequal` au `selectTile` suivant).

**Pourquoi 20K CCU :** leftover N155. 8 clients × (clic tuile / déselection / reclic) × `Instance.new("Part")` + Destroy. Une partie RTS produit des centaines de sélections. Pas d’autorité (cosmétique Effects). HUD feed **déjà** N167 — ne pas y revenir. BuildRing **déjà** N166. Visual V83 pulseRot **interdit** (ne pas merger `0b3d`). **Oubli de reparent `Parent = self.root` au reuse** = marqueur invisible. **Oubli de garder `self.selection`** = N155 retombe sur Instance.new. **Si le seul patch est un merger V83 : ne pas livrer.**

**Worker :**

1. Dans `Effects.clearSelection` seulement : **ne plus** `Destroy`. **Ne plus** `self.selection = nil`. Si `self.selection` et `self.selection.Parent` : `Parent = nil` (un second clear ne double-unparent pas). **Garder** la référence `self.selection`. Dans `Effects.selectTile`, après le `if not marker then` N155 (création inchangée, Name `SelectedTerritory`) : si `marker.Parent == nil` alors `marker.Parent = self.root` **avant** Color / Transparency / Size / CFrame / Tween. Reset Color + Transparency `0.38` + Size `(TILE_SIZE * 1.15, 0.28, TILE_SIZE * 1.15)` + CFrame **déjà** écrits par N155 — **ne pas** les retirer. Tween Create **conservé**. Name `SelectedTerritory` **conservé**. `clearActionPreview` Destroy **conservé**. `previewTile` N154 **conservé**. `tileFlash` N156 **conservé**. Pas de free-list tableau (un seul marqueur — ce n’est **pas** `feedFree` / `flashFree` / `ringFree`).

2. **Garder le marqueur.** Ne **pas** recréer après clear. Ne **pas** poser un Name différent. Ne **pas** toucher N155 reuse inter-clics (déjà `rawequal` 2000→2001). Ne **pas** toucher HUD N167. Ne **pas** geler Size (pas N152). Après N167. Flame **non** (N152). Overlay **non**. HUD **non**. `BuildingModels` **non**. Parent = **`self.root`** obligatoire au reuse (pas `overlay.root`, pas `hud.feed`).

3. Tests « calques d'entites, effets et apercu » leftover N155 `rawequal` 2000→2001 **doivent rester verts**. **Changer** l’assert `effects.selection == nil` : après `clearSelection`, `rawequal(effects.selection, selection)` **et** `selection.Parent == nil` **et** Name `SelectedTerritory`. Puis `selectTile(2000, …)` → `rawequal(effects.selection, selection)` **et** `rawequal(selection.Parent, effects.root)`. Tests « fil de notifications sature » leftover N153/N167 **sans** flush **doivent rester verts**. Tests « vagues de conquete » leftover N167 `feedFree` reuse **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client `calques` **doit rester vert** (N155 reuse 2000→2001, N154 preview 2001→2002, **nouveau** clear puis reselect `rawequal`). **Ne pas** `testFlushDelays` dans ce check. Check vagues leftover N167 / N166 / N165. Check notifications leftover N153/N167 sans flush. Check navires leftover N152 flame. **Ne pas** casser N167 (`feedFree` snapshot + reuse `rawequal` Parent `hud.feed`). **Ne pas** casser N166 (`ringFree` Parent model). **Ne pas** casser N155 (`rawequal` avant clear). Assert `effects.selection ~= nil` après clear. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `Effects.luau` (`clearSelection` **et** reparent dans `selectTile` si Parent nil). `tests/client.luau` **seulement** le check calques (commentaire leftover N168, **changer** l’assert nil, **garder** N155 `rawequal` 2000→2001 **avant** clear). `HUD.luau` **non**. `Overlay.luau` **non**. `BuildingModels.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher flame ni Blast ni BuildRing ni HUD feed. **Ne pas** modifier `clearActionPreview`. **Ne pas** merger visual V83.

**Contraintes :** pas de RemoteFunction. **N168 feel ≠ N167 (HUD feed pool) ≠ N155 (selectTile reuse déjà, Destroy encore) ≠ N154 (preview skip) ≠ N156 (flashFree) ≠ visual V83 (pulseRot, ne pas merger `0b3d`) ≠ N152 (flame Size, ne pas freeze V74) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N152 dans le même worker. Un seul marqueur — **pas** de tableau `selectionFree`. **Pas Destroy**. **Pas `self.selection = nil`**. Reparent `self.root` au `selectTile` suivant. **Changer l’assert nil du banc** — oubli = test rouge. Distinct `feedFree` / `flashFree` / `ringFree` / `blastFree` — **ne pas** partager. Name `SelectedTerritory` **obligatoire**. `clearActionPreview` Destroy **obligatoire** inchangé.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; HUD feed → **N167 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; HUD feed pool → **N167** ; Overlay explosion + chantier + fil clos ; `clearSelection` = **N168**) |
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
| N34–N151, N153–N167 | (voir rapport #210) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–76) |
| N168 | Effects `clearSelection` Destroy+nil | P3 | **nouveau** (`Parent = nil`, garder `self.selection`, reparent `selectTile`, N155 reuse **déjà**, `clearActionPreview` Destroy **conservé**, **≠** visual V83) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 / #169 / #171 / #173 / #176 / #178 / #181 / #183 / #185 / #187 / #189 / #191 / #193 / #195 / #197 / #200 / #202 / #204 / #206 / #208 / #210 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N167 HUD feed pool) |

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
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.71
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `fil de notifications sature` leftover N153 / leftover N167 commentaire **sans** flush ; `calques d'entites, effets et apercu` leftover N155 reuse / leftover N168 Destroy encore ; `hover spawn isolation` leftover N58 ; `construction du monde 3D` leftover N137/N138 ; `pose et capture de chaque type de batiment` leftover N136 / leftover N132 / leftover N162 commentaire **sans** flush / leftover N166 commentaire **sans** flush / leftover N167 commentaire ; `modeles procéduraux` leftover N150/N149 ; `apercu de placement pour chaque batiment` leftover N129 ; `livraison : le gain s'affiche sur la gare` leftover N159 **sans** flush ; `navires, missiles et interpolation` leftover N151 trail / leftover N152 flame Size / leftover N148 mesh / leftover N160 wake **sans** flush / leftover N161 splash **sans** flush / leftover N163 Shockwave **sans** flush / leftover N164 BlastSmoke **sans** flush / leftover N165 Blast **sans** flush, skip retraite id=1 N56 ; `vagues de conquete` N167 `feedFree` reuse (`testFlushDelays` → `#feedFree >= 1` **avant** N160, `hud:notify` texte nouveau `rawequal` Parent `hud.feed`, Dismiss recréé, `# == feedN - 1`) / leftover N166 `BuildRing` reuse / leftover N165 `Blast` reuse / leftover N164 `BlastSmoke` reuse / leftover N163 `Shockwave` reuse / leftover N162 `DeliveryPulse` reuse / leftover N161 `LandingSplash` reuse / leftover N160 `LaunchWake` reuse / leftover N159 `goldPopup` reuse / leftover N158 `floatingText` reuse / leftover N157 `conquestPulse` reuse / leftover N156 `tileFlash` reuse. Serveur **non** touché cette passe. `UnitModels.luau` **non** touché. `WorldCamera.luau` **non** touché. `Effects.luau` **non** touché. `PlacementPreview.luau` **non** touché. Overlay **non** touché. BuildingModels **non** touché. HUD feed **poolé**.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass76.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N167 est un pool TextLabel HUD vérifié par le banc headless (`notifications` sans flush + `vagues de conquete` flush + `hud:notify` reuse `rawequal` Parent `hud.feed`). Pulse flamme Size **inchangé** (N152). `clearSelection` Destroy **inchangé** (N168).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N167 n’ajoute **pas** de require (free-list locale HUD `notify`). N152 restera dans `UnitModels.place` flame. N168 restera dans `Effects.clearSelection`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Distinct trail N151. Distinct Overlay N163–N165 **déjà**. Distinct BuildRing N166 **déjà**. Distinct HUD N167 **déjà**. Distinct `clearSelection` leftover N168. Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N167 : `HUD.notify` entrée TextLabel seulement. Free-list `self.feedFree` **séparée** de Effects `textFree` / BuildingModels `ringFree`. `Parent = nil` + push, **pas** Destroy. Parent = **`self.feed`**. Reset Text + couleurs + transparences + LayoutOrder **avant** Parent. **Pas** `Theme.corner` / `Theme.stroke` au reuse (2e UICorner). Recréer Dismiss si `FindFirstChild("Dismiss")` nil (le delay Destroy la croix). Garde `LayoutOrder ~= born` dans le delay (un delay fantôme ne fond pas le message recyclé par le plafond). N153 while-shift **inchangé**. Dismiss `table.remove(index)` **inchangé**. Groupement **inchangé**. Distinct BuildRing N166. Distinct flame N152. Distinct visual V103 (préfixe, ne pas merger `7188`). `task.delay(4.5)` conservé. Lazy-init `feedFree` dans `notify`. **Ne pas** flush dans le check notifications (N153 Dismiss stubbe `task.delay`). Snapshot **après** le `testFlushDelays` des vagues. **Ne pas** nommer `textFree` **ni** `ringFree`. **Ne pas** casser N166 ni N165 ni N153.

Piège N168 (à venir) : `Effects.clearSelection` seulement. **Pas** Destroy. **Pas** `self.selection = nil`. `selectTile` reparent `self.root` si Parent nil. Name `SelectedTerritory` **conservé**. N155 reuse inter-clics **inchangé**. `clearActionPreview` Destroy **inchangé**. Distinct HUD leftover N167. Distinct flame leftover N152. Distinct visual V83 (ne pas merger `0b3d`). **Changer** l’assert `selection == nil` du check calques (sinon rouge). **Ne pas** flush. **Ne pas** casser N167 ni N155 ni N154.
