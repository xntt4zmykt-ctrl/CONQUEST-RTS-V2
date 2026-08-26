# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 21)

Déclencheur : ouverture de la **PR #59** (`cursor/analyse-nocturne-du-codebase-5bf6`) — blastBuf, boatSnapBuf, specs N71–N72.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-741d`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#59.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted (bunker / SAM / silo / usine / tous / PORT / NAVAL_BASE) ne sont pas répliqués. `missileSnapBuf` et `dirtyIndexBuf` sont des pools module-level, pas de l’état répliqué.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #59 (passe 20) : claims vérifiés.** `fillBlastBuf`/`scoreBlast` (N69) ; `boatSnapBuf` truncate (N70). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #59 a documenté (N71, N72)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #59

| Claim #59 | Réalité à l’ouverture |
|---|---|
| `fillBlastBuf` / `scoreBlast` (N69) | Oui. Index présent + set nil = score 0. SAM shield inchangé. |
| `boatSnapBuf` (N70) | Oui. Inner records réécrits. Truncate 2→1→0. Pas de `path` / `homeTile`. |
| Specs N71–N72 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #58, feel jusqu’à #59, plus #39/#44/#47/#50/#54/#57 visuelles. **#59 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#43←#46←#49←#52←#55←#58) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N71–N72 du rapport #59.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `replicate()` alloue table missiles + N payloads / tick (N71) | `GameState.luau` (`snapshotMissiles` / `missileSnapBuf`), `init.server.luau` (`replicate`), `tests/simulate.luau` | Recette `boatSnapBuf` / N70. Inner records réécrits, pas recréés. Truncate 1→0→1. Champs **uniquement** `Types.MissileSnapshot` (`id, slot, x, y, tx, ty, kind`). Pas de `sx` / `sy` / `progress` / `speed`. Overlay lit `tx`/`ty`, pas l’identité de table. Helper dans `GameState` car `init.server` est hors bundle. |
| `flushOwnerDelta` alloue `indices` chaque tick (N72) | `GameState.luau` (`dirtyIndexBuf`), `tests/simulate.luau` | Recette `factoryBuf` / N66. Early-out `next(dirty)==nil` → `nil` sans allouer. `buffer.create` outbound **neuf** (RemoteEvent). Format 5 octets / tuile inchangé. `buildPrices` → N2. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `flushBuildingDelta` (N73), maps HUD fronts (N74).

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
              → Diplomacy.step → GameState.step → replicate(
                flushOwnerDelta via dirtyIndexBuf,
                fireDeployed, snapshotBoats, snapshotMissiles)
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
- **Réplication :** StateDelta (`dirtyIndexBuf` N72) / UnitSnapshot (`retreating`, `boatSnapBuf` N70, `missileSnapBuf` N71) / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. `path` / `homeTile` / `progress` **non** répliqués. Playing 10 Hz ; lobby vide et ended → 1 Hz. `flushBuildingDelta` alloue encore `out` + N payloads (**N73**). `replicate()` alloue encore `activeAttacks` / `committedTroops` / `attackTargets` (**N74**) et `buildPrices` 10 Hz × slots (**N2**).

---

## 5. Issues worker-ready (nouveaux, N73–N74)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N72 = faits. N22 = **N67 fait**. N27 = doc only. N56 champ = fait ; alloc bateaux = **N70 fait**. Alloc missiles = **N71 fait**. Owner indices = **N72 fait**.

---

### ISSUE-N73 — `flushBuildingDelta` alloue `out` + N payloads chaque tick (feel)

**Priorité :** P3 alloc réplication. Suite de N72 (owner indices) **sans** toucher `dirtyIndexBuf` ni le format BuildingDelta. Distinct de N2 (`stats` / `buildPrices`), de N70/N71 (UnitSnapshot) et de N72 (owner 5 octets).

**Problème :** `GameState.flushBuildingDelta` fait `local out = {}` puis `table.insert` d’un **nouvel** enregistrement `{index, kind, slot, level, links}` pour chaque tuile `buildingDirty`, **chaque tick** — y compris le banc 6000 ticks qui flush pour ne pas fuiter. Si `buildingDirty` est vide, `out` est quand même alloué puis jeté (`return nil`). `links` est aujourd’hui la **table live** de l’usine (pas une copie) : Overlay / `applyBuildingDelta` lit `entry.index` / `kind` / `slot` / `level` / `links` tout de suite, pas l’identité de `out`. Le client ne reçoit le delta que si `buildings` est truthy (`init.server` : `if buildings then fireDeployed`).

**Pourquoi 20K CCU :** 10 Hz × shards, empilé avec N70–N72 déjà recyclés. Pas d’autorité (delta dérivé de `buildings` / `buildingDirty`). Un `table.create(16)` recyclé + truncate + early-out vide élimine l’alloc courte du hot path sans changer le wire `{index, kind, slot, level, links}`.

**Worker :**

1. `buildingSnapBuf = table.create(16)` module-level dans `GameState.luau` (à côté de `dirtyIndexBuf`). Early-out `next(self.buildingDirty) == nil` → `table.clear(self.buildingDirty)` + return nil **sans** allouer. Remplir par index (`n += 1`), recycle inner records (créer seulement si `buildingSnapBuf[n] == nil`, sinon réécrire les champs). Truncate `#buildingSnapBuf`. Champs **identiques** à aujourd’hui : `index, kind, slot, level, links`. Destruction (`buildings[index] == nil`) : `kind=0`, `slot=0`, `level=0`, `links=nil`. **`links` reste la référence live** (ne pas `table.clone` — extra alloc). Return `buildingSnapBuf` si `n > 0`, sinon nil.
2. `init.server` `replicate()` : ne pas changer l’appel `state:flushBuildingDelta()` ni le `if buildings then`. Ne pas toucher N72 `dirtyIndexBuf`. Ne pas toucher N2 `buildPrices`. Ne pas toucher N70/N71. Pas de RemoteFunction.
3. Test : `placeBuilding` CITY → `flushBuildingDelta` length 1, `kind` / `slot` / `index` honorés. Second flush immédiat → `nil`. `destroyBuilding` → length 1, `kind==0`, `links==nil`. 6000 ticks (le run principal flush déjà chaque tick). Client 35/35 (`applyBuildingDelta` lit les champs).
4. Fichiers : `GameState.luau` (`flushBuildingDelta`), `tests/simulate.luau` (bloc court, recette N72).

**Contraintes :** pas de RemoteFunction. Recette `missileSnapBuf` / N71, **pas** un dirty flag supplémentaire. **N73 feel ≠ N72 (owner indices, déjà fait) ≠ N2 (stats) ≠ N70/N71 (unités) ≠ visual V14 (autre ligne).** `buildingSnapBuf` n’est pas réentrant — un seul `flushBuildingDelta` par tick. Overlay / tests doivent lire les champs tout de suite. Ne **pas** copier `links` : le contrat actuel est la référence ; une copie changerait l’identité vue par un test qui comparerait `rawequal`.

---

### ISSUE-N74 — `replicate()` alloue `activeAttacks` / `committedTroops` / `attackTargets` chaque tick (feel)

**Priorité :** P3 alloc réplication HUD. Précision de N2 (StateDelta) **sans** toucher `stats[slot]` ni `buildPrices` (reste N2). Distinct de N73 (BuildingDelta) et de N70–N72 (déjà faits). `init.server` est hors bundle : extraire un helper `GameState` testable, comme N71.

**Problème :** `init.server` `replicate()` fait `local activeAttacks = {}` / `committedTroops = {}` / `attackTargets = {}` puis, pour chaque front, `table.insert` d’une **nouvelle** liste de cibles, **chaque tick** (10 Hz playing) — même à 0 front (trois tables vides jetées). Le HUD lit `activeAttacks`, `committedTroops`, `attackTargets` pour le curseur d’engagement ; ce n’est pas de l’autorité (dérivé de `state.attacks`). `attackTargets[slot]` est `nil` si le camp n’a aucun front (pas `{}`). Le banc 6000 ticks n’exerce pas `replicate()` (`init.server` hors bundle) : sans helper `GameState`, le recycle n’est pas testable.

**Pourquoi 20K CCU :** 10 Hz × 8 humains × 18 slots Classique, empilé avec `buildPrices` encore chaud (N2). 0–quelques fronts / camp d’habitude, mais l’alloc courte des trois maps est payée même idle. Pas d’autorité.

**Worker :**

1. Ajouter `GameState.frontHudForReplicate` (nom libre, un seul helper) calqué sur N71 : trois maps module-level `activeAttackBuf` / `committedTroopBuf` / `attackTargetBuf`. `table.clear` les trois au début de l’appel (pas de nouvelle table). Pour chaque `state.attacks` : incrémenter compteurs ; inner liste de cibles = `attackTargetPool[attacker]` recyclé (`table.clear` puis `table.insert` / index). Slots sans front : **absents** des trois maps (`nil`, pas `{}`) — `replicate()` garde `activeAttacks[slot] or 0` et `attackTargets[slot]` nil. Ne **pas** allouer de `stats` / `buildPrices` ici.
2. `init.server` `replicate()` : `local activeAttacks, committedTroops, attackTargets = state:frontHudForReplicate()` à la place des trois `local … = {}` + boucle. Le reste de `stats[slot] = { … }` **inchangé** (N2). Pas de RemoteFunction.
3. Test : 0 front → les trois maps vides (`next(...) == nil`). `launchAttack` 1 front → `activeAttacks[slot]==1`, `committedTroops[slot]` = floor(troupes), `attackTargets[slot]` length 1 égal à `atk.target`. `retreatAttack` jusqu’à disparition du front → maps vides à nouveau (pas de fuite de slot). Client 35/35 (HUD lit les champs, pas `rawequal` des maps). 6000 ticks.
4. Fichiers : `GameState.luau` (`frontHudForReplicate`), `init.server.luau` (`replicate`), `tests/simulate.luau` (nouveau bloc N74).

**Contraintes :** pas de RemoteFunction. Recette N71 (helper `GameState` + pools module-level), **pas** un dirty flag (les troupes commises bougent chaque tick). **N74 feel ≠ N2 (stats/buildPrices, ouvert) ≠ N73 (bâtiments) ≠ N22/N67 (warships, déjà fait).** Les trois maps ne sont pas réentrantes — `replicate()` est unique par tick. HUD / tests lisent les champs tout de suite. Ne pas merger un beachhead et un front terre dans le décompte : itérer `state.attacks` comme aujourd’hui (chaque tas compte).

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` reconstruit 10 Hz × slots ; bateaux → **N70 fait** ; missiles → **N71 fait** ; owner indices → **N72 fait** ; bâtiments → **N73** ; HUD fronts → **N74**) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert |
| N10 | Divers P3 | P3 | ouvert |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | ouvert |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 factions) | P1 | ouvert |
| N13 | Parité combat (ère / cost factor / constantes mortes) | P2 | ouvert |
| N14 | Apply immédiat vs lockstep (feel #19) | P1 | ouvert (produit) |
| N15 | `PREPARATION_DURATION=0` vs gardes `combatUnlocked` | P2 | ouvert |
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 | **N37+N42+N45 faits** |
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
| N37 | `findSeaPath` alloc 40k / appel | P2 | **fait** passe 8 |
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
| N64 | `refreshRailNetwork` scan gares O(B) | P3 | **fait** passe 17 (`buildingsBySlot[slot]`) |
| N65 | `syncCarriers` spawn NAVAL_BASE O(B) dirty | P3 | **fait** passe 18 (`navalBasesBySlot`) |
| N66 | `Trade.step` alloc+sort liste usines 10 Hz | P3 | **fait** passe 18 (`factoryBuf`) |
| N67 | `stepCarriers` nested O(C × B) 10 Hz | P2 | **fait** passe 19 (`carrierBuf`/`targetBuf`) |
| N68 | `samsOf` alloc table 10 Hz bots | P3 | **fait** passe 19 (`samBuf`) |
| N69 | `blastValue` × 90 tuiles frontière | P3 | **fait** passe 20 (`fillBlastBuf`) |
| N70 | `snapshotBoats` alloc 10 Hz | P2 | **fait** passe 20 (`boatSnapBuf`) |
| N71 | `snapshotMissiles` alloc 10 Hz | P2 | **fait** cette passe (`missileSnapBuf`) |
| N72 | `flushOwnerDelta` indices alloc | P3 | **fait** cette passe (`dirtyIndexBuf`) |
| N73 | `flushBuildingDelta` alloc 10 Hz | P3 | **nouveau** (BuildingDelta, pas owner) |
| N74 | HUD fronts `replicate()` alloc 10 Hz | P3 | **nouveau** (précision N2, pas `buildPrices`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 `NIGHTLY_REPORT.md` historique.

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
removePlayer index : snapshot buildingsBySlot, rien ne reste
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=7.6 p95Changed=8 maxChanged=479 avgTickMs=0.38 p95TickMs=0.90
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `hover spawn isolation : lisiere rouge, disque isole vert (N58)` et `navires, missiles et interpolation`. Overlay `previewTile(valid=false)` ne lève pas.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass21.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). Les correctifs N71–N72 sont serveur / pools, pas un Play Solo.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N71–N72 n’ajoutent **pas** de remote ni de `require` croisé (`snapshotMissiles` ne require pas Nukes ; `dirtyIndexBuf` ne require pas Overlay).

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
