# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 28)

Déclencheur : ouverture de la **PR #82** (`cursor/analyse-nocturne-du-codebase-69f4`) — pathWalkBuf, stationBuf, specs N85–N86.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-07c6`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#82.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. `ctxBuf` / `doomedBuf` / `collapsingBuf` sont des pools module-level, pas de l’état répliqué. Le tableau rendu par `findSeaPath` et `building.links` restent **uniques**. `ctxBuf` n’est pas le ctx client (`PlacementPreview`).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #82 (passe 27) : claims vérifiés.** `Navy.findSeaPath` recycle `pathWalkBuf` (N83, retour unique) ; `GameState.refreshRailNetwork` recycle `stationBuf` (N84, truncate avant sort). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #82 a documenté (N85, N86)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #82

| Claim #82 | Réalité à l’ouverture |
|---|---|
| `pathWalkBuf` (N83) | Oui. Walk scratch, copie inverse dans un tableau neuf. `not rawequal`. `p1[i]` intact. Pas `return pathWalkBuf`. |
| `stationBuf` (N84) | Oui. Truncate leftover **avant** `table.sort`. `railParentBuf` / `railXsBuf` / `railYsBuf` / maps de grappe. Inners `neighborsOf` uniques (`building.links`). Slot 99 → pas d’erreur. |
| Specs N85–N86 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #80 (bef6), feel jusqu’à #82, visuelles #39/#44/#47/#50/#54/#57/#61/#64/#67/#69/#72/#74/#77/#79/#81. **#82 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#76←#80) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N85–N86 du rapport #82.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `Buildings.contextFor` alloue table + 2 closures par resolve (N85) | `Buildings.luau` (`contextFor` + helpers module, `resolve` inchangé à l’appel), `tests/simulate.luau` | Leftover N81 (sites déjà). Record `ctxBuf` + `ctxOwnerAt`/`ctxBuildingAt` module. Slot 99 → `nil` sans muter. Deux appels → `rawequal`. Après A puis B, un `ownerAt` conservé lit B. Même `buffer.readu8(state.owner)` / `state.buildings[index]`. Pas le ctx client. |
| `ChantierB.cancelOpposingFronts` / `collapsing` allouent 10 Hz (N86) | `ChantierB.luau` (`cancelOpposingFronts` + wrap `stepAttacks` seulement), `tests/simulate.luau` | Leftover combat vivant. `doomedBuf` hash + `table.clear`. `collapsingBuf` + `collapseRecPool`. Truncate leftover **avant** traitement. Clash égal → fronts nuls, leftover 0. Défenseur sous seuil → `collapseFaction` (butin + captor). `origStepAttacks` ignoré. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `BoatFront.parked` (N87), `collapseFaction` remaining/leftovers (N88), pool `building.links`, ctx client `PlacementPreview`.

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
    cancelOpposingFronts via doomedBuf, collapsingBuf 10 Hz), BoatFront, AimFront,
    tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`. Stub = `error(...)`. Deux débarquements du même couple = **deux** tas (N5 ouvert ; hardening N29). `parked` encore alloué par lancer (**N87**).
- **`areAllied`** = deux directions **et** `tick < expiry` (`true` legacy tests reste vivant).
- **AimFront wrap** = re-visée du front terre du couple ; jamais `isBeachhead`.
- **`tryAnnex`** = BFS depuis les voisins défenseur du seed déjà capturé ; océan abort ; pool N37-like.
- **Carriers** = spawn/despawn/slot sur dirty NAVAL_BASE, spawn via `navalBasesBySlot` (N65). Ciblage obus = `carrierBuf`/`targetBuf` recyclés **(N67)**. Pas de spatial hash.
- **Posted bunker** = index `bunkersBySlot`. **Posted SAM** = `samsBySlot`. **Posted SILO** = `silosBySlot`. **Posted FACTORY** = `factoriesBySlot`. **Tous** = `buildingsBySlot`. **PORT** = `portsByTile`. **Posted NAVAL_BASE** = `navalBasesBySlot`.
- **`samsOf`** = lit `samsBySlot` dans `samBuf` recyclé (N68). `tryIntercept` lit l’index directement (N57).
- **Score nuke bots** = flatten `buildingsBySlot` une fois (N69), puis 90 `scoreBlast`.
- **Inbound `removePlayer`** = snapshot `buildingsBySlot` → destroy → diplo + transports `kind==1` (100 %, lit **`owner[targetTile]`**) + missiles contrat B + cadran/colis + convois `kind==2` (coulés), **avant** `setOwner`.
- **Hover spawn** = `SpawnHint` (Shared) si `tiles==0`. Serveur = `claimSpawn` (N52+N55).
- **Réplication :** StateDelta (`dirtyIndexBuf` N72, HUD fronts N74 via N76, `buildPrices` N75, records stats N76, `eraProgress` N77) / UnitSnapshot (`retreating`, `boatSnapBuf` N70, `missileSnapBuf` N71) / BuildingDelta (`buildingSnapBuf` N73) / plunder / trade / explosions / notify&sfx déployés / Diplomacy.viewFor 1 Hz (N78). `path` / `homeTile` / `progress` **non** répliqués. Playing 10 Hz ; lobby vide et ended → 1 Hz. `Diplomacy.step` recycle `expiredBuf` (**N79**). `Bots.neighborFactions` recycle `contactBuf` (**N80**). `gatherSites` recycle `siteBuf` (**N81**). `stepElimination` recycle `elimBuf` (**N82**). `findSeaPath` walk scratch, retour unique (**N83**). `refreshRailNetwork` porteuses recyclées (**N84**). `Buildings.contextFor` recycle `ctxBuf` (**N85**). `ChantierB.cancelOpposingFronts` / wrap `stepAttacks` recyclent `doomedBuf` / `collapsingBuf` (**N86**). `BoatFront.parked` alloue encore par lancer (**N87**). `collapseFaction` alloue encore `remaining` / `leftovers` (**N88**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N87–N88)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N86 = faits. N22 = **N67 fait**. N27 = doc only.

---

### ISSUE-N87 — `BoatFront.launchAttack` alloue `parked` par lancer (feel)

**Priorité :** P3 alloc marine. Leftover explicite de N86 (`Ne pas toucher BoatFront parked`) et de N5 (beachheads hors cap). Distinct de N86 (`collapsingBuf` 10 Hz combat) et de N23 (`retreatAttack` couple). Ne pas toucher `seedBeachhead` (contrat frontier = voisins encore à la cible) ni AimFront (re-visée terre).

**Problème :** chaque `launchAttack` wrap fait `local parked = {}` puis `table.insert(parked, atk)` pour chaque `isBeachhead`, retire, appelle `origLaunch`, réinsère. Une allocation porteuse par clic / décision bot, même à 0 tête de pont. La loi (garer `isBeachhead` seulement, jamais merger deux ponts, jamais fusionner pont+terre) ne change pas.

**Pourquoi 20K CCU :** leftover N5. Un shard 8 humains + 16 bots relance des fronts plusieurs fois par seconde en mid-game. Recycle de la porteuse élimine l’alloc courte du wrap. Pas d’autorité (mêmes `table.remove` / `table.insert` arrière, même `origLaunch`). Ne pas fusionner avec `collapsingBuf` : parked est une liste d’Attack live, pas des records victim/captor.

**Worker :**

1. Ajouter `parkedBuf: { any } = table.create(8)` module-level dans `BoatFront.luau`. Au début du wrap `launchAttack` : n = 0. Si `atk.isBeachhead` : n += 1 ; `parkedBuf[n] = atk` ; `table.remove(self.attacks, i)`. Truncate leftover n+1..# **avant** `origLaunch` (un leftover non truncaté réinsèrerait un pont fantôme d’un lancer précédent). Après `origLaunch` : réinsérer `1..n` (pas `#` sans truncate). Pas de RemoteFunction.
2. Ne pas modifier `seedBeachhead` / `enqueueFront` / `isBeachhead` critère. Ne pas merger deux ponts du même couple. Ne pas toucher AimFront / ChantierB / `MAX_ACTIVE_ATTACKS_PER_PLAYER`. Ne pas require de module nouveau. `origLaunch` reste le corps terre.
3. Test : 0 pont + `launchAttack` terre → `#attacks == 1`, pas d’erreur, second lancer 0 pont OK. 2 `seedBeachhead` du même couple + `launchAttack` terre → 2 ponts **plus** 1 front terre (3 Attack), troupes de pont intactes. Deux wrap sans pont → pas d’erreur. Client 35/35. 6000 ticks.
4. Fichiers : `BoatFront.luau` (wrap `launchAttack` seulement), `tests/simulate.luau` (bloc court à côté du banc « beachhead merge » / aim beachhead).

**Contraintes :** pas de RemoteFunction. Recette N86 (`collapsingBuf` + truncate avant traitement). **N87 feel ≠ N86 (`collapsingBuf`, déjà fait) ≠ N5 (cap beachhead, ouvert) ≠ N23 (`retreatAttack`, déjà fait).** `parkedBuf` n’est pas réentrant. `launchAttack` est synchrone. Ne pas `table.clone` des Attack. Les Attack parkés sont les **mêmes** objets (identité), pas des copies. Overlay n’itère pas cette liste.

---

### ISSUE-N88 — `GameState.collapseFaction` alloue `remaining` / `leftovers` (feel)

**Priorité :** P3 alloc collapse. Leftover explicite de N86 (le wrap recycle la **liste** victim/captor, pas le balayage tuiles). Distinct de N86 (`collapsingBuf`) et de N82 (`elimBuf` slots). Ne pas toucher le corps mort `GameState.stepAttacks` (`local collapsing = {}` ignoré : `local _ = origStepAttacks`).

**Problème :** chaque `collapseFaction` fait `local remaining = {}` (scan `TILE_COUNT`), puis jusqu’à `COLLAPSE_MAX_PASSES` (24) `local leftovers = {}` + `table.insert`. Deux allocations porteuses + N inserts par absorption. `collapseScratch = table.create(4, 0)` est aussi alloué **par appel**. La loi (butin avant démantèlement, héritier captor prioritaire, île → NEUTRAL, `CONQUEST_PLUNDER_*`) ne change pas.

**Pourquoi 20K CCU :** leftover N86. Un shard 18 slots absorbe plusieurs factions en late. Recycle des porteuses élimine l’alloc du balayage. Pas d’autorité (même scan, mêmes `setOwner`, même plunder). Ne pas fusionner avec `elimBuf` : collapse redistribue le territoire, `removePlayer` vient après via `stepElimination`. Ne pas fusionner avec `doomedBuf` (indices d’Attack).

**Worker :**

1. Ajouter `collapseRemainBuf: { number } = table.create(64)`, `collapseLeftBuf: { number } = table.create(64)`, `collapseScratch = table.create(4, 0)` module-level dans `GameState.luau`. `collapseFaction` : n = 0 ; scan `TILE_COUNT` → `collapseRemainBuf[n] = index`. Truncate leftover **avant** plunder (`# == 0` → return, comme aujourd’hui). Chaque passe : nLeft = 0 ; écrire `collapseLeftBuf` ; truncate leftover **avant** de swapper (échanger les deux buf, n = nLeft) ; break si n == 0 ou `not progressed`. Itérer `1..n`, pas `#` sans truncate. Pas de RemoteFunction.
2. Ne pas modifier `COLLAPSE_MAX_PASSES` / `COLLAPSE_MIN_TILES` / plunder / notify. Ne pas câbler `MAX_TILES_PER_TICK`. Ne pas require de module nouveau. Ne pas toucher `ChantierB` wrap (N86 déjà). Ne pas pooler `self.plunders` (payload répliqué). `where = remaining[1]` devient `collapseRemainBuf[1]` **avant** le premier swap.
3. Test : banc collapse existant (butin bot, territoire captor) **doit rester vert**. Banc N86 collapse recycle **doit rester vert**. Ajouter : `collapseFaction` sur un slot sans tuile → return, pas d’erreur, plunder inchangé. Deux appels (victime déjà à 0 puis autre victime) → pas de leftover de tuiles de A dans B. Client 35/35. 6000 ticks.
4. Fichiers : `GameState.luau` (`collapseFaction` seulement), `tests/simulate.luau` (bloc court à côté du banc « effondrement » / N86 collapse).

**Contraintes :** pas de RemoteFunction. Recette N82 (`elimBuf` truncate leftover avant traitement). **N88 feel ≠ N86 (`collapsingBuf`, déjà fait) ≠ N82 (`elimBuf`, déjà fait) ≠ N8 (combat mort vs vivant, ouvert).** Les buf ne sont pas réentrants. `collapseFaction` est unique par tick (collecte N86 close avant). Un leftover d’état A dans l’état B sans truncate ferait `setOwner` d’une tuile fantôme — truncate obligatoire. Ne pas itérer `#` sur un buf non truncaté.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; records stats → **N76 fait** ; `eraProgress` → **N77 fait** ; bateaux → **N70 fait** ; missiles → **N71 fait** ; owner indices → **N72 fait** ; bâtiments → **N73 fait** ; HUD fronts → **N74 fait** ; viewFor → **N78 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 nouveau**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; `ChantierB` doomed/collapsing → **N86 fait**) |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | ouvert |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 factions) | P1 | ouvert |
| N13 | Parité combat (ère / cost factor / constantes mortes) | P2 | ouvert |
| N14 | Apply immédiat vs lockstep (feel #19) | P1 | ouvert (produit) |
| N15 | `PREPARATION_DURATION=0` vs gardes `combatUnlocked` | P2 | ouvert |
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 | **N37+N42+N45 faits** ; path résultat → **N83 fait** |
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
| N37 | `findSeaPath` alloc 40k / appel | P2 | **fait** passe 8 (BFS) ; résultat → **N83 fait** |
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
| N64 | `refreshRailNetwork` scan gares O(B) | P3 | **fait** passe 17 (`buildingsBySlot[slot]`) ; alloc → **N84 fait** |
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
| N81 | `Bots.gatherSites` alloc array / décision | P3 | **fait** passe 26 (`siteBuf`, caps 40/60/45 inchangés) |
| N82 | `stepElimination` alloc `doomed` 10 Hz | P3 | **fait** passe 26 (`elimBuf`, pas le doomed bâtiments de `removePlayer`) |
| N83 | `findSeaPath` path + reversed | P3 | **fait** passe 27 (`pathWalkBuf`, retour **unique** pour `boat.path`) |
| N84 | `refreshRailNetwork` stations / parent | P3 | **fait** passe 27 (`stationBuf`, pas de pool `building.links`) |
| N85 | `Buildings.contextFor` table + closures | P3 | **fait** cette passe (`ctxBuf` + closures module, pas le ctx client) |
| N86 | `ChantierB` doomed / collapsing 10 Hz | P3 | **fait** cette passe (`doomedBuf` hash + `collapsingBuf` pool records) |
| N87 | `BoatFront.parked` par lancer | P3 | **nouveau** (`parkedBuf`, truncate avant origLaunch) |
| N88 | `collapseFaction` remaining / leftovers | P3 | **nouveau** (porteuses tuiles, pas collapsingBuf) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 `NIGHTLY_REPORT.md` historique.

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
| `RAIL_RANGE` | 56 | n/a | oui (N84, tri + union-find inchangés) |
| `COLLAPSE_MIN_TILES` | 100 | 100 | oui (N86 wrap, N88 leftover scan) |

---

## 7. Preuve tests

`./tests/run.sh` → **exit 0**.

Serveur :

```
seed 7 / 99991 / 31337 / 1234567 : 18 factions, invariants OK
factions : 18
intentions : sequence, idempotence, apply immediat, rate limit OK
findSeaPath pool : 5 tuiles, 4 appels identiques
findSeaPath pathWalk : identite unique, p1 intact (N83)
stationBuf : liens usine, income, identite (N84)
stationBuf : slot sans joueur, pas d'erreur (N84)
contextFor : rawequal, slot 99, resolve CITY, ownerAt lit B (N85)
doomedBuf : deux cancel vides, next nil (N86)
clash : fronts nuls, leftover 0 (N86)
collapse recycle : butin + captor grandit (N86)
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.72
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `hover spawn isolation : lisiere rouge, disque isole vert (N58)` et `identite, ere, diplomatie et classement`. Overlay `previewTile(valid=false)` ne lève pas. HUD lit `eraProgress` number (N77). HUD remplace `self.diplomacy = payload` (N78). Aucune surface client touchée cette passe (`PlacementPreview` / `Placement.luau` inchangés).

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass28.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). Les correctifs N85–N86 sont serveur / pools, pas un Play Solo.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N85 n’ajoute **pas** de require (`ctxBuf` vit dans Buildings, qui require déjà Placement — pas GameState depuis Placement). N86 n’ajoute **pas** de require (`doomedBuf` vit dans ChantierB). N87 ne devra **pas** require GameState depuis BoatFront au-delà de l’existant. N88 reste dans GameState.

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

Piège N83 : `pathWalkBuf` n’est pas réentrant. `findSeaPath` est synchrone et unique. Ne **jamais** `return pathWalkBuf` : `launchInvasion` / retraite / `spawnTradeShips` font `boat.path = path` — un second BFS aliaserait le trajet du premier transport. Ne pas `table.clone` du walk (ça réintroduit la deuxième alloc). Overlay n’itère pas `boat.path` (non répliqué). Le test d’identité (`not rawequal`, `p1[i]` intact) est pour les call sites serveur. `visitBuf` / `parentScratch` / `queueScratch` inchangés (`buffer.fill(visitBuf, 0, 0)`). Échec BFS / `MAX_BFS_NODES` → `nil`. Origine terrestre **exclue** du path (loi N37).

Piège N84 : `stationBuf` / `railParentBuf` / `railXsBuf` / `railYsBuf` / maps de grappe ne sont pas réentrants. `refreshRailNetwork` est unique par mutation. Truncate leftover **avant** `table.sort` : un leftover non truncaté mélange d’anciennes gares dans le tri et les liens répliqués. Itérer `1..count`, pas `#` sur parent/xs/ys. Ne **pas** pooler les inners `neighborsOf[i]` : elles deviennent `building.links` si usine + changed. Option B (`table.clear` in-place sur `building.links`) **interdite** : Overlay / BuildingDelta (N73) tiennent `links` live. Ne pas référencer `IS_STATION`. Ne pas `table.clone(links)` au dirty. Capital spawn est une gare : `railRoutes == 0` tant qu’il n’y a pas d’usine dans une grappe à 2+ gares. `stationBuf` n’est pas `factory.links` (l’usine ne se lie pas à elle-même).

Piège N85 : `ctxBuf` / `ctxState` ne sont pas réentrants. `resolve` est synchrone et unique. Ne **pas** `table.clone(ctxBuf)`. Slot inconnu → `return nil` **sans** muter (le test N85 l’attrape). Après `contextFor(A)` puis `contextFor(B)`, un `ownerAt` conservé lit B — c’est la loi, ne pas « corriger » en clonant. `terrain` est le buffer live (pas une copie). Ne pas toucher `Placement.luau` ni `PlacementPreview.luau` : le fantôme client construit **son** ctx avec les closures `ownerAt`/`buildingAt` fournies par `init.client`. GameState ne doit **pas** require Placement (cycle). `ctxOwnerAt` sans `ctxState` → `NEUTRAL_SLOT` (jamais renvoyé en prod).

Piège N86 : `doomedBuf` / `collapsingBuf` / `collapseRecPool` ne sont pas réentrants. `stepAttacks` est unique par tick. Ne **pas** itérer `#doomedBuf` (hash sparse — la boucle `for i = #state.attacks, 1, -1` reste). Truncate leftover collapsing **avant** le traitement : un leftover d’état A ferait collapse d’un slot fantôme. Compteur nommé `collapseN` (pas `n`) : le wrap a déjà `local n = MapGen.neighbors` dans la boucle de capture. `doomedBuf` est exporté pour le banc (`ChantierB.doomedBuf`) — Overlay ne le lit pas. Clash égal : leftover 0, **pas** de refund des troupes clashed (le banc N86 l’attrape). Collapse ≠ élimination : `collapseFaction` redistribue, `removePlayer` vient via `stepElimination`. `origStepAttacks` reste ignoré. Notify humain inchangé (`not victim.isBot`).
