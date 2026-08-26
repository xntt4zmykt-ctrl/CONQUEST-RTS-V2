# Nightly report — passe 27 (revue PR #77)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-e857` (PR #77, `d941cdc`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-027d`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #77 (`Research.progress` min / `viewFor` recycle — HEAD visuel). Correctifs sûrs, sans merger feel `2f5d`/`cc42` ni hardening `4197`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `Diplomacy.step` pool `expiredBuf` / `expiredRecPool` | `Diplomacy.luau` | V34 N79 |
| `Bots.neighborFactions` / `contactBuf` | `Bots.luau` | V35 N80 |

`viewFor` / `requestIsLive` / `areAllied` visuels **conservés** (type-guard `true`/non-number). Feel N79 ne purge que `typeof == "number"` — **non copié**. `Research.progress` / `pricesFor` / `playerStatsForReplicate` **non retouchés**. `gatherSites` **non poolé**. Schéma filaire client **inchangé** (`FireClient` diplomatie). GameState ne require toujours pas Buildings / Research.

---

## Constatations PR #77 (à ne pas casser)

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
- **Diplomatie 10 Hz :** `Diplomacy.step` (V34). `expiredBuf` + `expiredRecPool`. Collecter `n`, poser `rec.a`/`rec.b`, itérer `1..n`, truncate leftover. **`true` legacy continue** ; non-number (ex. `"oops"`) expire. Feel N79 ne copie pas ce type-guard.
- **Bots perception :** `Bots.neighborFactions` (V35). `contactBuf` unique, `table.clear`. Slot inconnu → map vide. **Pas réentrant.** `gatherSites` alloue encore (V36).
- **Spawn clic :** terre libre + `isSpawnIsolated`. Snap `r=6` seulement si la tuile cliquée est **occupée**.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `GameState` ne require pas `Buildings` / `Research` / `Types`.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–18) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.

---

## Specs worker (reste)

Ne pas merger feel `2f5d`/`cc42` ni hardening `4197` sur cette branche sans rebase. Porter **une** recette à la fois.

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

### ISSUE-V36 — `Bots.gatherSites` `siteBuf`

**Problème.** `gatherSites` (locale) alloue `local sites: { number } = {}` puis `table.insert` jusqu’à 40 (côte PORT/NAVAL_BASE), 60 (frontière DEFENSE) ou 45 tirages (villes/silos/SAM). Un appel par bot par `DECISION_INTERVAL` quand `decideBuild` a un `wanted`. Feel N81 (`2f5d`) recycle `siteBuf`.

**20K CCU.** Jusqu’à 18 bots × ~0.7 Hz = ~13 arrays courts / s sur le hot path build, après que V35 a déjà retiré les hash contacts. Le parcours côte/frontière est déjà payé.

**Faire.** Recette feel N81 (`2f5d`) : promouvoir `Bots.gatherSites`. `siteBuf` module-level (`table.create(60)` — cap DEFENSE). Au début : n = 0. Même algo, **sans shuffle**. PORT/NAVAL_BASE : `ps.coast`, cap 40. DEFENSE : `ps.border`, cap 60. Sinon : 45 `rng:NextInteger`, garder si `owner == ps.slot`. Poser `siteBuf[n] = index`. Truncate `#siteBuf` à n (recette N68). Slot / `ps` sans côte ni frontière → array **vide** (`# == 0`), pas nil. Remplacer l’appel interne dans `decideBuild`. **Pas réentrant.** Après V35. Ne pas porter `stepElimination` (V37) en même temps.

**Contraintes.** Server-only. Ne pas changer les caps 40/60/45. Ne pas require de module nouveau. Ne pas toucher `contactBuf` / `humanTargetProtected` / `decideNuke`. Ne pas itérer `owner` global pour DEFENSE/PORT.

**Tester.** 1 joueur spawn (frontière non vide). `Bots.gatherSites(state, ps, Config.BUILDING.DEFENSE, rng)` → `# >= 1`, chaque index est dans `ps.border`, `# <= 60`. Second appel immédiat → `rawequal`. `table.clear(ps.border)` puis rappel → `# == 0` (truncate). PORT sur un spawn sans côte → `# == 0`. `./tests/run.sh`. Client 34/34.

### ISSUE-V37 — `GameState.stepElimination` `elimBuf`

**Problème.** `stepElimination` alloue `local doomed: { number } = {}` **chaque tick**, puis `table.insert` les slots `tiles == 0` sans offensive ni bateau. Même sans élimination, la porteuse est allouée 10 Hz. Feel N82 recycle `elimBuf`. Distinct du `local doomed` bâtiments de `removePlayer`.

**20K CCU.** 10 Hz × 1 table vide, empilé sur le tick déjà allégé par V34/V35. Collecter avant de muter `players[]` reste obligatoire.

**Faire.** Recette feel N82 (`2f5d`) : `elimBuf` module-level (`table.create(8)`). **Ne pas** le nommer `doomed` (`removePlayer` a déjà ce nom). Au début : n = 0. Même loi : skip `awaitingSpawn`, skip `tiles > 0`, skip offensive `attacker == slot`, skip bateau `boat.slot == slot`, sinon `elimBuf[n] = slot`. Truncate leftover n+1..#. Itérer `1..n` (notify humain seulement, `removePlayer`). `return elimBuf`. Ne pas truncate à 0 **après** le return. Après V36. Ne pas modifier `GameState.step` / `removePlayer` / `collapseFaction` / `settledHumans`.

**Contraintes.** Server-only. Ne pas changer la loi : bot éliminé = silencieux, humain = notify. Un joueur avec transport en mer ou front actif **survit**. Buffer **partagé entre instances** : truncate leftover sinon un mort de l’état A fuit dans l’état B.

**Tester.** 1 joueur vivant → `stepElimination` length 0, second appel `rawequal`. Strip toutes les tuiles (`setOwner` → NEUTRAL, pas d’attaque, pas de bateau) → length 1, slot présent, `players[slot] == nil` après. **Truncate inter-instances** : après cette élimination, `GameState.new` + 1 joueur vivant → `stepElimination` length 0, **pas** le slot du mort précédent. Ne pas casser `awaitingSpawn` (passe 16). `./tests/run.sh`. Client 34/34.

---

## Hors scope volontaire

- Merger feel `2f5d`/`cc42` / hardening `4197` sur #39/#77.
- Spatial hash warships / `bunkerCells` (hardening N41) — `bunkersBySlot` + `carrierBuf` suffisent.
- Pairing convois simplifié hardening N40 (poids = level only) — la loi visuelle manhattan/alliance/`longCap` reste.
- `MODE_KEYS` mort (digits 1–4 = bâtiments). Cosmétique.
- Fallout disque = rayon **inner** seulement (OF outer = spec produit).
- Brancher les clés Config mortes (`ATTACK_SPEND_RATE`, `FRONT_TILES_PER_CONTACT`, `BOAT_LANDING_BONUS`).
- `combatUnlocked` forcé à `true` chaque tick playing (`init.server`) : prep=0, pas un leak client.
- Hover client `SpawnHint` (feel N58) — isolation serveur d’abord (V16b livré).
- `samsOf` / `fillBlastBuf` / `snapshotBoats` / `buildingSnapBuf` / `frontHudForReplicate` / `pricesFor` / `playerStatsForReplicate` / `viewFor` / `expiredBuf` / `contactBuf` réentrants : un seul appelant chacun (sauf `viewFor` **par slot** — c’est voulu). Dupliquer le buffer si un second appelant apparaît. `playerStatsForReplicate` appelle `frontHudForReplicate` — ne pas rappeler le HUD dans `replicate()`.
- Feel N70 `retreating` sur le snapshot — Overlay visuel ne teinte pas la retraite.
- `delivery.level` snapshot à l’arrivée (feel) : le header Trade dit « niveau à l’arrivée » ; dispatch stocke déjà `level` mais `resolve` lit `factory.level`. Produit, pas un bug d’index.
- Feel N81 (`gatherSites` siteBuf) / N82 (`elimBuf`) — V36 / V37.
- `dirtyIndexBuf` (feel N72 / hardening N53) — ne ferme pas l’alloc `buffer.create` (voir V14b).

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–26 + **passe 27** (`Diplomacy.step` oops purge + `true` survit, pacte numérique à terme → cooldown + notify pas TRAHI, leftover second step 0 notify, A–B et A–C tombent ensemble ; `neighborFactions` contact + `rawequal`, slot 99 vide + `rawequal`, disparu absent).  
Invariants 5b–5f : index `buildingsBySlot` / `coolingBuildings` / `factoriesBySlot` / `portsByTile` / `navalBasesBySlot` vs hash, chaque 500 ticks.  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
