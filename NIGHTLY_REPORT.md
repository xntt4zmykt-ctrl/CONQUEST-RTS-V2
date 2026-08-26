# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 13)

Déclencheur : ouverture de la **PR #40** (`cursor/analyse-nocturne-du-codebase-6830`) — bunkersBySlot, settledHumans, specs N38–N39.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-9f25`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #40**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#40. Pas d’outil Slack.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29/#32/#34/#36 + fd0b + d425 passe 13) : ne pas merger sur cette branche sans rebase. Les numéros N38+ feel (syncCarriers, tryAnnex, seq, N49–N54…) ne sont **pas** les N38–N41 de ce rapport. Cette passe **ferme** hardening N38 (pops stale / `guard`) et N39 (ciblage warships, contrat B). Seq obligatoire (feel N41) et `targetSlot` (feel N49) ne sont pas portés.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`. `RequestSnapshot` n’est toujours jamais `FireServer` côté client (N4).

La PR #40 a bien fermé le scan buildings du hot path combat et le DataStore des éliminés. Cette passe a **corrigé ce que #40 a spécifié** — debit de front et nested targeting marine :

| Bug | Gravité | Statut |
|---|---|---|
| Pops frontier périmés brûlent `guard < 80` (N38) | **P2 combat / debit** | **corrigé** (`captures` vs `pops`, cap 80/160) |
| Warships O(carriers × boats) à 10 Hz (N39) | **P2 marine / perf** | **corrigé** (contrat B : listes recyclées + early-out) |
| `retreatBoats` filtre `owner[targetTile]` courant | **P2 marine** | **ouvert** (reste de N28 ; feel d425 a la recette) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29) |
| `findSpawn` ignore splash / fallout (N33) | **P3 nucléaire** | **ouvert** (feel d425 a C1+C2) |
| `spawnTradeShips` O(ports²) (N40) | **P2 marine / perf** | **ouvert** |
| `attackLogic` scan bunkers par capture (N41) | **P2 combat / perf** | **ouvert** |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#40 + pops stale / cap brut + warships fire/empty/ally.
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #40

**À merger** (bunkersBySlot + aura morte + settledHumans + specs N38–N39), sous réserve que cette passe 13 parte avec : **les pops stale comptaient dans `guard < 80`**, et **chaque carrier rescannait tout `state.boats` à 10 Hz**.

Points encore vrais après #40 :

| Claim #40 | Réalité après passe 13 |
|---|---|
| `bunkersBySlot` + plus d’écritures `applyDefenseAura` | confirmé |
| `settledHumans` + helper `MatchLifecycle` | confirmé |
| N38 pops stale / `guard` | **fermé ici** |
| N39 warships nested targeting | **fermé ici** (contrat B, pas de spatial hash) |
| N33 `findSpawn` splash / fallout | **ouvert** |
| N28 retraite après flip / `targetSlot` | **ouvert** |
| N29 `seedBeachhead` no-merge | specs only, inchangé |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |

`init.server.luau` et `Persistence` restent **exclus du bundle**. Le helper `MatchLifecycle` est **dans** le bundle (37 modules serveur). Le fix `joinCooldown` n’a toujours pas de test headless.

PR #38 (feel passe 13, `d425`) ne doit pas être mergée par-dessus #16/#40 sans rebase. `targetSlot` (N49) / `findSpawn` C1+C2 (N50) / convoi vs PORT (N51) sont sur feel seulement ; N51 hardening était déjà sur fd1e.

On peut fermer #17, #18, #20, #23, #25, #27, #30, #31, #33, #35, #37 et #40 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| Pops stale hors budget captures | `ChantierB.stepAttacks` (install) | `guard += 1` **avant** `owner[index] ~= target` : 80 voisins déjà pris en tête = **zéro capture** alors que le debit `attackTilesPerTick` n’est pas consommé. Désormais `captures` (max 80) ne compte que les tuiles encore à la cible ; `pops` (max 160) borne un heap 100 % périmé. `attackTilesPerTick` / `attackLogic` inchangés. Pas de `MAX_TILES_PER_TICK`. |
| Ciblage warships contrat B | `Navy.stepCarriers` | Nested loop `state.boats × state.boats` à 10 Hz + `areAllied` par paire. Une passe remplit `carrierBuf` / `targetBuf` (pools module-level) ; early-out si 0 carrier ou 0 bateau d’un autre slot. Priorité transport > carrier > trade, `WARSHIP_TRANSPORT_DAMAGE`, skip `areAllied` : **inchangés**. Pas de spatial hash (contrat A). Pas de dirty boats. `spawnTradeShips` O(ports) laissé à N40. |

**Non modifié (volontaire) :** N1–N37 restant, reste de N28 (`targetSlot`). N10.8. Cap beachheads (N5 / N29). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` / `require(Nukes)` depuis GameState. Pas de contrat C spawn (N33). Pas de seq obligatoire (feel N41). Pas de spatial hash warships. Buffer `defense` **alloué** mais plus écrit.

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + **captures < 80 et pops < 160**).
- **Posted bunker** = `bunkersBySlot[slot][tile]`, pas le hash `buildings` ni le buffer `defense`. Capture → `transferBuilding` change de panier.
- **Têtes de pont** = `BoatFront.seedBeachhead` : frontier = **voisins encore à la cible**, flag `isBeachhead`. `launchAttack` gare les beachheads avant fusion.
- **Retraite** = couple `(attacker, target)` : tous les fronts + `Navy.retreatBoats`.
- **Pacte vivant** = `areAllied` : deux sens **et** `tick < expiry` (ou `true` legacy tests). Bots et tribus doivent passer par là, pas `alliances[]`.
- **Proposition vivante** = `requestIsLive` (`tick < expiry`). Croisement = accept **seulement** si encore live.
- **Comptabilité fronts** = `GameState.returnCommittedTroops` (pacte, défenseur disparu). Retraite terre = `RETREAT_LOSS`. Cote déjà nôtre = 100 %. **Transports inbound d’un disparu = 100 %**. **Missiles inbound = annulés, or du tireur conservé**. **Convois inbound = coulés, pas d’or**. **Convoi vs PORT détruit = coulé, pas d’or**.
- **Enclaves** = `ChantierB.tryAnnex` **après** `setOwner` : BFS depuis les voisins défenseur du seed. Océan = abort.
- **Porte-avions** = `syncCarriers` **événementiel** (`_carriersDirty`, NAVAL_BASE seulement). Ciblage obus = listes recyclées (N39), pas nested sur tout `state.boats`.
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients` (N26).
- **DataStore** : `settledHumans` avant destruction du PlayerState. `endMatch` grave via `MatchLifecycle.endMatchRecords`. `Persistence.record` max-merge inchangé (N6).
- **Require** : DAG. Pas de cycle. `MatchLifecycle` → Config seulement. `Tribes` → `Bots` (export `humanTargetProtected` seulement). `Navy` → `GameState` (unidirectionnel). `Nukes` → `GameState`. `ChantierB`/`BoatFront`/`AimFront` dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).
- **BFS mer** : `visitBuf` + `parentScratch` + `queueScratch` module-level. Un seul chemin en vol à la fois (Navy n’est pas réentrant).
- **BFS annex** : `annexVisitBuf` + `annexQueue` + `annexPocket` module-level. Un seul `tryAnnex` en vol à la fois (combat n’est pas réentrant).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N41 restent ouverts** sauf N19 partiel, N21 **fermé**, N24 remplacé par N31 (**fermé**), N30–N32 **fermés**, N34–N39 **fermés**. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + le reste de N28 / N29 / N33.

---

### ISSUE-N28 — `retreatBoats` / `retreatAttack` après flip de côte (reste)

**Priorité :** P2 combat / comptabilité navale. **Partiel :** inbound `removePlayer` **fermé** en passe 8.

**Problème restant :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetSlot`. Conséquences encore vraies :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers).
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

Feel d425 (N49) a déjà la recette : `launchInvasion` pose `targetSlot`, `retreatBoats` filtre l’intention (fallback `owner[targetTile]`), wrap 2e geste rappelle les tardifs. **Porter, ne pas réinventer.** Distinct de N10.8 et du fix inbound. Distinct de N35 (`destSlot` convoi ≠ `targetSlot` invasion).

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite.

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste, trancher si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`. Recette feel : branche `d425` / PR feel passe 13.

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N22). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % déjà livré). Ne pas recâbler N35 (convois, `kind==2`). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).** Ne pas porter AimFront ni seq.

---

### ISSUE-N29 — `seedBeachhead` ne fusionne plus le couple naval

**Priorité :** P2 combat / cap.

**Problème :** `GameState.seedBeachhead` de base fusionnait `(attacker, target)`. `BoatFront.install` **remplace** la fonction et `table.insert` toujours un nouvel `Attack` `isBeachhead`. Deux débarquements vs le même défenseur = deux fronts, pools de troupes séparés, deux consommations de debit `captures < 80`. Combiné à N5 (parking hors cap land), un joueur peut tenir 2 beachheads + 1 terre = 3 offensives alors que `MAX_ACTIVE_ATTACKS_PER_PLAYER = 2`.

**Pourquoi 20K CCU :** late-game invasions multiples. Ce n’est pas N11 (`MAX_TILES_PER_TICK` mort) ni N38 (pops stale, **fermé**) : ici le **nombre de tas** explose, chacun avec son `while captures < 80`.

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

Feel d425 (N50) a C1+C2 : `findSpawn` refuse un centre sous ogive en vol (`NUKE_STATS[kind].radius` / `missile.radius`) **et** `state.fallout[index] > tick`. **Porter, ne pas réinventer.** Contrat B (N30) déjà livré ici : ne pas l’ouvrir.

**Pourquoi 20K CCU :** moins chaud que N30 (il faut un voisin sous missile + spawn coincé dans le rayon).

**Worker :**

1. Ne **pas** rouvrir le contrat B. Options : (C1) `findSpawn` refuse un centre dont un missile en vol a `toIndex(floor(tx),floor(ty))` à distance `NUKE_STATS[kind].radius` (ogive : `missile.radius`) ; (C2) `findSpawn` refuse `state.fallout[index] > tick` ; (C3) documenter « le territoire, pas le joueur » pour le splash tiers. Feel a choisi C1+C2.
2. Test : A tire sur C (capitale), `removePlayer(B)`, forcer le spawn de l’héritier dans le rayon (tuiles libres), `Nukes.step`. Assert selon C1/C2/C3.
3. Fichiers : `GameState.findSpawn` / `addPlayer`, éventuellement `Nukes`, `tests/simulate.luau`. Recette feel : branche `d425`.

**Contraintes :** ne pas annuler une frappe tiers (régression `nuke third-party`). Ne pas rembourser l’or. Pas de RemoteFunction. Rayon lu depuis `NUKE_STATS` / `missile.radius`, pas une constante magique.

---

### ISSUE-N40 — `spawnTradeShips` O(ports²) + alloc à chaque vague

**Priorité :** P2 marine / perf. Reste de N20 / N39 après dirty carriers et listes warships. **N40 hardening ≠ N40 feel (settledHumans — déjà sur hardening via N37).**

**Problème :** `Navy.step` appelle `spawnTradeShips` quand `tick % TRADE_SHIP_INTERVAL == 0` (45 ticks, **y compris tick 0**). Chaque vague :

1. Alloue une table `ports` et parcourt **tout** `state.buildings`.
2. Pour **chaque** PORT source : alloue `candidates`, boucle **tous** les PORT, répète `level` fois `table.insert` (poids), puis `findSeaPath` (poolé, OK).
3. `canTrade` ne lit que les embargos — pas `areAllied` (voulu : le commerce OF traverse la guerre). N17 (embargo allié) est un autre ticket.

N39 a retiré le nested targeting à vide. Le prochain scan marine **allocataire** à cadence fixe est cette vague. Late-game : 18 factions × plusieurs PORT, `MAX_TRADE_SHIPS=24` souvent saturé → on paie O(ports²) pour un early-out `afloat >= 24` **après** avoir déjà construit `ports` et trié.

**Pourquoi 20K CCU :** 18 factions, vagues toutes les 4,5 s, plus `findSeaPath` si un candidat est tiré. Distinct de N39 (obus) et de N34 (index bases). Ici c’est le **spawn commercial**.

**Worker :**

1. Trancher **un** contrat : (A) early-out si `countTradeShips >= MAX_TRADE_SHIPS` **avant** d’allouer `ports` ; garder une liste `portsBySlot` dirty comme `_carriersDirty` (pose/destroy/transfer PORT seulement) ; (B) réutiliser un `portsBuf` / `candidateBuf` module-level (`table.clear`) sans changer la loi de tirage ; (C) documenter O(ports²) comme acceptable sous un cap `MAX_PORTS` à écrire. Pas A+changement d’équilibrage (`TRADE_SHIP_CHANCE`, gold) à la fois.
2. Si A ou B : test — 2 PORT reliés en mer, `tick % 45 == 0`, un convoi peut partir (rng forcé) ; 0 PORT → pas d’alloc visible / early-out ; `MAX_TRADE_SHIPS` saturé → pas de 25e bateau, pas de hang. Capture de PORT (N35) : le convoi en mer continue.
3. Fichiers : `Navy.luau` (`spawnTradeShips`, éventuellement dirty PORT dans `GameState.placeBuilding` / `destroyBuilding` / `transferBuilding`), `tests/simulate.luau`. Ne pas glisser le spatial hash warships (contrat A de N39, volontairement non fait).

**Contraintes :** ne pas recâbler N34 (`_carriersDirty` NAVAL_BASE seulement — un dirty PORT est un **autre** flag). Ne pas toucher N10.8 / N28 `targetSlot`. Pas de RemoteFunction. `canTrade` reste embargo-only (N17 à part). Ne pas porter AimFront. `findSeaPath` reste poolé.

---

### ISSUE-N41 — `attackLogic` scanne tous les bunkers du défenseur **par capture**

**Priorité :** P2 combat / perf. Suite de N36 (index par camp) + N38 (pops stale hors debit). **N41 hardening ≠ N41 feel (sequence playing obligatoire — pas sur cette ligne).**

**Problème :** `ChantierB.attackLogic` itère `bunkersBySlot[defender.slot]` **pour chaque tuile capturée** afin de savoir si un bunker est dans `DEFENSE_RADIUS` (30 après apply). Posted = booléen (`DEFENSE_POST_BONUS` ×5 / speed ×3) : dès qu’**un** bunker est dans le disque, on s’arrête. Late-game : 80 captures × N bunkers × `fromIndex` + dist². N36 a retiré le scan du hash `buildings` global ; N38 a cessé de payer le debit sur les pops stale. Le prochain coût dans le `while captures < 80` est ce scan linéaire.

Ce n’est **pas** le buffer `defense` (plus écrit, plus lu par le combat vivant). Ce n’est pas N16 (fermé via N36).

**Pourquoi 20K CCU :** 18 factions, plusieurs fronts, 80 captures/front/tick. Un camp qui spam bunker (rayon 30 ≈ 2 800 tuiles de couverture) allonge **chaque** capture.

**Worker :**

1. Trancher **un** contrat : (A) grille spatiale `cell = DEFENSE_RADIUS` (ou 16), rebuild dirty à `placeBuilding` / `destroyBuilding` / `transferBuilding` / `removePlayer` DEFENSE seulement — lookup O(9 cellules) par capture ; (B) early-out si `bunkersBySlot[def] == nil` ou table vide (déjà vrai) **et** casser la boucle dès le premier hit (déjà vrai) + documenter le linéaire comme OK sous un cap `MAX_BUNKERS_PER_PLAYER` à écrire ; (C) précompute un set `postedTiles[def][index]=true` au dirty (disque raster) pour un lookup O(1) — attention mémoire (rayon 30). Pas A et un changement d’équilibrage (`DEFENSE_RADIUS` / `DEFENSE_POST_BONUS`) à la fois.
2. Si A ou C : réutiliser les tests `attackLogic bunkers` (posted / hors rayon / capture change de panier). Ajouter : 0 bunker → pas de posted ; 2 bunkers dont un hors rayon → posted si l’autre couvre. Ne pas relire `state.defense`.
3. Fichiers : `ReplicatedStorage/Shared/ChantierB.luau` (`attackLogic`) + éventuellement l’index dans `GameState` (déjà `bunkersBySlot`), `tests/simulate.luau`.

**Contraintes :** ne pas réintroduire `applyDefenseAura` writes. Ne pas câbler `MAX_TILES_PER_TICK`. Ne pas changer `DEFENSE_POST_BONUS` / `DEFENSE_POST_SPEED_BONUS`. Posted reste un **booléen**, pas un stack. Pas de RemoteFunction. Ne pas mixer avec N29 beachhead. Seq obligatoire = feel N41, **pas ici**.

---

## 5b. N1–N41 encore ouverts ou fermés (passes 2–13)

| ID | Titre | Prio | Note passe 13 |
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
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | debit = `attackTilesPerTick` × speed, **captures<80 pops<160** |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 observé) | P1 | `Bots.spawnAll` wrap + `Tribes.spawnAll(6)` hors budget |
| N13 | Parité ère / cost factor `attackLogic` | P2 | doctrines oui ; `Eras.accumulate` et `sizeAttackFactors` coût **non** |
| N14 | Humains éliminés occupent cap + firehose + Persistence | P2 | **N37 fermé** (record). Cap slot / firehose encore ouverts via N25 |
| N15 | Heap AimFront ≠ ChantierB | P2 | `terrainMag` vs `TERRAIN_COST/2` |
| N16 | `attackLogic` scanne tous les DEF | P1 | **fermé via N36** ; scan **par camp par capture** → **N41** |
| N17 | Embargo allié + tribus auto-accept | P2 | design |
| N18 | `railIncome` HUD ≠ `deliveryValue` | P2 | snapshot niveau OK ; `links`/`stopBonus` absents du HUD |
| N19 | QuickChat 2-args target vs sequence | P3 | **partiel** : slot hors 1..48 refusé ; 2-args petit N + `needsTarget` = encore une cible |
| N20 | warships O(carriers×boats) + spawn ports | P2 | **N31 pool BFS fermé** ; **N34 dirty fermé** ; **N39 nested targeting fermé** ; spawnTradeShips O(ports²) → **N40** |
| N21 | `tryAnnex` alloc + BFS mort | P2 | **fermé** (passe 10). Océan = abort **volontaire**. **≠ N21 feel (QuickChat).** |
| N22 | `BOAT_LANDING_BONUS` jamais lu | P2 | specs only |
| N23 | Trade / Navy gold ignorent doctrine, ère, `HUMAN_GOLD_MULTIPLIER` | P2 | specs only |
| N24 | `findSeaPath` pool BFS | P2 | **fermé via N31**. **≠ N24 feel (notify fireDeployed).** |
| N25 | `checkVictory` / `stepElimination` → Persistence + cap | P2 | **N37 fermé** (record). Cap humains éliminés / firehose encore ouverts. Purges « disparu » = dans `removePlayer`. |
| N26 | Notify / Sfx globaux `FireAllClients` | P2 | specs only. **≠ N26 feel (SAM 100 %).** |
| N27 | Pops de frontier périmés brûlent `guard` | P2 | **fermé via N38** |
| N28 | `retreatBoats` après flip | P2 | **partiel** : inbound fermé passe 8 ; `targetSlot` ouvert (recette feel N49) |
| N29 | `seedBeachhead` no-merge | P2 | specs only |
| N30 | Missile inbound vs spawn recyclé | P2 | **fermé** (contrat B). Splash tiers → N33. **≠ N30 feel.** |
| N31 | Pool `findSeaPath` | P2 | **fermé** (recette feel N37, sans AimFront). **≠ N31 feel.** |
| N32 | Convoi marchand inbound | P2 | **fermé** (contrat B, passe 10). PORT détruit → N35 **fermé**. **≠ N32 feel.** |
| N33 | `findSpawn` splash / fallout | P3 | specs only (recette feel N50). **≠ N33 feel (BOAT_LANDING_BONUS).** |
| N34 | `syncCarriers` dirty | P2 | **fermé**. Recette feel N38. **≠ N34 feel.** |
| N35 | Convoi vs PORT détruit au combat | P3 | **fermé** (contrat B). Capture de PORT = convoi continue. **≠ N35 feel.** |
| N36 | `applyDefenseAura` / bunkers scan | P1 | **fermé**. Recette feel N42 + N45 Option A. **≠ N36 feel (AimFront).** |
| N37 | `settledHumans` / Persistence éliminés | P2 | **fermé**. Recette feel N40 + `MatchLifecycle`. **≠ N37 feel (findSeaPath).** |
| N38 | Pops frontier stale / `guard` | P2 | **fermé**. **≠ N38 feel (syncCarriers).** |
| N39 | Warships nested targeting | P2 | **fermé** (contrat B). **≠ N39 feel (tryAnnex).** |
| N40 | `spawnTradeShips` O(ports²) | P2 | specs only. **≠ N40 feel (settledHumans).** |
| N41 | `attackLogic` bunkers par capture | P2 | specs only. **≠ N41 feel (seq obligatoire).** |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu (reset à `startMatch` suffit) ; disconnect mid-match **vivant** = `Persistence.record(..., false)` 0 XP (chemin distinct de N37 ; éliminé puis leave **grave** le snapshot) ; wrap `launchAttack` n’applique `AimFront.focus` que si le couple n’existait pas (renfort = pas de re-visée — feel N36). Spatial hash warships (contrat A de N39) volontairement non fait.

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
| `WARSHIP_TARGET_RANGE` | — | 65 | oui (N39) |

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
  pops stale : 80 tete perimee, capture dans le tick
  pops cap : heap stale 200, 160 pops, leftover 40
  warships fire : transport prioritaire, degats honores
  warships empty : 0 carrier, pas de tir
  warships ally : areAllied saute le transport
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 captures=80 pops=160
  factions : 18
  metrics : ticks=6000 avgChanged=11.1 p95Changed=27 maxChanged=479 avgTickMs=0.30 p95TickMs=0.73
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe13.log`

---

## 8. Instructions worker (si reprise)

- Vérité runtime d’équilibrage = `ChantierB.apply(Config)` après `SystemsBootstrap.install()`, PAS `Config.luau` seul.
- Combat vivant = patches ChantierB, pas `GameState.stepAttacks` (sauf `returnCommittedTroops` et `retreatAttack`, partagés).
- Debit de front = `attackTilesPerTick * speedFactor`, **captures < 80** (tuiles encore à la cible) et **pops < 160** (anti-runaway). Un `continue` stale ne compte plus comme une capture. Ne pas recâbler `guard += 1` avant le test owner.
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
- Ciblage warships : `carrierBuf` / `targetBuf` module-level, `table.clear`. Early-out si 0 carrier ou 0 autre slot. Priorité et `areAllied` inchangés. Pas de spatial hash (N39 contrat A non retenu).
- Posted bunker : `bunkersBySlot[slot][tile]`. `placeBuilding` / `destroyBuilding` / `transferBuilding` / `removePlayer` maintiennent l’index. `attackLogic` itère `bunkersBySlot[defender.slot]` **par capture** (N41). Plus d’appels `applyDefenseAura`. Buffer `defense` alloué, plus écrit. Ne pas changer `DEFENSE_POST_BONUS`.
- Humain éliminé : `settledHumans[slot]` **avant** destruction du PlayerState. Bots ignorés. `endMatch` / disconnect après élimination passent par `MatchLifecycle` (init.server hors bundle). Disconnect **vivant** = 0 XP. `Persistence` reste hors du tick. Ne pas recâbler N6.
- Grâce humaine = `Bots.humanTargetProtected` (bots **et** tribus). Ne pas dupliquer une 2e courbe.
- Ne pas casser le client 34/34. `init.server` / `Persistence` exclus du bundle : extraire un helper testable (`MatchLifecycle` déjà là) ou documenter un test Studio.
- Ligne feel (#19/#22/#24/#26/#28/#29/#32/#34/#36/#38) : rebase sur cette passe avant cherry-pick, sinon perte pops stale / listes warships. Cherry-pick seq obligatoire (N41 feel) et `targetSlot` (N49 feel) seulement — N40/N42/N45 feel sont déjà redondants avec N36 / N37 hardening. N50 feel (`findSpawn`) porte N33.
