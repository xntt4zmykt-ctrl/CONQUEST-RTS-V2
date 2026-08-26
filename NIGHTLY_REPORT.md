# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 24)

Déclencheur : ouverture de la **PR #68** (`cursor/analyse-nocturne-du-codebase-4876`) — pricesFor, playerStatsForReplicate, specs N77–N78.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-cc42`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#68.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted (bunker / SAM / silo / usine / tous / PORT / NAVAL_BASE) ne sont pas répliqués. `viewBuf[slot]` est un pool module-level, pas de l’état répliqué. `Research.progress` ne retourne plus de table.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #68 (passe 23) : claims vérifiés.** `pricesFor` (N75) ; `playerStatsForReplicate` (N76). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #68 a documenté (N77, N78)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #68

| Claim #68 | Réalité à l’ouverture |
|---|---|
| `pricesFor` (N75) | Oui. `priceBuf[slot]` clear+refill BUILDABLE. Slot inconnu → `emptyPriceBuf` vide, pas `math.huge`. Helper dans Buildings. |
| `playerStatsForReplicate` (N76) | Oui. `statsBuf` / `statsRecPool`. `frontHudForReplicate` une fois. `eraProgress` / `buildPrices` nil dans le helper. |
| Specs N77–N78 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #66 (1e60), feel jusqu’à #68, visuelles #39/#44/#47/#50/#54/#57/#61/#64/#67. **#68 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#43←#46←#49←#52←#55←#58←#60←#63←#66) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N77–N78 du rapport #68.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `Research.progress` alloue `ratios` 10 Hz × slots (N77) | `Research.luau` (`progress` seulement), `tests/simulate.luau` | Leftover N76. Min courant : `gold/cost`, `tiles/requiredTiles`, `buildingCounts[kind]/count`. Pas de table, pas de `table.insert`. Slot inconnu / `era >= MAX_ID` → `1`. `init.server` inchangé (`rec.eraProgress = Research.progress(...)`). Pas de RemoteFunction. |
| `Diplomacy.viewFor` alloue 7 tables 1 Hz × humains (N78) | `Diplomacy.luau` (`viewFor` / `viewBuf[slot]`), `tests/simulate.luau` | Recette N75. **Un record par slot**, pas un buf global (FireClient séquentiel : clear trop tôt cassait le payload précédent). `table.clear` des 6 maps, identité porteuse + inners stable. Slot sans joueur → maps vides. Filtre expiry inchangé (N32). `areAllied` / `request` / `accept` non touchés. 1 Hz `FireClient` inchangé. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `Diplomacy.step` `expired` (N79), `Bots.neighborFactions` (N80).

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
- **Réplication :** StateDelta (`dirtyIndexBuf` N72, HUD fronts N74 via N76, `buildPrices` N75, records stats N76, `eraProgress` N77) / UnitSnapshot (`retreating`, `boatSnapBuf` N70, `missileSnapBuf` N71) / BuildingDelta (`buildingSnapBuf` N73) / plunder / trade / explosions / notify&sfx déployés / Diplomacy.viewFor 1 Hz (N78). `path` / `homeTile` / `progress` **non** répliqués. Playing 10 Hz ; lobby vide et ended → 1 Hz. `Diplomacy.step` alloue encore `expired` 10 Hz (**N79**). `Bots.neighborFactions` alloue un hash contacts à chaque décision (**N80**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N79–N80)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N78 = faits. N22 = **N67 fait**. N27 = doc only.

---

### ISSUE-N79 — `Diplomacy.step` alloue `expired` 10 Hz (feel)

**Priorité :** P3 alloc tick diplomatie. Leftover explicite de N78 (même module). Distinct de N78 (`viewFor` HUD, déjà fait) et de N32 (filtre expiry HUD, déjà fait). Ne pas toucher `areAllied` / `request` / `accept` / `viewFor`.

**Problème :** `Diplomacy.step` construit `local expired: { { a: number, b: number } } = {}` **chaque tick**, puis `table.insert(expired, { a = a, b = b })` pour chaque paire `a < b` dont `tick >= expiry`. Même sans pacte qui tombe, la table porteuse est allouée 10 Hz. Les inner `{ a, b }` sont rares (fin de pacte) mais neuves à chaque expiration. Collecter avant de muter `alliances[]` reste obligatoire (parcours + écriture = comportement indéfini).

**Pourquoi 20K CCU :** 10 Hz × 1 table vide, plus 1–N paires quand un graphe de 18 slots expire. Empilé sur le tick déjà allégé par N67–N78. Pas d’autorité (le pacte meurt de `tick >= expiry` ; le buffer ne fait que différer la mutation). Recycle + truncate élimine l’alloc courte.

**Worker :**

1. Ajouter `expiredBuf` module-level (array) + `expiredRecPool` (inner `{ a, b }` réécrits, recette N76 `statsRecPool`). Au début de `step` : truncate `#expiredBuf = 0` (ne pas `table.clear` si on veut garder la capacité array — `table.clear` est OK si on `table.insert` ensuite). Pour chaque paire `a < b` et `tick >= expiry` : prendre `expiredRecPool[n]` ou en créer un, poser `rec.a` / `rec.b`, `expiredBuf[n] = rec`. Après collecte, itérer `1..n` comme aujourd’hui (nil les deux sens, extensions, `startCooldown`, notify). Truncate `expiredBuf` après traitement (Overlay-style : un lecteur fantôme n’existe pas, mais `#` doit retomber à 0 avant le tick suivant). Pas de RemoteFunction.
2. Ne pas modifier `viewFor` (N78). Ne pas changer la loi : une seule fois par paire (`a < b`), pas de marque traître (ce n’est pas `breakAlliance`). `true` legacy dans `alliances[]` : `tick >= expiry` est faux pour un booléen — **laisser tel quel** (pacte de test sans date). Ne pas require de module nouveau.
3. Test : 2 joueurs, `request`+`accept`, `state.tick = expiry` (la valeur stockée), `Diplomacy.step` → `areAllied` faux, cooldown posé, notify de terme (pas « TRAHI »). Second `step` immédiat : toujours pas alliés, pas d’erreur. 3 joueurs, deux pactes A–B et A–C qui expirent le même tick → les deux tombent. Client 35/35. 6000 ticks.
4. Fichiers : `Diplomacy.luau` (`step` seulement — ne pas toucher `viewFor`), `tests/simulate.luau` (bloc court ; le test `areAllied expiry` existe déjà **avant** `step` — ne pas le casser, ajouter un bloc **après** `step`).

**Contraintes :** pas de RemoteFunction. Recette N76 (pool de records) + N70 (truncate). **N79 feel ≠ N78 (viewFor, déjà fait) ≠ N32 (filtre HUD, déjà fait) ≠ N46 (request inverse).** Ne pas fusionner A–B et B–A en deux expirations. Les records ne sont pas réentrants — `step` est unique par tick. Ne pas allouer `{ a, b }` anonyme dans la boucle.

---

### ISSUE-N80 — `Bots.neighborFactions` alloue un hash contacts par décision (feel)

**Priorité :** P3 alloc perception bots. Distinct de N69 (`blastValue` flatten, déjà fait) et de N62 (`buildingsBySlot`). Ne pas toucher `humanTargetProtected` / `decideNuke` / `gatherSites`.

**Problème :** `neighborFactions` construit `local contacts: { [number]: number } = {}` à chaque appel, en parcourant `ps.border`. Appelé jusqu’à **4 fois** par bot par `DECISION_INTERVAL` (14 ticks) : `decideDiplomacy` (trahison + proposition), `decideNavy`, `decideAttack`. Jusqu’à 18 Classique × ~0.3 Hz × 4 = ~20 hash courts / s sur le hot path bots, avant même `gatherSites`. Les appelants consomment tout de suite (`contacts[ally] > 4`, `for other in contacts`, `hasLandTarget`, scoring) et ne stockent pas l’identité.

**Pourquoi 20K CCU :** perception O(frontière) déjà payée ; l’alloc du hash est gratuite à éliminer. Pas d’autorité (les bots n’écrivent or/troupes que via `Diplomacy.*` / `launchAttack` serveur). Un `contactBuf` unique suffit : les appels sont **séquentiels**, jamais imbriqués.

**Worker :**

1. Promouvoir `neighborFactions` en `Bots.neighborFactions` (comme `samsOf`) pour le banc. Ajouter `contactBuf` module-level. Au début : `table.clear(contactBuf)`. Même algo : `ps.border` → `MapGen.neighbors` via `scratch` existant → si terre et `other ~= slot`, `contactBuf[other] += 1`. Slot sans joueur / sans frontière → map **vide** (pas nil). Retourner `contactBuf`. Pas de RemoteFunction. Pas de second buffer « au cas où ».
2. Remplacer les 4 appels internes par `Bots.neighborFactions`. Ne pas cacher NEUTRAL (le scoring `decideAttack` l’utilise). Ne pas toucher `gatherSites` (N81 potentiel). Ne pas require de module nouveau. `scratch` voisins déjà module-level — le garder.
3. Test : 2 joueurs collés (même recette contact que N76). `Bots.neighborFactions(state, a.slot)[b.slot] >= 1`. Second appel immédiat → `rawequal`. Slot 99 → `next(buf) == nil`. Après `removePlayer(b)`, `contacts[b.slot]` absent (tuiles de B devenues NEUTRAL : la clé peut être `NEUTRAL_SLOT`, pas le disparu — vérifier `contacts[gone] == nil`). Client 35/35. 6000 ticks.
4. Fichiers : `Bots.luau` (`neighborFactions` + 4 call sites), `tests/simulate.luau` (bloc court, recette N68 `samsOf`).

**Contraintes :** pas de RemoteFunction. Recette N68 (`samBuf` + clear, truncate N/A : c’est une map). **N80 feel ≠ N69 (blast flatten, déjà fait) ≠ N62 (index bâtiments) ≠ gatherSites (laisser en N81).** `contactBuf` n’est pas réentrant. Les 4 appelants lisent puis abandonnent avant le prochain appel — ne pas `table.clone`. Le test N59-style lit le **contenu**, plus `rawequal` sur le second appel. Ne pas itérer `buildings` / `owner` global (rester sur `ps.border`).

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
| N75 | `buildPrices` alloc 10 Hz × slots | P3 | **fait** passe 23 (`pricesFor`) |
| N76 | `stats[slot]` alloc 10 Hz × slots | P3 | **fait** passe 23 (`playerStatsForReplicate`) |
| N77 | `Research.progress` alloc `ratios` | P3 | **fait** cette passe (min courant) |
| N78 | `Diplomacy.viewFor` alloc 7 tables 1 Hz | P3 | **fait** cette passe (`viewBuf` par slot) |
| N79 | `Diplomacy.step` alloc `expired` 10 Hz | P3 | **nouveau** (pool paires, pas `{ a, b }` anonyme) |
| N80 | `Bots.neighborFactions` alloc hash contacts | P3 | **nouveau** (`contactBuf`, appels séquentiels) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 `NIGHTLY_REPORT.md` historique.

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
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=7.6 p95Changed=8 maxChanged=479 avgTickMs=0.38 p95TickMs=0.90
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `hover spawn isolation : lisiere rouge, disque isole vert (N58)` et `identite, ere, diplomatie et classement`. Overlay `previewTile(valid=false)` ne lève pas. HUD lit `eraProgress` number (N77, min courant, pas une table). HUD remplace `self.diplomacy = payload` (N78, copie désérialisée — recycle serveur OK).

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass24.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). Les correctifs N77–N78 sont serveur / pools, pas un Play Solo.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N77 n’ajoute **pas** de require (`progress` reste dans Research, qui require déjà GameState). N78 n’ajoute **pas** de require (`viewBuf` vit dans Diplomacy).

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

Piège N77 : `progress` ne retourne **pas** de table — ne pas introduire un `ratiosBuf`. Le min courant **est** le goulot HUD (ne pas moyenner). `requiredBuildings` vide (ère 1 → 2 a CITY=1 ; une ère future à `{}` est légale). `count == 0` n’existe pas dans `Eras.LIST` actuel — ne pas ajouter de garde qui changerait la formule. `init.server` pose `rec.eraProgress` **après** N76 : le banc N76 continue de voir `nil`.

Piège N78 : `viewBuf[slot]` n’est **pas** un buffer global unique. Un seul `viewBuf` partagé entre slots casserait le `FireClient` précédent (la boucle humains est séquentielle, le payload n’est pas cloné avant l’envoi — RemoteEvent sérialise de façon synchrone dans le banc, mais Studio queue le même table). HUD client fait `self.diplomacy = payload` (copie wire). Tests existants appellent `viewFor` pour 3 slots puis lisent les 3 vues — d’où un record **par slot**. `table.clear` des inners, pas de nouvelle table porteuse. Slot sans joueur : maps vides, **pas** de scan `requests`/`traitors`. Ne pas cloner `marks`.
