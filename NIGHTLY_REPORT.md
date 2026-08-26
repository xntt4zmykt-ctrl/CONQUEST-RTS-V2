# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 16)

Déclencheur : ouverture de la **PR #45** (`cursor/analyse-nocturne-du-codebase-2157`) — isolation claimSpawn, snapshot retreating, samsBySlot, specs N58–N60.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-5c74`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#45.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Le hover spawn (N58) est un **hint** : `claimSpawn` refuse encore splash / fallout.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #45 (passe 15) : claims vérifiés.** `isSpawnIsolated` partagé findSpawn/claimSpawn ; `snapshotBoats.retreating` ; `samsBySlot` + `tryIntercept` indexé. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #45 a documenté (N58, N59, N60)**. Recettes du rapport #45, plus une **correction N60** : `SILO_COOLDOWN` est vivant (`Nukes.launch`) — n’itérer que `samsBySlot` aurait gelé les silos.

Banc headless (`./tests/run.sh`) : voir §7. `os.exit(1)` si un invariant casse (le banc masquait auparavant un échec MIRV).

---

## 2. Revue PR #45

| Claim #45 | Réalité à l’ouverture |
|---|---|
| `isSpawnIsolated` partagé findSpawn/claimSpawn (N55) | Oui. Hover client encore vert en lisière — **N58 ici**. |
| `snapshotBoats.retreating` (N56) | Oui. Overlay teinte / pas de splash. |
| `samsBySlot` + `tryIntercept` (N57) | Oui. `samsOf` / `stepCooldowns` scannaient encore le hash — **N59 / N60 ici**. |
| Specs N58–N60 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #43, feel jusqu’à #45, plus #39/#44 visuelles. **#45 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←#20←#23←#25←#27←#30←#31←#33←#35←#37←#40←#43) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N58–N60 du rapport #45.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Hover spawn ignore l’isolation (N58) | `SpawnHint.luau` (nouveau, Shared), `init.client.luau`, `tests/client.luau` | **Option A.** Si `stats[mySlot].tiles==0`, `valid` = `SpawnHint.looksClaimable` (carré `SPAWN_RADIUS+3` NEUTRAL, ou voisin r=6). Mer refusée **avant** r=6 (même ordre que `claimSpawn`). Pas de RemoteFunction. Pas de copie `isSpawnSafe` (splash/fallout restent un refus serveur). Hint, pas un second `claimSpawn`. |
| `Buildings.samsOf` scanne `buildings` (N59) | `Buildings.luau`, `tests/simulate.luau` | Itère `samsBySlot[slot]` ; si l’index existe, un slot **sans** SAM ne rescane **pas** le hash. Fallback hash seulement si `samsBySlot` est nil (tests partiels). Sémantique inchangée (tuiles SAM de **ce** slot). |
| `stepCooldowns` O(B) / tick nuke (N60) | `Buildings.luau`, `GameState.luau` (`silosBySlot`), `Nukes.luau`, `tests/simulate.luau` | SAM via `samsBySlot`. **Correction :** `Nukes.launch` pose `silo.cooldown = SILO_COOLDOWN` — option A « SAM only » aurait gelé les silos. Index `silosBySlot` (recette `samsBySlot`) : pose / capture / destroy / `removePlayer`. `stepCooldowns` ticke SAM **et** silos. `Nukes.launch` choisit le silo dans l’index. Une ville forcée à cooldown n’est plus visitée. |
| Test MIRV injectait un silo hors index | `tests/simulate.luau` | `placeBuilding` pour alimenter `silosBySlot`. Sans ça : « Il te faut un silo. » |
| Banc `./tests/run.sh` masquait les échecs | `tests/simulate.luau`, `tests/client.luau` | `os.exit(1)` si `failures > 0`. Découvert quand le MIRV cassait sans faire échouer le script. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), warships grille (N22), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, factories scan Trade (N61), bots hash restant (N62), `spawnTradeShips` O(ports²) (N63).

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (seq obligatoire en playing, apply immédiat) → tick :
  Bots.step → Navy.step (syncCarriers si dirty ; coule TRADE si PORT absent ;
              TRANSPORT retraite si owner ~= targetSlot) → Nukes.step
              (stepCooldowns SAM+silo indexés ; tryIntercept via samsBySlot ;
               launch via silosBySlot) → Trade.step → Diplomacy.step → GameState.step
              → replicate(fireDeployed, snapshotBoats)
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom), BoatFront, AimFront, tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`. Stub = `error(...)`. Deux débarquements du même couple = **deux** tas (N5 ouvert ; hardening N29).
- **`areAllied`** = deux directions **et** `tick < expiry` (`true` legacy tests reste vivant).
- **AimFront wrap** = re-visée du front terre du couple ; jamais `isBeachhead`.
- **`tryAnnex`** = BFS depuis les voisins défenseur du seed déjà capturé ; océan abort ; pool N37-like.
- **Carriers** = spawn/despawn/slot sur dirty NAVAL_BASE, pas un scan 10 Hz.
- **Posted bunker** = index `bunkersBySlot`. **Posted SAM** = `samsBySlot`. **Posted SILO** = `silosBySlot` (N60).
- **Inbound `removePlayer`** = diplo + transports `kind==1` (100 %, lit **`owner[targetTile]`**) + missiles contrat B + cadran/colis + convois `kind==2` (coulés), **avant** `setOwner`. `samsBySlot[slot]` / `bunkersBySlot[slot]` / `silosBySlot[slot]` nil.
- **Hover spawn** = `SpawnHint` (Shared) si `tiles==0`. Serveur = `claimSpawn` (N52+N55).
- **Réplication :** StateDelta / UnitSnapshot (`retreating`) / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. `path` / `homeTile` **non** répliqués. Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready (nouveaux, N61–N63)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N22, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N32/N34–N60 = faits. N27 = doc only.

---

### ISSUE-N61 — `Trade.step` scanne tout `buildings` pour FACTORY (feel)

**Priorité :** P2 perf éco 10 Hz. Distinct de N20 (HUD `stopBonus`) et N48 (convoi inbound).

**Problème :** `Trade.step` construit à **chaque tick** une liste `factories` en itérant le hash `buildings`, puis `table.sort` pour figer le RNG. Late-game Classique : ~44 usines parmi ~90–150 bâtiments. 10 Hz × O(B) + sort, **même sans colis en vol**. L’index par kind existe déjà pour bunker / SAM / silo ; les usines n’en ont pas.

**Pourquoi 20K CCU :** le chemin nuke (N57/N59/N60) ne scanne plus `buildings`. Il reste ce collect 10 Hz sur le tick éco, **avant** combat `guard<80` et `stepDoomsday` O(TILE_COUNT) (N9). Cheap en isolation, pas cheap empilé. Pas d’autorité (l’or est serveur) — budget tick.

**Worker :**

1. Index `factoriesBySlot` **ou** set plat `factories[tile]=true` (recette `samsBySlot`) : pose / capture / destroy / `removePlayer`. `Trade.step` itère l’index, **garde le sort** (déterminisme RNG inter-serveurs).
2. Ne pas changer `delivery.level` snapshot (N20). Ne pas toucher convoi `kind==2` (N48) ni PORT détruit (N51). Pas de spatial hash.
3. Test : 2 usines + 1 ville ; `Trade.step` ne visite que les usines (compteur optionnel). Pose / transfer / destroy met à jour l’index. Invariant 5e (comme 5c/5d). 6000 ticks verts.
4. Fichiers : `GameState.luau` (index), `Trade.luau` (`step`), `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Recette N57/N60, pas un rebuild du commerce. **N61 feel ≠ N40 hardening (`spawnTradeShips` O(ports²) — voir N63).**

---

### ISSUE-N62 — Bots : upgrade + score nuke encore O(B) / O(90×B) (feel)

**Priorité :** P2 perf bots. Suite de N59 (`samsOf` indexé, le reste du hash non).

**Problème :** `Bots.tryUpgradeBuilding` itère tout `buildings` pour le moins développé du slot (`DECISION_INTERVAL=14`, ×11 bots). `decideNuke` : pour jusqu’à **90** tuiles de frontière, rescane tout `buildings` du camp visé pour scorer l’emprise (`value += level` dans `blast2`). Après N59, `coveredBy` est O(SAM) ; le score reste O(90×B) par décision de frappe.

**Pourquoi 20K CCU :** 11 bots + 6 tribus, ère 5 (4 factions ère 5 dans le banc 6000 ticks). Un spike nuke n’est plus `tryIntercept` (N57) ni `samsOf` (N59) : c’est 90 × ~90 bâtiments pour choisir une tuile. Budget tick, pas autorité. Distinct de N22 (warships spatiaux).

**Worker — choisir UNE option :**

1. **(A)** Index `buildingsBySlot[slot][tile]` (tous kinds) : upgrade itère le set du bot ; score nuke itère le set de la **cible** (plus le hash global). **(B)** Seulement `upgradablesBySlot` + réutiliser `buildings` de la cible via un set plat. Ne **pas** spatial-hasher le blast (N22 reste ouvert). Ne pas changer `SAM_RANGE` / chance (N26).
2. Ne pas faire viser les SAM alliés. Ne pas relire `samsOf` via le hash (N59).
3. Test : 3 bâtiments upgradables + 1 bunker maxé ; `tryUpgradeBuilding` choisit le plus bas. Score nuke : 2 villes dans le rayon battent une frontière vide. `samsOf` / intercept restent verts.
4. Fichiers : `GameState.luau` (si nouvel index), `Bots.luau` (`tryUpgradeBuilding`, boucle `value` ~L736), `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Recette index posted, pas un rewrite de l’IA. **N62 feel ≠ N31 feel historique (scan bunkers — déjà N42).**

---

### ISSUE-N63 — `Navy.spawnTradeShips` O(ports²) / tick dirty (feel)

**Priorité :** P2 perf marine. **Hardening N40** (branche f8c8 / `portsByTile`) — jamais porté sur feel.

**Problème :** `spawnTradeShips` collecte tous les PORT dans `buildings`, puis pour chaque source × chaque autre port `canTrade` + `findSeaPath` (poolé N37, mais l’appel reste O(ports²) chemins). Late-game ~24 ports. Appelé depuis `Navy.step` **chaque tick** (pas dirty). `MAX_TRADE_SHIPS` coupe tôt, mais la collecte + double boucle tourne quand même.

**Pourquoi 20K CCU :** 10 Hz × O(P²) BFS mer (même poolés) en plus du combat. Un shard 18 factions / 24 ports est le cas Classique du banc, pas un extrême. Feel n’a pas `portsByTile` ni l’early-out cap hardening. Distinct de N61 (usines terre) et N38 (`syncCarriers` dirty — déjà fait).

**Worker :**

1. Porter la recette hardening N40 **sans** AimFront / seq / `bunkerCells` : index incrémental PORT (`portsByTile` ou `portsBySlot`) pose/destroy/transfer ; early-out si `< 2` ports ou `countTradeShips >= MAX_TRADE_SHIPS` **avant** flatten / double boucle. Optionnel dirty si aucun PORT n’a changé **et** cap atteint.
2. Ne pas changer `TRADE_SHIP_CHANCE` / `canTrade` (embargo N27 maritime-only). Ne pas recréer `findSeaPath` (déjà poolé). Capture PORT = convoi survit (N51). Distinct de `_carriersDirty` (NAVAL_BASE).
3. Test : 3 ports, 2 camps ; un spawn ; détruire un PORT met à jour l’index. `trade port-detruit` / `trade inbound` restent verts. Ne pas crasher à `< 4` ports (visual V spawnTradeShips clamp).
4. Fichiers : `Navy.luau` (`spawnTradeShips`), `GameState.luau` (index PORT), `tests/simulate.luau`. Lire hardening f8c8 / PR associée pour le texte N40 original.

**Contraintes :** pas de RemoteFunction. Ne pas merger hardening sur feel. **N63 feel ≠ N40 feel historique (`settledHumans`).**

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
| N38 | `syncCarriers` O(B) / tick | P2 | **fait** passe 9 |
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
| N58 | Hover client spawn isolation | P3 | **fait** cette passe (option A, `SpawnHint`) |
| N59 | `samsOf` / bots scan O(B) | P2 | **fait** cette passe |
| N60 | `stepCooldowns` O(B) / tick nuke | P2 | **fait** cette passe (`samsBySlot` + `silosBySlot`) |
| N61 | `Trade.step` scan FACTORY O(B) | P2 | **nouveau** |
| N62 | Bots upgrade + score nuke O(B) | P2 | **nouveau** (N59 indexé, le reste non) |
| N63 | `spawnTradeShips` O(ports²) feel | P2 | **nouveau** (hardening N40 jamais porté) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 `NIGHTLY_REPORT.md` historique.

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

---

## 7. Preuve tests

`./tests/run.sh` → **exit 0**.

Serveur :

```
seed 7 / 99991 / 31337 / 1234567 : 18 factions, invariants OK
factions : 18
intentions : sequence, idempotence, apply immediat, rate limit OK
intentions : schema doctrine/nuke/diplomatie, ended OK
intentions : QuickChat cooldown honore
intentions : QuickChat 2-args refuse, 3-args marque
intentions : diplomatie self et sequence inf refusees
intentions : sequence committee apres apply reussi (N29)
intentions : sequence nil refusee en playing, optionnelle en lobby (N41)
samsOf : 3 tuiles, pas le silo (N59)
samsBySlot : pose / transfer / destroy OK
stepCooldowns : SAM+SILO tickent, ville intacte (N60)
claimSpawn isolation : lisiere refusee
boat snapshot retreat : retreating=true, pas de path
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=6.3 p95Changed=7 maxChanged=479 avgTickMs=0.25 p95TickMs=0.40
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `hover spawn isolation : lisiere rouge, disque isole vert (N58)`. Overlay `previewTile(valid=false)` ne lève pas.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass16.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). Le hover N58 est couvert par `SpawnHint` + `previewTile`, pas par un Play Solo.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. `bunkersBySlot` / `samsBySlot` / `silosBySlot` sont des champs d’état, pas des modules. N58 n’ajoute **pas** de remote. N59 n’ajoute **pas** de require. N60 n’ajoute **pas** de `require Nukes` depuis GameState (index local ; `launch` lit `state.silosBySlot`).

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.
