# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 27)

Déclencheur : ouverture de la **PR #83** (`cursor/analyse-nocturne-du-codebase-bef6`) — `siteBuf`, `elimBuf`, specs N64–N65.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-5edc`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #83**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#83. Pas d’outil Slack.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29/#32/#34/#36/#38/#41/#42/#45/#48/#51/#53/#56/#59/#62 + d425 + df65 + 2157 + 5c74 + e735 + 7c38 + 1fb3 + 5bf6 + 741d + 55ba + 4876 + cc42 + 2f5d + b62d + **69f4 passe 27**) : ne pas merger sur cette branche sans rebase. Les numéros N40+ feel (settledHumans, seq, N52–N86…) ne sont **pas** les N40–N67 de ce rapport. Cette passe **ferme** hardening N64 (`Navy.findSeaPath` `pathWalkBuf`) et N65 (`GameState.refreshRailNetwork` `stationBuf`). Seq obligatoire (feel N41) et `targetSlot` (feel N49/N53) ne sont pas portés. **Pas** de `TRAIN_STOP_BONUS` dans `railIncome` (feel N20 / N84 — volontaire). Feel 69f4 N83 (`pathWalkBuf`) et N84 (`stationBuf`) sont **portés**. Feel 69f4 N85 (`Buildings.contextFor`) = **N66 ici**. Feel 69f4 N86 (`ChantierB` `doomedBuf` / `collapsingBuf`) = **N67 ici**.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`. `RequestSnapshot` n’est toujours jamais `FireServer` côté client (N4). DAG : `GameState` ne `require` ni Navy, ni Nukes, ni Trade, ni Bots, ni Buildings, ni Research, ni Diplomacy. `Buildings`, `Research` et `Diplomacy` require déjà `GameState` — ne pas inverser. N64 (`pathWalkBuf`) vit dans Navy : **ne pas** require Navy depuis GameState. N65 (`stationBuf`) vit dans GameState : **ne pas** require Buildings depuis GameState. N66 (`ctxBuf`) vit dans Buildings. N67 (`doomedBuf`) vit dans ChantierB (ReplicatedStorage, `install()` serveur seulement).

La PR #83 a bien fermé `siteBuf` (N62) et `elimBuf` (N63). Cette passe a **corrigé ce que #83 a spécifié** — `findSeaPath` allouait encore path + reversed par trajet, et `refreshRailNetwork` allouait stations / parent / xs / ys / maps de grappe :

| Bug | Gravité | Statut |
|---|---|---|
| `Navy.findSeaPath` alloue path + reversed par trajet (N64) | **P3 alloc marine** | **corrigé** (`pathWalkBuf` walk + copie inverse unique, recette feel N83) |
| `GameState.refreshRailNetwork` alloue stations / parent (N65) | **P3 alloc pose/capture** | **corrigé** (`stationBuf` + truncate avant sort, recette feel N84, **sans** `TRAIN_STOP_BONUS`) |
| `Buildings.contextFor` alloue record + 2 closures (N66) | **P3 alloc pose** | **ouvert** (feel 69f4 N85) |
| `ChantierB.cancelOpposingFronts` / `collapsing` 10 Hz (N67) | **P3 alloc combat** | **ouvert** (feel 69f4 N86) |
| `retreatBoats` filtre `owner[targetTile]` courant | **P2 marine** | **ouvert** (reste de N28 ; feel d425/df65 a la recette) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29) |
| `findSpawn` ignore splash / fallout (N33) | **P3 nucléaire** | **ouvert** (feel d425/df65 a C1+C2 + `isSpawnSafe`) |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#83 + pathWalkBuf (N64) + stationBuf (N65).
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #83

**À merger** (`siteBuf` + `elimBuf` + specs N64–N65), sous réserve que cette passe 27 parte avec : **`findSeaPath` allouait encore path + reversed et `refreshRailNetwork` allouait encore stations / parent**.

Points encore vrais après #83 :

| Claim #83 | Réalité après passe 27 |
|---|---|
| `Bots.gatherSites` recycle `siteBuf` (N62) | confirmé |
| `GameState.stepElimination` recycle `elimBuf` (N63) | confirmé |
| N64 `Navy.findSeaPath` `pathWalkBuf` | **fermé ici** (walk scratch + copie inverse unique) |
| N65 `refreshRailNetwork` `stationBuf` | **fermé ici** (truncate avant sort, inners `links` uniques) |
| N33 `findSpawn` splash / fallout | **ouvert** |
| N28 retraite après flip / `targetSlot` | **ouvert** |
| N29 `seedBeachhead` no-merge | specs only, inchangé |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |

`init.server.luau` et `Persistence` restent **exclus du bundle**. Le helper `MatchLifecycle` est **dans** le bundle (37 modules serveur). `snapshotBoats` / `snapshotMissiles` / `flushOwnerDelta` / `flushBuildingDelta` / `frontHudForReplicate` / `playerStatsForReplicate` sont **dans** le bundle (`GameState`). `pricesFor` vit dans **Buildings**. `progress` ne alloue plus `ratios` (N58). `Diplomacy.viewFor` recycle `viewBuf[slot]` (N59). `Diplomacy.step` recycle `expiredBuf` (N60). `neighborFactions` recycle `contactBuf` (N61). `gatherSites` recycle `siteBuf` (N62). `stepElimination` recycle `elimBuf` (N63). `findSeaPath` recycle `pathWalkBuf` (N64) — le tableau rendu au bateau **reste unique**. `refreshRailNetwork` recycle `stationBuf` (N65) — `building.links` **reste unique**. `Buildings.contextFor` alloue encore record + closures (N66). `ChantierB` alloue encore `doomed` / `collapsing` 10 Hz (N67).

PR #82 (feel passe 27, `69f4`) ne doit pas être mergée par-dessus #16/#83 sans rebase. `pathWalkBuf` (feel N83) et `stationBuf` (feel N84) sont **portés** ici. Seq / `targetSlot` / hover `SpawnHint` / Overlay `retreating` / `TRAIN_STOP_BONUS` HUD restent feel-only. Feel N85/N86 → N66/N67.

On peut fermer #17, #18, #20, #23, #25, #27, #30, #31, #33, #35, #37, #40, #43, #46, #49, #52, #55, #58, #60, #63, #66, #70, #73, #76, #80 et #83 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| `Navy.findSeaPath` alloc path + reversed | `Navy.findSeaPath`, `Navy.pathWalkBuf`, `tests/simulate.luau` | Walk scratch module-level. Au hit : poser `toTile` puis remonter jusqu’à `fromTile` **exclu**. Truncate leftover. Allouer **un** `out` et copier à l’envers. `return out`, **jamais** `pathWalkBuf`. Banc N31 (4 appels, inverse) reste vert. Deux appels → `not rawequal` ; `p1[i]` intact. Recette feel 69f4 N83. |
| `GameState.refreshRailNetwork` alloc stations / parent | `GameState.refreshRailNetwork`, `GameState.stationBuf` + `railParentBuf` / `railXsBuf` / `railYsBuf` / maps grappe, `tests/simulate.luau` | Collecte N47 inchangée (`buildingsBySlot[slot]`, kinds inlinés, **pas** `IS_STATION`). Truncate leftover **avant** `table.sort`. Union-find / xs / ys dans les buf. Maps `table.clear`. Inners `neighborsOf` **uniques** (`building.links`). Formule `railIncome` **inchangée** (pas `TRAIN_STOP_BONUS`). Slot 99 → no-op. Recette feel 69f4 N84, sans le bonus HUD feel. |

**Non modifié (volontaire) :** N1–N63 restant, reste de N28 (`targetSlot`). N10.8. Cap beachheads (N5 / N29). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` depuis GameState. Pas de contrat C spawn (N33). Pas de seq obligatoire (feel N41). Pas de spatial hash warships. Buffer `defense` **alloué** mais plus écrit. Pas de `TRAIN_STOP_BONUS` dans `railIncome` (N18 / feel N20). `Buildings.contextFor` encore record + closures (N66). `ChantierB` encore `doomed` / `collapsing` 10 Hz (N67). Pas de `retreating` Overlay (feel N56 historique).

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + **captures < 80 et pops < 160**). `cancelOpposingFronts` alloue encore `doomed` ; wrap alloue encore `collapsing` (N67).
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
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients` (N26). Snapshot navires = `GameState.snapshotBoats` (`boatSnapBuf`, N51). Snapshot missiles = `GameState.snapshotMissiles` (`missileSnapBuf`, N52). Owner delta = `dirtyIndexBuf` (N53), buffer outbound **neuf**. BuildingDelta = `buildingSnapBuf` (N54), `links` live. HUD fronts = `frontHudForReplicate` (N55), appelé **une** fois depuis N57. `buildPrices` = `Buildings.pricesFor` (N56). Records stats = `playerStatsForReplicate` (N57). `Research.progress` min courant (N58). `Diplomacy.viewFor` recycle par slot (N59). `Diplomacy.step` recycle `expiredBuf` (N60). `neighborFactions` recycle `contactBuf` (N61). `gatherSites` recycle `siteBuf` (N62). `stepElimination` recycle `elimBuf` (N63). `findSeaPath` `pathWalkBuf` (N64, retour unique). `refreshRailNetwork` `stationBuf` (N65). `contextFor` record+closures (N66). Combat `doomed`/`collapsing` (N67).
- **DataStore** : `settledHumans` avant destruction du PlayerState. `endMatch` grave via `MatchLifecycle.endMatchRecords`. `Persistence.record` max-merge inchangé (N6).
- **Require** : DAG. Pas de cycle. `MatchLifecycle` → Config seulement. `Tribes` → `Bots` (export `humanTargetProtected` seulement). `Navy` → `GameState` (unidirectionnel). `Nukes` → `GameState` + `Buildings`. `Trade` → `GameState`. `Bots` → `GameState` (pas l’inverse). `Buildings` → `GameState` (pas l’inverse — N56 vit dans Buildings). `Research` → `GameState` (pas l’inverse — N57/N58 ne require pas Research depuis GameState). `Diplomacy` → `GameState` (pas l’inverse — N59/N60 vivent dans Diplomacy). `ChantierB`/`BoatFront`/`AimFront` dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).
- **BFS mer** : `visitBuf` + `parentScratch` + `queueScratch` + `pathWalkBuf` module-level. Un seul chemin en vol à la fois (Navy n’est pas réentrant). Résultat path **unique** (copie inverse, N64).
- **BFS annex** : `annexVisitBuf` + `annexQueue` + `annexPocket` module-level. Un seul `tryAnnex` en vol à la fois (combat n’est pas réentrant).
- **Gares** : `stationBuf` + `railParentBuf` / `railXsBuf` / `railYsBuf` + maps grappe. Truncate **avant** sort. `building.links` unique (N65).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N67 restent ouverts** sauf N19 partiel, N21 **fermé**, N24 remplacé par N31 (**fermé**), N30–N32 **fermés**, N34–N65 **fermés**. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + le reste de N28 / N29 / N33.

---

### ISSUE-N28 — `retreatBoats` / `retreatAttack` après flip de côte (reste)

**Priorité :** P2 combat / comptabilité navale. **Partiel :** inbound `removePlayer` **fermé** en passe 8.

**Problème restant :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetSlot`. Conséquences encore vraies :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers).
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

Feel d425 (N49) + df65 (N53) : `launchInvasion` pose `targetSlot`, `retreatBoats` filtre l’intention (fallback `owner[targetTile]`), wrap 2e geste rappelle les tardifs, `Navy.step` auto-retraite si `owner[targetTile] ~= targetSlot`. **Porter, ne pas réinventer.** Distinct de N10.8 et du fix inbound. Distinct de N35 (`destSlot` convoi ≠ `targetSlot` invasion). Distinct de N40 / N44–N67 (index / snapshots / HUD / `progress` / `viewFor` / `expired` / contacts / sites / elim / path / rail, **fermés** ou **specs**).

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite.

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste, trancher si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`. Recette feel : branche `d425` / `df65`.

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N22). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % déjà livré). Ne pas recâbler N35 (convois, `kind==2`). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).** Ne pas porter AimFront ni seq. Ne pas recâbler N50–N67 (`blastBuf` / snapshots / `dirtyIndexBuf` / `buildingSnapBuf` / HUD fronts / `pricesFor` / stats / `progress` / `viewFor` / `expiredBuf` / `contactBuf` / `siteBuf` / `elimBuf` / `pathWalkBuf` / `stationBuf`).

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

Feel d425 (N50) + df65 (N52) + 2157 (N55 isolation, ticket suivant) : `isSpawnSafe` partagé `findSpawn` / `claimSpawn`, refuse crater ogive **et** `state.fallout[index] > tick`. **Porter, ne pas réinventer.** Contrat B (N30) déjà livré ici : ne pas l’ouvrir. Isolation disque clic (feel N55) = ticket **feel**, pas celui-ci.

**Pourquoi 20K CCU :** moins chaud que N30 (il faut un voisin sous missile + spawn coincé dans le rayon).

**Worker :**

1. Ne **pas** rouvrir le contrat B. Options : (C1) `findSpawn` refuse un centre dont un missile en vol a `toIndex(floor(tx),floor(ty))` à distance `NUKE_STATS[kind].radius` (ogive : `missile.radius`) ; (C2) `findSpawn` refuse `state.fallout[index] > tick` ; (C3) documenter « le territoire, pas le joueur » pour le splash tiers. Feel a choisi C1+C2 via `isSpawnSafe`.
2. Test : A tire sur C (capitale), `removePlayer(B)`, forcer le spawn de l’héritier dans le rayon (tuiles libres), `Nukes.step`. Assert selon C1/C2/C3.
3. Fichiers : `GameState.findSpawn` / `addPlayer`, éventuellement `Nukes`, `tests/simulate.luau`. Recette feel : branche `d425` / `df65`.

**Contraintes :** ne pas annuler une frappe tiers (régression `nuke third-party`). Ne pas rembourser l’or. Pas de RemoteFunction. Rayon lu depuis `NUKE_STATS` / `missile.radius`, pas une constante magique. Ne pas porter isolation clic (feel N55) dans le même PR. Ne pas recâbler N50–N67.

---

### ISSUE-N66 — `Buildings.contextFor` alloue record + 2 closures par resolve

**Priorité :** P3 alloc pose. Leftover explicite de N10 / N62 (`siteBuf` déjà, plus le hash sites). Distinct de N56 (`pricesFor`) et de N65 (`stationBuf`). Ne pas toucher `Placement.luau` ni `PlacementPreview.luau` (client : le fantôme construit **son** ctx avec les closures `ownerAt`/`buildingAt` fournies par `init.client` — leftover visuel, pas ce worker). **N66 hardening ≠ N66 feel historique (`Trade.step` `factoryBuf`, leftover N45 déjà ici).** Feel 69f4 N85 décrit le même trou.

**Problème :** chaque `Buildings.resolve` (intent `BuildOrder` + `Bots.decideBuild`) fait `return { slot, era, gold, terrain, ownerAt = function…, buildingAt = function… }`. Trois allocations (record + 2 closures) par clic / décision bot. Les closures capturent `state`. `Placement.resolve` lit `ctx` de façon synchrone et abandonne — le record n’a pas besoin d’être unique.

**Pourquoi 20K CCU :** leftover N62. Un shard 8 humains + 16 bots pose/upgrade plusieurs fois par seconde en mid-game. Recycle du record + fonctions module (lisent `ctxState`) élimine l’alloc courte. Pas d’autorité (même `buffer.readu8(state.owner)` / `state.buildings[index]`). Ne pas fusionner avec le ctx client : les calques Overlay ne sont pas des buffers serveur.

**Worker :**

1. Ajouter `ctxState: GameState?` et `ctxBuf: Placement.Context` module-level dans `Buildings.luau`. `ownerAt` / `buildingAt` = fonctions **module** (pas de `function` inline) : `ownerAt` lit `buffer.readu8(ctxState.owner, index)` ; `buildingAt` lit `ctxState.buildings[index]` (kind/slot/level ou nil,nil,nil — **même contrat**). `contextFor` : slot inconnu → `return nil` **sans** muter `ctxBuf`. Slot vivant : poser `ctxState = state`, `ctxBuf.slot/era/gold/terrain`, `ctxBuf.ownerAt` / `ctxBuf.buildingAt` = les fonctions module (identité stable), `return ctxBuf`.
2. Ne pas require de module nouveau. Ne pas toucher `pricesFor` / `samBuf` / `stationBuf`. Ne pas toucher `Placement.luau` (le type `Context` reste). Ne pas toucher `PlacementPreview.resolve` (le client passe ses propres closures — un `ctxBuf` serveur n’existe pas côté client). `resolve` reste le seul appelant serveur. Pas de RemoteFunction.
3. Test : `Buildings.contextFor(state, slot)` deux fois → `rawequal`. Slot 99 → `nil`. `Buildings.resolve` pose encore une CITY (snap / exact inchangé — banc placement existant). Après `contextFor(A)` puis `contextFor(B)`, un `ownerAt` **conservé** du premier ctx lit B (non réentrant — documenter, ne pas « corriger » en clonant). Client 34/34. 6000 ticks.
4. Fichiers : `Buildings.luau` (`contextFor` + helpers module, `resolve` inchangé à l’appel), `tests/simulate.luau` (bloc court à côté du banc N56 / `pricesFor`). Recette feel : branche `69f4` N85 (spec — **porter, ne pas réinventer**).

**Contraintes :** pas de RemoteFunction. Recette N59 (record réécrit, pas une nouvelle table) + closures stables (recette N55 pool). **N66 hardening ≠ N56 (`pricesFor`, déjà fait) ≠ N62 (`siteBuf`, déjà fait) ≠ N65 (`stationBuf`, déjà fait) ≠ N66 feel historique (`factoryBuf`).** `ctxBuf` n’est pas réentrant. `resolve` est synchrone et unique. Ne pas `table.clone(ctxBuf)`. Ne pas stocker le ctx au-delà de `Placement.resolve`. `terrain` est le buffer live (pas une copie) — Overlay client a le sien. Ne pas `require(Buildings)` depuis GameState.

---

### ISSUE-N67 — `ChantierB.cancelOpposingFronts` / `collapsing` allouent 10 Hz

**Priorité :** P3 alloc combat. Leftover du wrap `GameState.stepAttacks` vivant. Distinct de N63 (`elimBuf` élimination) et de N23 (`retreatAttack` couple — déjà `tous les fronts`). Ne pas toucher `BoatFront` (`parked` par `launchAttack` — leftover N5, pas 10 Hz) ni `GameState.stepAttacks` mort (corps original ignoré : `local _ = origStepAttacks`). **N67 hardening ≠ N67 feel historique (`carrierBuf` / `targetBuf`, déjà N39 ici).** Feel 69f4 N86 décrit le même trou.

**Problème :** chaque tick avec fronts, `cancelOpposingFronts` fait `local doomed: { boolean } = {}` (hash sparse indexé par i d’attaque) et le wrap `stepAttacks` fait `local collapsing = {}` puis `table.insert(collapsing, { victim, captor })` par front sous le seuil. Deux allocations porteuses + N records par tick de combat. La loi (clash `min(troops)`, refund si troops>0 au remove, collapse si `tiles < collapseThreshold()` encore vrai **après** la passe) ne change pas.

**Pourquoi 20K CCU :** leftover combat vivant. 10 Hz × 18 slots × quelques fronts. Recycle des porteuses (et pool des records collapse) élimine l’alloc courte du hot path. Pas d’autorité (mêmes soustractions, même `table.remove` arrière, même notify). Ne pas fusionner avec `elimBuf` : collapse n’est pas une élimination (territoire redistribué, pas `removePlayer`).

**Worker :**

1. Ajouter `doomedBuf: { [number]: boolean } = {}` module-level dans `ChantierB.luau`. Au début de `cancelOpposingFronts` : `table.clear(doomedBuf)`. Remplacer `doomed` par `doomedBuf`. Ne **pas** itérer `#doomedBuf` (c’est un hash sparse — la boucle `for i = #state.attacks, 1, -1` reste). Ajouter `collapsingBuf` (`table.create(8)`) + `collapseRecPool` (`table.create(8)`, records `{ victim, captor }`). Au début du wrap `stepAttacks` : n = 0. À chaque insert : n += 1 ; réécrire un rec du pool (créer si `collapseRecPool[n] == nil`) ; `collapsingBuf[n] = rec`. Truncate leftover n+1..# **avant** la boucle `for _, entry in collapsing`. Traiter `1..n` (pas `#` sans truncate). Pas de RemoteFunction.
2. Ne pas modifier `attackLogic` / `attackTilesPerTick` / `tryAnnex` / `collapseFaction` / `collapseThreshold`. Ne pas câbler `MAX_TILES_PER_TICK`. Ne pas require de module nouveau. Ne pas toucher `BoatFront.parked`. `origStepAttacks` reste ignoré. Notify humain inchangé.
3. Test : banc combat vivant existant (guard=80) **doit rester vert**. Ajouter : deux joueurs, fronts opposés A→B et B→A avec troupes égales → les deux fronts disparaissent, troupes restituées (clash). Un défenseur sous le seuil → `collapseFaction` toujours appelé (territoire du captor augmente). Deux appels `cancelOpposingFronts` sans fronts → pas d’erreur, `next(doomedBuf) == nil` après clear. Client 34/34. 6000 ticks.
4. Fichiers : `ChantierB.luau` (`cancelOpposingFronts` + wrap `stepAttacks` seulement), `tests/simulate.luau` (bloc court à côté du banc « combat vivant »). Recette feel : branche `69f4` N86 (spec — **porter, ne pas réinventer**).

**Contraintes :** pas de RemoteFunction. Recette N60 (`expiredBuf` + pool records) pour collapsing ; recette `table.clear` hash pour doomed (comme `contactBuf` N61). **N67 hardening ≠ N63 (`elimBuf`, déjà fait) ≠ N23 (`retreatAttack`, déjà fait) ≠ N8 (combat mort vs vivant, ouvert) ≠ N67 feel historique (`carrierBuf`).** `doomedBuf` / `collapsingBuf` ne sont pas réentrants. `stepAttacks` est unique par tick. Ne pas `table.remove` dans `collapsingBuf` pendant l’itération — la collecte est close avant le traitement. Un leftover d’état A dans l’état B sans truncate ferait collapse d’un slot fantôme — truncate obligatoire (recette N63). Les records ne sont pas répliqués. Ne pas `require(ChantierB)` depuis GameState (le wrap est déjà dans `install()`).

---

## 5b. N1–N67 encore ouverts ou fermés (passes 2–27)

| ID | Titre | Prio | Note passe 27 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + `SAM_INTERCEPT_CHANCE` 0.55→1 ; clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz ; bateaux → **N51 fermé** ; missiles → **N52 fermé** ; indices dirty → **N53 fermé** ; bâtiments → **N54 fermé** ; HUD fronts → **N55 fermé** ; `buildPrices` → **N56 fermé** ; records stats → **N57 fermé** ; `progress` → **N58 fermé** ; `viewFor` → **N59 fermé** ; `expired` → **N60 fermé** ; contacts → **N61 fermé** ; sites → **N62 fermé** ; elim → **N63 fermé** ; path → **N64 fermé** ; rail → **N65 fermé** ; reste skip-si-inchangé |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` **jamais** `FireServer` côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | park `isBeachhead` → hors cap land ; **2 beachheads parked + 1 terre = 3** — voir N29 |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | refund + retraite `RETREAT_LOSS` alignés ; le reste du corps est mort ; `tileCost` lit encore `defense` (buffer plus écrit) ; wrap vivant → **N67** |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | timers slot maintenant purgés ; le scan rot est toujours O(tuiles) |
| N10 | Divers P3 | P3 | donations gold sans plafond ; `pendingMode` last-writer ; README SmoothTerrain ; `contextFor` → **N66** |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | debit = `attackTilesPerTick` × speed, **captures<80 pops<160** |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 observé) | P1 | `Bots.spawnAll` wrap + `Tribes.spawnAll(6)` hors budget |
| N13 | Parité ère / cost factor `attackLogic` | P2 | doctrines oui ; `Eras.accumulate` et `sizeAttackFactors` coût **non** |
| N14 | Humains éliminés occupent cap + firehose + Persistence | P2 | **N37 fermé** (record). Cap slot / firehose encore ouverts via N25 |
| N15 | Heap AimFront ≠ ChantierB | P2 | `terrainMag` vs `TERRAIN_COST/2` |
| N16 | `attackLogic` scanne tous les DEF | P1 | **fermé via N36** ; scan **par camp par capture** → **N41 fermé** (grille) |
| N17 | Embargo allié + tribus auto-accept | P2 | design |
| N18 | `railIncome` HUD ≠ `deliveryValue` | P2 | snapshot niveau OK ; `links`/`stopBonus` absents du HUD (**pas** porté avec N65) |
| N19 | QuickChat 2-args target vs sequence | P3 | **partiel** : slot hors 1..48 refusé ; 2-args petit N + `needsTarget` = encore une cible |
| N20 | warships O(carriers×boats) + spawn ports | P2 | **N31 pool BFS fermé** ; **N34 dirty fermé** ; **N39 nested targeting fermé** ; **N40 spawnTradeShips fermé** ; spawn carriers dirty → **N48 fermé** ; path résultat → **N64 fermé** |
| N21 | `tryAnnex` alloc + BFS mort | P2 | **fermé** (passe 10). Océan = abort **volontaire**. **≠ N21 feel (QuickChat).** |
| N22 | `BOAT_LANDING_BONUS` jamais lu | P2 | specs only |
| N23 | Trade / Navy gold ignorent doctrine, ère, `HUMAN_GOLD_MULTIPLIER` | P2 | specs only |
| N24 | `findSeaPath` pool BFS | P2 | **fermé via N31**. Résultat → **N64 fermé**. **≠ N24 feel (notify fireDeployed).** |
| N25 | `checkVictory` / `stepElimination` → Persistence + cap | P2 | **N37 fermé** (record). Cap humains éliminés / firehose encore ouverts. Purges « disparu » = dans `removePlayer`. Alloc `doomed` → **N63 fermé**. |
| N26 | Notify / Sfx globaux `FireAllClients` | P2 | specs only. **≠ N26 feel (SAM 100 %).** |
| N27 | Pops de frontier périmés brûlent `guard` | P2 | **fermé via N38** |
| N28 | `retreatBoats` après flip | P2 | **partiel** : inbound fermé passe 8 ; `targetSlot` ouvert (recette feel N49/N53) |
| N29 | `seedBeachhead` no-merge | P2 | specs only |
| N30 | Missile inbound vs spawn recyclé | P2 | **fermé** (contrat B). Splash tiers → N33. **≠ N30 feel.** |
| N31 | Pool `findSeaPath` | P2 | **fermé** (recette feel N37, sans AimFront). Résultat → **N64 fermé**. **≠ N31 feel.** |
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
| N47 | `refreshRailNetwork` scan gares | P3 | **fermé** (`buildingsBySlot[slot]`). Recette feel N64. **Pas** `IS_STATION`. Alloc porteuses → **N65 fermé**. |
| N48 | `syncCarriers` spawn NAVAL_BASE | P3 | **fermé** (`navalBasesBySlot`). Recette feel 7c38 N65. **≠ N48 feel historique.** |
| N49 | `samsOf` alloc table | P3 | **fermé** (`samBuf`). Recette feel 1fb3 N68. **≠ N49 feel historique (targetSlot).** |
| N50 | `blastValue` × 90 tuiles frontière | P3 | **fermé** (`fillBlastBuf` / `scoreBlast`). Recette feel 5bf6 N69. **≠ N50 feel historique.** |
| N51 | Snapshot navires alloc 10 Hz | P2 | **fermé** (`snapshotBoats` + `boatSnapBuf`). Recette feel 5bf6 N70 **sans** `retreating`. **≠ N51 feel historique.** |
| N52 | Snapshot missiles alloc 10 Hz | P2 | **fermé** (`snapshotMissiles` + `missileSnapBuf`). Recette feel 741d N71. **≠ N52 feel historique (claimSpawn splash).** |
| N53 | `flushOwnerDelta` `indices` alloc | P3 | **fermé** (`dirtyIndexBuf`). Recette feel 741d N72. Buffer outbound **neuf**. **≠ N53 feel historique (Navy.step auto-flip).** |
| N54 | `flushBuildingDelta` alloc 10 Hz | P3 | **fermé** (`buildingSnapBuf`). Recette feel 55ba N73. `links` live. **≠ N54 feel historique (MIRV bus).** |
| N55 | HUD fronts `replicate()` alloc | P3 | **fermé** (`frontHudForReplicate`). Recette feel 55ba N74. **≠ N55 feel historique (claimSpawn isolation).** |
| N56 | `buildPrices` alloc 10 Hz × slots | P3 | **fermé** (`Buildings.pricesFor` / `priceBuf`). Recette feel 4876 N75. **≠ N56 feel historique (`retreating`).** |
| N57 | `stats[slot]` alloc 10 Hz × slots | P3 | **fermé** (`playerStatsForReplicate` / `statsBuf`). Recette feel 4876 N76. **≠ N57 feel historique (`samsBySlot`).** |
| N58 | `Research.progress` alloue `ratios` | P3 | **fermé** (min courant). Recette feel cc42 N77. **≠ N58 feel historique (SpawnHint).** |
| N59 | `Diplomacy.viewFor` alloc 7 tables | P3 | **fermé** (`viewBuf[slot]`). Recette feel cc42 N78. **Un record par slot**, pas un buf global. **≠ N59 feel historique (`samsOf`).** |
| N60 | `Diplomacy.step` alloc `expired` 10 Hz | P3 | **fermé** (`expiredBuf` + pool). Recette feel 2f5d N79. **≠ N60 feel historique (`stepCooldowns`).** |
| N61 | `Bots.neighborFactions` alloc hash contacts | P3 | **fermé** (`contactBuf`). Recette feel 2f5d N80. **≠ N61 feel historique (FACTORY flatten).** |
| N62 | `Bots.gatherSites` alloc array / décision | P3 | **fermé** (`siteBuf`). Recette feel 2f5d/b62d N81. **≠ N62 feel historique (`buildingsBySlot`).** |
| N63 | `stepElimination` alloc `doomed` 10 Hz | P3 | **fermé** (`elimBuf`). Recette feel 2f5d/b62d N82. **≠ N63 feel historique (`spawnTradeShips`).** |
| N64 | `findSeaPath` path + reversed | P3 | **fermé** (`pathWalkBuf`, retour unique). Recette feel 69f4 N83. **≠ N64 feel historique (`refreshRail`).** |
| N65 | `refreshRailNetwork` stations / parent | P3 | **fermé** (`stationBuf`, truncate avant sort). Recette feel 69f4 N84 **sans** `TRAIN_STOP_BONUS`. **≠ N65 feel historique (`navalBasesBySlot`).** |
| N66 | `Buildings.contextFor` record + closures | P3 | specs only. Recette feel 69f4 N85. **≠ N66 feel historique (`factoryBuf`).** |
| N67 | `ChantierB` doomed / collapsing 10 Hz | P3 | specs only. Recette feel 69f4 N86. **≠ N67 feel historique (`carrierBuf`).** |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu (reset à `startMatch` suffit) ; disconnect mid-match **vivant** = `Persistence.record(..., false)` 0 XP (chemin distinct de N37 ; éliminé puis leave **grave** le snapshot) ; wrap `launchAttack` n’applique `AimFront.focus` que si le couple n’existait pas (renfort = pas de re-visée — feel N36). Spatial hash warships (contrat A de N39) volontairement non fait. `Trade.step` `factoriesBuf` déjà recyclé (N45) ; early-out 0 usine / sort seulement si `n>=2` = reste de feel N66, cheap. `structureHash` O(B log B) seulement sur `RequestSnapshot` rate-limité (N4, client jamais `FireServer`). `priceBuf` / `statsBuf` / `viewBuf` / `expiredBuf` / `contactBuf` / `siteBuf` / `elimBuf` / `pathWalkBuf` / `stationBuf` non réentrants — `replicate()` unique / tick ; `viewFor` séquentiel par humain (un record **par slot**) ; `step` unique par tick ; les 4 appelants `neighborFactions` lisent puis abandonnent ; `decideBuild` lit `siteBuf` puis abandonne ; `findSeaPath` synchrone unique ; `refreshRailNetwork` unique par mutation.

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
| `RAIL_RANGE` | (Config) | (apply) | oui (`refreshRailNetwork` via `buildingsBySlot` — N47 / `stationBuf` — N65) |
| `TRAIN_STOP_BONUS` | (Config) | (apply) | **non** sur cette ligne (feel HUD N20 ; N65 n’a **pas** porté le × bonus) |

---

## 7. Preuve tests

```
./tests/run.sh  → exit 0
bundle server : 37 modules
Serveur : Tous les invariants tiennent.
  … gardes #17–#83 inchangés …
  findSeaPath pool : 5 tuiles, 4 appels identiques
  findSeaPath pathWalk : identite unique, p1 intact (N64)
  stationBuf : liens usine, income, identite (N65)
  stationBuf : slot sans joueur, pas d'erreur (N65)
  gatherSites : DEFENSE frontiere, rawequal, cap 60 (N62)
  elimBuf : vivant length 0, rawequal (N63)
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 captures=80 pops=160
  factions : 18
  metrics : ticks=6000 avgChanged=8.9 p95Changed=19 maxChanged=479 avgTickMs=0.38 p95TickMs=0.88
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe27.log`

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
- Transports : `kind == 1`. Convois : `kind == 2`. Missiles : `toIndex(floor(tx), floor(ty))` vs `owner` **avant** `setOwner`. Ne pas `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` depuis GameState (cycle).
- Missile inbound = **annulé**, pas remboursé. Convoi inbound = **coulé**, pas d’or. Convoi vs PORT **détruit** (combat, pas recycle) = **coulé** dans `Navy.step` (contrat B). Capture de PORT = convoi continue. Frappe / convoi déjà visé sur un tiers = conservé. Splash tiers / fallout au spawn = N33.
- `findSeaPath` : pools module-level, `buffer.fill(buf, 0, 0)`, `table.clear` parent/queue. `pathWalkBuf` walk scratch (N64) ; copie inverse dans un tableau **neuf**. Navy n’est pas réentrant. Ne pas porter AimFront avec. Ne **pas** `return pathWalkBuf` : `boat.path` prend possession.
- `tryAnnex` : appelé **après** `setOwner` ; BFS depuis les voisins défenseur du seed. Océan = abort (enclave terrestre), pas un bug. Pools `annexVisitBuf` / queue / pocket, `buffer.fill(buf, 0, 0)`.
- `syncCarriers` : `_carriersDirty` NAVAL_BASE seulement (`placeBuilding` / `destroyBuilding` / `transferBuilding`). Spawn via `navalBasesBySlot` (N48). `carrierSeen` recyclé. Pas de scan 10 Hz. Pas de dirty CITY/PORT. Distinct de `portsByTile` (PORT) et de `buildingsBySlot` (tous kinds).
- Ciblage warships : `carrierBuf` / `targetBuf` module-level, `table.clear`. Early-out si 0 carrier ou 0 autre slot. Priorité et `areAllied` inchangés. Pas de spatial hash (N39 contrat A non retenu).
- Commerce maritime : `portsByTile[index]={slot,level}` (PORT seulement). Early-out `countTradeShips >= MAX_TRADE_SHIPS` **avant** flatten. `portsBuf` / `candidateBuf` recyclés. Sort par index, poids = niveau, `canTrade` embargo-only. Ne pas recâbler `_carriersDirty`. `TRADE_SHIP_CHANCE` / gold inchangés.
- Commerce terrestre : `factoriesByTile[index]={slot,level}` (FACTORY seulement, N45). Flatten + `table.sort` par index (RNG). Buffer `factoriesBuf` recyclé. `delivery.level` snapshot au départ. `refreshRailNetwork` (N47) itère `buildingsBySlot[slot]` — ne pas le fusionner avec `factoriesByTile`. Ne pas recâbler N40 (`portsByTile`). Porteuses → N65 **fermé** : truncate **avant** sort, ne pas pooler `building.links`. Formule `railIncome` **sans** `TRAIN_STOP_BONUS` (N18 ouvert).
- Posted bunker : `bunkersBySlot[slot][tile]` + `bunkerCells[slot][cellKey]` (cell = `DEFENSE_RADIUS`, clé `floor(y/r)*1024+floor(x/r)`). Lookup 3×3 + dist², cassure au premier hit. Posted = **booléen**, pas un stack. Plus d’appels `applyDefenseAura`. Buffer `defense` alloué, plus écrit. Ne pas changer `DEFENSE_POST_BONUS` / `DEFENSE_RADIUS`.
- Posted SAM : `samsBySlot[slot][tile]` (N42). `tryIntercept` itère les SAM ennemis non alliés, pas `buildings`. `samsOf` lit le même index dans `samBuf` (N49). Un SAM = une cible (`engaged`). Ne pas changer `SAM_RANGE` / chance / cooldown. `samBuf` n’est pas réentrant — appelant unique `Bots.decideNuke`. Index présent + set nil = zéro SAM, **pas** de fallback hash.
- Posted SILO : `silosBySlot[slot][tile]` (N44). `Nukes.launch` n’itère que ce set. Un slot sans silo ne rescane **pas** le hash. Un SAM / PORT n’est jamais un lanceur. `armCooldown` reste la voie d’écriture (N43). Ne pas poser `silo.cooldown =` à la main (feel 5c74 le faisait — **ne pas porter ça** : ça gèlerait `coolingBuildings`). Ne pas changer `SILO_COOLDOWN` / coût / ère. Un silo = un missile. Ne pas `require(Nukes)` depuis GameState.
- Posted NAVAL_BASE : `navalBasesBySlot[slot][tile]` (N48). `syncCarriers` n’itère que cet index. Un slot sans base ne rescane **pas** le hash. Un PORT n’est jamais un carrier. Ne pas `require(Navy)` depuis GameState. Garder `_carriersDirty` (pas un scan 10 Hz).
- Tous kinds : `buildingsBySlot[slot][tile]` (N46). `lowestUpgradable` itère le set du bot ; `blastValue` / `fillBlastBuf` itère le set de la **cible** (N50). `removePlayer` snapshot les clés puis destroy. Un slot sans bâtiments ne rescane **pas** le hash. Ne pas spatial-hasher le blast. Ne pas relire `samsOf` via le hash (N42/N49). Ne pas recâbler `Nukes.launch` (N44) ni `factoriesByTile` (N45) ni `navalBasesBySlot` (N48).
- Score nuke : `fillBlastBuf` **une fois** avant la boucle 90, puis `scoreBlast` (N50). Index présent + set nil = buffer vide, score 0. `Bots.blastValue` (banc N46) réutilise le même helper. `blastX/Y/Level` n’est pas réentrant — `decideNuke` unique par bot par tick. Ne pas changer la règle « tout couvert → frapper le SAM ».
- Cooldown bâtiments : `Buildings.armCooldown` est **la** voie d’écriture (intercept + tir silo). `stepCooldowns` parcourt `coolingBuildings`, pas `buildings`. Ne **pas** n’itérer que les SAM : un silo a aussi un cooldown (contrat B de N43 rejeté). `destroyBuilding` retire du set.
- Gares : `refreshRailNetwork` collecte depuis `buildingsBySlot[slot]` (N47). Kinds inlinés (CITY/CAPITAL/PORT/FACTORY). **Ne pas** utiliser `IS_STATION` depuis cette fonction (local trop bas). Sort conservé. Événementiel, pas 10 Hz. Porteuses N65 : truncate **avant** sort, ne pas pooler `building.links`.
- Snapshot navires : `GameState.snapshotBoats` (N51). `boatSnapBuf` recycle inner records, truncate. **Pas** de `path` / `homeTile` / `_sink` / `retreating`. Overlay de cette ligne ne lit pas `retreating` (Types.BoatSnapshot, client 34/34). Ne pas `require(Navy)` depuis GameState.
- Snapshot missiles : `GameState.snapshotMissiles` (N52). `missileSnapBuf` recycle inner records, truncate. Champs **uniquement** `Types.MissileSnapshot`. Pas de `sx` / `sy` / `progress` / `speed`. Overlay interpolé via `tx`/`ty`. Ne pas `require(Nukes)` depuis GameState. `missileSnapBuf` n’est pas réentrant — `replicate()` unique / tick.
- Owner delta : `flushOwnerDelta` via `dirtyIndexBuf` (N53). Early-out dirty vide sans allouer. Buffer outbound **neuf**. Format `[u32 index][u8 slot]`. Ne pas recycler le `buffer` envoyé (RemoteEvent).
- BuildingDelta : `flushBuildingDelta` via `buildingSnapBuf` (N54). Early-out dirty vide sans allouer. Inner records recyclés, truncate. `links` = **référence live** (pas clone). Destruction `kind=0`. `buildingSnapBuf` n’est pas réentrant. Overlay `applyBuildingDelta` lit `entry.index` / `kind` / `slot` / `level` / `links`.
- HUD fronts : `GameState.frontHudForReplicate` (N55). Trois maps `table.clear` + `attackTargetPool`. Slots sans front absents. Chaque tas compte. N57 appelle N55 **une** fois — ne pas recounter dans `init.server`.
- Prix HUD : `Buildings.pricesFor` (N56). `priceBuf[slot]` + `table.clear`. Slot inconnu → `emptyPriceBuf` vide, pas `math.huge`. Ne pas require Buildings depuis GameState. Formule `Placement.priceFor` / doctrine `buildCost` inchangée.
- Records stats : `GameState.playerStatsForReplicate` (N57). `statsBuf` + `statsRecPool`. `eraProgress` / `buildPrices` = nil dans le helper ; `init.server` les pose. Ne pas require Research / Buildings depuis GameState.
- Progress ère : `Research.progress` min courant (N58). Pas de table `ratios`, pas de `ratiosBuf`. Slot inconnu / `era >= MAX_ID` → `1`. Formule inchangée. `init.server` pose `rec.eraProgress`.
- Vue diplomatique : `Diplomacy.viewFor` (N59). `viewBuf[slot]` + 6 maps persistantes. Slot sans joueur → maps vides. **Un record par slot**, pas un buf global (FireClient séquentiel). `areAllied` / `requestIsLive` inchangés. 1 Hz `FireClient`.
- Expiration pactes : `Diplomacy.step` (N60). `expiredBuf` + `expiredRecPool`. Collecte `a < b` **avant** mutation. `true` legacy : `typeof == "number"` (ne pas faire `tick >= expiry` nu — mixte number/boolean lève en Luau). Pas de marque traître. Truncate **après** traitement. `viewFor` / `request` / `accept` non touchés. `expiredBuf` n’est pas réentrant — `step` unique par tick.
- Contacts bots : `Bots.neighborFactions` (N61). `contactBuf` + `table.clear`. Slot 99 / sans joueur = map **vide**. NEUTRAL conservé. 4 appelants lisent puis abandonnent — pas de `table.clone`. Après `removePlayer`, tuiles du disparu = NEUTRAL.
- Sites de pose : `Bots.gatherSites` (N62). `siteBuf` + truncate. Caps 40/60/45. Pas de shuffle. DEFENSE = `ps.border`, PORT/NAVAL_BASE = `ps.coast`. Slot / côte / frontière vide → `# == 0`. Unique appelant `decideBuild` — pas de `table.clone`. `siteBuf` n’est pas réentrant.
- Élimination : `GameState.stepElimination` (N63). `elimBuf` (pas `doomed`). Truncate leftover **avant** `removePlayer`, pas à 0 après return. Buffer partagé inter-instances. Loi : `tiles==0` + pas d’attaque + pas de bateau. Bot = silencieux. Ne pas `require(Bots)` depuis GameState.
- Trajet mer : `Navy.findSeaPath` (N64). `pathWalkBuf` walk scratch. Copie inverse dans un tableau **neuf**. Origine terrestre **exclue**. Échec / `MAX_BFS_NODES` → `nil`. Ne pas `return pathWalkBuf`. Banc N31 (déterminisme) doit rester vert.
- Gares porteuses : `GameState.refreshRailNetwork` (N65). `stationBuf` + truncate **avant** sort. `railParentBuf` / `railXsBuf` / `railYsBuf` itérés `1..count`. Maps grappe `table.clear`. Inners `neighborsOf` uniques. Ne pas pooler `building.links`. Ne pas porter `TRAIN_STOP_BONUS`. Ne pas `require(Buildings)` depuis GameState.
- `init.server` / `Persistence` restent hors bundle : extraire un helper testable (`MatchLifecycle` / `snapshotBoats` / `snapshotMissiles` / `frontHudForReplicate` / `playerStatsForReplicate` déjà là) ou documenter un test Studio.
- Humain éliminé : `settledHumans[slot]` **avant** destruction du PlayerState. Bots ignorés. `endMatch` / disconnect après élimination passent par `MatchLifecycle` (init.server hors bundle). Disconnect **vivant** = 0 XP. `Persistence` reste hors du tick. Ne pas recâbler N6.
- Grâce humaine = `Bots.humanTargetProtected` (bots **et** tribus). Ne pas dupliquer une 2e courbe.
- Ne pas casser le client 34/34.
- Ligne feel (#19/#22/#24/#26/#28/#29/#32/#34/#36/#38/#41/#42/#45/#48/#51/#53/#56/#59/#62 + 55ba + 4876 + cc42 + 2f5d + b62d + **69f4**) : rebase sur cette passe avant cherry-pick, sinon perte `pathWalkBuf` / `stationBuf`. Cherry-pick seq obligatoire (N41 feel) et `targetSlot` (N49 feel) seulement — N40/N42/N45/N57/N59/N60/N61/N62/N64/N65/N67/N68/N69/N70/N71/N72/N73/N74/N75/N76/N77/N78/N79/N80/N81/N82/N83/N84 feel sont déjà redondants avec N36 / N37 / N39 / N42 / N43 / N44 / N45 / N46 / N47 / N48 / N49 / N50 / N51 / N52 / N53 / N54 / N55 / N56 / N57 / N58 / N59 / N60 / N61 / N62 / N63 / N64 / N65 hardening. N50/N52 feel (`findSpawn` / `isSpawnSafe`) porte N33. N85 feel (`contextFor`) = N66 ici. N86 feel (`doomedBuf` / `collapsingBuf`) = N67 ici. **Ne pas** porter `retreating` Overlay (feel N56) avec N51. **Ne pas** porter `TRAIN_STOP_BONUS` HUD (feel N20) avec N65.
