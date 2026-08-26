# Nightly report — passe 19 (revue PR #54)

**Branche revue :** `cursor/analyse-nocturne-du-codebase-121e` (PR #54, `dc4333b`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-cb10`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**. `error()` si un invariant casse (Luau CLI sans `os.exit`).

Revue de PR #54 (aura morte, `CAPTURE_GUARD`, `samsBySlot` — HEAD visuel). Correctifs sûrs, sans merger feel `e735`/`7c38` ni hardening `a320`/`e91b`.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `silosBySlot` : pose / capture / destroy / `removePlayer` | `GameState.luau` | V18 N60 |
| `Nukes.launch` itère l’index (O(silos du camp), plus O(hash)) | `Nukes.luau` | V18 |
| MIRV de test passe par `placeBuilding` (plus d’écriture brute du hash) | `tests/simulate.luau` | V18 / hardening N44 |
| `samsOf` : slot sans SAM = `{}` (plus de rescan hash) | `Buildings.luau` | bug PR #54 |
| `isSpawnIsolated` partagé `findSpawn` / `claimSpawn` | `GameState.luau`, `ChantierB.luau` | V16b N55 |
| Clic spawn collé : **refus**, pas de snap `r=6` | `ChantierB.luau` | V16b |

Cooldown silo toujours écrit dans `launch` (`silo.cooldown = SILO_COOLDOWN`). Ne pas porter `armCooldown` (V19 / hardening N43).

---

## Constatations PR #54 (à ne pas casser)

- **Autorité :** le client n’évalue aucune règle de combat/économie. Ordres = remotes + sequence.
- **Vérité runtime :** `SystemsBootstrap.install()` → `ChantierB.apply(Config)`. Ne pas tuner `Config.luau` seul.
- **Combat vivant :** `ChantierB.stepAttacks`. Guard = `ChantierB.CAPTURE_GUARD` (80), **pas** `Config.MAX_TILES_PER_TICK` (56 après apply, 400 brut).
- **Posted DEFENSE :** `bunkersBySlot` + `attackLogic`. Buffer `defense` mort pour le combat installé. Plus d’écritures `applyDefenseAura`.
- **Posted SAM :** `samsBySlot` + `tryIntercept` / `samsOf`. Slot sans SAM ne rescane plus le hash (passe 19).
- **Posted SILO :** `silosBySlot` + `Nukes.launch`. Fantôme hors index ignoré.
- **Spawn clic :** terre libre + `isSpawnIsolated`. Snap `r=6` seulement si la tuile cliquée est **occupée**.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique). `silosBySlot` n’ajoute aucun require.
- **Produit 20K CCU :** 8 humains / salon, N serveurs. Un salon ≠ 20K joueurs.
- **Inbound recycle** (passes 16–18) : transports 100 %, missiles contrat B, convois `kind==2`, cadran/colis, alliances, quick-chat — inchangé.

---

## Specs worker (reste)

Ne pas merger feel `e735`/`7c38` ni hardening `a320`/`e91b` sur cette branche sans rebase. Porter **une** recette à la fois.

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

**Problème.** `record()` appelle encore `UpdateAsync` tout de suite (une écriture / humain). Le double-write `release`/`BindToClose` est corrigé ; la tempête de fin de match (8 writes synchrones) reste.

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

**Problème.** Passe 17 recycle `deltaIndices` mais `buffer.create(count * 5)` reste obligatoire : un tampon trop grand serait lu comme des tuiles fantômes (slot 0).

**20K CCU.** 10 Hz playing × alloc buffer = pression GC sur 8 clients.

**Faire.** Préfixer le payload `[u32 count][u32 index][u8 slot]…` **ou** RemoteEvent séparé pour la longueur. Adapter le client (`WorldRenderer` / init.client). Growth-only ensuite.

**Contraintes.** Changer client **et** serveur dans le même commit. Ne pas casser `RequestSnapshot` (carte entière, autre remote).

**Tester.** Match 6000 ticks, P0 metrics. Client 34/34.

### ISSUE-V19 — `stepCooldowns` O(hash) 10 Hz

**Problème.** `Buildings.stepCooldowns` décrémente **tous** les bâtiments chaque tick. Seuls SAM et silos portent un cooldown vivant. Passe 19 indexe les silos pour le **lancement**, pas pour le tick.

**20K CCU.** 10 Hz × N bâtiments, dont villes/usines à cooldown 0.

**Faire.** Recette hardening N43 : `coolingBuildings` + `armCooldown` SAM **et** silos (SAM-only gèlerait `SILO_COOLDOWN`). `Nukes.launch` / `tryIntercept` doivent appeler `armCooldown` (remplacer `silo.cooldown =` / `best.cooldown =`).

**Tester.** SAM intercept → cooldown 90. Silo launch → `SILO_COOLDOWN`. Ville/usine jamais dans l’index. Passe 19 silosBySlot reste verte. P0 metrics.

### ISSUE-V20 — `Trade.step` flatten FACTORY 10 Hz

**Problème.** Chaque tick, `Trade.step` alloue une liste, scannne le hash, **trie** les usines (déterminisme RNG). Feel a `factoriesBySlot` (N61) ; le sort 10 Hz reste (N66).

**20K CCU.** Alloc + sort sur le hot path économique.

**Faire.** Porter **une** recette. N61 : `factoriesBySlot` + iteration déterministe (tri des clés de l’index, pas un flatten hash). N66 : buffer recyclé, tri seulement si dirty. Vague ≠ 45 ticks (c’est le maritime).

**Tester.** Or colis inchangé. Deux seeds identiques → mêmes livraisons. `./tests/run.sh`.

### ISSUE-V21 — `spawnTradeShips` O(ports²)

**Problème.** Vague maritime (`TRADE_SHIP_INTERVAL=45`) flatten tous les PORT du hash puis paires. Hardening N40 a `portsByTile` + early-out cap + buffers recyclés. Visual ne l’a pas.

**20K CCU.** Moins chaud que 10 Hz, mais pic + alloc sur 24 convois max.

**Faire.** Recette hardening N40 (déjà portée feel N63) : `portsByTile` incrémental PORT only, early-out `MAX_TRADE_SHIPS` **et** `<2` avant flatten, `portsBuf`/`candidateBuf`. Distinct de `_carriersDirty` (NAVAL_BASE).

**Tester.** Cap 24 respecté. `<2` ports = pas de scan. P0 metrics. `./tests/run.sh`.

### ISSUE-V22 — Bots upgrade + score nuke O(hash)

**Problème.** `tryUpgradeBuilding` et `decideNuke` (valeur blast) parcourent tout `state.buildings`. Feel N62 a `buildingsBySlot` ; visual n’a que DEFENSE/SAM/SILO.

**20K CCU.** Décision bot × 10 Hz × hash global, pile sur un tick de combat.

**Faire.** Recette feel N62 : `buildingsBySlot` dirty pose/capture/destroy/`removePlayer` (snapshot les clés). `lowestUpgradable` / `blastValue` via l’index du camp. Ne pas re-toucher `silosBySlot` / `samsBySlot`.

**Tester.** Upgrade bot choisit le plus bas palier du camp. Score nuke ignore les bâtiments d’un autre slot. `removePlayer` nil l’index. `./tests/run.sh`.

### ISSUE-V23 — `syncCarriers` spawn NAVAL_BASE O(B)

**Problème.** Dirty flag vivant, mais le spawn des porte-avions manquants rescane tout le hash. Feel N65 a `navalBasesBySlot`.

**20K CCU.** Pose/destroy base = scan global, rare mais sur le même tick que le combat.

**Faire.** Recette feel N65 : `navalBasesBySlot` + spawn via l’index. **Garder** `_carriersDirty`. Ne pas porter le ciblage obus listes (V24).

**Tester.** Pose / capture / destroy NAVAL_BASE indexé. Dirty false → pas de spawn. `./tests/run.sh`.

### ISSUE-V24 — Warships nested targeting

**Problème.** `stepCarriers` : chaque carrier itère tous les bateaux (O(C×B)/tick). Hardening N39 a `carrierBuf`/`targetBuf` recyclés + early-out 0 carrier / 0 autre slot.

**20K CCU.** 10 Hz mer, jusqu’à ~24 unités. Moins chaud que l’éco, mais alloc + nested sur le tick.

**Faire.** Recette hardening N39 uniquement (feel N67). Pas de spatial hash.

**Tester.** 0 carrier → return immédiat. Priorité transport > carrier > trade inchangée. P0 metrics.

### ISSUE-V25 — `samsOf` alloc table

**Problème.** `Buildings.samsOf` alloue `{number}` à chaque appel (bots `decideNuke`). Passe 19 a fermé le rescan hash ; l’alloc reste. Feel N68.

**20K CCU.** Décision nuke bot × alloc, même pour un camp à 0 SAM (table vide neuve).

**Faire.** Buffer recyclé par slot **ou** itérateur interne qui n’alloue pas. Ne pas re-brancher le fallback hash.

**Tester.** `samsOf` slot vide = 0 sans alloc visible (compteur / reuse). `./tests/run.sh`.

---

## Hors scope volontaire

- Merger feel `e735`/`7c38` / hardening `a320`/`e91b` sur #39/#54.
- Spatial hash warships / `bunkerCells` (hardening N41) — `bunkersBySlot` suffit.
- `MODE_KEYS` mort (digits 1–4 = bâtiments). Cosmétique.
- Fallout disque = rayon **inner** seulement (OF outer = spec produit).
- Brancher les clés Config mortes (`ATTACK_SPEND_RATE`, `FRONT_TILES_PER_CONTACT`, `BOAT_LANDING_BONUS`).
- `combatUnlocked` forcé à `true` chaque tick playing (`init.server`) : prep=0, pas un leak client.
- Hover client `SpawnHint` (feel N58) — isolation serveur d’abord (V16b livré).

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, `error()` si échec (Luau CLI sans `os.exit`).  
Serveur : invariants + P0 + or plat + `removePlayer` refund + embargo auto + cap 3 transports + passe 16–18 + **passe 19** (`silosBySlot` pose/lancement plus proche prêt/capture/recycle/destroy, fantôme hash ignoré, `samsOf` sans fallback, isolation clic refus/accept).  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
