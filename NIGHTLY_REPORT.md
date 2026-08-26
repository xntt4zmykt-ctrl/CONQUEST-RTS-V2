# CONQUEST RTS — Rapport nocturne (2026-08-26)

Déclencheur : ouverture de la **PR #16** (`cursor/p0-framework-hardening-5b2e`) — IntentValidator, hash carte, metrics.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-f89b`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready** à copier dans GitHub Issues. Aucun commentaire n’a pu être posté sur #16.

---

## 1. Verdict

Le moteur est **server-authoritative**. Les clients n’envoient que des intentions ; `IntentValidator` enfile, le tick applique, `GameState` / `Navy` / `Nukes` / `Diplomacy` mutent. **Aucun cycle de `require`.**

La PR #16 est un bon P0 (file d’intentions, hash carte, metrics, découplage `Research`). Ce run a **corrigé les trous d’autorité et de comptabilité encore ouverts**, sans toucher aux tests client (34/34 OK).

**20K CCU n’est pas un objectif de salon.** Le produit actuel est ~12 factions / salon (`PUBLIC_MATCH_CAPACITY`), 8 humains max. 20K CCU = ~1 700 serveurs identiques. Le goulot n’est pas un monde unique de 20K joueurs : c’est le **coût tick + réplication par serveur** × le **matchmaking** (MemoryStore / Teleport), encore absent.

Banc headless (`./tests/run.sh`) : **exit 0**.

- Serveur : 5 seeds + invariants + P0 + nouveaux gardes (doctrine, nuke prep, `areAllied`, `removePlayer`, `stripTerritory`, file).
- Client : 34 OK, aucun écran cassé.
- Metrics 6000 ticks : `avgChanged=8.7 p95Changed=16 maxChanged=479 avgTickMs=0.37 p95TickMs=0.66`. **`MAX_TILES_PER_TICK` vivant = 56** (override `ChantierB.apply`), pas 400 (`Config.luau`).

---

## 2. Correctifs livrés dans cette PR (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| 9e humain non refusé | `init.server.luau` `deployPlayer` | `MAX_HUMAN_PLAYERS` n’était qu’un `warn` |
| `JoinRequest` sans throttle | `init.server.luau` + `Config.JOIN_COOLDOWN_SEC` | spam RemoteEvent hors IntentValidator |
| Mode lobby last-writer | `init.server.luau` | seul le **premier** deploiement pose `activeMode` |
| Nuke pendant la prep | `Nukes.launch` | terre/mer respectaient `combatUnlocked`, pas le silo |
| `justClaimed` avalait la 1re offensive | `SystemsBootstrap` / `IntentValidator` | succès silencieux, 0 front |
| Doctrine 999 → Industrielle | `Doctrines.isValid` + enqueue | repli silencieux |
| Nuke/diplomatie hors schéma en file | `IntentValidator` | charge de file pour des intents morts |
| Ordres en phase `ended` | `IntentValidator` | doctrine/ratio encore acceptés |
| File d’intents non bornée | `Config.MAX_PENDING_INTENTS=32` | RAM si flush prend du retard |
| `areAllied` unidirectionnel | `GameState.areAllied` | un camp peut frapper, l’autre non |
| `removePlayer` saute `setOwner` | `GameState.removePlayer` | frontieres fantômes chez les survivants |
| Spawn humain `tiles=1` à 0 tuiles | `ChantierB.stripTerritory` | `colonizedRatio` / HUD faussés |
| Pertes nuke post-cratère | `Nukes.detonate` | snapshot `tilesBefore` |
| Charge bateau `/5` vs Config 0.4 | `Navy` + `Config.BOAT_TROOP_RATIO=0.2` | aligne constante et moteur (1/5 OF) |

**Non modifié (volontaire)** : `MAX_TILES_PER_TICK` (mesure d’abord, et ChantierB le fixe déjà à 56), coalescence des deltas, DataStore session lock, beachheads, snapshot bâtiments.

---

## 3. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn), BoatFront, AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas `GameState.stepAttacks` (code mort après bootstrap).
- **Carte** : buffers `terrain` / `owner` / `defense`, 256×160, seed répliquée, deltas `[u32][u8]`.
- **Réplication 10 Hz** : `StateDelta` (owner + **stats complets**), `UnitSnapshot` (bateaux+missiles **même vides**). 1 Hz : diplomatie, match, leaderstats.
- **DataStore** : `ConquestRTS_Reputation_v1` / `player_{userId}`, `UpdateAsync` + `math.max`, pas de lock, pas de debounce.

---

## 4. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible dans cette automation. Copier chaque bloc.

---

### ISSUE-N1 — Source unique d’équilibrage (Config vs ChantierB.apply)

**Priorité :** P1 — bloquant pour tout tuning 20K / playtest.

**Problème :** `ReplicatedStorage/Shared/Config.luau` n’est **pas** la vérité runtime. `ChantierB.apply(Config)` (appelé par `SystemsBootstrap.install`) écrase START_TROOPS (150→8000), GROWTH_RATE (0.012→0), MAX_TILES_PER_TICK (400→56), SAM_RANGE (34→70), SAM_INTERCEPT_CHANCE (0.55→1), DEFENSE_RADIUS (6→30), MISSILE_SPEED (1.6→14), CITY pop, etc. La PR #16 a journalisé « plafond 400 inchangé » alors que le banc imprime **56**.

**Pourquoi 20K CCU :** deux tables d’équilibrage = deux simulations. Un worker qui « baisse MAX_TILES_PER_TICK » dans Config ne change rien en prod. Un tick à 56 tuiles vs 400 change CPU, deltas, et ressenti.

**Worker :**

1. Inventaire : grep `cfg.` dans `ChantierB.apply` vs `Config.luau`. Tableau avant/après.
2. Déplacer **toutes** les valeurs vivantes dans `Config.luau` (section « Production / port OF » commentée).
3. `ChantierB.apply` ne doit plus muter Config — ou devenir un no-op documenté.
4. `SystemsBootstrap` : retirer les `or 0.2` / `or 3` morts (`BOAT_TROOP_RATIO` et `MAX_BOATS_PER_PLAYER` sont déjà dans Config).
5. Mettre à jour README (SmoothTerrain vs `RENDER_MODE=Blocks`) et le commentaire P0 de #16.
6. Test : `./tests/run.sh` ; assert `Config.MAX_TILES_PER_TICK` **après** `SystemsBootstrap.install()` égale la constante documentée.
7. **Ne pas** retuner les chiffres OF sans mesure. Juste une seule source.

**Contraintes :** ne pas changer les valeurs vivantes dans ce ticket (lift-and-shift). Server-authoritative. Ne pas casser le banc client.

---

### ISSUE-N2 — Réplication : delta `stats` + UnitSnapshot dirty

**Priorité :** P1 perf.

**Problème :** `init.server.luau` `replicate()` fait `StateDelta:FireAllClients(ownerDelta, stats)` chaque tick avec **toute** la table stats (buildPrices recalculés via `BuildingDefs.BUILDABLE` pour **chaque** slot). `UnitSnapshot:FireAllClients` même si listes identiques (commentaire : snapshot vide pour tuer les fantômes). Roblox facture **par destinataire**.

**Pourquoi 20K CCU :** 8 humains × 10 Hz × payload multi-KB. À 1 700 serveurs le CPU/egress par instance reste le multiplicateur. Mesurer avant d’élargir `PUBLIC_MATCH_CAPACITY`.

**Worker :**

1. Instrumenter dans `TickMetrics` : `statsBytesEstimate`, `unitSnapshotBytes`, `remoteFireCount` (ne pas changer `MAX_TILES_PER_TICK`).
2. Envoyer `buildPrices` seulement si inflation/doctrine a changé, ou 1 Hz.
3. Flag `boatsDirty` / `missilesDirty` ; si inchangé, skip. Envoyer un snapshot vide **au plus** 1 Hz pour le cleanup overlay.
4. Option : n’envoyer `stats[slot]` que si un champ a changé (hash par slot).
5. Tests : overlay client doit encore retirer le dernier navire (rejouer le cas « liste vide » dans `tests/client.luau` Overlay). Banc serveur : metrics présentes.
6. Fichiers : `init.server.luau`, `TickMetrics.luau`, `Overlay.luau`, `tests/simulate.luau`, `tests/client.luau`.

**Contraintes :** pas de RemoteFunction ; toujours server → client ; ne pas casser l’animation d’arrivée navire.

---

### ISSUE-N3 — Timebase tick vs `os.clock()` (catch-up)

**Priorité :** P1 sim.

**Problème :** `Heartbeat` cap 5 steps ; si `accumulator > TICK_DT*5` → **zero**. Les timers de match (`matchEndsAt`, `combatStartsAt`, `doctrineLockAt`) sont en `os.clock()`. Sous lag, la sim saute des ticks **mais le chrono réel continue** → prep/combat/victoire se désynchronisent de l’économie.

**Pourquoi 20K CCU :** un shard chargé (GC, DataStore, spike de dirty tiles) décale la sim. À 10 Hz c’est l’équilibrage entier.

**Worker :**

1. Choisir **une** timebase : tout en `state.tick` (recommandé) **ou** catch-up borné sans jeter la sim.
2. Convertir `PREPARATION_DURATION`, `MATCH_DURATION`, `DOCTRINE_CHOICE_DURATION`, `POST_MATCH_DELAY` en ticks.
3. `checkVictory` / `combatUnlocked` / `endMatch` / `restartAt` lisent `state.tick`.
4. Documenter le cap Heartbeat (5) : skip **render/replicate extra**, pas la sim, si on garde wall-clock.
5. Tests headless : avancer artificiellement l’accumulateur n’est pas possible hors Studio ; tester que `combatUnlocked` bascule à `PREPARATION_DURATION / TICK_DT` ticks.
6. Fichiers : `init.server.luau`, `Config.luau`, `tests/simulate.luau`.

**Contraintes :** pas de changement d’équilibrage visible si le serveur tient 10 Hz. Server-authoritative.

---

### ISSUE-N4 — Resync bâtiments (`structureHash` ignoré)

**Priorité :** P1 correctness.

**Problème :** `RequestSnapshot` envoie owner buffer + `structureHash()`. Le client (`init.client.luau` OwnerSnapshot) **jette** le hash (`_structureHash`) et n’applique que le owner. Après desync, territoire OK, overlay bâtiments faux jusqu’au prochain `BuildingDelta`.

**Pourquoi 20K CCU :** un spike de deltas perdus (packet drop) à 10 Hz × chunks. Resync incomplet = HUD / placement mensonger (le serveur reste vrai, UX exploitée pour se plaindre / mal cliquer).

**Worker :**

1. Étendre `OwnerSnapshot` **ou** ajouter `BuildingSnapshot` (même format que `flushBuildingDelta`).
2. Client : si hash local ≠ hash serveur, appliquer le snapshot structures.
3. Quota existant (5 s, 12/match) inchangé.
4. Tests client : handler OwnerSnapshot n’élève pas ; si possible, hash mismatch → overlay rebuild.
5. Fichiers : `Remotes.luau`, `init.server.luau`, `init.client.luau`, `WorldRenderer` / `Overlay`.

**Contraintes :** pas de logique de jeu client. Rate-limit déjà en place — ne pas l’enlever.

---

### ISSUE-N5 — Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER`

**Priorité :** P2 anti-exploit / lisibilité.

**Problème :** `GameState.launchAttack` cap 2 fronts terre. `BoatFront.seedBeachhead` insère **toujours** un `Attack` avec `sourceTile`, sans cap. N débarquements = N fronts.

**Pourquoi 20K CCU :** plus de fronts = plus de `stepAttacks` (heap par front) + plus de `attackTargets` répliqués.

**Worker :**

1. Lire `BoatFront.luau` et `Navy.luau` landing.
2. Décision design (documenter dans Config) : (A) cap global 2 y compris bateaux, (B) cap séparé `MAX_BEACHHEADS`, (C) fusionner vers un beachhead existant même cible.
3. Implémenter + message de refus.
4. Test simulate : N+1 `seedBeachhead` refuse ou fusionne.
5. Ne pas casser l’isolation terre/mer (`sourceTile ~= nil` ne fusionne pas avec un front terre) — c’est le bug Chantier 5.

---

### ISSUE-N6 — DataStore : debounce, retry, session

**Priorité :** P2 persistance.

**Problème :** `Persistence.save` à chaque `record()` et `release()`. Disconnect + fin de match + `BindToClose` = burst. Pas de retry/backoff. Pas de session MemoryStore. `matches += 1` au rage-quit. `BindToClose` synchrone sur tous les joueurs.

**Pourquoi 20K CCU :** budget DataStore **par univers**, pas par serveur. 1 700 shards × 8 humains × writes de fin de match = throttle Roblox, pertes de réputation.

**Worker :**

1. Debounce writes (ex. 5 s) ; flush immédiat sur `BindToClose`.
2. Retry 3× backoff sur `UpdateAsync` failure.
3. Ne pas double-compter : si `resultRecorded`, `release` save sans `record`. (Déjà le cas dans `onPlayerRemoving` — vérifier tous les chemins.)
4. Documenter l’absence de session lock (même user, deux serveurs, `math.max` OK pour XP, pas pour `matches` additifs). Ticket séparé si vrai lock MemoryStore.
5. Tests : le module `Persistence` est **exclu** du bundle (`tests/bundle.js` EXCLUDE). Ajouter un mini-harness avec DataStore stub **ou** extraire merge `UpdateAsync` dans une fonction pure testable.
6. Fichiers : `Persistence.luau`, `tests/bundle.js` si harness, `init.server.luau` inchangé sauf si double-save.

**Contraintes :** pas de PII ; clé `player_{userId}` uniquement. Studio doit rester jouable si DataStore down (`pcall` + cache).

---

### ISSUE-N7 — Matchmaking 20K CCU (lobby MemoryStore / Teleport)

**Priorité :** P2 infra (hors sim).

**Problème :** une Place = une partie. Pas de file d’attente, pas de sharding, pas de `TeleportService`. 20K CCU est impossible sans N instances.

**Worker (ne pas toucher la sim) :**

1. Place « lobby » (max 50) + Places « match » (12 factions).
2. MemoryStore queue par mode (`classic` / `blitz` / `marathon`).
3. TeleportOptions : seed, mode, liste UserIds. Le match Place appelle `startMatch` avec cette seed.
4. Respecter `MAX_HUMAN_PLAYERS` / `PUBLIC_MATCH_CAPACITY` (déjà enforced côté match après ce nightly).
5. Aucune logique de combat dans le lobby.

**Contraintes :** server-authoritative ; ne pas répliquer la carte, seulement seed + mapMeta.

---

### ISSUE-N8 — Combat mort vs combat vivant

**Priorité :** P2 maintenance.

**Problème :** `GameState.stepAttacks` / `stepEconomy` / `maxTroops` / `tileCost` sont remplacés à runtime par `ChantierB`. Un worker qui « corrige GameState.stepAttacks » ne change pas la prod.

**Worker :**

1. Soit supprimer les fonctions mortes et garder ChantierB comme impl, soit inliner ChantierB dans GameState et tuer le monkey-patch.
2. Tests `simulate.luau` doivent viser le chemin **installé** (`SystemsBootstrap.install()` déjà appelé en tête — garder cet ordre).
3. Commentaire d’en-tête sur chaque fonction patchée : `NOTE: overridden by ChantierB.install`.

**Contraintes :** zero changement d’équilibrage. Diff de comportement = échec.

---

### ISSUE-N9 — `stepDoomsday` O(TILE_COUNT) par faction à risque

**Priorité :** P2 perf late-game.

**Problème :** `ChantierB.luau` rot parcourt jusqu’à toute la carte par joueur marqué. Late-game = pile le moment où le tick est déjà chaud (nukes, 207 explosions mesurées / 6000 ticks).

**Worker :**

1. Maintenir une liste de tuiles par slot (incrémentale via `setOwner`) **ou** un frontier de rot.
2. Budget : max K tuiles rot / tick / faction (déjà un grain `ROT_GRAIN_SECONDS`).
3. Test invariant : tuiles rot / owner buffer.
4. Ne pas scanner 40960 indices par joueur par tick.

---

### ISSUE-N10 — Divers (P3, tickets séparés)

1. **Séquence nil encore acceptée** (`IntentValidator.checkSequence`) — compat clients stale. Plan : métrique `refuseCounts` + date de coupure ; ensuite refuser `InvalidSchema`.
2. **Marathon `botCount=16` vs `PUBLIC_MATCH_CAPACITY=12`** — le mode est silencieusement plafonné. Soit monter la capa publique, soit baisser `botCount` marathon à 12, soit `min()` documenté dans GameModes.
3. **README** parle encore de SmoothTerrain alors que `RENDER_MODE=Blocks` et `WorldBuilder` collision blocs. Alignement docs.
4. **Invariant côte inverse** : `simulate.luau` détecte fausses côtes, pas les côtes manquantes. Ajouter le check reverse après ISSUE removePlayer (déjà fixé, le check reste utile).
5. **Bots `decideNuke`** : 90 tuiles front × tous les bâtiments. Index spatial (chunk) si le tick p95 dépasse 8 ms en late-game.
6. **`pendingMode` last-writer** pendant un match (mode du *prochain* round). Décision produit : host only / vote / freeze.
7. **Tests Studio multi-clients** : le headless ne charge pas `init.server.luau` (exclu du bundle). Un test d’intégration 2 joueurs JoinRequest reste un trou.

---

## 5. Revue PR #16 (sans commentaire GitHub)

**À merger** après relecture, sous réserve du dual Config/ChantierB (N1) clairement compris : les metrics « 400 » sont celles de `Config.luau` **avant** apply, le runtime est 56.

Points forts : IntentValidator, `terrainHash` / `mapMeta`, rate-limit snapshot, `SystemsBootstrap` (Research pur, banc vert), capacité produit explicite, identité CONQUEST.

Hors scope #16 (toujours vrai) : lobby Teleport, coalescence deltas, Studio multi-client.

---

## 6. Preuve tests

```
./tests/run.sh  → exit 0
Serveur : Tous les invariants tiennent.
  intentions : sequence, idempotence, rate limit OK
  intentions : schema doctrine/nuke/diplomatie, ended, file OK
  MAX_TILES_PER_TICK reste 56
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly.log`
