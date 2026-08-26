# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 41)

Déclencheur : ouverture de la **PR #130** (`cursor/analyse-nocturne-du-codebase-e488`) — `settledRecPool`, `profilePacket` pool, specs N91–N92.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-e9e5`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #130**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#130. Pas d’outil Slack.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29/#32/#34/#36/#38/#41/#42/#45/#48/#51/#53/#56/#59/#62 + d425 + df65 + 2157 + 5c74 + e735 + 7c38 + 1fb3 + 5bf6 + 741d + 55ba + 4876 + cc42 + 2f5d + b62d + 69f4 + 07c6 + 2b37 + e277 + 1e43 + a963 + d74d + c786 + **4a67 passe 35** / **8f41** / **5bbf** / **de1a** / **04b6** / **5c7e** / **04e7** / **846c**) : ne pas merger sur cette branche sans rebase. Les numéros N40+ feel (settledHumans feel N40, seq, N52–N116…) ne sont **pas** les N40–N94 de ce rapport. Cette passe **ferme** hardening N91 (`MapGen.metaBuf` / `mapMeta`) et N92 (`Trade.deliveryPool` / `dispatch`). Seq obligatoire (feel N41) et `targetSlot` (feel N49/N53) ne sont pas portés. **Pas** de `TRAIN_STOP_BONUS` dans `railIncome` (feel N20 / N84 feel — volontaire ; **≠ N84 hardening déjà fermé**). Feel N94 (`table.clear` border/coast) = N74 **déjà fermé**. N75 (scan cadran) **reste ouvert** — contrat A trop structurel pour un correctif « sûr » (index `setOwner` = autorité). Client hardening = **34/34** (feel 35/35 — Overlay `retreating`). Visual 6b53 V55 = ligne visuelle, pas ici. Payload Intent reste référence live (N82 — ne pas pooler). Persistence `UpdateAsync` **non** poolé (N6). Le record `mapMeta` a **7 champs** (la spec #130 disait 8 — `mapId` / `mapVersion` / `seed` / `generatorVersion` / `terrainHash` / `width` / `height`).

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`. `RequestSnapshot` n’est toujours jamais `FireServer` côté client (N4). DAG : `GameState` ne `require` ni Navy, ni Nukes, ni Trade, ni Bots, ni Buildings, ni Research, ni Diplomacy, ni Placement, ni MatchLifecycle, ni IntentValidator. `Buildings`, `Research`, `Diplomacy` require déjà `GameState` ; `Placement` require Shared only — ne pas inverser. `Nukes` require `GameState` + `Buildings` (pas l’inverse). `TickMetrics` require `Config` seulement. `MatchLifecycle` require `Config` seulement (N37 + N84 + N86 + N88 + N90). `IntentValidator` require Shared only (N82 + N87) — `state` en argument, pas un require. `MapGen` require `Config` seulement (N91) — pas GameState (cycle Shared). `Trade` require `GameState` (N92, pas l’inverse). N66 (`ctxBuf`) vit dans Buildings. N67 (`doomedBuf`) vit dans ChantierB (`install()` serveur seulement). N68 (`parkedBuf`) vit dans BoatFront. N69 (`collapseRemainBuf`) vit dans GameState. N70 (`destroyBuf`) vit dans GameState (`removePlayer`). N89 (`settledRecPool`) vit dans GameState (`removePlayer`). N71 (`blockBuf` / `candBuf` / `queueBuf` / `visitMap` / `emptyTileBuf` / `placeScratch`) vit dans Placement (Shared, pas le ctx client). N72 (`allyBuf`) vit dans Bots. N73 (`stripBuf`) vit dans ChantierB (`install()` serveur seulement). N74 (`table.clear` border/coast) vit dans `ChantierB.stripTerritory` (hashes **par joueur**, pas un buf module). N76 (`tilesBeforeBuf` / `hitTilesBuf`) vit dans **Nukes** (`detonate` seulement). N77 (`mirvTxBuf` / `mirvTyBuf`) vit dans **Nukes** (`splitMirv` seulement). N78–N81 vivent dans **TickMetrics**. N82 + N87 vivent dans **IntentValidator**. N83 (`eventPool` / `soundPool`) vit dans **GameState**. N84 (`rosterBuf`) + N86 (`matchUpdateBuf`) + N88 (`recordBuf`) + N90 (`profileBuf`) vivent dans **MatchLifecycle**. N85 (`plunderPool`) vit dans **GameState**. N91 (`metaBuf`) vit dans **MapGen** (Shared). N92 (`deliveryPool`) vit dans **Trade**.

La PR #130 a bien fermé `settledRecPool` (N89) et `profileBuf` (N90). Cette passe a **corrigé ce que #130 a spécifié** — `mapMeta` allouait encore 7 champs à chaque `startMatch` / late join, et `Trade.dispatch` allouait un record par expédition :

| Bug | Gravité | Statut |
|---|---|---|
| `settledHumans` snapshot (N89) | **P3 alloc élimination** | **déjà fermé** (#130, `settledRecPool[slot]`) |
| `profilePacket` 6 champs (N90) | **P3 alloc join/endMatch** | **déjà fermé** (#130, `buildProfilePacket` / `profileBuf`) |
| `MapGen.mapMeta` 7 champs (N91) | **P3 alloc join** | **corrigé** (`metaBuf`) |
| `Trade.dispatch` delivery (N92) | **P3 alloc commerce** | **corrigé** (`deliveryPool[index]`) |
| `stepDoomsday` scan O(TILE_COUNT) (N9 / N75) | **P2 cadran** | **ouvert** (index compact — leftover N73 ; contrat A trop structurel ici) |
| `indexPort` `{ slot, level }` (N93) | **P3 alloc pose PORT** | **ouvert** (leftover N40, recette `deliveryPool`) |
| `indexFactory` `{ slot, level }` (N94) | **P3 alloc pose FACTORY** | **ouvert** (leftover N45/N92, recette `deliveryPool`) |
| `retreatBoats` filtre `owner[targetTile]` courant | **P2 marine** | **ouvert** (reste de N28 ; feel d425/df65 a la recette) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29) |
| `findSpawn` ignore splash / fallout (N33) | **P3 nucléaire** | **ouvert** (feel d425/df65 a C1+C2 + `isSpawnSafe`) |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#130 + allyBuf (N72) + stripBuf (N73) + stripTerritory hashes (N74) + detonate hashes (N76) + splitMirv hashes (N77) + TickMetrics ring (N78) + snapshot arrays (N79) + reset pool (N80) + snapBuf (N81) + intentPool (N82) + notify/sound pool (N83) + rosterBuf (N84) + plunderPool (N85) + matchUpdateBuf (N86) + contextBuf (N87) + recordBuf (N88) + settledRecPool (N89) + profileBuf (N90) + metaBuf (N91) + deliveryPool (N92).
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #130

**À merger** (`settledRecPool` + `profileBuf` + specs N91–N92), sous réserve que cette passe 41 parte avec : **`mapMeta` allouait encore 7 champs, et `Trade.dispatch` allouait un record par expédition**.

Points encore vrais après #130 :

| Claim #130 | Réalité après passe 41 |
|---|---|
| N89 `settledHumans` snapshot | confirmé |
| N90 `profilePacket` 6 champs | confirmé |
| N91 `MapGen.mapMeta` 7 champs | **fermé ici** (rawequal `metaBuf`, seed à jour, hash seed 1 vs 2 distinct) |
| N92 `Trade.dispatch` delivery | **fermé ici** (rawequal `deliveryPool[index]`, destroy → `tradeDeliveries` nil) |
| N75 `stepDoomsday` scan O(TILE_COUNT) | **ouvert** (ferme N9 si A ou C ; A trop structurel ici) |
| N33 `findSpawn` splash / fallout | **ouvert** |
| N28 retraite après flip / `targetSlot` | **ouvert** |
| N29 `seedBeachhead` no-merge | specs only, inchangé (banc N68 documente 3 Attack) |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |

`init.server.luau` et `Persistence` restent **exclus du bundle**. Le helper `MatchLifecycle` est **dans** le bundle (37 modules serveur — pas de module nouveau). `MapGen.mapMeta` est **dans** le bundle (Shared). `Trade.dispatch` est **dans** le bundle. `snapshotBoats` / `snapshotMissiles` / `flushOwnerDelta` / `flushBuildingDelta` / `frontHudForReplicate` / `playerStatsForReplicate` sont **dans** le bundle (`GameState`). `pricesFor` / `contextFor` vivent dans **Buildings**. `progress` ne alloue plus `ratios` (N58). `Diplomacy.viewFor` recycle `viewBuf[slot]` (N59). `Diplomacy.step` recycle `expiredBuf` (N60). `neighborFactions` recycle `contactBuf` (N61). `gatherSites` recycle `siteBuf` (N62). `stepElimination` recycle `elimBuf` (N63). `findSeaPath` recycle `pathWalkBuf` (N64) — le tableau rendu au bateau **reste unique**. `refreshRailNetwork` recycle `stationBuf` (N65) — `building.links` **reste unique**. `Buildings.contextFor` recycle `ctxBuf` (N66) — pas le ctx client. `ChantierB` recycle `doomedBuf` / `collapsingBuf` (N67). `BoatFront.launchAttack` recycle `parkedBuf` (N68). `collapseFaction` recycle `collapseRemainBuf` / `collapseLeftBuf` (N69). `removePlayer` recycle `destroyBuf` (N70) et `settledRecPool` (N89). `Placement.validTiles` recycle blockers/candidates (N71). `decideDiplomacy` recycle `allyBuf` (N72). `stepDoomsday` recycle `stripBuf` (N73). `stripTerritory` `table.clear` in-place (N74). Scan cadran encore O(carte) (N9 / N75). `Nukes.detonate` recycle `tilesBeforeBuf` / `hitTilesBuf` (N76). `splitMirv` recycle `mirvTxBuf` / `mirvTyBuf` (N77). `TickMetrics.record` recycle `seenBuf` + ring Sample (N78). `snapshot` recycle 4 arrays (N79). `reset` conserve le pool Sample (N80, contrat B `historyCount`). `snapshot` recycle `snapBuf` (N81). `IntentValidator.flush` recycle `intentPool` (N82, contrat B). `notify` / `sound` recycle `eventPool` / `soundPool` (N83). `buildRoster` recycle `rosterBuf` (N84). `plunders` recycle `plunderPool` (N85). Packet `MatchUpdate` recycle `matchUpdateBuf` (N86). Context intents recycle `contextBuf` (N87). `endMatchRecords` recycle `recordBuf` (N88). Snapshot `settledHumans` recycle `settledRecPool` (N89). `profilePacket` recycle `profileBuf` (N90). `mapMeta` recycle `metaBuf` (N91). `Trade.dispatch` recycle `deliveryPool` (N92). `portsByTile[index]` encore alloué (N93). `factoriesByTile[index]` encore alloué (N94).

PR #106 / #105 (feel / visual) ne doivent pas être mergées par-dessus #16/#130 sans rebase. Seq / `targetSlot` / hover `SpawnHint` / Overlay `retreating` / `TRAIN_STOP_BONUS` HUD / `previewCtx` restent feel-only. Visual 6b53 V55 = ligne visuelle, pas ici.

On peut fermer #17, #18, #20, #23, #25, #27, #30, #31, #33, #35, #37, #40, #43, #46, #49, #52, #55, #58, #60, #63, #66, #70, #73, #76, #80, #83, #85, #88, #91, #95, #98, #102, #104, #109, #112, #116, #119, #123, #127 et #130 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| `MapGen.mapMeta` record (N91) | `MapGen.luau`, `init.server.luau`, `tests/simulate.luau` | Pool `metaBuf` (un record). `mapMeta` réécrit les 7 champs. `init.server` continue d’assigner `currentMapMeta = MapGen.mapMeta(...)` (référence live). Late join utilise `currentMapMeta` si non-nil — fallback `mapMeta` seulement si nil. Ne require **pas** GameState. Recette spec #130 N91. Banc N90 / N4 **verts**. **≠ feel historique.** |
| `Trade.dispatch` delivery (N92) | `Trade.luau`, `tests/simulate.luau` | Pool `deliveryPool[index]` (recette `settledRecPool` N89). `dispatch` réécrit les 6 champs. Usine sans colis → `tradeDeliveries[index] = nil`. `removePlayer` continue de nil les colis du slot. Destroy usine → `Trade.step` nil le colis ; le pool **survit**. `level` snapshot au départ **inchangé**. Ne require **pas** un module nouveau. Recette spec #130 N92. Banc colis snapshot / N45 **verts**. **Ne pas** pooler `factory.links` (N65). |

**Non modifié (volontaire) :** N1–N90 restant, reste de N28 (`targetSlot`). N10.8. Cap beachheads (N5 / N29). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` / `require(Placement)` / `require(MatchLifecycle)` / `require(IntentValidator)` depuis GameState. Pas de contrat C spawn (N33). Pas de seq obligatoire (feel N41). Pas de spatial hash warships. Buffer `defense` **alloué** mais plus écrit. Pas de `TRAIN_STOP_BONUS` dans `railIncome` (N18 / feel N20). Scan cadran encore O(carte) (N9 / N75) — contrat A (`tilesBySlot` dans `setOwner`) trop structurel : un index déréglé vs `owner` = pourriture du mauvais camp. `portsByTile[index]` encore alloué (N93). `factoriesByTile[index]` encore alloué (N94). Pas de `retreating` Overlay (feel N56 historique). Debit `captures`/`pops` **non** remplacé par feel `guard < 80`. `PlacementPreview` / `tests/client.luau` **non** édités. Skip AFK cadran **conservé**. Ogives MIRV **non** poolées (possession). `clearPlayer` reste `table.remove` (leftover cheap). Texte / kind / `only` / règle « humain impliqué » de `notifyBetween` **inchangés**. `betrayals` / doctrine lock **inchangés**. Payload Intent = référence live (N82 : **ne pas** pooler — possession RemoteEvent). Persistence `UpdateAsync` **non** poolé (N6). Closures `reply`/`refuse` **stables** (N87 ne les recrée pas). Sémantique N37 **inchangée** (humain snapshotte, bot ignore). `countByBiome` encore alloué (test-only, pas ticket). `structureHash` `indices = {}` reste N4 (client jamais `FireServer`).

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
- **Posted FACTORY** = `factoriesByTile[index]={slot,level}` (N45). `Trade.step` flatten depuis l’index, pas `buildings`. Dispatch colis poolé (N92). Record index encore alloué (N94).
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
- **Commerce maritime** = `portsByTile` incrémental (PORT seulement, N40). Vague plafonnée **avant** flatten. `canTrade` = embargo-only. Record `{slot,level}` encore alloué (N93).
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients` (N26). Snapshot navires = `GameState.snapshotBoats` (`boatSnapBuf`, N51). Snapshot missiles = `GameState.snapshotMissiles` (`missileSnapBuf`, N52). Owner delta = `dirtyIndexBuf` (N53), buffer outbound **neuf**. BuildingDelta = `buildingSnapBuf` (N54), `links` live. HUD fronts = `frontHudForReplicate` (N55), appelé **une** fois depuis N57. `buildPrices` = `Buildings.pricesFor` (N56). Records stats = `playerStatsForReplicate` (N57). `Research.progress` min courant (N58). `Diplomacy.viewFor` recycle par slot (N59). `Diplomacy.step` recycle `expiredBuf` (N60). `neighborFactions` recycle `contactBuf` (N61). `gatherSites` recycle `siteBuf` (N62). `stepElimination` recycle `elimBuf` (N63). `findSeaPath` `pathWalkBuf` (N64, retour unique). `refreshRailNetwork` `stationBuf` (N65). `contextFor` `ctxBuf` (N66). Combat `doomedBuf`/`collapsingBuf` (N67). `parkedBuf` (N68). `collapseRemainBuf` (N69). Snapshot destroy `destroyBuf` (N70). `validTiles` blockers (N71). `allyBuf` (N72). `stripBuf` (N73). `stripTerritory` `table.clear` (N74). Scan cadran encore O(carte) (N9 / N75). `Nukes.detonate` `tilesBeforeBuf`/`hitTilesBuf` (N76). `splitMirv` `mirvTxBuf`/`mirvTyBuf` (N77). `TickMetrics.record` `seenBuf` + ring Sample (N78). `snapshot` 4 arrays (N79). `reset` pool Sample (N80). `snapBuf` (N81). `intentPool` (N82). Notify/sfx `eventPool`/`soundPool` (N83). Roster `rosterBuf` (N84). Plunders `plunderPool` (N85). Packet `MatchUpdate` `matchUpdateBuf` (N86). Context intents `contextBuf` (N87). Gravure `recordBuf` (N88). Snapshot `settledRecPool` (N89). Packet profil `profileBuf` (N90). Métadonnées carte `metaBuf` (N91). Colis `deliveryPool` (N92). `portsByTile` record encore alloué (N93). `factoriesByTile` record encore alloué (N94).
- **DataStore** : `settledHumans` avant destruction du PlayerState (record poolé N89). `endMatch` grave via `MatchLifecycle.endMatchRecords` (porteuse poolée N88, snapshot poolé N89). Packet HUD `profileUpdate` / `mapInit` poolé (N90 + N91). `Persistence.record` max-merge inchangé (N6 — **ne pas** pooler).
- **Require** : DAG. Pas de cycle. `MatchLifecycle` → Config seulement (N37 + N84 + N86 + N88 + N90). `IntentValidator` → Shared only (N82 + N87). `MapGen` → Config seulement (N91). `Tribes` → `Bots` (export `humanTargetProtected` seulement). `Navy` → `GameState` (unidirectionnel). `Nukes` → `GameState` + `Buildings`. `Trade` → `GameState` (N92, pas l’inverse). `Bots` → `GameState` (pas l’inverse). `Buildings` → `GameState` (pas l’inverse — N56/N66 vivent dans Buildings). `Research` → `GameState` (pas l’inverse). `Diplomacy` → `GameState` (pas l’inverse). `Placement` → Shared only (N71 — **ne pas** require Placement depuis GameState). `TickMetrics` → Config seulement (N78). `ChantierB`/`BoatFront`/`AimFront` dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).
- **BFS mer** : `visitBuf` + `parentScratch` + `queueScratch` + `pathWalkBuf` module-level. Un seul chemin en vol à la fois (Navy n’est pas réentrant). Résultat path **unique** (copie inverse, N64).
- **Notify / sfx** : `eventPool` / `soundPool` module-level (N83). Truncate leftover = drain, pas notify. Non réentrant — `flushEvents` unique / tick. Overlay lit tout de suite.
- **Plunders** : `plunderPool` module-level (N85). Truncate leftover = `drainPlunders`. Overlay lit `tile`/`slot`/`gold` tout de suite. Distinct de `eventPool`.
- **Roster 1 Hz** : `rosterBuf` + `rosterRecPool[slot]` dans MatchLifecycle (N84). `table.clear` puis refill. Slot disparu absent. `init.server` pose le FireAllClients.
- **MatchUpdate 1 Hz** : `matchUpdateBuf` dans MatchLifecycle (N86). Overwrite scalaires. `summary` ended = live `statsBuf` (N57). `init.server` mute `matchUpdateArgs` local.
- **Context intents** : `contextBuf` dans IntentValidator (N87). Overwrite 14 champs. Closures stables. `init.server` mute `contextArgs` local. Non réentrant — enqueue + flush le même tick partagent le record.
- **Gravure fin de match** : `recordBuf` + `recordRecPool` + `seenBuf` dans MatchLifecycle (N88). `table.clear` au début. `stats` live = `settledRecPool[slot]` (N89).
- **Snapshot éliminé** : `settledRecPool[slot]` dans GameState (N89). Humain seulement. Pool module survit à `GameState.new`.
- **Packet profil** : `profileBuf` dans MatchLifecycle (N90). Join `lastGain = nil` après un endMatch qui avait un gain.
- **Métadonnées carte** : `metaBuf` dans MapGen (N91). `startMatch` + late join. Un leftover `seed` / `terrainHash` = client qui refuse la carte.
- **Colis commerce** : `deliveryPool[index]` dans Trade (N92). Un record par tuile d’usine. Overlay lit `onEvent("arrival")` tout de suite.

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N94 restent ouverts** sauf N19 partiel, N21 **fermé**, N24 remplacé par N31 (**fermé**), N30–N32 **fermés**, N34–N74 **fermés**, N76–N92 **fermés**. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + N75 + le reste de N28 / N29 / N33.

---

### ISSUE-N28 — `retreatBoats` / `retreatAttack` après flip de côte (reste)

**Priorité :** P2 combat / comptabilité navale. **Partiel :** inbound `removePlayer` **fermé** en passe 8.

**Problème restant :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetSlot`. Conséquences encore vraies :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers).
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

Feel d425 (N49) + df65 (N53) : `launchInvasion` pose `targetSlot`, `retreatBoats` filtre l’intention (fallback `owner[targetTile]`), wrap 2e geste rappelle les tardifs, `Navy.step` auto-retraite si `owner[targetTile] ~= targetSlot`. **Porter, ne pas réinventer.** Distinct de N10.8 et du fix inbound. Distinct de N35 (`destSlot` convoi ≠ `targetSlot` invasion). Distinct de N40 / N44–N94 (index / snapshots / HUD / `progress` / `viewFor` / `expired` / contacts / sites / elim / path / rail / ctx / doomed / parked / collapse / destroy / validTiles / allyBuf / stripBuf / strip hashes / detonate hashes / splitMirv / TickMetrics / notify / roster / plunders / MatchUpdate / intentContext / gravure / settled / profile / mapMeta / dispatch, **fermés** ou **specs**).

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite.

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste, trancher si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`. Recette feel : branche `d425` / `df65`.

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N22). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % déjà livré). Ne pas recâbler N35 (convois, `kind==2`). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).** Ne pas porter AimFront ni seq. Ne pas recâbler N50–N94.

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

**Contraintes :** ne pas annuler une frappe tiers (régression `nuke third-party`). Ne pas rembourser l’or. Pas de RemoteFunction. Rayon lu depuis `NUKE_STATS` / `missile.radius`, pas une constante magique. Ne pas porter isolation clic (feel N55) dans le même PR. Ne pas recâbler N50–N94. Ne pas mixer N76 (`tilesBeforeBuf` — leftover alloc, **déjà fermé**) ni N77 (`mirvTxBuf` — **déjà fermé**).

---

### ISSUE-N75 — `stepDoomsday` scanne encore `0..TILE_COUNT-1` par camp qui saigne

**Priorité :** P2 cadran / perf. Leftover explicite de N9 et de N73 (« ne pas remplacer le scan 40 960 — ticket suivant »). Distinct de N73 (`stripBuf` liste temporaire, **déjà fermé**) et de N74 (`stripTerritory` hashes spawn, **déjà fermé**). Ne pas toucher `rotQuota`. **N75 hardening ≠ N75 feel historique (`pricesFor`).** Visual V13 décrit le même trou. **Non livré en passe 41** : contrat A (`tilesBySlot` maintenu dans `setOwner`) est un index d’autorité — un déréglage vs `owner` pourrit le mauvais camp. Trop structurel pour un correctif « sûr » à côté de N91/N92.

**Problème :** même avec `stripBuf` recyclé, chaque slot sous quota (10 Hz, late-game plusieurs camps) re-scanne `Config.TILE_COUNT` (40 960) jusqu’à `quota * 4` hits. Un shard 18 factions en cadran = jusqu’à ~17 scans linéaires / tick. Il n’existe pas d’index compact tuiles-par-slot : `ps.tiles` est un compteur, `ps.border` / `ps.coast` ne couvrent pas l’intérieur. N73 a volontairement laissé ce scan.

**Pourquoi 20K CCU :** leftover N9. Late-game cadran = le tick le plus cher du shard (hors combat). Recycle de la porteuse (N73) n’enlève pas les 40k reads `buffer.readu8`. Un index compact (reservoir / linked list / dirty set) ramène le rot à O(tuiles du camp) au lieu de O(carte). Pas d’autorité si `setOwner` maintient l’index. Ne pas fusionner avec N74 : strip spawn parcourt encore la carte une fois au join, pas 10 Hz.

**Worker :**

1. Choisir un contrat : (A) `tilesBySlot[slot] = { number }` array compact, maintenu dans `setOwner` (insert au claim, swap-pop au loss) — `stepDoomsday` itère `1..ps.tiles` au lieu de `0..TILE_COUNT-1` ; (B) reservoir bitset 40 960 / 8 recyclé, rebuild seulement si dirty ; (C) documenter « scan O(carte) accepté, N9 fermé sans code ». **Un seul.** Feel / visual n’ont pas encore fermé V13. Pas de RemoteFunction.
2. Si A : `setOwner` est le **seul** writer. `removePlayer` / `collapseFaction` / `stripTerritory` / rot cadran passent déjà par `setOwner`. Ne pas maintenir un 2e index à côté. Cap array = `TILE_COUNT` worst-case d’un camp. Truncate leftover **avant** usage. Ne pas `require` de module nouveau. Skip AFK / `awaitingSpawn` **conservé**. `stripBuf` (N73) peut rester (copie depuis l’index) ou disparaître si on itère l’index directement — trancher et tester leftover inter-slots.
3. Test : bancs N73 stripBuf / doomsday recycle / AFK **doivent rester verts**. Ajouter : un camp sous quota → même `ripped` / `tiles` qu’aujourd’hui (déterminisme seed). Deux camps. `setOwner` d’une tuile intérieure met à jour l’index (rot la trouve, `ps.tiles` vs buffer). Client **34/34**. 6000 ticks. Mesurer `avgTickMs` cadran vs HEAD.

**Contraintes :** pas de RemoteFunction. **N75 hardening ≠ N73 (`stripBuf`, déjà fait) ≠ N74 (`border`/`coast`, **déjà fait**) ≠ N76–N92 (déjà faits) ≠ N9 (umbrella — ce ticket **ferme** N9 si A ou C).** Ne pas changer `rotQuota` / drain / WARN. Ne pas scanner `buildings`. Overlay n’itère pas l’index. Un index déréglé vs `owner` = pourriture du mauvais camp (invariants `tiles` vs buffer le verront). Ne pas `require(ChantierB)` depuis GameState. Ne pas mixer avec N93 (`portsByTile`) ni N94 (`factoriesByTile`).

---

### ISSUE-N91 — `MapGen.mapMeta` — **FERMÉ** (passe 41)

`MapGen.metaBuf` un record. `mapMeta` overwrite 7 champs. `currentMapMeta` = référence live. Late join fallback seulement si nil. Banc : rawequal, seed à jour, hash seed 1 vs 2 distinct. Ne pas rouvrir. Un leftover `terrainHash` = resync client (banc hash 4242). Leftover `portsByTile` record → N93. Leftover `factoriesByTile` record → N94.

---

### ISSUE-N92 — `Trade.dispatch` — **FERMÉ** (passe 41)

`deliveryPool[index]` (recette `settledRecPool` N89). `dispatch` réécrit. Usine sans colis → `tradeDeliveries[index] = nil`. Destroy → nil colis, pool survit. Banc : rawequal recycle, `arrivalTick` à jour, destroy nil. Banc colis snapshot **vert** (`level` snapshot). Ne pas rouvrir. Un leftover `slot` = or au mauvais camp. Leftover `factoriesByTile` record → N94. Leftover `portsByTile` record → N93. **Ne pas** pooler `factory.links` (N65).

---

### ISSUE-N93 — `GameState.indexPort` alloue `{ slot, level }` à chaque pose / upgrade PORT

**Priorité :** P3 alloc pose. Leftover explicite de N40 (`portsByTile` incrémental / `portsBuf` flatten recyclé ; le **record index** alloue encore) et de N91/N92 (même recette `deliveryPool[index]`). Distinct de N40 (`portsBuf` vague, **fermé**). Distinct de N92 (`deliveryPool` colis, **fermé**). Distinct de N48 (`navalBasesBySlot` set booléen). **N93 hardening ≠ N93 feel historique (si un jour numéroté).** N40 a volontairement laissé le record `{slot,level}` hors ticket : c’est **ce** ticket.

**Problème :** `indexPort` fait encore `self.portsByTile[index] = { slot = slot, level = level }` à chaque pose / upgrade / transfer. `spawnTradeShips` lit `info.slot` / `info.level`. Un clash 26 PORT observés × upgrade = autant d’allocs abandonnées. `indexPort(..., false)` nil la clé — le record n’est pas recyclé.

**Pourquoi 20K CCU :** leftover naturel une fois flatten PORT + colis fermés. Recycle `portRecPool[index]` (recette `deliveryPool` N92). Pas d’autorité si les 2 champs **inchangés**. Un leftover `slot` d’un PORT recyclé = convoi du mauvais camp (le banc `trade spawn index` / inbound le verra). `table.clear` **interdit** (ce n’est pas un hash, c’est un record 2 champs).

**Worker :**

1. Pool `portRecPool[index]` (un record par tuile PORT). `indexPort(..., true)` réécrit `slot` / `level`. `indexPort(..., false)` → `portsByTile[index] = nil` (pas un leftover vivant). Pool module survit à `GameState.new`. Pas de RemoteFunction. Rester dans `GameState.luau` — ne pas `require` Navy (cycle).
2. Ne pas changer la loi de tirage `spawnTradeShips` (poids = `level`, `canTrade` embargo, early-out cap). Banc N40 pose / upgrade / destroy / vague / cap **doivent rester verts**. 2e pose même tuile (destroy puis pose) → `rawequal` record, champs à jour.
3. Test : pose PORT → `rawequal(state.portsByTile[index], GameState.portRecPool[index])`. Upgrade → même record, `level` à jour. Destroy → `portsByTile[index] == nil`, pool survit. Transfer → `slot` à jour. Client **34/34**. 6000 ticks.
4. Fichiers : `GameState.luau` (`indexPort`, exposer `portRecPool` banc), `tests/simulate.luau` (étendre le banc N40 ou bloc court). `Navy.luau` / `Trade.luau` / `init.server` inchangés. Pas de recette feel.

**Contraintes :** pas de RemoteFunction. **N93 hardening ≠ N40 (flatten, déjà fait) ≠ N92 (colis, déjà fait) ≠ N48 (NAVAL_BASE).** Overlay n’écrit pas cet index. Un leftover `slot` = convoi fantôme (invariants PORT + banc spawn). Ne pas mixer N75 / N94. Ne pas pooler `boat.path` (N64, unique). Ne pas changer `portsBuf` (déjà recyclé).

---

### ISSUE-N94 — `GameState.indexFactory` alloue `{ slot, level }` à chaque pose / upgrade FACTORY

**Priorité :** P3 alloc pose. Leftover explicite de N45 (`factoriesByTile` incrémental / `factoriesBuf` flatten recyclé ; le **record index** alloue encore) et de N92 (`dispatch` poolé ; l’index que `Trade.step` parcourt alloue encore). Distinct de N45 (`factoriesBuf` flatten, **fermé**). Distinct de N92 (`deliveryPool` colis, **fermé**). Distinct de N93 (`portRecPool` PORT — **ne pas** fusionner les deux pools : kinds distincts, leftover croisé = usine lue comme port). **N94 hardening ≠ N94 feel historique (si un jour numéroté).** N45 a volontairement laissé le record `{slot,level}` hors ticket : c’est **ce** ticket.

**Problème :** `indexFactory` fait encore `self.factoriesByTile[index] = { slot = slot, level = level }` à chaque pose / upgrade / transfer. `Trade.step` n’utilise que les **clés** (flatten), mais les tests N45 lisent `rec.slot` / `rec.level` et `upgradeBuilding` réécrit le record. Un clash 48 usines observées × upgrade = autant d’allocs abandonnées. `indexFactory(..., false)` nil la clé — le record n’est pas recyclé.

**Pourquoi 20K CCU :** leftover naturel une fois flatten FACTORY + colis fermés. Recycle `factoryRecPool[index]` (recette `deliveryPool` N92, pool **séparé** de N93). Pas d’autorité si les 2 champs **inchangés**. Un leftover `slot` d’une usine recyclée = flatten du mauvais camp (le banc N45 transfer / `removePlayer` index le verra). `table.clear` **interdit**.

**Worker :**

1. Pool `factoryRecPool[index]` (un record par tuile FACTORY). `indexFactory(..., true)` réécrit `slot` / `level`. `indexFactory(..., false)` → `factoriesByTile[index] = nil`. Pool module survit à `GameState.new`. Pas de RemoteFunction. Rester dans `GameState.luau` — ne pas `require` Trade (cycle). **Ne pas** partager le pool avec N93 (`portRecPool`).
2. Ne pas changer `Trade.step` flatten / sort / `deliveryValue` / `level` snapshot. Banc N45 pose / upgrade / transfer / destroy / flatten ignore hash **doivent rester verts**. Banc N92 delivery pool **vert**. 2e pose même tuile → `rawequal` record, champs à jour.
3. Test : pose FACTORY → `rawequal(state.factoriesByTile[index], GameState.factoryRecPool[index])`. Upgrade → même record, `level` à jour. Transfer → `slot` à jour. Destroy → `factoriesByTile[index] == nil`, pool survit. Client **34/34**. 6000 ticks.
4. Fichiers : `GameState.luau` (`indexFactory`, exposer `factoryRecPool` banc), `tests/simulate.luau` (étendre le banc N45 ou bloc court). `Trade.luau` / `Navy.luau` / `init.server` inchangés. Pas de recette feel.

**Contraintes :** pas de RemoteFunction. **N94 hardening ≠ N45 (flatten, déjà fait) ≠ N92 (colis, déjà fait) ≠ N93 (PORT, ticket jumeau — pools séparés).** Overlay n’écrit pas cet index. Un leftover `slot` = usine fantôme (invariants FACTORY + banc N45). Ne pas mixer N75. Ne pas pooler `factory.links` (N65, unique). Ne pas changer `factoriesBuf` (déjà recyclé). Ne pas fusionner avec `deliveryPool` (colis ≠ index).

---

## 5b. N1–N94 encore ouverts ou fermés (passes 2–41)

| ID | Titre | Prio | Note passe 41 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + `SAM_INTERCEPT_CHANCE` 0.55→1 ; clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz ; bateaux → **N51 fermé** ; … ; Intent queue → **N82 fermé** ; notify/sfx → **N83 fermé** ; roster → **N84 fermé** ; plunders → **N85 fermé** ; MatchUpdate → **N86 fermé** ; context intents → **N87 fermé** ; gravure → **N88 fermé** ; settled → **N89 fermé** ; profilePacket → **N90 fermé** ; mapMeta → **N91 fermé** ; Trade.dispatch → **N92 fermé** ; reste skip-si-inchangé ; portsByTile record → **N93** ; factoriesByTile record → **N94** |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` **jamais** `FireServer` côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | park `isBeachhead` → hors cap land ; **2 beachheads parked + 1 terre = 3** — voir N29 ; alloc parked → **N68 fermé** |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions. **Ne pas** pooler (N90 le rappelle). |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | refund + retraite `RETREAT_LOSS` alignés ; wrap vivant → **N67 fermé** ; `collapseFaction` remaining → **N69 fermé** |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | timers slot maintenant purgés ; liste temporaire → **N73 fermé** ; hashes spawn → **N74 fermé** ; le scan rot est toujours O(tuiles) → **N75** |
| N10 | Divers P3 | P3 | donations gold sans plafond ; `pendingMode` last-writer ; README SmoothTerrain ; notify/sfx → **N83 fermé** ; roster → **N84 fermé** ; plunders → **N85 fermé** ; MatchUpdate → **N86 fermé** ; context → **N87 fermé** ; gravure → **N88 fermé** ; settled → **N89 fermé** ; profile → **N90 fermé** ; mapMeta → **N91 fermé** ; dispatch → **N92 fermé** ; portsByTile record → **N93** ; factoriesByTile record → **N94** |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | debit = `attackTilesPerTick` × speed, **captures<80 pops<160** |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 observé) | P1 | `Bots.spawnAll` wrap + `Tribes.spawnAll(6)` hors budget |
| N13–N27 | (ère / heap / embargo / rail HUD / QuickChat / warships / …) | — | inchangés vs passe 40 ; voir rapport #130 |
| N28 | `retreatBoats` après flip | P2 | **partiel** : inbound fermé passe 8 ; `targetSlot` ouvert (recette feel N49/N53) |
| N29 | `seedBeachhead` no-merge | P2 | specs only. Banc N68 documente 3 Attack (2 ponts + terre). |
| N30–N32 | inbound missile / pool BFS / convoi | P2 | **fermés** |
| N33 | `findSpawn` splash / fallout | P3 | specs only (recette feel N50/N52) |
| N34–N74 | (index / snapshots / HUD / diplomatie / bots / combat wrap / pose) | — | **tous fermés** (passes 11–32). Voir rapport #102. |
| N75 | `stepDoomsday` scan O(TILE_COUNT) | P2 | specs only. Leftover N9 / N73. Ferme N9 si contrat A ou C. **Non livré ici** (A trop structurel). |
| N76–N86 | detonate / MIRV / TickMetrics / Intent queue / notify / roster / plunder / MatchUpdate | P3 | **fermés** (passes 33–38) |
| N87 | `intentContext()` table 14 champs | P3 | **fermé**. Leftover N82. Closures stables. **Ne pas** pooler `payload`. |
| N88 | `endMatchRecords` `{ RecordTarget }` | P3 | **fermé**. Leftover N84/N86. Sémantique N37 **inchangée**. |
| N89 | `settledHumans` snapshot | P3 | **fermé**. Leftover N88. 5 champs, humain seulement. |
| N90 | `profilePacket` 6 champs | P3 | **fermé**. Leftover N88. Join + endMatch. **Ne pas** pooler N6 / payload. |
| N91 | `MapGen.mapMeta` 7 champs | P3 | **fermé**. Leftover N90. `startMatch` + late join. |
| N92 | `Trade.dispatch` delivery | P3 | **fermé**. Leftover N45. Un record par usine. |
| N93 | `indexPort` `{ slot, level }` | P3 | specs only. Leftover N40. Recette `deliveryPool`. |
| N94 | `indexFactory` `{ slot, level }` | P3 | specs only. Leftover N45/N92. Pool **séparé** de N93. |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu (reset à `startMatch` suffit — N87 continue de l’écrire) ; disconnect mid-match **vivant** = `Persistence.record(..., false)` 0 XP (chemin distinct de N37 ; éliminé puis leave **grave** le snapshot) ; wrap `launchAttack` n’applique `AimFront.focus` que si le couple n’existait pas (renfort = pas de re-visée — feel N36). Spatial hash warships (contrat A de N39) volontairement non fait. `Trade.step` `factoriesBuf` déjà recyclé (N45). `structureHash` O(B log B) seulement sur `RequestSnapshot` rate-limité (N4, client jamais `FireServer`). `Nukes.step` `table.remove` missiles encore O(n) par intercept/scission/détonation (pas ticket : ordre reverse-iter conservé). `clearPlayer` reste `table.remove` (cheap vs leftover N82). Payload Intent = référence live (N82, **ne pas** pooler — N87/N90 le rappellent). `{ index = … }` RemoteEvent = possession (N82). `MapGen.countByBiome` encore alloué (test-only, pas 10 Hz).

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
| `TRAIN_STOP_BONUS` | (Config) | (apply) | **non** sur cette ligne (feel HUD N20 ; N65 n’a **pas** porté le × bonus) |
| `NUKE_STATS[ATOM].radius` | 9 | 9 | oui (`detonate` — N76, hashes recyclés) |
| `NUKE_STATS[MIRV].warheads` | 6 | 6 | oui (`splitMirv` — N77, `mirvTxBuf` cap) |

---

## 7. Preuve tests

```
./tests/run.sh  → exit 0
bundle server : 37 modules
Serveur : Tous les invariants tiennent.
  … gardes #17–#130 inchangés …
  notify/sound pool : rawequal [1], #=0 (N83)
  roster pool : rawequal, removePlayer, doctrine (N84)
  plunder pool : rawequal [1], #=0 (N85)
  matchUpdate pool : rawequal, summary, reset (N86)
  intent context : rawequal, phase, reset (N87)
  endMatch pool : rawequal [1], skip, leftover (N88)
  settled pool : rawequal slot, bot/99 nil (N89)
  profilePacket pool : rawequal, lastGain nil, reset (N90)
  mapMeta pool : rawequal, seed a jour, hash distinct (N91)
  delivery pool : rawequal index, destroy nil (N92)
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 captures=80 pops=160
  factions : 18
  metrics : ticks=6000 avgChanged=8.9 p95Changed=19 maxChanged=479 avgTickMs=0.37 p95TickMs=0.85
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe41.log`

---

## 8. Instructions worker (si reprise)

- Vérité runtime d’équilibrage = `ChantierB.apply(Config)` après `SystemsBootstrap.install()`, PAS `Config.luau` seul.
- Combat vivant = patches ChantierB, pas `GameState.stepAttacks` (sauf `returnCommittedTroops` et `retreatAttack`, partagés). Debit **captures < 80 / pops < 160** (pas feel `guard < 80`).
- `areAllied` = deux sens **et** expiry. Ne pas revenir à un test `~= nil`. Bots / chat / tribus : **jamais** `alliances[slot][other]` comme vérité.
- `retreatAttack` = **tous** les fronts du couple. Ne pas revenir à un `return` au premier match.
- Cote déjà nôtre ≠ retraite. Allié en mer = toujours retraite 25 % (N10.8). Inbound disparu = 100 % (comme front terre).
- Purge inbound d’un slot = **dans `removePlayer`**, pas seulement dans `Diplomacy.step`. Inclut cadran + colis + **transports** + **missiles** + **convois kind==2** (avant `setOwner`).
- Ne pas `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` / `require(Placement)` / `require(MatchLifecycle)` / `require(IntentValidator)` depuis GameState (cycle).
- Notify / sfx : `eventPool` / `soundPool` (N83). `drainEvents` / `drainSounds` truncate. Overlay lit tout de suite.
- Plunders : `plunderPool` (N85). `drainPlunders` truncate. Overlay lit `tile`/`slot`/`gold` tout de suite. `where = collapseRemainBuf[1]` avant swap (N69).
- Roster : `MatchLifecycle.buildRoster(players)` (N84). `rosterBuf` + inner par slot. Ne pas `require(GameState)`. Quatre champs seulement.
- MatchUpdate : `MatchLifecycle.buildMatchUpdate(args, buf)` (N86). Un record. `summary` = live ou nil. Ne pas `require(GameState)`.
- Context intents : `IntentValidator.fillContext(args, buf)` (N87). Un record. Closures **stables**. `now` = fonction. Ne pas `require(GameState)`.
- Gravure : `endMatchRecords` recycle `recordBuf` (N88). `stats` live = `settledRecPool[slot]` (N89). `table.clear(seenBuf)` au début.
- Snapshot éliminé : `settledRecPool[slot]` (N89). Humain seulement. Pool module survit. Ne pas `require(MatchLifecycle)` depuis GameState.
- Packet profil : `MatchLifecycle.buildProfilePacket(profile, lastGain, buf)` (N90). Un record. `lastGain` nil ecrase leftover. Ne pas `require(GameState)` ni Persistence. **Ne pas** pooler N6.
- Métadonnées carte : `MapGen.mapMeta(seed, terrain)` recycle `metaBuf` (N91). Un record. Ne pas `require(GameState)`. Un leftover `terrainHash` = resync client.
- Colis commerce : `Trade.dispatch` recycle `deliveryPool[index]` (N92). Usine sans colis → nil. Ne pas `require` un module nouveau. **Ne pas** pooler `factory.links` (N65).
- File d’intents : `IntentValidator.enqueue` réécrit `intentPool[n]` (N82). `flush` nil `queue[1..n]`. Schema / sequence / rate inchangés. **Payload = référence live — ne pas pooler** (N87/N90 ne touchent pas le payload).
- Metrics : `seenBuf` + ring Sample (N78). `snapshot` 4 arrays (N79). `reset` pool (N80). `snapBuf` (N81).
- `init.server` / `Persistence` restent hors bundle : extraire un helper testable (`MatchLifecycle.buildRoster` / `buildMatchUpdate` / `endMatchRecords` / `buildProfilePacket` déjà là ; `fillContext` dans IntentValidator pour N87 ; `mapMeta` dans MapGen pour N91) ou documenter un test Studio.
- Ne pas casser le client 34/34.
- Ligne feel : rebase sur cette passe avant cherry-pick, sinon perte `metaBuf` / `deliveryPool`. Cherry-pick seq obligatoire (N41 feel) et `targetSlot` (N49 feel) seulement. **Ne pas** porter `retreating` Overlay (feel N56). **Ne pas** porter `TRAIN_STOP_BONUS` HUD (feel N20). **Ne pas** porter feel `guard < 80`. Client feel = 35/35 ; client hardening = **34/34**.
