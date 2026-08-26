# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 2)

Déclencheur : ouverture de la **PR #17** (`cursor/analyse-nocturne-du-codebase-f89b`) — correctifs d’autorité + rapport d’architecture. Base : PR #16 (`cursor/p0-framework-hardening-5b2e`).

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-4548`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16 / #17.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions ; `IntentValidator` enfile, le tick applique.

La PR #17 a bien fermé les trous P0 d’autorité (9e humain, JoinRequest throttle, nuke prep, `areAllied`, `removePlayer`/`setOwner`, file bornée). Cette passe a **corrigé ce que #17 a manqué** : JoinRequest en phase `ended`, réplication `FireAllClients` vers le menu, QuickChat succès fantôme, cadran sur AFK non spawn, HUD alliance unidirectionnelle, message ville « +900 ».

**Correction importante vs rapport #17 :** `MAX_TILES_PER_TICK = 56` est **écrit** par `ChantierB.apply` mais **jamais lu** par le combat installé. Le débit vivant est `attackTilesPerTick * speedFactor`, borné par `guard < 80`. Le banc imprime `attackTilesPerTick(10k,nil,1)=2`.

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique. Le goulot mesuré : **réplication stats+unités 10 Hz** (N2, partiellement réduit ici via audience) × matchmaking absent (N7).

Banc headless (`./tests/run.sh`) : **exit 0**.

- Serveur : 5 seeds + invariants + P0 + gardes #17 + QuickChat cooldown + doomsday AFK + `viewFor` unidirectionnel.
- Client : **34/34 OK**.
- Metrics 6000 ticks : `avgChanged=8.7 p95Changed=16 maxChanged=479 avgTickMs=0.39 p95TickMs=0.69`.
- **Factions observées : 18** (bots + 6 tribus) alors que `PUBLIC_MATCH_CAPACITY=12`.

---

## 2. Revue PR #17

**À merger** (autorité + comptabilité), sous réserve de N1 (dual Config/ChantierB) et de N11 (`MAX_TILES_PER_TICK` mort).

Points encore vrais après #17, mal étiquetés dans son rapport :

| Claim #17 | Réalité |
|---|---|
| `MAX_TILES_PER_TICK` vivant = 56 | Constante **inutilisée**. Combat = `attackTilesPerTick` + `guard < 80`. |
| `justClaimed` avalait l’offensive | Le flag n’existe plus en prod (`awaitingSpawn` / `claimSpawn`). Le test #17 pose `justClaimed` sur un objet mort. |
| Embargo « or par tick » | Docs seulement. L’embargo coupe les **navires de commerce**. |
| Capacité publique 12 | `Bots.spawnAll` ajoute **toujours 6 tribus** par-dessus. Banc : 18 factions. |

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| `JoinRequest` pendant `ended` | `init.server.luau` `deployPlayer` | Spawn + MapInit sur une carte morte (~20 s post-match) |
| `FireAllClients` StateDelta / Units / buildings / plunder / trade / explosions | `init.server.luau` `fireDeployed` | Facturation Roblox par destinataire, y compris le menu |
| Lobby `waiting` vide à 10 Hz | `init.server.luau` `stepOnce` | MatchUpdate 1 Hz seulement tant que personne n’est déployé |
| Phase `ended` à 10 Hz | `init.server.luau` | Réplication 1 Hz (summary HUD) |
| Hash terrain → `RequestSnapshot` | `init.client.luau` | Le snapshot owner ne répare pas un générateur divergé ; brûlait le quota 12/match |
| QuickChat `ok = true` malgré cooldown | `IntentValidator.luau` | Succès fantôme + file brûlée |
| `viewFor` alliances 1-way | `Diplomacy.viewFor` | HUD menteur vs `areAllied` bidirectionnel |
| Cadran saigne `awaitingSpawn` / `tiles=0` | `ChantierB.stepDoomsday` | Humain AFK non spawn drainé late-game |
| Message ville « +900 » | `Buildings.luau` | Runtime = `CITY_LEVELS[1].popCapBonus` (50 000 après apply) |
| Commentaire embargo | `Diplomacy.luau` | Aligné sur `canTrade` |
| Commentaire combat | `ChantierB.stepAttacks` | Documente que 56 n’est pas le cap vivant |

**Non modifié (volontaire) :** coalescence des payloads stats (N2 restant), timebase tick (N3), building snapshot (N4), beachheads (N5), DataStore (N6), matchmaking (N7), fusion ChantierB (N8), index rot (N9), tribus vs capa (N12), parité combat ère/cost factor (N13).

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom), BoatFront, AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick`), pas `GameState.stepAttacks`.
- **Carte** : buffers `terrain` / `owner` / `defense`, 256×160, seed répliquée, deltas `[u32][u8]`.
- **Réplication (après cette passe)** : `StateDelta` / `UnitSnapshot` / `BuildingDelta` → **deployés seulement**. `MatchUpdate` reste `FireAllClients` (menu). Playing 10 Hz ; waiting vide et ended → 1 Hz.
- **DataStore** : `ConquestRTS_Reputation_v1` / `player_{userId}`, `UpdateAsync` + `math.max`, pas de lock, pas de debounce.

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc.

---

### ISSUE-N1 — Source unique d’équilibrage (Config vs ChantierB.apply)

**Priorité :** P1 — bloquant pour tout tuning.

**Problème :** `ReplicatedStorage/Shared/Config.luau` n’est **pas** la vérité runtime. `ChantierB.apply(Config)` écrase START_TROOPS (150→8000), GROWTH_RATE (0.012→0), MAX_TILES_PER_TICK (400→56, **puis inutilisé**), SAM_RANGE (34→70), DEFENSE_RADIUS (6→30), CITY pop 900→50000, etc.

**Pourquoi 20K CCU :** deux tables = deux simulations. Un worker qui « baisse MAX_TILES_PER_TICK » dans Config ne change rien.

**Worker :**

1. Inventaire : grep `cfg.` dans `ChantierB.apply` vs `Config.luau`. Tableau avant/après (voir §6).
2. Déplacer **toutes** les valeurs vivantes dans `Config.luau` (section « Production »).
3. `ChantierB.apply` no-op documenté, ou supprimé.
4. `SystemsBootstrap` : retirer les `or 0.2` / `or 3` morts.
5. Test : `./tests/run.sh` ; assert après `SystemsBootstrap.install()` que les constantes documentées = runtime.
6. **Ne pas** retuner. Lift-and-shift.

**Contraintes :** server-authoritative. Ne pas casser le banc client. Coupler avec N11 (câbler ou supprimer `MAX_TILES_PER_TICK`).

---

### ISSUE-N2 — Réplication : delta `stats` + UnitSnapshot dirty

**Priorité :** P1 perf. Audience corrigée dans cette passe ; **payload** encore plein.

**Problème :** `replicate()` construit toute la table `stats` (buildPrices via `BuildingDefs.BUILDABLE` pour **chaque** slot) et snapshot bateaux+missiles chaque tick playing. `TickMetrics` ne compte que les octets **owner** delta.

**Pourquoi 20K CCU :** 8 humains × 10 Hz × payload multi-KB. Audience menu retirée ; le coût par commandant reste.

**Worker :**

1. Instrumenter `TickMetrics` : `statsBytesEstimate`, `unitSnapshotBytes`, `remoteFireCount`.
2. `buildPrices` seulement si inflation/doctrine a changé, ou 1 Hz.
3. Flag `boatsDirty` / `missilesDirty` ; snapshot vide **au plus** 1 Hz pour cleanup overlay.
4. Option : hash par slot, n’envoyer `stats[slot]` que si changé.
5. Tests : overlay retire le dernier navire (`tests/client.luau` Overlay). Banc : metrics présentes.
6. Fichiers : `init.server.luau`, `TickMetrics.luau`, `Overlay.luau`, `tests/simulate.luau`, `tests/client.luau`.

**Contraintes :** pas de RemoteFunction ; toujours server → client ; ne pas casser l’animation d’arrivée navire. Garder `fireDeployed` (ne pas revenir à FireAllClients).

---

### ISSUE-N3 — Timebase tick vs `os.clock()` (catch-up)

**Priorité :** P1 sim.

**Problème :** `Heartbeat` cap 5 steps ; si `accumulator > TICK_DT*5` → **zero**. Les timers (`matchEndsAt`, `combatStartsAt`, `doctrineLockAt`) sont en `os.clock()`. Sous lag, la sim saute des ticks **mais le chrono réel continue**.

**Pourquoi 20K CCU :** shard chargé (GC, DataStore, dirty tiles) décale la sim. À 10 Hz c’est l’équilibrage entier.

**Worker :**

1. Une timebase : tout en `state.tick` (recommandé).
2. Convertir `PREPARATION_DURATION`, `MATCH_DURATION`, `DOCTRINE_CHOICE_DURATION`, `POST_MATCH_DELAY` en ticks.
3. `checkVictory` / `combatUnlocked` / `endMatch` / `restartAt` lisent `state.tick`.
4. Tests : `combatUnlocked` bascule à `PREPARATION_DURATION / TICK_DT` ticks.
5. Fichiers : `init.server.luau`, `Config.luau`, `tests/simulate.luau`.

**Contraintes :** pas de changement d’équilibrage si le serveur tient 10 Hz.

---

### ISSUE-N4 — Resync bâtiments (`structureHash` ignoré)

**Priorité :** P1 correctness.

**Problème :** `RequestSnapshot` envoie owner + `structureHash()`. Le client jette le hash (`_structureHash`) et n’applique que l’owner. Cette passe a **arrêté** d’appeler snapshot sur un mismatch de **terrain** (inutile). Le resync bâtiments reste ouvert.

**Worker :**

1. Étendre `OwnerSnapshot` **ou** `BuildingSnapshot` (format `flushBuildingDelta`).
2. Client : si hash local ≠ serveur, appliquer le snapshot structures.
3. Quota 5 s / 12/match inchangé.
4. Fichiers : `Remotes.luau`, `init.server.luau`, `init.client.luau`, Overlay.

**Contraintes :** pas de logique de jeu client. Ne pas enlever le rate-limit.

---

### ISSUE-N5 — Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER`

**Priorité :** P2 anti-exploit.

**Problème :** `GameState.launchAttack` cap 2 fronts terre. `BoatFront.seedBeachhead` insère **toujours** un `Attack` avec `sourceTile`, sans cap.

**Pourquoi 20K CCU :** N débarquements = N heaps `stepAttacks` + `attackTargets` plus gros (nourrit N2).

**Worker :**

1. Lire `BoatFront.luau` et `Navy.luau` landing.
2. Décision (documenter dans Config) : (A) cap global 2 y compris bateaux, (B) `MAX_BEACHHEADS`, (C) fusionner vers un beachhead existant même cible.
3. Test : N+1 `seedBeachhead` refuse ou fusionne.
4. Ne pas casser l’isolation terre/mer (`sourceTile ~= nil`).

---

### ISSUE-N6 — DataStore : debounce, retry, session

**Priorité :** P2 persistance.

**Problème :** `Persistence.save` à chaque `record()` / `release()`. Pas de retry. Pas de session MemoryStore. `matches += 1` au rage-quit. `BindToClose` synchrone.

**Pourquoi 20K CCU :** budget DataStore **par univers**. 1 700 shards × 8 humains × writes de fin de match = throttle.

**Worker :**

1. Debounce 5 s ; flush immédiat `BindToClose`.
2. Retry 3× backoff sur `UpdateAsync`.
3. Vérifier tous les chemins : pas de double `record` + `release`.
4. Extraire le merge `UpdateAsync` en fonction pure testable (`Persistence` est exclu du bundle).
5. Fichiers : `Persistence.luau`, éventuellement `tests/bundle.js`.

**Contraintes :** pas de PII ; clé `player_{userId}` uniquement. Studio jouable si DataStore down.

---

### ISSUE-N7 — Matchmaking 20K CCU (lobby MemoryStore / Teleport)

**Priorité :** P2 infra (hors sim).

**Problème :** une Place = une partie. Pas de file, pas de sharding, pas de `TeleportService`.

**Worker (ne pas toucher la sim) :**

1. Place lobby (max 50) + Places match (12 factions).
2. MemoryStore queue par mode.
3. TeleportOptions : seed, mode, UserIds.
4. Respecter `MAX_HUMAN_PLAYERS` / `PUBLIC_MATCH_CAPACITY` **et N12 (tribus)**.
5. Aucune logique de combat dans le lobby.

---

### ISSUE-N8 — Combat mort vs combat vivant

**Priorité :** P2 maintenance.

**Problème :** `GameState.stepAttacks` / `stepEconomy` / `maxTroops` / `tileCost` sont remplacés à runtime par `ChantierB`. Un worker qui « corrige GameState.stepAttacks » ne change pas la prod.

**Worker :**

1. Soit supprimer les fonctions mortes, soit inliner ChantierB dans GameState (zéro drift).
2. Tests `simulate.luau` visent le chemin **installé**.
3. Commentaire d’en-tête sur chaque fonction patchée.

**Contraintes :** zero changement d’équilibrage.

---

### ISSUE-N9 — `stepDoomsday` O(TILE_COUNT) par faction à risque

**Priorité :** P2 perf late-game.

**Problème :** rot parcourt jusqu’à toute la carte par joueur marqué. L’exemption AFK (cette passe) ne réduit pas le scan des empires sous quota. Late-game = 207 explosions / 6000 ticks mesurées.

**Worker :**

1. Liste de tuiles par slot (incrémentale via `setOwner`) **ou** frontier de rot.
2. Budget K tuiles rot / tick / faction.
3. Test invariant owner buffer.
4. Ne pas scanner 40960 indices par joueur par tick.

---

### ISSUE-N11 — Câbler ou supprimer `MAX_TILES_PER_TICK`

**Priorité :** P1 honesty / perf combat.

**Problème :** `ChantierB.apply` pose 56. `GameState.stepAttacks` (mort) le lisait. Le combat installé utilise `attackTilesPerTick` (ex. 2 tuiles/tick pour 10k troupes vs neutre, contact 1) et `while guard < 80`. PR #16 a journalisé « plafond 400 inchangé » ; #17 a dit « runtime 56 ». Les deux sont faux pour la prod.

**Pourquoi 20K CCU :** le cap combat est le 1er levier CPU tick. Un knob mort = on ne peut pas limiter une offensive géante.

**Worker :**

1. Décision : (A) `numTiles = min(attackTilesPerTick*speed, MAX_TILES_PER_TICK)` et baisser guard, **ou** (B) supprimer la constante partout (Config, apply, tests, README).
2. Si (A) : mesurer 6000 ticks avant/après (`TickMetrics` p95TickMs, maxChanged). Ne pas changer le ressenti sans mesure.
3. Mettre à jour le test qui imprime `MAX_TILES_PER_TICK reste 56`.
4. Fichiers : `ChantierB.luau`, `Config.luau`, `GameState.luau` (code mort), `tests/simulate.luau`.

**Contraintes :** ne pas retuner `attackLogic`. Commentaire déjà en place dans `stepAttacks`.

---

### ISSUE-N12 — Tribus vs `PUBLIC_MATCH_CAPACITY`

**Priorité :** P1 produit / perf tick.

**Problème :** `activateMatch` fait `min(botCount, PUBLIC_MATCH_CAPACITY, MAX_TOTAL_FACTIONS)` puis `Bots.spawnAll`. Le wrap `SystemsBootstrap` appelle **ensuite** `Tribes.spawnAll(..., TRIBE_COUNT or 6)`. Banc : **18 factions** en Classique (12+6). Marathon `botCount=16` est déjà plafonné à 12 **puis** +6 tribus.

**Pourquoi 20K CCU :** 18 IA + 6 tribus step + plus de fronts/stats. La capa publique affichée (12) est un mensonge HUD (`MatchUpdate.maxPlayers`).

**Worker :**

1. Décision produit : (A) tribus **dans** le budget 12, (B) capa publique 12 humains/bots + 6 tribus documentée (18), (C) tribus opt-in par mode.
2. `botsToSpawn + TRIBE_COUNT <= MAX_TOTAL_FACTIONS` toujours.
3. Aligner `GameModes` taglines (Classique « 12 nations », Marathon « 16 »).
4. Test simulate : après `Bots.spawnAll` + flush pending, `#state.players` respecte la décision.
5. Fichiers : `SystemsBootstrap.luau`, `init.server.luau` `activateMatch`, `GameModes.luau`, `Config.luau`, `tests/simulate.luau`.

**Contraintes :** ne pas casser le spawn différé 15 s (`DEPLOY_DURATION`). Server-authoritative.

---

### ISSUE-N13 — Parité combat ChantierB vs GameState mort

**Priorité :** P2 équilibrage.

**Problème :** le `tileCost` mort appliquait `sizeAttackFactors` **(speed, cost)** et `Eras.accumulate(defender.era).defense`. Le vivant n’applique que `speedFactor` au débit de tuiles ; `attackLogic` ignore l’ère. `FRONT_TILES_PER_CONTACT`, `DEFENSE_COST_DIVISOR`, `CITY_TROOP_INCREASE` sont écrits par apply et jamais lus.

**Worker :**

1. Tableau : chaque constante apply → lue où (vivant / mort / nulle part).
2. Décision : réintroduire ère + cost factor dans `attackLogic` **ou** documenter l’écart comme voulu.
3. Supprimer les clés mortes ou les câbler.
4. Tests de régression : même graine, dumps de captures / pertes — drift = échec si on choisit « zéro changement ».

**Contraintes :** ticket de design avant code. Ne pas mixer avec N1 sans inventaire.

---

### ISSUE-N10 — Divers (P3, tickets séparés)

1. **Séquence nil encore acceptée** (`IntentValidator.checkSequence`) — métrique `refuseCounts` + date de coupure.
2. **README** SmoothTerrain vs `RENDER_MODE=Blocks` / `WorldBuilder` collision blocs.
3. **Invariant côte inverse** : `simulate.luau` détecte fausses côtes, pas les côtes manquantes.
4. **Bots `decideNuke`** : 90 tuiles front × tous les bâtiments. Index spatial si p95 tick > 8 ms late-game.
5. **`pendingMode` last-writer** pendant un match (mode du *prochain* round). Host only / vote / freeze.
6. **Tests Studio multi-clients** : `init.server.luau` exclu du bundle. JoinRequest 2 joueurs = trou.
7. **`justClaimed` test mort** (`tests/simulate.luau`) — remplacer par `awaitingSpawn` + `claimSpawn` puis `launchAttack`.
8. **Allied boat landing** (`Navy.luau`) rembourse 100 % si le cible s’allie en mer — vs `BOAT_RETREAT_LOSS` 25 %. Décision design.
9. **`BuildingDefs` description « +900 »** encore statique (HUD catalogue). `Buildings.describeBuild` est corrigé ; le catalogue non (N1).

---

## 6. Drift Config → `ChantierB.apply` (extrait)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | oui (formule custom) |
| `MAX_TILES_PER_TICK` | 400 | 56 | **non** |
| `DEFENSE_RADIUS` | 6 | 30 | oui |
| `SAM_RANGE` / chance / CD | 34 / 0.55 / 90 | 70 / 1 / 75 | oui |
| `CITY_LEVELS[1].popCapBonus` | 900 | 50000 | oui |
| `CITY_TROOP_INCREASE` | — | 50000 | **non** |
| `FRONT_TILES_PER_CONTACT` | — | 2.4 | **non** |
| `BOAT_TROOP_RATIO` | 0.2 | 0.2 | oui |

---

## 7. Preuve tests

```
./tests/run.sh  → exit 0
Serveur : Tous les invariants tiennent.
  intentions : sequence, idempotence, rate limit OK
  intentions : schema doctrine/nuke/diplomatie, ended, file OK
  intentions : QuickChat cooldown honore
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
  factions : 18
  MAX_TILES_PER_TICK reste 56
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-followup.log`
