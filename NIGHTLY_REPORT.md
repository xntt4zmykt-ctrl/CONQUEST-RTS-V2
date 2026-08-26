# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 42)

Déclencheur : ouverture de la **PR #135** (`cursor/analyse-nocturne-du-codebase-e9e5`) — `metaBuf`, `deliveryPool`, specs N93–N94.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-2c0f`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #135**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#135. Pas d’outil Slack.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29/#32/#34/#36/#38/#41/#42/#45/#48/#51/#53/#56/#59/#62 + d425 + df65 + 2157 + 5c74 + e735 + 7c38 + 1fb3 + 5bf6 + 741d + 55ba + 4876 + cc42 + 2f5d + b62d + 69f4 + 07c6 + 2b37 + e277 + 1e43 + a963 + d74d + c786 + **4a67 passe 35** / **8f41** / **5bbf** / **de1a** / **04b6** / **5c7e** / **04e7** / **846c** / **ab04**) : ne pas merger sur cette branche sans rebase. Les numéros N40+ feel (settledHumans feel N40, seq, N52–N118…) ne sont **pas** les N40–N96 de ce rapport. Cette passe **ferme** hardening N93 (`GameState.portRecPool` / `indexPort`) et N94 (`GameState.factoryRecPool` / `indexFactory`). Seq obligatoire (feel N41) et `targetSlot` (feel N49/N53) ne sont pas portés. **Pas** de `TRAIN_STOP_BONUS` dans `railIncome` (feel N20 / N84 feel — volontaire ; **≠ N84 hardening déjà fermé**). Feel N94 (`table.clear` border/coast) = N74 **déjà fermé**. N75 (scan cadran) **reste ouvert** — contrat A trop structurel pour un correctif « sûr » (index `setOwner` = autorité). Client hardening = **34/34** (feel 35/35 — Overlay `retreating`). Visual 6b53 V55 = ligne visuelle, pas ici. Payload Intent reste référence live (N82 — ne pas pooler). Persistence `UpdateAsync` **non** poolé (N6). Pools PORT / FACTORY **séparés** : un leftover croisé = usine lue comme port (convoi fantôme).

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`. `RequestSnapshot` n’est toujours jamais `FireServer` côté client (N4). DAG : `GameState` ne `require` ni Navy, ni Nukes, ni Trade, ni Bots, ni Buildings, ni Research, ni Diplomacy, ni Placement, ni MatchLifecycle, ni IntentValidator. `Buildings`, `Research`, `Diplomacy` require déjà `GameState` ; `Placement` require Shared only — ne pas inverser. `Nukes` require `GameState` + `Buildings` (pas l’inverse). `TickMetrics` require `Config` seulement. `MatchLifecycle` require `Config` seulement (N37 + N84 + N86 + N88 + N90). `IntentValidator` require Shared only (N82 + N87) — `state` en argument, pas un require. `MapGen` require `Config` seulement (N91) — pas GameState (cycle Shared). `Trade` require `GameState` (N92, pas l’inverse). N66 (`ctxBuf`) vit dans Buildings. N67 (`doomedBuf`) vit dans ChantierB (`install()` serveur seulement). N68 (`parkedBuf`) vit dans BoatFront. N69 (`collapseRemainBuf`) vit dans GameState. N70 (`destroyBuf`) vit dans GameState (`removePlayer`). N89 (`settledRecPool`) vit dans GameState (`removePlayer`). N71 (`blockBuf` / `candBuf` / `queueBuf` / `visitMap` / `emptyTileBuf` / `placeScratch`) vit dans Placement (Shared, pas le ctx client). N72 (`allyBuf`) vit dans Bots. N73 (`stripBuf`) vit dans ChantierB (`install()` serveur seulement). N74 (`table.clear` border/coast) vit dans `ChantierB.stripTerritory` (hashes **par joueur**, pas un buf module). N76 (`tilesBeforeBuf` / `hitTilesBuf`) vit dans **Nukes** (`detonate` seulement). N77 (`mirvTxBuf` / `mirvTyBuf`) vit dans **Nukes** (`splitMirv` seulement). N78–N81 vivent dans **TickMetrics**. N82 + N87 vivent dans **IntentValidator**. N83 (`eventPool` / `soundPool`) vit dans **GameState**. N84 (`rosterBuf`) + N86 (`matchUpdateBuf`) + N88 (`recordBuf`) + N90 (`profileBuf`) vivent dans **MatchLifecycle**. N85 (`plunderPool`) vit dans **GameState**. N91 (`metaBuf`) vit dans **MapGen** (Shared). N92 (`deliveryPool`) vit dans **Trade**. N93 (`portRecPool`) + N94 (`factoryRecPool`) vivent dans **GameState** — pools **séparés**.

La PR #135 a bien fermé `metaBuf` (N91) et `deliveryPool` (N92). Cette passe a **corrigé ce que #135 a spécifié** — `indexPort` allouait encore `{ slot, level }` à chaque pose / upgrade / transfer PORT, et `indexFactory` allouait le même shape pour FACTORY :

| Bug | Gravité | Statut |
|---|---|---|
| `MapGen.mapMeta` 7 champs (N91) | **P3 alloc join** | **déjà fermé** (#135, `metaBuf`) |
| `Trade.dispatch` delivery (N92) | **P3 alloc commerce** | **déjà fermé** (#135, `deliveryPool[index]`) |
| `indexPort` `{ slot, level }` (N93) | **P3 alloc pose PORT** | **corrigé** (`portRecPool[index]`) |
| `indexFactory` `{ slot, level }` (N94) | **P3 alloc pose FACTORY** | **corrigé** (`factoryRecPool[index]`) |
| `placeBuilding` Building record (N95) | **P3 alloc pose** | **ouvert** (leftover N93/N94 ; `links` unique N65) |
| `Navy` bateau live (N96) | **P3 alloc marine** | **ouvert** (leftover N40/N51 ; `path` unique N64) |
| `stepDoomsday` scan O(TILE_COUNT) (N9 / N75) | **P2 cadran** | **ouvert** (index compact — leftover N73 ; contrat A trop structurel ici) |
| `retreatBoats` filtre `owner[targetTile]` courant | **P2 marine** | **ouvert** (reste de N28 ; feel d425/df65 a la recette) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29) |
| `findSpawn` ignore splash / fallout (N33) | **P3 nucléaire** | **ouvert** (feel d425/df65 a C1+C2 + `isSpawnSafe`) |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#135 + allyBuf (N72) + stripBuf (N73) + stripTerritory hashes (N74) + detonate hashes (N76) + splitMirv hashes (N77) + TickMetrics ring (N78) + snapshot arrays (N79) + reset pool (N80) + snapBuf (N81) + intentPool (N82) + notify/sound pool (N83) + rosterBuf (N84) + plunderPool (N85) + matchUpdateBuf (N86) + contextBuf (N87) + recordBuf (N88) + settledRecPool (N89) + profileBuf (N90) + metaBuf (N91) + deliveryPool (N92) + portRecPool (N93) + factoryRecPool (N94).
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #135

**À merger** (`metaBuf` + `deliveryPool` + specs N93–N94), sous réserve que cette passe 42 parte avec : **`indexPort` allouait encore `{ slot, level }`, et `indexFactory` allouait le même shape**.

Points encore vrais après #135 :

| Claim #135 | Réalité après passe 42 |
|---|---|
| N91 `MapGen.mapMeta` 7 champs | confirmé (`metaBuf`) |
| N92 `Trade.dispatch` delivery | confirmé (`deliveryPool[index]`) |
| N93 `indexPort` `{ slot, level }` | **fermé ici** (rawequal `portRecPool[index]`, destroy → `portsByTile` nil) |
| N94 `indexFactory` `{ slot, level }` | **fermé ici** (rawequal `factoryRecPool[index]`, destroy → `factoriesByTile` nil, pools **séparés**) |
| N75 `stepDoomsday` scan O(TILE_COUNT) | **ouvert** (ferme N9 si A ou C ; A trop structurel ici) |
| N33 `findSpawn` splash / fallout | **ouvert** |
| N28 retraite après flip / `targetSlot` | **ouvert** |
| N29 `seedBeachhead` no-merge | specs only, inchangé (banc N68 documente 3 Attack) |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |

`init.server.luau` et `Persistence` restent **exclus du bundle**. Le helper `MatchLifecycle` est **dans** le bundle (37 modules serveur — pas de module nouveau). `MapGen.mapMeta` est **dans** le bundle (Shared). `Trade.dispatch` est **dans** le bundle. `indexPort` / `indexFactory` sont **dans** le bundle (`GameState`). `snapshotBoats` / `snapshotMissiles` / `flushOwnerDelta` / `flushBuildingDelta` / `frontHudForReplicate` / `playerStatsForReplicate` sont **dans** le bundle (`GameState`). `pricesFor` / `contextFor` vivent dans **Buildings**. `progress` ne alloue plus `ratios` (N58). `Diplomacy.viewFor` recycle `viewBuf[slot]` (N59). `Diplomacy.step` recycle `expiredBuf` (N60). `neighborFactions` recycle `contactBuf` (N61). `gatherSites` recycle `siteBuf` (N62). `stepElimination` recycle `elimBuf` (N63). `findSeaPath` recycle `pathWalkBuf` (N64) — le tableau rendu au bateau **reste unique**. `refreshRailNetwork` recycle `stationBuf` (N65) — `building.links` **reste unique**. `Buildings.contextFor` recycle `ctxBuf` (N66) — pas le ctx client. `ChantierB` recycle `doomedBuf` / `collapsingBuf` (N67). `BoatFront.launchAttack` recycle `parkedBuf` (N68). `collapseFaction` recycle `collapseRemainBuf` / `collapseLeftBuf` (N69). `removePlayer` recycle `destroyBuf` (N70) et `settledRecPool` (N89). `Placement.validTiles` recycle blockers/candidates (N71). `decideDiplomacy` recycle `allyBuf` (N72). `stepDoomsday` recycle `stripBuf` (N73). `stripTerritory` `table.clear` in-place (N74). Scan cadran encore O(carte) (N9 / N75). `Nukes.detonate` recycle `tilesBeforeBuf` / `hitTilesBuf` (N76). `splitMirv` recycle `mirvTxBuf` / `mirvTyBuf` (N77). `TickMetrics.record` recycle `seenBuf` + ring Sample (N78). `snapshot` recycle 4 arrays (N79). `reset` conserve le pool Sample (N80, contrat B `historyCount`). `snapshot` recycle `snapBuf` (N81). `IntentValidator.flush` recycle `intentPool` (N82, contrat B). `notify` / `sound` recycle `eventPool` / `soundPool` (N83). `buildRoster` recycle `rosterBuf` (N84). `plunders` recycle `plunderPool` (N85). Packet `MatchUpdate` recycle `matchUpdateBuf` (N86). Context intents recycle `contextBuf` (N87). `endMatchRecords` recycle `recordBuf` (N88). Snapshot `settledHumans` recycle `settledRecPool` (N89). `profilePacket` recycle `profileBuf` (N90). `mapMeta` recycle `metaBuf` (N91). `Trade.dispatch` recycle `deliveryPool` (N92). `indexPort` recycle `portRecPool` (N93). `indexFactory` recycle `factoryRecPool` (N94). `placeBuilding` record encore alloué (N95). Bateau live encore alloué (N96).

PR #106 / #105 (feel / visual) ne doivent pas être mergées par-dessus #16/#135 sans rebase. Seq / `targetSlot` / hover `SpawnHint` / Overlay `retreating` / `TRAIN_STOP_BONUS` HUD / `previewCtx` restent feel-only. Visual 6b53 V55 = ligne visuelle, pas ici.

On peut fermer #17, #18, #20, #23, #25, #27, #30, #31, #33, #35, #37, #40, #43, #46, #49, #52, #55, #58, #60, #63, #66, #70, #73, #76, #80, #83, #85, #88, #91, #95, #98, #102, #104, #109, #112, #116, #119, #123, #127, #130 et #135 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| `indexPort` record (N93) | `GameState.luau`, `tests/simulate.luau` | Pool `portRecPool[index]` (recette `deliveryPool` N92). `indexPort(..., true)` réécrit `slot` / `level`. `indexPort(..., false)` → `portsByTile[index] = nil` ; le pool **survit**. `GameState.new` reset `portsByTile = {}` sans vider le pool. Ne require **pas** Navy. Recette spec #135 N93. Banc N40 pose / upgrade / destroy / vague / cap **verts**. **≠ feel historique.** |
| `indexFactory` record (N94) | `GameState.luau`, `tests/simulate.luau` | Pool `factoryRecPool[index]` (recette `portRecPool` N93, pool **séparé**). `indexFactory(..., true)` réécrit. Destroy → `factoriesByTile` nil, pool survit. Ne require **pas** Trade. Recette spec #135 N94. Banc N45 pose / upgrade / transfer / destroy / flatten **verts**. Banc N92 delivery pool **vert**. **Ne pas** pooler `factory.links` (N65). |

**Non modifié (volontaire) :** N1–N92 restant, reste de N28 (`targetSlot`). N10.8. Cap beachheads (N5 / N29). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` / `require(Placement)` / `require(MatchLifecycle)` / `require(IntentValidator)` depuis GameState. Pas de contrat C spawn (N33). Pas de seq obligatoire (feel N41). Pas de spatial hash warships. Buffer `defense` **alloué** mais plus écrit. Pas de `TRAIN_STOP_BONUS` dans `railIncome` (N18 / feel N20). Scan cadran encore O(carte) (N9 / N75) — contrat A (`tilesBySlot` dans `setOwner`) trop structurel : un index déréglé vs `owner` = pourriture du mauvais camp. `placeBuilding` record encore alloué (N95). Bateau live encore alloué (N96). Pas de `retreating` Overlay (feel N56 historique). Debit `captures`/`pops` **non** remplacé par feel `guard < 80`. `PlacementPreview` / `tests/client.luau` **non** édités. Skip AFK cadran **conservé**. Ogives MIRV **non** poolées (possession). `clearPlayer` reste `table.remove` (leftover cheap). Texte / kind / `only` / règle « humain impliqué » de `notifyBetween` **inchangés**. `betrayals` / doctrine lock **inchangés**. Payload Intent = référence live (N82 : **ne pas** pooler — possession RemoteEvent). Persistence `UpdateAsync` **non** poolé (N6). Closures `reply`/`refuse` **stables** (N87 ne les recrée pas). Sémantique N37 **inchangée** (humain snapshotte, bot ignore). `countByBiome` encore alloué (test-only, pas ticket). `structureHash` `indices = {}` reste N4 (client jamais `FireServer`). `portsBuf` flatten **inchangé** (déjà recyclé N40). `factoriesBuf` flatten **inchangé** (déjà recyclé N45). Pools PORT / FACTORY **non fusionnés**.

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
- **Posted FACTORY** = `factoriesByTile[index]` poolé (N45 flatten + N94 record). `Trade.step` flatten depuis l’index, pas `buildings`. Dispatch colis poolé (N92).
- **Tous kinds** = `buildingsBySlot[slot][tile]` (N46). Bots upgrade / score nuke + collecte gares (N47). Distinct des index par kind. Score nuke = flatten une fois (N50), puis 90 `scoreBlast`. Record Building encore alloué (N95).
- **Posted NAVAL_BASE** = `navalBasesBySlot[slot][tile]` (N48). `syncCarriers` spawn via l’index. Distinct de `portsByTile` (PORT) et de `buildingsBySlot` (tous kinds).
- **Cooldown bâtiments** = `coolingBuildings[index]` (N43). Unique écriture : `Buildings.armCooldown`. SAM **et** silos. `launch` continue d’appeler `armCooldown`.
- **Têtes de pont** = `BoatFront.seedBeachhead` : frontier = **voisins encore à la cible**, flag `isBeachhead`. `launchAttack` gare les beachheads dans `parkedBuf` avant fusion (N68).
- **Retraite** = couple `(attacker, target)` : tous les fronts + `Navy.retreatBoats`.
- **Pacte vivant** = `areAllied` : deux sens **et** `tick < expiry` (ou `true` legacy tests). Bots et tribus doivent passer par là, pas `alliances[]`.
- **Proposition vivante** = `requestIsLive` (`tick < expiry`). Croisement = accept **seulement** si encore live.
- **Comptabilité fronts** = `GameState.returnCommittedTroops` (pacte, défenseur disparu). Retraite terre = `RETREAT_LOSS`. Cote déjà nôtre = 100 %. **Transports inbound d’un disparu = 100 %**. **Missiles inbound = annulés, or du tireur conservé**. **Convois inbound = coulés, pas d’or**. **Convoi vs PORT détruit = coulé, pas d’or**.
- **Enclaves** = `ChantierB.tryAnnex` **après** `setOwner` : BFS depuis les voisins défenseur du seed. Océan = abort.
- **Porte-avions** = `syncCarriers` **événementiel** (`_carriersDirty`, NAVAL_BASE seulement) + spawn via `navalBasesBySlot` (N48). Ciblage obus = listes recyclées (N39), pas nested sur tout `state.boats`. Bateau live encore alloué (N96).
- **Commerce maritime** = `portsByTile` incrémental (PORT seulement, N40 flatten + N93 record). Vague plafonnée **avant** flatten. `canTrade` = embargo-only.
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients` (N26). Snapshot navires = `GameState.snapshotBoats` (`boatSnapBuf`, N51). Snapshot missiles = `GameState.snapshotMissiles` (`missileSnapBuf`, N52). Owner delta = `dirtyIndexBuf` (N53), buffer outbound **neuf**. BuildingDelta = `buildingSnapBuf` (N54), `links` live. HUD fronts = `frontHudForReplicate` (N55), appelé **une** fois depuis N57. `buildPrices` = `Buildings.pricesFor` (N56). Records stats = `playerStatsForReplicate` (N57). `Research.progress` min courant (N58). `Diplomacy.viewFor` recycle par slot (N59). `Diplomacy.step` recycle `expiredBuf` (N60). `neighborFactions` recycle `contactBuf` (N61). `gatherSites` recycle `siteBuf` (N62). `stepElimination` recycle `elimBuf` (N63). `findSeaPath` `pathWalkBuf` (N64, retour unique). `refreshRailNetwork` `stationBuf` (N65). `contextFor` `ctxBuf` (N66). Combat `doomedBuf`/`collapsingBuf` (N67). `parkedBuf` (N68). `collapseRemainBuf` (N69). Snapshot destroy `destroyBuf` (N70). `validTiles` blockers (N71). `allyBuf` (N72). `stripBuf` (N73). `stripTerritory` `table.clear` (N74). Scan cadran encore O(carte) (N9 / N75). `Nukes.detonate` `tilesBeforeBuf`/`hitTilesBuf` (N76). `splitMirv` `mirvTxBuf`/`mirvTyBuf` (N77). `TickMetrics.record` `seenBuf` + ring Sample (N78). `snapshot` 4 arrays (N79). `reset` pool Sample (N80). `snapBuf` (N81). `intentPool` (N82). Notify/sfx `eventPool`/`soundPool` (N83). Roster `rosterBuf` (N84). Plunders `plunderPool` (N85). Packet `MatchUpdate` `matchUpdateBuf` (N86). Context intents `contextBuf` (N87). Gravure `recordBuf` (N88). Snapshot `settledRecPool` (N89). Packet profil `profileBuf` (N90). Métadonnées carte `metaBuf` (N91). Colis `deliveryPool` (N92). Index PORT `portRecPool` (N93). Index FACTORY `factoryRecPool` (N94). Building record encore alloué (N95). Bateau live encore alloué (N96).
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
- **Index PORT** : `portRecPool[index]` dans GameState (N93). `spawnTradeShips` lit `info.slot` / `info.level`. Un leftover `slot` = convoi du mauvais camp.
- **Index FACTORY** : `factoryRecPool[index]` dans GameState (N94). Distinct de `portRecPool` et de `deliveryPool` (colis ≠ index).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N96 restent ouverts** sauf N19 partiel, N21 **fermé**, N24 remplacé par N31 (**fermé**), N30–N32 **fermés**, N34–N74 **fermés**, N76–N94 **fermés**. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + N75 + le reste de N28 / N29 / N33.

---

### ISSUE-N28 — `retreatBoats` / `retreatAttack` après flip de côte (reste)

**Priorité :** P2 combat / comptabilité navale. **Partiel :** inbound `removePlayer` **fermé** en passe 8.

**Problème restant :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetSlot`. Conséquences encore vraies :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers).
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

Feel d425 (N49) + df65 (N53) : `launchInvasion` pose `targetSlot`, `retreatBoats` filtre l’intention (fallback `owner[targetTile]`), wrap 2e geste rappelle les tardifs, `Navy.step` auto-retraite si `owner[targetTile] ~= targetSlot`. **Porter, ne pas réinventer.** Distinct de N10.8 et du fix inbound. Distinct de N35 (`destSlot` convoi ≠ `targetSlot` invasion). Distinct de N40 / N44–N96 (index / snapshots / HUD / `progress` / `viewFor` / `expired` / contacts / sites / elim / path / rail / ctx / doomed / parked / collapse / destroy / validTiles / allyBuf / stripBuf / strip hashes / detonate hashes / splitMirv / TickMetrics / notify / roster / plunders / MatchUpdate / intentContext / gravure / settled / profile / mapMeta / dispatch / portRec / factoryRec, **fermés** ou **specs**).

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite.

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste, trancher si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`. Recette feel : branche `d425` / `df65`.

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N22). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % déjà livré). Ne pas recâbler N35 (convois, `kind==2`). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).** Ne pas porter AimFront ni seq. Ne pas recâbler N50–N96.

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

**Contraintes :** ne pas annuler une frappe tiers (régression `nuke third-party`). Ne pas rembourser l’or. Pas de RemoteFunction. Rayon lu depuis `NUKE_STATS` / `missile.radius`, pas une constante magique. Ne pas porter isolation clic (feel N55) dans le même PR. Ne pas recâbler N50–N96. Ne pas mixer N76 (`tilesBeforeBuf` — leftover alloc, **déjà fermé**) ni N77 (`mirvTxBuf` — **déjà fermé**).

---

### ISSUE-N75 — `stepDoomsday` scanne encore `0..TILE_COUNT-1` par camp qui saigne

**Priorité :** P2 cadran / perf. Leftover explicite de N9 et de N73 (« ne pas remplacer le scan 40 960 — ticket suivant »). Distinct de N73 (`stripBuf` liste temporaire, **déjà fermé**) et de N74 (`stripTerritory` hashes spawn, **déjà fermé**). Ne pas toucher `rotQuota`. **N75 hardening ≠ N75 feel historique (`pricesFor`).** Visual V13 décrit le même trou. **Non livré en passe 42** : contrat A (`tilesBySlot` maintenu dans `setOwner`) est un index d’autorité — un déréglage vs `owner` pourrit le mauvais camp. Trop structurel pour un correctif « sûr » à côté de N93/N94.

**Problème :** même avec `stripBuf` recyclé, chaque slot sous quota (10 Hz, late-game plusieurs camps) re-scanne `Config.TILE_COUNT` (40 960) jusqu’à `quota * 4` hits. Un shard 18 factions en cadran = jusqu’à ~17 scans linéaires / tick. Il n’existe pas d’index compact tuiles-par-slot : `ps.tiles` est un compteur, `ps.border` / `ps.coast` ne couvrent pas l’intérieur. N73 a volontairement laissé ce scan.

**Pourquoi 20K CCU :** leftover N9. Late-game cadran = le tick le plus cher du shard (hors combat). Recycle de la porteuse (N73) n’enlève pas les 40k reads `buffer.readu8`. Un index compact (reservoir / linked list / dirty set) ramène le rot à O(tuiles du camp) au lieu de O(carte). Pas d’autorité si `setOwner` maintient l’index. Ne pas fusionner avec N74 : strip spawn parcourt encore la carte une fois au join, pas 10 Hz.

**Worker :**

1. Choisir un contrat : (A) `tilesBySlot[slot] = { number }` array compact, maintenu dans `setOwner` (insert au claim, swap-pop au loss) — `stepDoomsday` itère `1..ps.tiles` au lieu de `0..TILE_COUNT-1` ; (B) reservoir bitset 40 960 / 8 recyclé, rebuild seulement si dirty ; (C) documenter « scan O(carte) accepté, N9 fermé sans code ». **Un seul.** Feel / visual n’ont pas encore fermé V13. Pas de RemoteFunction.
2. Si A : `setOwner` est le **seul** writer. Capture, nuke crater, strip, collapse, spawn doivent tous passer par là. Test : 6000 ticks, `ps.tiles == #tilesBySlot[slot]`, rot n’émet plus de tuile `owner ~= slot`. Banc N73 / N74 **verts**.
3. Fichiers : `GameState.setOwner` + `ChantierB.stepDoomsday` (via `install()`), `tests/simulate.luau`. Pas de require GameState ↔ ChantierB nouveau.

**Contraintes :** pas de RemoteFunction. **N75 hardening ≠ N73 (`stripBuf`, déjà fait) ≠ N74 (`border`/`coast`, **déjà fait**) ≠ N76–N94 (déjà faits) ≠ N9 (umbrella — ce ticket **ferme** N9 si A ou C).** Ne pas changer `rotQuota` / drain / WARN. Ne pas scanner `buildings`. Overlay n’itère pas l’index. Un index déréglé vs `owner` = pourriture du mauvais camp (invariants `tiles` vs buffer le verront). Ne pas `require(ChantierB)` depuis GameState. Ne pas mixer avec N95 (`placeBuilding`) ni N96 (bateaux live).

---

### ISSUE-N93 — `GameState.indexPort` — **FERMÉ** (passe 42)

`portRecPool[index]` (recette `deliveryPool` N92). `indexPort` overwrite `slot` / `level`. Destroy → `portsByTile[index] = nil`, pool survit. Banc : rawequal pose / upgrade / transfer / 2e pose, destroy nil. Banc N40 vague / cap **verts**. Ne pas rouvrir. Un leftover `slot` = convoi fantôme (invariants PORT). Leftover Building record → N95. Leftover bateau live → N96. **Ne pas** fusionner avec `factoryRecPool` (N94).

---

### ISSUE-N94 — `GameState.indexFactory` — **FERMÉ** (passe 42)

`factoryRecPool[index]` (recette `portRecPool` N93, pool **séparé**). `indexFactory` overwrite. Destroy → `factoriesByTile` nil, pool survit. Banc : rawequal pose / upgrade / transfer / 2e pose, destroy nil. Banc N45 flatten / N92 delivery **verts**. Ne pas rouvrir. Un leftover `slot` = usine fantôme. Leftover Building record → N95. **Ne pas** pooler `factory.links` (N65). **Ne pas** fusionner avec `deliveryPool` (colis ≠ index).

---

### ISSUE-N95 — `GameState.placeBuilding` alloue `{ kind, slot, level, links, cooldown }` à chaque pose

**Priorité :** P3 alloc pose. Leftover explicite de N93/N94 (les **sidecars** index sont poolés ; le record Building lui-même alloue encore) et de N65 (`building.links` unique, **déjà fermé** — ne pas le pooler). Distinct de N54 (`buildingSnapBuf` snapshot, **fermé** — `links` live alias). Distinct de N70 (`destroyBuf` indices, **fermé**). **N95 hardening ≠ N95 feel historique (si un jour numéroté).** N93/N94 ont volontairement laissé le record Building hors ticket : c’est **ce** ticket.

**Problème :** `placeBuilding` fait encore `self.buildings[index] = { kind = kind, slot = slot, level = 1, links = {}, cooldown = 0 }` à chaque pose. Upgrade / transfer mutent le record **en place** (pas d’alloc). Destroy nil `buildings[index]` — le record n’est pas recyclé. Un clash 48 usines + 26 PORT + 100 villes observées = autant d’allocs abandonnées au destroy / `removePlayer`. `buildingSnapBuf` (N54) alias `links` live : pooler `links` casserait les snapshots déjà flushés.

**Pourquoi 20K CCU :** leftover naturel une fois les index PORT/FACTORY fermés. Recycle `buildingRecPool[index]` (recette `portRecPool` N93). Pas d’autorité si les 5 champs **inchangés**. Un leftover `slot` d’un Building recyclé = capture / or / rail du mauvais camp (invariants `buildingsBySlot` + banc N46 / N70). `links` **reste unique** (nouveau tableau à chaque pose, N65) — on gagne le record 5 champs, pas le tableau de liaisons. `table.clear` du record **interdit** (ce n’est pas un hash).

**Worker :**

1. Pool `buildingRecPool[index]` (un record par tuile bâtie). `placeBuilding` réécrit `kind` / `slot` / `level=1` / `cooldown=0` et **assigne `links = {}` neuf** (N65 unique — ne pas `table.clear` un ancien `links` : N54 alias live). `destroyBuilding` → `buildings[index] = nil` (pas un leftover vivant). Pool module survit à `GameState.new`. Pas de RemoteFunction. Rester dans `GameState.luau`. Ne pas partager avec `portRecPool` / `factoryRecPool` / `deliveryPool`.
2. Ne pas changer pose / upgrade / transfer / destroy / `countBuilding` / index par kind. Banc N40 / N45 / N46 / N70 / N93 / N94 **doivent rester verts**. 2e pose même tuile (destroy puis pose) → `rawequal` record, `kind`/`slot` à jour, `links` **distinct** (nouveau tableau).
3. Test : pose CITY → `rawequal(state.buildings[index], GameState.buildingRecPool[index])`. Destroy → `buildings[index] == nil`, pool survit. 2e pose (autre kind OK) → `rawequal` record, `kind` à jour, `not rawequal(links1, links2)`. Client **34/34**. 6000 ticks.
4. Fichiers : `GameState.luau` (`placeBuilding`, exposer `buildingRecPool` banc), `tests/simulate.luau` (bloc court après N94). `Navy.luau` / `Trade.luau` / `init.server` / `PlacementPreview` / `tests/client.luau` inchangés. Pas de recette feel.

**Contraintes :** pas de RemoteFunction. **N95 hardening ≠ N54 (snapshot, déjà fait) ≠ N65 (`links` unique, déjà fait) ≠ N70 (indices destroy, déjà fait) ≠ N93/N94 (sidecars, déjà faits).** Overlay n’écrit pas `buildings`. Un leftover `slot` = bâtiment fantôme (invariants kind + banc N46). Ne pas mixer N75 / N96. Ne pas pooler `building.links` (N65). Ne pas changer `buildingSnapBuf` (N54, `links` live).

---

### ISSUE-N96 — `Navy` alloue un record bateau à chaque spawn (transport / convoi / carrier)

**Priorité :** P3 alloc marine. Leftover explicite de N40 (`portsBuf` flatten recyclé, `spawnTradeShips` `table.insert` encore un record) et de N51 (`boatSnapBuf` snapshot poolé ; le **bateau live** alloue encore). Distinct de N51 (`boatSnapBuf`, **fermé**, pas de `path` / `retreating`). Distinct de N64 (`boat.path` unique, **déjà fermé** — ne pas `return pathWalkBuf`). Distinct de N93 (`portRecPool` index, **fermé**). **N96 hardening ≠ N96 feel historique (`retreating` Overlay — feel N56, ne pas porter).** N40 a volontairement laissé le record bateau hors ticket : c’est **ce** ticket.

**Problème :** `launchInvasion` / `spawnTradeShips` / `syncCarriers` font `table.insert(state.boats, { id, slot, kind, troops, x, y, path, step, targetTile, homeTile, ... })`. Un clash 36 navires observés (24 carriers + convois) × vague 45 s + invasions = allocs abandonnées au `table.remove` (atterrissage, intercept, `removePlayer`). `path` est possession unique (N64) : un second `findSeaPath` ne doit pas aliaser. `boatSnapBuf` copie `id/slot/x/y/troops` — pas le record live.

**Pourquoi 20K CCU :** leftover naturel une fois flatten PORT + snapshot bateaux fermés. Recycle `boatRecPool` (free-list, recette `eventPool` N83 **ou** truncate d’un tableau parallèle — **un seul** contrat). Pas d’autorité si les champs **inchangés**. Un leftover `slot` / `kind` d’un bateau recyclé = or au mauvais camp / tête de pont fantôme (banc inbound N8 / vague N40 / carriers N48). `path` **reste unique**. `table.clear` du record **interdit**.

**Worker :**

1. Choisir un contrat : (A) free-list module `boatFree` — spawn pop/crée, `table.remove` push ; (B) `boatRecPool[n]` parallèle à `state.boats` (truncate comme `eventPool`, indices glissent avec `table.remove` — plus fragile). **Un seul.** Recette (A) recommandée. `path = path` unique (N64) à chaque spawn — ne pas réutiliser l’ancien tableau. Pool module survit à `GameState.new`. Pas de RemoteFunction. Rester dans `Navy.luau` — ne pas `require` depuis GameState (cycle). Couvrir **les 3 kinds** (transport / trade / carrier) pour ne pas laisser un insert vivant.
2. Ne pas changer la loi de tirage `spawnTradeShips`, `findSeaPath`, inbound `removePlayer`, N10.8, N35. Banc N40 vague / cap / empty **verts**. Banc N48 carriers **vert**. Banc inbound transports / convois **verts**. Snapshot N51 **vert** (pas de `path` dans le snap).
3. Test : spawn convoi → couler (`table.remove`) → 2e spawn → `rawequal` record (si A : même objet free-list), champs `slot`/`kind`/`targetTile` à jour, `not rawequal(path1, path2)`. Transport `launchInvasion` recycle aussi. Client **34/34**. 6000 ticks.
4. Fichiers : `Navy.luau` (spawn + remove, exposer `Navy.boatRecPool` ou `Navy.boatFree` banc), `tests/simulate.luau` (étendre le banc N40 ou bloc court). `GameState.luau` / `init.server` inchangés. Pas de recette feel. **Ne pas** porter `retreating` Overlay.

**Contraintes :** pas de RemoteFunction. **N96 hardening ≠ N40 (flatten, déjà fait) ≠ N51 (snapshot, déjà fait) ≠ N64 (`path` unique, déjà fait) ≠ N93 (index PORT, déjà fait).** Overlay lit le snapshot N51, pas le record live. Un leftover `kind==1` = tête de pont fantôme (banc inbound). Ne pas mixer N28 (`targetSlot`) ni N75 ni N95. Ne pas pooler `boat.path` (N64). Ne pas changer `portsBuf` (déjà recyclé). Ne pas ajouter `retreating` (feel N56).

---

## 5b. N1–N96 encore ouverts ou fermés (passes 2–42)

| ID | Titre | Prio | Note passe 42 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + `SAM_INTERCEPT_CHANCE` 0.55→1 ; clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz ; bateaux snap → **N51 fermé** ; … ; mapMeta → **N91 fermé** ; Trade.dispatch → **N92 fermé** ; portsByTile record → **N93 fermé** ; factoriesByTile record → **N94 fermé** ; reste skip-si-inchangé ; Building record → **N95** ; bateau live → **N96** |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` **jamais** `FireServer` côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | park `isBeachhead` → hors cap land ; **2 beachheads parked + 1 terre = 3** — voir N29 ; alloc parked → **N68 fermé** |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions. **Ne pas** pooler (N90 le rappelle). |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | refund + retraite `RETREAT_LOSS` alignés ; wrap vivant → **N67 fermé** ; `collapseFaction` remaining → **N69 fermé** |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | timers slot maintenant purgés ; liste temporaire → **N73 fermé** ; hashes spawn → **N74 fermé** ; le scan rot est toujours O(tuiles) → **N75** |
| N10 | Divers P3 | P3 | donations gold sans plafond ; `pendingMode` last-writer ; README SmoothTerrain ; … ; portsByTile record → **N93 fermé** ; factoriesByTile record → **N94 fermé** ; Building record → **N95** ; bateau live → **N96** |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | debit = `attackTilesPerTick` × speed, **captures<80 pops<160** |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 observé) | P1 | `Bots.spawnAll` wrap + `Tribes.spawnAll(6)` hors budget |
| N13–N27 | (ère / heap / embargo / rail HUD / QuickChat / warships / …) | — | inchangés vs passe 41 ; voir rapport #135 |
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
| N93 | `indexPort` `{ slot, level }` | P3 | **fermé**. Leftover N40. Recette `deliveryPool`. |
| N94 | `indexFactory` `{ slot, level }` | P3 | **fermé**. Leftover N45/N92. Pool **séparé** de N93. |
| N95 | `placeBuilding` Building record | P3 | specs only. Leftover N93/N94. `links` unique (N65). |
| N96 | bateau live `Navy` | P3 | specs only. Leftover N40/N51. `path` unique (N64). |

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
  … gardes #17–#135 inchangés …
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
  port pool : rawequal index, destroy nil (N93)
  factory pool : rawequal index, destroy nil (N94)
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 captures=80 pops=160
  factions : 18
  metrics : ticks=6000 avgChanged=8.9 p95Changed=19 maxChanged=479 avgTickMs=0.37 p95TickMs=0.84
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe42.log`

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
- Index PORT : `indexPort` recycle `portRecPool[index]` (N93). Destroy → `portsByTile` nil. Ne pas `require` Navy. **Ne pas** fusionner avec `factoryRecPool`.
- Index FACTORY : `indexFactory` recycle `factoryRecPool[index]` (N94). Destroy → `factoriesByTile` nil. Ne pas `require` Trade. Pools **séparés** de N93.
- File d’intents : `IntentValidator.enqueue` réécrit `intentPool[n]` (N82). `flush` nil `queue[1..n]`. Schema / sequence / rate inchangés. **Payload = référence live — ne pas pooler** (N87/N90 ne touchent pas le payload).
- Metrics : `seenBuf` + ring Sample (N78). `snapshot` 4 arrays (N79). `reset` pool (N80). `snapBuf` (N81).
- `init.server` / `Persistence` restent hors bundle : extraire un helper testable (`MatchLifecycle.buildRoster` / `buildMatchUpdate` / `endMatchRecords` / `buildProfilePacket` déjà là ; `fillContext` dans IntentValidator pour N87 ; `mapMeta` dans MapGen pour N91) ou documenter un test Studio.
- Ne pas casser le client 34/34.
- Ligne feel : rebase sur cette passe avant cherry-pick, sinon perte `portRecPool` / `factoryRecPool`. Cherry-pick seq obligatoire (N41 feel) et `targetSlot` (N49 feel) seulement. **Ne pas** porter `retreating` Overlay (feel N56). **Ne pas** porter `TRAIN_STOP_BONUS` HUD (feel N20). **Ne pas** porter feel `guard < 80`. Client feel = 35/35 ; client hardening = **34/34**.
