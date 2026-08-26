# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 11)

Déclencheur : ouverture de la **PR #35** (`cursor/analyse-nocturne-du-codebase-69b4`) — convois inbound, `tryAnnex` BFS, specs N34–N35.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-fd1e`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #35**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#35.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29/#32/#34/#36) : ne pas merger sur cette branche sans rebase. Les numéros N34+ feel (areAllied, BOAT_LANDING_BONUS, AimFront, seq…) ne sont **pas** les N34–N37 de ce rapport. Le dirty carriers de cette passe **porte la recette feel N38**. Le `tryAnnex` feel N39 est déjà sur hardening (passe 10). `settledHumans` (feel N40) et `bunkersBySlot` (feel N42 / N45) ne le sont pas.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`. `RequestSnapshot` n’est toujours jamais `FireServer` côté client (N4).

La PR #35 a bien fermé les convois inbound (contrat B) et le BFS d’enclave. Cette passe a **corrigé ce que #35 a spécifié** — perf marine à vide, plus la congestion `MAX_TRADE_SHIPS` hors recycle :

| Bug | Gravité | Statut |
|---|---|---|
| `syncCarriers` O(bases) / tick (N34) | **P2 perf marine** | **corrigé** (dirty + `carrierSeen` recyclé) |
| Convoi vs PORT détruit au combat (N35) | **P3 économie / congestion** | **corrigé** (contrat B) |
| `retreatBoats` filtre `owner[targetTile]` courant | **P2 marine** | **ouvert** (reste de N28) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29) |
| `findSpawn` ignore splash / fallout (N33) | **P3 nucléaire** | **ouvert** |
| `applyDefenseAura` écrit un buffer jamais lu (N36) | **P1 combat / perf** | **ouvert** |
| Humains éliminés sans `Persistence.record` (N37) | **P2 DataStore** | **ouvert** |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#35 + dirty carriers / convoi vs PORT détruit.
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #35

**À merger** (convois inbound + BFS `tryAnnex` + specs N34–N35), sous réserve que cette passe 11 parte avec : **`syncCarriers` scannait encore toutes les bases à 10 Hz**, et **un PORT détruit au combat laissait le convoi saturer `MAX_TRADE_SHIPS`**.

Points encore vrais après #35 :

| Claim #35 | Réalité après passe 11 |
|---|---|
| Convois inbound coulés (contrat B) | confirmé |
| Convoi déjà visé sur un tiers conservé | confirmé |
| `tryAnnex` BFS voisins défenseur + pool | confirmé |
| `tryAnnex` océan = abort volontaire | confirmé |
| N34 `syncCarriers` dirty | **fermé ici** (recette feel N38) |
| N35 convoi vs PORT détruit | **fermé ici** (contrat B) |
| N33 `findSpawn` splash / fallout | **ouvert** |
| N28 retraite après flip / `targetSlot` | **ouvert** |
| N29 `seedBeachhead` no-merge | specs only, inchangé |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |

`init.server.luau` est **exclu du bundle**. Le fix `joinCooldown` n’a toujours pas de test headless. `Persistence.record` des éliminés non plus (N37).

PR #34 (feel passe 10, `350e`) et la passe 11 feel (`9975`) ne doivent pas être mergées par-dessus #16/#35 sans rebase. Le dirty carriers feel (N38) est maintenant **aussi** sur hardening ; `settledHumans` (N40), seq obligatoire (N41) et `bunkersBySlot` (N42) / N45 aura morte ne le sont pas.

On peut fermer #17, #18, #20, #23, #25, #27, #30, #31, #33 et #35 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| `syncCarriers` dirty | `GameState` + `Navy.syncCarriers` | `Navy.step` appelait `syncCarriers` à **10 Hz**. Une base ne change qu’à `placeBuilding` / `destroyBuilding` / `transferBuilding`. Flag `_carriersDirty` levé **seulement** si `kind == NAVAL_BASE`. `setOwner` capture → `transferBuilding` → dirty. `removePlayer` détruit les bases du disparu → déjà dirty. `GameState.new` part dirty (ceinture : premier tick). `carrierSeen` module-level, `table.clear`. Pas de `require(Navy)` (cycle). Recette feel N38, **sans** AimFront. |
| Convoi vs PORT détruit | `Navy.step` | N32 coulait au **recycle de slot**. Si le PORT d’arrivée est **détruit au combat** sans `removePlayer`, le `kind==2` restait en mer jusqu’à `step > #path`, `resolveTrade` no-op, slot `MAX_TRADE_SHIPS` (24) occupé. Contrat **B** : couler dès que `buildings[targetTile]` n’est plus un PORT. Pas d’or. Pas de malus vendeur. **Capture** (transfer) : le PORT existe encore, le convoi continue (or verse au nouveau camp). Pas de `destSlot` (≠ N28 `targetSlot` transports). N32 recycle inchangé. |

**Non modifié (volontaire) :** N1–N33 restant, reste de N28 (retraite après flip). N10.8. Cap beachheads (N5). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` / `require(Nukes)` depuis GameState. Pas de contrat C spawn (N33). Pas de `bunkersBySlot` (N36). Pas de `settledHumans` (N37). Nested loop warships (N20).

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + `guard < 80`).
- **Têtes de pont** = `BoatFront.seedBeachhead` : frontier = **voisins encore à la cible**, flag `isBeachhead`. `launchAttack` gare les beachheads avant fusion.
- **Retraite** = couple `(attacker, target)` : tous les fronts + `Navy.retreatBoats`.
- **Pacte vivant** = `areAllied` : deux sens **et** `tick < expiry` (ou `true` legacy tests). Bots et tribus doivent passer par là, pas `alliances[]`.
- **Proposition vivante** = `requestIsLive` (`tick < expiry`). Croisement = accept **seulement** si encore live.
- **Comptabilité fronts** = `GameState.returnCommittedTroops` (pacte, défenseur disparu). Retraite terre = `RETREAT_LOSS`. Cote déjà nôtre = 100 %. **Transports inbound d’un disparu = 100 %** (passe 8). **Missiles inbound = annulés, or du tireur conservé** (passe 9). **Convois inbound = coulés, pas d’or** (passe 10). **Convoi vs PORT détruit = coulé, pas d’or** (cette passe).
- **Enclaves** = `ChantierB.tryAnnex` **après** `setOwner` : BFS depuis les voisins défenseur du seed. Océan = abort.
- **Porte-avions** = `syncCarriers` **événementiel** (`_carriersDirty`, NAVAL_BASE seulement). Pas de scan 10 Hz.
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients` (N26).
- **DataStore** : inchangé (N6). Éliminés : toujours pas de `Persistence.record` si `players[slot]` nil à `endMatch` (N14 / N25 / **N37**).
- **Require** : DAG. Pas de cycle. `Tribes` → `Bots` (export `humanTargetProtected` seulement). `Navy` → `GameState` (unidirectionnel). `Nukes` → `GameState`. `ChantierB`/`BoatFront`/`AimFront` dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).
- **BFS mer** : `visitBuf` + `parentScratch` + `queueScratch` module-level. Un seul chemin en vol à la fois (Navy n’est pas réentrant).
- **BFS annex** : `annexVisitBuf` + `annexQueue` + `annexPocket` module-level. Un seul `tryAnnex` en vol à la fois (combat n’est pas réentrant).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N35 restent ouverts** sauf N19 partiel, N21 **fermé**, N24 remplacé par N31 (**fermé**), N30–N32 **fermés**, **N34–N35 fermés**. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + le reste de N28 / N29 / N33.

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

**Pourquoi 20K CCU :** late-game invasions multiples. Ce n’est pas N11 (`MAX_TILES_PER_TICK` mort) ni N27 (pops stale) : ici le **nombre de tas** explose, chacun avec son `while guard < 80`.

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

### ISSUE-N36 — `applyDefenseAura` écrit `state.defense` jamais lu ; `attackLogic` scanne tous les bunkers

**Priorité :** P1 combat / perf. Fusionne N16 + feel N42/N45. **N36 hardening ≠ N36 feel (AimFront figé).**

**Problème :** `GameState.applyDefenseAura` (pose / destroy bunker) écrit un disque `radius=30` dans le buffer `state.defense` (falloff, clamp 0..255). Le combat vivant **ne lit jamais** ce buffer. `ChantierB.attackLogic` re-parcourt `state.buildings` à **chaque tuile capturée**, filtre `kind==DEFENSE` et `slot==défenseur`, test distance². Conséquences :

1. Pose/destroy bunker = O(radius²) ≈ 2 800 writes **mortes** (le buffer n’alimente personne).
2. Late-game : 18 factions × N bunkers, `guard < 80` tuiles/front/tick → scan hash buildings **par tuile**, pas par bunker.
3. Le falloff écrit n’a **aucun** effet : `posted` est booléen (×5 loss, ×3 speed) dès qu’un bunker est dans le rayon, centre ou bord.

Feel N42 : index `bunkersBySlot[slot][tile]`, posted O(bunkers_défenseur), capture suit le camp. Hardening n’a pas porté ça.

**Pourquoi 20K CCU :** c’est le hot path combat. Distinct de N11 (`MAX_TILES_PER_TICK` mort — debit ailleurs) et de N27 (pops stale). Ici c’est **l’aura**, pas le debit.

**Worker :**

1. Trancher **un** contrat : (A) porter feel N42 `bunkersBySlot` — `placeBuilding`/`destroyBuilding`/`transferBuilding`/`removePlayer` maintiennent l’index, `attackLogic` itère `bunkersBySlot[defender.slot]`, **supprimer** les writes `applyDefenseAura` (ou les garder pour un HUD futur, documenté) ; (B) faire **lire** `state.defense` (falloff réel, plus de booléen) et arrêter le scan buildings — change l’équilibrage (bord de l’aura < centre) ; (C) documenter l’aura comme HUD-only et garder le scan. Pas A et B à la fois.
2. Si A : capture d’un bunker (`setOwner` → `transferBuilding`) doit changer de panier. Test : bunker défenseur dans le rayon → `posted` ; bunker attaquant / tiers → pas posted ; destroy → plus posted ; second tick sans mutation buildings → même résultat.
3. Fichiers : `GameState.luau` (`applyDefenseAura`, place/destroy/transfer), `ChantierB.attackLogic`, `tests/simulate.luau`. Recette feel N42 OK, **sans** seq obligatoire (feel N41) ni `settledHumans` (N40).

**Contraintes :** ne pas changer `DEFENSE_POST_BONUS` / `DEFENSE_POST_SPEED_BONUS` si A (même booléen). Ne pas câbler `MAX_TILES_PER_TICK`. Pas de RemoteFunction. Ne pas mixer avec N29 beachhead. Le buffer `defense` peut rester alloué (snapshot / HUD) même si le combat ne l’écrit plus.

---

### ISSUE-N37 — humains éliminés : pas de `Persistence.record` (XP / défaite)

**Priorité :** P2 DataStore / fairness. Reste de N14 / N25. Recette feel N40 `settledHumans`. **N37 hardening ≠ N37 feel (findSeaPath alloc).**

**Problème :** `endMatch` (dans `init.server`, **exclu du bundle**) itère `slotByPlayer` puis `state.players[slot]`. `removePlayer` détruit le `PlayerState`. Un humain éliminé en cours de partie n’a plus d’entrée : pas de défaite, pas d’XP, `resultRecorded` reste faux. Disconnect mid-match appelle `Persistence.record(..., false)` 0 XP — chemin différent, pas l’élimination. Feel N40 : snapshot `settledHumans[slot]` **avant** destruction, `endMatch` grave quand même.

**Pourquoi 20K CCU :** 8 humains / shard, parties 10–25 min, DataStore `UpdateAsync`. Un joueur qui meurt à 12 min n’a ni courbes ni anti-cheat XP. Distinct de N6 (debounce / merge max). `init.server` n’est pas dans le banc : sans extraire un helper, le bug reste invisible.

**Worker :**

1. Porter feel N40 : dans `removePlayer`, si `not isBot` et `player` encore attaché, copier `{ player, betrayals, capturedTiles, capitalsCaptured, … }` vers `state.settledHumans[slot]` **avant** de nil le PlayerState. Ne pas snapshot les bots.
2. `endMatch` : pour chaque humain de `slotByPlayer` **ou** `settledHumans`, appeler `Persistence.record`. Ne pas double-graver (disconnect a déjà `resultRecorded`).
3. Extraire le choix « qui grave » dans un helper testable (`MatchLifecycle` / fonction pure) : `init.server` reste hors bundle. Test : `removePlayer` humain → snapshot présent ; `removePlayer` bot → pas de snapshot ; helper `endMatch` voit l’éliminé.
4. Fichiers : `GameState.removePlayer`, `init.server.luau` (`endMatch`), éventuellement un module nouveau **sans** cycle require, `tests/simulate.luau`.

**Contraintes :** ne pas recâbler N6 (debounce DataStore). Ne pas graver les bots. Pas de RemoteFunction. Ne pas porter seq obligatoire (feel N41) ni `bunkersBySlot` (N36) dans le même PR. `Persistence` reste hors du tick.

---

## 5b. N1–N37 encore ouverts ou fermés (passes 2–11)

| ID | Titre | Prio | Note passe 11 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + `SAM_INTERCEPT_CHANCE` 0.55→1 ; clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` **jamais** `FireServer` côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | park `isBeachhead` → hors cap land ; **2 beachheads parked + 1 terre = 3** — voir N29 |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | refund + retraite `RETREAT_LOSS` alignés ; le reste du corps est mort |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | timers slot maintenant purgés ; le scan rot est toujours O(tuiles) |
| N10 | Divers P3 | P3 | donations gold sans plafond ; `pendingMode` last-writer ; README SmoothTerrain |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | debit = `attackTilesPerTick` × speed, `guard<80` |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 observé) | P1 | `Bots.spawnAll` wrap + `Tribes.spawnAll(6)` hors budget |
| N13 | Parité ère / cost factor `attackLogic` | P2 | doctrines oui ; `Eras.accumulate` et `sizeAttackFactors` coût **non** |
| N14 | Humains éliminés occupent cap + firehose + **pas de Persistence.record** | P2 | **précisé en N25 / N37** |
| N15 | Heap AimFront ≠ ChantierB | P2 | `terrainMag` vs `TERRAIN_COST/2` |
| N16 | `attackLogic` scanne tous les DEF | P1 | **précisé en N36**. Buffer `state.defense` non lu |
| N17 | Embargo allié + tribus auto-accept | P2 | design |
| N18 | `railIncome` HUD ≠ `deliveryValue` | P2 | snapshot niveau OK ; `links`/`stopBonus` absents du HUD |
| N19 | QuickChat 2-args target vs sequence | P3 | **partiel** : slot hors 1..48 refusé ; 2-args petit N + `needsTarget` = encore une cible |
| N20 | warships O(carriers×boats) + spawn ports | P2 | **N31 pool BFS fermé** ; **N34 dirty fermé** ; N20 garde nested loop targeting |
| N21 | `tryAnnex` alloc + BFS mort | P2 | **fermé** (passe 10). Océan = abort **volontaire**. **≠ N21 feel (QuickChat).** |
| N22 | `BOAT_LANDING_BONUS` jamais lu | P2 | specs only |
| N23 | Trade / Navy gold ignorent doctrine, ère, `HUMAN_GOLD_MULTIPLIER` | P2 | specs only |
| N24 | `findSeaPath` pool BFS | P2 | **fermé via N31**. **≠ N24 feel (notify fireDeployed).** |
| N25 | `checkVictory` / `stepElimination` → Persistence + cap | P2 | **précisé en N37**. `Diplomacy.step` **avant** `state:step` : tout GC « disparu » dans `Diplomacy.step` rate l’élimination du même tick — les purges doivent vivre dans `removePlayer`. |
| N26 | Notify / Sfx globaux `FireAllClients` | P2 | specs only. **≠ N26 feel (SAM 100 %).** |
| N27 | Pops de frontier périmés brûlent `guard` | P2 | specs only. Ne pas compter les `continue` stale ; garder un cap brut (ex. 160). |
| N28 | `retreatBoats` après flip | P2 | **partiel** : inbound fermé passe 8 ; `targetSlot` ouvert |
| N29 | `seedBeachhead` no-merge | P2 | specs only |
| N30 | Missile inbound vs spawn recyclé | P2 | **fermé** (contrat B). Splash tiers → N33. **≠ N30 feel.** |
| N31 | Pool `findSeaPath` | P2 | **fermé** (recette feel N37, sans AimFront). **≠ N31 feel.** |
| N32 | Convoi marchand inbound | P2 | **fermé** (contrat B, passe 10). PORT détruit → N35 **fermé ici**. **≠ N32 feel.** |
| N33 | `findSpawn` splash / fallout | P3 | specs only. **≠ N33 feel (BOAT_LANDING_BONUS).** |
| N34 | `syncCarriers` dirty | P2 | **fermé**. Recette feel N38. **≠ N34 feel.** |
| N35 | Convoi vs PORT détruit au combat | P3 | **fermé** (contrat B). Capture de PORT = convoi continue. **≠ N35 feel.** |
| N36 | `applyDefenseAura` / bunkers scan | P1 | specs only. Recette feel N42. **≠ N36 feel (AimFront).** |
| N37 | `settledHumans` / Persistence éliminés | P2 | specs only. Recette feel N40. **≠ N37 feel (findSeaPath).** |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu (reset à `startMatch` suffit) ; disconnect mid-match = `Persistence.record(..., false)` 0 XP (chemin distinct de N37) ; wrap `launchAttack` n’applique `AimFront.focus` que si le couple n’existait pas (renfort = pas de re-visée — feel N36). Nested loop warships (N20 restant) après N34.

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

---

## 7. Preuve tests

```
./tests/run.sh  → exit 0
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
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
  factions : 18
  metrics : ticks=6000 avgChanged=8.9 p95Changed=18 maxChanged=658 avgTickMs=0.28 p95TickMs=0.94
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe11.log`

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
- Grâce humaine = `Bots.humanTargetProtected` (bots **et** tribus). Ne pas dupliquer une 2e courbe.
- Ne pas casser le client 34/34. `init.server` / `Persistence` exclus du bundle : extraire un helper testable ou documenter un test Studio.
- Ligne feel (#19/#22/#24/#26/#28/#29/#32/#34) : rebase sur cette passe avant cherry-pick, sinon perte convois inbound / dirty carriers. Cherry-pick `settledHumans` (N40) et `bunkersBySlot` (N42) seulement — dirty carriers (N38) et `tryAnnex` (N39) sont maintenant redondants avec N34 / N21 hardening.
