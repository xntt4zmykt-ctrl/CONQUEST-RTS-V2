# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 18)

Déclencheur : ouverture de la **PR #51** (`cursor/analyse-nocturne-du-codebase-e735`) — factoriesBySlot, buildingsBySlot, portsByTile, specs N65–N66.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-7c38`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#51.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted (bunker / SAM / silo / usine / tous / PORT / **NAVAL_BASE**) ne sont pas répliqués.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #51 (passe 17) : claims vérifiés.** `factoriesBySlot` + `Trade.step` sort conservé ; `buildingsBySlot` (upgrade + blast) ; `portsByTile` (vague = 45 ticks) ; `refreshRailNetwork` via slot. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #51 a documenté (N65, N66)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #51

| Claim #51 | Réalité à l’ouverture |
|---|---|
| `factoriesBySlot` (N61) | Oui. `Trade.step` itère l’index, sort conservé. Ville ignorée. |
| `buildingsBySlot` (N62) | Oui. `lowestUpgradable` / `blastValue` ; `removePlayer` snapshot. |
| `portsByTile` (N63) | Oui. Early-out cap et `<2` avant flatten. Vague = 45 ticks. |
| `refreshRailNetwork` slot (N64) | Oui. Bunker ignoré. Pas `IS_STATION` (local trop bas). |
| Specs N65–N66 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #49, feel jusqu’à #51, plus #39/#44/#47/#50 visuelles. **#51 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#43←#46←#49) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N65–N66 du rapport #51.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `syncCarriers` dirty scanne `buildings` pour NAVAL_BASE (N65) | `GameState.luau` (`navalBasesBySlot`), `Navy.luau`, `tests/simulate.luau` | Index pose / capture / destroy / `removePlayer`. Spawn itère l’index, **garde `_carriersDirty`** (pas 10 Hz). Despawn inchangé (`boats` + `carrierSeen`). Distinct de `portsByTile`. 2 bases + 1 port → 2 carriers. |
| `Trade.step` alloue + sort la liste usines 10 Hz (N66) | `Trade.luau`, `tests/simulate.luau` | `factoryBuf` module-level (recette `portsBuf`). Early-out 0 usine **avant** sort. Sort seulement si `n >= 2`. Loi de tirage / `delivery.level` inchangés. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), warships nested (N22 / N67), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `samsOf` alloc (N68).

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (seq obligatoire en playing, apply immédiat) → tick :
  Bots.step → Navy.step (syncCarriers si dirty, spawn via navalBasesBySlot ;
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
- **Carriers** = spawn/despawn/slot sur dirty NAVAL_BASE, **spawn via `navalBasesBySlot`** (N65). Pas un scan 10 Hz. Ciblage obus = encore O(carriers × boats) (N22 / N67).
- **Posted bunker** = index `bunkersBySlot`. **Posted SAM** = `samsBySlot`. **Posted SILO** = `silosBySlot`. **Posted FACTORY** = `factoriesBySlot`. **Tous** = `buildingsBySlot`. **PORT** = `portsByTile`. **Posted NAVAL_BASE** = `navalBasesBySlot` (N65).
- **Inbound `removePlayer`** = snapshot `buildingsBySlot` → destroy → diplo + transports `kind==1` (100 %, lit **`owner[targetTile]`**) + missiles contrat B + cadran/colis + convois `kind==2` (coulés), **avant** `setOwner`. Index par slot nil, y compris `navalBasesBySlot`.
- **Hover spawn** = `SpawnHint` (Shared) si `tiles==0`. Serveur = `claimSpawn` (N52+N55).
- **Réplication :** StateDelta / UnitSnapshot (`retreating`) / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. `path` / `homeTile` **non** répliqués. Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready (nouveaux, N67–N68)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N22, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N66 = faits. N27 = doc only. N22 est **précisé** en N67 (recette hardening N39, jamais portée feel).

---

### ISSUE-N67 — `stepCarriers` nested O(carriers × boats) 10 Hz (feel)

**Priorité :** P2 perf marine. Suite de N65 (spawn indexé, le ciblage reste nested). C’est le **N22 feel** restant. Distinct de N65 (`navalBasesBySlot`) et de N63 (`portsByTile`).

**Problème :** `Navy.stepCarriers` itère `state.boats` × `state.boats` chaque tick pour l’orbite + le choix de cible (priorité Transport > Warship > Trade). Hardening 9f25 / PR #43 a déjà le **contrat B** : `carrierBuf` / `targetBuf` module-level, early-out si 0 carrier ou 0 bateau d’un autre slot. Feel n’a pas porté ce patch. Late-game ~24 carriers + 39 navires (banc 6000 ticks) = ~900 comparaisons / tick, plus `areAllied` dans la boucle interne.

**Pourquoi 20K CCU :** 10 Hz × nested sur chaque shard. Pas d’autorité (les obus sont serveur) — budget tick, empilé avec combat `guard<80` et `stepDoomsday` O(TILE_COUNT) (N9). Un shard 18 factions / 24 bases saturera avant le scan buildings (déjà indexé).

**Worker :**

1. Porter le contrat B hardening 9f25 **sans** AimFront / `bunkerCells` / spatial hash : `carrierBuf = table.create(18)`, `targetBuf = table.create(48)` module-level. Une passe liste carriers vivants + cibles (TRANSPORT / TRADE / CARRIER hp>0). Early-out si `#carrierBuf == 0` **ou** aucun bateau d’un autre slot. Priorité / `areAllied` / dégâts / cadence `WARSHIP_SHELL_RATE` **inchangés**.
2. Ne pas toucher N65 (`navalBasesBySlot`, `_carriersDirty`) ni N63 (`portsByTile`). Pas de require cycle Navy → GameState. Pas de contrat A spatial hash (ticket séparé si le late-game le justifie).
3. Test : 0 carrier → pas de tir, pas d’erreur. 1 carrier + 1 transport ennemi in range → un obus, `lastShellTick` posé. 1 carrier + 0 autre slot → early-out, transport allié intact. `syncCarriers dirty` et N65 restent verts. 6000 ticks.
4. Fichiers : `Navy.luau` (`stepCarriers`), `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Recette hardening N39, pas un rebuild des warships. **N67 feel ≠ N39 hardening historique (déjà sur 9f25) ≠ N65 (spawn).**

---

### ISSUE-N68 — `Buildings.samsOf` alloue `{number}` à chaque visée nuke bot (feel)

**Priorité :** P3 alloc bots. Suite de N59 (`samsOf` lit `samsBySlot`, la table jetable reste).

**Problème :** `Buildings.samsOf` construit `local out = {}` puis `table.insert` à **chaque appel**. `Bots.luau` l’appelle dans la visée nuke (`local sams = Buildings.samsOf(state, bestSlot)`) avant d’échantillonner jusqu’à 90 tuiles de frontière. Recette N66 : buffer module-level. Ici l’appelant est unique et synchrone — un `samBuf` recyclé suffit. Le test N59 compare le contenu, pas l’identité de table.

**Pourquoi 20K CCU :** 10 Hz × bots en ère nuke × alloc courte, empilé avec `factoryBuf` (N66) et `blastValue` déjà indexé (N62). Cheap isolé. Pas d’autorité (le lancement reste `Nukes.launch` serveur).

**Worker :**

1. Recyclage `samBuf` module-level dans `Buildings.luau` (comme `factoryBuf`). Truncate `#samBuf` après remplissage. Early-out slot sans set → buffer vide, **pas** de fallback hash (contrat N59 : index présent ⇒ set nil = zéro SAM). Ne pas changer `tryIntercept` (`samsBySlot` direct, N57) ni `Nukes.launch`.
2. Ne pas toucher N22/N67 shells. Pas de spatial hash. Le test N59 (`samsOf : 3 tuiles, pas le silo`) doit rester vert — il lit le **contenu**, pas `rawequal`.
3. Test : slot sans SAM → `#samsOf == 0`. 3 SAM + 1 silo → 3 tuiles, silo absent. Deux appels successifs : second résultat correct (pas de fuite du premier remplissage). 6000 ticks verts.
4. Fichiers : `Buildings.luau` (`samsOf`), `tests/simulate.luau` (le test N59 existant + truncate).

**Contraintes :** pas de RemoteFunction. Recette N66 buffers, pas un rebuild du nucleaire. **N68 feel ≠ N59 (index, déjà fait) ≠ N57 (`tryIntercept`).** Si un second appelant concurrent apparaît, dupliquer le buffer — `samsOf` n’est pas réentrant aujourd’hui.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` reconstruit 10 Hz × slots) |
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
| N22 | Warships O(carriers × boats) | P2 | ouvert → **N67** (listes recyclées, recette hardening N39) |
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
| N56 | Snapshot bateau `retreating` | P3 | **fait** passe 15 (option A) |
| N57 | SAM scan O(B) / missile | P2 | **fait** passe 15 (`samsBySlot`) |
| N58 | Hover client spawn isolation | P3 | **fait** passe 16 (`SpawnHint`) |
| N59 | `samsOf` / bots scan O(B) | P2 | **fait** passe 16 (alloc restante → **N68**) |
| N60 | `stepCooldowns` O(B) / tick nuke | P2 | **fait** passe 16 (`samsBySlot` + `silosBySlot`) |
| N61 | `Trade.step` scan FACTORY O(B) | P2 | **fait** passe 17 (`factoriesBySlot`) |
| N62 | Bots upgrade + score nuke O(B) | P2 | **fait** passe 17 (`buildingsBySlot`) |
| N63 | `spawnTradeShips` O(ports²) feel | P2 | **fait** passe 17 (`portsByTile`) |
| N64 | `refreshRailNetwork` scan gares O(B) | P3 | **fait** passe 17 (`buildingsBySlot[slot]`) |
| N65 | `syncCarriers` spawn NAVAL_BASE O(B) dirty | P3 | **fait** cette passe (`navalBasesBySlot`) |
| N66 | `Trade.step` alloc+sort liste usines 10 Hz | P3 | **fait** cette passe (`factoryBuf`) |
| N67 | `stepCarriers` nested O(C × B) 10 Hz | P2 | **nouveau** (recette hardening N39) |
| N68 | `samsOf` alloc table 10 Hz bots | P3 | **nouveau** |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 `NIGHTLY_REPORT.md` historique.

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
navalBasesBySlot : 2 bases, pas le port, transfer/destroy OK (N65)
Trade.step : 0 usine, lastFactoryVisits=0 (N66)
Trade.step : 2 usines, sort stable (N66)
removePlayer index : snapshot buildingsBySlot, rien ne reste
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=8.8 p95Changed=31 maxChanged=479 avgTickMs=0.42 p95TickMs=1.51
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `hover spawn isolation : lisiere rouge, disque isole vert (N58)`. Overlay `previewTile(valid=false)` ne lève pas.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass18.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). Les correctifs N65–N66 sont serveur / index, pas un Play Solo.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N65–N66 n’ajoutent **pas** de remote ni de `require` croisé (Navy ne require pas Trade ; GameState n’ajoute pas Nukes).

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N66 : `factoryBuf` n’est pas réentrant. `Trade.step` est unique par tick. Ne pas appeler `Trade.step` depuis `dispatch` / `resolve`.
