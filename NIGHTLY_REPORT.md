# Nightly report — passe 30 (revue PR #84)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-107e` (PR #84, `0c369ee`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-c695`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #84 (`findSeaPath` pathWalkBuf / `refreshRailNetwork` stationBuf — HEAD visuel). Correctifs sûrs, sans merger feel `69f4`/`b62d` ni hardening `bef6`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `Buildings.contextFor` record + closures module | `Buildings.luau` | V40 N85 |
| `ChantierB.cancelOpposingFronts` / wrap `stepAttacks` | `ChantierB.luau` | V41 N86 |

`pricesFor` / `priceBuf` **conservés**. `Placement.luau` et `PlacementPreview` **non touchés** (le client construit ses closures). Slot inconnu → `nil` **sans** muter `ctxBuf`. `CAPTURE_GUARD=80` visuel **inchangé**. `stripTerritory` visuel (`awaitingSpawn = true`) **inchangé**. `elimBuf` / `pathWalkBuf` / `stationBuf` **non retouchés**. Schéma filaire client **inchangé**. GameState ne require toujours pas Buildings / Research.

---

## Constatations PR #84 (à ne pas casser)

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
- **Spawn clic :** terre libre + `isSpawnIsolated`. Snap `r=6` seulement si la tuile cliquée est **occupée**.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `GameState` ne require pas `Buildings` / `Research` / `Types`.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–18) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.

---

## Specs worker (reste)

Ne pas merger feel `69f4`/`b62d` ni hardening `bef6` sur cette branche sans rebase. Porter **une** recette à la fois.

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

**Faire.** Liste incrémentale des tuiles par slot (même structure que `border`) **ou** reservoir sampling sur un index compact. Ne pas changer la formule `Doomsday.rotQuota`. Distinct de V43 (`stripBuf` recycle la liste temporaire, **pas** le scan).

**Tester.** Cadran existant + 1 humain sous quota. Invariants `tiles` vs buffer.

### ISSUE-V14b — En-tête de compteur pour `flushOwnerDelta`

**Problème.** Passe 17 recycle `deltaIndices` mais `buffer.create(count * 5)` reste obligatoire : un tampon trop grand serait lu comme des tuiles fantômes (slot 0). Feel N72 a `dirtyIndexBuf` (liste d’indices, pas l’en-tête filaire).

**20K CCU.** 10 Hz playing × alloc buffer = pression GC sur 8 clients.

**Faire.** Préfixer le payload `[u32 count][u32 index][u8 slot]…` **ou** RemoteEvent séparé pour la longueur. Adapter le client (`WorldRenderer` / init.client). Growth-only ensuite. Ne pas porter feel N72 seul : ça ne ferme pas l’alloc `buffer.create`.

**Contraintes.** Changer client **et** serveur dans le même commit. Ne pas casser `RequestSnapshot` (carte entière, autre remote).

**Tester.** Match 6000 ticks, P0 metrics. Client 34/34.

### ISSUE-V42 — `Bots.decideDiplomacy` alloue `allies` à chaque décision

**Problème.** Chaque `decideDiplomacy` (Bots.step, 1 tick sur `DECISION_INTERVAL=14` par bot, décalage `slot * 3`) fait `local allies = {}` puis remplit via `areAllied`. Hash jetable, lu tout de suite pour la coalition anti-leader. Distinct de V35 (`contactBuf` / `neighborFactions`, perception de frontière) et de V40 (`ctxBuf` pose).

**20K CCU.** 16 bots × ~0.7 Hz. Recycle d’un `allyBuf` (`table.clear`) élimine l’alloc courte du hot path diplomatie IA. Pas d’autorité (`areAllied` inchangé, mêmes `accept`/`decline`/`setEmbargo`). Ne pas fusionner avec `contactBuf` : `allies` est un set de pactes, `contactBuf` est un set de voisins de tuiles.

**Faire.**

1. Ajouter `allyBuf: { [number]: boolean } = {}` module-level dans `Bots.luau`. Au début de `decideDiplomacy` : `table.clear(allyBuf)`. Remplacer `allies` par `allyBuf`. Ne **pas** itérer `#allyBuf` (hash). Ne pas toucher `neighborFactions` / `contactBuf` / `siteBuf`. Pas de RemoteFunction.
2. Ne pas changer les seuils `acceptChance` 0.75/0.35, `COALITION_ALLY_CHANCE`, `COALITION_EMBARGO_CHANCE`. Ne pas require de module nouveau. Après V41. Ne pas porter `stripBuf` (V43) en même temps.

**Contraintes.** Server-only. Recette `contactBuf` (V35) : `table.clear` hash, pas de truncate array. **V42 visual ≠ V35 (`contactBuf`, déjà fait) ≠ V40 (`ctxBuf`, déjà fait).** `allyBuf` n’est pas réentrant. `decideDiplomacy` est synchrone et unique par bot (la boucle `Bots.step` est séquentielle — un second `clear` au bot suivant est voulu). Ne pas stocker `allyBuf` au-delà de la fonction. Ne pas exposer le buffer (pas de filaire).

**Tester.** Banc diplomatie bots existant (accept/decline, embargo leader) **doit rester vert**. Ajouter : 2 humains alliés + 1 bot, `decideDiplomacy` deux fois → pas d’erreur ; après `breakAlliance` le bot ne traite plus l’ex-allié comme allié (le leftover d’un `clear` oublié ferait une coalition fantôme). `./tests/run.sh`. Client 34/34. 6000 ticks.

**Fichiers.** `Bots.luau` (`decideDiplomacy` seulement), `tests/simulate.luau` (bloc court à côté du banc V35 / `neighborFactions`).

### ISSUE-V43 — `ChantierB.stepDoomsday` alloue `toStrip` 10 Hz

**Problème.** Quand le cadran est armé et qu’un slot est sous quota, `stepDoomsday` fait `local ripped, toStrip = 0, {}` puis `table.insert` jusqu’à `quota * 4` (early-out du scan `TILE_COUNT`). Deux allocations porteuses par slot marqué par tick. La loi (`Doomsday.rotQuota`, drain troupes, `WARN_SECONDS`) ne change pas. Distinct de V13 (réécrire le scan O(carte) en liste incrémentale) et de V41 (`collapsingBuf` combat, pas rot).

**20K CCU.** Pic de fin de partie : 10 Hz × slots sous le seuil × alloc courte + scan 40 960. Recycle de `stripBuf` (`table.create(64)`) + truncate leftover ferme l’alloc **sans** toucher à la formule ni au scan. V13 reste le vrai fix O(carte).

**Faire.**

1. Ajouter `stripBuf: { number } = table.create(64)` module-level dans `ChantierB.luau`. Dans le bloc quota : `n = 0` ; à chaque tuile du camp : `n += 1 ; stripBuf[n] = index` ; break si `n >= quota * 4`. Truncate leftover `n+1..#` **avant** la boucle d’arrachage. Itérer `1..n`, pas `#` sans truncate. Remettre `n = 0` (ou truncate à 0) après traitement pour qu’un second slot du même tick ne ré-arrache pas les tuiles du premier. Pas de RemoteFunction.
2. Ne pas changer `Doomsday.rotQuota` / `drain` / `troopFloor`. Ne pas construire d’index tuiles-par-slot (ça c’est V13). Ne pas toucher `elimBuf` / `doomedBuf` / `collapsingBuf`. Ne pas require de module nouveau. Après V42. Ne pas porter `allyBuf` en même temps.

**Contraintes.** Pas de RemoteFunction. Recette V37 (`elimBuf` truncate avant traitement). **V43 visual ≠ V13 (scan O(carte), ouvert) ≠ V41 (`collapsingBuf`, déjà fait) ≠ V37 (`elimBuf`, déjà fait).** `stripBuf` n’est pas réentrant. `stepDoomsday` est unique par tick mais **boucle les slots** — truncate/reset **entre** slots (sinon slot B arrache les tuiles de A). Un leftover sans truncate ferait `setOwner(NEUTRAL)` sur une tuile d’un autre camp. Les indices ne sont pas répliqués.

**Tester.** Banc cadran existant **doit rester vert**. Ajouter : 1 humain sous quota, `rotQuota >= 1` → tuiles diminuent, `tiles` vs buffer `owner`. Deux slots marqués le même tick → chacun perd son propre territoire, pas celui de l’autre. `./tests/run.sh`. Client 34/34. 6000 ticks.

**Fichiers.** `ChantierB.luau` (`stepDoomsday` seulement, bloc `toStrip`), `tests/simulate.luau` (bloc court à côté du banc cadran).

---

## Hors scope volontaire

- Merger feel `69f4`/`b62d` / hardening `bef6` sur #39/#84.
- Spatial hash warships / `bunkerCells` (hardening N41) — `bunkersBySlot` + `carrierBuf` suffisent.
- Pairing convois simplifié hardening N40 (poids = level only) — la loi visuelle manhattan/alliance/`longCap` reste.
- `MODE_KEYS` mort (digits 1–4 = bâtiments). Cosmétique.
- Fallout disque = rayon **inner** seulement (OF outer = spec produit).
- Brancher les clés Config mortes (`ATTACK_SPEND_RATE`, `FRONT_TILES_PER_CONTACT`, `BOAT_LANDING_BONUS`).
- `combatUnlocked` forcé à `true` chaque tick playing (`init.server`) : prep=0, pas un leak client.
- Hover client `SpawnHint` (feel N58) — isolation serveur d’abord (V16b livré).
- `samsOf` / `fillBlastBuf` / `snapshotBoats` / `buildingSnapBuf` / `frontHudForReplicate` / `pricesFor` / `playerStatsForReplicate` / `viewFor` / `expiredBuf` / `contactBuf` / `siteBuf` / `elimBuf` / `pathWalkBuf` / `stationBuf` / `ctxBuf` / `doomedBuf` réentrants : un seul appelant chacun (sauf `viewFor` **par slot** — c’est voulu). Dupliquer le buffer si un second appelant apparaît. `playerStatsForReplicate` appelle `frontHudForReplicate` — ne pas rappeler le HUD dans `replicate()`.
- Feel N70 `retreating` sur le snapshot — Overlay visuel ne teinte pas la retraite.
- Feel N20 `TRAIN_STOP_BONUS` dans `refreshRailNetwork` — HUD visuel lit l’espérance **sans** ce multiplicateur ; `Trade.deliveryValue` l’applique déjà. Ne pas porter.
- `delivery.level` snapshot à l’arrivée (feel) : le header Trade dit « niveau à l’arrivée » ; dispatch stocke déjà `level` mais `resolve` lit `factory.level`. Produit, pas un bug d’index.
- `dirtyIndexBuf` (feel N72 / hardening N53) — ne ferme pas l’alloc `buffer.create` (voir V14b).
- `buildRoster` (`init.server`, hors bundle) — 10 Hz playing, leftover N2 skip-si-inchangé.
- `GameState.collapseFaction` `remaining`/`leftovers` — une fois par vie de faction, pas 10 Hz.
- `Nukes.splitMirv` `targets` — par MIRV, pas le hot path.

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–29 + **passe 30** (`contextFor` rawequal + slot 99 sans mute + CITY + ownerAt conserve lit B ; `doomedBuf` next nil après clear ; clash égal → 0 front ; collapse sous seuil → captor grandit).  
Invariants 5b–5f : index `buildingsBySlot` / `coolingBuildings` / `factoriesBySlot` / `portsByTile` / `navalBasesBySlot` vs hash, chaque 500 ticks.  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
