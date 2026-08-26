# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 74)

Déclencheur : ouverture de la **PR #206** (`cursor/analyse-nocturne-du-codebase-f293`) — Overlay BlastSmoke free-list (N164), specs N152 / N165.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-6512`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#206. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués.

Overlay Blast sphère : free-list `blastFree` (**N165**). Overlay BlastSmoke : free-list `smokeFree` (**N164**). Overlay Shockwave : free-list `shockFree` (**N163**). PointLight reste **enfant** de Blast (reuse `FindFirstChildWhichIsA`, pas un 2e pool). UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover **N152**, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). BuildingModels `playConstruction` BuildRing Instance.new+Destroy (leftover **N166**, Name `BuildRing` **conservé**, euler N136 **inline**, Parent = `model`, **≠** Overlay `blastFree` / `smokeFree` / `shockFree`).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #206 (passe 73) : claims vérifiés.** Overlay BlastSmoke free-list (N164, `smokeFree` pop O(1) **par itération**, `Parent = nil` + push si encore parenté, pas Destroy, Name `BlastSmoke` conservé, Size `(5+i)` + Transparency `0.22+i*0.07` + Color + CFrame avant Tween, Blast / PointLight / Shockwave inchangés alors). **N152 non livré** (freeze Size=API = visual V74, interdit). Spec N165 **corrigée ici**. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #205** (`fce3`) a **fermé V101** `dirtyHead` — feel N112 **déjà**, **pas merger**. Visual **6c83** V102 compact préfixe — feel N114 **déjà**, **pas merger**. Visual **PR #203** (`b7e3`) V100 trail **fermé**. Visual **PR #201** (`adfc`) V99 beacons **fermé**.

Cette passe a **livré N165** (ce que #206 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #206

| Claim #206 | Réalité à l’ouverture |
|---|---|
| Overlay BlastSmoke free-list (N164) | Oui. `smokeFree` pop O(1) par `i`. `Parent = nil` + push si encore parenté, pas Destroy. Name `BlastSmoke`. Reset Size `(5+i, 5+i, 5+i)` + Transparency `0.22 + i * 0.07` + Color + CFrame avant Tween. Blast `Destroy` **alors**. Shockwave N163 inchangé. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N165 | **N165 corrigé ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #206, visuelles #39/…/`fce3` V101 **fermé** / `6c83` V102 compact. **#206 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `6c83` / `fce3` / `b7e3` / `adfc` / `c94d` / `ae72` ni hardening `41e2` / `93f6` / `e291` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N165 est cosmétique client (sphère Blast Overlay). Risques documentés, non corrigés ici (hors N165) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N165. Overlay `explosion` n’a plus de `Destroy` (Blast / Shockwave / BlastSmoke tous poolés). BuildingModels `playConstruction` BuildRing **Destroy** encore (leftover N166). UnitModels `place` flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze Size=API).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N165 du rapport #206. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Overlay Blast sphère Instance.new+Destroy chaque explosion (N165) | `Overlay.luau` (`explosion` sphère Blast **seulement**, PointLight enfant, Shockwave / BlastSmoke / `routePart` / DeliveryPulse / LandingSplash / LaunchWake / `applyUnits` / `stepInterpolation` inchangés), `tests/client.luau` (commentaire leftover navires + snapshot + reuse 1 Blast dans vagues) | Leftover N164. Free-list `blastFree`, pop O(1). `Parent = nil` + push si encore parenté, pas Destroy. Name `Blast` conservé. Reset Size `(4, 4, 4)` + Transparency `0.15` + Color `255,190,110` + CFrame `ground.X, 14, ground.Z` **avant** Tween. PointLight : `FindFirstChildWhichIsA` + reset Brightness/Range/Color, sinon `Instance.new`. Tween Quart Out conservé. BlastSmoke N164 **inchangé**. Shockwave N163 **inchangé**. Cosmétique. Flame leftover N152 **alors**. BuildRing leftover N166 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), BuildingModels BuildRing Instance.new+Destroy (**N166**), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, PlacementPreview Size rayon (visual V76, feel Size = API), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline** **et** N160 free-list, **pas merger**), tribus `humanTargetProtected`. Effects / UnitModels / WorldCamera / WorldRenderer / BuildingModels / HUD / serveur **non édités**. Flame **non**. BlastSmoke **non**. Shockwave **non**. DeliveryPulse **non**. `routePart` **non**. Dismiss `table.remove(index)` **non**. `clearSelection` Destroy **inchangé**. Destroy du modèle navire **inchangé**.

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
- Overlay Blast sphère free-list (**N165**). Overlay BlastSmoke free-list (**N164**). Overlay Shockwave free-list (**N163**). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). BuildingModels BuildRing Instance.new+Destroy (**N166**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N166)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153–N165** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N166** = nouveau. **N165** fermé ici.

Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover feel BuildingModels `playConstruction` BuildRing Instance.new+Destroy = **N166** (Name `BuildRing` **conservé**, euler N136 **inline**, Parent = `model`, **≠** Overlay `blastFree` / `smokeFree` / `shockFree`). Visual V102 compact préfixe **fermée** sur `6c83` (feel N114 **déjà**, ne pas merger). Visual V101 `dirtyHead` **fermée** sur `fce3` / PR #205 (feel N112 **déjà**, ne pas merger). Visual V103 HUD feed leftover (feel N153 **déjà**, ne pas merger `ee71`).

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153–N165 (pools Overlay/Effects **déjà**). Distinct de N151 (trail Transparency), de N163–N165 (pools Overlay explosion), de N166 (BuildRing pool), de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**. Ne pas toucher trail. Ne pas toucher `BuildingModels`. Ne pas toucher Overlay. Ne pas toucher HUD. Ne pas toucher Effects.

**Problème :** N165 ferme le pool Blast. N166 reste ouvert (BuildRing). N151 ferme le trail. N153–N164 ferment HUD / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke. Reste, **chaque frame** (`UnitModels.place`, 60 Hz, une Part `EngineFlame` par ogive) :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (plus de pulse Size, `c0ec` / PR #151). Feel **garde** le pulse Z. Ne pas porter `c0ec`. Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**. Role `"flame"` **inchangé**. Shape `Ball` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. Blast **déjà** N165 — ne pas y revenir. BlastSmoke **déjà** N164 — ne pas y revenir. Shockwave **déjà** N163 — ne pas y revenir. Visual V74 freeze **interdit** (feel ≠ visual). **Passes 61–74 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse `1.8 + math.sin(time * 18) * 0.45`. **Ne pas** geler Size (visual V74 Option A, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)`. XY `0.62` / base `1.8` / freq `18` / amp `0.45` **inchangés**.

2. **Garder le pulse.** Ne **pas** poser Size = API. Ne **pas** « fermer » trail / HUD / preview / select / flash / pulse / texte / gold / wake / splash / delivery / Shockwave / BlastSmoke / Blast (N151–N165 déjà). Ne **pas** lire `piece.part.Size` (alloc). Ne pas porter visual. Après N165. `BuildingModels` **non**. Overlay **non**. HUD **non**. Effects **non**. `createMissile` construction **non** (taille initiale `Vector3.new(0.62, 0.62, 2.3)` inchangée).

3. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N166 seulement.** N152 reste alors ouvert (feel-diverged vs V74). Ne pas inventer un cache Size. Ne pas skip-si-inchangé (N2, pas ici).

4. Tests « navires, missiles et interpolation » leftover N151 trail **et** leftover N148 mesh **et** leftover N147 Fin **doivent rester verts**. Tests « vagues de conquete » leftover N165 `Blast` reuse **et** leftover N164 `BlastSmoke` reuse **et** leftover N163 `Shockwave` reuse **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` flame **seulement**, **un** `elseif`) **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N152. Overlay **non**. **Ne pas** éditer le serveur. **Ne pas** toucher Shockwave ni BlastSmoke ni Blast sphère ni BuildRing.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ N151 (trail Z) ≠ visual V74 (freeze Size=API, ne pas merger) ≠ N163 (Shockwave pool) ≠ N164 (BlastSmoke pool) ≠ N165 (Blast sphère pool) ≠ N166 (BuildRing pool) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N166 dans le même worker. Pulse Z **conservé** — ne pas figer à 1.8. Un `elseif` flame.

---

### ISSUE-N166 — BuildingModels `playConstruction` BuildRing Instance.new+Destroy (feel)

**Priorité :** P3 alloc client BuildingModels. Leftover explicite après N165 (Blast sphère free-list déjà). Distinct de N152 (UnitModels Size), de N153–N165 (pools Overlay/Effects), de N136 (euler BuildRing **déjà** inline). `BuildingModels.playConstruction` bague `BuildRing` **seulement**. Ne pas toucher les parts qui montent (drop / sort Y). Ne pas toucher Overlay.explosion. Ne pas toucher Blast / BlastSmoke / Shockwave. Ne pas toucher `routePart`. Ne pas toucher HUD. Ne pas toucher UnitModels. Ne pas toucher Effects. Ne pas toucher `animate`. Ne pas toucher `create`.

**Problème :** N165 ferme le pool Blast Overlay. N152 reste ouvert (freeze interdit). Reste, **chaque chantier** (`BuildingModels.playConstruction`, bague au sol) :

```
local ring = Instance.new("Part")
ring.Name = "BuildRing"
ring.Anchored = true
ring.CanCollide = false
ring.CanTouch = false
ring.CanQuery = false
ring.CastShadow = false
ring.Shape = Enum.PartType.Cylinder
ring.Material = Enum.Material.Neon
ring.Color = Color3.fromRGB(255, 214, 130)
ring.Transparency = 0.4
ring.Size = Vector3.new(0.4, 3, 3)
ring.CFrame = CFrame.new(ground) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))
ring.Parent = model
-- ... tween Size (0.4, 16, 16) / Transparency 1 sur `total` ...
task.delay(total + 0.2, function()
    if ring.Parent then
        ring:Destroy()
    end
end)
```

Instance.new Part + Destroy à `total + 0.2` (~2.7 s) par pose animée. Overlay explosion **réutilise déjà** (`blastFree` / `smokeFree` / `shockFree`). BuildRing non. Distinct de leftover N152 (`Size = Vector3.new` flamme). Distinct de leftover N165 (`blastFree` **déjà** — **ne pas** partager). Name `BuildRing` **inchangé**. Shape Cylinder **inchangé**. Material Neon **inchangé**. Size départ `Vector3.new(0.4, 3, 3)` **inchangé** (**réécrire** au reuse, le tween a fait `(0.4, 16, 16)`). Color `Color3.fromRGB(255, 214, 130)` **inchangée**. Transparency départ `0.4` **inchangée**. CFrame `CFrame.new(ground) * fromEulerAnglesYXZ(0, 0, math.rad(90))` **inchangé** (**réécrire** : `ground` **varie** ; euler N136 **inline** — **ne pas** cuire un rot). Tween Quad Out Size/Transparency **inchangé**. `task.delay(total + 0.2)` **inchangé**. Garde Destroy devient `Parent = nil` + push si encore parenté. Parent = **`model`** (**pas** `overlay.root`). Drop / sort Y des parts **inchangés**. Overlay explosion **inchangé**.

**Pourquoi 20K CCU :** leftover N165. 8 clients × poses (ville/port/usine/silo/SAM/…) × `Instance.new` + Tween + Destroy 2.7 s. Pas d’autorité (cosmétique chantier). Blast **déjà** N165 — ne pas y revenir. BlastSmoke **déjà** N164 — ne pas y revenir. Shockwave **déjà** N163 — ne pas y revenir. Flame leftover N152 **alors** (ne pas freeze). Overlay explosion **doit** continuer (`blastFree` / `smokeFree` / `shockFree`). Oubli de reset Size / Transparency / CFrame au reuse = bague trop grande (`(0.4, 16, 16)`) au mauvais `ground`. **Si le bâtiment est Destroy avant le delay** (capture / destruction pendant les ~2.5 s) : en Studio le Destroy parent est récursif → `ring.Parent` nil → miss pool, prochain chantier `Instance.new` (OK). Ne **pas** reparenter vers `overlay.root` pour « sauver » la bague (changement visuel).

**Worker :**

1. Dans `BuildingModels.playConstruction` bague `BuildRing` seulement : free-list d’ancres (`BuildingModels.ringFree` tableau **module**, pop O(1), lazy-init dans `playConstruction` — **pas** `Overlay.new`). **Pas** `blastFree` (c’est Overlay N165). **Pas** `smokeFree` (c’est Overlay N164). **Pas** `shockFree` (c’est Overlay N163). **Pas** `pulseFree` (c’est Effects N157). Si une Part libre : **réutiliser** (pas `Instance.new`). Writes **avant** Tween : `Size = Vector3.new(0.4, 3, 3)`, `Transparency = 0.4`, `Color = Color3.fromRGB(255, 214, 130)`, `CFrame = CFrame.new(ground) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))`, `Parent = model`. Name `BuildRing` **conservé**. Euler N136 **inline** — **ne pas** cuire `wakeRot` / `pulseRot` / `ringRot`. **Ne pas** Destroy à `total + 0.2` : `Parent = nil` + push free-list (`if ring.Parent` devient push seulement si encore parenté — un second delay fantôme ne double-push pas). Sinon : création inchangée (`Instance.new` Part Name `BuildRing`, Cylinder, Neon, Size `(0.4, 3, 3)`). Tween Create **conservé** (Size / Transparency restart). Pas de `self.live`. **Ne pas** wrapper un record. **Ne pas** partager `blastFree` / `smokeFree` / `shockFree` / `deliveryFree` / `splashFree` / `wakeFree` / `goldFree` / `textFree` / `pulseFree` / `flashFree`. **Ne pas** modifier Overlay.explosion. **Ne pas** changer le drop / sort Y. Un pop par `playConstruction`.

2. **Garder la bague.** Ne **pas** recréer au reuse. Ne **pas** retirer Name `BuildRing`. Ne **pas** toucher Overlay N165/N164/N163. Ne **pas** geler Size (pas N152). Après N165. Flame **non** (N152). HUD **non**. `UnitModels` **non**. Effects **non**. Overlay **non**. Parent = **`model`** obligatoire (pas `overlay.root`).

3. Tests « pose et capture de chaque type de batiment » leftover N136 euler **et** leftover N162 DeliveryPulse **sans** flush **doivent rester verts**. **Ne pas** `testFlushDelays` dans le check pose (N162 DeliveryPulse doit rester parenté jusqu’aux vagues). Tests « vagues de conquete » leftover N165 `Blast` reuse **et** leftover N164 `BlastSmoke` reuse **et** leftover N163 `Shockwave` reuse **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client `pose` **doit rester vert** (playConstruction **sans** flush, **pas** de `testFlushDelays`). Après flush des delays **dans le check vagues** (déjà un `testFlushDelays` — les BuildRing du check pose y tombent **dans le banc stubs**, Destroy parent non récursif), `BuildingModels.ringFree` `# >= 1` ; snapshot `pooledRing` **avant** `applyUnits` N160 **et avant** `applyBuildingDelta` N162 (N162 `animateFrom = 0` + CITY+FACTORY **consomme 2** bagues). Réparente (`rawequal` Parent = `overlay.buildings[cityIndex]` **ou** `overlay.buildings[factoryIndex]`, **pas** `overlay.root`, Name `BuildRing`). **Réécrire** Size `(0.4, 3, 3)` + Transparency `0.4` + CFrame **avant** Tween — oubli = bague `(0.4, 16, 16)` au `ground` précédent. Ne **pas** flush dans le check « pose ». **Ne pas** casser N165 (`blastFree` snapshot + reuse `rawequal` Name `Blast`, PointLight enfant). **Ne pas** casser N164 (`smokeFree` snapshot + reuse 5 smokes). **Ne pas** casser N163 (`shockFree` snapshot + reuse Name `Shockwave`). **Ne pas** casser N162 (`deliveryFree` snapshot **avant** N160, reuse **après** reconstruct). Assert `pooledRing ~= pooledBlast`. Assert `pooledRing ~= pooledSmoke`. Assert `pooledRing ~= pooledShock`. Check vagues leftover N165 / N164 / N163 / N162. Check pose leftover N136 euler / leftover N162 sans flush. Check navires leftover N152 flame. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `BuildingModels.luau` (`playConstruction` bague BuildRing **seulement**). `tests/client.luau` **seulement si** le check pose ne mentionne pas encore N166 (commentaire leftover, **garder** N136 euler / N162 sans flush). `Overlay.luau` **non**. `Effects.luau` **non**. `HUD.luau` **non**. `UnitModels.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher flame ni Blast ni BlastSmoke ni Shockwave ni DeliveryPulse. **Ne pas** modifier `routePart`. **Ne pas** changer le `Parent = nil` Overlay.

**Contraintes :** pas de RemoteFunction. **N166 feel ≠ N165 (Blast sphère pool) ≠ N164 (BlastSmoke pool) ≠ N163 (Shockwave pool) ≠ N152 (flame Size, ne pas freeze V74) ≠ N136 (euler déjà) ≠ visual V85 (euler BuildRing fermé, ne pas merger `7be5`) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N152 dans le même worker. Free-list — ne pas skip CFrame si `ground` change, ne pas skip Size. Un `playConstruction` — ne pas splitter le drop des parts. `task.delay(total + 0.2)` **conservé**. Ne pas `table.remove` la free-list (pop O(1) depuis la fin). Ancre `Parent = nil` **pas** Destroy. Distinct `blastFree` / `smokeFree` / `shockFree` / `deliveryFree` / `splashFree` / `wakeFree` / `goldFree` / `textFree` / `pulseFree` / `flashFree` — **ne pas** partager. **Reset Size + CFrame + Transparency + Color avant Tween** — oubli = bague fantôme / trop grande (`ground` varie). Name `BuildRing` **obligatoire**. Parent = **`model`** **obligatoire**. Euler N136 **inline obligatoire**. Overlay explosion **obligatoire** inchangé. Nommer `ringFree` **pas** `blastFree` **pas** `smokeFree` **pas** `shockFree` **pas** `pulseFree`. Exposer `BuildingModels.ringFree` (le banc y lit, ce n’est pas un `self` Overlay).

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; Blast sphère → **N165 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (… ; Blast sphère pool → **N165** ; Overlay explosion clos ; BuildRing pool = **N166**) |
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
| N34–N151, N153–N165 | (voir rapport #206) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–74) |
| N166 | BuildingModels `playConstruction` BuildRing Instance.new+Destroy | P3 | **nouveau** (`playConstruction` bague free-list `ringFree`, Name `BuildRing` **conservé**, Parent = `model`, euler N136 inline, **≠** Overlay `blastFree` / `smokeFree` / `shockFree`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 / #169 / #171 / #173 / #176 / #178 / #181 / #183 / #185 / #187 / #189 / #191 / #193 / #195 / #197 / #200 / #202 / #204 / #206 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N165 Blast pool) |

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

Client : **35/35 OK** — dont `fil de notifications sature` leftover N153 ; `calques d'entites, effets et apercu` leftover N155 reuse ; `hover spawn isolation` leftover N58 ; `construction du monde 3D` leftover N137/N138 ; `pose et capture de chaque type de batiment` leftover N136 / leftover N132 / leftover N162 commentaire **sans** flush ; `modeles procéduraux` leftover N150/N149 ; `apercu de placement pour chaque batiment` leftover N129 ; `livraison : le gain s'affiche sur la gare` leftover N159 **sans** flush ; `navires, missiles et interpolation` leftover N151 trail / leftover N152 flame Size / leftover N148 mesh / leftover N160 wake **sans** flush / leftover N161 splash **sans** flush / leftover N163 Shockwave **sans** flush / leftover N164 BlastSmoke **sans** flush / leftover N165 Blast **sans** flush, skip retraite id=1 N56 ; `vagues de conquete` N165 `Blast` reuse (`testFlushDelays` → `#blastFree >= 1` **avant** N160, `explosion(40, 40, 6)` `rawequal` Parent root, Name `Blast`, PointLight enfant, `# == blastN - 1`) / leftover N164 `BlastSmoke` reuse (`#smokeFree >= 5` **avant** N160, `explosion(40, 40, 6)` `rawequal` Parent root, Name `BlastSmoke`, `# == smokeN - 5`) / leftover N163 `Shockwave` reuse / leftover N162 `DeliveryPulse` reuse / leftover N161 `LandingSplash` reuse / leftover N160 `LaunchWake` reuse / leftover N159 `goldPopup` reuse / leftover N158 `floatingText` reuse / leftover N157 `conquestPulse` reuse / leftover N156 `tileFlash` reuse. Serveur **non** touché cette passe. `UnitModels.luau` **non** touché. `WorldCamera.luau` **non** touché. `Effects.luau` **non** touché. `PlacementPreview.luau` **non** touché. `HUD.luau` **non** touché. `BuildingModels.luau` **non** touché. Overlay Shockwave **inchangé**. Overlay BlastSmoke **inchangé**. Overlay Blast sphère **poolé**.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass74.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N165 est un pool sphère Blast vérifié par le banc headless (`navires` sans flush + `vagues de conquete` flush + `explosion(40, 40, 6)` reuse `rawequal`). Pulse flamme Size **inchangé** (N152). BuildRing **inchangé** (N166).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N165 n’ajoute **pas** de require (free-list locale Overlay `explosion`). N152 restera dans `UnitModels.place` flame. N166 restera dans `BuildingModels.playConstruction` bague.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Distinct trail N151. Distinct Overlay N163–N165 **déjà**. Distinct BuildRing leftover N166. Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N165 : `Overlay.explosion` sphère Blast seulement. Free-list `blastFree` **séparée** de `smokeFree` / `shockFree` / `deliveryFree` / `splashFree` / `wakeFree` / `goldFree` / `textFree` / `pulseFree` / `flashFree`. Tween Size/Transparency **conservé**. `Parent = nil` + push, **pas** Destroy. Name `Blast` **conservé**. Reset Size `(4, 4, 4)` + Transparency `0.15` + Color `255,190,110` + CFrame `ground.X, 14, ground.Z` **avant** Tween (`worldRadius` et `ground` **varient**). PointLight enfant **réutilisé** (reset Brightness/Range, pas un 2e pool). Distinct BlastSmoke N164. Distinct Shockwave N163. Distinct flame N152. Distinct BuildRing leftover N166. `task.delay` 1.3 s conservé. Lazy-init `blastFree` dans `explosion` (pas `Overlay.new`). **Ne pas** modifier `routePart`. BlastSmoke `smokeFree` **obligatoire**. Shockwave `shockFree` **obligatoire**. Le check navires n’a pas flushé — snapshot `blastFree` `# >= 1` après le premier `testFlushDelays` des vagues, reuse **lors** de `explosion(40, 40, 6)` N163/N164. **Ne pas** nommer `smokeFree` **ni** `shockFree` **ni** `pulseFree`. **Ne pas** casser N164 ni N163. Le banc applique le tween **immédiatement** : ne **pas** assert `Brightness == 8` après `Play()` (le tween pose 0).

Piège N166 (à venir) : `BuildingModels.playConstruction` bague BuildRing seulement. Free-list `BuildingModels.ringFree` **séparée** de Overlay `blastFree` / `smokeFree` / `shockFree`. Tween Size/Transparency **conservé**. `Parent = nil` + push, **pas** Destroy. Name `BuildRing` **conservé**. Parent = **`model`** (**pas** `overlay.root`). Reset Size `(0.4, 3, 3)` + Transparency `0.4` + Color `255,214,130` + CFrame `CFrame.new(ground) * fromEulerAnglesYXZ(0, 0, math.rad(90))` **avant** Tween (`ground` **varie**). Euler N136 **inline** — **ne pas** cuire un rot. Distinct Blast N165. Distinct flame N152. `task.delay(total + 0.2)` conservé. Lazy-init `ringFree` dans `playConstruction` (pas `BuildingModels.create`). **Ne pas** modifier Overlay.explosion. **Ne pas** flush dans le check pose (N162 DeliveryPulse). Snapshot **avant** N162 `applyBuildingDelta` (CITY+FACTORY `animateFrom = 0` consomme 2). **Ne pas** nommer `blastFree` **ni** `smokeFree` **ni** `shockFree` **ni** `pulseFree`. **Ne pas** casser N165 ni N164 ni N163 ni N162.
