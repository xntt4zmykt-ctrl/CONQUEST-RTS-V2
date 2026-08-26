# Nightly report — passe 25 (revue PR #72)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-b826` (PR #72, `853bd3e`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-3245`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #72 (`buildingSnapBuf` / `frontHudForReplicate` — HEAD visuel). Correctifs sûrs, sans merger feel `cc42`/`4876` ni hardening `c4da`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `Buildings.pricesFor` / `priceBuf` (slot inconnu = `emptyPriceBuf`, pas `math.huge`) | `Buildings.luau` | V30 N75/N56 |
| `playerStatsForReplicate` / `statsBuf` (`eraProgress`/`buildPrices` nil dans le helper) | `GameState.luau` | V31 N76/N57 |
| `init.server` `replicate()` pose `eraProgress` / `buildPrices` après le helper | `init.server.luau` | V30+V31 |

`buildingSnapBuf` / `frontHudForReplicate` / `boatSnapBuf` / `missileSnapBuf` **non retouchés**. Schéma filaire client **inchangé** (`FireAllClients`, pas `fireDeployed`). GameState ne require toujours pas Buildings / Research.

---

## Constatations PR #72 (à ne pas casser)

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
- **Spawn clic :** terre libre + `isSpawnIsolated`. Snap `r=6` seulement si la tuile cliquée est **occupée**.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `GameState` ne require pas `Buildings` / `Research` / `Types`.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–18) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.

---

## Specs worker (reste)

Ne pas merger feel `cc42`/`4876` ni hardening `c4da` sur cette branche sans rebase. Porter **une** recette à la fois.

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

### ISSUE-V32 — `Research.progress` sans table `ratios`

**Problème.** `Research.progress` alloue `ratios = { gold, tiles }` puis `table.insert` par bâtiment requis, **chaque tick playing × 18 factions**. Feel N77 (`cc42`) calcule le min courant sans table.

**20K CCU.** 10 Hz × 18 = alloc HUD même sans clic d’ère.

**Faire.** Recette feel N77 (`cc42`) : `lowest` scalaire, `math.min` or / tuiles / buildings, `math.clamp(lowest, 0, 1)`. **Pas** de `ratiosBuf` (inutile). Formule inchangée. Ne pas porter `viewFor` recycle en même temps (V33).

**Contraintes.** Server-only. Ne pas changer le schéma `eraProgress` (number 0..1). Ne pas toucher `canAdvance` / `advance` / `goldReserveFor`.

**Tester.** Slot max ère → 1. Slot or=0 tuiles insuffisantes → 0. Un critère bloquant = le min. `./tests/run.sh`. Client 34/34.

### ISSUE-V33 — `Diplomacy.viewFor` record par slot

**Problème.** `viewFor` alloue 6 tables (`allies`/`incoming`/`outgoing`/`embargoes`/`traitors`/`marks` + record) **par humain, 1 Hz**. Feel N78 a `viewBuf[slot]` — **un record par slot**, pas un buf global (la boucle `FireClient` séquentielle viderait le client précédent).

**20K CCU.** 1 Hz × 8 humains = alloc diplomatique inutile ; un buf global corromprait le HUD.

**Faire.** Recette feel N78 (`cc42`) : `viewRecFor(slot)` + `table.clear` des inner maps. Slot disparu → maps vides, pas d’erreur, **pas** de scan requests/traitors. Garder `areAllied` / `requestIsLive` visuels (feel inline `tick < expiry` — ne pas casser le type-guard visuel). Après V32.

**Contraintes.** Server-only. Ne pas porter `Diplomacy.step` `expired` pool (feel N79) ni `neighborFactions` `contactBuf` (feel N80). Schéma `Types.Diplomacy` inchangé. `FireClient` visuel (pas `fireDeployed`).

**Tester.** 1 joueur 0 pacte → maps vides, second appel `rawequal` du record. Alliance live → `allies[other]`. Slot disparu → maps vides. `./tests/run.sh`. Client 34/34.

---

## Hors scope volontaire

- Merger feel `cc42`/`4876` / hardening `c4da` sur #39/#72.
- Spatial hash warships / `bunkerCells` (hardening N41) — `bunkersBySlot` + `carrierBuf` suffisent.
- Pairing convois simplifié hardening N40 (poids = level only) — la loi visuelle manhattan/alliance/`longCap` reste.
- `MODE_KEYS` mort (digits 1–4 = bâtiments). Cosmétique.
- Fallout disque = rayon **inner** seulement (OF outer = spec produit).
- Brancher les clés Config mortes (`ATTACK_SPEND_RATE`, `FRONT_TILES_PER_CONTACT`, `BOAT_LANDING_BONUS`).
- `combatUnlocked` forcé à `true` chaque tick playing (`init.server`) : prep=0, pas un leak client.
- Hover client `SpawnHint` (feel N58) — isolation serveur d’abord (V16b livré).
- `samsOf` / `fillBlastBuf` / `snapshotBoats` / `buildingSnapBuf` / `frontHudForReplicate` / `pricesFor` / `playerStatsForReplicate` réentrants : un seul appelant chacun. Dupliquer le buffer si un second appelant apparaît. `playerStatsForReplicate` appelle `frontHudForReplicate` — ne pas rappeler le HUD dans `replicate()`.
- Feel N70 `retreating` sur le snapshot — Overlay visuel ne teinte pas la retraite.
- `delivery.level` snapshot à l’arrivée (feel) : le header Trade dit « niveau à l’arrivée » ; dispatch stocke déjà `level` mais `resolve` lit `factory.level`. Produit, pas un bug d’index.
- Feel N77 (`Research.progress` sans table `ratios`) / N78 (`viewFor` recycle par slot) — V32 / V33.
- Feel N79 (`Diplomacy.step` expired pool) / N80 (`neighborFactions` contactBuf) — après V33.
- `dirtyIndexBuf` (feel N72 / hardening N53) — ne ferme pas l’alloc `buffer.create` (voir V14b).

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–24 + **passe 25** (`pricesFor` = `priceFor` pour chaque BUILDABLE, second appel `rawequal`, slot 99 map vide, CITY double après pose ; 1 joueur 0 front → champs honores `eraProgress`/`buildPrices` nil, second appel `rawequal` porteuse+record, launch → `activeAttacks==1`, `removePlayer` → slot absent).  
Invariants 5b–5f : index `buildingsBySlot` / `coolingBuildings` / `factoriesBySlot` / `portsByTile` / `navalBasesBySlot` vs hash, chaque 500 ticks.  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
