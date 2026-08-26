# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 21)

Déclencheur : ouverture de la **PR #63** (`cursor/analyse-nocturne-du-codebase-08a1`) — `fillBlastBuf`, `snapshotBoats`, specs N52–N53.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-1e60`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #63**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#63. Pas d’outil Slack.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29/#32/#34/#36/#38/#41/#42/#45/#48/#51/#53/#56/#59/#62 + d425 + df65 + 2157 + 5c74 + e735 + 7c38 + 1fb3 + 5bf6 + 741d + **55ba passe 22**) : ne pas merger sur cette branche sans rebase. Les numéros N40+ feel (settledHumans, seq, N52–N76…) ne sont **pas** les N40–N55 de ce rapport. Cette passe **ferme** hardening N52 (`snapshotMissiles`) et N53 (`dirtyIndexBuf`). Seq obligatoire (feel N41) et `targetSlot` (feel N49/N53) ne sont pas portés. Feel 741d N71 (`missileSnapBuf`) et N72 (`dirtyIndexBuf`) sont **portés**. Feel 55ba N73 (`buildingSnapBuf`) = **N54 ici**. Feel 55ba N74 (`frontHudForReplicate`) = **N55 ici**.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`. `RequestSnapshot` n’est toujours jamais `FireServer` côté client (N4). DAG : `GameState` ne `require` ni Navy, ni Nukes, ni Trade, ni Bots.

La PR #63 a bien fermé `fillBlastBuf` (N50) et `snapshotBoats` (N51, sans `retreating`). Cette passe a **corrigé ce que #63 a spécifié** — `replicate()` allouait encore table + N payloads missiles chaque tick, et `flushOwnerDelta` allouait `indices` chaque tick :

| Bug | Gravité | Statut |
|---|---|---|
| Snapshot missiles alloué chaque tick (N52) | **P2 alloc réplication** | **corrigé** (`GameState.snapshotMissiles` + `missileSnapBuf`, recette feel N71) |
| `flushOwnerDelta` alloue `indices` chaque tick (N53) | **P3 alloc réplication** | **corrigé** (`dirtyIndexBuf`, recette feel N72) |
| `retreatBoats` filtre `owner[targetTile]` courant | **P2 marine** | **ouvert** (reste de N28 ; feel d425/df65 a la recette) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29) |
| `findSpawn` ignore splash / fallout (N33) | **P3 nucléaire** | **ouvert** (feel d425/df65 a C1+C2 + `isSpawnSafe`) |
| `flushBuildingDelta` alloue `out` + N payloads (N54) | **P3 alloc réplication** | **ouvert** (feel 741d N73) |
| `replicate()` maps HUD fronts chaque tick (N55) | **P3 alloc réplication** | **ouvert** (feel 741d N74) |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#63 + missileSnapBuf (N52) + dirtyIndexBuf (N53).
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #63

**À merger** (`fillBlastBuf` + `snapshotBoats` + specs N52–N53), sous réserve que cette passe 21 parte avec : **chaque tick allouait N payloads missiles, et `flushOwnerDelta` jetait un tableau d’indices**.

Points encore vrais après #63 :

| Claim #63 | Réalité après passe 21 |
|---|---|
| `fillBlastBuf` / `scoreBlast` (N50) | confirmé |
| `snapshotBoats` sans `retreating` (N51) | confirmé (truncate 2→1→0) |
| N52 snapshot missiles alloc | **fermé ici** (`snapshotMissiles`, Types.MissileSnapshot seulement) |
| N53 `flushOwnerDelta` `indices` | **fermé ici** (`dirtyIndexBuf`, buffer outbound neuf) |
| N33 `findSpawn` splash / fallout | **ouvert** |
| N28 retraite après flip / `targetSlot` | **ouvert** |
| N29 `seedBeachhead` no-merge | specs only, inchangé |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |

`init.server.luau` et `Persistence` restent **exclus du bundle**. Le helper `MatchLifecycle` est **dans** le bundle (37 modules serveur). `snapshotBoats` / `snapshotMissiles` / `flushOwnerDelta` sont **dans** le bundle (`GameState`). `flushBuildingDelta` alloue encore `out` inline (N54). Les maps HUD fronts (`activeAttacks` / `committedTroops` / `attackTargets`) vivent encore **inline** dans `replicate()` (hors bundle) — N55.

PR #62 (feel passe 21, `741d`) ne doit pas être mergée par-dessus #16/#63 sans rebase. `missileSnapBuf` (feel N71) et `dirtyIndexBuf` (feel N72) sont **portés** ici. Seq / `targetSlot` / hover `SpawnHint` / Overlay `retreating` restent feel-only. Feel N73/N74 → N54/N55.

On peut fermer #17, #18, #20, #23, #25, #27, #30, #31, #33, #35, #37, #40, #43, #46, #49, #52, #55, #58, #60 et #63 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| Snapshot missiles alloc 10 Hz | `GameState.snapshotMissiles`, `GameState.missileSnapBuf`, `init.server.replicate`, `tests/simulate.luau` | Extraire le helper dans le bundle (`init.server` hors tests). Recycle N inner payloads, truncate 1→0→1. Champs **uniquement** `Types.MissileSnapshot` : `id, slot, x, y, tx, ty, kind`. **Pas** de `sx` / `sy` / `progress` / `speed` / `engaged` / `warhead`. Overlay lit `tx`/`ty`, pas l’identité de table. Recette feel N71. |
| `flushOwnerDelta` `indices` 10 Hz | `GameState.flushOwnerDelta`, `GameState.dirtyIndexBuf`, `tests/simulate.luau` | Recycle `dirtyIndexBuf`. Early-out `next(dirty)==nil` → `nil` sans allouer. `buffer.create` outbound **neuf** (RemoteEvent). Format 5 octets / tuile inchangé. Recette feel N72. |

**Non modifié (volontaire) :** N1–N51 restant, reste de N28 (`targetSlot`). N10.8. Cap beachheads (N5 / N29). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` depuis GameState. Pas de contrat C spawn (N33). Pas de seq obligatoire (feel N41). Pas de spatial hash warships. Buffer `defense` **alloué** mais plus écrit. `Trade.step` `factoriesBuf` déjà recyclé (N45). `flushBuildingDelta` alloue encore `out` (N54). Maps HUD fronts encore inline `init.server` (N55). `buildPrices` 10 Hz × slots (N2). Pas de `retreating` Overlay (feel N56).

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + **captures < 80 et pops < 160**).
- **Posted bunker** = `bunkersBySlot[slot][tile]` + grille `bunkerCells[slot][cellKey]` (cell = `DEFENSE_RADIUS`). Capture → `transferBuilding` change de panier **et** de cellule. Lookup 3×3 par capture (N41).
- **Posted SAM** = `samsBySlot[slot][tile]` (N42). `tryIntercept` ne scanne plus `buildings`. `samsOf` lit le même index dans `samBuf` recyclé (N49).
- **Posted SILO** = `silosBySlot[slot][tile]` (N44). `Nukes.launch` n’itère que ce set.
- **Posted FACTORY** = `factoriesByTile[index]={slot,level}` (N45). `Trade.step` flatten depuis l’index, pas `buildings`.
- **Tous kinds** = `buildingsBySlot[slot][tile]` (N46). Bots upgrade / score nuke + collecte gares (N47). Distinct des index par kind. Score nuke = flatten une fois (N50), puis 90 `scoreBlast`.
- **Posted NAVAL_BASE** = `navalBasesBySlot[slot][tile]` (N48). `syncCarriers` spawn via l’index. Distinct de `portsByTile` (PORT) et de `buildingsBySlot` (tous kinds).
- **Cooldown bâtiments** = `coolingBuildings[index]` (N43). Unique écriture : `Buildings.armCooldown`. SAM **et** silos. `launch` continue d’appeler `armCooldown`.
- **Têtes de pont** = `BoatFront.seedBeachhead` : frontier = **voisins encore à la cible**, flag `isBeachhead`. `launchAttack` gare les beachheads avant fusion.
- **Retraite** = couple `(attacker, target)` : tous les fronts + `Navy.retreatBoats`.
- **Pacte vivant** = `areAllied` : deux sens **et** `tick < expiry` (ou `true` legacy tests). Bots et tribus doivent passer par là, pas `alliances[]`.
- **Proposition vivante** = `requestIsLive` (`tick < expiry`). Croisement = accept **seulement** si encore live.
- **Comptabilité fronts** = `GameState.returnCommittedTroops` (pacte, défenseur disparu). Retraite terre = `RETREAT_LOSS`. Cote déjà nôtre = 100 %. **Transports inbound d’un disparu = 100 %**. **Missiles inbound = annulés, or du tireur conservé**. **Convois inbound = coulés, pas d’or**. **Convoi vs PORT détruit = coulé, pas d’or**.
- **Enclaves** = `ChantierB.tryAnnex` **après** `setOwner` : BFS depuis les voisins défenseur du seed. Océan = abort.
- **Porte-avions** = `syncCarriers` **événementiel** (`_carriersDirty`, NAVAL_BASE seulement) + spawn via `navalBasesBySlot` (N48). Ciblage obus = listes recyclées (N39), pas nested sur tout `state.boats`.
- **Commerce maritime** = `portsByTile` incrémental (PORT seulement, N40). Vague plafonnée **avant** flatten. `canTrade` = embargo-only.
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients` (N26). Snapshot navires = `GameState.snapshotBoats` (`boatSnapBuf`, N51). Snapshot missiles = `GameState.snapshotMissiles` (`missileSnapBuf`, N52). Owner delta = `dirtyIndexBuf` (N53), buffer outbound **neuf**. `flushBuildingDelta` alloue encore `out` (N54). Maps HUD fronts encore inline `init.server` (N55). `buildPrices` 10 Hz × slots (N2).
- **DataStore** : `settledHumans` avant destruction du PlayerState. `endMatch` grave via `MatchLifecycle.endMatchRecords`. `Persistence.record` max-merge inchangé (N6).
- **Require** : DAG. Pas de cycle. `MatchLifecycle` → Config seulement. `Tribes` → `Bots` (export `humanTargetProtected` seulement). `Navy` → `GameState` (unidirectionnel). `Nukes` → `GameState` + `Buildings`. `Trade` → `GameState`. `Bots` → `GameState` (pas l’inverse). `ChantierB`/`BoatFront`/`AimFront` dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).
- **BFS mer** : `visitBuf` + `parentScratch` + `queueScratch` module-level. Un seul chemin en vol à la fois (Navy n’est pas réentrant).
- **BFS annex** : `annexVisitBuf` + `annexQueue` + `annexPocket` module-level. Un seul `tryAnnex` en vol à la fois (combat n’est pas réentrant).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N55 restent ouverts** sauf N19 partiel, N21 **fermé**, N24 remplacé par N31 (**fermé**), N30–N32 **fermés**, N34–N53 **fermés**. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + le reste de N28 / N29 / N33.

---

### ISSUE-N28 — `retreatBoats` / `retreatAttack` après flip de côte (reste)

**Priorité :** P2 combat / comptabilité navale. **Partiel :** inbound `removePlayer` **fermé** en passe 8.

**Problème restant :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetSlot`. Conséquences encore vraies :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers).
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

Feel d425 (N49) + df65 (N53) : `launchInvasion` pose `targetSlot`, `retreatBoats` filtre l’intention (fallback `owner[targetTile]`), wrap 2e geste rappelle les tardifs, `Navy.step` auto-retraite si `owner[targetTile] ~= targetSlot`. **Porter, ne pas réinventer.** Distinct de N10.8 et du fix inbound. Distinct de N35 (`destSlot` convoi ≠ `targetSlot` invasion). Distinct de N40 / N44–N53 (index / snapshots, **fermés**).

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite.

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste, trancher si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`. Recette feel : branche `d425` / `df65`.

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N22). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % déjà livré). Ne pas recâbler N35 (convois, `kind==2`). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).** Ne pas porter AimFront ni seq. Ne pas recâbler N50–N53 (`blastBuf` / `snapshotBoats` / `snapshotMissiles` / `dirtyIndexBuf`).

---

### ISSUE-N29 — `seedBeachhead` ne fusionne plus le couple naval

**Priorité :** P2 combat / cap.

**Problème :** `GameState.seedBeachhead` de base fusionnait `(attacker, target)`. `BoatFront.install` **remplace** la fonction et `table.insert` toujours un nouvel `Attack` `isBeachhead`. Deux débarquements vs le même défenseur = deux fronts, pools de troupes séparés, deux consommations de debit `captures < 80`. Combiné à N5 (parking hors cap land), un joueur peut tenir 2 beachheads + 1 terre = 3 offensives alors que `MAX_ACTIVE_ATTACKS_PER_PLAYER = 2`.

**Pourquoi 20K CCU :** late-game invasions multiples. Ce n’est pas N11 (`MAX_TILES_PER_TICK` mort) ni N38/N41 (debit / lookup bunker, **fermés**) : ici le **nombre de tas** explose, chacun avec son `while captures < 80`.

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

Feel d425 (N50) + df65 (N52) + 2157 (N55 isolation, ticket suivant) : `isSpawnSafe` partagé `findSpawn` / `claimSpawn`, refuse crater ogive **et** `state.fallout[index] > tick`. **Porter, ne pas réinventer.** Contrat B (N30) déjà livré ici : ne pas l’ouvrir. Isolation disque clic (feel N55) = ticket **suivant**, pas celui-ci.

**Pourquoi 20K CCU :** moins chaud que N30 (il faut un voisin sous missile + spawn coincé dans le rayon).

**Worker :**

1. Ne **pas** rouvrir le contrat B. Options : (C1) `findSpawn` refuse un centre dont un missile en vol a `toIndex(floor(tx),floor(ty))` à distance `NUKE_STATS[kind].radius` (ogive : `missile.radius`) ; (C2) `findSpawn` refuse `state.fallout[index] > tick` ; (C3) documenter « le territoire, pas le joueur » pour le splash tiers. Feel a choisi C1+C2 via `isSpawnSafe`.
2. Test : A tire sur C (capitale), `removePlayer(B)`, forcer le spawn de l’héritier dans le rayon (tuiles libres), `Nukes.step`. Assert selon C1/C2/C3.
3. Fichiers : `GameState.findSpawn` / `addPlayer`, éventuellement `Nukes`, `tests/simulate.luau`. Recette feel : branche `d425` / `df65`.

**Contraintes :** ne pas annuler une frappe tiers (régression `nuke third-party`). Ne pas rembourser l’or. Pas de RemoteFunction. Rayon lu depuis `NUKE_STATS` / `missile.radius`, pas une constante magique. Ne pas porter isolation clic (feel N55) dans le même PR. Ne pas recâbler N50–N53.

---

### ISSUE-N54 — `flushBuildingDelta` alloue `out` + N payloads chaque tick

**Priorité :** P3 alloc réplication. Suite de N53 (owner indices) **sans** toucher `dirtyIndexBuf` ni le format BuildingDelta. Distinct de N2 (`stats` / `buildPrices`), de N51/N52 (UnitSnapshot) et de N53 (owner 5 octets). **N54 hardening ≠ N54 feel historique (MIRV bus `radius=0`).** Feel 741d N73 décrit le même trou.

**Problème :** `GameState.flushBuildingDelta` fait `local out = {}` puis `table.insert` d’un **nouvel** enregistrement `{index, kind, slot, level, links}` pour chaque tuile `buildingDirty`, **chaque tick** — y compris le banc 6000 ticks qui flush pour ne pas fuiter. Si `buildingDirty` est vide, `out` est quand même alloué puis jeté (`return nil`). `links` est aujourd’hui la **table live** de l’usine (pas une copie) : Overlay / `applyBuildingDelta` lit `entry.index` / `kind` / `slot` / `level` / `links` tout de suite, pas l’identité de `out`. Le client ne reçoit le delta que si `buildings` est truthy (`init.server` : `if buildings then fireDeployed`).

**Pourquoi 20K CCU :** 10 Hz × shards, empilé avec N51–N53 déjà recyclés. Pas d’autorité (delta dérivé de `buildings` / `buildingDirty`). Un `table.create(16)` recyclé + truncate + early-out vide élimine l’alloc courte du hot path sans changer le wire `{index, kind, slot, level, links}`.

**Worker :**

1. `buildingSnapBuf = table.create(16)` module-level dans `GameState.luau` (à côté de `dirtyIndexBuf`). Early-out `next(self.buildingDirty) == nil` → `table.clear(self.buildingDirty)` + return nil **sans** allouer. Remplir par index (`n += 1`), recycle inner records (créer seulement si `buildingSnapBuf[n] == nil`, sinon réécrire les champs). Truncate `#buildingSnapBuf`. Champs **identiques** à aujourd’hui : `index, kind, slot, level, links`. Destruction (`buildings[index] == nil`) : `kind=0`, `slot=0`, `level=0`, `links=nil`. **`links` reste la référence live** (ne pas `table.clone` — extra alloc). Return `buildingSnapBuf` si `n > 0`, sinon nil.
2. `init.server` `replicate()` : ne pas changer l’appel `state:flushBuildingDelta()` ni le `if buildings then`. Ne pas toucher N53 `dirtyIndexBuf`. Ne pas toucher N2 `buildPrices`. Ne pas toucher N51/N52. Pas de RemoteFunction.
3. Test : `placeBuilding` CITY → `flushBuildingDelta` length 1, `kind` / `slot` / `index` honorés. Second flush immédiat → `nil`. `destroyBuilding` → length 1, `kind==0`, `links==nil`. 6000 ticks (le run principal flush déjà chaque tick). Client 34/34 (`applyBuildingDelta` lit les champs).
4. Fichiers : `GameState.luau` (`flushBuildingDelta`), `tests/simulate.luau` (bloc court, recette N53). Recette feel : branche `55ba` N73 (implémentée) / `741d` (spec).

**Contraintes :** pas de RemoteFunction. Recette `missileSnapBuf` / N52, **pas** un dirty flag supplémentaire. **N54 hardening ≠ N53 (owner indices, déjà fait) ≠ N2 (stats) ≠ N51/N52 (unités) ≠ visual V14 (autre ligne) ≠ feel N73 (même trou, numérotation feel).** `buildingSnapBuf` n’est pas réentrant — un seul `flushBuildingDelta` par tick. Overlay / tests doivent lire les champs tout de suite. Ne **pas** copier `links` : le contrat actuel est la référence ; une copie changerait l’identité vue par un test qui comparerait `rawequal`.

---

### ISSUE-N55 — `replicate()` alloue `activeAttacks` / `committedTroops` / `attackTargets` chaque tick

**Priorité :** P3 alloc réplication HUD. Précision de N2 (StateDelta) **sans** toucher `stats[slot]` ni `buildPrices` (reste N2). Distinct de N54 (BuildingDelta) et de N51–N53 (déjà faits). `init.server` est hors bundle : extraire un helper `GameState` testable, comme N52. **N55 hardening ≠ N55 feel historique (claimSpawn isolation).** Feel 741d N74 décrit le même trou.

**Problème :** `init.server` `replicate()` fait `local activeAttacks = {}` / `committedTroops = {}` / `attackTargets = {}` puis, pour chaque front, `table.insert` d’une **nouvelle** liste de cibles, **chaque tick** (10 Hz playing) — même à 0 front (trois tables vides jetées). Le HUD lit `activeAttacks`, `committedTroops`, `attackTargets` pour le curseur d’engagement ; ce n’est pas de l’autorité (dérivé de `state.attacks`). `attackTargets[slot]` est `nil` si le camp n’a aucun front (pas `{}`). Le banc 6000 ticks n’exerce pas `replicate()` (`init.server` hors bundle) : sans helper `GameState`, le recycle n’est pas testable.

**Pourquoi 20K CCU :** 10 Hz × 8 humains × 18 slots Classique, empilé avec `buildPrices` encore chaud (N2). 0–quelques fronts / camp d’habitude, mais l’alloc courte des trois maps est payée même idle. Pas d’autorité.

**Worker :**

1. Ajouter `GameState.frontHudForReplicate` (nom libre, un seul helper) calqué sur N52 : trois maps module-level `activeAttackBuf` / `committedTroopBuf` / `attackTargetBuf`. `table.clear` les trois au début de l’appel (pas de nouvelle table). Pour chaque `state.attacks` : incrémenter compteurs ; inner liste de cibles = `attackTargetPool[attacker]` recyclé (`table.clear` puis `table.insert` / index). Slots sans front : **absents** des trois maps (`nil`, pas `{}`) — `replicate()` garde `activeAttacks[slot] or 0` et `attackTargets[slot]` nil. Ne **pas** allouer de `stats` / `buildPrices` ici.
2. `init.server` `replicate()` : `local activeAttacks, committedTroops, attackTargets = state:frontHudForReplicate()` à la place des trois `local … = {}` + boucle. Le reste de `stats[slot] = { … }` **inchangé** (N2). Pas de RemoteFunction.
3. Test : 0 front → les trois maps vides (`next(...) == nil`). `launchAttack` 1 front → `activeAttacks[slot]==1`, `committedTroops[slot]` = floor(troupes), `attackTargets[slot]` length 1 égal à `atk.target`. `retreatAttack` jusqu’à disparition du front → maps vides à nouveau (pas de fuite de slot). Client 34/34 (HUD lit les champs, pas `rawequal` des maps). 6000 ticks.
4. Fichiers : `GameState.luau` (`frontHudForReplicate`), `init.server.luau` (`replicate`), `tests/simulate.luau` (nouveau bloc N55). Recette feel : branche `55ba` N74 (implémentée) / `741d` (spec).

**Contraintes :** pas de RemoteFunction. Recette N52 (helper `GameState` + pools module-level), **pas** un dirty flag (les troupes commises bougent chaque tick). **N55 hardening ≠ N2 (stats/buildPrices, ouvert) ≠ N54 (bâtiments) ≠ N39 (warships, déjà fait) ≠ feel N74 (même trou, numérotation feel).** Les trois maps ne sont pas réentrantes — `replicate()` est unique par tick. HUD / tests lisent les champs tout de suite. Ne pas merger un beachhead et un front terre dans le décompte : itérer `state.attacks` comme aujourd’hui (chaque tas compte). Ne pas porter AimFront ni seq.

---

## 5b. N1–N55 encore ouverts ou fermés (passes 2–21)

| ID | Titre | Prio | Note passe 21 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + `SAM_INTERCEPT_CHANCE` 0.55→1 ; clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz ; bateaux → **N51 fermé** ; missiles → **N52 fermé** ; indices dirty → **N53 fermé** ; bâtiments → **N54** ; HUD fronts → **N55** ; `buildPrices` encore 10 Hz |
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
| N16 | `attackLogic` scanne tous les DEF | P1 | **fermé via N36** ; scan **par camp par capture** → **N41 fermé** (grille) |
| N17 | Embargo allié + tribus auto-accept | P2 | design |
| N18 | `railIncome` HUD ≠ `deliveryValue` | P2 | snapshot niveau OK ; `links`/`stopBonus` absents du HUD |
| N19 | QuickChat 2-args target vs sequence | P3 | **partiel** : slot hors 1..48 refusé ; 2-args petit N + `needsTarget` = encore une cible |
| N20 | warships O(carriers×boats) + spawn ports | P2 | **N31 pool BFS fermé** ; **N34 dirty fermé** ; **N39 nested targeting fermé** ; **N40 spawnTradeShips fermé** ; spawn carriers dirty → **N48 fermé** |
| N21 | `tryAnnex` alloc + BFS mort | P2 | **fermé** (passe 10). Océan = abort **volontaire**. **≠ N21 feel (QuickChat).** |
| N22 | `BOAT_LANDING_BONUS` jamais lu | P2 | specs only |
| N23 | Trade / Navy gold ignorent doctrine, ère, `HUMAN_GOLD_MULTIPLIER` | P2 | specs only |
| N24 | `findSeaPath` pool BFS | P2 | **fermé via N31**. **≠ N24 feel (notify fireDeployed).** |
| N25 | `checkVictory` / `stepElimination` → Persistence + cap | P2 | **N37 fermé** (record). Cap humains éliminés / firehose encore ouverts. Purges « disparu » = dans `removePlayer`. |
| N26 | Notify / Sfx globaux `FireAllClients` | P2 | specs only. **≠ N26 feel (SAM 100 %).** |
| N27 | Pops de frontier périmés brûlent `guard` | P2 | **fermé via N38** |
| N28 | `retreatBoats` après flip | P2 | **partiel** : inbound fermé passe 8 ; `targetSlot` ouvert (recette feel N49/N53) |
| N29 | `seedBeachhead` no-merge | P2 | specs only |
| N30 | Missile inbound vs spawn recyclé | P2 | **fermé** (contrat B). Splash tiers → N33. **≠ N30 feel.** |
| N31 | Pool `findSeaPath` | P2 | **fermé** (recette feel N37, sans AimFront). **≠ N31 feel.** |
| N32 | Convoi marchand inbound | P2 | **fermé** (contrat B, passe 10). PORT détruit → N35 **fermé**. **≠ N32 feel.** |
| N33 | `findSpawn` splash / fallout | P3 | specs only (recette feel N50/N52). **≠ N33 feel (BOAT_LANDING_BONUS).** |
| N34 | `syncCarriers` dirty | P2 | **fermé**. Recette feel N38. Spawn → N48 **fermé**. **≠ N34 feel.** |
| N35 | Convoi vs PORT détruit au combat | P3 | **fermé** (contrat B). Capture de PORT = convoi continue. **≠ N35 feel.** |
| N36 | `applyDefenseAura` / bunkers scan | P1 | **fermé**. Recette feel N42 + N45 Option A. **≠ N36 feel (AimFront).** |
| N37 | `settledHumans` / Persistence éliminés | P2 | **fermé**. Recette feel N40 + `MatchLifecycle`. **≠ N37 feel (findSeaPath).** |
| N38 | Pops frontier stale / `guard` | P2 | **fermé**. **≠ N38 feel (syncCarriers).** |
| N39 | Warships nested targeting | P2 | **fermé** (contrat B). **≠ N39 feel (tryAnnex).** |
| N40 | `spawnTradeShips` O(ports²) | P2 | **fermé** (contrat A). **≠ N40 feel (settledHumans).** |
| N41 | `attackLogic` bunkers par capture | P2 | **fermé** (grille 3×3). **≠ N41 feel (seq obligatoire).** |
| N42 | SAM `tryIntercept` O(buildings) | P2 | **fermé** (`samsBySlot` + `samsOf`). Recette feel N57. Alloc → **N49 fermé**. **≠ N42 feel (bunkersBySlot).** |
| N43 | `stepCooldowns` O(buildings) | P3 | **fermé** (`coolingBuildings`, contrat A : SAM+silo). **≠ N43 feel (inbound transports).** |
| N44 | `Nukes.launch` scan silos | P3 | **fermé** (`silosBySlot`). Recette feel 5c74 N60. **≠ N44 feel (inbound missiles).** |
| N45 | `Trade.step` flatten usines | P2 | **fermé** (`factoriesByTile` + `factoriesBuf`). Recette `portsByTile` + feel N61. **≠ N45 feel (aura defense).** |
| N46 | Bots upgrade + score nuke O(B) | P2 | **fermé** (`buildingsBySlot`). Recette feel N62. Nested × 90 → **N50 fermé**. **≠ N46 feel historique (request croisée).** |
| N47 | `refreshRailNetwork` scan gares | P3 | **fermé** (`buildingsBySlot[slot]`). Recette feel N64. **Pas** `IS_STATION`. |
| N48 | `syncCarriers` spawn NAVAL_BASE | P3 | **fermé** (`navalBasesBySlot`). Recette feel 7c38 N65. **≠ N48 feel historique.** |
| N49 | `samsOf` alloc table | P3 | **fermé** (`samBuf`). Recette feel 1fb3 N68. **≠ N49 feel historique (targetSlot).** |
| N50 | `blastValue` × 90 tuiles frontière | P3 | **fermé** (`fillBlastBuf` / `scoreBlast`). Recette feel 5bf6 N69. **≠ N50 feel historique.** |
| N51 | Snapshot navires alloc 10 Hz | P2 | **fermé** (`snapshotBoats` + `boatSnapBuf`). Recette feel 5bf6 N70 **sans** `retreating`. **≠ N51 feel historique.** |
| N52 | Snapshot missiles alloc 10 Hz | P2 | **fermé** (`snapshotMissiles` + `missileSnapBuf`). Recette feel 741d N71. **≠ N52 feel historique (claimSpawn splash).** |
| N53 | `flushOwnerDelta` `indices` alloc | P3 | **fermé** (`dirtyIndexBuf`). Recette feel 741d N72. Buffer outbound **neuf**. **≠ N53 feel historique (Navy.step auto-flip).** |
| N54 | `flushBuildingDelta` alloc 10 Hz | P3 | specs only. Recette feel 741d N73. Recycle `buildingSnapBuf`, `links` live. **≠ N54 feel historique (MIRV bus).** |
| N55 | HUD fronts `replicate()` alloc | P3 | specs only. Recette feel 741d N74. Extraire `frontHudForReplicate`. **≠ N55 feel historique (claimSpawn isolation).** |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu (reset à `startMatch` suffit) ; disconnect mid-match **vivant** = `Persistence.record(..., false)` 0 XP (chemin distinct de N37 ; éliminé puis leave **grave** le snapshot) ; wrap `launchAttack` n’applique `AimFront.focus` que si le couple n’existait pas (renfort = pas de re-visée — feel N36). Spatial hash warships (contrat A de N39) volontairement non fait. `Trade.step` `factoriesBuf` déjà recyclé (N45) ; early-out 0 usine / sort seulement si `n>=2` = reste de feel N66, cheap. `structureHash` O(B log B) seulement sur `RequestSnapshot` rate-limité (N4, client jamais `FireServer`).

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
| `DEFENSE_RADIUS` | 6 | **30** | oui (`attackLogic` via `bunkerCells` / bunkersBySlot) |
| `DEFENSE_STRENGTH` | 55 | 200 | **non** (buffer plus écrit) |
| `WARSHIP_TARGET_RANGE` | — | 65 | oui (N39) |
| `TRADE_SHIP_CHANCE` | 0.22 | 0.22 | oui (N40, loi inchangée) |
| `MAX_TRADE_SHIPS` | 24 | 24 | oui (early-out **avant** flatten) |
| `SAM_RANGE` | 34 | **70** | oui (`tryIntercept` via `samsBySlot` — N42) |
| `SAM_COOLDOWN` | 90 | **75** | oui (`armCooldown` / `coolingBuildings` — N43) |
| `SILO_COOLDOWN` | (Config) | (apply) | oui (`Nukes.launch` via `silosBySlot` — N44, écriture `armCooldown`) |
| `TRUCK_COOLDOWN` | (Config) | (apply) | oui (`Trade.step` via `factoriesByTile` — N45, sort inchangé) |
| `RAIL_RANGE` | (Config) | (apply) | oui (`refreshRailNetwork` via `buildingsBySlot` — N47) |

---

## 7. Preuve tests

```
./tests/run.sh  → exit 0
bundle server : 37 modules
Serveur : Tous les invariants tiennent.
  … gardes #17–#63 inchangés …
  boatSnapBuf : 1 carrier + 1 transport, pas de path (N51)
  boatSnapBuf : truncate 2→1→0 (N51)
  missileSnapBuf : 1 ogive, tx/ty, pas de progress (N52)
  missileSnapBuf : truncate 1→0→1 (N52)
  dirtyIndexBuf : spawn>0, second nil, 1 tuile (N53)
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 captures=80 pops=160
  factions : 18
  metrics : ticks=6000 avgChanged=10.5 p95Changed=5 maxChanged=479 avgTickMs=0.31 p95TickMs=0.57
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe21.log`

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
- Transports : `kind == 1`. Convois : `kind == 2`. Missiles : `toIndex(floor(tx), floor(ty))` vs `owner` **avant** `setOwner`. Ne pas `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` depuis GameState (cycle).
- Missile inbound = **annulé**, pas remboursé. Convoi inbound = **coulé**, pas d’or. Convoi vs PORT **détruit** (combat, pas recycle) = **coulé** dans `Navy.step` (contrat B). Capture de PORT = convoi continue. Frappe / convoi déjà visé sur un tiers = conservé. Splash tiers / fallout au spawn = N33.
- `findSeaPath` : pools module-level, `buffer.fill(buf, 0, 0)`, `table.clear` parent/queue. Navy n’est pas réentrant. Ne pas porter AimFront avec.
- `tryAnnex` : appelé **après** `setOwner` ; BFS depuis les voisins défenseur du seed. Océan = abort (enclave terrestre), pas un bug. Pools `annexVisitBuf` / queue / pocket, `buffer.fill(buf, 0, 0)`.
- `syncCarriers` : `_carriersDirty` NAVAL_BASE seulement (`placeBuilding` / `destroyBuilding` / `transferBuilding`). Spawn via `navalBasesBySlot` (N48). `carrierSeen` recyclé. Pas de scan 10 Hz. Pas de dirty CITY/PORT. Distinct de `portsByTile` (PORT) et de `buildingsBySlot` (tous kinds).
- Ciblage warships : `carrierBuf` / `targetBuf` module-level, `table.clear`. Early-out si 0 carrier ou 0 autre slot. Priorité et `areAllied` inchangés. Pas de spatial hash (N39 contrat A non retenu).
- Commerce maritime : `portsByTile[index]={slot,level}` (PORT seulement). Early-out `countTradeShips >= MAX_TRADE_SHIPS` **avant** flatten. `portsBuf` / `candidateBuf` recyclés. Sort par index, poids = niveau, `canTrade` embargo-only. Ne pas recâbler `_carriersDirty`. `TRADE_SHIP_CHANCE` / gold inchangés.
- Commerce terrestre : `factoriesByTile[index]={slot,level}` (FACTORY seulement, N45). Flatten + `table.sort` par index (RNG). Buffer `factoriesBuf` recyclé. `delivery.level` snapshot au départ. `refreshRailNetwork` (N47) itère `buildingsBySlot[slot]` — ne pas le fusionner avec `factoriesByTile`. Ne pas recâbler N40 (`portsByTile`).
- Posted bunker : `bunkersBySlot[slot][tile]` + `bunkerCells[slot][cellKey]` (cell = `DEFENSE_RADIUS`, clé `floor(y/r)*1024+floor(x/r)`). Lookup 3×3 + dist², cassure au premier hit. Posted = **booléen**, pas un stack. Plus d’appels `applyDefenseAura`. Buffer `defense` alloué, plus écrit. Ne pas changer `DEFENSE_POST_BONUS` / `DEFENSE_RADIUS`.
- Posted SAM : `samsBySlot[slot][tile]` (N42). `tryIntercept` itère les SAM ennemis non alliés, pas `buildings`. `samsOf` lit le même index dans `samBuf` (N49). Un SAM = une cible (`engaged`). Ne pas changer `SAM_RANGE` / chance / cooldown. `samBuf` n’est pas réentrant — appelant unique `Bots.decideNuke`. Index présent + set nil = zéro SAM, **pas** de fallback hash.
- Posted SILO : `silosBySlot[slot][tile]` (N44). `Nukes.launch` n’itère que ce set. Un slot sans silo ne rescane **pas** le hash. Un SAM / PORT n’est jamais un lanceur. `armCooldown` reste la voie d’écriture (N43). Ne pas poser `silo.cooldown =` à la main (feel 5c74 le faisait — **ne pas porter ça** : ça gèlerait `coolingBuildings`). Ne pas changer `SILO_COOLDOWN` / coût / ère. Un silo = un missile. Ne pas `require(Nukes)` depuis GameState.
- Posted NAVAL_BASE : `navalBasesBySlot[slot][tile]` (N48). `syncCarriers` n’itère que cet index. Un slot sans base ne rescane **pas** le hash. Un PORT n’est jamais un carrier. Ne pas `require(Navy)` depuis GameState. Garder `_carriersDirty` (pas un scan 10 Hz).
- Tous kinds : `buildingsBySlot[slot][tile]` (N46). `lowestUpgradable` itère le set du bot ; `blastValue` / `fillBlastBuf` itère le set de la **cible** (N50). `removePlayer` snapshot les clés puis destroy. Un slot sans bâtiments ne rescane **pas** le hash. Ne pas spatial-hasher le blast. Ne pas relire `samsOf` via le hash (N42/N49). Ne pas recâbler `Nukes.launch` (N44) ni `factoriesByTile` (N45) ni `navalBasesBySlot` (N48).
- Score nuke : `fillBlastBuf` **une fois** avant la boucle 90, puis `scoreBlast` (N50). Index présent + set nil = buffer vide, score 0. `Bots.blastValue` (banc N46) réutilise le même helper. `blastX/Y/Level` n’est pas réentrant — `decideNuke` unique par bot par tick. Ne pas changer la règle « tout couvert → frapper le SAM ».
- Cooldown bâtiments : `Buildings.armCooldown` est **la** voie d’écriture (intercept + tir silo). `stepCooldowns` parcourt `coolingBuildings`, pas `buildings`. Ne **pas** n’itérer que les SAM : un silo a aussi un cooldown (contrat B de N43 rejeté). `destroyBuilding` retire du set.
- Gares : `refreshRailNetwork` collecte depuis `buildingsBySlot[slot]` (N47). Kinds inlinés (CITY/CAPITAL/PORT/FACTORY). **Ne pas** utiliser `IS_STATION` depuis cette fonction (local trop bas). Sort conservé. Événementiel, pas 10 Hz.
- Snapshot navires : `GameState.snapshotBoats` (N51). `boatSnapBuf` recycle inner records, truncate. **Pas** de `path` / `homeTile` / `_sink` / `retreating`. Overlay de cette ligne ne lit pas `retreating` (Types.BoatSnapshot, client 34/34). Ne pas `require(Navy)` depuis GameState.
- Snapshot missiles : `GameState.snapshotMissiles` (N52). `missileSnapBuf` recycle inner records, truncate. Champs **uniquement** `Types.MissileSnapshot`. Pas de `sx` / `sy` / `progress` / `speed`. Overlay interpolé via `tx`/`ty`. Ne pas `require(Nukes)` depuis GameState. `missileSnapBuf` n’est pas réentrant — `replicate()` unique / tick.
- Owner delta : `flushOwnerDelta` via `dirtyIndexBuf` (N53). Early-out dirty vide sans allouer. Buffer outbound **neuf**. Format `[u32 index][u8 slot]`. Ne pas recycler le `buffer` envoyé (RemoteEvent).
- `init.server` / `Persistence` restent hors bundle : extraire un helper testable (`MatchLifecycle` / `snapshotBoats` / `snapshotMissiles` déjà là) ou documenter un test Studio. BuildingDelta (N54) et HUD fronts (N55) = extraire **avant** de recycler.
- Humain éliminé : `settledHumans[slot]` **avant** destruction du PlayerState. Bots ignorés. `endMatch` / disconnect après élimination passent par `MatchLifecycle` (init.server hors bundle). Disconnect **vivant** = 0 XP. `Persistence` reste hors du tick. Ne pas recâbler N6.
- Grâce humaine = `Bots.humanTargetProtected` (bots **et** tribus). Ne pas dupliquer une 2e courbe.
- Ne pas casser le client 34/34.
- Ligne feel (#19/#22/#24/#26/#28/#29/#32/#34/#36/#38/#41/#42/#45/#48/#51/#53/#56/#59/#62) : rebase sur cette passe avant cherry-pick, sinon perte `missileSnapBuf` / `dirtyIndexBuf`. Cherry-pick seq obligatoire (N41 feel) et `targetSlot` (N49 feel) seulement — N40/N42/N45/N57/N59/N60/N61/N62/N64/N65/N67/N68/N69/N70/N71/N72 feel sont déjà redondants avec N36 / N37 / N39 / N42 / N43 / N44 / N45 / N46 / N47 / N48 / N49 / N50 / N51 / N52 / N53 hardening. N50/N52 feel (`findSpawn` / `isSpawnSafe`) porte N33. N73 feel (`flushBuildingDelta`) = N54 ici. N74 feel (`frontHudForReplicate`) = N55 ici. **Ne pas** porter `retreating` Overlay (feel N56) avec N51.
