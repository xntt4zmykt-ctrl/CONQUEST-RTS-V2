# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 3)

Déclencheur : ouverture de la **PR #19** (`cursor/of-feel-parity-5b2e`) — feel OpenFront (clic, combat, prep=0, intents immédiats). Base : PR #16 (P0 IntentValidator / hash / metrics) + identité CONQUEST.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-e863`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16 / #19.

Les nightly **#17 / #18** ont déjà livré ces correctifs sur la branche P0 **sans** feel-parity. Cette passe les **reporte sur #19** (HEAD feel) et ajoute les specs nées du feel.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes et slot cible sont dérivés serveur.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**, clic gauche = attaque/spawn.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #19 (feel OpenFront)

| Claim #19 | Réalité |
|---|---|
| Intents immédiats | Oui. File + `flush` no-op en prod. Header IntentValidator était encore « tick suivant » — corrigé. |
| Prep 0 | Oui. Les gardes `combatUnlocked` terre/mer/nuke restent, mais `init.server` force `true`. Reste l’immunité nuke spawn 5 s. |
| Combat OF sans doctrine sur pertes | Oui, `ChantierB.attackLogic`. `MAX_TILES_PER_TICK=56` **toujours non lu** (`guard < 80`). |
| Clic gauche = attaque | Client `init.client.luau` ; serveur dérive le slot depuis `owner`. |

**Bugs #19 encore ouverts avant cette passe (hérités P0, non patchés sur feel) :** `removePlayer` hors `setOwner`, `stripTerritory tiles=1`, `areAllied` 1-way, `BOAT_TROOP_RATIO` mort, 9e humain, JoinRequest `ended`, `FireAllClients` vers le menu, QuickChat succès fantôme.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `removePlayer` écrit `owner` à la main | `GameState.luau` | Drift `tiles`/`border`/`coast` des voisins à la déco |
| `stripTerritory` `tiles=1` | `ChantierB.luau` | Fausse `colonizedRatio`, maxTroops, cadran pendant spawn clic |
| `areAllied` 1-way + `viewFor` | `GameState.luau`, `Diplomacy.luau` | Un camp attaque, l’autre est bloqué |
| Charge bateau `/5` vs Config 0.4 | `Navy.luau`, `Config.luau` → **0.2** | Équilibrage vivant ≠ constante |
| Cap 8 humains + cooldown Join | `init.server.luau` | 9e slot / spam MapInit |
| `JoinRequest` phase `ended` | `init.server.luau` | Spawn sur carte morte ~20 s |
| `FireAllClients` stats/unités | `init.server.luau` `fireDeployed` | Facturation Roblox × joueurs menu |
| Lobby vide / ended 10 Hz | `init.server.luau` | 1 Hz MatchUpdate |
| Hash terrain → snapshot owner | `init.client.luau` | Ne répare pas le générateur ; brûlait le quota |
| Schema doctrine / nuke / diplo | `IntentValidator.luau`, `Doctrines.isValid` | Repli silencieux / action pirate |
| Phase `ended` refuse tout | `IntentValidator.luau` | Ratio/doctrine encore mutables |
| QuickChat cooldown honoré | `IntentValidator.luau` | Succès fantôme |
| `justClaimed` avalait l’attaque | `SystemsBootstrap.luau` | Premier clic post-spawn no-op |
| Nuke `combatUnlocked` + snapshot tuiles | `Nukes.luau` | Ouverture + pertes faussées par crater |
| Cadran AFK `tiles=0` | `ChantierB.luau` | Drain d’une armée fantôme |
| Message ville « +900 » | `Buildings.luau` | Runtime = `CITY_LEVELS[1].popCapBonus` |
| Invariant `portLevels` + print usine/navale | `tests/simulate.luau` | Comptabilité or port |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore (N6), tribus vs capa (N12), fusion Config/ChantierB (N1).

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (apply immédiat) → tick : Bots/Navy/Nukes/Trade/Diplomacy → GameState.step → replicate(fireDeployed)
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom), BoatFront, AimFront, tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Réplication :** StateDelta / UnitSnapshot / BuildingDelta → déployés. MatchUpdate → tous (menu). Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready

`gh issue create` n’est pas disponible. Copier chaque bloc.

---

### ISSUE-N1 — Source unique d’équilibrage (Config vs ChantierB.apply)

**Priorité :** P1 — bloquant pour tout tuning.

**Problème :** `Config.luau` n’est pas la vérité runtime. `ChantierB.apply` écrase START_TROOPS 150→8000, GROWTH_RATE→0, MAX_TILES_PER_TICK 400→56 (**puis inutilisé**), CITY pop 900→50000, SAM_RANGE 34→70, etc.

**Pourquoi 20K CCU :** un worker qui « baisse MAX_TILES_PER_TICK » dans Config ne change rien.

**Worker :**

1. Inventaire `cfg.` dans `ChantierB.apply` vs `Config.luau` (tableau §6).
2. Déplacer les valeurs vivantes dans `Config.luau` (section Production).
3. `ChantierB.apply` no-op documenté ou supprimé.
4. Test : après `SystemsBootstrap.install()`, constantes documentées = runtime.
5. **Ne pas** retuner. Lift-and-shift. Coupler N11.

**Fichiers :** `ChantierB.luau`, `Config.luau`, `SystemsBootstrap.luau`, `tests/simulate.luau`.
**Contraintes :** server-authoritative. Ne pas casser le banc client.

---

### ISSUE-N2 — Réplication : delta `stats` + UnitSnapshot dirty

**Priorité :** P1 perf. Audience corrigée ici ; **payload** encore plein.

**Problème :** `replicate()` construit `stats` (buildPrices pour chaque slot) + snapshot bateaux/missiles chaque tick playing. `TickMetrics` ne compte que les octets **owner**.

**Worker :**

1. Instrumenter `statsBytesEstimate`, `unitSnapshotBytes`, `remoteFireCount`.
2. `buildPrices` 1 Hz ou sur dirty inflation/doctrine.
3. Flag `boatsDirty` / `missilesDirty` ; snapshot vide **au plus** 1 Hz (cleanup overlay).
4. Tests Overlay dernier navire. Garder `fireDeployed`.

**Fichiers :** `init.server.luau`, `TickMetrics.luau`, `Overlay.luau`, `tests/simulate.luau`, `tests/client.luau`.
**Contraintes :** pas de RemoteFunction. Ne pas casser l’animation d’arrivée navire.

---

### ISSUE-N3 — Timebase tick vs `os.clock()` (catch-up)

**Priorité :** P1 sim.

**Problème :** Heartbeat cap 5 steps ; si retard → accumulator = 0. `matchEndsAt` / `doctrineLockAt` / `restartAt` sont en `os.clock()`. La sim saute, le chrono réel continue.

**Worker :** tout en `state.tick`. Convertir durées en ticks. Tests : `combatUnlocked` / restart lisent le tick.
**Fichiers :** `init.server.luau`, `Config.luau`, `tests/simulate.luau`.
**Contraintes :** pas de changement d’équilibrage si le serveur tient 10 Hz.

---

### ISSUE-N4 — Resync bâtiments (`structureHash` ignoré)

**Priorité :** P1 correctness.

**Problème :** `RequestSnapshot` envoie owner + hash. Le client jette le hash. Cette passe a arrêté d’appeler snapshot sur un mismatch **terrain**. Le resync structures reste ouvert.

**Worker :** étendre snapshot bâtiments (format `flushBuildingDelta`). Client applique si hash ≠. Quota 5 s / 12 inchangé.
**Fichiers :** `Remotes.luau`, `init.server.luau`, `init.client.luau`, Overlay.

---

### ISSUE-N5 — Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER`

**Priorité :** P2 anti-exploit.

**Problème :** terre cap 2 fronts. `BoatFront.seedBeachhead` insère toujours un `Attack` `sourceTile`.

**Worker :** (A) cap global 2, (B) `MAX_BEACHHEADS`, (C) fusionner même cible. Test N+1 refuse/fusionne. Ne pas casser isolation terre/mer.

---

### ISSUE-N6 — DataStore debounce / retry / merge additif

**Priorité :** P2 persistance.

**Problème :** `Persistence.save` à chaque `record`/`release`. `UpdateAsync` + `math.max` **perd les incréments** `matches`/`xp` si deux shards écrivent. Pas de retry. `release()` drop le cache même si save a échoué. `BindToClose` synchrone.

**Pourquoi 20K CCU :** budget DataStore **univers**. 1700 shards × 8 humains.

**Worker :**

1. Debounce 5 s ; flush `BindToClose`.
2. Retry 3× backoff.
3. Merge additif testable (extraire hors DataStore — `Persistence` exclu du bundle).
4. Ne pas drop cache si save fail ; BindToClose itère le cache restant.
5. Pas de PII ; clé `player_{userId}`. Studio jouable si DataStore down.

**Fichiers :** `Persistence.luau`, éventuellement `tests/bundle.js`.

---

### ISSUE-N7 — Matchmaking 20K CCU (MemoryStore / Teleport)

**Priorité :** P2 infra (hors sim).

**Problème :** une Place = une partie. Pas de file, pas de sharding.

**Worker :** Place lobby (max 50) + Places match. MemoryStore par mode. TeleportOptions : seed, mode, UserIds. Respecter `MAX_HUMAN_PLAYERS` **et N12**. Aucune logique de combat dans le lobby.

---

### ISSUE-N8 — Combat mort vs combat vivant

**Priorité :** P2 maintenance.

**Problème :** `GameState.stepAttacks` / `stepEconomy` / `maxTroops` / `tileCost` sont remplacés à runtime. Un worker qui « corrige GameState.stepAttacks » ne change pas la prod.

**Worker :** supprimer les corps morts **ou** inliner ChantierB. Tests visent le chemin **installé**. Zéro retune.

---

### ISSUE-N9 — `stepDoomsday` O(TILE_COUNT) par faction à risque

**Priorité :** P2 perf late-game.

**Problème :** rot scan 0..40959 par joueur marqué. L’exemption AFK ne réduit pas le scan des empires sous quota.

**Worker :** liste de tuiles par slot via `setOwner`, budget K/tick. Invariant owner buffer. Ne pas scanner 40960 indices / joueur / tick.

---

### ISSUE-N11 — Câbler ou supprimer `MAX_TILES_PER_TICK`

**Priorité :** P1 honesty / perf combat.

**Problème :** apply pose 56. Combat vivant = `attackTilesPerTick * speedFactor` + `guard < 80`. Neutre : jusqu’à 100 `tilesPerTickUsed` dans `attackLogic`. ~18 factions × 2 fronts × 80 = ~2880 mutations/tick théoriques.

**Worker :** (A) `numTiles = min(..., MAX_TILES_PER_TICK)` et baisser guard, **ou** (B) supprimer la constante. Si (A) : mesurer 6000 ticks p95TickMs / maxChanged. Ne pas retuner `attackLogic`.
**Fichiers :** `ChantierB.luau`, `Config.luau`, `tests/simulate.luau`.

---

### ISSUE-N12 — Tribus vs `PUBLIC_MATCH_CAPACITY`

**Priorité :** P1 produit / perf.

**Problème :** `activateMatch` plafonne bots à 12, puis `Tribes.spawnAll(6)`. Banc : **18 factions**. HUD `maxPlayers=12` est faux.

**Worker :** (A) tribus dans le budget 12, (B) documenter 12+6=18, (C) opt-in par mode. `botsToSpawn + TRIBE_COUNT <= MAX_TOTAL_FACTIONS`. Aligner taglines GameModes. Ne pas casser spawn différé 15 s.

---

### ISSUE-N13 — Parité combat (ère / cost factor / constantes mortes)

**Priorité :** P2 équilibrage.

**Problème :** `tileCost` mort appliquait `sizeAttackFactors` (speed **et** cost) + `Eras.accumulate.defense`. Le vivant n’applique que `speedFactor`. `FRONT_TILES_PER_CONTACT`, `DEFENSE_COST_DIVISOR`, `CITY_TROOP_INCREASE` écrits, jamais lus. Buffer `defense` rempli, combat scanne tous les bunkers (O(buildings) × 80).

**Worker :** tableau constante → lue où. Décision design avant code. Ne pas mixer avec N1 sans inventaire.

---

### ISSUE-N14 — Apply immédiat vs lockstep (feel #19)

**Priorité :** P1 sim / anti-exploit.

**Problème :** `IntentValidator.enqueue` appelle `applyOne` tout de suite. Plusieurs intents dans la même frame Heartbeat voient un état **partiel** (attaque avant `stepAttacks`, build avant économie). `flush` trié (userId, seq, type) n’est jamais utilisé en prod. `MAX_PENDING_INTENTS` est dormant.

**Pourquoi 20K CCU :** burst d’intents d’un cheater 20/s = 20 mutations hors budget tick, hors ordre stable. OF lockstep = file → apply en tête de tick.

**Worker :**

1. Décision produit : (A) garder immédiat (feel) + documenter, (B) revenir au flush trié en tête de `stepOnce` **playing**.
2. Si (B) : adapter `tests/simulate.luau` (le banc #19 assert `flush==0` / ratio immédiat). Remettre `table.insert(queue)` dans `enqueue`.
3. Si (A) : retirer le code mort `flush`/`queue` ou le garder derrière un flag `Config.INTENT_DEFER_TO_TICK=false`.
4. Ne pas casser le clic spawn (`awaitingSpawn` → `claimSpawn`) ni le rate 20/s.

**Fichiers :** `IntentValidator.luau`, `init.server.luau` `stepOnce`, `tests/simulate.luau`.
**Contraintes :** server-authoritative. Ne pas casser le banc client.

---

### ISSUE-N15 — `PREPARATION_DURATION=0` vs gardes `combatUnlocked`

**Priorité :** P2 honesty.

**Problème :** feel #19 ouvre le combat au déploiement. `init.server` force `combatUnlocked=true`. Les gardes terre / mer / nuke ne tirent jamais en prod. Reste `SPAWN_NUKE_IMMUNITY=5`.

**Worker :** (A) supprimer `combatUnlocked` et ne garder que l’immunité nuke spawn, **ou** (B) restaurer une prep > 0 (hors scope feel). Documenter README. Tests existants : nuke prep pose `combatUnlocked=false` artificiellement — les garder si (B), les remplacer par l’immunité spawn si (A).

---

### ISSUE-N16 — Buffer `defense` vs scan bunkers + `findSeaPath` 40k

**Priorité :** P2 perf combat / marine.

**Problème :** `applyDefenseAura` remplit `state.defense` ; `GameState.tileCost` (mort) le lisait. `attackLogic` vivant rescane **tous** les buildings DEFENSE par tuile (jusqu’à 80× / front / tick). `Navy.findSeaPath` alloue un buffer `visited` 40960 octets **par appel** (invasion, trade, retraite).

**Worker :**

1. `attackLogic` lit `buffer.readu8(state.defense, tile)` (ou un bit posted). Tester bonus ×5/×3 inchangé.
2. Pooler `visited` sea path (bitset réutilisé, `clear` entre appels).
3. Mesurer 6000 ticks p95TickMs.

**Fichiers :** `ChantierB.luau`, `Navy.luau`, `GameState.luau` aura, `tests/simulate.luau`.
**Contraintes :** ne pas changer les tables OF de pertes. Server-authoritative.

---

### ISSUE-N10 — Divers (P3)

1. Séquence nil encore acceptée (`checkSequence`) — date de coupure.
2. README SmoothTerrain vs `RENDER_MODE=Blocks`.
3. Invariant côte inverse (fausses côtes, pas côtes manquantes).
4. Bots `decideNuke` 90 tuiles × bâtiments.
5. `pendingMode` last-writer (mode du *prochain* round).
6. `init.server` exclu du bundle — pas d’E2E JoinRequest 2 joueurs.
7. Embargo n’affecte pas `Trade.luau` (trains) — seulement `Navy.canTrade`. Décision design.
8. `BuildingDefs` description « +900 » catalogue HUD (N1).
9. Landing : 1 tuile gratuite avant beachhead (`Navy.luau` ~267). Alignement OF.
10. `GROWTH_RATE` apply=0 ; croissance live hardcodée `(troops^0.73)/4` dans ChantierB.

---

## 6. Drift Config → `ChantierB.apply` (extrait)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | formule custom |
| `MAX_TILES_PER_TICK` | 400 | 56 | **non** (`guard<80`) |
| `DEFENSE_RADIUS` | 6 | 30 | oui (scan buildings) |
| `BOAT_TROOP_RATIO` | **0.2** (cette passe) | 0.2 | **oui** (Navy) |
| `CITY_LEVELS[1].popCapBonus` | 900 | 50000 | oui |
| `PREPARATION_DURATION` | 0 | 0 | forcé true |
| `FRONT_TILES_PER_CONTACT` | — | 2.4 | **non** |
| `CITY_TROOP_INCREASE` | — | 50000 | **non** |

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
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=6.4 p95Changed=1 maxChanged=479 avgTickMs=0.36 p95TickMs=0.41
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **34/34 OK** — tous les écrans se construisent et s’exécutent sans erreur.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass3.log`
