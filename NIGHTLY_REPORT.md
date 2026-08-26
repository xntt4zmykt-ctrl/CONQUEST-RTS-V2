# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 26)

Déclencheur : ouverture de la **PR #75** (`cursor/analyse-nocturne-du-codebase-2f5d`) — expiredBuf, contactBuf, specs N81–N82.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-b62d`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#76.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. `siteBuf` / `elimBuf` sont des pools module-level, pas de l’état répliqué.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #75 (passe 25) : claims vérifiés.** `Diplomacy.step` recycle `expiredBuf` / `expiredRecPool` (N79) ; `Bots.neighborFactions` recycle `contactBuf` (N80). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #75 a documenté (N81, N82)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #75

| Claim #75 | Réalité à l’ouverture |
|---|---|
| `expiredBuf` / `expiredRecPool` (N79) | Oui. Collecte `a < b` puis mutation. `true` legacy : `typeof == "number"`. Pas TRAHI. |
| `contactBuf` (N80) | Oui. `table.clear` (map). 4 call sites séquentiels. Slot 99 → vide. |
| Specs N81–N82 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #76 (4197), feel jusqu’à #75, visuelles #39/#44/#47/#50/#54/#57/#61/#64/#67/#69/#72/#74. **#75 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#73←#76) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N81–N82 du rapport #75.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `Bots.gatherSites` alloue un array par décision build (N81) | `Bots.luau` (`gatherSites` + 1 call site `decideBuild`), `tests/simulate.luau` | Leftover N80. Pool `siteBuf` (`table.create(60)`, cap DEFENSE). Caps 40/60/45 inchangés. Pas de shuffle. Promu `Bots.gatherSites`. Truncate leftover (recette N68). Slot / côte vide → `# == 0`. |
| `GameState.stepElimination` alloue `doomed` 10 Hz (N82) | `GameState.luau` (`stepElimination` seulement), `tests/simulate.luau` | Leftover N79 (alloc porteuse / tick). Pool `elimBuf` (`table.create(8)`). **Pas** nommé `doomed` (`removePlayer` snapshot bâtiments). Truncate leftover avant traitement ; ne pas truncate à 0 après return. Loi inchangée : bot silencieux, humain notify, bateau / front → survit. Buffer partagé entre instances (recette N70). |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `findSeaPath` path+reversed (N83), `refreshRailNetwork` stations (N84), `Buildings.contextFor` alloc par resolve.

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (seq obligatoire en playing, apply immédiat) → tick :
  Bots.step → Navy.step (syncCarriers si dirty, spawn via navalBasesBySlot ;
    stepCarriers via carrierBuf/targetBuf, early-out 0 carrier / 0 autre slot ;
    coule TRADE si PORT absent ; TRANSPORT retraite si owner ~= targetSlot ;
    spawnTradeShips si tick % 45 == 0, via portsByTile) → Nukes.step
              (stepCooldowns SAM+silo indexés ; tryIntercept via samsBySlot ;
               launch via silosBySlot) → Trade.step (factoriesBySlot + factoryBuf)
              → Diplomacy.step (expiredBuf N79) → GameState.step → replicate(
                flushOwnerDelta via dirtyIndexBuf,
                playerStatsForReplicate + pricesFor + Research.progress (min courant),
                fireDeployed, snapshotBoats, snapshotMissiles,
                flushBuildingDelta via buildingSnapBuf)
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom), BoatFront, AimFront, tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`. Stub = `error(...)`. Deux débarquements du même couple = **deux** tas (N5 ouvert ; hardening N29).
- **`areAllied`** = deux directions **et** `tick < expiry` (`true` legacy tests reste vivant).
- **AimFront wrap** = re-visée du front terre du couple ; jamais `isBeachhead`.
- **`tryAnnex`** = BFS depuis les voisins défenseur du seed déjà capturé ; océan abort ; pool N37-like.
- **Carriers** = spawn/despawn/slot sur dirty NAVAL_BASE, spawn via `navalBasesBySlot` (N65). Ciblage obus = `carrierBuf`/`targetBuf` recyclés **(N67)**. Pas de spatial hash.
- **Posted bunker** = index `bunkersBySlot`. **Posted SAM** = `samsBySlot`. **Posted SILO** = `silosBySlot`. **Posted FACTORY** = `factoriesBySlot`. **Tous** = `buildingsBySlot`. **PORT** = `portsByTile`. **Posted NAVAL_BASE** = `navalBasesBySlot`.
- **`samsOf`** = lit `samsBySlot` dans `samBuf` recyclé (N68). `tryIntercept` lit l’index directement (N57).
- **Score nuke bots** = flatten `buildingsBySlot` une fois (N69), puis 90 `scoreBlast`.
- **Inbound `removePlayer`** = snapshot `buildingsBySlot` → destroy → diplo + transports `kind==1` (100 %, lit **`owner[targetTile]`**) + missiles contrat B + cadran/colis + convois `kind==2` (coulés), **avant** `setOwner`.
- **Hover spawn** = `SpawnHint` (Shared) si `tiles==0`. Serveur = `claimSpawn` (N52+N55).
- **Réplication :** StateDelta (`dirtyIndexBuf` N72, HUD fronts N74 via N76, `buildPrices` N75, records stats N76, `eraProgress` N77) / UnitSnapshot (`retreating`, `boatSnapBuf` N70, `missileSnapBuf` N71) / BuildingDelta (`buildingSnapBuf` N73) / plunder / trade / explosions / notify&sfx déployés / Diplomacy.viewFor 1 Hz (N78). `path` / `homeTile` / `progress` **non** répliqués. Playing 10 Hz ; lobby vide et ended → 1 Hz. `Diplomacy.step` recycle `expiredBuf` (**N79**). `Bots.neighborFactions` recycle `contactBuf` (**N80**). `gatherSites` recycle `siteBuf` (**N81**). `stepElimination` recycle `elimBuf` (**N82**). `findSeaPath` alloue encore path+reversed par trajet réussi (**N83**). `refreshRailNetwork` alloue encore `stations` / `parent` / `neighborsOf` (**N84**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N83–N84)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N82 = faits. N22 = **N67 fait**. N27 = doc only.

---

### ISSUE-N83 — `Navy.findSeaPath` alloue path + reversed par trajet réussi (feel)

**Priorité :** P3 alloc marine. Leftover explicite de N37 (`visitBuf` / `parentScratch` / `queueScratch` déjà poolés). Distinct de N37 (BFS visité) et de N63 (`portsBuf` / `candidateBuf` vague commerciale). Ne pas toucher `syncCarriers` / `stepCarriers` / `targetSlot`.

**Problème :** un trajet réussi construit `local path = { toTile }` puis `table.insert` en remontant `parent`, puis `local reversed = table.create(#path)` et un second remplissage. Deux allocations par invasion, retraite, et convoi commercial. Les trois call sites **prennent possession** du retour : `boat.path = path` (`launchInvasion`, retraite, `spawnTradeShips`). Un `pathBuf` partagé aliaserait le trajet du bateau A quand B cherche une route — le transport suivrait alors le chemin d’un autre.

**Pourquoi 20K CCU :** N37 a déjà payé le BFS (40k tuiles visitées sans alloc). Il reste le double alloc du résultat, sur chaque vague `TRADE_SHIP_INTERVAL` (45 ticks) et chaque débarquement. Recycle du **walk** seulement ; le tableau rendu au bateau **doit rester unique**. Pas d’autorité (la géométrie du trajet ne change pas).

**Worker :**

1. Ajouter `pathWalkBuf` module-level (`table.create(256)`). Au hit `nb == toTile` : n = 0 ; poser `toTile` puis remonter `current` jusqu’à `fromTile` **exclu** (loi actuelle : l’origine terrestre n’est pas dans le path). `pathWalkBuf[n] = node`. Truncate leftover n+1..#. Allouer **un** `out = table.create(n)` et copier **à l’envers** (`out[i] = pathWalkBuf[n - i + 1]`). `return out`. Ne **pas** `return pathWalkBuf`. Pas de RemoteFunction. Pas de second tableau `reversed`.
2. Ne pas modifier `launchInvasion` / retraite / `spawnTradeShips` (ils stockent déjà le retour). Ne pas require de module nouveau. Ne pas toucher `visitBuf` / `parentScratch` / `queueScratch`. `buffer.fill(visitBuf, 0, 0)` inchangé. Échec BFS / `MAX_BFS_NODES` → `nil` comme aujourd’hui.
3. Test : banc N37 existant (4 appels, même contenu, trajet inverse ne pollue pas) **doit rester vert**. Ajouter : deux appels successifs même paire → **pas** `rawequal` (identité unique). Stocker `p1`, rappeler, `p1[i]` inchangé (pas de mutation du path du premier bateau). Client 35/35. 6000 ticks.
4. Fichiers : `Navy.luau` (`findSeaPath` seulement), `tests/simulate.luau` (bloc court à côté du banc N37).

**Contraintes :** pas de RemoteFunction. Recette N37 (pools BFS) + **ownership** du retour (comme `building.links` N84 — unique, pas partagé). **N83 feel ≠ N37 (BFS visité, déjà fait) ≠ N63 (ports commerciaux) ≠ N49 (`targetSlot`).** `pathWalkBuf` n’est pas réentrant. `findSeaPath` est synchrone et unique. Ne pas `table.clone` du walk pour « être prudent » : ça réintroduit la deuxième alloc. Overlay n’itère pas `boat.path` (non répliqué) — le test d’identité est pour les call sites serveur.

---

### ISSUE-N84 — `GameState.refreshRailNetwork` alloue stations / parent / neighborsOf (feel)

**Priorité :** P3 alloc pose/capture. Leftover explicite de N64 (`buildingsBySlot[slot]` déjà, plus le hash global). Distinct de N64 (index) et de N20 (`stopBonus` HUD). Ne pas toucher `Trade.step` / `deliveryValue` / `elimBuf`.

**Problème :** chaque `placeBuilding` / `destroyBuilding` / `transferBuilding` d’une gare reconstruit `local stations = {}`, `parent = table.create(count)`, `xs`/`ys`, `neighborsOf` (une table interne **par** gare) et deux maps de grappe. Pas 10 Hz, mais une partie Classique pose/capture des dizaines de gares, et `table.sort(stations)` plus union-find O(gares²) paient déjà le CPU. `building.links = links` **prend possession** de `neighborsOf[i]` : un pool partagé des inners aliaserait les voies de deux usines (et le dirty BuildingDelta).

**Pourquoi 20K CCU :** leftover N64. Recycle des **porteuses** (stations, parent, xs, ys, maps de grappe) élimine l’alloc courte. Les inners `neighborsOf` stockées dans `building.links` restent uniques — même classe que N83 (`boat.path`). Pas d’autorité (tri + union-find inchangés ; sans tri les liens répliqués danseraient).

**Worker :**

1. Ajouter `stationBuf` module-level (`table.create(32)`), plus `railParentBuf` / `railXsBuf` / `railYsBuf` (`table.create(32)`), plus `clusterStations` / `clusterFactoryCount` maps recyclées (`table.clear`). Au début : n = 0. Même collecte N64 (`buildingsBySlot[slot]`, fallback hash, kinds CITY/CAPITAL/PORT/FACTORY, **pas** DEFENSE). `stationBuf[n] = index`. **Truncate leftover puis `table.sort(stationBuf)`** — `table.sort` sur un leftover non truncaté mélangerait d’anciennes gares. `count = n`. Remplir parent/xs/ys dans les buf existants (itérer `1..count`, pas `#`). Maps de grappe : `table.clear` puis refill.
2. **Ne pas** recycler les inners `neighborsOf[i]` dans un pool partagé. Allouer `{}` par gare comme aujourd’hui (elles deviennent `building.links` si usine + changed). Option B (écrire dans `building.links` existant) **interdite** pour ce worker : Overlay / BuildingDelta comparent l’identité via le dirty, et un `table.clear` in-place pendant qu’un snapshot N73 tient `links` live casserait le wire. Ne pas require de module nouveau. Ne **pas** référencer `IS_STATION` (local trop bas, nil au runtime — piège N64). Ne pas toucher `elimBuf`.
3. Test : banc N64 existant (bunker ignoré, ville/capitale liée) **doit rester vert**. Ajouter : 1 FACTORY + 1 CITY à portée → `factory.links` contient la ville, `railIncome > 0`. Deuxième `refreshRailNetwork` → mêmes liens, `not rawequal(factory.links, stationBuf)`. Slot sans gare → `railRoutes == 0`, pas d’erreur. Client 35/35. 6000 ticks.
4. Fichiers : `GameState.luau` (`refreshRailNetwork` seulement), `tests/simulate.luau` (bloc court à côté du banc N64).

**Contraintes :** pas de RemoteFunction. Recette N81 (array + truncate **avant** sort) + N64 (index slot). **N84 feel ≠ N64 (index, déjà fait) ≠ N20 (stopBonus, déjà fait) ≠ N73 (`buildingSnapBuf` live `links`) ≠ N82 (`elimBuf`, déjà fait).** `stationBuf` n’est pas réentrant. `refreshRailNetwork` est unique par mutation. Ne pas `table.clone(links)` au dirty (N73 : Overlay itère tout de suite). Capital spawn est une gare : un test « 1 FACTORY seule » peut encore lier la capitale — le banc N64 le couvre déjà (`owner.capitalTile`).

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; records stats → **N76 fait** ; `eraProgress` → **N77 fait** ; bateaux → **N70 fait** ; missiles → **N71 fait** ; owner indices → **N72 fait** ; bâtiments → **N73 fait** ; HUD fronts → **N74 fait** ; viewFor → **N78 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` alloc+closures par resolve — leftover N81) |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | ouvert |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 factions) | P1 | ouvert |
| N13 | Parité combat (ère / cost factor / constantes mortes) | P2 | ouvert |
| N14 | Apply immédiat vs lockstep (feel #19) | P1 | ouvert (produit) |
| N15 | `PREPARATION_DURATION=0` vs gardes `combatUnlocked` | P2 | ouvert |
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 | **N37+N42+N45 faits** ; path résultat → **N83 nouveau** |
| N17 | Humains éliminés occupent le cap | P2 | ouvert |
| N18 | Heap AimFront ≠ ChantierB / BoatFront | P2 | ouvert (frontier mixte mag vs TERRAIN_COST) |
| N19 | Embargo allié + tribus auto-accept | P2 | ouvert |
| N20 | `railIncome` vs `deliveryValue` | P2 | **fait** `stopBonus` ; reste niveau live vs snapshot colis |
| N21 | QuickChat 2-args | P3 | **fait** passe 5 |
| N22 | Warships O(carriers × boats) | P2 | **fait** passe 19 (**N67**) |
| N23 | `retreatAttack` premier front | P2 | **fait** passe 5 |
| N24 | notify/sfx `FireAllClients` | P2 | **fait** passe 5 |
| N25 | `MAX_BOATS_PER_PLAYER` 6 vs 3 | P3 | ouvert |
| N26 | SAM chance 0.55 vs 1.0 | P1 | **fait** Config=1.0 |
| N27 | Embargo land trade | P2 | **doc** maritime-only |
| N28 | `RequestSnapshot` mort client | P2 | ouvert (serveur rate-limite ; client n’envoie jamais) |
| N29 | Seq commitée avant apply | P3 | **fait** passe 9 |
| N30 | Stub `seedBeachhead` faux | P3 | **fait** `error(...)` |
| N31 | Scan bunkers O(B) | P1 | **fait** passe 10 (N42) |
| N32 | `viewFor` requests expirées | P3 | **fait** |
| N33 | `BOAT_LANDING_BONUS` mort | P2 | ouvert |
| N34 | `areAllied` ignore expiry pacte | P2 | **fait** passe 7 |
| N35 | `applyDefenseAura` buffer mort (posted) | P2 | **fait** posted=index ; écritures → **N45 fait** |
| N36 | AimFront figé après premier lancer | P2 | **fait** passe 8 |
| N37 | `findSeaPath` alloc 40k / appel | P2 | **fait** passe 8 (BFS) ; résultat → **N83** |
| N38 | `syncCarriers` O(B) / tick | P2 | **fait** passe 9 (dirty ; spawn → **N65 fait**) |
| N39 | `tryAnnex` alloc + BFS mort | P2 | **fait** passe 9 |
| N40 | Éliminés skip `Persistence.record` | P1 | **fait** passe 9 |
| N41 | Sequence `nil` bypass idempotence | P2 | **fait** passe 10 |
| N42 | `attackLogic` index bunkers | P1 | **fait** passe 10 |
| N43 | Transports inbound `removePlayer` (feel) | P2 | **fait** passe 11 |
| N44 | Missiles inbound vs slot recyclé | P2 | **fait** passe 11 |
| N45 | `applyDefenseAura` writes mortes | P3 | **fait** passe 11 |
| N46 | `Diplomacy.request` inverse périmée | P2 | **fait** passe 12 |
| N47 | Cadran / colis recycle feel | P2 | **fait** passe 12 |
| N48 | Convoi marchand inbound | P2 | **fait** passe 12 |
| N49 | `retreatBoats` / `targetSlot` après flip | P2 | **fait** passe 13 |
| N50 | `findSpawn` splash / fallout | P3 | **fait** passe 13 (C1+C2) |
| N51 | Convoi vs PORT détruit au combat | P3 | **fait** passe 13 |
| N52 | `claimSpawn` splash / fallout | P3 | **fait** passe 14 |
| N53 | Débarquement auto vs côte flippée | P3 | **fait** passe 14 (option A) |
| N54 | MIRV bus vs `findSpawn` | P3 | **fait** passe 14 (`spread + warheadRadius`) |
| N55 | `claimSpawn` isolation disque | P3 | **fait** passe 15 |
| N56 | Snapshot bateau `retreating` | P3 | **fait** passe 15 (option A) ; alloc → **N70 fait** |
| N57 | SAM scan O(B) / missile | P2 | **fait** passe 15 (`samsBySlot`) |
| N58 | Hover client spawn isolation | P3 | **fait** passe 16 (`SpawnHint`) |
| N59 | `samsOf` / bots scan O(B) | P2 | **fait** passe 16 (alloc → **N68 fait**) |
| N60 | `stepCooldowns` O(B) / tick nuke | P2 | **fait** passe 16 (`samsBySlot` + `silosBySlot`) |
| N61 | `Trade.step` scan FACTORY O(B) | P2 | **fait** passe 17 (`factoriesBySlot`) |
| N62 | Bots upgrade + score nuke O(B) | P2 | **fait** passe 17 (`buildingsBySlot`) ; nested 90 → **N69 fait** |
| N63 | `spawnTradeShips` O(ports²) feel | P2 | **fait** passe 17 (`portsByTile`) |
| N64 | `refreshRailNetwork` scan gares O(B) | P3 | **fait** passe 17 (`buildingsBySlot[slot]`) ; alloc → **N84** |
| N65 | `syncCarriers` spawn NAVAL_BASE O(B) dirty | P3 | **fait** passe 18 (`navalBasesBySlot`) |
| N66 | `Trade.step` alloc+sort liste usines 10 Hz | P3 | **fait** passe 18 (`factoryBuf`) |
| N67 | `stepCarriers` nested O(C × B) 10 Hz | P2 | **fait** passe 19 (`carrierBuf`/`targetBuf`) |
| N68 | `samsOf` alloc table 10 Hz bots | P3 | **fait** passe 19 (`samBuf`) |
| N69 | `blastValue` × 90 tuiles frontière | P3 | **fait** passe 20 (`fillBlastBuf`) |
| N70 | `snapshotBoats` alloc 10 Hz | P2 | **fait** passe 20 (`boatSnapBuf`) |
| N71 | `snapshotMissiles` alloc 10 Hz | P3 | **fait** passe 21 (`missileSnapBuf`) |
| N72 | `flushOwnerDelta` indices alloc | P3 | **fait** passe 21 (`dirtyIndexBuf`) |
| N73 | `flushBuildingDelta` alloc 10 Hz | P3 | **fait** passe 22 (`buildingSnapBuf`) |
| N74 | HUD fronts `replicate()` alloc 10 Hz | P3 | **fait** passe 22 (`frontHudForReplicate`) |
| N75 | `buildPrices` alloc 10 Hz × slots | P3 | **fait** passe 23 (`pricesFor`) |
| N76 | `stats[slot]` alloc 10 Hz × slots | P3 | **fait** passe 23 (`playerStatsForReplicate`) |
| N77 | `Research.progress` alloc `ratios` | P3 | **fait** passe 24 (min courant) |
| N78 | `Diplomacy.viewFor` alloc 7 tables 1 Hz | P3 | **fait** passe 24 (`viewBuf` par slot) |
| N79 | `Diplomacy.step` alloc `expired` 10 Hz | P3 | **fait** passe 25 (`expiredBuf` + pool records) |
| N80 | `Bots.neighborFactions` alloc hash contacts | P3 | **fait** passe 25 (`contactBuf`) |
| N81 | `Bots.gatherSites` alloc array / décision | P3 | **fait** cette passe (`siteBuf`, caps 40/60/45 inchangés) |
| N82 | `stepElimination` alloc `doomed` 10 Hz | P3 | **fait** cette passe (`elimBuf`, pas le doomed bâtiments de `removePlayer`) |
| N83 | `findSeaPath` path + reversed | P3 | **nouveau** (walk scratch, retour **unique** pour `boat.path`) |
| N84 | `refreshRailNetwork` stations / parent | P3 | **nouveau** (`stationBuf`, pas de pool `building.links`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 `NIGHTLY_REPORT.md` historique.

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

---

## 7. Preuve tests

`./tests/run.sh` → **exit 0**.

Serveur :

```
seed 7 / 99991 / 31337 / 1234567 : 18 factions, invariants OK
factions : 18
intentions : sequence, idempotence, apply immediat, rate limit OK
samsOf recycle : truncate, pas de fuite (N68)
blastValue : 2 villes battent une frontiere vide (N62)
blastBuf : set nil = 0, restore identique (N69)
warships empty / fire / ally / own (N67)
boatSnapBuf : 1 carrier + 1 transport, retreating, pas de path (N70)
boatSnapBuf : truncate 2→1→0 (N70)
missileSnapBuf : 1 ogive, tx/ty, pas de progress (N71)
missileSnapBuf : truncate 1→0→1 (N71)
dirtyIndexBuf : spawn>0, second nil, 1 tuile (N72)
buildingSnapBuf : CITY, second nil, destroy kind=0 (N73)
frontHud : 0 vide, 1 front slot/troupes/cible (N74)
frontHud : retraite → maps vides (N74)
pricesFor : BUILDABLE, rawequal, CITY double (N75)
playerStats : 0 front, rawequal (N76)
playerStats : 1 front activeAttacks==1 (N76)
playerStats : removePlayer → slot absent (N76)
progress : gold=0 < 1, MAX_ID=1, clamp (N77)
viewFor recycle : incoming/outgoing, expiry, rawequal, traitre (N78)
diplomacy step expired : terme, cooldown, pas TRAHI (N79)
diplomacy step expired : A–B et A–C tombent ensemble (N79)
neighborFactions : contact, rawequal, slot 99 vide (N80)
neighborFactions : removePlayer → disparu absent (N80)
gatherSites : DEFENSE frontiere, rawequal, cap 60 (N81)
gatherSites : truncate border + PORT sans cote (N81)
elimBuf : vivant length 0, rawequal (N82)
elimBuf : strip → length 1, slot disparu (N82)
elimBuf : truncate 1→0 inter-instances (N82)
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.73
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `hover spawn isolation : lisiere rouge, disque isole vert (N58)` et `identite, ere, diplomatie et classement`. Overlay `previewTile(valid=false)` ne lève pas. HUD lit `eraProgress` number (N77). HUD remplace `self.diplomacy = payload` (N78). Aucune surface client touchée cette passe.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass26.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). Les correctifs N81–N82 sont serveur / pools, pas un Play Solo.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N81 n’ajoute **pas** de require (`siteBuf` vit dans Bots, qui require déjà GameState / MapGen). N82 n’ajoute **pas** de require (`elimBuf` vit dans GameState).

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N66 : `factoryBuf` n’est pas réentrant. `Trade.step` est unique par tick. Ne pas appeler `Trade.step` depuis `dispatch` / `resolve`.

Piège N67 : `carrierBuf` / `targetBuf` ne sont pas réentrants. `stepCarriers` est unique par `Navy.step`. Dead carriers (`health <= 0`) restent dans `state.boats` (respawn) mais **hors** `carrierBuf` et hors cibles.

Piège N68 : `samBuf` n’est pas réentrant. `samsOf` n’est appelé que depuis `Bots.decideNuke` (synchrone). Un appelant concurrent doit dupliquer le buffer. Le test N59 lit le **contenu**, pas `rawequal`.

Piège N69 : `blastX/Y/Level` ne sont pas réentrants. `decideNuke` flatten une fois puis `scoreBlast` ; `Bots.blastValue` re-fill (banc unitaire). Ne pas appeler `blastValue` depuis la boucle 90. Index présent + set nil = score 0, **pas** de fallback hash.

Piège N70 : `boatSnapBuf` n’est pas réentrant et est **partagé entre toutes les instances** `GameState` (module-level). `replicate()` est unique par tick. Overlay / tests doivent lire les champs tout de suite, pas stocker l’identité de table d’un tick sur l’autre. Truncate obligatoire : Overlay itère `for _, boat in boats`.

Piège N71 : `missileSnapBuf` n’est pas réentrant et est **partagé entre toutes les instances** `GameState`. Overlay copie `tx`/`ty` dans `extra` à `applyUnits` — ne pas garder l’enregistrement du buffer. Truncate obligatoire : Overlay itère `for _, missile in missiles`. Ne **pas** répliquer `progress` : le client interpolé n’en a pas besoin.

Piège N72 : `dirtyIndexBuf` n’est pas réentrant. Un seul `flushOwnerDelta` par tick (`replicate` + banc). Le `buffer.create` outbound **doit** rester neuf — RemoteEvent. Early-out vide ne doit **pas** allouer le buffer. Ne pas itérer `dirty` deux fois.

Piège N73 : `buildingSnapBuf` n’est pas réentrant et est **partagé entre toutes les instances** `GameState`. Overlay / tests lisent `entry.index` / `kind` / `slot` / `level` / `links` tout de suite. Truncate obligatoire : Overlay itère `for _, entry in deltas`. Early-out dirty vide ne doit **pas** allouer. Ne **pas** cloner `links` : Overlay.syncFactoryRoutes itère immédiatement ; un `table.clone` casserait un test `rawequal` éventuel et allouerait. `refreshRailNetwork` ne dirty que les FACTORY dont les liens changent — poser une CITY seule flush length 1.

Piège N74 : `activeAttackBuf` / `committedTroopBuf` / `attackTargetBuf` / `attackTargetPool` ne sont pas réentrants. `playerStatsForReplicate` (N76) appelle N74 **une** fois. HUD / tests lisent les champs tout de suite. Slots sans front : **absents**, pas `{}` — N76 garde `activeAttacks[slot] or 0`. Ne pas merger beachhead et terre. Inner listes : `table.clear` au premier front du slot ce tick, puis `table.insert`.

Piège N75 : `priceBuf[slot]` / `emptyPriceBuf` ne sont pas réentrants. `replicate()` pose `rec.buildPrices = Buildings.pricesFor(...)` **après** N76, une fois par slot vivant (séquentiel : chaque slot a sa propre map). HUD client reçoit une copie désérialisée : recycle serveur OK. Slot inconnu = `emptyPriceBuf` partagé — ne pas le remplir avec `math.huge`. Ne **pas** cacher « prix inchangés » : le doublement `2^units` après pose CITY doit rester visible (le test N75 l’attrape). GameState ne doit **pas** require Buildings.

Piège N76 : `statsBuf` / `statsRecPool` ne sont pas réentrants et sont **partagés entre toutes les instances** `GameState`. `table.clear(statsBuf)` détache les records ; le pool les réécrit. Slots disparus **absents** de la porteuse (le test `removePlayer` l’attrape). `eraProgress` / `buildPrices` sont `nil` jusqu’à `init.server` — le banc N76 vérifie ce contrat ; le client ne voit que le payload déjà remplis. Ne **pas** cloner `attackTargets`. Ne pas merger `priceFor` dans ce helper (cycle).

Piège N77 : `progress` ne retourne **pas** de table — ne pas introduire un `ratiosBuf`. Le min courant **est** le goulot HUD (ne pas moyenner). `requiredBuildings` vide (ère 1 → 2 a CITY=1 ; une ère future à `{}` est légale). `count == 0` n’existe pas dans `Eras.LIST` actuel — ne pas ajouter de garde qui changerait la formule. `init.server` pose `rec.eraProgress` **après** N76 : le banc N76 continue de voir `nil`.

Piège N78 : `viewBuf[slot]` n’est **pas** un buffer global unique. Un seul `viewBuf` partagé entre slots casserait le `FireClient` précédent (la boucle humains est séquentielle, le payload n’est pas cloné avant l’envoi — RemoteEvent sérialise de façon synchrone dans le banc, mais Studio queue le même table). HUD client fait `self.diplomacy = payload` (copie wire). Tests existants appellent `viewFor` pour 3 slots puis lisent les 3 vues — d’où un record **par slot**. `table.clear` des inners, pas de nouvelle table porteuse. Slot sans joueur : maps vides, **pas** de scan `requests`/`traitors`. Ne pas cloner `marks`.

Piège N79 : `expiredBuf` / `expiredRecPool` ne sont pas réentrants. `step` est unique par tick. Truncate **après** traitement (`#` → 0) : aucun lecteur fantôme en prod, le banc N79 rappelle `step` tout de suite. Ne pas fusionner A–B et B–A en deux expirations (`a < b`). `true` legacy : **ne pas** faire `tick >= expiry` nu — en Luau le mixte number/boolean peut lever ; `typeof == "number"` est la loi `pactStillLive`. Ne pas marquer traître (ce n’est pas `breakAlliance`). Les records ne sont pas répliqués.

Piège N80 : `contactBuf` n’est pas réentrant. Les 4 appelants (`decideDiplomacy` ×2, `decideNavy`, `decideAttack`) lisent puis abandonnent avant le prochain appel — ne pas `table.clone`. Slot 99 / sans joueur = map **vide** (le test `next(buf) == nil` l’attrape), pas nil. Ne pas cacher NEUTRAL : `decideAttack` le score. Après `removePlayer`, les tuiles du disparu sont NEUTRAL : `contacts[gone] == nil`, la clé peut être `NEUTRAL_SLOT`. Ne pas itérer `buildings` / `owner` global (rester sur `ps.border`).

Piège N81 : `siteBuf` n’est pas réentrant. `decideBuild` lit puis abandonne avant le prochain bot — ne pas `table.clone`. Caps 40 (côte) / 60 (frontière) / 45 tirages (intérieur) inchangés. Pas de shuffle : l’ordre de hash `coast`/`border` est la loi. Slot / `ps.coast` vide pour PORT → `# == 0`, pas nil. Le tirage CITY **reste RNG** : ne pas tester `rawequal` de contenu sur CITY. Ne pas itérer `owner` global pour DEFENSE/PORT (rester sur `ps.border` / `ps.coast`). Truncate leftover (recette N68) : `table.clear(ps.border)` puis rappel → `# == 0`.

Piège N82 : `elimBuf` n’est pas réentrant et est **partagé entre toutes les instances** `GameState`. Truncate leftover **avant** `removePlayer`, **pas** à 0 après return (l’appelant et le banc lisent `#`). Ne pas nommer le buffer `doomed` (`removePlayer` a déjà un snapshot bâtiments). Ne pas merger beachhead/terre dans le skip offensive : n’importe quel `atk.attacker == slot` suffit. Overlay n’itère pas cette liste (retour ignoré en prod). Un leftover d’état A dans l’état B sans truncate ferait `# > 0` pour un vivant — le banc inter-instances l’attrape.
