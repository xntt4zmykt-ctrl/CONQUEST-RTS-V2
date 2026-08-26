# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 30)

Déclencheur : ouverture de la **PR #91** (`cursor/analyse-nocturne-du-codebase-9327`) — `parkedBuf`, `collapseRemainBuf`, specs N70–N71.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-ae35`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #91**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#91. Pas d’outil Slack.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29/#32/#34/#36/#38/#41/#42/#45/#48/#51/#53/#56/#59/#62 + d425 + df65 + 2157 + 5c74 + e735 + 7c38 + 1fb3 + 5bf6 + 741d + 55ba + 4876 + cc42 + 2f5d + b62d + 69f4 + 07c6 + 2b37 + **e277 passe 30**) : ne pas merger sur cette branche sans rebase. Les numéros N40+ feel (settledHumans, seq, N52–N92…) ne sont **pas** les N40–N73 de ce rapport. Cette passe **ferme** hardening N70 (`removePlayer` `destroyBuf`) et N71 (`Placement.validTiles`). Seq obligatoire (feel N41) et `targetSlot` (feel N49/N53) ne sont pas portés. **Pas** de `TRAIN_STOP_BONUS` dans `railIncome` (feel N20 / N84 — volontaire). Feel e277 N89 (`destroyBuf`) et N90 (`validTiles`) sont **portés**. Client hardening = **34/34** (feel 35/35 — Overlay `retreating`).

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`. `RequestSnapshot` n’est toujours jamais `FireServer` côté client (N4). DAG : `GameState` ne `require` ni Navy, ni Nukes, ni Trade, ni Bots, ni Buildings, ni Research, ni Diplomacy, ni Placement. `Buildings`, `Research`, `Diplomacy` require déjà `GameState` ; `Placement` require Shared only — ne pas inverser. N66 (`ctxBuf`) vit dans Buildings. N67 (`doomedBuf`) vit dans ChantierB (`install()` serveur seulement). N68 (`parkedBuf`) vit dans BoatFront. N69 (`collapseRemainBuf`) vit dans GameState. N70 (`destroyBuf`) vit dans GameState (`removePlayer`). N71 (`blockBuf` / `candBuf` / `queueBuf` / `visitMap` / `emptyTileBuf` / `placeScratch`) vit dans Placement (Shared, pas le ctx client).

La PR #91 a bien fermé `parkedBuf` (N68) et `collapseRemainBuf` (N69). Cette passe a **corrigé ce que #91 a spécifié** — `removePlayer` allouait encore `doomed` snapshot, et `Placement.validTiles` allouait encore blockers/candidates/queue/visited :

| Bug | Gravité | Statut |
|---|---|---|
| `removePlayer` snapshot `doomed` bâtiments (N70) | **P3 alloc élimination** | **corrigé** (`destroyBuf`, recette feel 2b37 N89 / worker #91) |
| `Placement.validTiles` blockers / candidates (N71) | **P3 alloc pose** | **corrigé** (`blockBuf`/`candBuf`/`queueBuf`/`visitMap`/`emptyTileBuf`/`placeScratch`, recette feel 2b37 N90 / worker #91) |
| `Bots.decideDiplomacy` snapshot `alliances[] or {}` (N72) | **P3 alloc bots** | **ouvert** (visual d3e2 V42 `allyBuf`) |
| `ChantierB.stepDoomsday` `toStrip = {}` par slot (N73) | **P3 alloc cadran** | **ouvert** (visual d3e2 V43 `stripBuf`) |
| `retreatBoats` filtre `owner[targetTile]` courant | **P2 marine** | **ouvert** (reste de N28 ; feel d425/df65 a la recette) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29) |
| `findSpawn` ignore splash / fallout (N33) | **P3 nucléaire** | **ouvert** (feel d425/df65 a C1+C2 + `isSpawnSafe`) |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#91 + destroyBuf (N70) + validTiles (N71).
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #91

**À merger** (`parkedBuf` + `collapseRemainBuf` + specs N70–N71), sous réserve que cette passe 30 parte avec : **`removePlayer` allouait encore `doomed` et `validTiles` allouait encore blockers / candidates**.

Points encore vrais après #91 :

| Claim #91 | Réalité après passe 30 |
|---|---|
| `BoatFront.launchAttack` recycle `parkedBuf` (N68) | confirmé |
| `GameState.collapseFaction` recycle `collapseRemainBuf` (N69) | confirmé |
| N70 `removePlayer` `destroyBuf` | **fermé ici** (truncate avant destroy, leftover 0, CITY de B survit) |
| N71 `Placement.validTiles` | **fermé ici** (`emptyTileBuf` rawequal, deux resolve CITY tile identique) |
| N33 `findSpawn` splash / fallout | **ouvert** |
| N28 retraite après flip / `targetSlot` | **ouvert** |
| N29 `seedBeachhead` no-merge | specs only, inchangé (banc N68 documente 3 Attack) |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |

`init.server.luau` et `Persistence` restent **exclus du bundle**. Le helper `MatchLifecycle` est **dans** le bundle (37 modules serveur). `snapshotBoats` / `snapshotMissiles` / `flushOwnerDelta` / `flushBuildingDelta` / `frontHudForReplicate` / `playerStatsForReplicate` sont **dans** le bundle (`GameState`). `pricesFor` / `contextFor` vivent dans **Buildings**. `progress` ne alloue plus `ratios` (N58). `Diplomacy.viewFor` recycle `viewBuf[slot]` (N59). `Diplomacy.step` recycle `expiredBuf` (N60). `neighborFactions` recycle `contactBuf` (N61). `gatherSites` recycle `siteBuf` (N62). `stepElimination` recycle `elimBuf` (N63). `findSeaPath` recycle `pathWalkBuf` (N64) — le tableau rendu au bateau **reste unique**. `refreshRailNetwork` recycle `stationBuf` (N65) — `building.links` **reste unique**. `Buildings.contextFor` recycle `ctxBuf` (N66) — pas le ctx client. `ChantierB` recycle `doomedBuf` / `collapsingBuf` (N67). `BoatFront.launchAttack` recycle `parkedBuf` (N68). `collapseFaction` recycle `collapseRemainBuf` / `collapseLeftBuf` (N69). `removePlayer` recycle `destroyBuf` (N70). `Placement.validTiles` recycle blockers/candidates (N71). `decideDiplomacy` snapshot `or {}` encore alloué (N72). `stepDoomsday` `toStrip` encore alloué (N73).

PR #89 (feel passe 29, `2b37`) ne doit pas être mergée par-dessus #16/#91 sans rebase. `parkedBuf` (feel N87) et `collapseRemainBuf` (feel N88) étaient **déjà portés** en #91. Seq / `targetSlot` / hover `SpawnHint` / Overlay `retreating` / `TRAIN_STOP_BONUS` HUD restent feel-only. Feel N89/N90 → N70/N71 **fermés ici**. Visual d3e2 V42 (`allyBuf`) / V43 (`stripBuf`) → N72/N73.

On peut fermer #17, #18, #20, #23, #25, #27, #30, #31, #33, #35, #37, #40, #43, #46, #49, #52, #55, #58, #60, #63, #66, #70, #73, #76, #80, #83, #85, #88 et #91 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| `removePlayer` alloc `doomed` snapshot | `GameState.removePlayer`, `GameState.destroyBuf`, `tests/simulate.luau` | Array module-level. Truncate leftover **avant** `destroyBuilding`. Itérer `1..n`. Fallback hash conservé. Slot sans bâtiment → leftover 0. Slot déjà absent → return. A CITY + B CITY autre index → CITY de B survit. Recette worker #91 / feel 2b37 N89. Ne ferme **pas** N63 / N67 / N69. |
| `Placement.validTiles` alloc blockers / candidates | `Placement.validTiles`, `blockBuf`/`candBuf`/`queueBuf`/`visitMap`/`emptyTileBuf`/`placeScratch`, `tests/simulate.luau` | Early-out → `emptyTileBuf` (jamais d’insert, `rawequal`). Truncate queue **avant** BFS, candidats **avant** sort. Itérer `1..n`. Retourner `candBuf` (pas clone). `visitMap` pas `visitBuf`. `placeScratch` (leftover N71 autorisé). Deux `resolve` CITY → `tile` identique. Recette worker #91 / feel 2b37 N90. Ne ferme **pas** N66. Client **34/34**. |

**Non modifié (volontaire) :** N1–N69 restant, reste de N28 (`targetSlot`). N10.8. Cap beachheads (N5 / N29). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` / `require(Placement)` depuis GameState. Pas de contrat C spawn (N33). Pas de seq obligatoire (feel N41). Pas de spatial hash warships. Buffer `defense` **alloué** mais plus écrit. Pas de `TRAIN_STOP_BONUS` dans `railIncome` (N18 / feel N20). `decideDiplomacy` snapshot encore alloué (N72). `stepDoomsday` `toStrip` encore alloué (N73). Pas de `retreating` Overlay (feel N56 historique). Debit `captures`/`pops` **non** remplacé par feel `guard < 80`. `PlacementPreview` / `tests/client.luau` **non** édités.

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead + parkedBuf), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + **captures < 80 et pops < 160**). `cancelOpposingFronts` recycle `doomedBuf` ; wrap recycle `collapsingBuf` (N67).
- **Posted bunker** = `bunkersBySlot[slot][tile]` + grille `bunkerCells[slot][cellKey]` (cell = `DEFENSE_RADIUS`). Capture → `transferBuilding` change de panier **et** de cellule. Lookup 3×3 par capture (N41).
- **Posted SAM** = `samsBySlot[slot][tile]` (N42). `tryIntercept` ne scanne plus `buildings`. `samsOf` lit le même index dans `samBuf` recyclé (N49).
- **Posted SILO** = `silosBySlot[slot][tile]` (N44). `Nukes.launch` n’itère que ce set.
- **Posted FACTORY** = `factoriesByTile[index]={slot,level}` (N45). `Trade.step` flatten depuis l’index, pas `buildings`.
- **Tous kinds** = `buildingsBySlot[slot][tile]` (N46). Bots upgrade / score nuke + collecte gares (N47). Distinct des index par kind. Score nuke = flatten une fois (N50), puis 90 `scoreBlast`.
- **Posted NAVAL_BASE** = `navalBasesBySlot[slot][tile]` (N48). `syncCarriers` spawn via l’index. Distinct de `portsByTile` (PORT) et de `buildingsBySlot` (tous kinds).
- **Cooldown bâtiments** = `coolingBuildings[index]` (N43). Unique écriture : `Buildings.armCooldown`. SAM **et** silos. `launch` continue d’appeler `armCooldown`.
- **Têtes de pont** = `BoatFront.seedBeachhead` : frontier = **voisins encore à la cible**, flag `isBeachhead`. `launchAttack` gare les beachheads dans `parkedBuf` avant fusion (N68).
- **Retraite** = couple `(attacker, target)` : tous les fronts + `Navy.retreatBoats`.
- **Pacte vivant** = `areAllied` : deux sens **et** `tick < expiry` (ou `true` legacy tests). Bots et tribus doivent passer par là, pas `alliances[]`.
- **Proposition vivante** = `requestIsLive` (`tick < expiry`). Croisement = accept **seulement** si encore live.
- **Comptabilité fronts** = `GameState.returnCommittedTroops` (pacte, défenseur disparu). Retraite terre = `RETREAT_LOSS`. Cote déjà nôtre = 100 %. **Transports inbound d’un disparu = 100 %**. **Missiles inbound = annulés, or du tireur conservé**. **Convois inbound = coulés, pas d’or**. **Convoi vs PORT détruit = coulé, pas d’or**.
- **Enclaves** = `ChantierB.tryAnnex` **après** `setOwner` : BFS depuis les voisins défenseur du seed. Océan = abort.
- **Porte-avions** = `syncCarriers` **événementiel** (`_carriersDirty`, NAVAL_BASE seulement) + spawn via `navalBasesBySlot` (N48). Ciblage obus = listes recyclées (N39), pas nested sur tout `state.boats`.
- **Commerce maritime** = `portsByTile` incrémental (PORT seulement, N40). Vague plafonnée **avant** flatten. `canTrade` = embargo-only.
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients` (N26). Snapshot navires = `GameState.snapshotBoats` (`boatSnapBuf`, N51). Snapshot missiles = `GameState.snapshotMissiles` (`missileSnapBuf`, N52). Owner delta = `dirtyIndexBuf` (N53), buffer outbound **neuf**. BuildingDelta = `buildingSnapBuf` (N54), `links` live. HUD fronts = `frontHudForReplicate` (N55), appelé **une** fois depuis N57. `buildPrices` = `Buildings.pricesFor` (N56). Records stats = `playerStatsForReplicate` (N57). `Research.progress` min courant (N58). `Diplomacy.viewFor` recycle par slot (N59). `Diplomacy.step` recycle `expiredBuf` (N60). `neighborFactions` recycle `contactBuf` (N61). `gatherSites` recycle `siteBuf` (N62). `stepElimination` recycle `elimBuf` (N63). `findSeaPath` `pathWalkBuf` (N64, retour unique). `refreshRailNetwork` `stationBuf` (N65). `contextFor` `ctxBuf` (N66). Combat `doomedBuf`/`collapsingBuf` (N67). `parkedBuf` (N68). `collapseRemainBuf` (N69). Snapshot destroy `destroyBuf` (N70). `validTiles` blockers (N71). `allyBuf` (N72). `stripBuf` (N73).
- **DataStore** : `settledHumans` avant destruction du PlayerState. `endMatch` grave via `MatchLifecycle.endMatchRecords`. `Persistence.record` max-merge inchangé (N6).
- **Require** : DAG. Pas de cycle. `MatchLifecycle` → Config seulement. `Tribes` → `Bots` (export `humanTargetProtected` seulement). `Navy` → `GameState` (unidirectionnel). `Nukes` → `GameState` + `Buildings`. `Trade` → `GameState`. `Bots` → `GameState` (pas l’inverse). `Buildings` → `GameState` (pas l’inverse — N56/N66 vivent dans Buildings). `Research` → `GameState` (pas l’inverse). `Diplomacy` → `GameState` (pas l’inverse). `Placement` → Shared only (N71 — **ne pas** require Placement depuis GameState). `ChantierB`/`BoatFront`/`AimFront` dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).
- **BFS mer** : `visitBuf` + `parentScratch` + `queueScratch` + `pathWalkBuf` module-level. Un seul chemin en vol à la fois (Navy n’est pas réentrant). Résultat path **unique** (copie inverse, N64).
- **BFS annex** : `annexVisitBuf` + `annexQueue` + `annexPocket` module-level. Un seul `tryAnnex` en vol à la fois (combat n’est pas réentrant).
- **Gares** : `stationBuf` + `railParentBuf` / `railXsBuf` / `railYsBuf` + maps grappe. Truncate **avant** sort. `building.links` unique (N65).
- **Pose** : `ctxBuf` + closures module. Non réentrant. `terrain` = buffer live (N66). `validTiles` recycle `blockBuf`/`candBuf`/`queueBuf`/`visitMap` (N71). `emptyTileBuf` jamais d’insert.
- **Clash / collapse wrap** : `doomedBuf` hash + `collapsingBuf` / `collapseRecPool`. Truncate leftover **avant** `collapseFaction` (N67). Balayage tuiles recyclé (N69).
- **Park beachhead** : `parkedBuf` module-level. Truncate leftover **avant** `origLaunch` (N68).
- **Collapse tuiles** : `collapseRemainBuf` / `collapseLeftBuf` + swap. Truncate leftover **avant** plunder (N69).
- **Destroy snapshot** : `destroyBuf` module-level. Truncate leftover **avant** `destroyBuilding` (N70). `GameState.destroyBuf` exposé banc.
- **validTiles** : `blockBuf`/`candBuf`/`queueBuf`/`visitMap`/`emptyTileBuf`/`placeScratch`. Truncate avant BFS et avant sort (N71).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N73 restent ouverts** sauf N19 partiel, N21 **fermé**, N24 remplacé par N31 (**fermé**), N30–N32 **fermés**, N34–N71 **fermés**. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + le reste de N28 / N29 / N33.

---

### ISSUE-N28 — `retreatBoats` / `retreatAttack` après flip de côte (reste)

**Priorité :** P2 combat / comptabilité navale. **Partiel :** inbound `removePlayer` **fermé** en passe 8.

**Problème restant :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetSlot`. Conséquences encore vraies :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers).
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

Feel d425 (N49) + df65 (N53) : `launchInvasion` pose `targetSlot`, `retreatBoats` filtre l’intention (fallback `owner[targetTile]`), wrap 2e geste rappelle les tardifs, `Navy.step` auto-retraite si `owner[targetTile] ~= targetSlot`. **Porter, ne pas réinventer.** Distinct de N10.8 et du fix inbound. Distinct de N35 (`destSlot` convoi ≠ `targetSlot` invasion). Distinct de N40 / N44–N73 (index / snapshots / HUD / `progress` / `viewFor` / `expired` / contacts / sites / elim / path / rail / ctx / doomed / parked / collapse / destroy / validTiles, **fermés** ou **specs**).

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite.

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste, trancher si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`. Recette feel : branche `d425` / `df65`.

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N22). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % déjà livré). Ne pas recâbler N35 (convois, `kind==2`). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).** Ne pas porter AimFront ni seq. Ne pas recâbler N50–N73.

---

### ISSUE-N29 — `seedBeachhead` ne fusionne plus le couple naval

**Priorité :** P2 combat / cap.

**Problème :** `GameState.seedBeachhead` de base fusionnait `(attacker, target)`. `BoatFront.install` **remplace** la fonction et `table.insert` toujours un nouvel `Attack` `isBeachhead`. Deux débarquements vs le même défenseur = deux fronts, pools de troupes séparés, deux consommations de debit `captures < 80`. Combiné à N5 (parking hors cap land), un joueur peut tenir 2 beachheads + 1 terre = 3 offensives alors que `MAX_ACTIVE_ATTACKS_PER_PLAYER = 2`. Le banc N68 **documente** ce 3 = 2 ponts + 1 terre (ne pas le « corriger » dans N68).

**Pourquoi 20K CCU :** late-game invasions multiples. Ce n’est pas N11 (`MAX_TILES_PER_TICK` mort) ni N38/N41 (debit / lookup bunker, **fermés**) : ici le **nombre de tas** explose, chacun avec son `while captures < 80`.

**Worker :**

1. Confirmer le contrat OpenFront : **un** front naval par couple `(attacker, target)`, distinct du front terre. Si oui : dans `BoatFront.seedBeachhead`, trouver un `isBeachhead` existant du couple, ajouter `troops`, enfiler les nouveaux voisins, return. Si le tas est vide après enqueue, refund comme aujourd’hui.
2. Si le produit **veut** les griffes multiples : documenter dans Config, et **compter** les beachheads dans le cap (fermer N5 dans le même PR). Pas les deux à la fois.
3. Test : deux `seedBeachhead` même couple → `#attacks == 1` et `troops` somme **ou** (si multi-prong assumé) `launchAttack` refuse au-delà du cap y compris parked. Le banc N68 (3 Attack) devra alors être mis à jour.
4. Fichiers : `BoatFront.luau`, éventuellement `GameState.launchAttack` / wrapper parking, `tests/simulate.luau`.

**Contraintes :** ne pas fusionner beachhead avec front terre (régression BoatFront / aim). Ne pas changer `attackTilesPerTick`. Ne pas mixer avec N28 (bateaux inbound / targetSlot). Ne pas mixer avec N68 (`parkedBuf` — leftover alloc, **déjà fermé**). **N29 hardening ≠ N29 feel (seq avant apply).**

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

**Contraintes :** ne pas annuler une frappe tiers (régression `nuke third-party`). Ne pas rembourser l’or. Pas de RemoteFunction. Rayon lu depuis `NUKE_STATS` / `missile.radius`, pas une constante magique. Ne pas porter isolation clic (feel N55) dans le même PR. Ne pas recâbler N50–N73.

---

### ISSUE-N72 — `Bots.decideDiplomacy` alloue `alliances[] or {}` et itère la table brute

**Priorité :** P3 alloc bots / diplomatie. Leftover explicite de N61 (`neighborFactions` / `contactBuf` — « ne pas mixer avec breakAlliance »). Distinct de N61 (`contactBuf` voisins de tuiles) et de N59 (`viewBuf` HUD). Ne pas toucher `areAllied` / `requestIsLive` / seuils 0.75/0.35/2.2. **N72 hardening ≠ N72 feel historique (`flushOwnerDelta`, déjà N53 ici).** Visual d3e2 V42 décrit le même trou.

**Problème :** chaque `decideDiplomacy` (tous les bots, 10 Hz) fait `local allies = state.alliances[slot] or {}`. Un bot sans pacte alloue une table vide. Un bot avec pactes itère `alliances[]` brute puis re-filtre `areAllied` (un pacte périmé reste en table jusqu’à `Diplomacy.step`, qui tourne **après** `Bots.step`). `breakAlliance` mute le hash pendant l’itération. Visual d3e2 : snapshot `areAllied` dans `allyBuf` (hash, `table.clear`), puis itérer le snapshot — leftover `breakAlliance` sans clear = coalition fantôme au bot suivant.

**Pourquoi 20K CCU :** leftover N61. 16 bots × 10 Hz × table vide (`or {}`) + itération d’un hash muté. Recycle de la porteuse + snapshot `areAllied` aligne bots sur la vérité d’expiry (déjà la règle N61 / N34). Pas d’autorité (mêmes seuils, même `Diplomacy.request` / `breakAlliance`). Ne pas fusionner avec `contactBuf` : contacts = voisins de tuiles, allyBuf = pactes vivants.

**Worker :**

1. Ajouter `allyBuf: { [number]: boolean } = {}` module-level dans `Bots.luau`. `decideDiplomacy` : `table.clear(allyBuf)` ; pour chaque `other` dans `state.players` si `other ~= slot` et `state:areAllied(slot, other)` alors `allyBuf[other] = true`. Remplacer `not state:areAllied(...)` / `for ally in allies` par `allyBuf[other]` / `for ally in allyBuf`. Coalition : `not allyBuf[other]` (plus `not areAllied`). Trahison : itérer `allyBuf` (plus le `continue` `not areAllied`). Proposition : `not allyBuf[other]`. Pas de RemoteFunction. Hash, pas array — `table.clear`, pas de truncate.
2. Ne pas modifier `neighborFactions` (`contactBuf` déjà). Ne pas changer `COALITION_ALLY_CHANCE` / `COALITION_EMBARGO_CHANCE` / 0.75 / 0.35 / 2.2 / 0.25 / 0.3 / contacts `> 4`. Ne pas `require` de module nouveau. `Bots.allyBuf` exposé banc. `Bots.step` séquentiel — un second `clear` au bot suivant est **voulu**. Ne pas recâbler N70/N71.
3. Test : bancs N61 `neighborFactions` + bot expiry ally **doivent rester verts**. Ajouter : deux `decideDiplomacy` successifs même bot → `rawequal(Bots.allyBuf)`. `breakAlliance` puis second bot sans pacte → `next(allyBuf) == nil` (leftover). Slot isolé 0 pacte → `next(allyBuf) == nil`. Client **34/34**. 6000 ticks.
4. Fichiers : `Bots.luau` (`decideDiplomacy` seulement, du `local allies` jusqu’à la proposition), `tests/simulate.luau` (bloc court à côté du banc N61). Recette visual : branche `d3e2` V42 (**porter, ne pas réinventer**). Feel n’a pas encore ce ticket.

**Contraintes :** pas de RemoteFunction. Recette N61 (`contactBuf` leftover interdit de toucher `decideDiplomacy` — c’est **ce** leftover). **N72 hardening ≠ N61 (`contactBuf`, déjà fait) ≠ N59 (`viewBuf`) ≠ N72 feel historique (`dirtyIndexBuf`).** `allyBuf` n’est pas réentrant. Un leftover sans `clear` ferait proposer / trahir un pacte fantôme du bot précédent. Ne pas itérer `state.alliances[slot]` comme vérité (règle bots : `areAllied`). Overlay n’itère pas cette liste. Ne pas `require(Bots)` depuis GameState.

---

### ISSUE-N73 — `ChantierB.stepDoomsday` alloue `toStrip` par slot pourri

**Priorité :** P3 alloc cadran. Leftover explicite de N9 (`stepDoomsday` O(TILE_COUNT) — « le scan rot est toujours O(tuiles) ») et de N70 (`destroyBuf` élimination, pas rot). Distinct de N9 (scan encore, **ce** ticket = liste temporaire seulement) et de N67 (`collapsingBuf` combat). Ne pas toucher `Doomsday.rotQuota` / WARN / drain. **N73 hardening ≠ N73 feel historique (`flushBuildingDelta`, déjà N54 ici).** Visual d3e2 V43 décrit le même trou.

**Problème :** chaque slot sous quota (10 Hz, late-game plusieurs camps) fait `local ripped, toStrip = 0, {}` puis `table.insert` jusqu’à `quota * 4`. Une allocation porteuse + N inserts par camp qui saigne. La loi (scan `TILE_COUNT` jusqu’au cap, arracher `quota` tuiles, `destroyBuilding` puis `setOwner(NEUTRAL)`, skip AFK / `awaitingSpawn`) ne change pas. Un leftover d’un slot A dans le slot B du **même tick** ferait `setOwner(NEUTRAL)` sur le camp précédent.

**Pourquoi 20K CCU :** leftover N9. Un shard 18 slots en cadran late-game saigne plusieurs camps / tick. Recycle de la porteuse élimine l’alloc courte. Pas d’autorité (même scan, même `rotQuota`). Ne pas fusionner avec `destroyBuf` : destroy snapshot les bâtiments d’un disparu, stripBuf liste des tuiles à pourrir. Ne pas fusionner avec V13 / N9 (index compact / reservoir — ticket **suivant**, pas celui-ci).

**Worker :**

1. Ajouter `stripBuf: { number } = table.create(64)` module-level dans `ChantierB.luau` (à côté de `doomedBuf`, **pas** dans GameState — `stepDoomsday` vit dans `install()`). Pour chaque slot qui saigne : n = 0 ; scan `TILE_COUNT` → `stripBuf[n] = index`, break si `n >= quota * 4`. Truncate leftover n+1..# **avant** l’arrachage. Itérer `1..n`, pas `#`. Après le slot : truncate `1..n` à 0 (un leftover ferait arracher le camp précédent au slot suivant du même tick). Pas de RemoteFunction.
2. Ne pas modifier `Doomsday.rotQuota` / `troopFloor` / `drain` / WARN_SECONDS. Ne pas toucher `destroyBuf` (N70 déjà) ni `elimBuf` (N63). Ne pas require de module nouveau. `ChantierB.stripBuf` exposé banc. Ne pas remplacer le scan 40 960 (ça c’est N9 / visual V13 — ticket suivant). Ne pas recâbler N70/N71. Skip AFK / `awaitingSpawn` **conservé**.
3. Test : bancs doomsday recycle / AFK clear existants **doivent rester verts**. Ajouter : un camp sous quota → `ripped <= quota`, `ps.tiles` vs buffer. Deux camps saignent le même tick → le second n’arrache pas les tuiles du premier (leftover). Slot `awaitingSpawn` → `stripBuf` non lu / pas d’erreur. Client **34/34**. 6000 ticks.
4. Fichiers : `ChantierB.luau` (`stepDoomsday` boucle `toStrip` seulement), `tests/simulate.luau` (bloc court à côté du banc doomsday recycle). Recette visual : branche `d3e2` V43 (**porter, ne pas réinventer**). Feel n’a pas encore ce ticket.

**Contraintes :** pas de RemoteFunction. Recette N63 (`elimBuf` truncate leftover **avant** traitement) + reset **après** (boucle slots). **N73 hardening ≠ N9 (scan O(carte), encore) ≠ N70 (`destroyBuf`, déjà fait) ≠ N67 (`collapsingBuf`) ≠ N73 feel historique (`buildingSnapBuf`).** `stripBuf` n’est pas réentrant. `stepDoomsday` unique par tick, mais boucle les slots — truncate **à chaque** slot. Un leftover sans truncate ferait `setOwner(NEUTRAL)` d’une tuile encore occupée du camp précédent. Overlay n’itère pas cette liste. Ne pas `require(ChantierB)` depuis GameState. Formule `rotQuota` **inchangée**.

---

## 5b. N1–N73 encore ouverts ou fermés (passes 2–30)

| ID | Titre | Prio | Note passe 30 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + `SAM_INTERCEPT_CHANCE` 0.55→1 ; clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz ; bateaux → **N51 fermé** ; missiles → **N52 fermé** ; indices dirty → **N53 fermé** ; bâtiments → **N54 fermé** ; HUD fronts → **N55 fermé** ; `buildPrices` → **N56 fermé** ; records stats → **N57 fermé** ; `progress` → **N58 fermé** ; `viewFor` → **N59 fermé** ; `expired` → **N60 fermé** ; contacts → **N61 fermé** ; sites → **N62 fermé** ; elim → **N63 fermé** ; path → **N64 fermé** ; rail → **N65 fermé** ; ctx → **N66 fermé** ; doomed → **N67 fermé** ; parked → **N68 fermé** ; collapse → **N69 fermé** ; destroy → **N70 fermé** ; validTiles → **N71 fermé** ; reste skip-si-inchangé |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` **jamais** `FireServer` côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | park `isBeachhead` → hors cap land ; **2 beachheads parked + 1 terre = 3** — voir N29 ; alloc parked → **N68 fermé** |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | refund + retraite `RETREAT_LOSS` alignés ; le reste du corps est mort ; `tileCost` lit encore `defense` (buffer plus écrit) ; wrap vivant → **N67 fermé** ; `collapseFaction` remaining → **N69 fermé** |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | timers slot maintenant purgés ; le scan rot est toujours O(tuiles) ; liste temporaire → **N73** |
| N10 | Divers P3 | P3 | donations gold sans plafond ; `pendingMode` last-writer ; README SmoothTerrain ; `contextFor` → **N66 fermé** ; `validTiles` → **N71 fermé** |
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
| N25 | `checkVictory` / `stepElimination` → Persistence + cap | P2 | **N37 fermé** (record). Cap humains éliminés / firehose encore ouverts. Purges « disparu » = dans `removePlayer`. Alloc `doomed` slots → **N63 fermé**. Snapshot bâtiments → **N70 fermé**. |
| N26 | Notify / Sfx globaux `FireAllClients` | P2 | specs only. **≠ N26 feel (SAM 100 %).** |
| N27 | Pops de frontier périmés brûlent `guard` | P2 | **fermé via N38** |
| N28 | `retreatBoats` après flip | P2 | **partiel** : inbound fermé passe 8 ; `targetSlot` ouvert (recette feel N49/N53) |
| N29 | `seedBeachhead` no-merge | P2 | specs only. Banc N68 documente 3 Attack (2 ponts + terre). |
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
| N61 | `Bots.neighborFactions` alloc hash contacts | P3 | **fermé** (`contactBuf`). Recette feel 2f5d N80. Leftover `decideDiplomacy` → **N72**. **≠ N61 feel historique (FACTORY flatten).** |
| N62 | `Bots.gatherSites` alloc array / décision | P3 | **fermé** (`siteBuf`). Recette feel 2f5d/b62d N81. **≠ N62 feel historique (`buildingsBySlot`).** |
| N63 | `stepElimination` alloc `doomed` 10 Hz | P3 | **fermé** (`elimBuf`). Recette feel 2f5d/b62d N82. Snapshot bâtiments `removePlayer` → **N70 fermé**. **≠ N63 feel historique (`spawnTradeShips`).** |
| N64 | `findSeaPath` path + reversed | P3 | **fermé** (`pathWalkBuf`, retour unique). Recette feel 69f4 N83. **≠ N64 feel historique (`refreshRail`).** |
| N65 | `refreshRailNetwork` stations / parent | P3 | **fermé** (`stationBuf`, truncate avant sort). Recette feel 69f4 N84 **sans** `TRAIN_STOP_BONUS`. **≠ N65 feel historique (`navalBasesBySlot`).** |
| N66 | `Buildings.contextFor` record + closures | P3 | **fermé** (`ctxBuf` + closures module). Recette feel 07c6 N85. Leftover Placement → **N71 fermé**. **≠ N66 feel historique (`factoryBuf`).** |
| N67 | `ChantierB` doomed / collapsing 10 Hz | P3 | **fermé** (`doomedBuf` hash + `collapsingBuf` pool). Recette feel 07c6 N86. **≠ N67 feel historique (`carrierBuf`).** |
| N68 | `BoatFront.parked` par lancer | P3 | **fermé** (`parkedBuf`). Recette feel 2b37 N87. **≠ N68 feel historique (`samsOf`).** |
| N69 | `collapseFaction` remaining / leftovers | P3 | **fermé** (`collapseRemainBuf` / `collapseLeftBuf`). Recette feel 2b37 N88. **≠ N69 feel historique (`blastValue`).** |
| N70 | `removePlayer` snapshot `doomed` bâtiments | P3 | **fermé** (`destroyBuf`). Recette feel 2b37 N89. **≠ N70 feel historique (`snapshotBoats`).** |
| N71 | `Placement.validTiles` blockers / candidates | P3 | **fermé** (`blockBuf`/`candBuf`/`queueBuf`/`visitMap`/`emptyTileBuf`/`placeScratch`). Recette feel 2b37 N90. **≠ N71 feel historique (`snapshotMissiles`).** |
| N72 | `Bots.decideDiplomacy` snapshot `or {}` | P3 | specs only. Recette visual d3e2 V42. **≠ N72 feel historique (`dirtyIndexBuf`).** |
| N73 | `ChantierB.stepDoomsday` `toStrip` par slot | P3 | specs only. Recette visual d3e2 V43. **≠ N73 feel historique (`buildingSnapBuf`).** |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu (reset à `startMatch` suffit) ; disconnect mid-match **vivant** = `Persistence.record(..., false)` 0 XP (chemin distinct de N37 ; éliminé puis leave **grave** le snapshot) ; wrap `launchAttack` n’applique `AimFront.focus` que si le couple n’existait pas (renfort = pas de re-visée — feel N36). Spatial hash warships (contrat A de N39) volontairement non fait. `Trade.step` `factoriesBuf` déjà recyclé (N45) ; early-out 0 usine / sort seulement si `n>=2` = reste de feel N66, cheap. `structureHash` O(B log B) seulement sur `RequestSnapshot` rate-limité (N4, client jamais `FireServer`). `priceBuf` / `statsBuf` / `viewBuf` / `expiredBuf` / `contactBuf` / `siteBuf` / `elimBuf` / `pathWalkBuf` / `stationBuf` / `ctxBuf` / `doomedBuf` / `collapsingBuf` / `parkedBuf` / `collapseRemainBuf` / `destroyBuf` / `blockBuf` non réentrants — `replicate()` unique / tick ; `viewFor` séquentiel par humain (un record **par slot**) ; `step` unique par tick ; les 4 appelants `neighborFactions` lisent puis abandonnent ; `decideBuild` lit `siteBuf` puis abandonne ; `findSeaPath` synchrone unique ; `refreshRailNetwork` unique par mutation ; `resolve` synchrone unique ; `stepAttacks` unique par tick ; `launchAttack` synchrone ; `collapseFaction` unique par tick (collecte N67 close avant) ; `removePlayer` synchrone (N70) ; `validTiles` synchrone (N71). Swap `collapseRemainBuf`/`collapseLeftBuf` = upvalues module (le prochain appel écrit dans le buf courant). `emptyTileBuf` ne reçoit **jamais** d’insert.

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
| `COLLAPSE_MAX_PASSES` | 24 | 24 | oui (N69, inchangé) |
| `COLLAPSE_MIN_TILES` | 24 | 24 | oui (N69, inchangé) |
| `BUILD_MIN_SPACING` | (Config) | (apply) | oui (`validTiles` via `blockBuf` — N71, loi inchangée) |
| `BUILD_SNAP_RADIUS` | (Config) | (apply) | oui (`validTiles` — N71, loi inchangée) |

---

## 7. Preuve tests

```
./tests/run.sh  → exit 0
bundle server : 37 modules
Serveur : Tous les invariants tiennent.
  … gardes #17–#91 inchangés …
  destroyBuf : A parti, CITY de B survit (N70)
  destroyBuf : slot absent inerte (N70)
  destroyBuf : slot sans batiment, leftover 0 (N70)
  validTiles : emptyTileBuf rawequal, etranger/hors carte/CAPITAL (N71)
  validTiles : deux resolve CITY, tile identique (N71)
  parkedBuf : 0 pont land, leftover 0 (N68)
  parkedBuf : 2 ponts + 1 terre, leftover 3 (N68)
  contextFor : rawequal, slot 99, resolve CITY, ownerAt lit B (N66)
  doomedBuf : deux cancel vides, next nil (N67)
  clash : fronts nuls, leftover 0 (N67)
  collapse recycle : butin + captor grandit (N67)
  collapseRemain : slot vide return, plunder inchange (N69)
  collapseRemain : A a 0 puis B, pas de leftover (N69)
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 captures=80 pops=160
  factions : 18
  metrics : ticks=6000 avgChanged=8.9 p95Changed=19 maxChanged=479 avgTickMs=0.38 p95TickMs=0.87
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe30.log`

---

## 8. Instructions worker (si reprise)

- Vérité runtime d’équilibrage = `ChantierB.apply(Config)` après `SystemsBootstrap.install()`, PAS `Config.luau` seul.
- Combat vivant = patches ChantierB, pas `GameState.stepAttacks` (sauf `returnCommittedTroops` et `retreatAttack`, partagés). Debit **captures < 80 / pops < 160** (pas feel `guard < 80`).
- Debit de front = `attackTilesPerTick * speedFactor`, **captures < 80** (tuiles encore à la cible) et **pops < 160** (anti-runaway). Un `continue` stale ne compte plus comme une capture. Ne pas recâbler `guard += 1` avant le test owner.
- `areAllied` = deux sens **et** expiry. Ne pas revenir à un test `~= nil`. Bots / chat / tribus : **jamais** `alliances[slot][other]` comme vérité.
- Croisement diplomatique = accept **seulement** si `requestIsLive`. Une inverse périmée s’efface et on enfile une nouvelle demande.
- `retreatAttack` = **tous** les fronts du couple. Ne pas revenir à un `return` au premier match.
- Cote déjà nôtre ≠ retraite. Allié en mer = toujours retraite 25 % (N10.8). Inbound disparu = 100 % (comme front terre).
- Purge inbound d’un slot = **dans `removePlayer`**, pas seulement dans `Diplomacy.step` (ordre : Diplomacy puis `state:step`). Inclut cadran + colis + **transports** + **missiles** + **convois kind==2** (avant `setOwner`).
- Transports : `kind == 1`. Convois : `kind == 2`. Missiles : `toIndex(floor(tx), floor(ty))` vs `owner` **avant** `setOwner`. Ne pas `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` / `require(Placement)` depuis GameState (cycle).
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
- Tous kinds : `buildingsBySlot[slot][tile]` (N46). `lowestUpgradable` itère le set du bot ; `blastValue` / `fillBlastBuf` itère le set de la **cible** (N50). `removePlayer` snapshot les clés puis destroy via `destroyBuf` (N70). Un slot sans bâtiments ne rescane **pas** le hash. Ne pas spatial-hasher le blast. Ne pas relire `samsOf` via le hash (N42/N49). Ne pas recâbler `Nukes.launch` (N44) ni `factoriesByTile` (N45) ni `navalBasesBySlot` (N48).
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
- Contacts bots : `Bots.neighborFactions` (N61). `contactBuf` + `table.clear`. Slot 99 / sans joueur = map **vide**. NEUTRAL conservé. 4 appelants lisent puis abandonnent — pas de `table.clone`. Après `removePlayer`, tuiles du disparu = NEUTRAL. Leftover `decideDiplomacy` → N72.
- Sites de pose : `Bots.gatherSites` (N62). `siteBuf` + truncate. Caps 40/60/45. Pas de shuffle. DEFENSE = `ps.border`, PORT/NAVAL_BASE = `ps.coast`. Slot / côte / frontière vide → `# == 0`. Unique appelant `decideBuild` — pas de `table.clone`. `siteBuf` n’est pas réentrant.
- Élimination : `GameState.stepElimination` (N63). `elimBuf` (pas `doomed`). Truncate leftover **avant** `removePlayer`, pas à 0 après return. Buffer partagé inter-instances. Loi : `tiles==0` + pas d’attaque + pas de bateau. Bot = silencieux. Ne pas `require(Bots)` depuis GameState. Snapshot bâtiments dans `removePlayer` → N70 **fermé**.
- Trajet mer : `Navy.findSeaPath` (N64). `pathWalkBuf` walk scratch. Copie inverse dans un tableau **neuf**. Origine terrestre **exclue**. Échec / `MAX_BFS_NODES` → `nil`. Ne pas `return pathWalkBuf`. Banc N31 (déterminisme) doit rester vert.
- Gares porteuses : `GameState.refreshRailNetwork` (N65). `stationBuf` + truncate **avant** sort. `railParentBuf` / `railXsBuf` / `railYsBuf` itérés `1..count`. Maps grappe `table.clear`. Inners `neighborsOf` uniques. Ne pas pooler `building.links`. Ne pas porter `TRAIN_STOP_BONUS`. Ne pas `require(Buildings)` depuis GameState.
- Pose ctx : `Buildings.contextFor` (N66). `ctxBuf` + `ctxOwnerAt` / `ctxBuildingAt` module. Slot inconnu → `nil` sans muter. Deux appels → `rawequal`. Après A puis B, un `ownerAt` conservé lit B. `terrain` = buffer live. Pas le ctx client (`PlacementPreview`). `resolve` inchangé à l’appel. Ne pas `table.clone(ctxBuf)`. Ne pas `require(Buildings)` depuis GameState. Leftover `validTiles` → N71 **fermé**.
- Clash / collapse wrap : `ChantierB.cancelOpposingFronts` (N67). `doomedBuf` hash + `table.clear`. `collapsingBuf` + `collapseRecPool`. Truncate leftover **avant** `collapseFaction`. Hash sparse — ne pas itérer `#doomedBuf`. Debit `captures`/`pops` inchangé. `origStepAttacks` ignoré. `doomedBuf` / `collapsingBuf` non réentrants. Balayage tuiles → N69 **fermé**.
- Park beachhead : `BoatFront.launchAttack` (N68). `parkedBuf` + truncate leftover **avant** `origLaunch`. Réinsérer `1..n` (identité Attack). 0 pont → `#parkedBuf == 0`. Ne pas merger deux ponts (N29 ouvert). `BoatFront.parkedBuf` exposé banc. Non réentrant. `origLaunch` = corps terre (SystemsBootstrap wrap est **dehors**).
- Collapse tuiles : `GameState.collapseFaction` (N69). `collapseRemainBuf` / `collapseLeftBuf` + `collapseScratch` module. Truncate leftover **avant** plunder et **avant** swap. Itérer `1..n`. `where = collapseRemainBuf[1]` avant le premier swap. Slot sans tuile → return, pas de plunder. Swap d’upvalues — le prochain appel écrit dans le buf courant. Ne pas `require(ChantierB)` depuis GameState. `COLLAPSE_MAX_PASSES` / plunder inchangés.
- Destroy snapshot : `GameState.removePlayer` (N70). `destroyBuf` + truncate leftover **avant** `destroyBuilding`. Itérer `1..n`. Fallback hash si `buildingsBySlot[slot]` nil. Pas de `table.clone` de l’index live. `GameState.destroyBuf` exposé banc. Non réentrant — `stepElimination` enchaîne plusieurs slots (n recompté). Slot déjà absent → return. Ne pas `require(Placement)` depuis GameState.
- Pose tuiles : `Placement.validTiles` (N71). `blockBuf`/`candBuf`/`queueBuf`/`visitMap`/`emptyTileBuf`/`placeScratch`. Early-out → `emptyTileBuf` (jamais d’insert). Truncate queue **avant** BFS, candidats **avant** sort. Retourner `candBuf` (resolve lit `tiles[1]` tout de suite). `visitMap` pas `visitBuf`. Ne pas éditer `PlacementPreview`. GameState ne require **pas** Placement. Loi spacing / coastalOnly / `tiles[1]` plus proche **inchangée**.
- `init.server` / `Persistence` restent hors bundle : extraire un helper testable (`MatchLifecycle` / `snapshotBoats` / `snapshotMissiles` / `frontHudForReplicate` / `playerStatsForReplicate` déjà là) ou documenter un test Studio.
- Humain éliminé : `settledHumans[slot]` **avant** destruction du PlayerState. Bots ignorés. `endMatch` / disconnect après élimination passent par `MatchLifecycle` (init.server hors bundle). Disconnect **vivant** = 0 XP. `Persistence` reste hors du tick. Ne pas recâbler N6.
- Grâce humaine = `Bots.humanTargetProtected` (bots **et** tribus). Ne pas dupliquer une 2e courbe.
- Ne pas casser le client 34/34.
- Ligne feel (#19/#22/#24/#26/#28/#29/#32/#34/#36/#38/#41/#42/#45/#48/#51/#53/#56/#59/#62 + 55ba + 4876 + cc42 + 2f5d + b62d + 69f4 + 07c6 + **2b37**) : rebase sur cette passe avant cherry-pick, sinon perte `destroyBuf` / `validTiles`. Cherry-pick seq obligatoire (N41 feel) et `targetSlot` (N49 feel) seulement — N40/N42/N45/N57/N59/N60/N61/N62/N64/N65/N67/N68/N69/N70/N71/N72/N73/N74/N75/N76/N77/N78/N79/N80/N81/N82/N83/N84/N85/N86/N87/N88 feel sont déjà redondants avec N36 / N37 / N39 / N42 / N43 / N44 / N45 / N46 / N47 / N48 / N49 / N50 / N51 / N52 / N53 / N54 / N55 / N56 / N57 / N58 / N59 / N60 / N61 / N62 / N63 / N64 / N65 / N66 / N67 / N68 / N69 hardening. N50/N52 feel (`findSpawn` / `isSpawnSafe`) porte N33. N89 feel (`destroyBuf`) = N70 **fermé**. N90 feel (`Placement.validTiles`) = N71 **fermé**. Visual d3e2 V42 (`allyBuf`) = N72. Visual d3e2 V43 (`stripBuf`) = N73. **Ne pas** porter `retreating` Overlay (feel N56) avec N51. **Ne pas** porter `TRAIN_STOP_BONUS` HUD (feel N20) avec N65. **Ne pas** porter feel `guard < 80` (debit hardening = captures/pops). Client feel = 35/35 ; client hardening = **34/34**.
