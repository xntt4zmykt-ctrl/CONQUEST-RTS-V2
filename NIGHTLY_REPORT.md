# Nightly report — passe 31 (revue PR #87)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-c695` (PR #87, `0b77282`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-d3e2`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #87 (`Buildings.contextFor` ctxBuf / `ChantierB` doomedBuf+collapsingBuf — HEAD visuel). Correctifs sûrs, sans merger feel `07c6`/`69f4` ni hardening `5edc`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `Bots.decideDiplomacy` recycle `allyBuf` | `Bots.luau` | V42 |
| `ChantierB.stepDoomsday` recycle `stripBuf` | `ChantierB.luau` | V43 |

`ctxBuf` / `doomedBuf` / `collapsingBuf` **conservés**. `contactBuf` / `siteBuf` / `elimBuf` **non touchés**. Seuils `acceptChance` 0.75/0.35, `COALITION_ALLY_CHANCE`, `COALITION_EMBARGO_CHANCE` **inchangés**. `Doomsday.rotQuota` / `drain` / `troopFloor` **inchangés**. `CAPTURE_GUARD=80` visuel **inchangé**. `stripTerritory` visuel (`awaitingSpawn = true`) **inchangé**. Schéma filaire client **inchangé**. GameState ne require toujours pas Buildings / Research.

---

## Constatations PR #87 (à ne pas casser)

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
- **Path maritime :** `Navy.findSeaPath` (V38). `pathWalkBuf` walk scratch. Copie inverse dans un tableau **neuf**. `return out`, jamais `return pathWalkBuf`. Origine terrestre **exclue**. `visitBuf` / `parentPool` / `queuePool` inchangés. **Pas réentrant.** Unique appelant synchrone (invasion / retraite / convoi).
- **Réseau ferroviaire :** `refreshRailNetwork` (V39). `stationBuf` + `railParentBuf` / `railXsBuf` / `railYsBuf` + maps de grappe. Truncate leftover **puis** `table.sort`. Itérer `1..count`, pas `#`. Inners `neighborsOf` uniques. Formule HUD visuelle **sans** `TRAIN_STOP_BONUS`. **Pas réentrant.**
- **Placement serveur :** `Buildings.contextFor` (V40). `ctxBuf` + `ownerAt`/`buildingAt` module. Deux appels → `rawequal`. Slot inconnu → `nil` sans muter. **Pas réentrant** : un `ownerAt` conservé lit le `ctxState` vivant. `resolve` synchrone unique. Ne pas `table.clone`.
- **Clash / collapse 10 Hz :** `doomedBuf` hash + `collapsingBuf` pool (V41). `table.clear(doomedBuf)` en tête de `cancelOpposingFronts`. Ne **pas** itérer `#doomedBuf`. Truncate leftover collapsing **avant** `collapseFaction`. `ChantierB.doomedBuf` exposé pour le banc (`next` après clear). **Pas réentrant.** Distinct de `elimBuf` (redistribution, pas `removePlayer`).
- **Bots diplomatie :** `decideDiplomacy` recycle `allyBuf` (V42). Hash, `table.clear`, pas de truncate. Distinct de `contactBuf` (voisins de tuiles). **Pas réentrant.** `Bots.step` séquentiel — un second `clear` au bot suivant est voulu. `Bots.allyBuf` exposé banc (pas de filaire). Seuils accept/coalition **inchangés**.
- **Rot cadran :** `stepDoomsday` recycle `stripBuf` (V43). Array + truncate leftover **avant** arrachage. Reset `n=0` / truncate à 0 **après** (un leftover ferait `setOwner(NEUTRAL)` sur le camp précédent). Itérer `1..n`, pas `#`. Distinct de V13 (scan O(carte) encore). Formule `Doomsday.rotQuota` **inchangée**. **Pas réentrant.**
- **Spawn clic :** terre libre + `isSpawnIsolated`. Snap `r=6` seulement si la tuile cliquée est **occupée**.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `GameState` ne require pas `Buildings` / `Research` / `Types`.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–18) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.

---

## Specs worker (reste)

Ne pas merger feel `07c6`/`69f4` ni hardening `5edc` sur cette branche sans rebase. Porter **une** recette à la fois.

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

**Problème.** `ChantierB.stepDoomsday` parcourt `TILE_COUNT` par joueur marqué pour arracher `quota` tuiles. V43 recycle seulement la **liste temporaire** (`stripBuf`) : le scan 40 960 reste.

**20K CCU.** 10 Hz × 40 960 lectures buffer quand le cadran tourne = pic en fin de partie.

**Faire.** Liste incrémentale des tuiles par slot (même structure que `border`) **ou** reservoir sampling sur un index compact. Ne pas changer la formule `Doomsday.rotQuota`. Ne pas retoucher `stripBuf` (V43 déjà).

**Tester.** Cadran existant + 1 humain sous quota. Invariants `tiles` vs buffer. Banc V43 (deux camps, chacun perd le sien) **doit rester vert**.

### ISSUE-V14b — En-tête de compteur pour `flushOwnerDelta`

**Problème.** Passe 17 recycle `deltaIndices` mais `buffer.create(count * 5)` reste obligatoire : un tampon trop grand serait lu comme des tuiles fantômes (slot 0). Feel N72 a `dirtyIndexBuf` (liste d’indices, pas l’en-tête filaire).

**20K CCU.** 10 Hz playing × alloc buffer = pression GC sur 8 clients.

**Faire.** Préfixer le payload `[u32 count][u32 index][u8 slot]…` **ou** RemoteEvent séparé pour la longueur. Adapter le client (`WorldRenderer` / init.client). Growth-only ensuite. Ne pas porter feel N72 seul : ça ne ferme pas l’alloc `buffer.create`.

**Contraintes.** Changer client **et** serveur dans le même commit. Ne pas casser `RequestSnapshot` (carte entière, autre remote).

**Tester.** Match 6000 ticks, P0 metrics. Client 34/34.

### ISSUE-V44 — `BoatFront.launchAttack` alloue `parked` par lancer

**Problème.** Chaque wrap `launchAttack` fait `local parked = {}` puis `table.insert` pour chaque `isBeachhead`, retire, appelle `origLaunch`, réinsère. Une allocation porteuse par clic / décision bot, même à 0 tête de pont. La loi (garer `isBeachhead` seulement, jamais merger deux ponts, jamais fusionner pont+terre) ne change pas. Distinct de V41 (`collapsingBuf` 10 Hz combat) et de V29 (HUD fronts, tas séparés).

**20K CCU.** Un shard 8 humains + 16 bots relance des fronts plusieurs fois par seconde en mid-game. Recycle de la porteuse élimine l’alloc courte du wrap. Pas d’autorité (mêmes `table.remove` / `table.insert` arrière, même `origLaunch`). Ne pas fusionner avec `collapsingBuf` : parked est une liste d’Attack live, pas des records victim/captor.

**Faire.**

1. Ajouter `parkedBuf: { any } = table.create(8)` module-level dans `BoatFront.luau`. Au début du wrap `launchAttack` : n = 0. Si `atk.isBeachhead` : n += 1 ; `parkedBuf[n] = atk` ; `table.remove(self.attacks, i)`. Truncate leftover n+1..# **avant** `origLaunch` (un leftover non truncaté réinsèrerait un pont fantôme d’un lancer précédent). Après `origLaunch` : réinsérer `1..n` (pas `#` sans truncate). Pas de RemoteFunction.
2. Ne pas modifier `seedBeachhead` / `enqueueFront` / `isBeachhead` critère. Ne pas merger deux ponts du même couple. Ne pas toucher AimFront / ChantierB / `MAX_ACTIVE_ATTACKS_PER_PLAYER`. Ne pas require de module nouveau. `origLaunch` reste le corps terre. Après V43. Ne pas porter `collapseRemainBuf` (V45) en même temps.

**Contraintes.** Server-only. Recette V41 (`collapsingBuf` + truncate avant traitement). **V44 visual ≠ V41 (`collapsingBuf`, déjà fait) ≠ V29 (HUD fronts, déjà fait).** `parkedBuf` n’est pas réentrant. `launchAttack` est synchrone. Ne pas `table.clone` des Attack. Les Attack parkés sont les **mêmes** objets (identité), pas des copies. Overlay n’itère pas cette liste. Client 34/34 (pas 35 : pas de `SpawnHint` feel).

**Tester.** 0 pont + `launchAttack` terre → `#attacks == 1`, pas d’erreur, second lancer 0 pont OK. 2 `seedBeachhead` du même couple + `launchAttack` terre → 2 ponts **plus** 1 front terre (3 Attack), troupes de pont intactes. Deux wrap sans pont → pas d’erreur. Banc V29 (HUD 1 terre + 1 beachhead = 2 tas) **doit rester vert**. `./tests/run.sh`. Client 34/34. 6000 ticks.

**Fichiers.** `BoatFront.luau` (wrap `launchAttack` seulement), `tests/simulate.luau` (bloc court à côté du banc beachhead / V29).

### ISSUE-V45 — `GameState.collapseFaction` alloue `remaining` / `leftovers`

**Problème.** Chaque `collapseFaction` fait `local remaining = {}` (scan `TILE_COUNT`), puis jusqu’à `COLLAPSE_MAX_PASSES` (24) `local leftovers = {}` + `table.insert`. Deux allocations porteuses + N inserts par absorption. `collapseScratch = table.create(4, 0)` est aussi alloué **par appel**. La loi (butin avant démantèlement, héritier captor prioritaire, île → NEUTRAL, `CONQUEST_PLUNDER_*`) ne change pas. Distinct de V41 (`collapsingBuf` liste victim/captor) et de V37 (`elimBuf` slots).

**20K CCU.** Leftover V41. Un shard 18 slots absorbe plusieurs factions en late. Recycle des porteuses élimine l’alloc du balayage. Pas d’autorité (même scan, mêmes `setOwner`, même plunder). Ne pas fusionner avec `elimBuf` : collapse redistribue le territoire, `removePlayer` vient après via `stepElimination`. Ne pas fusionner avec `doomedBuf` (indices d’Attack).

**Faire.**

1. Ajouter `collapseRemainBuf: { number } = table.create(64)`, `collapseLeftBuf: { number } = table.create(64)`, `collapseScratch = table.create(4, 0)` module-level dans `GameState.luau`. `collapseFaction` : n = 0 ; scan `TILE_COUNT` → `collapseRemainBuf[n] = index`. Truncate leftover **avant** plunder (`# == 0` → return, comme aujourd’hui). Chaque passe : nLeft = 0 ; écrire `collapseLeftBuf` ; truncate leftover **avant** de swapper (échanger les deux buf, n = nLeft) ; break si n == 0 ou `not progressed`. Itérer `1..n`, pas `#` sans truncate. Pas de RemoteFunction.
2. Ne pas modifier `COLLAPSE_MAX_PASSES` / `COLLAPSE_MIN_TILES` / plunder / notify. Ne pas câbler `MAX_TILES_PER_TICK`. Ne pas require de module nouveau. Ne pas toucher `ChantierB` wrap (V41 déjà). Ne pas pooler `self.plunders` (payload répliqué). `where = remaining[1]` devient `collapseRemainBuf[1]` **avant** le premier swap. Après V44. Ne pas porter `parkedBuf` en même temps. **Garder** `stripTerritory` visuel (`awaitingSpawn`).

**Contraintes.** Pas de RemoteFunction. Recette V37 (`elimBuf` truncate leftover avant traitement). **V45 visual ≠ V41 (`collapsingBuf`, déjà fait) ≠ V37 (`elimBuf`, déjà fait) ≠ V43 (`stripBuf` rot, déjà fait).** Les buf ne sont pas réentrants. `collapseFaction` est unique par tick (collecte V41 close avant). Un leftover d’état A dans l’état B sans truncate ferait `setOwner` d’une tuile fantôme — truncate obligatoire. Ne pas itérer `#` sur un buf non truncaté. Client 34/34.

**Tester.** Banc collapse existant (butin bot, territoire captor) **doit rester vert**. Banc V41 collapse recycle **doit rester vert**. Ajouter : `collapseFaction` sur un slot sans tuile → return, pas d’erreur, plunder inchangé. Deux appels (victime déjà à 0 puis autre victime) → pas de leftover de tuiles de A dans B. `./tests/run.sh`. Client 34/34. 6000 ticks.

**Fichiers.** `GameState.luau` (`collapseFaction` seulement), `tests/simulate.luau` (bloc court à côté du banc « effondrement » / V41 collapse).

---

## Hors scope volontaire

- Merger feel `07c6`/`69f4` / hardening `5edc` sur #39/#87.
- Spatial hash warships / `bunkerCells` (hardening N41) — `bunkersBySlot` + `carrierBuf` suffisent.
- Pairing convois simplifié hardening N40 (poids = level only) — la loi visuelle manhattan/alliance/`longCap` reste.
- `MODE_KEYS` mort (digits 1–4 = bâtiments). Cosmétique.
- Fallout disque = rayon **inner** seulement (OF outer = spec produit).
- Brancher les clés Config mortes (`ATTACK_SPEND_RATE`, `FRONT_TILES_PER_CONTACT`, `BOAT_LANDING_BONUS`).
- `combatUnlocked` forcé à `true` chaque tick playing (`init.server`) : prep=0, pas un leak client.
- Hover client `SpawnHint` (feel N58) — isolation serveur d’abord (V16b livré).
- `samsOf` / `fillBlastBuf` / `snapshotBoats` / `buildingSnapBuf` / `frontHudForReplicate` / `pricesFor` / `playerStatsForReplicate` / `viewFor` / `expiredBuf` / `contactBuf` / `siteBuf` / `elimBuf` / `pathWalkBuf` / `stationBuf` / `ctxBuf` / `doomedBuf` / `allyBuf` / `stripBuf` réentrants : un seul appelant chacun (sauf `viewFor` **par slot** — c’est voulu). Dupliquer le buffer si un second appelant apparaît. `playerStatsForReplicate` appelle `frontHudForReplicate` — ne pas rappeler le HUD dans `replicate()`.
- Feel N70 `retreating` sur le snapshot — Overlay visuel ne teinte pas la retraite.
- Feel N20 `TRAIN_STOP_BONUS` dans `refreshRailNetwork` — HUD visuel lit l’espérance **sans** ce multiplicateur ; `Trade.deliveryValue` l’applique déjà. Ne pas porter.
- `delivery.level` snapshot à l’arrivée (feel) : le header Trade dit « niveau à l’arrivée » ; dispatch stocke déjà `level` mais `resolve` lit `factory.level`. Produit, pas un bug d’index.
- `dirtyIndexBuf` (feel N72 / hardening N53) — ne ferme pas l’alloc `buffer.create` (voir V14b).
- `buildRoster` (`init.server`, hors bundle) — 10 Hz playing, leftover N2 skip-si-inchangé.
- `BoatFront.parked` — par lancer, pas 10 Hz (V44).
- `GameState.collapseFaction` `remaining`/`leftovers` — une fois par vie de faction, pas 10 Hz (V45).
- `Nukes.splitMirv` `targets` — par MIRV, pas le hot path.

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–30 + **passe 31** (`allyBuf` rawequal + leftover `breakAlliance` ; `stripBuf` rot sous quota, deux camps, tiles vs buffer).  
Invariants 5b–5f : index `buildingsBySlot` / `coolingBuildings` / `factoriesBySlot` / `portsByTile` / `navalBasesBySlot` vs hash, chaque 500 ticks.  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
