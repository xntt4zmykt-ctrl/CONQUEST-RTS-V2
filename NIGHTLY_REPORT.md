# Nightly report — passe 28 (revue PR #79)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-027d` (PR #79, `5b3681f`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-d685`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #79 (`Diplomacy.step` expiredBuf / `neighborFactions` recycle — HEAD visuel). Correctifs sûrs, sans merger feel `b62d`/`2f5d` ni hardening `ded3`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `Bots.gatherSites` pool `siteBuf` | `Bots.luau` | V36 N81 |
| `GameState.stepElimination` pool `elimBuf` | `GameState.luau` | V37 N82 |

`expiredBuf` / `contactBuf` / type-guard visuel (`true`/non-number) **conservés**. Skip `awaitingSpawn` et `settledHumans` **conservés**. `removePlayer` snapshot bâtiments (`local doomed`) **non retouché**. `findSeaPath` path+reversed **non poolé**. `refreshRailNetwork` stations **non poolées**. Schéma filaire client **inchangé**. GameState ne require toujours pas Buildings / Research.

---

## Constatations PR #79 (à ne pas casser)

- **Autorité :** le client n’évalue aucune règle de combat/économie. Ordres = remotes + sequence.
- **Vérité runtime :** `SystemsBootstrap.install()` → `ChantierB.apply(Config)`. Ne pas tuner `Config.luau` seul.
- **Combat vivant :** `ChantierB.stepAttacks`. Guard = `ChantierB.CAPTURE_GUARD` (80), **pas** `Config.MAX_TILES_PER_TICK` (56 après apply, 400 brut).
- **Posted DEFENSE :** `bunkersBySlot` + `attackLogic`. Buffer `defense` mort. Plus d’écritures `applyDefenseAura`.
- **Posted SAM :** `samsBySlot` + `tryIntercept` / `samsOf`. Slot sans SAM ne rescane plus le hash. `samsOf` recycle un buffer — **pas réentrant**.
- **Posted SILO :** `silosBySlot` + `Nukes.launch`. Fantôme hors index ignoré.
- **Cooldown 10 Hz :** `coolingBuildings` + `armCooldown` (SAM **et** silos). SAM-only gèlerait `SILO_COOLDOWN`.
- **Posted tous kinds :** `buildingsBySlot`. Bots upgrade / score nuke / rail collect via l’index.
- **Posted FACTORY :** `factoriesBySlot` (sous-ensemble, 10 Hz Trade). Ne pas itérer `buildingsBySlot` pour les colis.
- **Posted PORT :** `portsByTile` `{slot, level}`. Distinct de `_carriersDirty` (NAVAL_BASE). Vague = `TRADE_SHIP_INTERVAL` 45, pas 10 Hz. **Loi manhattan visuelle inchangée.**
- **Posted NAVAL_BASE :** `navalBasesBySlot`. Spawn seulement si `_carriersDirty`. Un PORT n’est jamais un carrier.
- **Warships targeting :** `carrierBuf`/`targetBuf` (V24). Early-out 0 carrier / 0 bateau d’un autre slot. Pas de spatial hash.
- **Score nuke bots :** `fillBlastBuf` une fois par visée (V27). Index présent + set nil = 0, pas de fallback hash.
- **UnitSnapshot 10 Hz :** `snapshotBoats` / `snapshotMissiles` (V26). Table vide recyclee (pas `nil`) pour retirer le dernier fantôme client. Pas de `path` / `homeTile` / `retreating` / `progress` / `sx`.
- **BuildingDelta 10 Hz :** `buildingSnapBuf` (V28). Early-out dirty vide → `nil`. Destruction `kind=0`. `links` = table live (Overlay lit tout de suite).
- **HUD fronts 10 Hz :** `frontHudForReplicate` (V29), appelé **une fois** depuis `playerStatsForReplicate`. Terre et `isBeachhead` = tas séparés. Slot sans front absent (nil, pas `{}`).
- **Prix HUD 10 Hz :** `Buildings.pricesFor` (V30). Slot inconnu = map vide, **pas** `math.huge` (réservé à `priceFor` unitaire). Pas dans GameState — cycle `require`.
- **Stats HUD 10 Hz :** `playerStatsForReplicate` (V31). `eraProgress` / `buildPrices` posés dans `init.server`. Record recyclé par slot ; slot parti absent de la porteuse.
- **Ère HUD 10 Hz :** `Research.progress` (V32). Min scalaire or / tuiles / bâtiments, **pas** de table `ratios`. Slot inconnu / `MAX_ID` = 1. Schéma `eraProgress` number 0..1 inchangé.
- **Diplomatie 1 Hz :** `viewFor` (V33). **Un record par slot** (`viewBuf[slot]`), pas un buf global (la boucle `FireClient` séquentielle viderait le client précédent). Slot disparu → maps vides, pas de scan. `requestIsLive` visuel conservé.
- **Diplomatie 10 Hz :** `Diplomacy.step` (V34). `expiredBuf` + `expiredRecPool`. Collecter `n`, poser `rec.a`/`rec.b`, itérer `1..n`. **`true` legacy continue** ; non-number (ex. `"oops"`) expire. Feel N79 ne copie pas ce type-guard.
- **Bots perception :** `Bots.neighborFactions` (V35). `contactBuf` unique, `table.clear`. Slot inconnu → map vide. **Pas réentrant.**
- **Bots pose :** `Bots.gatherSites` (V36). `siteBuf` (`table.create(60)`). Caps 40/60/45. Pas de shuffle. Truncate leftover. Slot / côte vide → `# == 0`. **Pas réentrant.** Unique appelant `decideBuild`.
- **Élimination 10 Hz :** `stepElimination` (V37). `elimBuf` (`table.create(8)`). **Pas** nommé `doomed`. Skip `awaitingSpawn`. Truncate leftover **avant** `removePlayer`. Ne pas truncate à 0 après return. Buffer **partagé inter-instances**. `settledHumans` inchangé.
- **Spawn clic :** terre libre + `isSpawnIsolated`. Snap `r=6` seulement si la tuile cliquée est **occupée**.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `GameState` ne require pas `Buildings` / `Research` / `Types`.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–18) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.

---

## Specs worker (reste)

Ne pas merger feel `b62d`/`2f5d` ni hardening `ded3` sur cette branche sans rebase. Porter **une** recette à la fois.

### ISSUE-V1 — Packing spawn 18 factions

**Problème.** `SPAWN_RADIUS=18` + `SPAWN_MIN_PLAYER_DISTANCE=30` : les seeds 7 / 99991 / 1234567 / 424242 placent 11–15 factions sur 18. Les tribus sautent. `spawnCenter` et `isSpawnIsolated` sont vivants mais le disque 21² reste trop large : occupancy ≫ minDist.

**20K CCU.** Un salon Classique sous-peuplé fausse l’éco, les bots et le climax nucléaire.

**Faire.** Recherche spirale / rejet plus souple pour `isTribe` (dist min 20) **ou** `TRIBE_SPAWN_RADIUS` plus petit. Ne pas réduire le disque humain. Ne pas re-poser `isSpawnIsolated` / `spawnCenter`.

**Contraintes.** Server-only. `addPlayer` rollback si `findSpawn` nil. `stripTerritory` doit continuer d’effacer `spawnCenter`.

**Tester.** `EXTRA_SEEDS` + seed 424242 : `spawned == BOT_COUNT + TRIBE_COUNT`. `./tests/run.sh`.

### ISSUE-V7 — `findSpawn` / `claimSpawn` anti-splash

**Problème.** Spawn ignore cratère ogive / fallout chaud. Un humain peut (re)naître dans le splash. Isolation clic (V16b) ne couvre **pas** le fallout.

**Faire.** Recette feel N50/N52 : `isSpawnSafe` partagé `findSpawn` + `claimSpawn` (C1+C2), **en plus** de `isSpawnIsolated`. Contrat B missiles inbound **inchangé**.

**Tester.** MIRV existant + capitale sous fallout → refus / autre tuile. Isolation clic (passe 19) reste verte.

### ISSUE-V9b — Persistence debounce 30 s

**Problème.** `Persistence.record()` marque dirty **puis** appelle `save()` tout de suite (`UpdateAsync` / humain). Le double-write `release`/`BindToClose` est corrigé ; la tempête de fin de match (8 writes synchrones) reste.

**20K CCU.** N salons × 8 humains × `endMatch` = burst DataStore.

**Faire.** `record()` marque dirty **sans** `save`. Flush 30 s + `endMatch` + `release` + `BindToClose`. Une écriture / userId / match.

**Contraintes.** Ne pas perdre l’XP d’un éliminé si le salon crash avant flush : flush immédiat sur `settledHumans` **ou** accepter ≤1 write / éliminé. Hors bundle (`Persistence`).

**Tester.** Studio : 8 humains `endMatch` = ≤8 writes, disconnect après `record` = 0 write supplémentaire.

### ISSUE-V13 — Rot doomsday O(carte)

**Problème.** `ChantierB.stepDoomsday` parcourt `TILE_COUNT` par joueur marqué pour arracher `quota` tuiles.

**20K CCU.** 10 Hz × 40 960 lectures buffer quand le cadran tourne = pic en fin de partie.

**Faire.** Liste incrémentale des tuiles par slot (même structure que `border`) **ou** reservoir sampling sur un index compact. Ne pas changer la formule `Doomsday.rotQuota`.

**Tester.** Cadran existant + 1 humain sous quota. Invariants `tiles` vs buffer.

### ISSUE-V14b — En-tête de compteur pour `flushOwnerDelta`

**Problème.** Passe 17 recycle `deltaIndices` mais `buffer.create(count * 5)` reste obligatoire : un tampon trop grand serait lu comme des tuiles fantômes (slot 0). Feel N72 a `dirtyIndexBuf` (liste d’indices, pas l’en-tête filaire).

**20K CCU.** 10 Hz playing × alloc buffer = pression GC sur 8 clients.

**Faire.** Préfixer le payload `[u32 count][u32 index][u8 slot]…` **ou** RemoteEvent séparé pour la longueur. Adapter le client (`WorldRenderer` / init.client). Growth-only ensuite. Ne pas porter feel N72 seul : ça ne ferme pas l’alloc `buffer.create`.

**Contraintes.** Changer client **et** serveur dans le même commit. Ne pas casser `RequestSnapshot` (carte entière, autre remote).

**Tester.** Match 6000 ticks, P0 metrics. Client 34/34.

### ISSUE-V38 — `Navy.findSeaPath` `pathWalkBuf`

**Problème.** Un trajet réussi construit `local path = { toTile }` puis `table.insert` en remontant `parent`, puis `local reversed = table.create(#path)` et un second remplissage. Deux allocations par invasion, retraite, et convoi commercial. Les trois call sites **prennent possession** du retour : `boat.path = path`. Un `pathBuf` partagé aliaserait le trajet du bateau A quand B cherche une route. Feel N83 recycle le walk seulement. Distinct de V16 (`visitBuf` / `parentPool` / `queuePool` déjà poolés) et de V21 (`portsBuf` / `candidateBuf`).

**20K CCU.** Le BFS visité est déjà payé (V16). Il reste le double alloc du résultat, sur chaque vague `TRADE_SHIP_INTERVAL` (45) et chaque débarquement. Recycle du **walk** seulement ; le tableau rendu au bateau **doit rester unique**. Pas d’autorité (la géométrie ne change pas).

**Faire.** Recette feel N83 (`b62d`) : `pathWalkBuf` module-level (`table.create(256)`). Au hit `nb == toTile` : n = 0 ; poser `toTile` puis remonter `current` jusqu’à `fromTile` **exclu** (loi actuelle : l’origine terrestre n’est pas dans le path). `pathWalkBuf[n] = node`. Truncate leftover n+1..#. Allouer **un** `out = table.create(n)` et copier **à l’envers** (`out[i] = pathWalkBuf[n - i + 1]`). `return out`. Ne **pas** `return pathWalkBuf`. Pas de second tableau `reversed`. Après V37. Ne pas porter `refreshRailNetwork` (V39) en même temps.

**Contraintes.** Server-only. Ne pas modifier `launchInvasion` / retraite / `spawnTradeShips` (ils stockent déjà le retour). Ne pas require de module nouveau. Ne pas toucher `visitBuf` / `parentPool` / `queuePool`. `buffer.fill(visitBuf, 0, 0)` inchangé. Échec BFS / `MAX_BFS_NODES` → `nil`. Ne pas `table.clone` du walk. Overlay n’itère pas `boat.path` (non répliqué). **Pas réentrant.** `findSeaPath` est synchrone et unique.

**Tester.** Banc V16 existant (deux appels, mêmes longueurs) **doit rester vert**. Ajouter : deux appels successifs même paire → **pas** `rawequal` (identité unique). Stocker `p1`, rappeler, `p1[i]` inchangé (pas de mutation du path du premier bateau). Trajet inverse ne pollue pas. `./tests/run.sh`. Client 34/34.

**Fichiers.** `Navy.luau` (`findSeaPath` seulement), `tests/simulate.luau` (bloc court à côté du banc V16 seed 1608).

### ISSUE-V39 — `GameState.refreshRailNetwork` `stationBuf`

**Problème.** Chaque `placeBuilding` / `destroyBuilding` / `transferBuilding` d’une gare reconstruit `local stations = {}`, `parent = table.create(count)`, `xs`/`ys`, `neighborsOf` (une table interne **par** gare) et deux maps de grappe. Pas 10 Hz, mais une partie Classique pose/capture des dizaines de gares. `building.links = links` **prend possession** de `neighborsOf[i]` : un pool partagé des inners aliaserait les voies de deux usines (et le dirty BuildingDelta). Feel N84 recycle les **porteuses**. Distinct de V22 (`buildingsBySlot[slot]` déjà) et de V28 (`buildingSnapBuf` live `links`).

**20K CCU.** Leftover V22. Recycle des porteuses (stations, parent, xs, ys, maps de grappe) élimine l’alloc courte. Les inners `neighborsOf` stockées dans `building.links` restent uniques — même classe que V38 (`boat.path`). Pas d’autorité (tri + union-find inchangés ; sans tri les liens répliqués danseraient).

**Faire.** Recette feel N84 (`b62d`) : `stationBuf` module-level (`table.create(32)`), plus `railParentBuf` / `railXsBuf` / `railYsBuf` (`table.create(32)`), plus `clusterStations` / `clusterFactoryCount` maps recyclées (`table.clear`). Au début : n = 0. Même collecte V22 (`buildingsBySlot[slot]`, fallback hash, kinds CITY/CAPITAL/PORT/FACTORY, **pas** DEFENSE). `stationBuf[n] = index`. **Truncate leftover puis `table.sort(stationBuf)`** — `table.sort` sur un leftover non truncaté mélangerait d’anciennes gares. `count = n`. Remplir parent/xs/ys dans les buf (itérer `1..count`, pas `#`). Maps de grappe : `table.clear` puis refill. Après V38. Ne pas toucher `elimBuf` / `siteBuf`.

**Contraintes.** Server-only. **Ne pas** recycler les inners `neighborsOf[i]` dans un pool partagé. Allouer `{}` par gare comme aujourd’hui (elles deviennent `building.links` si usine + changed). Option B (écrire dans `building.links` existant) **interdite** : Overlay / BuildingDelta comparent l’identité via le dirty, et un `table.clear` in-place pendant qu’un snapshot V28 tient `links` live casserait le wire. Ne pas require de module nouveau. Ne **pas** référencer `IS_STATION` (local trop bas, nil au runtime — piège V22). Ne pas `table.clone(links)` au dirty. **Pas réentrant.** `refreshRailNetwork` est unique par mutation.

**Tester.** 1 FACTORY + 1 CITY à portée → `factory.links` contient la ville, `railIncome > 0`. Deuxième `refreshRailNetwork` → mêmes liens, `not rawequal(factory.links, stationBuf)`. Slot sans gare (hors capitale) : poser uniquement un bunker → `railRoutes` inchangé / pas d’erreur. Capitale spawn est une gare : un test « 1 FACTORY seule » peut encore lier `owner.capitalTile`. `./tests/run.sh`. Client 34/34.

**Fichiers.** `GameState.luau` (`refreshRailNetwork` seulement), `tests/simulate.luau` (bloc court).

---

## Hors scope volontaire

- Merger feel `b62d`/`2f5d` / hardening `ded3` sur #39/#79.
- Spatial hash warships / `bunkerCells` (hardening N41) — `bunkersBySlot` + `carrierBuf` suffisent.
- Pairing convois simplifié hardening N40 (poids = level only) — la loi visuelle manhattan/alliance/`longCap` reste.
- `MODE_KEYS` mort (digits 1–4 = bâtiments). Cosmétique.
- Fallout disque = rayon **inner** seulement (OF outer = spec produit).
- Brancher les clés Config mortes (`ATTACK_SPEND_RATE`, `FRONT_TILES_PER_CONTACT`, `BOAT_LANDING_BONUS`).
- `combatUnlocked` forcé à `true` chaque tick playing (`init.server`) : prep=0, pas un leak client.
- Hover client `SpawnHint` (feel N58) — isolation serveur d’abord (V16b livré).
- `samsOf` / `fillBlastBuf` / `snapshotBoats` / `buildingSnapBuf` / `frontHudForReplicate` / `pricesFor` / `playerStatsForReplicate` / `viewFor` / `expiredBuf` / `contactBuf` / `siteBuf` / `elimBuf` réentrants : un seul appelant chacun (sauf `viewFor` **par slot** — c’est voulu). Dupliquer le buffer si un second appelant apparaît. `playerStatsForReplicate` appelle `frontHudForReplicate` — ne pas rappeler le HUD dans `replicate()`.
- Feel N70 `retreating` sur le snapshot — Overlay visuel ne teinte pas la retraite.
- `delivery.level` snapshot à l’arrivée (feel) : le header Trade dit « niveau à l’arrivée » ; dispatch stocke déjà `level` mais `resolve` lit `factory.level`. Produit, pas un bug d’index.
- Feel N83 (`findSeaPath` path unique) / N84 (`stationBuf`) — V38 / V39.
- `dirtyIndexBuf` (feel N72 / hardening N53) — ne ferme pas l’alloc `buffer.create` (voir V14b).

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–27 + **passe 28** (`gatherSites` DEFENSE frontière + `rawequal` + cap 60, truncate border `# == 0`, PORT sans côte `# == 0` ; `elimBuf` vivant length 0 + `rawequal`, strip → length 1 slot disparu, leftover inter-instances 1→0).  
Invariants 5b–5f : index `buildingsBySlot` / `coolingBuildings` / `factoriesBySlot` / `portsByTile` / `navalBasesBySlot` vs hash, chaque 500 ticks.  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
