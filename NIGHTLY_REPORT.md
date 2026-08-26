# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 19)

Déclencheur : ouverture de la **PR #53** (`cursor/analyse-nocturne-du-codebase-7c38`) — navalBasesBySlot, factoryBuf, specs N67–N68.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-1fb3`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#53.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted (bunker / SAM / silo / usine / tous / PORT / NAVAL_BASE) ne sont pas répliqués. `carrierBuf` / `targetBuf` / `samBuf` sont des pools module-level, pas de l’état répliqué.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #53 (passe 18) : claims vérifiés.** `navalBasesBySlot` + `syncCarriers` spawn via l’index (`_carriersDirty` conservé) ; `factoryBuf` recycle + early-out 0 usine. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #53 a documenté (N67, N68)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #53

| Claim #53 | Réalité à l’ouverture |
|---|---|
| `navalBasesBySlot` (N65) | Oui. Spawn carriers via l’index. Dirty NAVAL_BASE seulement. PORT ignoré. |
| `factoryBuf` (N66) | Oui. Early-out 0 usine. Sort si `n >= 2`. |
| Specs N67–N68 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #52, feel jusqu’à #53, plus #39/#44/#47/#50 visuelles. **#53 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#43←#46←#49←#52) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N67–N68 du rapport #53.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `stepCarriers` nested `boats × boats` 10 Hz (N67) | `Navy.luau` (`carrierBuf`/`targetBuf`), `tests/simulate.luau` | Recette hardening N39 / 9f25. Une passe liste carriers vivants + cibles (TRANSPORT / TRADE / CARRIER hp>0). Early-out si 0 carrier **ou** 0 bateau d’un autre slot. Priorité / `areAllied` / dégâts / `WARSHIP_SHELL_RATE` inchangés. N65 (`navalBasesBySlot`) et N63 (`portsByTile`) non touchés. Pas de spatial hash. |
| `Buildings.samsOf` alloue `{number}` à chaque visée nuke bot (N68) | `Buildings.luau` (`samBuf`), `tests/simulate.luau` | Recette `factoryBuf` / N66. Truncate après remplissage. Index présent + set nil = zéro SAM (contrat N59, pas de fallback hash). `tryIntercept` / `Nukes.launch` inchangés. Buffer non réentrant (appelant unique : `Bots.decideNuke`). |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, blastValue × 90 (N69), snapshotBoats alloc (N70).

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
              → Diplomacy.step → GameState.step → replicate(fireDeployed, snapshotBoats)
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom), BoatFront, AimFront, tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`. Stub = `error(...)`. Deux débarquements du même couple = **deux** tas (N5 ouvert ; hardening N29).
- **`areAllied`** = deux directions **et** `tick < expiry` (`true` legacy tests reste vivant).
- **AimFront wrap** = re-visée du front terre du couple ; jamais `isBeachhead`.
- **`tryAnnex`** = BFS depuis les voisins défenseur du seed déjà capturé ; océan abort ; pool N37-like.
- **Carriers** = spawn/despawn/slot sur dirty NAVAL_BASE, spawn via `navalBasesBySlot` (N65). Ciblage obus = `carrierBuf`/`targetBuf` recyclés **(N67, recette hardening N39)**. Pas de spatial hash.
- **Posted bunker** = index `bunkersBySlot`. **Posted SAM** = `samsBySlot`. **Posted SILO** = `silosBySlot`. **Posted FACTORY** = `factoriesBySlot`. **Tous** = `buildingsBySlot`. **PORT** = `portsByTile`. **Posted NAVAL_BASE** = `navalBasesBySlot`.
- **`samsOf`** = lit `samsBySlot` dans `samBuf` recyclé (N68). `tryIntercept` lit l’index directement (N57).
- **Inbound `removePlayer`** = snapshot `buildingsBySlot` → destroy → diplo + transports `kind==1` (100 %, lit **`owner[targetTile]`**) + missiles contrat B + cadran/colis + convois `kind==2` (coulés), **avant** `setOwner`.
- **Hover spawn** = `SpawnHint` (Shared) si `tiles==0`. Serveur = `claimSpawn` (N52+N55).
- **Réplication :** StateDelta / UnitSnapshot (`retreating`) / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. `path` / `homeTile` **non** répliqués. Playing 10 Hz ; lobby vide et ended → 1 Hz. `snapshotBoats` alloue encore chaque tick (N70).

---

## 5. Issues worker-ready (nouveaux, N69–N70)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N68 = faits. N22 = **N67 fait**. N27 = doc only. N59 index = fait ; alloc = **N68 fait**.

---

### ISSUE-N69 — `Bots.blastValue` O(bâtiments cible) × 90 tuiles frontière (feel)

**Priorité :** P3 alloc bots. Suite de N62 (`buildingsBySlot` pour le score) et de N68 (`samsOf` recyclé — le score d’emprise reste nested). Distinct de N68 (liste SAM) et de N57 (`tryIntercept`).

**Problème :** `Bots.decideNuke` échantillonne jusqu’à 90 tuiles de `target.border`. Chaque tuile non couverte par un SAM appelle `blastValue(state, bestSlot, index, blast2)`, qui itère `buildingsBySlot[bestSlot]` (x, y, level). Un rival mid-game ~40 bâtiments × 90 = 3 600 lookups / visée, plus `coveredBy` (déjà cheap après N68). `blastValue` est aussi exporté pour les tests N62 — ne pas casser l’API, flatten **autour** de la boucle 90, pas dans chaque appel unitaire.

**Pourquoi 20K CCU :** 10 Hz × bots ère nuke × nested, empilé avec `samBuf` (N68) et `factoryBuf` (N66). Pas d’autorité (le lancement reste `Nukes.launch` serveur). Cheap isolé une fois aplati.

**Worker :**

1. Dans `decideNuke`, **avant** la boucle 90 : flatten `buildingsBySlot[bestSlot]` dans un `blastBuf` module-level (`table.create(48)` d’enregistrements `{x, y, level}` ou trois arrays parallèles). Truncate. Early-out set nil → buffer vide, score 0 (contrat N62 : index présent ⇒ pas de fallback hash). La boucle 90 lit le buffer, plus `blastValue` par tuile.
2. Garder `Bots.blastValue` pour le test N62 (2 villes > frontière vide). Il peut s’appuyer sur le même helper interne. Ne pas toucher `samsOf` / N68, ni `Nukes.launch`, ni la règle « tout couvert → frapper le SAM ».
3. Test : N62 `blastValue` reste vert. 0 bâtiment cible → toutes les tuiles score 0, SAM shield inchangé. 2 villes dans le rayon battent une tuile vide. Deux visées successives : pas de fuite du premier flatten (truncate). 6000 ticks.
4. Fichiers : `Bots.luau` (`decideNuke` / helper), `tests/simulate.luau` (N62 existant + truncate).

**Contraintes :** pas de RemoteFunction. Recette N66 buffers, pas un spatial hash d’emprise. **N69 feel ≠ N62 (index, déjà fait) ≠ N68 (`samsOf`).** `blastBuf` n’est pas réentrant — `decideNuke` est unique par bot par tick.

---

### ISSUE-N70 — `snapshotBoats` alloue table + N payloads chaque tick (feel)

**Priorité :** P2 alloc réplication. Précision de N2 (UnitSnapshot) **sans** toucher `buildPrices` / stats (reste N2). Distinct de N56 (`retreating` déjà répliqué) et de N67 (ciblage serveur, pas le snapshot).

**Problème :** `GameState.snapshotBoats` fait `local boats = {}` puis `table.insert` d’un **nouvel** enregistrement `{id, slot, x, y, troops, kind, retreating}` pour chaque navire, **chaque tick** (10 Hz playing). Les carriers orbitent : x/y changent toujours, un dirty-skip positionnel ne marcherait pas. Late-game banc 6000 ticks = ~40 navires dont ~23 carriers → 40 tables jetées / tick / shard, plus la table `missiles` reconstruite dans `init.server` `replicate()` (hors bundle, même pattern). Le client n’a pas besoin de `path` / `homeTile` (N56).

**Pourquoi 20K CCU :** 10 Hz × 8 humains × alloc courte, empilé avec `buildPrices` 10 Hz × slots (N2) et `structureHash` à la demande (N4). Pas d’autorité (snapshot dérivé serveur). Un shard 18 factions / 24 carriers saturera le GC avant le scan buildings (déjà indexé).

**Worker :**

1. `boatSnapBuf = table.create(48)` module-level dans `GameState.luau`. Recycle N inner payloads (créer seulement si `boatSnapBuf[i] == nil`, sinon réécrire les champs). Truncate `#boatSnapBuf` après remplissage. **Ne pas** répliquer `path` / `homeTile` / `_sink`. `retreating == true` inchangé (N56).
2. Ne pas toucher N2 `buildPrices` / stats. Ne pas toucher N67 shells. `init.server` missiles : hors bundle — ticket séparé ou même recette dans `replicate()` **si** un hook testable existe déjà ; sinon documenter en N70b et s’arrêter à `snapshotBoats`. Pas de RemoteFunction.
3. Test : 1 carrier + 1 transport → snapshot length 2, `retreating` du transport honoré, pas de `path`. Retirer le transport → snapshot length 1 (pas de fuite). Carrier seul après destroy base (N65) : length suit. 6000 ticks. Client 35/35 (Overlay lit `retreating`, pas l’identité de table).
4. Fichiers : `GameState.luau` (`snapshotBoats`), `tests/simulate.luau` (étendre le test N56 existant).

**Contraintes :** pas de RemoteFunction. Recette `factoryBuf` / N66, pas un dirty flag (l’orbite invalide tout). **N70 feel ≠ N2 (stats/buildPrices, ouvert) ≠ N56 (champ retreating, déjà fait) ≠ N67 (ciblage).** `boatSnapBuf` n’est pas réentrant — `replicate()` est unique par tick.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` reconstruit 10 Hz × slots ; snapshot bateaux → **N70**) |
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
| N22 | Warships O(carriers × boats) | P2 | **fait** cette passe (**N67**, recette hardening N39) |
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
| N56 | Snapshot bateau `retreating` | P3 | **fait** passe 15 (option A) ; alloc → **N70** |
| N57 | SAM scan O(B) / missile | P2 | **fait** passe 15 (`samsBySlot`) |
| N58 | Hover client spawn isolation | P3 | **fait** passe 16 (`SpawnHint`) |
| N59 | `samsOf` / bots scan O(B) | P2 | **fait** passe 16 (alloc → **N68 fait**) |
| N60 | `stepCooldowns` O(B) / tick nuke | P2 | **fait** passe 16 (`samsBySlot` + `silosBySlot`) |
| N61 | `Trade.step` scan FACTORY O(B) | P2 | **fait** passe 17 (`factoriesBySlot`) |
| N62 | Bots upgrade + score nuke O(B) | P2 | **fait** passe 17 (`buildingsBySlot`) ; nested 90 → **N69** |
| N63 | `spawnTradeShips` O(ports²) feel | P2 | **fait** passe 17 (`portsByTile`) |
| N64 | `refreshRailNetwork` scan gares O(B) | P3 | **fait** passe 17 (`buildingsBySlot[slot]`) |
| N65 | `syncCarriers` spawn NAVAL_BASE O(B) dirty | P3 | **fait** passe 18 (`navalBasesBySlot`) |
| N66 | `Trade.step` alloc+sort liste usines 10 Hz | P3 | **fait** passe 18 (`factoryBuf`) |
| N67 | `stepCarriers` nested O(C × B) 10 Hz | P2 | **fait** cette passe (`carrierBuf`/`targetBuf`) |
| N68 | `samsOf` alloc table 10 Hz bots | P3 | **fait** cette passe (`samBuf`) |
| N69 | `blastValue` × 90 tuiles frontière | P3 | **nouveau** |
| N70 | `snapshotBoats` alloc 10 Hz | P2 | **nouveau** (précision N2, pas `buildPrices`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 `NIGHTLY_REPORT.md` historique.

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
samsOf : 3 tuiles, pas le silo (N59)
samsOf recycle : truncate, pas de fuite (N68)
navalBasesBySlot : 2 bases, pas le port, transfer/destroy OK (N65)
Trade.step : 0 usine, lastFactoryVisits=0 (N66)
Trade.step : 2 usines, sort stable (N66)
warships empty : 0 carrier, pas de tir (N67)
warships fire : 1 obus, lastShellTick pose (N67)
warships ally : areAllied saute le transport (N67)
warships own : 0 autre slot, early-out (N67)
removePlayer index : snapshot buildingsBySlot, rien ne reste
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=7.6 p95Changed=8 maxChanged=479 avgTickMs=0.38 p95TickMs=0.90
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `hover spawn isolation : lisiere rouge, disque isole vert (N58)`. Overlay `previewTile(valid=false)` ne lève pas.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass19.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). Les correctifs N67–N68 sont serveur / pools, pas un Play Solo.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N67–N68 n’ajoutent **pas** de remote ni de `require` croisé (Navy ne require pas Buildings ; `samsOf` ne require pas Bots).

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N66 : `factoryBuf` n’est pas réentrant. `Trade.step` est unique par tick. Ne pas appeler `Trade.step` depuis `dispatch` / `resolve`.

Piège N67 : `carrierBuf` / `targetBuf` ne sont pas réentrants. `stepCarriers` est unique par `Navy.step`. Dead carriers (`health <= 0`) restent dans `state.boats` (respawn) mais **hors** `carrierBuf` et hors cibles.

Piège N68 : `samBuf` n’est pas réentrant. `samsOf` n’est appelé que depuis `Bots.decideNuke` (synchrone). Un appelant concurrent doit dupliquer le buffer. Le test N59 lit le **contenu**, pas `rawequal`.
