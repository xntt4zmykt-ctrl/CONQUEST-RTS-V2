# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 23)

Déclencheur : ouverture de la **PR #65** (`cursor/analyse-nocturne-du-codebase-55ba`) — buildingSnapBuf, frontHudForReplicate, specs N75–N76.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-4876`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#66.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted (bunker / SAM / silo / usine / tous / PORT / NAVAL_BASE) ne sont pas répliqués. `priceBuf` / `emptyPriceBuf` et `statsBuf` / `statsRecPool` sont des pools module-level, pas de l’état répliqué.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #65 (passe 22) : claims vérifiés.** `buildingSnapBuf` (N73) ; `frontHudForReplicate` (N74). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #65 a documenté (N75, N76)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #65

| Claim #65 | Réalité à l’ouverture |
|---|---|
| `buildingSnapBuf` (N73) | Oui. Inner records réécrits. Truncate. `links` live. Early-out dirty vide → `nil`. Destruction `kind=0` / `links=nil`. |
| `frontHudForReplicate` (N74) | Oui. Trois maps + `attackTargetPool`. Slots sans front absents. Terre et `isBeachhead` comptés séparément. |
| Specs N75–N76 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #66 (1e60), feel jusqu’à #65, visuelles #39/#44/#47/#50/#54/#57/#61/#64. **#65 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#43←#46←#49←#52←#55←#58←#60←#63←#66) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N75–N76 du rapport #65.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `replicate()` alloue `buildPrices` 10 Hz × slots (N75) | `Buildings.luau` (`pricesFor` / `priceBuf`), `init.server.luau` (`replicate`), `tests/simulate.luau` | Recette `factoryBuf` / N66. Helper dans **Buildings** (GameState ne require pas Buildings — cycle). `table.clear` + refill `BUILDABLE` via `priceFor`. Slot inconnu → `emptyPriceBuf` vide, **pas** `math.huge`. Pas de dirty flag (counts bougent en combat). Wire `{ [kind]: number }` inchangé. |
| `replicate()` alloue `stats[slot]` 10 Hz × slots (N76) | `GameState.luau` (`playerStatsForReplicate` / `statsBuf` / `statsRecPool`), `init.server.luau` (`replicate`), `tests/simulate.luau` | Recette N74. Helper GameState (init.server hors bundle). Appelle `frontHudForReplicate` **une** fois. `eraProgress` / `buildPrices` restent `nil` dans le helper ; `init.server` les pose (`Research.progress`, `Buildings.pricesFor`). Slots sans joueur absents. `attackTargets` = liste N74, pas un clone. Pas de require Research / Buildings depuis GameState. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `Research.progress` ratios (N77), `Diplomacy.viewFor` alloc (N78).

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
                playerStatsForReplicate + pricesFor + Research.progress,
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
- **Réplication :** StateDelta (`dirtyIndexBuf` N72, HUD fronts N74 via N76, `buildPrices` N75, records stats N76) / UnitSnapshot (`retreating`, `boatSnapBuf` N70, `missileSnapBuf` N71) / BuildingDelta (`buildingSnapBuf` N73) / plunder / trade / explosions / notify&sfx déployés. `path` / `homeTile` / `progress` **non** répliqués. Playing 10 Hz ; lobby vide et ended → 1 Hz. `Research.progress` alloue encore `ratios` 10 Hz × slots (**N77**). `Diplomacy.viewFor` alloue 7 tables 1 Hz × humains (**N78**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N77–N78)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N76 = faits. N22 = **N67 fait**. N27 = doc only. N56 champ = fait ; alloc bateaux = **N70 fait**. Alloc missiles = **N71 fait**. Owner indices = **N72 fait**. Bâtiments = **N73 fait**. HUD fronts = **N74 fait**. Prix = **N75 fait**. Records stats = **N76 fait**.

---

### ISSUE-N77 — `Research.progress` alloue `ratios` 10 Hz × slots (feel)

**Priorité :** P3 alloc HUD ère. Leftover explicite de N76. Distinct de N75 (`buildPrices`) et de N76 (records stats, déjà faits). Ne pas toucher `eraCost` / `canAdvance` / `advance`.

**Problème :** `Research.progress` construit `local ratios = { gold/cost, tiles/requiredTiles }` puis `table.insert` pour chaque `requiredBuildings`, puis boucle pour le min. Appelé **chaque tick, chaque slot vivant** depuis `init.server` `replicate()` (10 Hz playing × jusqu’à 18 Classique). Le retour est un `number` 0..1 (`math.clamp`) ; le HUD lit `eraProgress`, pas une table. L’alloc courte n’a aucune raison d’exister.

**Pourquoi 20K CCU :** 10 Hz × 18 tables de 3–4 nombres, empilé sur le hot path de `replicate()` déjà allégé par N75–N76. Pas d’autorité (dérivé de gold / tiles / `buildingCounts`). Un min courant sans table élimine l’alloc.

**Worker :**

1. Réécrire `Research.progress` : min courant, **sans** table `ratios` et **sans** `table.insert`. Même formule : `gold/cost` (1 si `cost==0`), `tiles/requiredTiles` (1 si required==0), puis chaque `buildingCounts[kind]/count`. `math.clamp(lowest, 0, 1)`. `era >= Eras.MAX_ID` → `1` inchangé. Slot inconnu → `1` inchangé. Pas de RemoteFunction. Pas de buffer module-level (inutile : on ne retourne pas la table).
2. Ne pas modifier `init.server` (l’appel `rec.eraProgress = Research.progress(...)` reste). Ne pas toucher N75/N76. Ne pas require de module nouveau.
3. Test : `addPlayer` ère 1, gold=0 → `progress` dans `[0, 1]`, **< 1** (le critère or bloque). `ps.era = Eras.MAX_ID` → `1`. Gold énorme + tiles/bâtiments déjà là (spawn capitale) : ne **pas** exiger `1` si `requiredBuildings` de l’ère suivante n’est pas rempli — seulement `clamp` et pas de NaN. Client 35/35. 6000 ticks.
4. Fichiers : `Research.luau` (`progress` seulement), `tests/simulate.luau` (bloc court, recette N75).

**Contraintes :** pas de RemoteFunction. **N77 feel ≠ N76 (records, déjà fait) ≠ N75 (prix, déjà fait) ≠ N2 skip-si-inchangé.** Ne pas cacher le min (le HUD barre affiche le goulot). Ne pas allouer un `ratiosBuf` « au cas où ». `Research` require déjà `GameState` : rester dans ce module.

---

### ISSUE-N78 — `Diplomacy.viewFor` alloue 7 tables 1 Hz × humains (feel)

**Priorité :** P3 alloc vue diplomatique. Distinct de N32 (expiry HUD, déjà fait) et de N76 (stats StateDelta). `viewFor` est déjà 1 Hz (`tick % TICK_RATE == 0`) et **FireClient** par humain, pas FireAllClients.

**Problème :** `Diplomacy.viewFor` alloue `allies`, `incoming`, `outgoing`, `embargoes`, `traitors`, `marks` **et** la table porteuse, à chaque appel. `init.server` l’appelle une fois par humain connecté, 1 Hz. Les maps sont petites (≤ 17 autres slots) mais nouvelles à chaque seconde. Le client remplace `diplomacy = payload` ; HUD / radial lisent les champs, pas `rawequal`. `areAllied` filtre déjà l’expiry (N32/N34).

**Pourquoi 20K CCU :** 1 Hz × 8 humains × 7 tables, plus le scan `state.requests` (toutes les paires) pour `incoming`. Recycle des 6 maps + de la porteuse par slot élimine l’alloc courte. Pas d’autorité (vue dérivée). Ne pas passer en 10 Hz.

**Worker :**

1. Ajouter `viewBuf[slot]` module-level (créer si nil) : un record `{ allies, incoming, outgoing, embargoes, traitors, marks }` dont les 6 inners sont des maps persistantes. Au début de `viewFor` : `table.clear` des 6 maps, réécrire le record (identité stable), refill comme aujourd’hui (`areAllied` pour allies, `typeof(expiry)=="number" and tick < expiry` pour requests, embargoes du slot, `traitorUntil > tick`, marks = moi + alliés). Slot sans joueur → record recyclé aux maps **vides** (pas d’erreur). Pas de RemoteFunction. Ne **pas** changer `areAllied` / `request` / `accept`.
2. `init.server` : `Diplomacy.viewFor(state, slot)` inchangé. Garder 1 Hz et `FireClient` (pas FireAllClients — la vue est par joueur). Ne pas toucher N75/N76/`replicate` stats.
3. Test : 2 joueurs, `Diplomacy.request(a, b)` vivant → `viewFor(b).incoming[a]==true`, `viewFor(a).outgoing[b]==true`. Forcer expiry (`requests[a][b] = state.tick`) → incoming/outgoing absents. Second appel immédiat → `rawequal` la porteuse **et** `rawequal(view.allies, previousAllies)`. Traître : `ps.traitorUntil = state.tick+10` → `traitors[slot]==true`. Client 35/35. 6000 ticks.
4. Fichiers : `Diplomacy.luau` (`viewFor`), `tests/simulate.luau` (bloc court ; des tests expiry existent déjà — ne pas les casser, ajouter `rawequal`).

**Contraintes :** pas de RemoteFunction. Recette N75 (`priceBuf[slot]` + clear). **N78 feel ≠ N32 (filtre expiry, déjà fait) ≠ N76 (stats 10 Hz) ≠ N2 skip-si-inchangé.** Les maps ne sont pas réentrantes — un seul `viewFor` à la fois par tick (boucle humains séquentielle : **un** `viewBuf` partagé entre slots **casse** le FireClient précédent si on clear trop tôt). Donc **un record par slot**, pas un buffer global unique. HUD / tests lisent les champs tout de suite. Ne pas cloner `marks` côté client.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; records stats → **N76 fait** ; bateaux → **N70 fait** ; missiles → **N71 fait** ; owner indices → **N72 fait** ; bâtiments → **N73 fait** ; HUD fronts → **N74 fait** ; reste skip-si-inchangé) |
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
| N71 | `snapshotMissiles` alloc 10 Hz | P2 | **fait** passe 21 (`missileSnapBuf`) |
| N72 | `flushOwnerDelta` indices alloc | P3 | **fait** passe 21 (`dirtyIndexBuf`) |
| N73 | `flushBuildingDelta` alloc 10 Hz | P3 | **fait** passe 22 (`buildingSnapBuf`) |
| N74 | HUD fronts `replicate()` alloc 10 Hz | P3 | **fait** passe 22 (`frontHudForReplicate`) |
| N75 | `buildPrices` alloc 10 Hz × slots | P3 | **fait** cette passe (`pricesFor`) |
| N76 | `stats[slot]` alloc 10 Hz × slots | P3 | **fait** cette passe (`playerStatsForReplicate`) |
| N77 | `Research.progress` alloc `ratios` | P3 | **nouveau** (min courant, pas de table) |
| N78 | `Diplomacy.viewFor` alloc 7 tables 1 Hz | P3 | **nouveau** (record par slot, pas un buf global) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 `NIGHTLY_REPORT.md` historique.

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
removePlayer index : snapshot buildingsBySlot, rien ne reste
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=7.6 p95Changed=8 maxChanged=479 avgTickMs=0.38 p95TickMs=0.90
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `hover spawn isolation : lisiere rouge, disque isole vert (N58)` et `navires, missiles et interpolation`. Overlay `previewTile(valid=false)` ne lève pas. HUD lit `buildPrices[id]` (N75, copie désérialisée). HUD lit `activeAttacks` / `committedTroops` (N74/N76).

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass23.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). Les correctifs N75–N76 sont serveur / pools, pas un Play Solo.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N75 n’ajoute **pas** de `require` croisé (`pricesFor` vit dans Buildings, qui require déjà GameState). N76 n’ajoute **pas** de require Buildings/Research depuis GameState (`eraProgress` / `buildPrices` posés dans `init.server`).

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

Piège N76 : `statsBuf` / `statsRecPool` ne sont pas réentrants et sont **partagés entre toutes les instances** `GameState`. `table.clear(statsBuf)` détache les records ; le pool les réécrit. Slots disparus **absents** de la porteuse (le test `removePlayer` l’attrape). `eraProgress` / `buildPrices` sont `nil` jusqu’à `init.server` — le banc N76 vérifie ce contrat ; le client ne voit que le payload déjà rempli. Ne **pas** cloner `attackTargets`. Ne pas merger `priceFor` dans ce helper (cycle).
