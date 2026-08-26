# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 61)

Déclencheur : ouverture de la **PR #178** (`cursor/analyse-nocturne-du-codebase-c450`) — BuildingModels `CityWindows` `rest.X` / beacons `rest.Z`, specs N151–N152.

Branche de ce rapport : `cursor/audit-nocturne-du-codebase-80b9`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#179. Pas d’outil Slack.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. Camera overview : lerp mire `fx/fy/fz` (N121) ; champs `focusX/Y/Z` (N122) ; shake `sx/sy/sz` (N119) ; offset YXZ `ox/oy/oz` (N120) ; pose `CFrame.new * rotation` (N118). Minimap : `setFocus(x,y,z)` nombres (N123). Radar / Flag / Boom : `fromEulerAnglesYXZ` (N124). Overlay navire : roulis `fromEulerAnglesYXZ` (N125). Overlay camion : roues `fromEulerAnglesYXZ` (N126). `UnitModels.place` radar : `fromEulerAnglesYXZ` (N127). `UnitModels.place` flag : `fromEulerAnglesYXZ` (N128). `PlacementPreview.update` footprint : `fromEulerAnglesYXZ` (N129). Overlay LaunchWake : `fromEulerAnglesYXZ` (N130, inline — **≠** visual V78 `wakeRot` cuit). Overlay LandingSplash : `fromEulerAnglesYXZ` (N131, inline — **≠** visual V79 `wakeRot`). Overlay DeliveryPulse : `fromEulerAnglesYXZ` (N132, inline — **≠** visual V80 `wakeRot` cuit). Overlay Shockwave : `fromEulerAnglesYXZ` (N133). Effects `conquestPulse` ring : `fromEulerAnglesYXZ` (N134). WorldRenderer OceanGlint : `fromEulerAnglesYXZ` (N135). BuildingModels `BuildRing` : `fromEulerAnglesYXZ` (N136). WorldRenderer TreeTrunk / SavannaTrunk : `fromEulerAnglesYXZ` (N137). WorldRenderer Rock : `fromEulerAnglesYXZ` (N138). BuildingModels `cylinder()` : `fromEulerAnglesYXZ` (N139). BuildingModels toits usine : `fromEulerAnglesYXZ` (N140). BuildingModels portes silo : `fromEulerAnglesYXZ` (N141). BuildingModels rampes SAM : `fromEulerAnglesYXZ` (N142). UnitModels houle `addWake` : `fromEulerAnglesYXZ` (N143). UnitModels proue `Bow` : `fromEulerAnglesYXZ` (N144). UnitModels rampe `LandingRamp` : `fromEulerAnglesYXZ` (N145). UnitModels corps missile `MissileBody` : `fromEulerAnglesYXZ` (N146). UnitModels ailettes `Fin` : `fromEulerAnglesYXZ` (N147). UnitModels `buildCarrier` mesh : `visual.pieces` (N148). BuildingModels `CityWindows` : `rest.X` (N149). BuildingModels beacons : `rest.Z` (N150). UnitModels `place` trail : `offset.Z` (N151). Plus aucun `CFrame.Angles` vivant côté client (hors stubs de banc). Plus aucun `child.Position` / `offset.Position` 60 Hz. UnitModels `place` flamme `Size = Vector3.new` encore 60 Hz (leftover N152, pulse Z **conservé**, **≠** visual V74 freeze — **non livré** : l’API `Size` exige un `Vector3`). `HUD.feedEntries` `table.remove(1)` encore (leftover N153, recette hardening N110, porter ne pas merger `41e2`).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #178 (passe 60) : claims vérifiés.** BuildingModels `CityWindows` `rest.X` (N149, plus de `child.Position.X` 60 Hz) ; BuildingModels beacons `rest.Z` (N150, CityBeacon / PortBeacon / LabBeacon, un `elseif`, plus de `child.Position.Z` 60 Hz). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé. Visual **PR #179** (`2b04`) a **fermé V87** Rock — feel N138 **déjà** inline, **pas merger**. Visual V88 `cylinder()` **fermée** sur `f9ec` — feel N139 **déjà** inline, **pas merger** `a8e1`.

Cette passe a **livré N151** (ce que #178 a documenté). **N152 non livré** : le seul patch distinct de l’API serait un freeze Size=API (visual V74 / `c0ec`) — interdit par la spec.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #178

| Claim #178 | Réalité à l’ouverture |
|---|---|
| BuildingModels `CityWindows` `rest.X` (N149) | Oui. `child.Transparency = 0.06 + (math.sin(time * 0.7 + rest.X * 0.1) + 1) * 0.08`. Plus de `child.Position.X`. Amplitude / fréquence / coeff inchangés. Recette leftover N148, pas merger visual. |
| BuildingModels beacons `rest.Z` (N150) | Oui. `CityBeacon` / `PortBeacon` / `LabBeacon`, un `elseif`. `child.Transparency = 0.05 + (math.sin(time * 2.8 + rest.Z * 0.05) + 1) * 0.18`. Plus de `child.Position.Z`. Recette leftover N149, pas merger visual. |
| Specs N151–N152 | **N151 corrigé ici.** N152 **laissé ouvert** (pulse Z conservé ; freeze Size=API = visual V74, ne pas merger `c0ec`). |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #160/`41e2` (N107–N108), feel jusqu’à #178, visuelles #39/…/`2b04` V87 **fermé**. **#178 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel reste distincte. Ne pas merger visual `2b04` / `75ce` / `7be5` / `0b3d` / `490f` / `47c0` / `a597` / `54d6` / `6183` / `185a` / `70a5` / `c0ec` / `1b5c` ni hardening `41e2` / `93f6` / `e291` sans rebase.

**Revue autorité :** pas de RemoteFunction ; pas de chemin client gold/troupes/owner ; pas de cycle Server/Shared. `JoinRequest` reste hors IntentValidator (chemin menu dédié, ended+cooldown déjà). N151 est cosmétique client. Risques documentés, non corrigés ici (hors N151) : Persistence `math.max` perd les +1 concurrents (N6) ; `RequestSnapshot` buffer owner complet.

**Revue combat/éco :** `areAllied` deux sens + expiry OK ; bots `humanTargetProtected` OK. **Tribus** : `Tribes.decideAttack` n’appelle pas `humanTargetProtected` (88 % skip seulement) — écart feel vs hardening/visual, **non porté** cette passe (gameplay, pas stub). Scan cadran O(carte) encore N9. `Trade.dispatch` `{}` encore (hardening N92, pas sur feel). Aucun bug clair sûr hors N151. `CARRIER_MESH_ID` reste `""` — le chemin mesh n’est pas exercé par le banc (N148 est un crash latent, pas un vert runtime). BuildingModels `animate` n’a plus de `child.Position` 60 Hz. UnitModels n’a plus de `offset.Position` 60 Hz. UnitModels n’a plus de `CFrame.Angles` vivant. `HUD.feedEntries` `table.remove(1)` encore (leftover N153, MAX=3). Serveur feel : `table.remove` bateaux/missiles encore (hardening N105–N106, ne pas porter). UnitModels `place` flamme `Size = Vector3.new` encore (leftover N152, **≠** visual V74 freeze Size=API).

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N151 du rapport #178. N152 **non livré** (spec : si le seul patch est un freeze, ne pas livrer).

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| UnitModels `place` trail `offset.Position.Z` 60 Hz (N151) | `UnitModels.luau` (`place` trail **seulement**, **un** `elseif`), `tests/client.luau` (check navires) | Leftover N150. `offset.Z` au lieu de `offset.Position.Z`. Amplitude `0.035` / fréquence `time * 9` / clamp `0.25..0.9` / `+=` Transparency inchangés. Cosmétique. Flame leftover N152 **alors** ; beacons N150 / fenêtres N149 **inchangés**. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), UnitModels flamme `Size = Vector3.new` (**N152**, **≠** visual V74 freeze — **non livré**), `HUD.feedEntries` `table.remove(1)` (**N153**), flamme Size = API leftover visual V74 fermée Option A — feel **garde** le pulse, ne pas merger, PlacementPreview Size rayon (visual V76, feel Size = API), PlacementPreview early-out hover (visual V77, **pas merger**), Overlay LaunchWake `wakeRot` (visual V78, feel N130 **inline**, **pas merger**), Overlay LandingSplash `wakeRot` (visual V79, feel N131 **inline**, **pas merger**), Overlay DeliveryPulse `wakeRot` (visual V80, feel N132 **inline**, **pas merger**), Overlay Shockwave `wakeRot` (visual V81, feel N133 **inline**, **pas merger**), tribus `humanTargetProtected`. Overlay / Effects / WorldCamera / HUD / Minimap / PlacementPreview / WorldRenderer / BuildingModels / serveur **non édités**. Trail hors `offset.Z` **non**. Flame **non**. Radar / flag **non** (N127/N128 déjà). Wake / light **non**. `createMissile` construction **non**. `Fin` **non**. Mesh **non**.

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
- Overlay interpolation X/Z + yaw euler (**N117**) **et** camion `segRot` (**N115**) **et** roulis navire (**N125**) **et** roues camion (**N126**). Camera : lerp nombres (**N121**) + champ `focusX/Y/Z` (**N122**) + shake (**N119**) + offset (**N120**) + pose (**N118**). Minimap `setFocus(x,y,z)` (**N123**). Radar/Flag/Boom euler (**N124**). `UnitModels.place` radar euler (**N127**) **et** flag euler (**N128**). `PlacementPreview.update` footprint euler (**N129**). Overlay LaunchWake euler (**N130**). Overlay LandingSplash euler (**N131**). Overlay DeliveryPulse euler (**N132**). Overlay Shockwave euler (**N133**). Effects `conquestPulse` ring euler (**N134**). WorldRenderer OceanGlint euler (**N135**). BuildingModels `BuildRing` euler (**N136**). WorldRenderer trunks euler (**N137**). WorldRenderer Rock euler (**N138**). BuildingModels `cylinder()` euler (**N139**). BuildingModels toits usine euler (**N140**). BuildingModels portes silo euler (**N141**). BuildingModels rampes SAM euler (**N142**). UnitModels houle `addWake` euler (**N143**). UnitModels proue `Bow` euler (**N144**). UnitModels rampe `LandingRamp` euler (**N145**). UnitModels corps missile `MissileBody` euler (**N146**). UnitModels ailettes `Fin` euler (**N147**). UnitModels mesh carrier `visual.pieces` (**N148**). BuildingModels `CityWindows` `rest.X` (**N149**). BuildingModels beacons `rest.Z` (**N150**). UnitModels trail `offset.Z` (**N151**). UnitModels flamme `Size = Vector3.new` encore 60 Hz (**N152**). `HUD.feedEntries` `table.remove(1)` encore (**N153**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (N152 restant + N153)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26, N29–N151 = faits. N22 = **N67 fait**. N27 = doc only. **N152** reste ouvert (non livrable sans freeze V74). **N153** = nouveau. **V73 / N127 / N128** fermés passe 49. **N129 / N130** fermés passe 50. **N131 / N132** fermés passe 51. **N133 / N134** fermés passe 52. **N135 / N136** fermés passe 53. **N137 / N138** fermés passe 54. **N139 / N140** fermés passe 55. **N141 / N142** fermés passe 56. **N143 / N144** fermés passe 57. **N145 / N146** fermés passe 58. **N147 / N148** fermés passe 59. **N149 / N150** fermés passe 60. **N151** fermé ici (porté, pas mergé). Leftover feel UnitModels flamme `Size = Vector3.new` = **N152** (**≠** visual V74 freeze Size=API — feel **garde** le pulse, ne pas merger `c0ec` ; **si le seul patch est un freeze : ne pas livrer**). Leftover feel `HUD.feedEntries` `table.remove(1)` = **N153** (recette hardening N110, porter ne pas merger `41e2`). Flamme `Size = Vector3.new` visual V74 **fermée** Option A sur `c0ec` (Size = API, ne pas porter). PlacementPreview Size rayon = visual V76 **fermée** sur `70a5` (feel Size = API, ne pas merger). PlacementPreview early-out hover = visual V77 **fermée** sur `185a` (feel **pas merger**). Overlay LaunchWake `wakeRot` = visual V78 **fermée** sur `6183` (feel N130 **inline**, ne pas merger). Overlay LandingSplash `wakeRot` = visual V79 **fermée** sur `54d6` (feel N131 **inline**, ne pas merger). Overlay DeliveryPulse `wakeRot` = visual V80 **fermée** sur `a597` (feel N132 **inline**, ne pas merger). Overlay Shockwave `wakeRot` = visual V81 **fermée** sur `47c0` (feel N133 **inline**, ne pas merger). Effects `conquestPulse` `pulseRot` = visual V82 **fermée** sur `490f` (feel N134 **inline** Y=3, **≠** visual surface+0.8, ne pas merger). Effects SelectionRing `pulseRot` = visual V83 **fermée** sur `0b3d` (ne pas merger). Visual V85 BuildRing **fermée** sur `7be5` / PR #174 (feel N136 **déjà**, ne pas merger). Visual V84 OceanGlint **fermée** sur `8015`. Visual V86 TreeTrunk **fermée** sur `75ce` / PR #177 (feel N137 **déjà**, ne pas merger `c299`). Visual V87 Rock **fermée** sur `2b04` / PR #179 (feel N138 **déjà**, ne pas merger `c299`). Visual V88 `cylinder()` **fermée** sur `f9ec` (feel N139 **déjà**, ne pas merger `a8e1`).

---

### ISSUE-N152 — UnitModels `place` flamme `Size = Vector3.new` 60 Hz (feel)

**Priorité :** P3 alloc client UnitModels. Leftover explicite après N151 (trail `offset.Z` déjà). Distinct de N151 (trail Transparency), de visual V74 (Size = API freeze — **ne pas merger** `c0ec`). `UnitModels.place` branche `piece.role == "flame"` **seulement**. Ne pas toucher trail. Ne pas toucher `BuildingModels`. Ne pas toucher Overlay. Ne pas toucher HUD.

**Problème :** N151 ferme le trail. Reste, **chaque frame** (`UnitModels.place`, 60 Hz, une Part `EngineFlame` par ogive) :

```
piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)
```

`Vector3.new` alloue pour écrire `Size`. Visual V74 Option A a **gelé** Size = API (plus de pulse Size, `c0ec` / PR #151). Feel **garde** le pulse Z. Ne pas porter `c0ec`. Distinct de leftover N151 (`offset.Z` trail **déjà**). Distinct de leftover N153 (`HUD.feedEntries` `table.remove`). Amplitude `0.45` / fréquence `time * 18` / base `1.8` / XY `0.62` **inchangés**. Role `"flame"` **inchangé**. Shape `Ball` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × ogives × 60 Hz × `Vector3` pour un pulse de Size. Pas d’autorité. Trail **déjà** N151 — ne pas y revenir. Beacons **déjà** N150 — ne pas y revenir. Visual V74 freeze **interdit** (feel ≠ visual). **Passe 61 a refusé de livrer N152** : le seul patch distinct de l’API serait le freeze.

**Worker :**

1. Dans `UnitModels.place` branche `role == "flame"` seulement : **conserver** le pulse `1.8 + math.sin(time * 18) * 0.45`. **Ne pas** geler Size (visual V74 Option A, ne pas merger `c0ec`). L’API `Size` exige un `Vector3` : garder `piece.part.Size = Vector3.new(0.62, 0.62, 1.8 + math.sin(time * 18) * 0.45)`. XY `0.62` / base `1.8` / freq `18` / amp `0.45` **inchangés**.

2. **Garder le pulse.** Ne **pas** poser Size = API. Ne **pas** « fermer » trail (N151 déjà). Ne **pas** lire `piece.part.Size` (alloc). Ne pas porter visual. Après N151. Trail **non**. Radar / flag **non**. Wake **non**. `BuildingModels` **non**. Overlay **non**. HUD **non**. `createMissile` construction **non** (taille initiale `Vector3.new(0.62, 0.62, 2.3)` inchangée).

3. **Si le seul patch possible est un freeze Size=API : ne pas livrer N152. Laisser la ligne inchangée. Livrer N153 seulement.** N152 reste alors ouvert (feel-diverged vs V74). Ne pas inventer un cache Size. Ne pas skip-si-inchangé (N2, pas ici).

4. Tests « navires, missiles et interpolation » leftover N151 trail **et** leftover N148 mesh **et** leftover N147 Fin **doivent rester verts**. Tests « modeles procéduraux » leftover N150 / N149 **doivent rester verts**. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `UnitModels.luau` (`place` flame **seulement**, **un** `elseif`) **seulement si** un patch feel distinct de V74 existe. Sinon **aucun** fichier flame. `tests/client.luau` **seulement si** le check navires ne mentionne pas encore N152 (commentaire leftover, **garder** N151/N148). `BuildingModels.luau` **non**. `Overlay.luau` **non**. `HUD.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher trail ni beacons.

**Contraintes :** pas de RemoteFunction. **N152 feel ≠ N151 (trail Z) ≠ visual V74 (freeze Size=API, ne pas merger) ≠ N153 (HUD feed) ≠ N150 (beacons) ≠ N2 (skip-si-inchangé).** Non réentrant. Ne pas fusionner avec N153 dans le même worker. Pulse Z **conservé** — ne pas figer à 1.8. Un `elseif` flame.

---

### ISSUE-N153 — HUD `feedEntries` `table.remove(1)` au plafond (feel)

**Priorité :** P3 alloc client HUD. Leftover explicite après N151 (trail `offset.Z` déjà) et N152 (flame Size, **non livré**). Distinct de N152 (UnitModels Size), de N112 (`dirtyHead` WorldRenderer **déjà**), de hardening N110 (même sujet, **porter ne pas merger** `41e2`). `HUD.notify` boucle `while #self.feedEntries > MAX_FEED_ENTRIES` **seulement**. Ne pas toucher `removeEntry` (croix Dismiss). Ne pas toucher UnitModels. Ne pas toucher Overlay.

**Problème :** N151 ferme le trail. N152 reste ouvert (freeze interdit). Reste, **à chaque notify au-delà du plafond** (`HUD.notify`, `MAX_FEED_ENTRIES = 3`) :

```
while #self.feedEntries > MAX_FEED_ENTRIES do
    local oldest = table.remove(self.feedEntries, 1)
    if oldest then
        removeEntry(oldest)
    end
end
```

`table.remove(self.feedEntries, 1)` décale les 2 restantes. `removeEntry` refait `table.find` (miss, déjà retiré) puis `Destroy`. FIFO / `LayoutOrder` **inchangés**. Distinct de leftover N152 (`Size = Vector3.new` flamme). Distinct de leftover N112 (`dirtyHead` chunks, **déjà**). Recette hardening N110 sur `41e2` — porter, **ne pas merger**. `MAX_FEED_ENTRIES = 3` **inchangé**. Groupement `feedGroups[text]` **inchangé**. `task.delay(4.5)` **inchangé**.

**Pourquoi 20K CCU :** leftover N151. 8 clients × rafales notify (trahison, cadran, conquête). `n=3` est petit, même classe que `dirtyQueue` N112 (curseur, plus de `table.remove(1)`). Pas d’autorité (cosmétique HUD). Trail **déjà** N151 — ne pas y revenir. Flame leftover N152 **alors** (ne pas freeze). WorldRenderer dirty **déjà** N112/N114 — ne pas y revenir.

**Worker :**

1. Dans `HUD.notify` boucle plafond seulement : remplacer `table.remove(self.feedEntries, 1)` par un décalage préfixe in-place. FIFO conservé :

```
local n = #self.feedEntries
local oldest = self.feedEntries[1]
for i = 1, n - 1 do
    self.feedEntries[i] = self.feedEntries[i + 1]
end
self.feedEntries[n] = nil
removeEntry(oldest)
```

`#feedEntries` après shift = `n - 1`. Leftover `[4] == nil` (MAX=3, un 4e vient d’être inséré puis le plus vieux part). Appeler `removeEntry(oldest)` **après** le shift (comme aujourd’hui : `table.find` rate, pas de double-retrait, `Destroy` + `feedGroups` nil). `while #self.feedEntries > MAX_FEED_ENTRIES` **conservé**.

2. **Garder FIFO.** Ne **pas** swap-pop (ça inverserait `LayoutOrder` / le plus vieux ne serait plus en tête). Ne **pas** inventer `feedHead` (N112 est WorldRenderer, pas ici — n=3, décalage suffit). Ne **pas** toucher `removeEntry` / Dismiss `table.remove(self.feedEntries, index)` (geste joueur, pas le plafond). Ne **pas** toucher `feedGroups` / groupement. Ne **pas** changer `MAX_FEED_ENTRIES`. Ne **pas** porter hardening `41e2` (N107/N108 serveur). Après N151. Flame **non** (N152). Trail **non**. `UnitModels` **non**. Overlay **non**. WorldRenderer **non**.

3. Tests « fil de notifications sature » leftover groupement / croix / compteur reset **doivent rester verts** (`#feedEntries` après Dismiss, `feedGroups["a degager"].count == 1`). Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

4. Test : banc client `fil de notifications sature` **doit rester vert** (40 messages, plafond 3, répétition groupée, Dismiss, compteur). Check navires leftover N151 `offset.Z`. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.

5. Fichiers : `HUD.luau` (`notify` boucle plafond **seulement**). `tests/client.luau` **seulement si** le check fil ne mentionne pas encore N153 (commentaire leftover, **garder** le check existant). `UnitModels.luau` **non**. `Overlay.luau` **non**. **Ne pas** éditer le serveur. **Ne pas** toucher flame ni trail ni Dismiss.

**Contraintes :** pas de RemoteFunction. **N153 feel ≠ N152 (flame Size, ne pas freeze V74) ≠ N151 (trail Z) ≠ hardening N110 (porter ne pas merger `41e2`) ≠ N112 (`dirtyHead` chunks).** Non réentrant. Ne pas fusionner avec N152 dans le même worker. FIFO **conservé** — ne pas swap-pop. Un `while` plafond — ne pas splitter Dismiss.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; … ; fenêtres → **N149 fait** ; beacons → **N150 fait** ; trail → **N151 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; … ; trail → **N151 fait** ; `HUD.feedEntries` `table.remove(1)` = **N153**) |
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
| N34–N150 | (voir rapport #178) | — | **faits** |
| N151 | UnitModels `place` trail `offset.Position.Z` 60 Hz | P3 | **fait** cette passe (`place`, `offset.Z`) |
| N152 | UnitModels `place` flamme `Size = Vector3.new` 60 Hz | P3 | **ouvert** (`place`, pulse Z **conservé**, **≠** visual V74 freeze ; **non livré** passe 61) |
| N153 | HUD `feedEntries` `table.remove(1)` plafond | P3 | **nouveau** (`notify` while-cap, FIFO, porter N110 sans merger `41e2`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 / #101 / #106 / #108 / #111 / #114 / #118 / #121 / #125 / #128 / #131 / #133 / #136 / #140 / #144 / #147 / #150 / #153 / #155 / #158 / #161 / #163 / #165 / #167 / #169 / #171 / #173 / #176 / #178 `NIGHTLY_REPORT.md` historique.

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
| `TILE_SIZE` | 12 | n/a | oui (N101 lerp monde … N151 trail) |

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

Client : **35/35 OK** — dont `construction du monde 3D` (N137 trunks `fromEulerAnglesYXZ` Z=90, N138 Rock `fromEulerAnglesYXZ` yaw `phase`, leftover N135 OceanGlint yaw `angle`, leftover N114 compact, leftover N112 `dirtyHead`, leftover N106/N107/N108) ; `pose et capture de chaque type de batiment` (N136 `BuildRing` `fromEulerAnglesYXZ`, leftover N132 DeliveryPulse, leftover N126 roues, leftover N115 `segRot`, leftover N113 `rot` chantier) ; `modeles procéduraux` (N150 beacons `rest.Z`, N149 `CityWindows` `rest.X`, leftover N142 Interceptor `fromEulerAnglesYXZ` pitch X=-31°, leftover N141 portes silo Z=±18°, leftover N140 toits usine Z=-12°, leftover N139 `cylinder()` Z=90, leftover N124 radar/flag/boom, leftover N109 câble Y, Parts stables, rotation visible CFrame ≠ RestCFrame, Y inchangé = pas une translation) ; `apercu de placement pour chaque batiment` (N129 footprint `fromEulerAnglesYXZ`, leftover N92 ctx, ghost visible / snap / upgrade, hauteur 0.4) ; `navires, missiles et interpolation` (N151 trail `offset.Z` ; N148 `visual.pieces` mesh, `CARRIER_MESH_ID` reste `""` ; N147 Fin `fromEulerAnglesYXZ` Z=axis·π/2 ; leftover N146 MissileBody `fromEulerAnglesYXZ` Y=90° ; leftover N145 LandingRamp `fromEulerAnglesYXZ` pitch X=-8° ; leftover N144 Bow `fromEulerAnglesYXZ` Y=π ; leftover N143 houle `addWake` `fromEulerAnglesYXZ` yaw `side*11°` ; leftover N133 Shockwave ; leftover N131 LandingSplash ; leftover N130 LaunchWake ; leftover N128 flag ; leftover N127 radar euler ; leftover N125 roulis ; leftover N117 second frame lerp sous yaw euler ; leftover N116 navire immobile `currentX == targetX` ; leftover N103 lerp missile, N98 extra `rawequal`, N101 `targetX`, navire `extra == nil`, `retreatTinted` conservé ; leftover N152 flame Size ; `overlay:explosion` N133) ; `fil de notifications sature` leftover N153 `table.remove(1)` ; `livraison : le gain s'affiche sur la gare` leftover N20 ; `vagues de conquete` N134 `conquestPulse` `fromEulerAnglesYXZ`. Serveur **non** touché cette passe. `HUD.luau` **non** touché. `WorldCamera.luau` **non** touché. `Overlay.luau` **non** touché. `Effects.luau` **non** touché. `PlacementPreview.luau` **non** touché. `Minimap.luau` **non** touché. `WorldSpace.luau` **non** touché. `GreedyMesh.luau` **non** touché. `WorldRenderer.luau` **non** touché. `BuildingModels.luau` **non** touché. UnitModels hors `place` trail **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass61.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N151 est une lecture `offset.Z` vérifiée par le banc headless (`place` ogive trail ne lève pas ; radar / flag leftovers N127/N128 restent verts). Pulse trail Transparency **inchangé** (N151 ne touche que la source de phase).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N151 n’ajoute **pas** de require (`offset.Z` local UnitModels `place` trail). N152 restera dans `UnitModels.place` flame. N153 restera dans `HUD.notify` plafond.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N125 : `frame` a déjà translation × yaw — **ne pas** réduire à `CFrame.new * euler`. Immobile = zéro compose. Missile = pas de roulis. Recette visual V71 déjà sur `9ab9` — porter, ne pas merger.

Piège N126 : spin réel `progress * π * 20` dans un local `spin`. `frame` a déjà `segRot`. Ne pas cuire le spin dans `piece.offset`. Recette visual V72 déjà sur `9793` — porter, ne pas merger.

Piège N127 : garder `piece.offset * euler`, **ne pas** réduire à `CFrame.new(offset.X,Y,Z) * euler` (recette N124 bâtiments). Distinct SAM Radar N124 (`time * 1.45`). Leftover visual V73 déjà fermé sur `1b5c` (`localFrame * euler`, équivalent) — porter, ne pas merger.

Piège N128 : amplitude 0.06 / fréquence 5. Distinct CapitalFlag N124 (deux sin, rest identité). Ne pas fusionner avec N127. Leftover visual V73 déjà fermé sur `1b5c` — porter, ne pas merger.

Piège N129 : cylindre à plat Z=90. Ne pas omettre l’euler (le cylindre se dresserait). Hauteur feel **0.4** ≠ visual 0.42. Ne pas inventer `self.pulse`. Size footprint **API**. Visual V75 **fermée** sur `c0ec` (`footprintRot` + pulse) — porter euler worker #153, pas merger.

Piège N130 : insert navire seulement, pas `stepInterpolation`. Offset Y `+ 0.12` ≠ splash `+ 0.14`. **Inline** `fromEulerAnglesYXZ` — **ne pas** porter visual V78 `wakeRot` cuit (`6183` / PR #162). Ne pas fusionner splash/pulse/shockwave.

Piège N131 : despawn non-retraite seulement. N56 skip retraite **conservé**. Distinct pulse N132 (`route.to` terre). Distinct wake N130 (`origin` spawn, Y `+ 0.12`). Visual V79 LandingSplash `wakeRot` **fermée** sur `54d6` (feel **déjà** N131 **inline** — ne pas merger `54d6` / `5aa9`).

Piège N132 : fin de `delivery` seulement, pas construction voie. `route.to` déjà Vector3 — ne pas `tileToWorld`. Distinct shockwave N133. Visual V80 DeliveryPulse `wakeRot` **fermée** sur `a597` (feel **déjà** N132 **inline** — ne pas merger `a597` / `5aa9`).

Piège N133 : `explosion` seulement. Sphère / fumée **sans** euler. Distinct Effects ring N134 (`Y = 3`). Distinct DeliveryPulse N132 (`route.to` gare). Distinct splash N131 (mer). Visual V81 Shockwave `wakeRot` **fermée** sur `47c0` (feel **déjà** N133 **inline** — ne pas merger).

Piège N134 : `conquestPulse` seulement, pas Overlay. Caps flash **conservés**. Distinct OceanGlint N135 (yaw `angle`). Distinct Shockwave N133 (`PLAINS + 0.5`).

Piège N135 : `buildOcean` seulement. Yaw `angle` **variable** — ne pas figer. Distinct `BuildRing` N136 (Z=90). Distinct trunks N137. `step` **non** (N108 déjà). Plan Ocean / SeaFloor **sans** euler.

Piège N136 : `playConstruction` seulement, pas `animate`. Distinct trunks N137. Distinct OceanGlint N135 (yaw). Distinct `cylinder()` N139.

Piège N137 : `buildDecorations` trunks seulement. Z=90 **deux** call sites ensemble. Distinct Rock N138 (yaw `phase`). `step` **non**.

Piège N138 : `buildDecorations` Rock seulement. Yaw `phase` **variable** — ne pas figer. Distinct trunks N137 (Z=90). Distinct BuildingModels `cylinder()` N139.

Piège N139 : helper `cylinder()` seulement. Z=90 **un** site. Ne pas inliner. Distinct toits N140 (Z=-12°). `playConstruction` **non**. Call sites `buildFactory` / `buildSilo` **non édités**.

Piège N140 : `buildFactory` toits seulement. Z=-12° **fixe**. Distinct `cylinder()` N139 (Z=90). Distinct portes silo N141 (`±18°`). Distinct rampes SAM N142 (`pitch -31°`).

Piège N141 : `buildSilo` portes seulement. Z=+18° **et** Z=-18°. **Deux** sites ensemble. Ne pas splitter A/B. Distinct rampes N142 (pitch X). `cylinder()` **non**.

Piège N142 : `buildSam` launchers seulement. Pitch X=-31° **fixe**. Distinct portes N141 (Z). Distinct Radar `animate` N124. Distinct houle N143.

Piège N143 : `addWake` seulement. Yaw Y=`side * 11°` **variable** — ne pas figer. **Deux** sides ensemble. Distinct proue N144 (Y=π). Overlay LaunchWake **non** (N130 déjà).

Piège N144 : `Bow` seulement. Yaw Y=π **fixe**. **Deux** sites ensemble (carrier + transport/cargo). Ne pas splitter. Distinct houle N143 (±11°). Distinct rampe N145 (pitch -8°).

Piège N145 : `LandingRamp` seulement. Pitch X=-8° **fixe**. **Un** site (transport amphibie kind==1). Distinct missile N146 (Y=90). Distinct SAM N142 (pitch -31°). Cargo kind==2 **sans** rampe — ne pas en inventer.

Piège N146 : `MissileBody` seulement. Yaw Y=90° **fixe**. **Un** site. Distinct ailettes N147 (`Z = axis * π/2`). Distinct `cylinder()` N139 (Z=90 bâtiments). Nez / bandes / flamme **sans** euler.

Piège N147 : `Fin` seulement. Roll Z=`axis * π/2` **variable**. **Quatre** sites ensemble (boucle `axis = 0..3`). Distinct corps N146 (Y=90). Distinct leftover N148 (`visual.parts` → `pieces`, **fait**). Nez / bandes / flamme **non**.

Piège N148 : `table.insert` mesh seulement. `visual.pieces` **pas** `visual.parts`. `CARRIER_MESH_ID` **reste `""`**. Distinct Fin N147. Coque procédurale **non**. Ne pas ajouter `addWake` sur le chemin mesh.

Piège N149 : `CityWindows` seulement. `rest.X` **pas** `child.Position.X`. Amplitude / fréquence inchangées. Distinct beacons N150 (`rest.Z`, **fait**). Distinct trail N151 (`offset.Z`, **fait**).

Piège N150 : beacons seulement (`CityBeacon` / `PortBeacon` / `LabBeacon`, un `elseif`). `rest.Z` **pas** `child.Position.Z`. Trois noms ensemble. Distinct fenêtres N149. Distinct trail N151.

Piège N151 : trail seulement. `piece.offset.Z` **pas** `piece.offset.Position.Z`. Amplitude / `+=` Transparency inchangés. Distinct flame leftover N152 (`Size = Vector3.new`, **≠** visual V74 freeze). Distinct beacons N150. Distinct HUD leftover N153.

Piège N152 (à venir) : flame seulement. Pulse Z **conservé**. **Ne pas** geler Size (visual V74, ne pas merger `c0ec`). Distinct trail N151. Distinct HUD N153. Si le seul patch est un freeze : **ne pas livrer N152**.

Piège N153 (à venir) : plafond `notify` seulement. Décalage préfixe **pas** `table.remove(1)`, **pas** swap-pop. FIFO / MAX=3 inchangés. Distinct Dismiss `table.remove(index)`. Distinct dirtyHead N112. Distinct flame N152. Porter hardening N110, **ne pas merger** `41e2`.
