# Nightly report — PR #39 (visual + parité OF)

**Branche revue :** `cursor/of-visual-parity-5b2e` (`c9a3b10`)  
**Branche de correctifs :** `cursor/analyse-nocturne-du-codebase-420a`  
**Date :** 2026-08-26  
**Banc :** `./tests/run.sh` — serveur **vert**, client **34/34 vert**.

PR #39 part de P0 + feel-clic + overlay visuel. Elle **n’inclut pas** les nightlies feel `df65` / hardening `9f25`. Cette passe porte les recettes d’autorité **sûres** sur le HEAD visuel, sans merger les deux lignes.

`gh` est en lecture seule : pas d’issues GitHub. Les specs worker sont ci-dessous.

---

## Correctifs livrés (sûrs)

| Sujet | Fichiers | Recette |
|---|---|---|
| `areAllied` mutuel + `tick < expiry` (`true` legacy vivant) | `GameState.luau` | N34 |
| `viewFor` / QuickChat alliesOnly filtrent l’expiry | `Diplomacy.luau` | N32 |
| `accept` refuse une demande périmée ; `request` ignore une inverse périmée | `Diplomacy.luau` | N46 |
| `removePlayer` : `setOwner`, refund défenseur, inbound kind 1/2 + missiles contrat B, diplo inbound, cadran/colis | `GameState.luau` | N43–N48 |
| `settledHumans` + Persistence à l’élimination | `GameState.luau`, `init.server.luau` | N40 |
| Beachhead = `isBeachhead` ; frontier = voisins encore à la cible | `BoatFront.luau` | N36 |
| AimFront re-vise le front terre (`not isBeachhead`) | `SystemsBootstrap.luau` | N36 |
| `tryAnnex` BFS depuis voisins défenseur (BFS mort réparé) | `ChantierB.luau` | N39 |
| Refund si défenseur disparaît mid-combat | `ChantierB.luau` | — |
| `retreatAttack` marque **tous** les fronts du couple | `GameState.luau` | — |
| Own-tile boat = 100 % (pas `BOAT_RETREAT_LOSS`) | `Navy.luau` | — |
| `manhattan` trade : `ay - by` (était `by - by` = 0) | `Navy.luau` | bug net |
| `BOAT_TROOP_RATIO` lu (plus `/5` magique) | `Navy.luau` | — |
| Scan bunkers seulement si `buildingCounts[DEFENSE] > 0` | `ChantierB.luau` | partiel N42 |
| JoinRequest `ended` + `nan`/`inf`/non-entier | `init.server.luau` | — |
| Playing : sequence `>= 1` ; commit **après** apply OK | `IntentValidator.luau`, `Config.luau` | N41 + N29 |
| Diplomatie self refusée à l’enqueue | `IntentValidator.luau` | — |
| Bots : `areAllied` (plus `alliances[]`) | `Bots.luau` | — |
| Tribus : `Bots.humanTargetProtected` | `Tribes.luau` | — |
| HUD : marque « Traître (actif) » | `HUD.luau` | — |
| Pulse de conquête à `surfaceHeight` | `Effects.luau` | — |

---

## Constataitions PR #39 (à ne pas casser)

- **Autorité :** le client n’évalue aucune règle de combat/économie. Ordres = remotes + sequence.
- **Vérité runtime :** `SystemsBootstrap.install()` → `ChantierB.apply(Config)`. Ne pas tuner `Config.luau` seul.
- **Combat vivant :** `ChantierB.stepAttacks`. `GameState.stepAttacks` est mort après install. `MAX_TILES_PER_TICK=56` n’est **pas lu** ; débit = `attackTilesPerTick * speedFactor`, `guard < 80`.
- **Nouveau OF (volontaire) :** or plat 1.2/0.6, plafond `2×(tiles^0.6×1000+50000)` + villes, spacing 15, spawn r=18, dist min 30, embargo auto à l’attaque, victoire 80 %, max 3 transports, SAM hyperbole, warships OF, traître ×0.5/30s, rebate anti-blob, priorité mag 1/1.5/2.
- **Cycles `require` :** aucun au chargement. `Nukes` lazy-require `Diplomacy`. `Tribes` → `Bots` (acyclique).
- **Produit 20K CCU :** 8 humains / salon, 12 bots + 6 tribus **visés**, N serveurs. Un salon ≠ 20K joueurs.

---

## Specs worker (reste)

Ne pas merger feel `df65` ni hardening `9f25` sur cette branche sans rebase. Porter **une** recette à la fois.

### ISSUE-V1 — Packing spawn 18 factions

**Problème.** `SPAWN_RADIUS=18` + `SPAWN_MIN_PLAYER_DISTANCE=30` : les seeds 7 / 99991 / 1234567 / 424242 placent 11–15 factions sur 18. Les tribus sautent. Le banc classique (N12) n’est plus tenable.

**20K CCU.** Un salon Classique sous-peuplé fausse l’éco, les bots et le climax nucléaire (0 frappe en 10 min sur le run principal).

**Faire.** `GameState.findSpawn` : recherche spirale / rejet plus souple pour `isTribe` (dist min 20) **ou** disque tribu plus petit (`TRIBE_SPAWN_RADIUS`). Ne pas réduire le disque humain.

**Contraintes.** Server-only. Ne pas toucher `claimSpawn` visuel. `addPlayer` déjà rollback si `findSpawn` nil.

**Tester.** `EXTRA_SEEDS` + seed 424242 : `spawned == BOT_COUNT + TRIBE_COUNT`. `./tests/run.sh`.

### ISSUE-V2 — `findSeaPath` alloue 40 960 octets / appel

**Problème.** `Navy.findSeaPath` : `buffer.create(TILE_COUNT)` + hash `parent` à chaque invasion / trade / retraite.

**20K CCU.** 10 Hz × 12 factions × tentatives = GC spikes.

**Faire.** Recette feel N37 : pool module `visitBuf`, `parent`, `queue`. `buffer.fill(buf, 0, 0)` (offset + value). Pas d’AimFront.

**Tester.** Invasions existantes + extra seed. Pas de régression de chemin.

### ISSUE-V3 — `syncCarriers` scan bâtiments / tick

**Problème.** `Navy.syncCarriers` parcourt `state.buildings` à chaque `Navy.step`.

**Faire.** Recette feel N38 : `_carriersDirty` + `carrierSeen` recyclé. Dirty uniquement `placeBuilding` / `destroyBuilding` / `transferBuilding` si `NAVAL_BASE`. Pas de scan 10 Hz.

**Tester.** Pose / destruction / capture de base navale → carrier spawn/despawn. Match 6000 ticks.

### ISSUE-V4 — `bunkersBySlot` (scan restant)

**Problème.** `attackLogic` short-circuit si 0 bunker, sinon O(bâtiments) **par tuile conquise**. `applyDefenseAura` écrit encore un buffer ignoré par le combat installé.

**Faire.** Recette feel N42 Option B : `bunkersBySlot[slot][tile]`. Posted = O(bunkers du défenseur). Puis Option A feel N45 : plus d’appels `applyDefenseAura` (fonction conservée pour `tileCost` hors install).

**Tester.** Bunker pose/capture/destroy ; posted bonus ×5 / speed ×3 uniquement si défenseur a un bunker in-range.

### ISSUE-V5 — Pool `tryAnnex`

**Problème.** `visited` / `queue` / `pocket` alloués jusqu’à 80 fois / attaque / tick. BFS sémantique **déjà réparée**.

**Faire.** Recette feel N39 pool only. Ne pas retoucher le seed (voisins défenseur). Océan = abort (enclave terrestre).

**Tester.** Front shape (simulate) + poche inland.

### ISSUE-V6 — `retreatBoats` / `targetSlot` après flip

**Problème.** `Navy.retreatBoats` filtre `owner[targetTile] == targetOwner`. Si la côte a flip pendant le transit, le wrap `retreatAttack` rate le transport.

**Faire.** Recette feel N49 : `launchInvasion` pose `targetSlot`. `retreatBoats` filtre l’intention ; fallback `owner[targetTile]`. Feel N53 (option A) : `Navy.step` auto-retraite si `owner[targetTile] ~= targetSlot` (sans champ = pas d’auto).

**Tester.** Transport en route, `setOwner` de la côte cible, `retreatAttack` → `beginRetreat`. Puis flip sans geste → auto N53.

### ISSUE-V7 — `findSpawn` / `claimSpawn` anti-splash

**Problème.** Spawn ignore cratère ogive / fallout chaud. Un humain peut (re)naître dans le splash.

**Faire.** Recette feel N50/N52 : `isSpawnSafe` partagé `findSpawn` + `claimSpawn` (C1+C2). Contrat B missiles inbound **inchangé**.

**Tester.** MIRV existant + capitale sous fallout → refus / autre tuile.

### ISSUE-V8 — Convoi vs PORT détruit au combat

**Problème.** `resolveTrade` no-op silencieux si le PORT destination n’existe plus.

**Faire.** Recette hardening fd1e / feel N51 option B : dans `Navy.step`, couler le `kind==2` (pas d’or). Capture de PORT = **continue** (le nouveau proprio reçoit).

**Tester.** Détruire le PORT pendant le transit → bateau retiré, or inchangé.

### ISSUE-V9 — Replication lobby 10 Hz + DataStore

**Problème.** `init.server` `replicate()` à 10 Hz en `waiting` (`StateDelta` + `UnitSnapshot` + `stats` imbriqués). `Persistence.record` → `UpdateAsync` synchrone par humain en `endMatch` + `BindToClose`.

**20K CCU.** N salons × 10 Hz FireAllClients à vide + tempête DS en fin de match.

**Faire.** Lobby/ended : 1 Hz (cadence `matchUpdate`). Dirty flag Persistence, flush 30 s, une écriture `endMatch` / `settledHumans`. Ne pas toucher au 10 Hz **playing**.

**Tester.** Hors bundle (`init.server`). Studio : 0 humain en menu = trafic bas. 8 humains `endMatch` = ≤8 writes.

### ISSUE-V10 — Embargo terrestre

**Problème.** Embargo auto à l’attaque coupe `Navy.canTrade` mais `Trade.luau` (rails/camions) ignore l’embargo.

**Faire.** Si parité OF = embargo **maritime only** : documenter dans `Trade.luau` et ne rien changer. Si embargo = arme éco totale : garder `canTrade` dans `dispatch`/`resolve` (même helper que Navy).

**Tester.** Embargo puis usine+gare : or camion 0 **seulement** si le produit tranche « total ».

### ISSUE-V11 — Client perf construction / pulses

**Problème.** `BuildingModels` : `Smoke` + `PointLight.Shadows` par usine/SAM. `Effects.conquestPulse` sans cap (contrairement à `MAX_LIVE_FLASHES`).

**Faire.** Qualité : pas de Smoke/shadows si `UserGameSettings.SavedQualityLevel` bas. Cap pulses (ex. 8 live). Pas de logique de jeu côté client.

**Tester.** `tests/client.luau` (ne pas casser le banc). Studio : rush de poses.

### ISSUE-V12 — Clés Config mortes + `justClaimed`

**Problème.** Après apply : `MAX_TILES_PER_TICK`, `FRONT_TILES_PER_CONTACT`, `DEFENSE_COST_DIVISOR`, `TRAIN_GOLD_ALLY`/`OTHER`, `BOAT_LANDING_BONUS` non lus par le runtime installé. `justClaimed` renvoie `true` sans lancer d’attaque (le client joue `attackLaunch`).

**Faire.** Commenter « mort après install » à côté de chaque clé **ou** les brancher. `justClaimed` : renvoyer `false, "Territoire revendique."` **ou** message dédié, pas un succès d’attaque.

**Tester.** P0 metrics inchangés. Client : premier clic post-spawn.

---

## Hors scope volontaire

- Merger feel `df65` / hardening `9f25` sur #39.
- Spatial hash warships (N39 hardening a des buffers recyclés — porter plus tard).
- `MODE_KEYS` mort (digits 1–4 = bâtiments). Cosmétique.
- Fallout disque = rayon **inner** seulement (OF outer = spec produit).

---

## Tests

```
./tests/run.sh
```

Client : 34 checks, dont fiche diplomatie « Traître (actif) ».  
Serveur : invariants + P0 (hash, sequence, N41 nil, N29 retry) + or plat + `removePlayer` refund + embargo auto + cap 3 transports.  
Note banc : Atomique souvent inatteignable en 6000 ticks (or plat + packing) ; Industrielle exigée.
