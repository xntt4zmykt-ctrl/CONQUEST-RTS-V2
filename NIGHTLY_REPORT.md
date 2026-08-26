# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 66)

Déclencheur : ouverture de la **PR #189** (`cursor/analyse-nocturne-du-codebase-ce40`) — Effects `tileFlash` free-list (N156), specs N152 / N157.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-6a4b`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#189. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. Camera overview : lerp mire `fx/fy/fz` (N121) ; champs `focusX/Y/Z` (N122) ; shake `sx/sy/sz` (N119) ; offset YXZ `ox/oy/oz` (N120) ; pose `CFrame.new * rotation` (N118). Minimap : `setFocus(x,y,z)` nombres (N123). Radar / Flag / Boom : `fromEulerAnglesYXZ` (N124). Overlay navire : roulis `fromEulerAnglesYXZ` (N125). Overlay camion : roues `fromEulerAnglesYXZ` (N126). `UnitModels.place` radar : `fromEulerAnglesYXZ` (N127). `UnitModels.place` flag : `fromEulerAnglesYXZ` (N128). `PlacementPreview.update` footprint : `fromEulerAnglesYXZ` (N129). Overlay LaunchWake : `fromEulerAnglesYXZ` (N130, inline — **≠** visual V78 `wakeRot` cuit). Overlay LandingSplash : `fromEulerAnglesYXZ` (N131, inline — **≠** visual V79 `wakeRot`). Overlay DeliveryPulse : `fromEulerAnglesYXZ` (N132, inline — **≠** visual V80 `wakeRot` cuit). Overlay Shockwave : `fromEulerAnglesYXZ` (N133). Effects `conquestPulse` ring : `fromEulerAnglesYXZ` (N134). WorldRenderer OceanGlint : `fromEulerAnglesYXZ` (N135). BuildingModels `BuildRing` : `fromEulerAnglesYXZ` (N136). WorldRenderer TreeTrunk / SavannaTrunk : `fromEulerAnglesYXZ` (N137). WorldRenderer Rock : `fromEulerAnglesYXZ` (N138). BuildingModels `cylinder()` : `fromEulerAnglesYXZ` (N139). BuildingModels toits usine : `fromEulerAnglesYXZ` (N140). BuildingModels portes silo : `fromEulerAnglesYXZ` (N141). BuildingModels rampes SAM : `fromEulerAnglesYXZ` (N142). UnitModels houle `addWake` : `fromEulerAnglesYXZ` (N143). UnitModels proue `Bow` : `fromEulerAnglesYXZ` (N144). UnitModels rampe `LandingRamp` : `fromEulerAnglesYXZ` (N145). UnitModels corps missile `MissileBody` : `fromEulerAnglesYXZ` (N146). UnitModels ailettes `Fin` : `fromEulerAnglesYXZ` (N147). UnitModels `buildCarrier` mesh : `visual.pieces` (N148). BuildingModels `CityWindows` : `rest.X` (N149). BuildingModels beacons : `rest.Z` (N150). UnitModels `place` trail : `offset.Z` (N151). HUD `feedEntries` plafond : décalage préfixe (N153). Effects `previewTile` : skip index+valid+color (N154). Effects `selectTile` : reuse Part (N155). Effects `tileFlash` : free-list (N156). Effects `conquestPulse` : free-list (N157). Plus aucun `CFrame.Angles` vivant côté client (hors stubs de banc). Plus aucun `child.Position` / `offset.Position` 60 Hz. Plus aucun `table.remove(1)` client (Dismiss garde `table.remove(index)`). UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover N152, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). Effects `floatingText` Instance.new+Destroy chaque chiffre (leftover N158, arbre Billboard **conservé**, **≠** N157 `pulseFree`).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #189 (passe 65) : claims vérifiés.** Effects `tileFlash` free-list (N156, `flashFree` pop O(1), `Parent = nil` + push, pas Destroy, caps 90/28, Tween pulse conservé). **N152 non livré** (freeze Size=API = visual V74, interdit). Spec N157 **corrigée ici**. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #188** (`d645`) a **fermé V92** `addWake` — feel N143 **déjà** inline, **pas merger** `c62f`. Visual **PR #190** (`29b4`) a **fermé V93** `Bow` — feel N144 **déjà** inline, **pas merger** `c62f`. Visual V94 `LandingRamp` **ouvert** — feel N145 **déjà** inline, **pas merger** `95ed`. Visual **PR #170** (`490f`) a **fermé V82** `conquestPulse` `pulseRot` — feel N134 **inline** Y=3 **et** N157 **free-list** sans Name, **pas merger**.

Cette passe a **livré N157** (ce que #189 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #189

| Claim #189 | Réalité à l’ouverture |
|---|---|
| Effects `tileFlash` free-list (N156) | Oui. `flashFree` pop O(1). `Parent = nil` + push, pas Destroy. Caps 90/28. Tween pulse conservé. Recette leftover N155, pas merger visual V83. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N157 | **N157 corrigé ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #189, visuelles #39/…/`d645` V92 **fermé**. **#189 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `d645` / `930a` / `6095` / `9fd4` / `f9ec` / `2b04` / `75ce` / `7be5` / `0b3d` / `490f` / `47c0` / `a597` / `54d6` / `6183` / `185a` / `70a5` / `c0ec` / `1b5c` ni hardening `41e2` / `93f6` / `e291` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N157 est cosmétique client (anneaux Effects). Risques documentés, non corrigés ici (hors N157) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N157. `CARRIER_MESH_ID` reste `""` — le chemin mesh n’est pas exercé par le banc (N148 est un crash latent, pas un vert runtime). BuildingModels `animate` n’a plus de `child.Position` 60 Hz. UnitModels n’a plus de `offset.Position` 60 Hz. UnitModels n’a plus de `CFrame.Angles` vivant. `HUD.feedEntries` plafond **sans** `table.remove(1)` (N153). Effects `previewTile` **sans** rewrite CFrame/Color si hover inchangé (N154). Effects `selectTile` **sans** Destroy+recreate (N155). Effects `tileFlash` **sans** Destroy à 0.7 s (N156). Effects `conquestPulse` **sans** Destroy à 1 s (N157). Serveur feel : `table.remove` bateaux/missiles encore (hardening N105–N106, ne pas porter). UnitModels `place` flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze Size=API). Effects `floatingText` Instance.new+Destroy (leftover N158).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N157 du rapport #189. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Effects `conquestPulse` Instance.new+Destroy chaque onde (N157) | `Effects.luau` (`conquestPulse` **seulement**, `tileFlash` / `selectTile` / `previewTile` / `floatingText` inchangés), `tests/client.luau` (commentaire fil + assert reuse) | Leftover N156. Free-list `pulseFree`, pop O(1). `Parent = nil` + push, pas Destroy. Euler N134 inline Y=3 inchangé. Pas de Name. Tween pulse conservé. Cosmétique. Flame leftover N152 **alors**. HUD N153 **inchangé**. `previewTile` **inchangé**. `selectTile` **inchangé**. `tileFlash` **inchangé**. `floatingText` leftover N158 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), Effects `floatingText` Instance.new+Destroy (**N158**), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, PlacementPreview Size rayon (visual V76, feel Size = API), PlacementPreview early-out hover (visual V77, **pas merger**), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline**, **pas merger**), Overlay LandingSplash `wakeRot` (visual V79, feel N131 **inline**, **pas merger**), Overlay DeliveryPulse `wakeRot` (visual V80, feel N132 **inline**, **pas merger**), Overlay Shockwave `wakeRot` (visual V81, feel N133 **inline**, **pas merger**), Effects `conquestPulse` `pulseRot` (visual V82, feel N134 **inline** Y=3 **et** N157 free-list, **pas merger** `490f`), Effects SelectionRing `pulseRot` (visual V83, feel N155 **reuse Part** Name `SelectedTerritory`, **pas merger** `0b3d`), tribus `humanTargetProtected`. Overlay / UnitModels / WorldCamera / WorldRenderer / BuildingModels / HUD / serveur **non édités**. Flame **non**. `previewTile` **non**. `selectTile` **non**. `tileFlash` **non**. Dismiss `table.remove(index)` **non**. `floatingText` **non**. `clearSelection` Destroy **inchangé**. `lossWave` barycentre **inchangé**.

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
- Overlay interpolation X/Z + yaw euler (**N117**) **et** camion `segRot` (**N115**) **et** roulis navire (**N125**) **et** roues camion (**N126**). Camera : lerp nombres (**N121**) + champ `focusX/Y/Z` (**N122**) + shake (**N119**) + offset (**N120**) + pose (**N118**). Minimap `setFocus(x,y,z)` (**N123**). Radar/Flag/Boom euler (**N124**). `UnitModels.place` radar euler (**N127**) **et** flag euler (**N128**). `PlacementPreview.update` footprint euler (**N129**). Overlay LaunchWake euler (**N130**). Overlay LandingSplash euler (**N131**). Overlay DeliveryPulse euler (**N132**). Overlay Shockwave euler (**N133**). Effects `conquestPulse` ring euler (**N134**) **et** free-list (**N157**). WorldRenderer OceanGlint euler (**N135**). BuildingModels `BuildRing` euler (**N136**). WorldRenderer trunks euler (**N137**). WorldRenderer Rock euler (**N138**). BuildingModels `cylinder()` euler (**N139**). BuildingModels toits usine euler (**N140**). BuildingModels portes silo euler (**N141**). BuildingModels rampes SAM euler (**N142**). UnitModels houle `addWake` euler (**N143**). UnitModels proue `Bow` euler (**N144**). UnitModels rampe `LandingRamp` euler (**N145**). UnitModels corps missile `MissileBody` euler (**N146**). UnitModels ailettes `Fin` euler (**N147**). UnitModels mesh carrier `visual.pieces` (**N148**). BuildingModels `CityWindows` `rest.X` (**N149**). BuildingModels beacons `rest.Z` (**N150**). UnitModels trail `offset.Z` (**N151**). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). HUD `feedEntries` décalage préfixe (**N153**). Effects `previewTile` skip index+valid+color (**N154**). Effects `selectTile` reuse Part (**N155**). Effects `tileFlash` free-list (**N156**). Effects `conquestPulse` free-list (**N157**). Effects `floatingText` Instance.new+Destroy (**N158**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N158)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153**, **N154**, **N155**, **N156**, **N157** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N158** = nouveau. **V73 / N127 / N128** fermés passe 49. **N129 / N130** fermés passe 50. **N131 / N132** fermés passe 51. **N133 / N134** fermés passe 52. **N135 / N136** fermés passe 53. **N137 / N138** fermés passe 54. **N139 / N140** fermés passe 55. **N141 / N142** fermés passe 56. **N143 / N144** fermés passe 57. **N145 / N146** fermés passe 58. **N147 / N148** fermés passe 59. **N149 / N150** fermés passe 60. **N151** fermé passe 61. **N153** fermé passe 62. **N154** fermé passe 63. **N155** fermé passe 64. **N156** fermé passe 65. **N157** fermé ici (porté, pas mergé). Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover feel Effects `floatingText` Instance.new+Destroy = **N158** (arbre Billboard **conservé**, **≠** N157 `pulseFree` / visual V82 `pulseRot`, ne pas merger `490f`). Flamme `Size = Vector3.new` visual V74 **fermée** Option A sur `c0ec` (Size = API, ne pas porter). PlacementPreview Size rayon = visual V76 **fermée** sur `70a5` (feel Size = API, ne pas merger). PlacementPreview early-out hover = visual V77 **fermée** sur `185a` (feel **pas merger**). Overlay LaunchWake `wakeRot` = visual V78 **fermée** sur `6183` (feel N130 **inline**, ne pas merger). Overlay LandingSplash `wakeRot` = visual V79 **fermée** sur `54d6` (feel N131 **inline**, ne pas merger). Overlay DeliveryPulse `wakeRot` = visual V80 **fermée** sur `a597` (feel N132 **inline**, ne pas merger). Overlay Shockwave `wakeRot` = visual V81 **fermée** sur `47c0` (feel N133 **inline**, ne pas merger). Effects `conquestPulse` `pulseRot` = visual V82 **fermée** sur `490f` (feel N134 **inline** Y=3 **et** N157 free-list, **≠** visual surface+0.8, ne pas merger). Effects SelectionRing `pulseRot` = visual V83 **fermée** sur `0b3d` (feel N155 **reuse Part** Name `SelectedTerritory`, ne pas merger). Visual V85 BuildRing **fermée** sur `7be5` / PR #174 (feel N136 **déjà**, ne pas merger). Visual V84 OceanGlint **fermée** sur `8015`. Visual V86 TreeTrunk **fermée** sur `75ce` / PR #177 (feel N137 **déjà**, ne pas merger `c299`). Visual V87 Rock **fermée** sur `2b04` / PR #179 (feel N138 **déjà**, ne pas merger `c299`). Visual V88 `cylinder()` **fermée** sur `f9ec` / PR #180 (feel N139 **déjà**, ne pas merger `a8e1`). Visual V89 toits usine **fermée** sur `9fd4` / PR #182 (feel N140 **déjà**, ne pas merger `a8e1`). Visual V90 portes silo **fermée** sur `6095` / PR #184 (feel N141 **déjà**, ne pas merger `4885`). Visual V91 rampes SAM **fermée** sur `930a` / PR #186 (feel N142 **déjà**, ne pas merger `4885`). Visual V92 `addWake` **fermée** sur `d645` / PR #188 (feel N143 **déjà**, ne pas merger `c62f`). Visual V93 `Bow` **fermée** sur `29b4` / PR #190 (feel N144 **déjà**, ne pas merger `c62f`). Visual V94 `LandingRamp` **ouvert** (feel N145 **déjà**, ne pas merger `95ed`).

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153 (HUD plafond **déjà**), N154 (`previewTile` skip **déjà**), N155 (`selectTile` reuse **déjà**), N156 (`tileFlash` free-list **déjà**) et N157 (`conquestPulse` pool **déjà**). Distinct de N151 (trail Transparency), de N153 (HUD feed), de N154 (previewTile skip), de N155 (`selectTile` reuse), de N156 (`tileFlash` pool), de N157 (`conquestPulse` pool), de N158 (`floatingText` pool), de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**. Ne pas toucher trail. Ne pas toucher `BuildingModels`. Ne pas toucher Overlay. Ne pas toucher HUD. Ne pas toucher Effects.

**Problème :** N151 ferme le trail. N153 ferme le plafond HUD. N154 ferme le skip hover. N155 ferme le reuse sélection. N156 ferme le pool éclats. N157 ferme le pool anneaux. Reste, **chaque frame** (`UnitModels.place`, 60 Hz, une Part `EngineFlame` par ogive) :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (plus de pulse Size, `c0ec` / PR #151). Feel **garde** le pulse Z. Ne pas porter `c0ec`. Distinct de leftover N151 (`offset.Z` trail **déjà**). Distinct de leftover N153 (HUD plafond **déjà**). Distinct de leftover N154 (`previewTile` skip **déjà**). Distinct de leftover N155 (`selectTile` reuse **déjà**). Distinct de leftover N156 (`tileFlash` pool **déjà**). Distinct de leftover N157 (`conquestPulse` pool **déjà**). Distinct de leftover N158 (`floatingText` Destroy). Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**. Role `"flame"` **inchangé**. Shape `Ball` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. Trail **déjà** N151 — ne pas y revenir. HUD **déjà** N153 — ne pas y revenir. Preview **déjà** N154 — ne pas y revenir. Select **déjà** N155 — ne pas y revenir. Flash **déjà** N156 — ne pas y revenir. Pulse **déjà** N157 — ne pas y revenir. Visual V74 freeze **interdit** (feel ≠ visual). **Passes 61–66 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse `1.8 + math.sin(time * 18) * 0.45`. **Ne pas** geler Size (visual V74 Option A, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)`. XY `0.62` / base `1.8` / freq `18` / amp `0.45` **inchangés**.

2. **Garder le pulse.** Ne **pas** poser Size = API. Ne **pas** « fermer » trail (N151 déjà). Ne **pas** « fermer » HUD (N153 déjà). Ne **pas** « fermer » previewTile (N154 déjà). Ne **pas** « fermer » selectTile (N155 déjà). Ne **pas** « fermer » tileFlash (N156 déjà). Ne **pas** « fermer » conquestPulse (N157 déjà). Ne **pas** lire `piece.part.Size` (alloc). Ne pas porter visual. Après N157. Trail **non**. Radar / flag **non**. Wake **non**. `BuildingModels` **non**. Overlay **non**. HUD **non**. Effects **non**. `createMissile` construction **non** (taille initiale `Vector3.new(0.62, 0.62, 2.3)` inchangée).

3. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N158 seulement.** N152 reste alors ouvert (feel-diverged vs V74). Ne pas inventer un cache Size. Ne pas skip-si-inchangé (N2, pas ici).

4. Tests « navires, missiles et interpolation » leftover N151 trail **et** leftover N148 mesh **et** leftover N147 Fin **doivent rester verts**. Tests « fil de notifications sature » leftover N153 **doivent rester verts**. Tests « calques d'entites, effets et apercu » leftover N155 `selectTile` reuse **doivent rester verts**. Tests « vagues de conquete » leftover N157 `conquestPulse` reuse **et** leftover N156 `tileFlash` reuse **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` flame **seulement**, **un** `elseif`) **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N152 (commentaire leftover, **garder** N151/N148). `BuildingModels.luau` **non**. `Overlay.luau` **non**. `HUD.luau` **non**. `Effects.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher trail ni HUD ni previewTile ni selectTile ni tileFlash ni conquestPulse.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ N151 (trail Z) ≠ visual V74 (freeze Size=API, ne pas merger) ≠ N153 (HUD feed) ≠ N154 (previewTile skip) ≠ N155 (selectTile reuse) ≠ N156 (tileFlash pool) ≠ N157 (conquestPulse pool) ≠ N158 (floatingText pool) ≠ N2 (skip-si-inchangé).** Non réentrant. Ne pas fusionner avec N158 dans le même worker. Pulse Z **conservé** — ne pas figer à 1.8. Un `elseif` flame.

---

### ISSUE-N158 — Effects `floatingText` Instance.new+Destroy chaque chiffre (feel)

**Priorité :** P3 alloc client Effects. Leftover explicite après N157 (`conquestPulse` free-list déjà). Distinct de N152 (UnitModels Size), de N153 (HUD feed), de N154 (previewTile skip), de N155 (`selectTile` reuse), de N156 (`tileFlash` pool), de N157 (`conquestPulse` pool), de visual V82 (`pulseRot` cuit / Name `ConquestPulse` — **ne pas merger** `490f`). `Effects.floatingText` **seulement**. Ne pas toucher `conquestPulse`. Ne pas toucher `tileFlash`. Ne pas toucher `selectTile`. Ne pas toucher `previewTile`. Ne pas toucher HUD. Ne pas toucher UnitModels.

**Problème :** N157 ferme le pool anneaux. N152 reste ouvert (freeze interdit). Reste, **chaque chiffre** (`Effects.floatingText`, `conquestWave` si `mine` et `count >= 4` **et** `lossWave` si `count >= 4`) :

```
local anchor = Instance.new("Part")
...
local billboard = Instance.new("BillboardGui")
...
local label = Instance.new("TextLabel")
...
local outline = Instance.new("UIStroke")
...
TweenService:Create(anchor, TweenInfo.new(1.2, ... Out), { CFrame Y=26 }):Play()
TweenService:Create(label, TweenInfo.new(1.2), { TextTransparency=1 }):Play()
TweenService:Create(outline, TweenInfo.new(1.2), { Transparency=1 }):Play()
task.delay(1.3, function()
    anchor:Destroy()
end)
```

Instance.new × 4 + Destroy à 1.3 s par chiffre. `conquestPulse` **réutilise déjà** (`pulseFree`, N157). `tileFlash` **réutilise déjà** (`flashFree`, N156). `selectTile` **réutilise déjà** (N155). `previewTile` **réutilise déjà** (N96 + N154 skip). `floatingText` non. Distinct de leftover N152 (`Size = Vector3.new` flamme). Distinct de leftover N157 (`conquestPulse` pool **déjà**). Distinct de leftover N134 (euler anneau déjà — **ne pas** re-patcher `fromEulerAnglesYXZ`). Distinct de visual V82 (`pulseRot` cuit — **ne pas merger** `490f`, ce n’est pas un texte). Départ `Y = 12` **inchangé**. Arrivée tween `Y = 26` **inchangée**. Anchor Size `0.1, 0.1, 0.1` **inchangé**. Transparency anchor `1` **inchangée**. Billboard `UDim2.fromOffset(120, 30)` / `AlwaysOnTop` / `MaxDistance = 900` **inchangés**. Label `TextSize = 20` / `Theme.font.display` / `BackgroundTransparency = 1` **inchangés**. Outline `Color3.fromRGB(6, 8, 14)` / `Thickness = 2.5` **inchangés**. Tween 1.2 Quad Out **inchangé**. `task.delay` 1.3 s **inchangé**. Caps `MAX_FLASHES_PER_WAVE` / `MAX_LIVE_FLASHES` **inchangés** (pas un live count de textes). `conquestWave` / `lossWave` barycentre **inchangés**. Seuil `count >= 4` **inchangé**.

**Pourquoi 20K CCU :** leftover N157. 8 clients × vague (conquête mine ≥ 4 **et** perte ≥ 4) × 4 `Instance.new` + Tween × 3 + Destroy 1.3 s. Pas d’autorité (cosmétique Effects). Pulse **déjà** N157 — ne pas y revenir. Flash **déjà** N156 — ne pas y revenir. Select **déjà** N155 — ne pas y revenir. Preview **déjà** N154 — ne pas y revenir. Flame leftover N152 **alors** (ne pas freeze). Visual V82 `pulseRot` **interdit** (feel ≠ visual, et ce n’est pas un Billboard).

**Worker :**

1. Dans `Effects.floatingText` seulement : free-list d’ancres (`textFree` tableau, pop O(1)). Si une ancre libre : **réutiliser** l’arbre entier (Part + BillboardGui + TextLabel + UIStroke déjà enfants — **ne pas** recréer les 3 descendants). Writes : `CFrame` départ `Y = 12`, `label.Text`, `label.TextColor3`, **`label.TextTransparency = 0`** (le tween l’avait mise à 1), **`outline.Transparency = 0`**, `Parent = self.root`. **Ne pas** Destroy à 1.3 s : `Parent = nil` + push free-list. Sinon : création inchangée (pas de Name, Part Transparency 1, Size `0.1³`, Billboard 120×30, label display 20, outline 2.5). Tween Create **conservé** à chaque appel (CFrame Y=26 + TextTransparency + outline Transparency restart). Pas de `self.live` (c’est `tileFlash`). Caps flash **inchangés**. Descendre l’arbre via `GetChildren` / `FindFirstChildWhichIsA` — **ne pas** wrapper `{anchor, label, outline}` dans un record (la free-list est un tableau de Parts, recette `pulseFree` N157).

2. **Garder l’arbre.** Ne **pas** recréer Billboard/Label/Stroke au reuse. Ne **pas** porter visual V82. Ne **pas** poser Name. Ne **pas** changer Y=12 / Y=26. Ne **pas** toucher `conquestPulse` / N157. Ne **pas** toucher `tileFlash` / N156. Ne **pas** toucher `selectTile` / N155. Ne **pas** toucher `previewTile` / skip N154. Ne **pas** geler Size (pas N152). Après N157. Flame **non** (N152). HUD **non**. `UnitModels` **non**. Overlay **non**. PlacementPreview **non**. `lossWave` / `conquestWave` **non** (ils appellent déjà `floatingText`).

3. Tests « vagues de conquete » leftover N157 `conquestPulse` reuse **et** leftover N156 `tileFlash` reuse **et** leftover N134 euler **doivent rester verts** (caps flash, `rawequal` plaque **et** anneau, pas d’erreur). Tests « calques d'entites, effets et apercu » leftover N155 `selectTile` reuse **doivent rester verts**. Check « apercu de placement » leftover N129 **doit rester vert**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client `vagues de conquete` **doit rester vert**. Après flush des delays de texte, `textFree` non vide ; `lossWave` (count ≥ 4) réparente la même ancre (`rawequal`). **Réécrire** `label.TextTransparency = 0` sinon le reuse est invisible. Check calques leftover N155. Check fil leftover N153. Check navires leftover N151 `offset.Z` / leftover N152 flame. Check pulse leftover N157 `pulseFree`. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `Effects.luau` (`floatingText` **seulement**). `tests/client.luau` **seulement si** le check vagues ne mentionne pas encore N158 (commentaire leftover, **garder** N157 / N156 / N134). `HUD.luau` **non**. `UnitModels.luau` **non**. `PlacementPreview.luau` **non**. `Overlay.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher flame ni HUD ni `previewTile` ni `selectTile` ni `tileFlash` ni `conquestPulse`.

**Contraintes :** pas de RemoteFunction. **N158 feel ≠ N157 (conquestPulse pool) ≠ N156 (tileFlash pool) ≠ N155 (selectTile reuse) ≠ N154 (previewTile skip) ≠ N152 (flame Size, ne pas freeze V74) ≠ N153 (HUD feed) ≠ N134 (conquestPulse euler déjà) ≠ visual V82 (ConquestPulse pulseRot, ne pas merger `490f`) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N152 dans le même worker. Free-list — ne pas skip Text si le chiffre change. Un `floatingText` — ne pas splitter `conquestPulse`. `task.delay` 1.3 s **conservé**. Ne pas `table.remove` la free-list (pop O(1) depuis la fin). Ancre `Parent = nil` **pas** Destroy (sauf si le module est détruit — hors scope). Distinct `pulseFree` / `flashFree` — **ne pas** partager les free-lists de N157/N156. **Reset Transparency label/outline** au reuse — oubli = texte fantôme.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; trail → **N151 fait** ; HUD feed → **N153 fait** ; previewTile → **N154 fait** ; selectTile → **N155 fait** ; tileFlash → **N156 fait** ; conquestPulse → **N157 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; HUD feed → **N153 fait** ; previewTile skip → **N154 fait** ; selectTile reuse → **N155** ; tileFlash pool → **N156** ; conquestPulse pool → **N157** ; Effects `floatingText` pool = **N158**) |
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
| N34–N151, N153–N157 | (voir rapport #189) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–66) |
| N158 | Effects `floatingText` Instance.new+Destroy | P3 | **nouveau** (`floatingText` free-list, arbre Billboard **conservé**, **≠** N157 `pulseFree`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 / #169 / #171 / #173 / #176 / #178 / #181 / #183 / #185 / #187 / #189 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N157 conquestPulse pool) |

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

Client : **35/35 OK** — dont `fil de notifications sature` leftover N153 ; `calques d'entites, effets et apercu` leftover N155 reuse `selectTile(2000)` puis `selectTile(2001)` `rawequal`, leftover N154 `previewTile(2001)` puis `previewTile(2002)` deux indices, `clearSelection` nil ; `hover spawn isolation` leftover N58 `previewTile(pocket)` puis `clearActionPreview` ; `construction du monde 3D` leftover N137/N138 ; `pose et capture de chaque type de batiment` leftover N136 ; `modeles procéduraux` leftover N150/N149 ; `apercu de placement pour chaque batiment` leftover N129 ; `navires, missiles et interpolation` leftover N151 trail `offset.Z` / leftover N152 flame Size / leftover N148 mesh ; `vagues de conquete` N157 `conquestPulse` reuse (`testFlushDelays` → `#pulseFree >= 1`, `lossWave` `rawequal` Parent root, Name ≠ `ConquestPulse`) / leftover N156 `tileFlash` reuse (`#flashFree == liveBefore`, seconde vague `rawequal`) / leftover N134 euler / leftover N158 `floatingText` Destroy. Serveur **non** touché cette passe. `UnitModels.luau` **non** touché. `WorldCamera.luau` **non** touché. `Overlay.luau` **non** touché. `PlacementPreview.luau` **non** touché. `HUD.luau` **non** touché. `previewTile` skip **inchangé**. `selectTile` reuse **inchangé**. `tileFlash` **inchangé**. `floatingText` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass66.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N157 est un pool anneaux vérifié par le banc headless (`vagues de conquete` flush + reuse `rawequal`). Pulse flamme Size **inchangé** (N152). Pulse trail Transparency **inchangé** (N151). Skip hover **inchangé** (N154). Select reuse **inchangé** (N155). Flash reuse **inchangé** (N156).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N157 n’ajoute **pas** de require (free-list locale Effects `conquestPulse`). N152 restera dans `UnitModels.place` flame. N158 restera dans `Effects.floatingText`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N151 : trail seulement. `piece.offset.Z` **pas** `piece.offset.Position.Z`. Amplitude / `+=` Transparency inchangés. Distinct flame leftover N152 (`Size = Vector3.new`, **≠** visual V74 freeze). Distinct HUD N153 **déjà**. Distinct previewTile N154 **déjà**. Distinct selectTile N155 **déjà**. Distinct tileFlash N156 **déjà**. Distinct conquestPulse N157 **déjà**.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Distinct trail N151. Distinct HUD N153. Distinct previewTile N154. Distinct selectTile N155. Distinct tileFlash N156. Distinct conquestPulse N157. Distinct floatingText N158. Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N153 : plafond `notify` seulement. Décalage préfixe **pas** `table.remove(1)`, **pas** swap-pop. FIFO / MAX=3 inchangés. Distinct Dismiss `table.remove(index)`. Distinct dirtyHead N112. Distinct flame N152. Porter hardening N110, **ne pas merger** `41e2`.

Piège N154 : `previewTile` seulement. Skip **index+valid+color**. Ne pas skip Color si seul `valid` change. Ne pas porter visual V77 PlacementPreview. Distinct `selectTile` N155 **déjà**. Distinct flame N152. Distinct HUD N153. Distinct tileFlash N156 **déjà**. Distinct conquestPulse N157 **déjà**. `clearActionPreview` nil les trois champs. Couleurs Theme / `PLAYER_COLORS` sont des références stables — `==` marche même sans `Color3.__eq` au banc.

Piège N155 : `selectTile` seulement. Reuse Part, pas Destroy+recreate. Tween pulse **conservé**. Size reset `TILE_SIZE * 1.15` avant Tween (restart depuis 0.82). Ne pas porter visual V83 SelectionRing `pulseRot`. Distinct previewTile N154. Distinct flame N152. Distinct HUD N153. Distinct tileFlash N156 **déjà**. Distinct conquestPulse N157 **déjà**. `clearSelection` Destroy inchangé. Name `SelectedTerritory` inchangé.

Piège N156 : `tileFlash` seulement. Free-list `flashFree`, pop O(1) depuis la fin. Tween pulse **conservé**. `Parent = nil` + push, **pas** Destroy. Caps 90/28 inchangés. `self.live` inchangé. Ne pas porter visual V83. Distinct selectTile N155. Distinct previewTile N154. Distinct flame N152. Distinct `conquestPulse` N157 **déjà**. Distinct `floatingText` leftover N158. `task.delay` 0.7 s conservé. Lazy-init `flashFree` dans `tileFlash` (pas `Effects.new`). Ne pas `table.remove` la free-list.

Piège N157 : `conquestPulse` seulement. Free-list `pulseFree` **séparée** de `flashFree`. Tween Size/Transparency **conservé**. `Parent = nil` + push, **pas** Destroy. Euler N134 **inline** (`fromEulerAnglesYXZ`, Y=3) — **ne pas** cuire `pulseRot`. Ne pas porter visual V82. Ne pas poser Name `ConquestPulse`. Distinct tileFlash N156. Distinct flame N152. Distinct `floatingText` leftover N158. `task.delay` 1 s conservé. Lazy-init `pulseFree` dans `conquestPulse` (pas `Effects.new`).

Piège N158 (à venir) : `floatingText` seulement. Free-list `textFree` **séparée** de `pulseFree` / `flashFree`. Tween CFrame/TextTransparency **conservé**. `Parent = nil` + push, **pas** Destroy. Arbre Billboard **conservé** au reuse — reset `TextTransparency = 0` et `outline.Transparency = 0`. Ne pas porter visual V82. Distinct conquestPulse N157. Distinct flame N152. `task.delay` 1.3 s conservé.
