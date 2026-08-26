# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 25)

Déclencheur : ouverture de la **PR #71** (`cursor/analyse-nocturne-du-codebase-cc42`) — Research.progress min, viewFor recycle, specs N79–N80.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-2f5d`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#73.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. `expiredBuf` / `contactBuf` sont des pools module-level, pas de l’état répliqué.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #71 (passe 24) : claims vérifiés.** `Research.progress` min courant (N77) ; `viewBuf[slot]` (N78). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #71 a documenté (N79, N80)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #71

| Claim #71 | Réalité à l’ouverture |
|---|---|
| `Research.progress` min (N77) | Oui. Pas de table `ratios`. Slot inconnu / `era >= MAX_ID` → `1`. `init.server` pose `rec.eraProgress` après N76. |
| `viewBuf[slot]` (N78) | Oui. Un record par slot, `table.clear` des 6 maps. Slot sans joueur → maps vides. Filtre expiry inchangé (N32). |
| Specs N79–N80 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #70 (3ef4), feel jusqu’à #71, visuelles #39/#44/#47/#50/#54/#57/#61/#64/#67/#69/#72. **#71 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#66←#70) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N79–N80 du rapport #71.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `Diplomacy.step` alloue `expired` 10 Hz (N79) | `Diplomacy.luau` (`step` seulement), `tests/simulate.luau` | Leftover N78. Pool `expiredBuf` + `expiredRecPool` (recette N76). Collecte `a < b` puis mutation. `true` legacy : `typeof == "number"` (même classe que `pactStillLive`) — le pacte de test sans date ne tombe pas. Truncate après traitement. Loi inchangée : pas de marque traître, cooldown + notify « terme ». `viewFor` / `request` / `accept` / `areAllied` non touchés. |
| `Bots.neighborFactions` alloue un hash par décision (N80) | `Bots.luau` (`neighborFactions` + 4 call sites), `tests/simulate.luau` | Leftover N69. `contactBuf` unique, `table.clear` (map, pas truncate). Promu `Bots.neighborFactions` pour le banc. NEUTRAL conservé. `gatherSites` non touché (N81). Slot sans joueur → map vide. Les 4 appelants lisent puis abandonnent — pas de `table.clone`. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `gatherSites` (N81), `stepElimination` `doomed` (N82).

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
- **Réplication :** StateDelta (`dirtyIndexBuf` N72, HUD fronts N74 via N76, `buildPrices` N75, records stats N76, `eraProgress` N77) / UnitSnapshot (`retreating`, `boatSnapBuf` N70, `missileSnapBuf` N71) / BuildingDelta (`buildingSnapBuf` N73) / plunder / trade / explosions / notify&sfx déployés / Diplomacy.viewFor 1 Hz (N78). `path` / `homeTile` / `progress` **non** répliqués. Playing 10 Hz ; lobby vide et ended → 1 Hz. `Diplomacy.step` recycle `expiredBuf` (**N79**). `Bots.neighborFactions` recycle `contactBuf` (**N80**). `gatherSites` alloue encore un array par décision build (**N81**). `stepElimination` alloue encore `doomed` 10 Hz (**N82**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N81–N82)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N80 = faits. N22 = **N67 fait**. N27 = doc only.

---

### ISSUE-N81 — `Bots.gatherSites` alloue un array par décision build (feel)

**Priorité :** P3 alloc perception bots. Leftover explicite de N80 (même module). Distinct de N80 (`contactBuf` contacts, déjà fait) et de N62 (`buildingsBySlot` / `lowestUpgradable`). Ne pas toucher `neighborFactions` / `humanTargetProtected` / `decideNuke` / `decideAttack`.

**Problème :** `gatherSites` construit `local sites: { number } = {}` à chaque appel, puis `table.insert` jusqu’à 40 (côte PORT/NAVAL_BASE), 60 (frontière DEFENSE) ou jusqu’à 45 tuiles tirées au hasard (villes/silos/SAM). Appelé **une fois** par bot par `DECISION_INTERVAL` quand `decideBuild` a choisi un `wanted` et que l’or suffit. Jusqu’à 18 Classique × ~0.7 Hz = ~13 arrays courts / s sur le hot path build, après que N80 a déjà retiré les hash contacts. L’appelant (`for _, index in gatherSites(...)`) consomme tout de suite et ne stocke pas l’identité.

**Pourquoi 20K CCU :** le parcours côte/frontière est déjà payé ; l’alloc de l’array est gratuite à éliminer. Pas d’autorité (les bots ne posent que via `Buildings.build` serveur). Un `siteBuf` unique suffit : `decideBuild` n’est pas réentrant.

**Worker :**

1. Promouvoir `gatherSites` en `Bots.gatherSites` (comme `neighborFactions` N80 / `samsOf`) pour le banc. Ajouter `siteBuf` module-level (`table.create(60)` — cap DEFENSE). Au début : n = 0. Même algo, **sans shuffle** (le code actuel n’en a pas : l’ordre de hash `coast`/`border` est la loi). PORT/NAVAL_BASE : `ps.coast`, cap 40. DEFENSE : `ps.border`, cap 60. Sinon : 45 `rng:NextInteger` sur la carte, garder si `owner == ps.slot`. Poser `siteBuf[n] = index`. Truncate `#siteBuf` à n (recette N68 / N70). Slot / `ps` sans côte ni frontière → array **vide** (`# == 0`), pas nil. Retourner `siteBuf`. Pas de RemoteFunction. Pas de second buffer.
2. Remplacer l’appel interne `gatherSites(...)` dans `decideBuild` par `Bots.gatherSites`. Ne pas changer les caps 40/60/45. Ne pas ajouter de shuffle (changerait quelles côtes les bots essaient en premier). Ne pas require de module nouveau. Ne pas toucher `contactBuf`.
3. Test : 1 joueur spawn (frontière non vide). `Bots.gatherSites(state, ps, Config.BUILDING.DEFENSE, rng)` → `# >= 1`, chaque index est dans `ps.border`, `# <= 60`. Second appel immédiat → `rawequal`. `table.clear(ps.border)` puis rappel → `# == 0` (truncate, pas de fuite N68). PORT sur un spawn sans côte → `# == 0` (pas d’erreur). Client 35/35. 6000 ticks.
4. Fichiers : `Bots.luau` (`gatherSites` + 1 call site `decideBuild`), `tests/simulate.luau` (bloc court, recette N80 / N68).

**Contraintes :** pas de RemoteFunction. Recette N68 (array + truncate) + N80 (promu sur `Bots`). **N81 feel ≠ N80 (contacts, déjà fait) ≠ N62 (index bâtiments) ≠ N66 (factoryBuf Trade).** `siteBuf` n’est pas réentrant. `decideBuild` lit puis abandonne avant le prochain bot — ne pas `table.clone`. Le test N59-style lit le **contenu** (appartenance `border`) plus `rawequal` sur le second appel. Ne pas itérer `owner` global pour DEFENSE/PORT (rester sur `ps.border` / `ps.coast`). Le tirage intérieur **reste RNG** : ne pas tester `rawequal` de contenu sur CITY, seulement l’identité du buffer si besoin.

---

### ISSUE-N82 — `GameState.stepElimination` alloue `doomed` 10 Hz (feel)

**Priorité :** P3 alloc tick élimination. Distinct de N79 (`Diplomacy.step` `expiredBuf`, déjà fait) et de N40/`settledHumans` (déjà fait). Ne pas toucher `removePlayer` (son `local doomed` est un snapshot **bâtiments**, N62) ni `collapseFaction` (`remaining` / `leftovers`, rare).

**Problème :** `stepElimination` construit `local doomed: { number } = {}` **chaque tick**, puis `table.insert` les slots `tiles == 0` sans offensive ni bateau. Même sans élimination, la table porteuse est allouée 10 Hz × shards. Collecter avant de muter `players[]` reste obligatoire (`removePlayer` mute le hash). `GameState.step` retourne cette liste ; `init.server` **ignore** le retour (`state:step()`). Les inner slots sont rares (une élimination) mais la porteuse est chaude.

**Pourquoi 20K CCU :** 10 Hz × 1 table vide, empilé sur le tick déjà allégé par N67–N80. Pas d’autorité (la loi `tiles==0` + pas d’attaque + pas de bateau est inchangée). Recycle + truncate élimine l’alloc courte. Buffer **module-level partagé entre instances** (comme `boatSnapBuf` N70) : un leftover d’état A fuit dans l’état B si on ne truncate pas.

**Worker :**

1. Ajouter `elimBuf` module-level (`table.create(8)`). **Ne pas** le nommer `doomed` : `removePlayer` a déjà un `local doomed` bâtiments — collision de lecture pour le prochain agent. Au début de `stepElimination` : n = 0. Même loi : skip `tiles > 0`, skip offensive `attacker == slot`, skip bateau `boat.slot == slot`, sinon `elimBuf[n] = slot`. Truncate leftover n+1..# (garder 1..n pour l’appelant). Itérer `1..n` comme aujourd’hui (notify humain seulement, `removePlayer`). `return elimBuf`. Pas de RemoteFunction. Ne pas truncate à 0 **après** le return : l’appelant (et le banc) lit `#`.
2. Ne pas modifier `GameState.step` (il retourne déjà `self:stepElimination()`). Ne pas modifier `removePlayer` / `collapseFaction` / `settledHumans`. Ne pas require de module nouveau. Ne pas changer la loi : bot éliminé = silencieux, humain = notify. Un joueur avec transport en mer ou front actif **survit**.
3. Test : 1 joueur vivant → `stepElimination` length 0, second appel `rawequal`. Strip toutes les tuiles (`setOwner` → NEUTRAL, pas d’attaque, pas de bateau) → length 1, slot présent, `players[slot] == nil` après. **Truncate inter-instances** : après cette élimination, `GameState.new` + 1 joueur vivant → `stepElimination` length 0, **pas** le slot du mort précédent (recette N70 2→1→0). Client 35/35. 6000 ticks.
4. Fichiers : `GameState.luau` (`stepElimination` seulement), `tests/simulate.luau` (bloc court ; ne pas casser `settledHumans`).

**Contraintes :** pas de RemoteFunction. Recette N70 (array partagé + truncate leftover, pas clear-à-0 après return). **N82 feel ≠ N79 (expired diplomatique, déjà fait) ≠ N40 (settledHumans, déjà fait) ≠ N62 (`removePlayer` snapshot bâtiments).** `elimBuf` n’est pas réentrant. `step` est unique par tick. Ne pas allouer `{ slot }` anonyme. Overlay n’itère pas cette liste (retour ignoré en prod) — le truncate est pour le banc et un futur appelant. Ne **pas** merger beachhead/terre dans le skip offensive : n’importe quel `atk.attacker == slot` suffit déjà.

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
| N77 | `Research.progress` alloc `ratios` | P3 | **fait** passe 24 (min courant) |
| N78 | `Diplomacy.viewFor` alloc 7 tables 1 Hz | P3 | **fait** passe 24 (`viewBuf` par slot) |
| N79 | `Diplomacy.step` alloc `expired` 10 Hz | P3 | **fait** cette passe (`expiredBuf` + pool records) |
| N80 | `Bots.neighborFactions` alloc hash contacts | P3 | **fait** cette passe (`contactBuf`) |
| N81 | `Bots.gatherSites` alloc array / décision | P3 | **nouveau** (`siteBuf`, caps 40/60/45 inchangés) |
| N82 | `stepElimination` alloc `doomed` 10 Hz | P3 | **nouveau** (`elimBuf`, pas le doomed bâtiments de `removePlayer`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 `NIGHTLY_REPORT.md` historique.

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
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.73
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `hover spawn isolation : lisiere rouge, disque isole vert (N58)` et `identite, ere, diplomatie et classement`. Overlay `previewTile(valid=false)` ne lève pas. HUD lit `eraProgress` number (N77). HUD remplace `self.diplomacy = payload` (N78). Aucune surface client touchée cette passe.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass25.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). Les correctifs N79–N80 sont serveur / pools, pas un Play Solo.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N79 n’ajoute **pas** de require (`expiredBuf` vit dans Diplomacy). N80 n’ajoute **pas** de require (`contactBuf` vit dans Bots, qui require déjà GameState / MapGen).

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
