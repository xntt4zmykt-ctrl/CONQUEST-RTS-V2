# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 17)

Déclencheur : ouverture de la **PR #48** (`cursor/analyse-nocturne-du-codebase-5c74`) — hover spawn, samsOf, silosBySlot, specs N61–N63.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-e735`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#48.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted (bunker / SAM / silo / usine / tous / PORT) ne sont pas répliqués.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #48 (passe 16) : claims vérifiés.** `SpawnHint` hover si `tiles==0` ; `samsOf` lit `samsBySlot` ; `stepCooldowns` SAM+silo via index ; banc `os.exit(1)`. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #48 a documenté (N61, N62, N63)** plus deux suites sûres du nouvel index `buildingsBySlot` : `refreshRailNetwork` (N64) et `removePlayer` snapshot.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #48

| Claim #48 | Réalité à l’ouverture |
|---|---|
| Hover spawn isolation (N58) | Oui. `SpawnHint` Shared, mer refusée avant r=6. Pas de RemoteFunction. |
| `samsOf` indexé (N59) | Oui. Slot sans SAM ne rescane pas le hash. |
| `stepCooldowns` SAM+SILO (N60) | Oui. `silosBySlot` + `Nukes.launch` via l’index. Ville forcée à cooldown non tickée. |
| Specs N61–N63 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #46, feel jusqu’à #48, plus #39/#44/#47 visuelles. **#48 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#43←#46) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N61–N63 du rapport #48, plus N64 (rail) parce que `buildingsBySlot` rendait le scan gares trivial.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `Trade.step` scanne `buildings` pour FACTORY (N61) | `GameState.luau` (`factoriesBySlot`), `Trade.luau`, `tests/simulate.luau` | Index pose / capture / destroy / `removePlayer`. `Trade.step` itère l’index, **garde le sort** (RNG inter-serveurs). Compteur `Trade.lastFactoryVisits`. 10 Hz × O(usines) au lieu de O(B). |
| Bots upgrade + score nuke O(B) / O(90×B) (N62) | `GameState.luau` (`buildingsBySlot`), `Bots.luau`, `tests/simulate.luau` | **Option A.** Tous kinds. `lowestUpgradable` itère le set du bot ; `blastValue` itère le set de la **cible**. Fallback hash si index nil. `removePlayer` snapshot les clés puis destroy (l’index mute). |
| `spawnTradeShips` O(ports²) collect (N63) | `GameState.luau` (`portsByTile`), `Navy.luau`, `tests/simulate.luau` | Recette hardening N40 **sans** AimFront / `bunkerCells` : index PORT slot+level (upgrade inclus) ; early-out `MAX_TRADE_SHIPS` **et** `< 2` ports **avant** flatten ; `portsBuf` / `candidateBuf` recyclés. Distinct de `_carriersDirty`. **Correction spec :** appelé toutes les `TRADE_SHIP_INTERVAL` (45) ticks, pas 10 Hz. |
| `refreshRailNetwork` scanne `buildings` (N64) | `GameState.luau` | Collecte les gares depuis `buildingsBySlot[slot]`. **Pas** `IS_STATION` (local déclaré plus bas — nil au runtime). Garde le sort. Pas 10 Hz (pose/capture/destroy gare). |
| Test MIRV / banc | `tests/simulate.luau` | Invariants 5e/5f/5g. Pose / transfer / destroy usines. Upgrade lowest + blast. 3 ports spawn + destroy. Rail bunker ignoré. `removePlayer` vide les index. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), warships grille (N22), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `syncCarriers` spawn NAVAL_BASE (N65).

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (seq obligatoire en playing, apply immédiat) → tick :
  Bots.step → Navy.step (syncCarriers si dirty ; coule TRADE si PORT absent ;
    TRANSPORT retraite si owner ~= targetSlot ;
    spawnTradeShips si tick % 45 == 0, via portsByTile) → Nukes.step
              (stepCooldowns SAM+silo indexés ; tryIntercept via samsBySlot ;
               launch via silosBySlot) → Trade.step (factoriesBySlot) → Diplomacy.step → GameState.step
              → replicate(fireDeployed, snapshotBoats)
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom), BoatFront, AimFront, tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`. Stub = `error(...)`. Deux débarquements du même couple = **deux** tas (N5 ouvert ; hardening N29).
- **`areAllied`** = deux directions **et** `tick < expiry` (`true` legacy tests reste vivant).
- **AimFront wrap** = re-visée du front terre du couple ; jamais `isBeachhead`.
- **`tryAnnex`** = BFS depuis les voisins défenseur du seed déjà capturé ; océan abort ; pool N37-like.
- **Carriers** = spawn/despawn/slot sur dirty NAVAL_BASE, pas un scan 10 Hz. Le **spawn** dirty itère encore `buildings` (N65).
- **Posted bunker** = index `bunkersBySlot`. **Posted SAM** = `samsBySlot`. **Posted SILO** = `silosBySlot`. **Posted FACTORY** = `factoriesBySlot` (N61). **Tous** = `buildingsBySlot` (N62). **PORT** = `portsByTile` slot+level (N63).
- **Inbound `removePlayer`** = snapshot `buildingsBySlot` → destroy → diplo + transports `kind==1` (100 %, lit **`owner[targetTile]`**) + missiles contrat B + cadran/colis + convois `kind==2` (coulés), **avant** `setOwner`. Index par slot nil.
- **Hover spawn** = `SpawnHint` (Shared) si `tiles==0`. Serveur = `claimSpawn` (N52+N55).
- **Réplication :** StateDelta / UnitSnapshot (`retreating`) / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. `path` / `homeTile` **non** répliqués. Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready (nouveaux, N65–N66)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N22, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N64 = faits. N27 = doc only.

---

### ISSUE-N65 — `syncCarriers` dirty scanne encore `buildings` pour NAVAL_BASE (feel)

**Priorité :** P3 perf marine. Suite de N38 (dirty flag, le spawn reste O(B)). Distinct de N63 (`portsByTile`, PORT).

**Problème :** Quand `_carriersDirty`, `syncCarriers` itère tout `buildings` pour spawner les porte-avions manquants. Dirty = pose / destroy / transfer NAVAL_BASE seulement, mais le scan est O(B) pas O(bases). `buildingsBySlot` est tous kinds : itérer tous les slots reste O(B).

**Pourquoi 20K CCU :** une capture de base navale en late-game (~150 bâtiments, ~24 bases) rescane le hash. Rare vs `Trade.step` 10 Hz (déjà N61), mais la recette index posted est établie. Pas d’autorité — budget tick.

**Worker :**

1. Index `navalBasesBySlot` **ou** plat `navalBases[tile]=true` (recette `samsBySlot`) : pose / capture / destroy / `removePlayer`. `syncCarriers` itère l’index pour le spawn ; garde le despawn sur `state.boats` + `carrierSeen`. **Garder `_carriersDirty`** (ne pas scanner 10 Hz). Distinct de `portsByTile` (PORT).
2. Ne pas toucher N22 shells / N39 listes recyclées. Pas de spatial hash. Pas de require cycle Navy → GameState.
3. Test : pose 2 bases + 1 port ; sync ne spawn que 2 carriers. Destroy / transfer met à jour l’index. `syncCarriers dirty` existant reste vert. 6000 ticks.
4. Fichiers : `GameState.luau` (index), `Navy.luau` (`syncCarriers`), `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Recette N57/N61, pas un rebuild des warships. **N65 feel ≠ N34 hardening historique (`syncCarriers` dirty — déjà porté).**

---

### ISSUE-N66 — `Trade.step` alloue + sort la liste usines chaque tick (feel)

**Priorité :** P3 alloc 10 Hz. Suite de N61 (index, la liste jetable reste).

**Problème :** `Trade.step` construit `{ number }` + `table.sort` à **chaque tick**, même à 0 usine (early-game) ou 1 usine (sort no-op mais alloc). Recette N63 : `portsBuf` recyclé. Ici la liste vit 10 Hz, pas toutes les 45 ticks.

**Pourquoi 20K CCU :** 10 Hz × alloc courte + sort, empilé avec combat `guard<80` et `stepDoomsday` O(TILE_COUNT) (N9). Cheap isolé. Pas d’autorité (l’or est serveur) — GC tick.

**Worker :**

1. Recyclage `factoryBuf` module-level (comme `portsBuf`). Early-out si 0 usine **avant** sort. Sort seulement si `n >= 2` (déterminisme RNG). Ne pas changer `delivery.level` (N20) ni la loi de tirage.
2. Ne pas toucher convoi `kind==2` (N48) ni PORT détruit (N51). Pas de spatial hash.
3. Test : 0 usine → `lastFactoryVisits==0` sans erreur. 2 usines → visites=2, sort stable (deux `Trade.step` même rng → même destination si cooldown off). 6000 ticks verts.
4. Fichiers : `Trade.luau` (`step`), `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Recette N63 buffers, pas un rebuild du commerce. **N66 feel ≠ N40 hardening (`spawnTradeShips`).**

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert |
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
| N22 | Warships O(carriers × boats) | P2 | ouvert (shells ; spawn → **N38 fait**) |
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
| N38 | `syncCarriers` O(B) / tick | P2 | **fait** passe 9 (dirty ; spawn reste N65) |
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
| N56 | Snapshot bateau `retreating` | P3 | **fait** passe 15 (option A) |
| N57 | SAM scan O(B) / missile | P2 | **fait** passe 15 (`samsBySlot`) |
| N58 | Hover client spawn isolation | P3 | **fait** passe 16 (`SpawnHint`) |
| N59 | `samsOf` / bots scan O(B) | P2 | **fait** passe 16 |
| N60 | `stepCooldowns` O(B) / tick nuke | P2 | **fait** passe 16 (`samsBySlot` + `silosBySlot`) |
| N61 | `Trade.step` scan FACTORY O(B) | P2 | **fait** cette passe (`factoriesBySlot`) |
| N62 | Bots upgrade + score nuke O(B) | P2 | **fait** cette passe (`buildingsBySlot`) |
| N63 | `spawnTradeShips` O(ports²) feel | P2 | **fait** cette passe (`portsByTile`, recette hardening N40) |
| N64 | `refreshRailNetwork` scan gares O(B) | P3 | **fait** cette passe (`buildingsBySlot[slot]`) |
| N65 | `syncCarriers` spawn NAVAL_BASE O(B) dirty | P3 | **nouveau** |
| N66 | `Trade.step` alloc+sort liste usines 10 Hz | P3 | **nouveau** |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 `NIGHTLY_REPORT.md` historique.

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

---

## 7. Preuve tests

`./tests/run.sh` → **exit 0**.

Serveur :

```
seed 7 / 99991 / 31337 / 1234567 : 18 factions, invariants OK
factions : 18
intentions : sequence, idempotence, apply immediat, rate limit OK
Trade.step : 2 usines visites, pas la ville (N61)
factoriesBySlot : pose / transfer / destroy OK
lowestUpgradable : ville niveau 1, bunker ignore (N62)
blastValue : 2 villes battent une frontiere vide (N62)
portsByTile : 3 ports, spawn, destroy OK (N63)
refreshRail : gares du slot, bunker ignore (N64)
removePlayer index : snapshot buildingsBySlot, rien ne reste
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=8.8 p95Changed=31 maxChanged=479 avgTickMs=0.41 p95TickMs=1.49
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `hover spawn isolation : lisiere rouge, disque isole vert (N58)`. Overlay `previewTile(valid=false)` ne lève pas.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass17.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). Les correctifs N61–N64 sont serveur / Shared index, pas un Play Solo.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N61–N64 n’ajoutent **pas** de remote ni de `require` croisé (Navy ne require pas Trade ; GameState n’ajoute pas Nukes).

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime (`attempt to index nil with number` au premier `addPlayer`).
