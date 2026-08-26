# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 34)

Déclencheur : ouverture de la **PR #104** (`cursor/analyse-nocturne-du-codebase-5f6c`) — `Nukes.detonate` hashes, specs N77–N78.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-a0f9`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #104**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#104. Pas d’outil Slack.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29/#32/#34/#36/#38/#41/#42/#45/#48/#51/#53/#56/#59/#62 + d425 + df65 + 2157 + 5c74 + e735 + 7c38 + 1fb3 + 5bf6 + 741d + 55ba + 4876 + cc42 + 2f5d + b62d + 69f4 + 07c6 + 2b37 + e277 + 1e43 + a963 + d74d + **c786 passe 34**) : ne pas merger sur cette branche sans rebase. Les numéros N40+ feel (settledHumans, seq, N52–N100…) ne sont **pas** les N40–N80 de ce rapport. Cette passe **ferme** hardening N77 (`splitMirv` visée) et N78 (`TickMetrics` Sample/`seen`). Seq obligatoire (feel N41) et `targetSlot` (feel N49/N53) ne sont pas portés. **Pas** de `TRAIN_STOP_BONUS` dans `railIncome` (feel N20 / N84 — volontaire). Feel N94 (`table.clear` border/coast) = N74 **déjà fermé**. N75 (scan cadran) **reste ouvert** — contrat A trop structurel pour un correctif « sûr » (index `setOwner` = autorité). Client hardening = **34/34** (feel 35/35 — Overlay `retreating`). Visual e3ed V54 = ligne visuelle, pas ici.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`. `RequestSnapshot` n’est toujours jamais `FireServer` côté client (N4). DAG : `GameState` ne `require` ni Navy, ni Nukes, ni Trade, ni Bots, ni Buildings, ni Research, ni Diplomacy, ni Placement. `Buildings`, `Research`, `Diplomacy` require déjà `GameState` ; `Placement` require Shared only — ne pas inverser. `Nukes` require `GameState` + `Buildings` (pas l’inverse). `TickMetrics` require `Config` seulement. N66 (`ctxBuf`) vit dans Buildings. N67 (`doomedBuf`) vit dans ChantierB (`install()` serveur seulement). N68 (`parkedBuf`) vit dans BoatFront. N69 (`collapseRemainBuf`) vit dans GameState. N70 (`destroyBuf`) vit dans GameState (`removePlayer`). N71 (`blockBuf` / `candBuf` / `queueBuf` / `visitMap` / `emptyTileBuf` / `placeScratch`) vit dans Placement (Shared, pas le ctx client). N72 (`allyBuf`) vit dans Bots. N73 (`stripBuf`) vit dans ChantierB (`install()` serveur seulement). N74 (`table.clear` border/coast) vit dans `ChantierB.stripTerritory` (hashes **par joueur**, pas un buf module). N76 (`tilesBeforeBuf` / `hitTilesBuf`) vit dans **Nukes** (`detonate` seulement). N77 (`mirvTxBuf` / `mirvTyBuf`) vit dans **Nukes** (`splitMirv` seulement). N78 (`seenBuf` / `history` ring) vit dans **TickMetrics**.

La PR #104 a bien fermé `Nukes.detonate` hashes (N76). Cette passe a **corrigé ce que #104 a spécifié** — `splitMirv` allouait encore `targets = {}` + `Vector2`, et `TickMetrics.record` allouait encore un Sample + `seen` à 10 Hz :

| Bug | Gravité | Statut |
|---|---|---|
| `ChantierB.stripTerritory` `border = {}` / `coast = {}` (N74) | **P3 alloc spawn** | **déjà fermé** (#102, `table.clear`) |
| `Nukes.detonate` `tilesBefore` / `hitTiles` (N76) | **P3 alloc nuke** | **déjà fermé** (#104, `tilesBeforeBuf` / `hitTilesBuf`) |
| `splitMirv` `targets = {}` (N77) | **P3 alloc MIRV** | **corrigé** (`mirvTxBuf` / `mirvTyBuf`, `table.clear`) |
| `TickMetrics.record` Sample + `seen` (N78) | **P3 alloc metrics** | **corrigé** (`seenBuf` + ring Sample, pas `remove(1)`) |
| `stepDoomsday` scan O(TILE_COUNT) (N9 / N75) | **P2 cadran** | **ouvert** (index compact — leftover N73 ; contrat A trop structurel ici) |
| `TickMetrics.snapshot` 4 arrays (N79) | **P3 alloc metrics** | **ouvert** (leftover post-N78) |
| `TickMetrics.reset` droppe le pool Sample (N80) | **P3 alloc metrics** | **ouvert** (leftover post-N78) |
| `retreatBoats` filtre `owner[targetTile]` courant | **P2 marine** | **ouvert** (reste de N28 ; feel d425/df65 a la recette) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29) |
| `findSpawn` ignore splash / fallout (N33) | **P3 nucléaire** | **ouvert** (feel d425/df65 a C1+C2 + `isSpawnSafe`) |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#104 + allyBuf (N72) + stripBuf (N73) + stripTerritory hashes (N74) + detonate hashes (N76) + splitMirv hashes (N77) + TickMetrics ring (N78).
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #104

**À merger** (`Nukes.detonate` hashes + specs N77–N78), sous réserve que cette passe 34 parte avec : **`splitMirv` allouait encore `targets = {}` / `Vector2`, et `TickMetrics.record` allouait encore Sample + `seen` à 10 Hz**.

Points encore vrais après #104 :

| Claim #104 | Réalité après passe 34 |
|---|---|
| N76 `Nukes.detonate` hashes | confirmé |
| N77 `splitMirv` `targets` | **fermé ici** (rawequal, leftover ocean `# == 1`, pas de Vector2) |
| N78 `TickMetrics.record` Sample/`seen` | **fermé ici** (rawequal `seenBuf`, ring 601, `formatReport` parseable) |
| N75 `stepDoomsday` scan O(TILE_COUNT) | **ouvert** (ferme N9 si A ou C ; A trop structurel ici) |
| N33 `findSpawn` splash / fallout | **ouvert** |
| N28 retraite après flip / `targetSlot` | **ouvert** |
| N29 `seedBeachhead` no-merge | specs only, inchangé (banc N68 documente 3 Attack) |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |

`init.server.luau` et `Persistence` restent **exclus du bundle**. Le helper `MatchLifecycle` est **dans** le bundle (37 modules serveur). `snapshotBoats` / `snapshotMissiles` / `flushOwnerDelta` / `flushBuildingDelta` / `frontHudForReplicate` / `playerStatsForReplicate` sont **dans** le bundle (`GameState`). `pricesFor` / `contextFor` vivent dans **Buildings**. `progress` ne alloue plus `ratios` (N58). `Diplomacy.viewFor` recycle `viewBuf[slot]` (N59). `Diplomacy.step` recycle `expiredBuf` (N60). `neighborFactions` recycle `contactBuf` (N61). `gatherSites` recycle `siteBuf` (N62). `stepElimination` recycle `elimBuf` (N63). `findSeaPath` recycle `pathWalkBuf` (N64) — le tableau rendu au bateau **reste unique**. `refreshRailNetwork` recycle `stationBuf` (N65) — `building.links` **reste unique**. `Buildings.contextFor` recycle `ctxBuf` (N66) — pas le ctx client. `ChantierB` recycle `doomedBuf` / `collapsingBuf` (N67). `BoatFront.launchAttack` recycle `parkedBuf` (N68). `collapseFaction` recycle `collapseRemainBuf` / `collapseLeftBuf` (N69). `removePlayer` recycle `destroyBuf` (N70). `Placement.validTiles` recycle blockers/candidates (N71). `decideDiplomacy` recycle `allyBuf` (N72). `stepDoomsday` recycle `stripBuf` (N73). `stripTerritory` `table.clear` in-place (N74). Scan cadran encore O(carte) (N9 / N75). `Nukes.detonate` recycle `tilesBeforeBuf` / `hitTilesBuf` (N76). `splitMirv` recycle `mirvTxBuf` / `mirvTyBuf` (N77). `TickMetrics.record` recycle `seenBuf` + ring Sample (N78). `snapshot` alloue encore 4 arrays (N79). `reset` droppe encore le pool (N80).

PR #101 / #105 (feel / visual) ne doivent pas être mergées par-dessus #16/#104 sans rebase. Seq / `targetSlot` / hover `SpawnHint` / Overlay `retreating` / `TRAIN_STOP_BONUS` HUD / `previewCtx` restent feel-only. Visual e3ed V54 = ligne visuelle, pas ici.

On peut fermer #17, #18, #20, #23, #25, #27, #30, #31, #33, #35, #37, #40, #43, #46, #49, #52, #55, #58, #60, #63, #66, #70, #73, #76, #80, #83, #85, #88, #91, #95, #98, #102 et #104 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| `splitMirv` alloc `targets = {}` + `Vector2` | `Nukes.splitMirv`, `tests/simulate.luau` | Deux arrays module-level `mirvTxBuf` / `mirvTyBuf`, `table.clear` **avant** fill. `rawequal` des deux arrays sur deux scissions. Porteur land : `# >= 1`, ogives == `#`. Porteur océan / hors carte : `# == 1` (fallback point visé), pas de leftover du premier. Loi `spread` / `minGap=4` / `speed * 1.8` / `warheadRadius` **inchangées**. Records `state.missiles[]` **uniques**. Contrat B inbound (N30) **inchangé**. Recette spec #104 N77. Ne ferme **pas** N75 ni N78. |
| `TickMetrics.record` Sample + `seen` 10 Hz | `TickMetrics.luau`, `tests/simulate.luau` | `seenBuf` hash module, `table.clear` **avant** fill. Early-out delta nil **conservé** (pas de clear). Ring `history[1..HISTORY_CAP]` + write index, **pas** `table.remove(history, 1)`. 601 `record` → `#history == 600`, `rawequal` du Sample. `formatReport` encore parseable (`ticks=`). Totaux / `HISTORY_CAP` / percentiles **inchangés**. Recette spec #104 N78. Ne ferme **pas** N79 (`snapshot` arrays) ni N80 (`reset` droppe le pool). |

**Non modifié (volontaire) :** N1–N76 restant, reste de N28 (`targetSlot`). N10.8. Cap beachheads (N5 / N29). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` / `require(Placement)` depuis GameState. Pas de contrat C spawn (N33). Pas de seq obligatoire (feel N41). Pas de spatial hash warships. Buffer `defense` **alloué** mais plus écrit. Pas de `TRAIN_STOP_BONUS` dans `railIncome` (N18 / feel N20). Scan cadran encore O(carte) (N9 / N75) — contrat A (`tilesBySlot` dans `setOwner`) trop structurel : un index déréglé vs `owner` = pourriture du mauvais camp. `snapshot` encore alloué (N79). `reset` droppe encore le pool Sample (N80). Pas de `retreating` Overlay (feel N56 historique). Debit `captures`/`pops` **non** remplacé par feel `guard < 80`. `PlacementPreview` / `tests/client.luau` **non** édités. Skip AFK cadran **conservé**. Ogives MIRV **non** poolées (possession).

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
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients` (N26). Snapshot navires = `GameState.snapshotBoats` (`boatSnapBuf`, N51). Snapshot missiles = `GameState.snapshotMissiles` (`missileSnapBuf`, N52). Owner delta = `dirtyIndexBuf` (N53), buffer outbound **neuf**. BuildingDelta = `buildingSnapBuf` (N54), `links` live. HUD fronts = `frontHudForReplicate` (N55), appelé **une** fois depuis N57. `buildPrices` = `Buildings.pricesFor` (N56). Records stats = `playerStatsForReplicate` (N57). `Research.progress` min courant (N58). `Diplomacy.viewFor` recycle par slot (N59). `Diplomacy.step` recycle `expiredBuf` (N60). `neighborFactions` recycle `contactBuf` (N61). `gatherSites` recycle `siteBuf` (N62). `stepElimination` recycle `elimBuf` (N63). `findSeaPath` `pathWalkBuf` (N64, retour unique). `refreshRailNetwork` `stationBuf` (N65). `contextFor` `ctxBuf` (N66). Combat `doomedBuf`/`collapsingBuf` (N67). `parkedBuf` (N68). `collapseRemainBuf` (N69). Snapshot destroy `destroyBuf` (N70). `validTiles` blockers (N71). `allyBuf` (N72). `stripBuf` (N73). `stripTerritory` `table.clear` (N74). Scan cadran encore O(carte) (N9 / N75). `Nukes.detonate` `tilesBeforeBuf`/`hitTilesBuf` (N76). `splitMirv` `mirvTxBuf`/`mirvTyBuf` (N77). `TickMetrics.record` `seenBuf` + ring Sample (N78). `snapshot` encore alloué (N79).
- **DataStore** : `settledHumans` avant destruction du PlayerState. `endMatch` grave via `MatchLifecycle.endMatchRecords`. `Persistence.record` max-merge inchangé (N6).
- **Require** : DAG. Pas de cycle. `MatchLifecycle` → Config seulement. `Tribes` → `Bots` (export `humanTargetProtected` seulement). `Navy` → `GameState` (unidirectionnel). `Nukes` → `GameState` + `Buildings`. `Trade` → `GameState`. `Bots` → `GameState` (pas l’inverse). `Buildings` → `GameState` (pas l’inverse — N56/N66 vivent dans Buildings). `Research` → `GameState` (pas l’inverse). `Diplomacy` → `GameState` (pas l’inverse). `Placement` → Shared only (N71 — **ne pas** require Placement depuis GameState). `TickMetrics` → Config seulement (N78). `ChantierB`/`BoatFront`/`AimFront` dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).
- **BFS mer** : `visitBuf` + `parentScratch` + `queueScratch` + `pathWalkBuf` module-level. Un seul chemin en vol à la fois (Navy n’est pas réentrant). Résultat path **unique** (copie inverse, N64).
- **BFS annex** : `annexVisitBuf` + `annexQueue` + `annexPocket` module-level. Un seul `tryAnnex` en vol à la fois (combat n’est pas réentrant).
- **Gares** : `stationBuf` + `railParentBuf` / `railXsBuf` / `railYsBuf` + maps grappe. Truncate **avant** sort. `building.links` unique (N65).
- **Pose** : `ctxBuf` + closures module. Non réentrant. `terrain` = buffer live (N66). `validTiles` recycle `blockBuf`/`candBuf`/`queueBuf`/`visitMap` (N71). `emptyTileBuf` jamais d’insert.
- **Clash / collapse wrap** : `doomedBuf` hash + `collapsingBuf` / `collapseRecPool`. Truncate leftover **avant** `collapseFaction` (N67). Balayage tuiles recyclé (N69).
- **Park beachhead** : `parkedBuf` module-level. Truncate leftover **avant** `origLaunch` (N68).
- **Collapse tuiles** : `collapseRemainBuf` / `collapseLeftBuf` + swap. Truncate leftover **avant** plunder (N69).
- **Destroy snapshot** : `destroyBuf` module-level. Truncate leftover **avant** `destroyBuilding` (N70). `GameState.destroyBuf` exposé banc.
- **validTiles** : `blockBuf`/`candBuf`/`queueBuf`/`visitMap`/`emptyTileBuf`/`placeScratch`. Truncate avant BFS et avant sort (N71).
- **Pactes bots** : `allyBuf` hash module-level. `table.clear` + fill `areAllied` (N72). `Bots.allyBuf` exposé banc.
- **Rot cadran** : `stripBuf` array module-level. Truncate avant arrachage, reset après slot (N73). `ChantierB.stripBuf` exposé banc. Scan O(carte) **reste** (N9 / N75).
- **Strip spawn** : `table.clear(ps.border)` / `table.clear(ps.coast)` in-place (N74). Hashes **par joueur**.
- **Crater nuke** : `tilesBeforeBuf` / `hitTilesBuf` hashes module-level (N76). `table.clear` **avant** fill. `Nukes.tilesBeforeBuf` / `Nukes.hitTilesBuf` exposés banc. Non réentrant — `Nukes.step` détone en série. Wrap `installFallout` après orig.
- **Visée MIRV** : `mirvTxBuf` / `mirvTyBuf` arrays module-level (N77). `table.clear` **avant** fill. `Nukes.mirvTxBuf` / `Nukes.mirvTyBuf` exposés banc. Non réentrant — `Nukes.step` scinde en série. Ogives = records **neufs**.
- **Metrics** : `seenBuf` hash + ring `history[1..HISTORY_CAP]` (N78). `table.clear(seenBuf)` **avant** fill (delta non-nil seulement). `TickMetrics.seenBuf` / `TickMetrics.history` exposés banc. `snapshot` encore alloué (N79). `reset` `table.clear(history)` droppe le pool (N80).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N80 restent ouverts** sauf N19 partiel, N21 **fermé**, N24 remplacé par N31 (**fermé**), N30–N32 **fermés**, N34–N74 **fermés**, N76–N78 **fermés**. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + N75 + le reste de N28 / N29 / N33.

---

### ISSUE-N28 — `retreatBoats` / `retreatAttack` après flip de côte (reste)

**Priorité :** P2 combat / comptabilité navale. **Partiel :** inbound `removePlayer` **fermé** en passe 8.

**Problème restant :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetSlot`. Conséquences encore vraies :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers).
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

Feel d425 (N49) + df65 (N53) : `launchInvasion` pose `targetSlot`, `retreatBoats` filtre l’intention (fallback `owner[targetTile]`), wrap 2e geste rappelle les tardifs, `Navy.step` auto-retraite si `owner[targetTile] ~= targetSlot`. **Porter, ne pas réinventer.** Distinct de N10.8 et du fix inbound. Distinct de N35 (`destSlot` convoi ≠ `targetSlot` invasion). Distinct de N40 / N44–N78 (index / snapshots / HUD / `progress` / `viewFor` / `expired` / contacts / sites / elim / path / rail / ctx / doomed / parked / collapse / destroy / validTiles / allyBuf / stripBuf / strip hashes / detonate hashes / splitMirv / TickMetrics, **fermés** ou **specs**).

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite.

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste, trancher si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`. Recette feel : branche `d425` / `df65`.

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N22). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % déjà livré). Ne pas recâbler N35 (convois, `kind==2`). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).** Ne pas porter AimFront ni seq. Ne pas recâbler N50–N78.

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

Feel d425 (N50) + df65 (N52) + 2157 (N55 isolation, ticket suivant) : `isSpawnSafe` partagé `findSpawn` / `claimSpawn`, refuse crater ogive **et** `state.fallout[index] > tick`. **Porter, ne pas réinventer.** Contrat B (N30) déjà livré ici : ne pas l’ouvrir. Isolation disque clic (feel N55) = ticket **feel**, pas celui-ci. N76 (`detonate` hashes) **fermé** : ne pas le mixer. N77 (`splitMirv`) **fermé** : ne pas le mixer.

**Pourquoi 20K CCU :** moins chaud que N30 (il faut un voisin sous missile + spawn coincé dans le rayon).

**Worker :**

1. Ne **pas** rouvrir le contrat B. Options : (C1) `findSpawn` refuse un centre dont un missile en vol a `toIndex(floor(tx),floor(ty))` à distance `NUKE_STATS[kind].radius` (ogive : `missile.radius`) ; (C2) `findSpawn` refuse `state.fallout[index] > tick` ; (C3) documenter « le territoire, pas le joueur » pour le splash tiers. Feel a choisi C1+C2 via `isSpawnSafe`.
2. Test : A tire sur C (capitale), `removePlayer(B)`, forcer le spawn de l’héritier dans le rayon (tuiles libres), `Nukes.step`. Assert selon C1/C2/C3.
3. Fichiers : `GameState.findSpawn` / `addPlayer`, éventuellement `Nukes`, `tests/simulate.luau`. Recette feel : branche `d425` / `df65`.

**Contraintes :** ne pas annuler une frappe tiers (régression `nuke third-party`). Ne pas rembourser l’or. Pas de RemoteFunction. Rayon lu depuis `NUKE_STATS` / `missile.radius`, pas une constante magique. Ne pas porter isolation clic (feel N55) dans le même PR. Ne pas recâbler N50–N78. Ne pas mixer N76 (`tilesBeforeBuf` — leftover alloc, **déjà fermé**) ni N77 (`mirvTxBuf` — **déjà fermé**).

---

### ISSUE-N75 — `stepDoomsday` scanne encore `0..TILE_COUNT-1` par camp qui saigne

**Priorité :** P2 cadran / perf. Leftover explicite de N9 et de N73 (« ne pas remplacer le scan 40 960 — ticket suivant »). Distinct de N73 (`stripBuf` liste temporaire, **déjà fermé**) et de N74 (`stripTerritory` hashes spawn, **déjà fermé**). Ne pas toucher `rotQuota`. **N75 hardening ≠ N75 feel historique (`pricesFor`).** Visual V13 décrit le même trou. **Non livré en passe 34** : contrat A (`tilesBySlot` maintenu dans `setOwner`) est un index d’autorité — un déréglage vs `owner` pourrit le mauvais camp. Trop structurel pour un correctif « sûr » à côté de N77/N78.

**Problème :** même avec `stripBuf` recyclé, chaque slot sous quota (10 Hz, late-game plusieurs camps) re-scanne `Config.TILE_COUNT` (40 960) jusqu’à `quota * 4` hits. Un shard 18 factions en cadran = jusqu’à ~17 scans linéaires / tick. Il n’existe pas d’index compact tuiles-par-slot : `ps.tiles` est un compteur, `ps.border` / `ps.coast` ne couvrent pas l’intérieur. N73 a volontairement laissé ce scan.

**Pourquoi 20K CCU :** leftover N9. Late-game cadran = le tick le plus cher du shard (hors combat). Recycle de la porteuse (N73) n’enlève pas les 40k reads `buffer.readu8`. Un index compact (reservoir / linked list / dirty set) ramène le rot à O(tuiles du camp) au lieu de O(carte). Pas d’autorité si `setOwner` maintient l’index. Ne pas fusionner avec N74 : strip spawn parcourt encore la carte une fois au join, pas 10 Hz.

**Worker :**

1. Choisir un contrat : (A) `tilesBySlot[slot] = { number }` array compact, maintenu dans `setOwner` (insert au claim, swap-pop au loss) — `stepDoomsday` itère `1..ps.tiles` au lieu de `0..TILE_COUNT-1` ; (B) reservoir bitset 40 960 / 8 recyclé, rebuild seulement si dirty ; (C) documenter « scan O(carte) accepté, N9 fermé sans code ». **Un seul.** Feel / visual n’ont pas encore fermé V13. Pas de RemoteFunction.
2. Si A : `setOwner` est le **seul** writer. `removePlayer` / `collapseFaction` / `stripTerritory` / rot cadran passent déjà par `setOwner`. Ne pas maintenir un 2e index à côté. Cap array = `TILE_COUNT` worst-case d’un camp. Truncate leftover **avant** usage. Ne pas `require` de module nouveau. Skip AFK / `awaitingSpawn` **conservé**. `stripBuf` (N73) peut rester (copie depuis l’index) ou disparaître si on itère l’index directement — trancher et tester leftover inter-slots.
3. Test : bancs N73 stripBuf / doomsday recycle / AFK **doivent rester verts**. Ajouter : un camp sous quota → même `ripped` / `tiles` qu’aujourd’hui (déterminisme seed). Deux camps. `setOwner` d’une tuile intérieure met à jour l’index (rot la trouve, `ps.tiles` vs buffer). Client **34/34**. 6000 ticks. Mesurer `avgTickMs` cadran vs HEAD.
4. Fichiers : `GameState.setOwner` (si A), `ChantierB.stepDoomsday`, éventuellement `stripTerritory` (N74 est **fermé** — ne pas le mixer), `tests/simulate.luau`. Recette visuelle V13 si elle existe plus tard — **ne pas inventer un spatial hash**.

**Contraintes :** pas de RemoteFunction. **N75 hardening ≠ N73 (`stripBuf`, déjà fait) ≠ N74 (`border`/`coast`, **déjà fait**) ≠ N76 (`detonate`, **déjà fait**) ≠ N77 (`splitMirv`, **déjà fait**) ≠ N78 (`TickMetrics`, **déjà fait**) ≠ N9 (umbrella — ce ticket **ferme** N9 si A ou C).** Ne pas changer `rotQuota` / drain / WARN. Ne pas scanner `buildings`. Overlay n’itère pas l’index. Un index déréglé vs `owner` = pourriture du mauvais camp (invariants `tiles` vs buffer le verront). Ne pas `require(ChantierB)` depuis GameState. Ne pas mixer avec N79 (`snapshot`) ni N80 (`reset` pool).

---

### ISSUE-N76 — `Nukes.detonate` hashes — **FERMÉ** (passe 33)

`tilesBeforeBuf` / `hitTilesBuf` module-level. `table.clear` avant fill. Banc : rawequal, snapshot avant crater, leftover ocean `next` nil. Ne pas rouvrir. Ne pas partager `samBuf` / `blastX` / `destroyBuf` / `mirvTxBuf`. Wrap `installFallout` inchangé.

---

### ISSUE-N77 — `splitMirv` `targets` — **FERMÉ** (passe 34)

`mirvTxBuf` / `mirvTyBuf` arrays module-level. `table.clear` avant fill. Pas de `Vector2`. Banc : rawequal deux scissions, leftover océan `# == 1` fallback point visé. Ogives restent des records neufs. Ne pas rouvrir. Ne pas partager `tilesBeforeBuf` / `hitTilesBuf` (N76).

---

### ISSUE-N78 — `TickMetrics.record` Sample/`seen` — **FERMÉ** (passe 34)

`seenBuf` hash module + ring `history[1..HISTORY_CAP]`. Early-out delta nil conservé. Banc : rawequal `seenBuf`, 601 `record` → `# == 600`, Sample recyclé, `formatReport` parseable. Ne pas rouvrir. Leftover `snapshot` arrays → N79. Leftover `reset` droppe le pool → N80.

---

### ISSUE-N79 — `TickMetrics.snapshot` alloue 4 arrays + table de retour

**Priorité :** P3 alloc instrumentation. Leftover explicite de N78 (« ne pas mixer `snapshot` — lifetime différent, `table.sort` dans `percentile` mute »). Distinct de N78 (Sample/`seen`, **déjà fermé**) et de N2 (delta stats HUD). Distinct de N53 (`dirtyIndexBuf` — buffer outbound **neuf**, déjà fermé). **N79 hardening ≠ N79 feel historique (`Diplomacy.step` expired).**

**Problème :** `TickMetrics.snapshot` (appelé par `formatReport`, logs périodiques `init.server`) fait `table.create(#history, 0)` × 4 (`changed` / `bytes` / `ms` / `chunks`) puis une table de retour `{ samples, totals, p95, p99 }` avec deux nested. `percentile` **mute** via `table.sort`. ~1 700 shards × (log 60 s) × 4 arrays de 600 nombres. Moins chaud que N78 (10 Hz) mais le leftover naturel après le ring.

**Pourquoi 20K CCU :** l’instrumentation ne doit pas ré-allouer 2 400 nombres à chaque rapport. Recycle 4 arrays module-level, overwrite `1..#history`, truncate leftover. Pas d’autorité : TickMetrics ne mute pas `GameState`. Format de `formatReport` **inchangé**.

**Worker :**

1. Quatre arrays module-level `changedBuf` / `bytesBuf` / `msBuf` / `chunksBuf`, `table.create(HISTORY_CAP, 0)`. Overwrite `1..#history`. Truncate leftover `#history+1..#buf` **avant** `percentile` (un leftover d’un run plus long fausserait p95). Exposer les 4 pour le banc. Pas de RemoteFunction.
2. **Ne pas** recycler la table de retour ni `p95`/`p99` dans le même PR — leftover **N80 si on y va après le pool reset**, ou rester sur N80 = pool `reset`. `percentile` mute : après sort, les bufs ne sont plus en ordre d’historique. Le prochain `snapshot` **doit** tout réécrire (pas un early-out « déjà plein »). Ne pas `require(TickMetrics)` depuis GameState.
3. Test : bancs N78 ring / seenBuf / formatReport `ticks=` **doivent rester verts**. Ajouter : deux `snapshot` → `rawequal` des 4 arrays. Après 3 `record` puis 601 `record` (history pleine) → leftover au-delà de 600 absent (`[601] == nil`). Client **34/34**. 6000 ticks. Ne **pas** appeler `reset` avant le `formatReport` du run principal.
4. Fichiers : `TickMetrics.luau` (`snapshot` seulement), `tests/simulate.luau` (bloc court **après** le formatReport du run, comme N78). Pas de recette feel.

**Contraintes :** pas de RemoteFunction. **N79 hardening ≠ N78 (`record`/`seen`, déjà fait) ≠ N80 (`reset` pool) ≠ N53 (`dirtyIndexBuf`) ≠ N2 (stats HUD).** Overlay n’lit pas TickMetrics. Ne pas changer `HISTORY_CAP` / percentiles. Ne pas mixer N75 / N77. `init.server` hors bundle — le helper est **dans** le bundle (déjà testé). Ne pas porter `retreating`.

---

### ISSUE-N80 — `TickMetrics.reset` droppe le pool Sample (`table.clear(history)`)

**Priorité :** P3 alloc instrumentation. Leftover explicite de N78 (`reset` → `table.clear` / index 0, **volontaire** dans N78 pour ne pas mixer). Distinct de N78 (ring pendant le match, **déjà fermé**) et de N79 (`snapshot` arrays). **N80 hardening ≠ N80 feel historique (`Bots.neighborFactions`).**

**Problème :** `TickMetrics.reset` (chaque `startMatch` / `runMatch`) fait `table.clear(history)` : les jusqu’à 600 records Sample **recyclés pendant le match** sont abandonnés au GC. Le match suivant ré-alloue 600 tables. ~1 700 shards × N matchs / heure × 600 tables. N78 a volontairement `table.clear` pour borner le contrat (index 0, pas de Sample fantôme d’un match précédent dans `snapshot`).

**Pourquoi 20K CCU :** un shard enchaîne les matchs (10–25 min). Garder le pool (count=0, **sans** `table.clear` des records) ramène l’alloc match-to-match à zéro. Pas d’autorité. Un leftover Sample non réécrit = p95 d’un match mort (le banc N78 601 `record` après reset le verrait si on oublie d’overwrite).

**Worker :**

1. `reset` : `historyCount = 0`, `historyWrite = 0`, totaux à 0. **Ne pas** `table.clear(history)` — les records restent. `#history` après reset doit être **0** pour `snapshot` / `formatReport` (sinon p95 du match mort). Options : (A) truncate `history[i] = nil` pour `i = 1..oldCount` **sans** détruire les records — les garder dans un `samplePool` parallèle ; (B) garder `history` dense et faire lire `snapshot` `1..historyCount` (pas `#history`) — **alors** mettre à jour N78 tests (`#history == 600` → `historyCount`). **Un seul.** Recommandé : B + exposer `TickMetrics.historyCount`. Pas de RemoteFunction.
2. Ne pas modifier `record` / `seenBuf` (N78 **fermé**) sauf si B exige `snapshot` itère `historyCount`. Ne pas mixer N79 (`snapshot` arrays) — si B change l’itération, N79 overwrite `1..historyCount`. `formatReport` encore parseable. Early-out delta nil **conservé**.
3. Test : bancs N78 **doivent rester verts** (adapter `#history` si B). Ajouter : `record` × 10, `reset`, `record` × 1 → `rawequal` du Sample `[1]` (pas une 11e table). `snapshot.samples == 1` (pas 10 fantômes). `formatReport` `ticks=1`. Client **34/34**. 6000 ticks. Ne **pas** appeler `reset` avant le formatReport du run principal.
4. Fichiers : `TickMetrics.luau` (`reset` + éventuellement `snapshot` itération), `tests/simulate.luau` (bloc court à côté de N78, après formatReport). Pas de recette feel.

**Contraintes :** pas de RemoteFunction. **N80 hardening ≠ N78 (ring pendant le match, déjà fait) ≠ N79 (`snapshot` arrays) ≠ N53.** Overlay n’lit pas TickMetrics. Ne pas changer `HISTORY_CAP`. Ne pas mixer N75 / N77. Un Sample fantôme après reset = p95 d’un match mort (le banc `samples == 1` le verra).

---

## 5b. N1–N80 encore ouverts ou fermés (passes 2–34)

| ID | Titre | Prio | Note passe 34 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + `SAM_INTERCEPT_CHANCE` 0.55→1 ; clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz ; bateaux → **N51 fermé** ; missiles → **N52 fermé** ; indices dirty → **N53 fermé** ; bâtiments → **N54 fermé** ; HUD fronts → **N55 fermé** ; `buildPrices` → **N56 fermé** ; records stats → **N57 fermé** ; `progress` → **N58 fermé** ; `viewFor` → **N59 fermé** ; `expired` → **N60 fermé** ; contacts → **N61 fermé** ; sites → **N62 fermé** ; elim → **N63 fermé** ; path → **N64 fermé** ; rail → **N65 fermé** ; ctx → **N66 fermé** ; doomed → **N67 fermé** ; parked → **N68 fermé** ; collapse → **N69 fermé** ; destroy → **N70 fermé** ; validTiles → **N71 fermé** ; allyBuf → **N72 fermé** ; stripBuf → **N73 fermé** ; strip hashes → **N74 fermé** ; detonate hashes → **N76 fermé** ; splitMirv → **N77 fermé** ; metrics Sample/`seen` → **N78 fermé** ; reste skip-si-inchangé ; snapshot arrays → **N79** ; reset pool → **N80** |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` **jamais** `FireServer` côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | park `isBeachhead` → hors cap land ; **2 beachheads parked + 1 terre = 3** — voir N29 ; alloc parked → **N68 fermé** |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | refund + retraite `RETREAT_LOSS` alignés ; le reste du corps est mort ; `tileCost` lit encore `defense` (buffer plus écrit) ; wrap vivant → **N67 fermé** ; `collapseFaction` remaining → **N69 fermé** |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | timers slot maintenant purgés ; liste temporaire → **N73 fermé** ; hashes spawn → **N74 fermé** ; le scan rot est toujours O(tuiles) → **N75** |
| N10 | Divers P3 | P3 | donations gold sans plafond ; `pendingMode` last-writer ; README SmoothTerrain ; `contextFor` → **N66 fermé** ; `validTiles` → **N71 fermé** ; `stripTerritory` hashes → **N74 fermé** ; `detonate` hashes → **N76 fermé** ; `splitMirv` → **N77 fermé** ; metrics Sample → **N78 fermé** ; snapshot arrays → **N79** ; reset pool → **N80** |
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
| N34–N74 | (index / snapshots / HUD / diplomatie / bots / combat wrap / pose) | — | **tous fermés** (passes 11–32). Voir rapport #102. |
| N75 | `stepDoomsday` scan O(TILE_COUNT) | P2 | specs only. Leftover N9 / N73. Ferme N9 si contrat A ou C. **Non livré ici** (A trop structurel). **≠ N75 feel historique (`pricesFor`).** |
| N76 | `Nukes.detonate` `tilesBefore` / `hitTiles` | P3 | **fermé** (passe 33). **≠ N76 feel historique (`stats[slot]`).** |
| N77 | `splitMirv` `targets = {}` | P3 | **fermé**. Leftover N76. **≠ N77 feel historique (`progress` min).** |
| N78 | `TickMetrics.record` Sample + `seen` | P3 | **fermé**. 10 Hz instrumentation. `snapshot` arrays → leftover **N79**. `reset` pool → leftover **N80**. **≠ N78 feel historique (`viewFor`).** |
| N79 | `TickMetrics.snapshot` 4 arrays | P3 | specs only. Leftover N78. **≠ N79 feel historique (`expired`).** |
| N80 | `TickMetrics.reset` droppe le pool Sample | P3 | specs only. Leftover N78. **≠ N80 feel historique (`neighborFactions`).** |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu (reset à `startMatch` suffit) ; disconnect mid-match **vivant** = `Persistence.record(..., false)` 0 XP (chemin distinct de N37 ; éliminé puis leave **grave** le snapshot) ; wrap `launchAttack` n’applique `AimFront.focus` que si le couple n’existait pas (renfort = pas de re-visée — feel N36). Spatial hash warships (contrat A de N39) volontairement non fait. `Trade.step` `factoriesBuf` déjà recyclé (N45) ; early-out 0 usine / sort seulement si `n>=2` = reste de feel N66, cheap. `structureHash` O(B log B) seulement sur `RequestSnapshot` rate-limité (N4, client jamais `FireServer`). `Nukes.detonate` (N76) `table.clear` les hashes **module** — leftover ocean `next` nil. `splitMirv` (N77) `table.clear` les arrays **module** — leftover ocean `# == 1`. `TickMetrics.record` (N78) ring — leftover `snapshot` (N79) / `reset` pool (N80). `Nukes.step` `table.remove` missiles encore O(n) par intercept/scission/détonation (pas ticket : ordre reverse-iter conservé).

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
| `MIRV_SEPARATION` | 0.55 | 0.55 | oui (`splitMirv` — N77, arrays recyclés) |
| `NUKE_STATS[ATOM].radius` | 9 | 9 | oui (`detonate` — N76, hashes recyclés) |
| `NUKE_STATS[MIRV].warheads` | 6 | 6 | oui (`splitMirv` — N77, `mirvTxBuf` cap) |
| `NUKE_STATS[MIRV].spread` | 16 | 16 | oui (`splitMirv` — N77, `NextInteger` inchangé) |

---

## 7. Preuve tests

```
./tests/run.sh  → exit 0
bundle server : 37 modules
Serveur : Tous les invariants tiennent.
  … gardes #17–#104 inchangés …
  allyBuf : deux appels, rawequal, allie present (N72)
  allyBuf : breakAlliance → ex-allie absent (N72)
  allyBuf : slot isole next nil (N72)
  stripBuf : rot sous quota, deux camps, leftover 0 (N73)
  stripBuf : awaitingSpawn skip, leftover 0 (N73)
  stripTerritory : table.clear in-place, voisin intact (N74)
  detonate hashes : boom A, snapshot avant crater (N76)
  detonate hashes : ocean leftover 0, rawequal (N76)
  splitMirv hashes : porteur land, rawequal (N77)
  splitMirv hashes : ocean leftover 1, rawequal (N77)
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 captures=80 pops=160
  factions : 18
  metrics : ticks=6000 avgChanged=8.9 p95Changed=19 maxChanged=479 avgTickMs=0.38 p95TickMs=0.87
  metrics hashes : seenBuf rawequal, nil sans clear (N78)
  metrics hashes : ring 601, Sample recycle, ticks= (N78)
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe34.log`

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
- Crater nuke : `tilesBeforeBuf` / `hitTilesBuf` (N76). `table.clear` **avant** fill. Formule `share = tilesHit / tilesBefore` inchangée. Wrap `installFallout` **après** orig. Ne pas `require(Nukes)` depuis GameState. Visée MIRV → N77 **fermé**.
- Visée MIRV : `mirvTxBuf` / `mirvTyBuf` (N77). `table.clear` **avant** fill. Pas de `Vector2`. Ogives = records **neufs** dans `state.missiles` (possession). `spread` / `minGap=4` / fallback point visé inchangés. Non réentrant — `Nukes.step` série. Ne pas partager `tilesBeforeBuf` / `hitTilesBuf`. Leftover `snapshot` metrics → N79.
- Metrics : `seenBuf` + ring Sample (N78). Early-out delta nil **sans** clear. `formatReport` parse `ticks=`. `snapshot` encore alloué → N79. `reset` `table.clear(history)` → N80. Ne pas `require(TickMetrics)` depuis GameState.
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
- Contacts bots : `Bots.neighborFactions` (N61). `contactBuf` + `table.clear`. Slot 99 / sans joueur = map **vide**. NEUTRAL conservé. 4 appelants lisent puis abandonnent — pas de `table.clone`. Après `removePlayer`, tuiles du disparu = NEUTRAL. Leftover `decideDiplomacy` → N72 **fermé**.
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
- Pactes bots : `Bots.decideDiplomacy` (N72). `allyBuf` hash + `table.clear`. Fill `areAllied` sur `state.players` (**pas** copie des clés `alliances[slot]` — recette visual V42, pas feel 1e43 N91). Coalition / trahison / proposition lisent `allyBuf`. `Bots.allyBuf` exposé banc. Non réentrant — `Bots.step` séquentiel, `clear` au bot suivant **voulu**. Seuils 0.75/0.35/2.2/0.25/0.3 inchangés. Ne pas `require(Bots)` depuis GameState. Ne pas fusionner avec `contactBuf` (N61).
- Rot cadran : `ChantierB.stepDoomsday` (N73). `stripBuf` array + truncate leftover **avant** arrachage, reset **après** chaque slot. Itérer `1..n`. Skip AFK / `awaitingSpawn` **conservé**. `rotQuota` inchangé. Scan `TILE_COUNT` **reste** (N9 / N75). `ChantierB.stripBuf` exposé banc. Non réentrant. Ne pas `require(ChantierB)` depuis GameState. Leftover hashes spawn → N74 **fermé**. Leftover scan → N75.
- Strip spawn : `ChantierB.stripTerritory` (N74). `table.clear(ps.border)` / `table.clear(ps.coast)` in-place. Pas de buf module. `tiles = 0` / `awaitingSpawn` / destroy capital inchangés. Hashes **par joueur**. Banc rawequal + voisin intact. Ne pas `ps.border = nil`.
- Crater nuke : `Nukes.detonate` (N76). `tilesBeforeBuf` / `hitTilesBuf` + `table.clear` **avant** fill. Snapshot `ps.tiles` **avant** crater. Formule `share` inchangée. `Nukes.tilesBeforeBuf` / `Nukes.hitTilesBuf` exposés banc. Non réentrant — `Nukes.step` détone en série, `clear` au boom suivant **voulu**. Wrap `installFallout` après orig. Ne pas partager `samBuf` / `blastX` / `destroyBuf` / `mirvTxBuf`. Leftover `splitMirv` → N77 **fermé**.
- Visée MIRV : `Nukes.splitMirv` (N77). `mirvTxBuf` / `mirvTyBuf` + `table.clear` **avant** fill. Pas de `Vector2`. Fallback `# == 0` → point visé. `Nukes.mirvTxBuf` / `Nukes.mirvTyBuf` exposés banc. Non réentrant — `clear` à la scission suivante **voulu**. Ogives unique. Leftover metrics → N78 **fermé**.
- Metrics tick : `TickMetrics.record` (N78). `seenBuf` + `table.clear` avant fill (delta non-nil). Ring Sample, pas `remove(1)`. `TickMetrics.seenBuf` / `TickMetrics.history` exposés banc. Early-out nil sans clear. Leftover `snapshot` arrays → N79. Leftover `reset` pool → N80.
- `init.server` / `Persistence` restent hors bundle : extraire un helper testable (`MatchLifecycle` / `snapshotBoats` / `snapshotMissiles` / `frontHudForReplicate` / `playerStatsForReplicate` déjà là) ou documenter un test Studio. TickMetrics est **dans** le bundle (N78).
- Humain éliminé : `settledHumans[slot]` **avant** destruction du PlayerState. Bots ignorés. `endMatch` / disconnect après élimination passent par `MatchLifecycle` (init.server hors bundle). Disconnect **vivant** = 0 XP. `Persistence` reste hors du tick. Ne pas recâbler N6.
- Grâce humaine = `Bots.humanTargetProtected` (bots **et** tribus). Ne pas dupliquer une 2e courbe.
- Ne pas casser le client 34/34.
- Ligne feel (#19/#22/#24/#26/#28/#29/#32/#34/#36/#38/#41/#42/#45/#48/#51/#53/#56/#59/#62 + 55ba + 4876 + cc42 + 2f5d + b62d + 69f4 + 07c6 + 2b37 + e277 + 1e43 + a963 + d74d + **c786**) : rebase sur cette passe avant cherry-pick, sinon perte `mirvTxBuf` / ring Sample. Cherry-pick seq obligatoire (N41 feel) et `targetSlot` (N49 feel) seulement. Feel N91 (`allyBuf`) = N72 **fermé via visual V42**. Feel N93 (`stripBuf`) = N73 **fermé via visual V43**. Feel N94 (`stripTerritory`) = N74 **fermé**. Feel N95/N96 (`gainBuf` / `surveyTerritories`) = ligne visuelle. N50/N52 feel (`findSpawn` / `isSpawnSafe`) porte N33. **Ne pas** porter `retreating` Overlay (feel N56) avec N51. **Ne pas** porter `TRAIN_STOP_BONUS` HUD (feel N20) avec N65. **Ne pas** porter feel `guard < 80` (debit hardening = captures/pops). **Ne pas** porter `previewCtx` (feel N92). Client feel = 35/35 ; client hardening = **34/34**.
