# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 70)

Déclencheur : ouverture de la **PR #197** (`cursor/analyse-nocturne-du-codebase-d29b`) — Overlay LaunchWake free-list (N160), specs N152 / N161.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-41d3`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#197. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. Camera overview : lerp mire `fx/fy/fz` (N121) ; champs `focusX/Y/Z` (N122) ; shake `sx/sy/sz` (N119) ; offset YXZ `ox/oy/oz` (N120) ; pose `CFrame.new * rotation` (N118). Minimap : `setFocus(x,y,z)` nombres (N123). Radar / Flag / Boom : `fromEulerAnglesYXZ` (N124). Overlay navire : roulis `fromEulerAnglesYXZ` (N125). Overlay camion : roues `fromEulerAnglesYXZ` (N126). `UnitModels.place` radar : `fromEulerAnglesYXZ` (N127). `UnitModels.place` flag : `fromEulerAnglesYXZ` (N128). `PlacementPreview.update` footprint : `fromEulerAnglesYXZ` (N129). Overlay LaunchWake : `fromEulerAnglesYXZ` (N130, inline — **≠** visual V78 `wakeRot` cuit) **et** free-list (N160). Overlay LandingSplash : `fromEulerAnglesYXZ` (N131, inline — **≠** visual V79 `wakeRot`) **et** free-list (N161). Overlay DeliveryPulse : `fromEulerAnglesYXZ` (N132, inline — **≠** visual V80 `wakeRot` cuit). Overlay Shockwave : `fromEulerAnglesYXZ` (N133). Effects `conquestPulse` ring : `fromEulerAnglesYXZ` (N134). WorldRenderer OceanGlint : `fromEulerAnglesYXZ` (N135). BuildingModels `BuildRing` : `fromEulerAnglesYXZ` (N136). WorldRenderer TreeTrunk / SavannaTrunk : `fromEulerAnglesYXZ` (N137). WorldRenderer Rock : `fromEulerAnglesYXZ` (N138). BuildingModels `cylinder()` : `fromEulerAnglesYXZ` (N139). BuildingModels toits usine : `fromEulerAnglesYXZ` (N140). BuildingModels portes silo : `fromEulerAnglesYXZ` (N141). BuildingModels rampes SAM : `fromEulerAnglesYXZ` (N142). UnitModels houle `addWake` : `fromEulerAnglesYXZ` (N143). UnitModels proue `Bow` : `fromEulerAnglesYXZ` (N144). UnitModels rampe `LandingRamp` : `fromEulerAnglesYXZ` (N145). UnitModels corps missile `MissileBody` : `fromEulerAnglesYXZ` (N146). UnitModels ailettes `Fin` : `fromEulerAnglesYXZ` (N147). UnitModels `buildCarrier` mesh : `visual.pieces` (N148). BuildingModels `CityWindows` : `rest.X` (N149). BuildingModels beacons : `rest.Z` (N150). UnitModels `place` trail : `offset.Z` (N151). HUD `feedEntries` plafond : décalage préfixe (N153). Effects `previewTile` : skip index+valid+color (N154). Effects `selectTile` : reuse Part (N155). Effects `tileFlash` : free-list (N156). Effects `conquestPulse` : free-list (N157). Effects `floatingText` : free-list (N158). Overlay `goldPopup` : free-list (N159). Overlay LaunchWake : free-list (N160). Overlay LandingSplash : free-list (N161). Plus aucun `CFrame.Angles` vivant côté client (hors stubs de banc). Plus aucun `child.Position` / `offset.Position` 60 Hz. Plus aucun `table.remove(1)` client (Dismiss garde `table.remove(index)`). UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover N152, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). Overlay DeliveryPulse Instance.new+Destroy à la fin de trajet (leftover N162, euler N132 **inline**, Name `DeliveryPulse` **conservé**, **≠** N161 `splashFree` / visual V80 `wakeRot`).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #197 (passe 69) : claims vérifiés.** Overlay LaunchWake free-list (N160, `wakeFree` pop O(1), `Parent = nil` + push si encore parenté, pas Destroy, Name `LaunchWake` conservé, euler N130 inline). **N152 non livré** (freeze Size=API = visual V74, interdit). Spec N161 **corrigée ici**. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #198** (`ae72`) a **fermé V97** mesh carrier — feel N148 **déjà**, **pas merger** `ae72`. Visual V98 CityWindows **ouvert** — feel N149 **déjà**, **pas merger**. Visual **PR #196** (`f89f`) V96 Fin **fermé** — feel N147 **déjà**. Visual **PR #194** (`60f2`) V95 MissileBody **fermé** — feel N146 **déjà**.

Cette passe a **livré N161** (ce que #197 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #197

| Claim #197 | Réalité à l’ouverture |
|---|---|
| Overlay LaunchWake free-list (N160) | Oui. `wakeFree` pop O(1). `Parent = nil` + push si encore parenté, pas Destroy. Name `LaunchWake`. Reset Size `(0.16, 2.5, 2.5)` + Transparency `0.34`. Euler N130 inline. |
| N152 non livré | Oui. `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)` inchangé. Pulse Z conservé. Freeze Size=API = visual V74, interdit. |
| Specs N152 / N161 | **N161 corrigé ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #197, visuelles #39/…/`ae72` V97 **fermé** / leftover V98. **#197 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `ae72` / `f89f` / `60f2` / `aae2` / `29b4` / `d645` / `930a` / `6095` / `9fd4` / `f9ec` / `2b04` / `75ce` / `7be5` / `0b3d` / `490f` / `47c0` / `a597` / `54d6` / `6183` / `185a` / `70a5` / `c0ec` / `1b5c` ni hardening `41e2` / `93f6` / `e291` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N161 est cosmétique client (anneau débarquement Overlay). Risques documentés, non corrigés ici (hors N161) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N161. `CARRIER_MESH_ID` reste `""` — le chemin mesh n’est pas exercé par le banc (N148 est un crash latent, pas un vert runtime). BuildingModels `animate` n’a plus de `child.Position` 60 Hz. UnitModels n’a plus de `offset.Position` 60 Hz. UnitModels n’a plus de `CFrame.Angles` vivant. `HUD.feedEntries` plafond **sans** `table.remove(1)` (N153). Effects `previewTile` **sans** rewrite CFrame/Color si hover inchangé (N154). Effects `selectTile` **sans** Destroy+recreate (N155). Effects `tileFlash` **sans** Destroy à 0.7 s (N156). Effects `conquestPulse` **sans** Destroy à 1 s (N157). Effects `floatingText` **sans** Destroy à 1.3 s (N158). Overlay `goldPopup` **sans** Destroy à 1.5 s (N159). Overlay LaunchWake **sans** Destroy à 0.8 s (N160). Overlay LandingSplash **sans** Destroy à 0.95 s (N161). Serveur feel : `table.remove` bateaux/missiles encore (hardening N105–N106, ne pas porter). UnitModels `place` flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze Size=API). Overlay DeliveryPulse Instance.new+Destroy (leftover N162).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N161 du rapport #197. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Overlay LandingSplash Instance.new+Destroy chaque despawn navire (N161) | `Overlay.luau` (`applyUnits` despawn navire **seulement**, LaunchWake / `goldPopup` / DeliveryPulse / Shockwave / `routePart` / Destroy modèle navire inchangés), `tests/client.luau` (commentaire leftover navires + assert reuse dans vagues) | Leftover N160. Free-list `splashFree`, pop O(1). `Parent = nil` + push si encore parenté, pas Destroy. Name `LandingSplash` conservé. Reset Size `(0.18, 3, 3)` + Transparency `0.18` au reuse. Euler N131 **inline**. Tween 0.9 Quart Out conservé. Skip retraite N56 **conservé**. Cosmétique. Flame leftover N152 **alors**. HUD N153 **inchangé**. Effects **inchangé**. goldPopup N159 **inchangé**. LaunchWake N160 **inchangé**. DeliveryPulse leftover N162 **alors**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), Overlay DeliveryPulse Instance.new+Destroy (**N162**), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, PlacementPreview Size rayon (visual V76, feel Size = API), PlacementPreview early-out hover (visual V77, **pas merger**), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline** **et** N160 free-list, **pas merger** `6183`), Overlay LandingSplash `wakeRot` (visual V79, feel N131 **inline** **et** N161 free-list, **pas merger** `54d6`), Overlay DeliveryPulse `wakeRot` (visual V80, feel N132 **inline**, **pas merger**), Overlay Shockwave `wakeRot` (visual V81, feel N133 **inline**, **pas merger**), Effects `conquestPulse` `pulseRot` (visual V82, feel N134 **inline** Y=3 **et** N157 free-list, **pas merger** `490f`), Effects SelectionRing `pulseRot` (visual V83, feel N155 **reuse Part** Name `SelectedTerritory`, **pas merger** `0b3d`), tribus `humanTargetProtected`. Effects / UnitModels / WorldCamera / WorldRenderer / BuildingModels / HUD / serveur **non édités**. Flame **non**. `previewTile` **non**. `selectTile` **non**. `tileFlash` **non**. `conquestPulse` **non**. `floatingText` **non**. `goldPopup` **non**. LaunchWake **non**. Dismiss `table.remove(index)` **non**. DeliveryPulse **non**. `routePart` **non**. `clearSelection` Destroy **inchangé**. `lossWave` barycentre **inchangé**. `onTradeEvent` **inchangé**. Destroy du modèle navire **inchangé**.

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
- Overlay interpolation X/Z + yaw euler (**N117**) **et** camion `segRot` (**N115**) **et** roulis navire (**N125**) **et** roues camion (**N126**). Camera : lerp nombres (**N121**) + champ `focusX/Y/Z` (**N122**) + shake (**N119**) + offset (**N120**) + pose (**N118**). Minimap `setFocus(x,y,z)` (**N123**). Radar/Flag/Boom euler (**N124**). `UnitModels.place` radar euler (**N127**) **et** flag euler (**N128**). `PlacementPreview.update` footprint euler (**N129**). Overlay LaunchWake euler (**N130**) **et** free-list (**N160**). Overlay LandingSplash euler (**N131**) **et** free-list (**N161**). Overlay DeliveryPulse euler (**N132**). Overlay Shockwave euler (**N133**). Effects `conquestPulse` ring euler (**N134**) **et** free-list (**N157**). WorldRenderer OceanGlint euler (**N135**). BuildingModels `BuildRing` euler (**N136**). WorldRenderer trunks euler (**N137**). WorldRenderer Rock euler (**N138**). BuildingModels `cylinder()` euler (**N139**). BuildingModels toits usine euler (**N140**). BuildingModels portes silo euler (**N141**). BuildingModels rampes SAM euler (**N142**). UnitModels houle `addWake` euler (**N143**). UnitModels proue `Bow` euler (**N144**). UnitModels rampe `LandingRamp` euler (**N145**). UnitModels corps missile `MissileBody` euler (**N146**). UnitModels ailettes `Fin` euler (**N147**). UnitModels mesh carrier `visual.pieces` (**N148**). BuildingModels `CityWindows` `rest.X` (**N149**). BuildingModels beacons `rest.Z` (**N150**). UnitModels trail `offset.Z` (**N151**). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). HUD `feedEntries` décalage préfixe (**N153**). Effects `previewTile` skip index+valid+color (**N154**). Effects `selectTile` reuse Part (**N155**). Effects `tileFlash` free-list (**N156**). Effects `conquestPulse` free-list (**N157**). Effects `floatingText` free-list (**N158**). Overlay `goldPopup` free-list (**N159**). Overlay LaunchWake free-list (**N160**). Overlay LandingSplash free-list (**N161**). Overlay DeliveryPulse Instance.new+Destroy (**N162**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N162)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151, **N153**, **N154**, **N155**, **N156**, **N157**, **N158**, **N159**, **N160**, **N161** = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N162** = nouveau. **V73 / N127 / N128** fermés passe 49. **N129 / N130** fermés passe 50. **N131 / N132** fermés passe 51. **N133 / N134** fermés passe 52. **N135 / N136** fermés passe 53. **N137 / N138** fermés passe 54. **N139 / N140** fermés passe 55. **N141 / N142** fermés passe 56. **N143 / N144** fermés passe 57. **N145 / N146** fermés passe 58. **N147 / N148** fermés passe 59. **N149 / N150** fermés passe 60. **N151** fermé passe 61. **N153** fermé passe 62. **N154** fermé passe 63. **N155** fermé passe 64. **N156** fermé passe 65. **N157** fermé passe 66. **N158** fermé passe 67. **N159** fermé passe 68. **N160** fermé passe 69. **N161** fermé ici (porté, pas mergé). Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer N152**). Leftover feel Overlay DeliveryPulse Instance.new+Destroy = **N162** (euler N132 **inline**, Name `DeliveryPulse` **conservé**, **≠** N161 `splashFree` / visual V80 `wakeRot`, ne pas merger `a597`). Flamme `Size = Vector3.new` visual V74 **fermée** Option A sur `c0ec` (Size = API, ne pas porter). PlacementPreview Size rayon = visual V76 **fermée** sur `70a5` (feel Size = API, ne pas merger). PlacementPreview early-out hover = visual V77 **fermée** sur `185a` (feel **pas merger**). Overlay LaunchWake `wakeRot` = visual V78 **fermée** sur `6183` (feel N130 **inline** **et** N160 free-list, ne pas merger). Overlay LandingSplash `wakeRot` = visual V79 **fermée** sur `54d6` (feel N131 **inline** **et** N161 free-list, ne pas merger). Overlay DeliveryPulse `wakeRot` = visual V80 **fermée** sur `a597` (feel N132 **inline**, ne pas merger). Overlay Shockwave `wakeRot` = visual V81 **fermée** sur `47c0` (feel N133 **inline**, ne pas merger). Effects `conquestPulse` `pulseRot` = visual V82 **fermée** sur `490f` (feel N134 **inline** Y=3 **et** N157 free-list, **≠** visual surface+0.8, ne pas merger). Effects SelectionRing `pulseRot` = visual V83 **fermée** sur `0b3d` (feel N155 **reuse Part** Name `SelectedTerritory`, ne pas merger). Visual V85 BuildRing **fermée** sur `7be5` / PR #174 (feel N136 **déjà**, ne pas merger). Visual V84 OceanGlint **fermée** sur `8015`. Visual V86 TreeTrunk **fermée** sur `75ce` / PR #177 (feel N137 **déjà**, ne pas merger `c299`). Visual V87 Rock **fermée** sur `2b04` / PR #179 (feel N138 **déjà**, ne pas merger `c299`). Visual V88 `cylinder()` **fermée** sur `f9ec` / PR #180 (feel N139 **déjà**, ne pas merger `a8e1`). Visual V89 toits usine **fermée** sur `9fd4` / PR #182 (feel N140 **déjà**, ne pas merger `a8e1`). Visual V90 portes silo **fermée** sur `6095` / PR #184 (feel N141 **déjà**, ne pas merger `4885`). Visual V91 rampes SAM **fermée** sur `930a` / PR #186 (feel N142 **déjà**, ne pas merger `4885`). Visual V92 `addWake` **fermée** sur `d645` / PR #188 (feel N143 **déjà**, ne pas merger `c62f`). Visual V93 `Bow` **fermée** sur `29b4` / PR #190 (feel N144 **déjà**, ne pas merger `c62f`). Visual V94 `LandingRamp` **fermée** sur `aae2` / PR #192 (feel N145 **déjà**, ne pas merger `95ed`). Visual V95 `MissileBody` **fermée** sur `60f2` / PR #194 (feel N146 **déjà**, ne pas merger `60f2`). Visual V96 `Fin` **fermée** sur `f89f` / PR #196 (feel N147 **déjà**, ne pas merger `f89f`). Visual V97 mesh carrier **fermée** sur `ae72` / PR #198 (feel N148 **déjà**, ne pas merger `ae72`). Visual V98 CityWindows **ouvert** (feel N149 **déjà**, ne pas merger).

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà), N153 (HUD plafond **déjà**), N154 (`previewTile` skip **déjà**), N155 (`selectTile` reuse **déjà**), N156 (`tileFlash` free-list **déjà**), N157 (`conquestPulse` pool **déjà**), N158 (`floatingText` pool **déjà**), N159 (`goldPopup` pool **déjà**), N160 (LaunchWake pool **déjà**) et N161 (LandingSplash pool **déjà**). Distinct de N151 (trail Transparency), de N153 (HUD feed), de N154 (previewTile skip), de N155 (`selectTile` reuse), de N156 (`tileFlash` pool), de N157 (`conquestPulse` pool), de N158 (`floatingText` pool), de N159 (`goldPopup` pool), de N160 (LaunchWake pool), de N161 (LandingSplash pool), de N162 (DeliveryPulse pool), de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**. Ne pas toucher trail. Ne pas toucher `BuildingModels`. Ne pas toucher Overlay. Ne pas toucher HUD. Ne pas toucher Effects.

**Problème :** N151 ferme le trail. N153 ferme le plafond HUD. N154 ferme le skip hover. N155 ferme le reuse sélection. N156 ferme le pool éclats. N157 ferme le pool anneaux. N158 ferme le pool chiffres. N159 ferme le pool popups or. N160 ferme le pool LaunchWake. N161 ferme le pool LandingSplash. Reste, **chaque frame** (`UnitModels.place`, 60 Hz, une Part `EngineFlame` par ogive) :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (plus de pulse Size, `c0ec` / PR #151). Feel **garde** le pulse Z. Ne pas porter `c0ec`. Distinct de leftover N151 (`offset.Z` trail **déjà**). Distinct de leftover N153 (HUD plafond **déjà**). Distinct de leftover N154 (`previewTile` skip **déjà**). Distinct de leftover N155 (`selectTile` reuse **déjà**). Distinct de leftover N156 (`tileFlash` pool **déjà**). Distinct de leftover N157 (`conquestPulse` pool **déjà**). Distinct de leftover N158 (`floatingText` pool **déjà**). Distinct de leftover N159 (`goldPopup` pool **déjà**). Distinct de leftover N160 (LaunchWake pool **déjà**). Distinct de leftover N161 (LandingSplash pool **déjà**). Distinct de leftover N162 (DeliveryPulse Destroy). Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**. Role `"flame"` **inchangé**. Shape `Ball` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. Trail **déjà** N151 — ne pas y revenir. HUD **déjà** N153 — ne pas y revenir. Preview **déjà** N154 — ne pas y revenir. Select **déjà** N155 — ne pas y revenir. Flash **déjà** N156 — ne pas y revenir. Pulse **déjà** N157 — ne pas y revenir. Texte **déjà** N158 — ne pas y revenir. Popup or **déjà** N159 — ne pas y revenir. LaunchWake **déjà** N160 — ne pas y revenir. LandingSplash **déjà** N161 — ne pas y revenir. Visual V74 freeze **interdit** (feel ≠ visual). **Passes 61–70 ont refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse `1.8 + math.sin(time * 18) * 0.45`. **Ne pas** geler Size (visual V74 Option A, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)`. XY `0.62` / base `1.8` / freq `18` / amp `0.45` **inchangés**.

2. **Garder le pulse.** Ne **pas** poser Size = API. Ne **pas** « fermer » trail (N151 déjà). Ne **pas** « fermer » HUD (N153 déjà). Ne **pas** « fermer » previewTile (N154 déjà). Ne **pas** « fermer » selectTile (N155 déjà). Ne **pas** « fermer » tileFlash (N156 déjà). Ne **pas** « fermer » conquestPulse (N157 déjà). Ne **pas** « fermer » floatingText (N158 déjà). Ne **pas** « fermer » goldPopup (N159 déjà). Ne **pas** « fermer » LaunchWake (N160 déjà). Ne **pas** « fermer » LandingSplash (N161 déjà). Ne **pas** lire `piece.part.Size` (alloc). Ne pas porter visual. Après N161. Trail **non**. Radar / flag **non**. Wake **non**. `BuildingModels` **non**. Overlay **non**. HUD **non**. Effects **non**. `createMissile` construction **non** (taille initiale `Vector3.new(0.62, 0.62, 2.3)` inchangée).

3. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N162 seulement.** N152 reste alors ouvert (feel-diverged vs V74). Ne pas inventer un cache Size. Ne pas skip-si-inchangé (N2, pas ici).

4. Tests « navires, missiles et interpolation » leftover N151 trail **et** leftover N148 mesh **et** leftover N147 Fin **doivent rester verts**. Tests « fil de notifications sature » leftover N153 **doivent rester verts**. Tests « calques d'entites, effets et apercu » leftover N155 `selectTile` reuse **doivent rester verts**. Tests « vagues de conquete » leftover N161 `LandingSplash` reuse **et** leftover N160 `LaunchWake` reuse **et** leftover N159 `goldPopup` reuse **et** leftover N158 `floatingText` reuse **et** leftover N157 `conquestPulse` reuse **et** leftover N156 `tileFlash` reuse **doivent rester verts**. Tests « livraison : le gain s'affiche sur la gare » leftover N159 **doivent rester verts**. Tests « pose et capture de chaque type de batiment » leftover N132 `DeliveryPulse` **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` flame **seulement**, **un** `elseif`) **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N152 (commentaire leftover, **garder** N151/N148). `BuildingModels.luau` **non**. `Overlay.luau` **non**. `HUD.luau` **non**. `Effects.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher trail ni HUD ni previewTile ni selectTile ni tileFlash ni conquestPulse ni floatingText ni goldPopup ni LaunchWake ni LandingSplash.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ N151 (trail Z) ≠ visual V74 (freeze Size=API, ne pas merger) ≠ N153 (HUD feed) ≠ N154 (previewTile skip) ≠ N155 (selectTile reuse) ≠ N156 (tileFlash pool) ≠ N157 (conquestPulse pool) ≠ N158 (floatingText pool) ≠ N159 (goldPopup pool) ≠ N160 (LaunchWake pool) ≠ N161 (LandingSplash pool) ≠ N162 (DeliveryPulse pool) ≠ N2 (skip-si-inchangé).** Non réentrant. Ne pas fusionner avec N162 dans le même worker. Pulse Z **conservé** — ne pas figer à 1.8. Un `elseif` flame.

---

### ISSUE-N162 — Overlay DeliveryPulse Instance.new+Destroy chaque fin de trajet (feel)

**Priorité :** P3 alloc client Overlay. Leftover explicite après N161 (LandingSplash free-list déjà). Distinct de N152 (UnitModels Size), de N153 (HUD feed), de N154 (previewTile skip), de N155 (`selectTile` reuse), de N156 (`tileFlash` pool), de N157 (`conquestPulse` pool), de N158 (`floatingText` pool), de N159 (`goldPopup` pool), de N160 (LaunchWake pool), de N161 (LandingSplash pool), de N132 (DeliveryPulse euler **déjà** inline), de visual V80 (`wakeRot` cuit — **ne pas merger** `a597`). `stepInterpolation` fin de `delivery` (`progress >= 1`) **seulement**. Ne pas toucher LandingSplash. Ne pas toucher LaunchWake. Ne pas toucher `goldPopup`. Ne pas toucher Shockwave. Ne pas toucher `routePart` (partagé Pulse/Shockwave/Smoke). Ne pas toucher HUD. Ne pas toucher UnitModels. Ne pas toucher Effects. Ne pas toucher `truckModel.Parent = nil`. Ne pas toucher `applyUnits`.

**Problème :** N161 ferme le pool LandingSplash. N152 reste ouvert (freeze interdit). Reste, **chaque fin de livraison terrestre** (`stepInterpolation`, `delivery.progress >= 1`) :

```
local pulse = routePart(self.root, "DeliveryPulse", Vector3.new(0.22, 2.8, 2.8), colorFor(route.slot), Enum.Material.Neon)
pulse.Shape = Enum.PartType.Cylinder
pulse.Transparency = 0.28
pulse.CFrame = CFrame.new(route.to) * CFrame.fromEulerAnglesYXZ(0, 0, math.rad(90))
TweenService:Create(pulse, TweenInfo.new(0.75, ... Out), { Size = Vector3.new(0.22, 11, 11), Transparency = 1 }):Play()
task.delay(0.85, function()
    if pulse.Parent then
        pulse:Destroy()
    end
end)
```

Instance.new (via `routePart`) + Destroy à 0.85 s par arrivée. LandingSplash **réutilise déjà** (`splashFree`, N161). LaunchWake **réutilise déjà** (`wakeFree`, N160). `goldPopup` **réutilise déjà** (`goldFree`, N159). DeliveryPulse non. Distinct de leftover N152 (`Size = Vector3.new` flamme). Distinct de leftover N161 (`splashFree` **déjà** — **ne pas** partager). Distinct de leftover N132 (euler anneau **déjà** inline). Distinct de leftover N133 (Shockwave Destroy — leftover suivant, **ne pas** fusionner). Distinct de visual V80 (`wakeRot` cuit — **ne pas merger** `a597`). Distinct de Effects `pulseFree` (N157, Name ≠ `ConquestPulse` — **ne pas** partager, nommer `deliveryFree`). Name `DeliveryPulse` **inchangé**. Shape Cylinder **inchangé**. Size départ `Vector3.new(0.22, 2.8, 2.8)` **inchangé**. Color `colorFor(route.slot)` **inchangé** (**réécrire** au reuse — le slot change). Material Neon **inchangé**. Transparency départ `0.28` **inchangée**. `CFrame.new(route.to)` **inchangé** (`route.to` déjà Vector3 gare). Euler `fromEulerAnglesYXZ(0, 0, math.rad(90))` **inchangé** (N132 inline). Tween 0.75 Quad Out Size `(0.22, 11, 11)` / Transparency 1 **inchangé**. `task.delay` 0.85 s **inchangé**. Garde `if pulse.Parent` **inchangée** (devient `Parent = nil` + push). `truckModel.Parent = nil` **inchangé**. `route.delivery = nil` **inchangé**. `routePart` **non modifié**.

**Pourquoi 20K CCU :** leftover N161. 8 clients × arrivées de colis × `Instance.new` + Tween + Destroy 0.85 s. Pas d’autorité (cosmétique Overlay). LandingSplash **déjà** N161 — ne pas y revenir. LaunchWake **déjà** N160 — ne pas y revenir. Popup or **déjà** N159 — ne pas y revenir. Pulse Effects **déjà** N157 — ne pas y revenir. Flame leftover N152 **alors** (ne pas freeze). Visual V80 `wakeRot` **interdit** (feel ≠ visual, euler déjà N132 inline). Camion retiré **doit** continuer (`Parent = nil`).

**Worker :**

1. Dans `stepInterpolation` fin de `delivery` (`progress >= 1`) seulement : free-list d’ancres (`deliveryFree` tableau, pop O(1)). **Pas** `pulseFree` (c’est Effects N157). Si une Part libre : **réutiliser** (pas `routePart`). Writes : `Size = Vector3.new(0.22, 2.8, 2.8)` (le tween l’avait mise à `(0.22, 11, 11)`), `Transparency = 0.28`, **`Color = colorFor(route.slot)`** (le slot change — oubli = pulse de la mauvaise faction), `CFrame` euler N132 inline (`route.to`), `Parent = self.root`. Name `DeliveryPulse` **conservé**. **Ne pas** Destroy à 0.85 s : `Parent = nil` + push free-list (`if pulse.Parent` devient push seulement si encore parenté — un second delay fantôme ne double-push pas). Sinon : création inchangée via `routePart` (Name `DeliveryPulse`, Size `0.22, 2.8, 2.8`, Cylinder, Neon, `colorFor(route.slot)`). Tween Create **conservé** à chaque appel (Size + Transparency restart). Pas de `self.live` (c’est Effects `tileFlash`). **Ne pas** wrapper un record. **Ne pas** partager `splashFree` / `wakeFree` / `goldFree` / `textFree` / `pulseFree` / `flashFree`. **Ne pas** modifier `routePart`. **Ne pas** changer `truckModel.Parent = nil`. **Ne pas** toucher `applyUnits`.

2. **Garder l’arrivée.** Ne **pas** recréer au reuse. Ne **pas** porter visual V80 (`wakeRot` cuit). Ne **pas** retirer Name `DeliveryPulse`. Ne **pas** changer `route.to`. Ne **pas** cuire `wakeRot`. Ne **pas** toucher LandingSplash / N161. Ne **pas** toucher LaunchWake / N160. Ne **pas** toucher `goldPopup` / N159. Ne **pas** toucher Shockwave / N133. Ne **pas** geler Size (pas N152). Après N161. Flame **non** (N152). HUD **non**. `UnitModels` **non**. Effects **non**. `trackUnit` insert **non**. `applyUnits` despawn **non**. PlacementPreview **non**. `applyRouteProgress` **non**. Camion `Parent = nil` **obligatoire**.

3. Tests « pose et capture de chaque type de batiment » leftover N132 euler **et** leftover N136 BuildRing **doivent rester verts** (`DeliveryPulse` trouvé **sans** flush, Name conservé). Tests « livraison : le gain s'affiche sur la gare » leftover N159 **doivent rester verts**. Tests « navires, missiles et interpolation » leftover N161 splash **sans** flush **et** leftover N160 wake **sans** flush **doivent rester verts**. Tests « vagues de conquete » leftover N161 `LandingSplash` reuse **et** leftover N160 `LaunchWake` reuse **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client `pose et capture` **doit rester vert** (`pulseFound`, Name `DeliveryPulse`, **pas** de `testFlushDelays`). Après flush des delays **dans le check vagues** (déjà un `testFlushDelays` — le DeliveryPulse du check pose y tombe), `deliveryFree` non vide ; snapshot `pooledDelivery` ; **reconstruire** une voie (le check pose détruit les routes : `next(overlay.routes) == nil` en fin de check). Recette : `applyBuildingDelta` FACTORY + CITY avec `links`, `onTradeEvent("dispatch", factoryIndex, cityIndex, slot, gold)`, `stepInterpolation` jusqu’à `delivery == nil` (comme le check pose : ~12 × 0.02 s). Réparente la même Part (`rawequal`, Name `DeliveryPulse`). **Réécrire** Size `(0.22, 2.8, 2.8)`, Transparency `0.28` **et Color `colorFor(slot)`** au reuse sinon l’anneau est invisible (tween l’avait mis à 1), trop grand, ou de la mauvaise faction. Ne **pas** flush dans le check « pose et capture ». Attention : le check vagues despawn déjà id=99 pour N161 — **ne pas** y toucher. Pour N162 : après l’assert N161, snapshot `deliveryFree` (déjà flushé au premier `testFlushDelays`, **avant** N160/N161). Si `deliveryFree` est encore nil au snapshot (le pulse n’a pas été créé — le check pose l’exige), le banc pose est cassé. Préférer : après le premier flush, `deliveryFree` non vide **avant** le `applyUnits` N160 ; snapshot `pooledDelivery` ; puis **après** les asserts N161, reconstruire voie + dispatch + step → reuse `rawequal`. **Réécrire** Size/Transparency/Color. Check vagues leftover N161. Check pose leftover N132. Check fil leftover N153. Check navires leftover N151 `offset.Z` / leftover N152 flame. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `Overlay.luau` (`stepInterpolation` fin de `delivery` DeliveryPulse **seulement**). `tests/client.luau` **seulement si** le check pose ne mentionne pas encore N162 (commentaire leftover, **garder** N132 euler / N161 splash / N160 wake). `Effects.luau` **non**. `HUD.luau` **non**. `UnitModels.luau` **non**. `PlacementPreview.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher flame ni HUD ni `previewTile` ni `selectTile` ni `tileFlash` ni `conquestPulse` ni `floatingText` ni `goldPopup` ni LaunchWake ni LandingSplash. **Ne pas** toucher Shockwave. **Ne pas** modifier `routePart`. **Ne pas** changer `truckModel.Parent = nil`.

**Contraintes :** pas de RemoteFunction. **N162 feel ≠ N161 (LandingSplash pool) ≠ N160 (LaunchWake pool) ≠ N159 (goldPopup pool) ≠ N158 (floatingText pool) ≠ N157 (conquestPulse pool, `pulseFree` Effects — ne pas réutiliser le nom) ≠ N156 (tileFlash pool) ≠ N155 (selectTile reuse) ≠ N154 (previewTile skip) ≠ N152 (flame Size, ne pas freeze V74) ≠ N153 (HUD feed) ≠ N132 (DeliveryPulse euler déjà) ≠ visual V80 (DeliveryPulse wakeRot, ne pas merger `a597`) ≠ N133 (Shockwave Destroy, leftover suivant) ≠ N2 (skip-si-inchangé replication).** Non réentrant. Ne pas fusionner avec N152 dans le même worker. Free-list — ne pas skip CFrame si `route.to` change. Un `progress >= 1` — ne pas splitter `applyRouteProgress`. `task.delay` 0.85 s **conservé**. Ne pas `table.remove` la free-list (pop O(1) depuis la fin). Ancre `Parent = nil` **pas** Destroy. Distinct `splashFree` / `wakeFree` / `goldFree` / `textFree` / `pulseFree` / `flashFree` — **ne pas** partager les free-lists. **Reset Size + Transparency + Color** au reuse — oubli = anneau fantôme / mauvaise faction. Name `DeliveryPulse` **obligatoire**. Euler N132 **inline** — ne pas cuire `wakeRot`. Ne pas modifier `routePart`. `truckModel.Parent = nil` **obligatoire**. Nommer `deliveryFree` **pas** `pulseFree`.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; trail → **N151 fait** ; HUD feed → **N153 fait** ; previewTile → **N154 fait** ; selectTile → **N155 fait** ; tileFlash → **N156 fait** ; conquestPulse → **N157 fait** ; floatingText → **N158 fait** ; goldPopup → **N159 fait** ; LaunchWake → **N160 fait** ; LandingSplash → **N161 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; HUD feed → **N153 fait** ; previewTile skip → **N154 fait** ; selectTile reuse → **N155** ; tileFlash pool → **N156** ; conquestPulse pool → **N157** ; floatingText pool → **N158** ; goldPopup pool → **N159** ; LaunchWake pool → **N160** ; LandingSplash pool → **N161** ; Overlay DeliveryPulse pool = **N162**) |
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
| N34–N151, N153–N161 | (voir rapport #197) | — | **faits** |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passes 61–70) |
| N162 | Overlay DeliveryPulse Instance.new+Destroy | P3 | **nouveau** (`stepInterpolation` fin de delivery free-list `deliveryFree`, Name `DeliveryPulse` **conservé**, euler N132 **inline**, **≠** N161 `splashFree` / visual V80 `wakeRot`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 / #169 / #171 / #173 / #176 / #178 / #181 / #183 / #185 / #187 / #189 / #191 / #193 / #195 / #197 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N161 LandingSplash pool) |

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

Client : **35/35 OK** — dont `fil de notifications sature` leftover N153 ; `calques d'entites, effets et apercu` leftover N155 reuse `selectTile(2000)` puis `selectTile(2001)` `rawequal`, leftover N154 `previewTile(2001)` puis `previewTile(2002)` deux indices, `clearSelection` nil ; `hover spawn isolation` leftover N58 `previewTile(pocket)` puis `clearActionPreview` ; `construction du monde 3D` leftover N137/N138 ; `pose et capture de chaque type de batiment` leftover N136 / leftover N132 `DeliveryPulse` **sans** flush ; `modeles procéduraux` leftover N150/N149 ; `apercu de placement pour chaque batiment` leftover N129 ; `livraison : le gain s'affiche sur la gare` leftover N159 Name `GoldPopup` / `+1.24K or` **sans** flush ; `navires, missiles et interpolation` leftover N151 trail `offset.Z` / leftover N152 flame Size / leftover N148 mesh / leftover N160 wake **sans** flush / leftover N161 splash **sans** flush, skip retraite id=1 N56 ; `vagues de conquete` N161 `LandingSplash` reuse (`testFlushDelays` → `#splashFree >= 1` **avant** id=99, `applyUnits({}, {})` despawn id=99 `rawequal` Parent root, Name `LandingSplash`) / leftover N160 `LaunchWake` reuse (`#wakeFree >= 1`, `applyUnits` id=99 `rawequal` Parent root, Name `LaunchWake`) / leftover N159 `goldPopup` reuse (`#goldFree >= 1`, `goldPopup` `rawequal` Parent root, Name `GoldPopup`, texte `+500 or`) / leftover N158 `floatingText` reuse (`#textFree >= 1`, `lossWave` `rawequal` Parent root) / leftover N157 `conquestPulse` reuse (`#pulseFree >= 1`, Name ≠ `ConquestPulse`) / leftover N156 `tileFlash` reuse (`#flashFree == liveBefore`, seconde vague `rawequal`) / leftover N134 euler. Serveur **non** touché cette passe. `UnitModels.luau` **non** touché. `WorldCamera.luau` **non** touché. `Effects.luau` **non** touché. `PlacementPreview.luau` **non** touché. `HUD.luau` **non** touché. `previewTile` skip **inchangé**. `selectTile` reuse **inchangé**. `tileFlash` **inchangé**. `conquestPulse` **inchangé**. `floatingText` **inchangé**. `goldPopup` **inchangé**. LaunchWake **inchangé**. Overlay DeliveryPulse **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass70.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N161 est un pool anneaux débarquement vérifié par le banc headless (`navires` sans flush + skip retraite N56 + `vagues de conquete` flush + reuse `rawequal` après despawn id=99). Pulse flamme Size **inchangé** (N152). Pulse trail Transparency **inchangé** (N151). Skip hover **inchangé** (N154). Select reuse **inchangé** (N155). Flash reuse **inchangé** (N156). Pulse reuse **inchangé** (N157). Texte reuse **inchangé** (N158). Popup or reuse **inchangé** (N159). LaunchWake reuse **inchangé** (N160). DeliveryPulse **inchangé** (N162).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N161 n’ajoute **pas** de require (free-list locale Overlay `applyUnits`). N152 restera dans `UnitModels.place` flame. N162 restera dans `stepInterpolation` fin de delivery.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N151 : trail seulement. `piece.offset.Z` **pas** `piece.offset.Position.Z`. Amplitude / `+=` Transparency inchangés. Distinct flame leftover N152 (`Size = Vector3.new`, **≠** visual V74 freeze). Distinct HUD N153 **déjà**. Distinct previewTile N154 **déjà**. Distinct selectTile N155 **déjà**. Distinct tileFlash N156 **déjà**. Distinct conquestPulse N157 **déjà**. Distinct floatingText N158 **déjà**. Distinct goldPopup N159 **déjà**. Distinct LaunchWake N160 **déjà**. Distinct LandingSplash N161 **déjà**.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Distinct trail N151. Distinct HUD N153. Distinct previewTile N154. Distinct selectTile N155. Distinct tileFlash N156. Distinct conquestPulse N157. Distinct floatingText N158. Distinct goldPopup N159. Distinct LaunchWake N160. Distinct LandingSplash N161. Distinct DeliveryPulse leftover N162. Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N153 : plafond `notify` seulement. Décalage préfixe **pas** `table.remove(1)`, **pas** swap-pop. FIFO / MAX=3 inchangés. Distinct Dismiss `table.remove(index)`. Distinct dirtyHead N112. Distinct flame N152. Porter hardening N110, **ne pas merger** `41e2`.

Piège N154 : `previewTile` seulement. Skip **index+valid+color**. Ne pas skip Color si seul `valid` change. Ne pas porter visual V77 PlacementPreview. Distinct `selectTile` N155 **déjà**. Distinct flame N152. Distinct HUD N153. Distinct tileFlash N156 **déjà**. Distinct conquestPulse N157 **déjà**. Distinct floatingText N158 **déjà**. Distinct goldPopup N159 **déjà**. `clearActionPreview` nil les trois champs. Couleurs Theme / `PLAYER_COLORS` sont des références stables — `==` marche même sans `Color3.__eq` au banc.

Piège N155 : `selectTile` seulement. Reuse Part, pas Destroy+recreate. Tween pulse **conservé**. Size reset `TILE_SIZE * 1.15` avant Tween (restart depuis 0.82). Ne pas porter visual V83 SelectionRing `pulseRot`. Distinct previewTile N154. Distinct flame N152. Distinct HUD N153. Distinct tileFlash N156 **déjà**. Distinct conquestPulse N157 **déjà**. Distinct floatingText N158 **déjà**. Distinct goldPopup N159 **déjà**. `clearSelection` Destroy inchangé. Name `SelectedTerritory` inchangé.

Piège N156 : `tileFlash` seulement. Free-list `flashFree`, pop O(1) depuis la fin. Tween pulse **conservé**. `Parent = nil` + push, **pas** Destroy. Caps 90/28 inchangés. `self.live` inchangé. Ne pas porter visual V83. Distinct selectTile N155. Distinct previewTile N154. Distinct flame N152. Distinct `conquestPulse` N157 **déjà**. Distinct `floatingText` N158 **déjà**. Distinct goldPopup N159 **déjà**. `task.delay` 0.7 s conservé. Lazy-init `flashFree` dans `tileFlash` (pas `Effects.new`). Ne pas `table.remove` la free-list.

Piège N157 : `conquestPulse` seulement. Free-list `pulseFree` **séparée** de `flashFree`. Tween Size/Transparency **conservé**. `Parent = nil` + push, **pas** Destroy. Euler N134 **inline** (`fromEulerAnglesYXZ`, Y=3) — **ne pas** cuire `pulseRot`. Ne pas porter visual V82. Ne pas poser Name `ConquestPulse`. Distinct tileFlash N156. Distinct flame N152. Distinct `floatingText` N158 **déjà**. Distinct goldPopup N159 **déjà**. `task.delay` 1 s conservé. Lazy-init `pulseFree` dans `conquestPulse` (pas `Effects.new`).

Piège N158 : `floatingText` seulement. Free-list `textFree` **séparée** de `pulseFree` / `flashFree` / `goldFree`. Tween CFrame/TextTransparency **conservé**. `Parent = nil` + push, **pas** Destroy. Arbre Billboard **conservé** au reuse — reset `TextTransparency = 0` et `outline.Transparency = 0`. Ne pas porter visual V82. Ne pas poser Name. Distinct conquestPulse N157. Distinct flame N152. Distinct `goldPopup` N159 **déjà**. `task.delay` 1.3 s conservé. Lazy-init `textFree` dans `floatingText` (pas `Effects.new`). FindFirstChildWhichIsA BillboardGui → TextLabel → UIStroke. Ne pas partager avec Overlay.

Piège N159 : `goldPopup` seulement. Free-list `goldFree` **séparée** de `textFree` / `pulseFree` / `flashFree` / `wakeFree`. Tween CFrame/TextTransparency **conservé**. `Parent = nil` + push **si encore parenté**, **pas** Destroy. Arbre Billboard **conservé** au reuse — reset `TextTransparency` / `TextStrokeTransparency` ours vs rival. Name `GoldPopup` **conservé** (banc livraison sans flush). Ne pas porter visual V82. Distinct floatingText N158. Distinct flame N152. Distinct LaunchWake N160 **déjà**. `task.delay` 1.5 s conservé. Lazy-init `goldFree` dans `goldPopup` (pas `Overlay.new`). FindFirstChild `"Board"` → TextLabel. Ne pas partager avec Effects.

Piège N160 : `trackUnit` insert navire seulement. Free-list `wakeFree` **séparée** de `goldFree` / `textFree` / `pulseFree` / `flashFree` / `splashFree`. Tween Size/Transparency **conservé**. `Parent = nil` + push, **pas** Destroy. Euler N130 **inline** — **ne pas** cuire `wakeRot`. Name `LaunchWake` **conservé**. Reset Size `(0.16, 2.5, 2.5)` + Transparency `0.34` au reuse. Ne pas porter visual V78. Distinct goldPopup N159. Distinct flame N152. Distinct LandingSplash N161 **déjà**. `task.delay` 0.8 s conservé. Lazy-init `wakeFree` dans `trackUnit` (pas `Overlay.new`). **Ne pas** modifier `routePart`. Garde `not isMissile` **obligatoire**.

Piège N161 : `applyUnits` despawn navire seulement. Free-list `splashFree` **séparée** de `wakeFree` / `goldFree` / `textFree` / `pulseFree` / `flashFree`. Tween Size/Transparency **conservé**. `Parent = nil` + push, **pas** Destroy. Euler N131 **inline** — **ne pas** cuire `wakeRot`. Name `LandingSplash` **conservé**. Reset Size `(0.18, 3, 3)` + Transparency `0.18` au reuse. Ne pas porter visual V79. Distinct LaunchWake N160. Distinct flame N152. Distinct DeliveryPulse leftover N162. `task.delay` 0.95 s conservé. Lazy-init `splashFree` dans le despawn (pas `Overlay.new`). **Ne pas** modifier `routePart`. Gardes `not isMissile` / `not retreating` (N56) **obligatoires**. Ne pas Destroy le modèle navire via la free-list.

Piège N162 (à venir) : `stepInterpolation` fin de `delivery` seulement. Free-list `deliveryFree` **séparée** de `splashFree` / `wakeFree` / `goldFree` / `textFree` / `pulseFree` (Effects N157) / `flashFree`. Tween Size/Transparency **conservé**. `Parent = nil` + push, **pas** Destroy. Euler N132 **inline** — **ne pas** cuire `wakeRot`. Name `DeliveryPulse` **conservé**. Reset Size `(0.22, 2.8, 2.8)` + Transparency `0.28` **+ Color `colorFor(route.slot)`** au reuse. Ne pas porter visual V80. Distinct LandingSplash N161. Distinct flame N152. Distinct Shockwave leftover. `task.delay` 0.85 s conservé. Lazy-init `deliveryFree` dans la fin de delivery (pas `Overlay.new`). **Ne pas** modifier `routePart`. `truckModel.Parent = nil` **obligatoire**. Le check pose détruit les routes — reconstruire FACTORY+CITY pour le reuse dans vagues. **Ne pas** nommer `pulseFree`.
