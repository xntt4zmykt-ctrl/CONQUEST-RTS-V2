# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 10)

Déclencheur : ouverture de la **PR #33** (`cursor/analyse-nocturne-du-codebase-c68a`) — missiles inbound, `findSeaPath` pool, specs N32–N33.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-69b4`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #33**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#33.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29/#32) : ne pas merger sur cette branche sans rebase. Les numéros N32+ feel (viewFor HUD, BOAT_LANDING_BONUS, seq, AimFront…) ne sont **pas** les N32–N35 de ce rapport. Le `tryAnnex` de cette passe **porte la recette feel N39** (BFS voisins + pool) sans le dirty carriers (feel N38) ni `settledHumans` (feel N40).

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`. `RequestSnapshot` n’est toujours jamais `FireServer` côté client (N4).

La PR #33 a bien fermé les missiles inbound et le pool BFS marin. Cette passe a **corrigé ce que #33 a manqué** — encore de l’autorité de slot recyclé, plus le BFS d’enclave déjà spécifié :

| Bug | Gravité | Statut |
|---|---|---|
| Convoi marchand inbound vs port recyclé (N32) | **P2 économie / fairness** | **corrigé** (contrat B) |
| `tryAnnex` BFS mort après `setOwner` + alloc (N21) | **P2 combat / GC** | **corrigé** (voisins défenseur + pool) |
| `retreatBoats` filtre `owner[targetTile]` courant | **P2 marine** | **ouvert** (reste de N28) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29) |
| `findSpawn` ignore splash / fallout (N33) | **P3 nucléaire** | **ouvert** |
| `syncCarriers` O(bases) / tick (N34) | **P2 perf marine** | **ouvert** |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#33 + convois inbound / tiers + poche tryAnnex / ocean abort.
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #33

**À merger** (missiles inbound + pool `findSeaPath` + specs N32–N33), sous réserve que cette passe 10 parte avec : **les convois marchands fuyaient encore au recycle de slot**, et **`tryAnnex` n’annexait aucune enclave** (seed déjà attaquant → `continue` sans voisins).

Points encore vrais après #33 :

| Claim #33 | Réalité après passe 10 |
|---|---|
| Missiles inbound annulés (contrat B) | confirmé |
| Frappe déjà visée sur un tiers conservée | confirmé |
| `findSeaPath` poolé (`buffer.fill(buf, 0, 0)`) | confirmé |
| N32 convoi inbound | **fermé ici** (contrat B) |
| N33 `findSpawn` splash / fallout | **ouvert** |
| N28 retraite après flip / `targetSlot` | **ouvert** |
| N29 `seedBeachhead` no-merge | specs only, inchangé |
| N21 `tryAnnex` alloc + BFS mort | **fermé ici** (recette feel N39) |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |
| `tryAnnex` océan = enclave terrestre | volontaire, pas un bug |

`init.server.luau` est **exclu du bundle**. Le fix `joinCooldown` n’a toujours pas de test headless.

PR #32 (feel, `e541`) ne doit pas être mergée par-dessus #16/#33 sans rebase. Son `tryAnnex` (N39) est maintenant **aussi** sur hardening ; son dirty carriers (N38) et `settledHumans` (N40) ne le sont pas.

On peut fermer #17, #18, #20, #23, #25, #27, #30, #31 et #33 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| Convois inbound | `GameState.removePlayer` | `Navy.step` tourne **avant** `stepElimination`. `removePlayer` coulait les `kind==1` (transports) et les bateaux **du** disparu, pas les `kind==2` d’autrui. Un `JoinRequest` entre deux ticks recyclait le slot, reposait un PORT sur **la même tuile**, `resolveTrade` versait l’or aux deux camps. Contrôle **avant** `setOwner` via `owner[targetTile]`. Contrat **B** : couler si la tuile visée appartenait au disparu. Pas d’or (le convoi n’est pas arrivé). Pas de malus vendeur. Convoi déjà visé sur un **tiers** : conservé. Pas de `require(Navy)` (cycle). |
| `tryAnnex` BFS + pool | `ChantierB.tryAnnex` | Appelé **après** `setOwner` : `queue = { seed }` marquait visited puis `continue` (`owner ~= defender`) sans étendre les voisins — **aucune enclave annexée**. Port de la recette feel N39 : BFS depuis les voisins défenseur du seed (si seed encore défenseur, file comme avant). Pools `annexVisitBuf` / `annexQueue` / `annexPocket`. `buffer.fill(buf, 0, 0)`. Cap poche 280 inchangé. Océan = abort (enclave terrestre). |

**Non modifié (volontaire) :** N1–N20, N22–N31 restant, reste de N28 (retraite après flip). N10.8. Cap beachheads (N5). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` / `require(Nukes)` depuis GameState. Pas de dirty carriers (N34). Pas de contrat C spawn (N33). Pas de `destSlot` sur les convois (contrat A, N35).

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
- **Comptabilité fronts** = `GameState.returnCommittedTroops` (pacte, défenseur disparu). Retraite terre = `RETREAT_LOSS`. Cote déjà nôtre = 100 %. **Transports inbound d’un disparu = 100 %** (passe 8). **Missiles inbound = annulés, or du tireur conservé** (passe 9). **Convois inbound = coulés, pas d’or** (cette passe).
- **Enclaves** = `ChantierB.tryAnnex` **après** `setOwner` : BFS depuis les voisins défenseur du seed. Océan = abort.
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients` (N26).
- **DataStore** : inchangé (N6). Éliminés : toujours pas de `Persistence.record` si `players[slot]` nil à `endMatch` (N14 / N25).
- **Require** : DAG. Pas de cycle. `Tribes` → `Bots` (export `humanTargetProtected` seulement). `Navy` → `GameState` (unidirectionnel). `Nukes` → `GameState`. `ChantierB`/`BoatFront`/`AimFront` dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).
- **BFS mer** : `visitBuf` + `parentScratch` + `queueScratch` module-level. Un seul chemin en vol à la fois (Navy n’est pas réentrant).
- **BFS annex** : `annexVisitBuf` + `annexQueue` + `annexPocket` module-level. Un seul `tryAnnex` en vol à la fois (combat n’est pas réentrant).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N33 restent ouverts** sauf N19 partiel, N21 **fermé**, N24 remplacé par N31 (**fermé**), N30–N32 **fermés**. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + le reste de N28 / N29 / N33.

---

### ISSUE-N28 — `retreatBoats` / `retreatAttack` après flip de côte (reste)

**Priorité :** P2 combat / comptabilité navale. **Partiel :** inbound `removePlayer` **fermé** en passe 8.

**Problème restant :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetSlot`. Conséquences encore vraies :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers).
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite. Distinct de N10.8 (malus allié en mer) et du fix inbound (déjà livré).

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste, trancher si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N22). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % déjà livré). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).**

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

### ISSUE-N34 — `syncCarriers` scanne toutes les bases chaque tick

**Priorité :** P2 perf marine. Reste de N20 (nested loop warships + spawn ports). Recette feel N38, **sans** AimFront.

**Problème :** `Navy.step` appelle `syncCarriers` à **10 Hz**. La fonction (1) parcourt `state.boats` pour les `kind==3`, (2) parcourt `state.buildings` à la recherche de `NAVAL_BASE` manquantes. Une base ne change qu’à `placeBuilding` / `destroyBuilding` / `transferBuilding`. Feel N38 : flag `_carriersDirty` + `carrierSeen` recyclé. Ici le scan tourne encore à vide.

**Pourquoi 20K CCU :** 18 factions × bases navales, 600 ticks/min. Distinct du pool `findSeaPath` (N31, fermé) et du nested loop warship→boat (N20 restant). Ici c’est le **réveil des porte-avions**, pas le targeting.

**Worker :**

1. Flag `state._carriersDirty = true` dans `placeBuilding` / `destroyBuilding` / `transferBuilding` **seulement** si `kind == NAVAL_BASE`. `removePlayer` détruit les bâtiments du disparu → déjà dirty via `destroyBuilding`.
2. `syncCarriers` no-op si le flag est faux (sauf premier tick / `boats` vide de carriers alors qu’une base existe — ceinture : dirty à `GameState.new` ou au premier `Navy.step`).
3. Recycle : un carrier dont `homeTile` n’a plus de base est retiré (déjà le cas). Ne pas laisser un carrier du disparu (déjà `boat.slot == slot` dans `removePlayer`).
4. Test : poser NAVAL_BASE → carrier apparaît au `Navy.step` suivant. `transferBuilding` change `boat.slot`. `destroyBuilding` retire le carrier. Un `Navy.step` sans mutation de base ne crée / ne duplique pas. Fichiers : `GameState.luau`, `Navy.luau`, `tests/simulate.luau`.

**Contraintes :** pas de `require(Navy)` depuis GameState. Ne pas porter le nested loop warships (N20 restant). Ne pas mixer avec N28 `targetSlot`. Recette feel N38 OK, **sans** `_carriersDirty` sur CITY/PORT. **N34 hardening ≠ N34 feel.**

---

### ISSUE-N35 — Convoi vs PORT détruit au combat (cap `MAX_TRADE_SHIPS`)

**Priorité :** P3 économie / congestion. Reste de N32 hors recycle.

**Problème :** N32 coule le convoi inbound au **recycle de slot**. Si le PORT d’arrivée est **détruit au combat** (`destroyBuilding` / capture) sans `removePlayer`, le `kind==2` reste en mer jusqu’à `step > #path`, puis `resolveTrade` no-op (bâtiment absent). Il occupe `MAX_TRADE_SHIPS` (24) pendant tout le transit. Pas d’or fantôme (pas de rebuild du même tick par un héritier — ça, N32 l’a fermé).

**Pourquoi 20K CCU :** late-game raids de ports + 24 slots globaux. Un camp peut saturer le cap avec des convois morts. Distinct de N23 (gold sans doctrines) et du contrat B recycle.

**Worker :**

1. Trancher **un** contrat : (A) stocker `destSlot` au spawn, `resolveTrade` exige `destination.slot == destSlot`, et `Navy.step` coule dès que `buildings[targetTile]` n’est plus un PORT ; (B) `Navy.step` coule tout `kind==2` dont le PORT d’arrivée a disparu (pas d’attente fin de path) ; (C) documenter la congestion comme volontaire.
2. Si A ou B : pas d’or. Ne pas taxer le vendeur. Ne pas recâbler N32 (recycle déjà coulé dans `removePlayer`).
3. Test : convoi A→port B, `destroyBuilding(portB)` **sans** `removePlayer`, `Navy.step`. Assert : plus de `kind==2` (A/B) **ou** commentaire + assert volontaire (C). Second test : N32 recycle toujours vert.
4. Fichiers : `Navy.luau` (`spawnTradeShips`, `Navy.step` / `resolveTrade`), `tests/simulate.luau`.

**Contraintes :** pas de `require(Navy)` depuis GameState. Ne pas toucher `TRADE_GOLD_*`. Ne pas mixer avec N28 `targetSlot` transports (champs distincts : `destSlot` convoi ≠ `targetSlot` invasion). Pas de RemoteFunction. **N35 hardening ≠ feel.**

---

## 5b. N1–N35 encore ouverts ou fermés (passes 2–10)

| ID | Titre | Prio | Note passe 10 |
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
| N14 | Humains éliminés occupent cap + firehose + **pas de Persistence.record** | P2 | **précisé en N25** |
| N15 | Heap AimFront ≠ ChantierB | P2 | `terrainMag` vs `TERRAIN_COST/2` |
| N16 | `attackLogic` scanne tous les DEF | P1 | buffer `state.defense` non lu ; O(buildings) **par tuile** capturée |
| N17 | Embargo allié + tribus auto-accept | P2 | design |
| N18 | `railIncome` HUD ≠ `deliveryValue` | P2 | snapshot niveau OK ; `links`/`stopBonus` absents du HUD |
| N19 | QuickChat 2-args target vs sequence | P3 | **partiel** : slot hors 1..48 refusé ; 2-args petit N + `needsTarget` = encore une cible |
| N20 | warships O(carriers×boats) + spawn ports | P2 | **N31 pool BFS fermé** ; **N34** extrait le sync carriers ; N20 garde nested loop |
| N21 | `tryAnnex` alloc + BFS mort | P2 | **fermé**. Océan = abort **volontaire**. **≠ N21 feel (QuickChat).** |
| N22 | `BOAT_LANDING_BONUS` jamais lu | P2 | specs only |
| N23 | Trade / Navy gold ignorent doctrine, ère, `HUMAN_GOLD_MULTIPLIER` | P2 | specs only |
| N24 | `findSeaPath` pool BFS | P2 | **fermé via N31**. **≠ N24 feel (notify fireDeployed).** |
| N25 | `checkVictory` / `stepElimination` → Persistence + cap | P2 | specs only. `Diplomacy.step` **avant** `state:step` : tout GC « disparu » dans `Diplomacy.step` rate l’élimination du même tick — les purges doivent vivre dans `removePlayer`. |
| N26 | Notify / Sfx globaux `FireAllClients` | P2 | specs only. **≠ N26 feel (SAM 100 %).** |
| N27 | Pops de frontier périmés brûlent `guard` | P2 | specs only. Ne pas compter les `continue` stale ; garder un cap brut (ex. 160). |
| N28 | `retreatBoats` après flip | P2 | **partiel** : inbound fermé passe 8 ; `targetSlot` ouvert |
| N29 | `seedBeachhead` no-merge | P2 | specs only |
| N30 | Missile inbound vs spawn recyclé | P2 | **fermé** (contrat B). Splash tiers → N33. **≠ N30 feel.** |
| N31 | Pool `findSeaPath` | P2 | **fermé** (recette feel N37, sans AimFront). **≠ N31 feel.** |
| N32 | Convoi marchand inbound | P2 | **fermé** (contrat B). PORT détruit au combat → N35. **≠ N32 feel (viewFor HUD).** |
| N33 | `findSpawn` splash / fallout | P3 | specs only. **≠ N33 feel (BOAT_LANDING_BONUS).** |
| N34 | `syncCarriers` dirty | P2 | specs only. Recette feel N38. **≠ N34 feel.** |
| N35 | Convoi vs PORT détruit au combat | P3 | specs only. Reste congestion N32. |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu (reset à `startMatch` suffit) ; disconnect mid-match = `Persistence.record(..., false)` 0 XP ; wrap `launchAttack` n’applique `AimFront.focus` que si le couple n’existait pas (renfort = pas de re-visée — feel N36). Congestion `MAX_TRADE_SHIPS` vers port détruit **sans recycle** précisée en N35.

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
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
  factions : 18
  metrics : ticks=6000 avgChanged=8.9 p95Changed=18 maxChanged=658 avgTickMs=0.29 p95TickMs=0.95
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe10.log`

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
- Missile inbound = **annulé**, pas remboursé. Convoi inbound = **coulé**, pas d’or. Frappe / convoi déjà visé sur un tiers = conservé. Splash tiers / fallout au spawn = N33. PORT détruit au combat (sans recycle) = N35.
- `findSeaPath` : pools module-level, `buffer.fill(buf, 0, 0)`, `table.clear` parent/queue. Navy n’est pas réentrant. Ne pas porter AimFront avec.
- `tryAnnex` : appelé **après** `setOwner` ; BFS depuis les voisins défenseur du seed. Océan = abort (enclave terrestre), pas un bug. Pools `annexVisitBuf` / queue / pocket, `buffer.fill(buf, 0, 0)`.
- Grâce humaine = `Bots.humanTargetProtected` (bots **et** tribus). Ne pas dupliquer une 2e courbe.
- Ne pas casser le client 34/34. `init.server` / `Persistence` exclus du bundle : extraire un helper testable ou documenter un test Studio.
- Ligne feel (#19/#22/#24/#26/#28/#29/#32) : rebase sur cette passe avant cherry-pick, sinon perte convois inbound. Le `tryAnnex` feel N39 est maintenant redondant avec N21 hardening — cherry-pick dirty carriers (N38) et `settledHumans` (N40) seulement.
