# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 12)

Déclencheur : ouverture de la **PR #37** (`cursor/analyse-nocturne-du-codebase-fd1e`) — syncCarriers dirty, convoi vs PORT détruit, specs N36–N37.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-6830`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #37**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#37. Pas d’outil Slack.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29/#32/#34/#36 + fd0b passe 12) : ne pas merger sur cette branche sans rebase. Les numéros N36+ feel (AimFront, findSeaPath, seq, N46–N51…) ne sont **pas** les N36–N39 de ce rapport. Cette passe **porte** feel N42 (`bunkersBySlot`) + N45 (aura morte) + N40 (`settledHumans`). Seq obligatoire (feel N41) et inbound recycle feel N46–N48 ne sont pas portés (hardening les a déjà via passes 8–11).

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`. `RequestSnapshot` n’est toujours jamais `FireServer` côté client (N4). `MatchLifecycle` est un module pur (Config seulement) : pas de cycle GameState.

La PR #37 a bien fermé le scan carriers 10 Hz et le convoi vs PORT détruit. Cette passe a **corrigé ce que #37 a spécifié** — hot path combat + DataStore des éliminés :

| Bug | Gravité | Statut |
|---|---|---|
| `applyDefenseAura` writes mortes + scan buildings (N36) | **P1 combat / perf** | **corrigé** (`bunkersBySlot` + plus d’écritures) |
| Humains éliminés sans `Persistence.record` (N37) | **P2 DataStore** | **corrigé** (`settledHumans` + helper testable) |
| `retreatBoats` filtre `owner[targetTile]` courant | **P2 marine** | **ouvert** (reste de N28) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29) |
| `findSpawn` ignore splash / fallout (N33) | **P3 nucléaire** | **ouvert** |
| Pops de frontier périmés brûlent `guard` (N38) | **P2 combat** | **ouvert** |
| Warships O(carriers × boats) (N39) | **P2 marine / perf** | **ouvert** |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#37 + bunkersBySlot / settledHumans / aura morte.
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #37

**À merger** (dirty carriers + convoi vs PORT détruit + specs N36–N37), sous réserve que cette passe 12 parte avec : **`attackLogic` scannait encore tout le hash buildings par tuile**, et **`endMatch` ratait les humains déjà `removePlayer`**.

Points encore vrais après #37 :

| Claim #37 | Réalité après passe 12 |
|---|---|
| `syncCarriers` dirty + `carrierSeen` recyclé | confirmé |
| Convoi vs PORT détruit (contrat B) | confirmé |
| Capture de PORT = convoi continue | confirmé |
| N36 `bunkersBySlot` / aura morte | **fermé ici** (recette feel N42 + N45 Option A) |
| N37 `settledHumans` / Persistence | **fermé ici** (recette feel N40 + helper `MatchLifecycle`) |
| N33 `findSpawn` splash / fallout | **ouvert** |
| N28 retraite après flip / `targetSlot` | **ouvert** |
| N29 `seedBeachhead` no-merge | specs only, inchangé |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |

`init.server.luau` et `Persistence` restent **exclus du bundle**. Le helper `MatchLifecycle` est **dans** le bundle (37 modules serveur). Le fix `joinCooldown` n’a toujours pas de test headless.

PR #36 (feel passe 11, `9975`) ne doit pas être mergée par-dessus #16/#37 sans rebase. `bunkersBySlot` (N42) / aura morte (N45) / `settledHumans` (N40) sont maintenant **aussi** sur hardening ; seq obligatoire (N41) ne l’est pas.

On peut fermer #17, #18, #20, #23, #25, #27, #30, #31, #33, #35 et #37 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| `bunkersBySlot` + aura morte | `GameState` + `ChantierB.attackLogic` | Pose/destroy bunker écrivait un disque `radius=30` ≈ 2 800 writes **mortes** (`state.defense` jamais lu par le combat vivant). `attackLogic` re-parcourait `state.buildings` **par tuile capturée**. Index `bunkersBySlot[slot][tile]` maintenu à `placeBuilding` / `destroyBuilding` / `transferBuilding` / `removePlayer`. Capture change de panier. **Plus d’appels** `applyDefenseAura` (fonction conservée pour `tileCost` hors install). Booléen posted inchangé (`DEFENSE_POST_BONUS` ×5 / speed ×3). Recette feel N42 + N45 Option A, **sans** seq (feel N41). |
| `settledHumans` + helper | `GameState.removePlayer`, `MatchLifecycle`, `init.server` | `endMatch` itérait `slotByPlayer` puis `players[slot]`. `removePlayer` détruisait le PlayerState → pas de défaite, pas d’XP. Snapshot `{ player, betrayals, capturedTiles, capitalsCaptured, buildingsBuilt }` **avant** nil, humains seulement. `MatchLifecycle.endMatchRecords` / `experienceFor` / `lookupStats` extraits (init.server hors bundle). Disconnect vivant = toujours 0 XP (P3 distinct). Disconnect **après** élimination = snapshot + XP. Pas de double-grave (`resultRecorded`). Recette feel N40, **sans** seq. |

**Non modifié (volontaire) :** N1–N35 restant, reste de N28 (retraite après flip). N10.8. Cap beachheads (N5). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` / `require(Nukes)` depuis GameState. Pas de contrat C spawn (N33). Pas de seq obligatoire (feel N41). Nested loop warships (N39). Pops stale frontier (N38). Buffer `defense` **alloué** mais plus écrit.

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + `guard < 80`).
- **Posted bunker** = `bunkersBySlot[slot][tile]`, pas le hash `buildings` ni le buffer `defense`. Capture → `transferBuilding` change de panier.
- **Têtes de pont** = `BoatFront.seedBeachhead` : frontier = **voisins encore à la cible**, flag `isBeachhead`. `launchAttack` gare les beachheads avant fusion.
- **Retraite** = couple `(attacker, target)` : tous les fronts + `Navy.retreatBoats`.
- **Pacte vivant** = `areAllied` : deux sens **et** `tick < expiry` (ou `true` legacy tests). Bots et tribus doivent passer par là, pas `alliances[]`.
- **Proposition vivante** = `requestIsLive` (`tick < expiry`). Croisement = accept **seulement** si encore live.
- **Comptabilité fronts** = `GameState.returnCommittedTroops` (pacte, défenseur disparu). Retraite terre = `RETREAT_LOSS`. Cote déjà nôtre = 100 %. **Transports inbound d’un disparu = 100 %**. **Missiles inbound = annulés, or du tireur conservé**. **Convois inbound = coulés, pas d’or**. **Convoi vs PORT détruit = coulé, pas d’or**.
- **Enclaves** = `ChantierB.tryAnnex` **après** `setOwner` : BFS depuis les voisins défenseur du seed. Océan = abort.
- **Porte-avions** = `syncCarriers` **événementiel** (`_carriersDirty`, NAVAL_BASE seulement). Pas de scan 10 Hz.
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients` (N26).
- **DataStore** : `settledHumans` avant destruction du PlayerState. `endMatch` grave via `MatchLifecycle.endMatchRecords`. `Persistence.record` max-merge inchangé (N6).
- **Require** : DAG. Pas de cycle. `MatchLifecycle` → Config seulement. `Tribes` → `Bots` (export `humanTargetProtected` seulement). `Navy` → `GameState` (unidirectionnel). `Nukes` → `GameState`. `ChantierB`/`BoatFront`/`AimFront` dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).
- **BFS mer** : `visitBuf` + `parentScratch` + `queueScratch` module-level. Un seul chemin en vol à la fois (Navy n’est pas réentrant).
- **BFS annex** : `annexVisitBuf` + `annexQueue` + `annexPocket` module-level. Un seul `tryAnnex` en vol à la fois (combat n’est pas réentrant).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N37 restent ouverts** sauf N19 partiel, N21 **fermé**, N24 remplacé par N31 (**fermé**), N30–N32 **fermés**, N34–N37 **fermés**. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + le reste de N28 / N29 / N33.

---

### ISSUE-N28 — `retreatBoats` / `retreatAttack` après flip de côte (reste)

**Priorité :** P2 combat / comptabilité navale. **Partiel :** inbound `removePlayer` **fermé** en passe 8.

**Problème restant :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetSlot`. Conséquences encore vraies :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers).
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite. Distinct de N10.8 (malus allié en mer) et du fix inbound (déjà livré). Distinct de N35 (`destSlot` convoi ≠ `targetSlot` invasion — ne pas fusionner les champs).

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste, trancher si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N22). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % déjà livré). Ne pas recâbler N35 (convois, `kind==2`). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).**

---

### ISSUE-N29 — `seedBeachhead` ne fusionne plus le couple naval

**Priorité :** P2 combat / cap.

**Problème :** `GameState.seedBeachhead` de base fusionnait `(attacker, target)`. `BoatFront.install` **remplace** la fonction et `table.insert` toujours un nouvel `Attack` `isBeachhead`. Deux débarquements vs le même défenseur = deux fronts, pools de troupes séparés, deux consommations de debit `guard < 80`. Combiné à N5 (parking hors cap land), un joueur peut tenir 2 beachheads + 1 terre = 3 offensives alors que `MAX_ACTIVE_ATTACKS_PER_PLAYER = 2`.

**Pourquoi 20K CCU :** late-game invasions multiples. Ce n’est pas N11 (`MAX_TILES_PER_TICK` mort) ni N38 (pops stale) : ici le **nombre de tas** explose, chacun avec son `while guard < 80`.

**Worker :**

1. Confirmer le contrat OpenFront : **un** front naval par couple `(attacker, target)`, distinct du front terre. Si oui : dans `BoatFront.seedBeachhead`, trouver un `isBeachhead` existant du couple, ajouter `troops`, enfiler les nouveaux voisins, return. Si le tas est vide après enqueue, refund comme aujourd’hui.
2. Si le produit **veut** les griffes multiples : documenter dans Config, et **compter** les beachheads dans le cap (fermer N5 dans le même PR). Pas les deux à la fois.
3. Test : deux `seedBeachhead` même couple → `#attacks == 1` et `troops` somme **ou** (si multi-prong assumé) `launchAttack` refuse au-delà du cap y compris parked.
4. Fichiers : `BoatFront.luau`, éventuellement `GameState.launchAttack` / wrapper parking, `tests/simulate.luau`.

**Contraintes :** ne pas fusionner beachhead avec front terre (régression BoatFront / aim). Ne pas changer `attackTilesPerTick`. Ne pas mixer avec N28 (bateaux inbound / targetSlot). **N29 hardening ≠ N29 feel (seq avant apply).**

---

### ISSUE-N33 — `findSpawn` ignore fallout et splash d’une frappe tiers

**Priorité :** P3 nucléaire / spawn. Reste du contrat C de l’ancien N30.

**Problème :** après le contrat B (ogive visée sur le disparu **annulée**), il reste : une frappe **déjà visée sur un voisin** dont le cratère recouvre l’ancien capital / le `SPAWN_RADIUS` de `findSpawn`. `addPlayer` choisit un disque terrestre libre, sans lire `state.missiles` ni `state.fallout`. L’héritier spawn, `Nukes.step` explose, SAM de l’héritier n’existait pas au `engaged`.

**Pourquoi 20K CCU :** moins chaud que N30 (il faut un voisin sous missile + spawn coincé dans le rayon). Distinct du contrat B déjà livré.

**Worker :**

1. Ne **pas** rouvrir le contrat B. Options : (C1) `findSpawn` refuse un centre dont un missile en vol a `toIndex(floor(tx),floor(ty))` à distance `NUKE_STATS[kind].radius` (ogive : `missile.radius`) ; (C2) `findSpawn` refuse `state.fallout[index] > tick` ; (C3) documenter « le territoire, pas le joueur » pour le splash tiers.
2. Test : A tire sur C (capitale), `removePlayer(B)`, forcer le spawn de l’héritier dans le rayon (tuiles libres), `Nukes.step`. Assert selon C1/C2/C3.
3. Fichiers : `GameState.findSpawn` / `addPlayer`, éventuellement `Nukes`, `tests/simulate.luau`.

**Contraintes :** ne pas annuler une frappe tiers (régression `nuke third-party`). Ne pas rembourser l’or. Pas de RemoteFunction. Rayon lu depuis `NUKE_STATS` / `missile.radius`, pas une constante magique.

---

### ISSUE-N38 — pops de frontier périmés brûlent `guard < 80`

**Priorité :** P2 combat / debit. Fusionne / précise N27. **N38 hardening ≠ N38 feel (syncCarriers dirty — déjà sur hardening via N34).**

**Problème :** `ChantierB.stepAttacks` (install) fait `guard += 1` **avant** le test `owner[index] ~= atk.target`. Un pop dont la tuile a déjà changé de main (`continue` stale) compte quand même dans le cap 80. Late-game : heap gonflé par des voisins enfilés puis capturés par un autre front / annex / collapse → une grande part du budget 80 est du no-op, le debit `attackTilesPerTick * speedFactor` n’est pas consommé. Le cap brut reste nécessaire (anti-runaway), mais compter les `continue` stale **comme du travail** sous-utilise chaque front.

N36 a retiré le scan buildings du hot path : le prochain coût visible dans `while guard < 80` est ce gaspillage de pops.

**Pourquoi 20K CCU :** 18 factions, plusieurs fronts, `guard < 80` par front par tick. Distinct de N11 (`MAX_TILES_PER_TICK` mort — debit ailleurs) et de N29 (nombre de tas). Ici c’est le **budget d’un tas déjà créé**.

**Worker :**

1. Ne **pas** compter les `continue` stale dans `guard`. Garder un cap brut séparé (ex. 160 pops max, dont 80 captures) pour qu’un heap 100 % périmé ne boucle pas 10 000 fois.
2. Option : après N pops stale d’affilée, `break` (le heap se recale au tick suivant via enqueue des voisins frais). Documenter le contrat.
3. Test : front dont les 40 premiers pops du heap ont `owner != target`, les suivants sont valides → au moins une capture dans le tick (aujourd’hui : 40 stale + 40 captures max ; si on met 80 stale en tête, **zéro** capture). Second test : heap entièrement stale → termine sans allouer, cap brut respecté.
4. Fichiers : `ReplicatedStorage/Shared/ChantierB.luau` (`stepAttacks` installé), `tests/simulate.luau`.

**Contraintes :** ne pas câbler `MAX_TILES_PER_TICK`. Ne pas changer `attackTilesPerTick` / `attackLogic`. Ne pas mixer avec N29 beachhead. Pas de RemoteFunction. Ne pas relire `state.defense`.

---

### ISSUE-N39 — warships : nested loop O(carriers × boats) à 10 Hz

**Priorité :** P2 marine / perf. Reste de N20 après N31 (pool BFS) et N34 (dirty carriers). **N39 hardening ≠ N39 feel (tryAnnex — déjà sur hardening via N21).**

**Problème :** `Navy.step` (après `syncCarriers` événementiel) fait encore, **chaque tick**, pour chaque `KIND_CARRIER` : scan de **tous** les `state.boats` pour prioriser transport > carrier > trade dans `WARSHIP_TARGET_RANGE`. Le match headless finit à ~15 navires / 11 porte-avions (cheap). Late-game + `MAX_TRADE_SHIPS=24` + transports + carriers : nested loop à 10 Hz, plus `areAllied` par paire. `spawnTradeShips` scanne aussi **tous les PORT** chaque tick (O(ports²) candidats) — noter, ne pas fusionner dans le même PR.

N34 a retiré le scan bases à vide. Le prochain scan 10 Hz marine **inutile à vide** est ce nested targeting (inutile aussi quand 0 ennemi à portée, mais on parcourt quand même).

**Pourquoi 20K CCU :** 18 factions × bases navales × convois. Distinct de N34 (index bases) et de N31 (BFS mer). Ici c’est le **ciblage obus**.

**Worker :**

1. Trancher **un** contrat : (A) spatial hash / grilles de cellules (`WARSHIP_TARGET_RANGE=65`) rebuild si `_boatsDirty` (launch / sink / removePlayer) ; (B) early-out si 0 carrier ou 0 cible hostile, et lister les carriers une fois hors de la boucle boats ; (C) documenter le nested loop comme acceptable sous `MAX_BOATS_PER_PLAYER=6` × 18. Pas A et un changement d’équilibrage à la fois.
2. Si A ou B : test — 2 carriers + 1 transport ennemi à portée → obus comme aujourd’hui (priorité transport, `WARSHIP_TRANSPORT_DAMAGE`) ; 0 carrier → pas d’alloc ; allied skip via `areAllied` (pas la table brute).
3. Fichiers : `Navy.luau` (bloc « Shell fire »), éventuellement flag dirty sur insert/remove boats, `tests/simulate.luau`. `spawnTradeShips` O(ports) = ticket séparé, ne pas le glisser ici.

**Contraintes :** ne pas recâbler N34 (`_carriersDirty` NAVAL_BASE seulement). Ne pas toucher N10.8 / N28 `targetSlot`. Pas de RemoteFunction. `areAllied` reste la vérité (expiry). Ne pas porter AimFront.

---

## 5b. N1–N39 encore ouverts ou fermés (passes 2–12)

| ID | Titre | Prio | Note passe 12 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + `SAM_INTERCEPT_CHANCE` 0.55→1 ; clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` **jamais** `FireServer` côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | park `isBeachhead` → hors cap land ; **2 beachheads parked + 1 terre = 3** — voir N29 |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | refund + retraite `RETREAT_LOSS` alignés ; le reste du corps est mort ; `tileCost` lit encore `defense` (buffer plus écrit) |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | timers slot maintenant purgés ; le scan rot est toujours O(tuiles) |
| N10 | Divers P3 | P3 | donations gold sans plafond ; `pendingMode` last-writer ; README SmoothTerrain |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | debit = `attackTilesPerTick` × speed, `guard<80` |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 observé) | P1 | `Bots.spawnAll` wrap + `Tribes.spawnAll(6)` hors budget |
| N13 | Parité ère / cost factor `attackLogic` | P2 | doctrines oui ; `Eras.accumulate` et `sizeAttackFactors` coût **non** |
| N14 | Humains éliminés occupent cap + firehose + Persistence | P2 | **N37 fermé** (record). Cap slot / firehose encore ouverts via N25 |
| N15 | Heap AimFront ≠ ChantierB | P2 | `terrainMag` vs `TERRAIN_COST/2` |
| N16 | `attackLogic` scanne tous les DEF | P1 | **fermé via N36** |
| N17 | Embargo allié + tribus auto-accept | P2 | design |
| N18 | `railIncome` HUD ≠ `deliveryValue` | P2 | snapshot niveau OK ; `links`/`stopBonus` absents du HUD |
| N19 | QuickChat 2-args target vs sequence | P3 | **partiel** : slot hors 1..48 refusé ; 2-args petit N + `needsTarget` = encore une cible |
| N20 | warships O(carriers×boats) + spawn ports | P2 | **N31 pool BFS fermé** ; **N34 dirty fermé** ; nested targeting → **N39** ; spawnTradeShips O(ports²) reste |
| N21 | `tryAnnex` alloc + BFS mort | P2 | **fermé** (passe 10). Océan = abort **volontaire**. **≠ N21 feel (QuickChat).** |
| N22 | `BOAT_LANDING_BONUS` jamais lu | P2 | specs only |
| N23 | Trade / Navy gold ignorent doctrine, ère, `HUMAN_GOLD_MULTIPLIER` | P2 | specs only |
| N24 | `findSeaPath` pool BFS | P2 | **fermé via N31**. **≠ N24 feel (notify fireDeployed).** |
| N25 | `checkVictory` / `stepElimination` → Persistence + cap | P2 | **N37 fermé** (record). Cap humains éliminés / firehose encore ouverts. Purges « disparu » = dans `removePlayer`. |
| N26 | Notify / Sfx globaux `FireAllClients` | P2 | specs only. **≠ N26 feel (SAM 100 %).** |
| N27 | Pops de frontier périmés brûlent `guard` | P2 | **précisé en N38** |
| N28 | `retreatBoats` après flip | P2 | **partiel** : inbound fermé passe 8 ; `targetSlot` ouvert |
| N29 | `seedBeachhead` no-merge | P2 | specs only |
| N30 | Missile inbound vs spawn recyclé | P2 | **fermé** (contrat B). Splash tiers → N33. **≠ N30 feel.** |
| N31 | Pool `findSeaPath` | P2 | **fermé** (recette feel N37, sans AimFront). **≠ N31 feel.** |
| N32 | Convoi marchand inbound | P2 | **fermé** (contrat B, passe 10). PORT détruit → N35 **fermé**. **≠ N32 feel.** |
| N33 | `findSpawn` splash / fallout | P3 | specs only. **≠ N33 feel (BOAT_LANDING_BONUS).** |
| N34 | `syncCarriers` dirty | P2 | **fermé**. Recette feel N38. **≠ N34 feel.** |
| N35 | Convoi vs PORT détruit au combat | P3 | **fermé** (contrat B). Capture de PORT = convoi continue. **≠ N35 feel.** |
| N36 | `applyDefenseAura` / bunkers scan | P1 | **fermé**. Recette feel N42 + N45 Option A. **≠ N36 feel (AimFront).** |
| N37 | `settledHumans` / Persistence éliminés | P2 | **fermé**. Recette feel N40 + `MatchLifecycle`. **≠ N37 feel (findSeaPath).** |
| N38 | Pops frontier stale / `guard` | P2 | specs only. **≠ N38 feel (syncCarriers).** |
| N39 | Warships nested targeting | P2 | specs only. **≠ N39 feel (tryAnnex).** |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu (reset à `startMatch` suffit) ; disconnect mid-match **vivant** = `Persistence.record(..., false)` 0 XP (chemin distinct de N37 ; éliminé puis leave **grave** le snapshot) ; wrap `launchAttack` n’applique `AimFront.focus` que si le couple n’existait pas (renfort = pas de re-visée — feel N36). `spawnTradeShips` O(ports²) à 10 Hz après N39.

---

## 6. Drift Config → `ChantierB.apply` (extrait, inchangé)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | oui (formule custom) |
| `MAX_TILES_PER_TICK` | 400→écrit 56 | 56 | **non** |
| `RETREAT_LOSS` | 0.25 | 0.25 | oui |
| `BOAT_RETREAT_LOSS` | 0.25 | 0.25 | oui (retraite vraie seulement ; inbound disparu = 100 %) |
| `BOAT_LANDING_BONUS` | 1.35 | 1.35 | **non** (N22) |
| `SAM_INTERCEPT_CHANCE` | 0.55 | **1** | oui (100 % si à portée) |
| `CITY_LEVELS[1].popCapBonus` | 900 | 50000 | oui |
| `FRONT_TILES_PER_CONTACT` | — | 2.4 | **non** |
| `MAX_BOATS_PER_PLAYER` | 6 | 6 (`or 3` mort) | oui |
| `DEFENSE_RADIUS` | 6 | **30** | oui (`attackLogic` via bunkersBySlot) |
| `DEFENSE_STRENGTH` | 55 | 200 | **non** (buffer plus écrit) |

---

## 7. Preuve tests

```
./tests/run.sh  → exit 0
bundle server : 37 modules
Serveur : Tous les invariants tiennent.
  intentions : sequence, idempotence, rate limit OK
  intentions : schema doctrine/nuke/diplomatie, ended, file OK
  intentions : QuickChat cooldown honore
  intentions : ratio borne, QuickChat slot hors catalogue refuse
  intentions : diplomatie vers soi refusee
  refund defenseur : removePlayer rend les troupes
  refund orphelin : stepAttacks rend les troupes
  beachhead : frontier voisins, pas de remboursement
  aim reinforce : un seul front apres deux lancers
  colis snapshot : niveau au depart honore
  accept expire : proposition perimee refusee
  viewFor expiry : proposition perimee masquee
  areAllied expiry : pacte perime refuse avant step
  boat own-tile : restitution integrale, pas de malus
  removePlayer inbound : embargo, proposition et marque purges
  retraite couple : tous les fronts du meme adversaire marques
  doomsday recycle : timers cadran purges au recycle de slot
  doomsday AFK clear : timers effaces pendant strip / spawn
  trade inbound : colis purges au recycle de slot
  human grace : BOT_HUMAN_GRACE_DURATION et protection tuiles
  tribe grace : tribu n'attaque pas l'humain pendant la grace
  bot expiry ally : areAllied + request ignorent un pacte perime en table
  boat inbound : transports restitues, pas de tete de pont vs disparu
  boat attacker leave : transports de l'attaquant detruits
  request stale reverse : proposition perimee ignoree, nouvelle demande enfilee
  request live reverse : croisement vivant signe le pacte
  nuke inbound : ogive annulee, pas de remboursement, heritier intact
  nuke third-party : frappe visee sur un tiers conservee
  nuke attacker leave : missiles du tireur detruits
  findSeaPath pool : 5 tuiles, 4 appels identiques
  trade inbound : convoi coule, pas d'or a l'heritier
  trade third-party : convoi A→C conserve, or verse
  tryAnnex poche terrestre : 8 tuiles annexees, pool reutilise
  tryAnnex ocean : poche cotiere refusee
  syncCarriers dirty : pose / capture / destroy OK
  trade port-detruit : convoi coule, pas d'or
  settledHumans : snapshot humain elimine, bot ignore
  endMatch helper : elimine vu, bot ignore, pas de double-grave
  attackLogic bunkers : posted / hors rayon / capture OK
  defense aura : buffer non ecrit, index pose/destroy OK
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
  factions : 18
  metrics : ticks=6000 avgChanged=8.9 p95Changed=18 maxChanged=658 avgTickMs=0.27 p95TickMs=0.90
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe12.log`

---

## 8. Instructions worker (si reprise)

- Vérité runtime d’équilibrage = `ChantierB.apply(Config)` après `SystemsBootstrap.install()`, PAS `Config.luau` seul.
- Combat vivant = patches ChantierB, pas `GameState.stepAttacks` (sauf `returnCommittedTroops` et `retreatAttack`, partagés).
- `areAllied` = deux sens **et** expiry. Ne pas revenir à un test `~= nil`. Bots / chat / tribus : **jamais** `alliances[slot][other]` comme vérité.
- Croisement diplomatique = accept **seulement** si `requestIsLive`. Une inverse périmée s’efface et on enfile une nouvelle demande.
- `retreatAttack` = **tous** les fronts du couple. Ne pas revenir à un `return` au premier match.
- Cote déjà nôtre ≠ retraite. Allié en mer = toujours retraite 25 % (N10.8). Inbound disparu = 100 % (comme front terre).
- Purge inbound d’un slot = **dans `removePlayer`**, pas seulement dans `Diplomacy.step` (ordre : Diplomacy puis `state:step`). Inclut cadran + colis + **transports** + **missiles** + **convois kind==2** (avant `setOwner`).
- Transports : `kind == 1`. Convois : `kind == 2`. Missiles : `toIndex(floor(tx), floor(ty))` vs `owner` **avant** `setOwner`. Ne pas `require(Navy)` / `require(Nukes)` depuis GameState (cycle).
- Missile inbound = **annulé**, pas remboursé. Convoi inbound = **coulé**, pas d’or. Convoi vs PORT **détruit** (combat, pas recycle) = **coulé** dans `Navy.step` (contrat B). Capture de PORT = convoi continue. Frappe / convoi déjà visé sur un tiers = conservé. Splash tiers / fallout au spawn = N33.
- `findSeaPath` : pools module-level, `buffer.fill(buf, 0, 0)`, `table.clear` parent/queue. Navy n’est pas réentrant. Ne pas porter AimFront avec.
- `tryAnnex` : appelé **après** `setOwner` ; BFS depuis les voisins défenseur du seed. Océan = abort (enclave terrestre), pas un bug. Pools `annexVisitBuf` / queue / pocket, `buffer.fill(buf, 0, 0)`.
- `syncCarriers` : `_carriersDirty` NAVAL_BASE seulement (`placeBuilding` / `destroyBuilding` / `transferBuilding`). `carrierSeen` recyclé. Pas de scan 10 Hz. Pas de dirty CITY/PORT.
- Posted bunker : `bunkersBySlot[slot][tile]`. `placeBuilding` / `destroyBuilding` / `transferBuilding` / `removePlayer` maintiennent l’index. `attackLogic` itère `bunkersBySlot[defender.slot]`. Plus d’appels `applyDefenseAura`. Buffer `defense` alloué, plus écrit. Ne pas changer `DEFENSE_POST_BONUS`.
- Humain éliminé : `settledHumans[slot]` **avant** destruction du PlayerState. Bots ignorés. `endMatch` / disconnect après élimination passent par `MatchLifecycle` (init.server hors bundle). Disconnect **vivant** = 0 XP. `Persistence` reste hors du tick. Ne pas recâbler N6.
- Grâce humaine = `Bots.humanTargetProtected` (bots **et** tribus). Ne pas dupliquer une 2e courbe.
- Ne pas casser le client 34/34. `init.server` / `Persistence` exclus du bundle : extraire un helper testable (`MatchLifecycle` déjà là) ou documenter un test Studio.
- Ligne feel (#19/#22/#24/#26/#28/#29/#32/#34/#36) : rebase sur cette passe avant cherry-pick, sinon perte convois inbound / dirty carriers / bunkersBySlot. Cherry-pick seq obligatoire (N41) seulement — N40/N42/N45 feel sont maintenant redondants avec N36 / N37 hardening.
