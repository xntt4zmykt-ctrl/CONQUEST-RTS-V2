# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 44)

Déclencheur : ouverture de la **PR #141** (`cursor/analyse-nocturne-du-codebase-4c70`) — `buildingRecPool`, `boatFree`, specs N97–N98.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-24a7`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #141**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#141. Pas d’outil Slack.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29/#32/#34/#36/#38/#41/#42/#45/#48/#51/#53/#56/#59/#62 + d425 + df65 + 2157 + 5c74 + e735 + 7c38 + 1fb3 + 5bf6 + 741d + 55ba + 4876 + cc42 + 2f5d + b62d + 69f4 + 07c6 + 2b37 + e277 + 1e43 + a963 + d74d + c786 + **4a67 passe 35** / **8f41** / **5bbf** / **de1a** / **04b6** / **5c7e** / **04e7** / **846c** / **ab04** / **bec6** / **b19e**) : ne pas merger sur cette branche sans rebase. Les numéros N40+ feel (settledHumans feel N40, seq, N52–N122…) ne sont **pas** les N40–N100 de ce rapport. Cette passe **ferme** hardening N97 (`Nukes.missileFree` / missile live) et N98 (`GameState.attackFree` / Attack record). Seq obligatoire (feel N41) et `targetSlot` (feel N49/N53) ne sont pas portés. **Pas** de `TRAIN_STOP_BONUS` dans `railIncome`. Feel N94 (`table.clear` border/coast) = N74 **déjà fermé**. N75 (scan cadran) **reste ouvert** — contrat A trop structurel. Client hardening = **34/34** (feel 35/35 — Overlay `retreating`). Payload Intent reste référence live (N82 — ne pas pooler). Persistence `UpdateAsync` **non** poolé (N6). `building.links` **unique** (N65). `boat.path` **unique** (N64). `Heap.frontier` **unique** (N98). `removePlayer` bateaux / missiles **non** poolés (GameState ne require pas Navy/Nukes).

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`. `RequestSnapshot` n’est toujours jamais `FireServer` côté client (N4). DAG : `GameState` ne `require` ni Navy, ni Nukes, ni Trade, ni Bots, ni Buildings, ni Research, ni Diplomacy, ni Placement, ni MatchLifecycle, ni IntentValidator, ni ChantierB, ni BoatFront. `Buildings`, `Research`, `Diplomacy` require déjà `GameState` ; `Placement` require Shared only — ne pas inverser. `Nukes` require `GameState` + `Buildings` (pas l’inverse). `TickMetrics` require `Config` seulement. `MatchLifecycle` require `Config` seulement. `IntentValidator` require Shared only. `MapGen` require `Config` seulement. `Trade` require `GameState` (pas l’inverse). `Navy` require `GameState` (N96, pas l’inverse). N95 (`buildingRecPool`) vit dans **GameState**. N96 (`boatFree`) vit dans **Navy**. N97 (`missileFree`) vit dans **Nukes**. N98 (`attackFree`) vit dans **GameState**. BoatFront.install appelle `GameState.acquireAttack` (pas de require nouveau).

La PR #141 a bien fermé `buildingRecPool` (N95) et `boatFree` (N96). Cette passe a **corrigé ce que #141 a spécifié** — `Nukes.launch` / `splitMirv` allouaient encore un record missile à chaque tir, et `launchAttack` / `seedBeachhead` allouaient encore un record `Attack` à chaque front :

| Bug | Gravité | Statut |
|---|---|---|
| `placeBuilding` Building record (N95) | **P3 alloc pose** | **déjà fermé** (#141, `buildingRecPool`) |
| `Navy` bateau live (N96) | **P3 alloc marine** | **déjà fermé** (#141, `boatFree`) |
| `Nukes.launch` / `splitMirv` missile live (N97) | **P3 alloc nucléaire** | **corrigé** (`missileFree` free-list) |
| `launchAttack` / `seedBeachhead` Attack (N98) | **P3 alloc combat** | **corrigé** (`attackFree` free-list) |
| `AimFront.focus` `Heap.new` + `queued={}` (N99) | **P3 alloc visee** | **ouvert** (leftover N98) |
| `Nukes.step` `table.remove` O(n) (N100) | **P3 alloc/ordre** | **ouvert** (leftover N97 ; pool le record, pas l’ordre) |
| `stepDoomsday` scan O(TILE_COUNT) (N9 / N75) | **P2 cadran** | **ouvert** (index compact — leftover N73 ; contrat A trop structurel ici) |
| `retreatBoats` filtre `owner[targetTile]` courant | **P2 marine** | **ouvert** (reste de N28 ; feel d425/df65 a la recette) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29 ; N98 pool le record, **pas** la fusion) |
| `findSpawn` ignore splash / fallout (N33) | **P3 nucléaire** | **ouvert** (feel d425/df65 a C1+C2 + `isSpawnSafe`) |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#141 + allyBuf (N72) + stripBuf (N73) + stripTerritory hashes (N74) + detonate hashes (N76) + splitMirv hashes (N77) + TickMetrics ring (N78) + snapshot arrays (N79) + reset pool (N80) + snapBuf (N81) + intentPool (N82) + notify/sound pool (N83) + rosterBuf (N84) + plunderPool (N85) + matchUpdateBuf (N86) + contextBuf (N87) + recordBuf (N88) + settledRecPool (N89) + profileBuf (N90) + metaBuf (N91) + deliveryPool (N92) + portRecPool (N93) + factoryRecPool (N94) + buildingRecPool (N95) + boatFree (N96) + missileFree (N97) + attackFree (N98).
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #141

**À merger** (`buildingRecPool` + `boatFree` + specs N97–N98), sous réserve que cette passe 44 parte avec : **`Nukes.launch` / `splitMirv` allouaient encore le record missile, et `launchAttack` / `BoatFront.seedBeachhead` allouaient encore un record Attack**.

Points encore vrais après #141 :

| Claim #141 | Réalité après passe 44 |
|---|---|
| N95 `placeBuilding` Building record | confirmé (`buildingRecPool`) |
| N96 bateau live `Navy` | confirmé (`boatFree`) |
| N97 missile live `Nukes` | **fermé ici** (rawequal `missileFree` LIFO, `engaged`/`warhead` nil, ogives uniques) |
| N98 Attack `launchAttack` / `seedBeachhead` | **fermé ici** (rawequal `attackFree` LIFO, `Heap.frontier` distinct, leftover N68 = 3 Attack) |
| N75 `stepDoomsday` scan O(TILE_COUNT) | **ouvert** |
| N33 `findSpawn` splash / fallout | **ouvert** |
| N28 retraite après flip / `targetSlot` | **ouvert** |
| N29 `seedBeachhead` no-merge | specs only, inchangé (banc N68 / N98 documente 3 Attack) |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |

`init.server.luau` et `Persistence` restent **exclus du bundle**. Le helper `MatchLifecycle` est **dans** le bundle (37 modules serveur — pas de module nouveau). `Nukes.launch` / `splitMirv` / `Nukes.step` sont **dans** le bundle. `launchAttack` / `seedBeachhead` / `releaseAttack` sont **dans** le bundle. `Heap.frontier` **reste unique** (N98). `queued` **reste unique**. Overlay lit le snapshot N52, pas le record live missile. `removePlayer` missiles **sans** `missileFree` (cycle GameState→Nukes — leftover N97, ticket N100 ordre prioritaire). `BoatFront.parkedBuf` **ne push pas** (gare live). AimFront `Heap.new` encore alloué (N99). `Nukes.step` `table.remove` encore O(n) (N100).

PR feel / visual ne doivent pas être mergées par-dessus #16/#141 sans rebase. Seq / `targetSlot` / hover `SpawnHint` / Overlay `retreating` / `TRAIN_STOP_BONUS` HUD / `previewCtx` restent feel-only.

On peut fermer #17, #18, #20, #23, #25, #27, #30, #31, #33, #35, #37, #40, #43, #46, #49, #52, #55, #58, #60, #63, #66, #70, #73, #76, #80, #83, #85, #88, #91, #95, #98, #102, #104, #109, #112, #116, #119, #123, #127, #130, #135, #138 et #141 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| missile live `Nukes` (N97) | `Nukes.luau`, `tests/simulate.luau` | Free-list `Nukes.missileFree` (contrat A, recette `boatFree` N96). `acquireMissile` pop/crée, overwrite `id/slot/kind/x/y/sx/sy/tx/ty/progress/speed`, **nil** `engaged` / `warhead` / `radius` / `troopKill` (sauf ogive : `warhead=true` + `radius` + `troopKill`). `despawnMissile` push. Couvre **launch + splitMirv + 3 table.remove** de `Nukes.step`. Scission : despawn porteur **avant** acquire ogives (snapshot des champs) — première ogive `rawequal` le porteur. Pool module survit à `GameState.new`. Ne require **pas** depuis GameState. Recette spec #141 N97. Banc ATOM + MIRV **verts**. **Ne pas** pooler depuis `removePlayer`. **Ne pas** changer `missileSnapBuf`. |
| Attack record (N98) | `GameState.luau`, `BoatFront.luau`, `ChantierB.luau`, `Diplomacy.luau`, `tests/simulate.luau` | Free-list `GameState.attackFree` (contrat A). `acquireAttack` pop/crée, `frontier = Heap.new()` **neuf**, `queued = {}` neuf, overwrite `attacker` / `target` / `troops` / `isBeachhead` / `sourceTile` / `retreatAt` (nil si terre) / `aimX` / `aimY`. `releaseAttack` push au despawn. Couvre `launchAttack` (nouveau couple) + `seedBeachhead` (base + wrap BoatFront). `BoatFront.parkedBuf` **ne push pas**. Abort frontier vide → `freeAttack` sans insert. Recette spec #141 N98. Banc land rawequal + 2 ponts leftover 3 **verts**. **Ne pas** fusionner N29. **Ne pas** pooler le Heap. |

**Non modifié (volontaire) :** N1–N96 restant, reste de N28 (`targetSlot`). N10.8. Cap beachheads (N5 / N29). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` / `require(Placement)` / `require(MatchLifecycle)` / `require(IntentValidator)` / `require(ChantierB)` depuis GameState. Pas de contrat C spawn (N33). Pas de seq obligatoire (feel N41). Pas de spatial hash warships. Buffer `defense` **alloué** mais plus écrit. Pas de `TRAIN_STOP_BONUS` dans `railIncome`. Scan cadran encore O(carte) (N9 / N75). AimFront `Heap.new` encore alloué (N99). `Nukes.step` `table.remove` encore O(n) (N100). `removePlayer` bateaux / missiles **non** poolés (cycle). Pas de `retreating` Overlay. Debit `captures`/`pops` **non** remplacé par feel `guard < 80`. `PlacementPreview` / `tests/client.luau` **non** édités. Skip AFK cadran **conservé**. Payload Intent = référence live (N82). Persistence `UpdateAsync` **non** poolé (N6). `building.links` unique (N65). `boat.path` unique (N64). `Heap.frontier` unique (N98). Pools PORT / FACTORY / Building / missile / Attack **non fusionnés**.

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead + parkedBuf + acquireAttack), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + **captures < 80 et pops < 160**). Attack record **poolé** (N98). `releaseAttack` au despawn (retraite, clash, collapse, `removePlayer`, pacte). `Heap.frontier` unique.
- **Posted** : bunkers / SAM / SILO / FACTORY / PORT / NAVAL_BASE / `buildingsBySlot` inchangés vs #141. Record Building **poolé** (N95). Sidecars PORT/FACTORY **poolés** (N93/N94).
- **Têtes de pont** = `BoatFront.seedBeachhead` via `acquireAttack` (N98) : frontier = **voisins encore à la cible**, flag `isBeachhead`. `launchAttack` gare les beachheads dans `parkedBuf` **sans** `releaseAttack`. Insert sémantique encore un Attack par débarquement (N29).
- **Pacte vivant** = `areAllied` : deux sens **et** `tick < expiry` (ou `true` legacy tests). `Diplomacy.accept` `releaseAttack` les fronts du couple.
- **Porte-avions** = `syncCarriers` événementiel + spawn via `navalBasesBySlot` + `acquireBoat` (N96).
- **Commerce maritime** = `portsByTile` incrémental + `spawnTradeShips` `acquireBoat` (N96). Vague plafonnée avant flatten.
- **Nucléaire** = `Nukes.missileFree` (N97). Overlay lit `snapshotMissiles` (N52), pas le live. `removePlayer` missiles **sans** free-list (cycle).
- **Réplication** : inchangée vs #141.
- **DataStore** : `settledHumans` poolé (N89). `endMatchRecords` poolé (N88). Persistence `UpdateAsync` **non** poolé (N6).
- **Require** : DAG. Pas de cycle. N97 dans Nukes. N98 dans GameState. Ne pas `require(Nukes)` depuis GameState.

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N100 restent ouverts** sauf N19 partiel, N21 **fermé**, N24 remplacé par N31 (**fermé**), N30–N32 **fermés**, N34–N74 **fermés**, N76–N98 **fermés**. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + N75 + le reste de N28 / N29 / N33.

---

### ISSUE-N28 — `retreatBoats` / `retreatAttack` après flip de côte (reste)

**Priorité :** P2 combat / comptabilité navale. **Partiel :** inbound `removePlayer` **fermé** en passe 8.

**Problème restant :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetSlot`. Conséquences encore vraies :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers).
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

Feel d425 (N49) + df65 (N53) : `launchInvasion` pose `targetSlot`, `retreatBoats` filtre l’intention (fallback `owner[targetTile]`), wrap 2e geste rappelle les tardifs, `Navy.step` auto-retraite si `owner[targetTile] ~= targetSlot`. **Porter, ne pas réinventer.** Distinct de N10.8 et du fix inbound. Distinct de N96 (`boatFree` — **déjà fermé**). Distinct de N97/N98 (**déjà fermés**). Distinct de N99/N100.

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite.

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste, trancher si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`. Recette feel : branche `d425` / `df65`. `acquireBoat` doit overwrite `targetSlot` (N96 — leftover `targetSlot` d’un convoi recyclé en transport = retraite du mauvais camp).

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N22). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % déjà livré). Ne pas recâbler N35 (convois, `kind==2`). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).** Ne pas porter AimFront ni seq. Ne pas recâbler N50–N100. Ne pas casser `boatFree` (N96) : tout nouveau champ **doit** être écrit dans `acquireBoat`.

---

### ISSUE-N29 — `seedBeachhead` ne fusionne plus le couple naval

**Priorité :** P2 combat / cap.

**Problème :** `GameState.seedBeachhead` de base fusionnait `(attacker, target)`. `BoatFront.install` **remplace** la fonction et `table.insert` toujours un nouvel `Attack` `isBeachhead` (désormais via `acquireAttack` N98 — leftover **sémantique**, pas alloc). Deux débarquements vs le même défenseur = deux fronts, pools de troupes séparés, deux consommations de debit `captures < 80`. Combiné à N5 (parking hors cap land), un joueur peut tenir 2 beachheads + 1 terre = 3 offensives alors que `MAX_ACTIVE_ATTACKS_PER_PLAYER = 2`. Le banc N68 / N98 **documente** ce 3 = 2 ponts + 1 terre (ne pas le « corriger » dans N68/N98).

**Pourquoi 20K CCU :** late-game invasions multiples. Ce n’est pas N11 (`MAX_TILES_PER_TICK` mort) ni N98 (leftover alloc Attack, **déjà fermé**) : ici le **nombre de tas** explose, chacun avec son `while captures < 80`.

**Worker :**

1. Confirmer le contrat OpenFront : **un** front naval par couple `(attacker, target)`, distinct du front terre. Si oui : dans `BoatFront.seedBeachhead`, trouver un `isBeachhead` existant du couple, ajouter `troops`, enfiler les nouveaux voisins, **freeAttack** le record acquis non inséré, return. Si le tas est vide après enqueue, refund + `freeAttack` comme aujourd’hui.
2. Si le produit **veut** les griffes multiples : documenter dans Config, et **compter** les beachheads dans le cap (fermer N5 dans le même PR). Pas les deux à la fois.
3. Test : deux `seedBeachhead` même couple → `#attacks == 1` et `troops` somme **ou** (si multi-prong assumé) `launchAttack` refuse au-delà du cap y compris parked. Le banc N68 / N98 (3 Attack) devra alors être mis à jour.
4. Fichiers : `BoatFront.luau`, éventuellement `GameState.launchAttack` / wrapper parking, `tests/simulate.luau`. Passer par `acquireAttack` / `freeAttack` (N98).

**Contraintes :** ne pas fusionner beachhead avec front terre (régression BoatFront / aim). Ne pas changer `attackTilesPerTick`. Ne pas mixer avec N28 (bateaux inbound / targetSlot). Ne pas mixer avec N68 (`parkedBuf` — leftover alloc, **déjà fermé**). Ne pas mixer avec N98 (pool Attack — leftover alloc, **déjà fermé**). **N29 hardening ≠ N29 feel (seq avant apply).** Ne pas recâbler N99/N100.

---

### ISSUE-N33 — `findSpawn` ignore fallout et splash d’une frappe tiers

**Priorité :** P3 nucléaire / spawn. Reste du contrat C de l’ancien N30.

**Problème :** après le contrat B (ogive visée sur le disparu **annulée**), il reste : une frappe **déjà visée sur un voisin** dont le cratère recouvre l’ancien capital / le `SPAWN_RADIUS` de `findSpawn`. `addPlayer` choisit un disque terrestre libre, sans lire `state.missiles` ni `state.fallout`. L’héritier spawn, `Nukes.step` explose, SAM de l’héritier n’existait pas au `engaged`.

Feel d425 (N50) + df65 (N52) + 2157 (N55 isolation, ticket suivant) : `isSpawnSafe` partagé `findSpawn` / `claimSpawn`, refuse crater ogive **et** `state.fallout[index] > tick`. **Porter, ne pas réinventer.** Contrat B (N30) déjà livré ici : ne pas l’ouvrir. Isolation disque clic (feel N55) = ticket **feel**, pas celui-ci. N97 (missile live pool) **fermé** : ne pas le mixer. Overlay lit le snapshot, pas le live.

**Pourquoi 20K CCU :** moins chaud que N30 (il faut un voisin sous missile + spawn coincé dans le rayon).

**Worker :**

1. Ne **pas** rouvrir le contrat B. Options : (C1) `findSpawn` refuse un centre dont un missile en vol a `toIndex(floor(tx),floor(ty))` à distance `NUKE_STATS[kind].radius` (ogive : `missile.radius`) ; (C2) `findSpawn` refuse `state.fallout[index] > tick` ; (C3) documenter « le territoire, pas le joueur » pour le splash tiers. Feel a choisi C1+C2 via `isSpawnSafe`.
2. Test : A tire sur C (capitale), `removePlayer(B)`, forcer le spawn de l’héritier dans le rayon (tuiles libres), `Nukes.step`. Assert selon C1/C2/C3.
3. Fichiers : `GameState.findSpawn` / `addPlayer`, éventuellement `Nukes`, `tests/simulate.luau`. Recette feel : branche `d425` / `df65`.

**Contraintes :** ne pas annuler une frappe tiers (régression `nuke third-party`). Ne pas rembourser l’or. Pas de RemoteFunction. Rayon lu depuis `NUKE_STATS` / `missile.radius`, pas une constante magique. Ne pas porter isolation clic (feel N55) dans le même PR. Ne pas recâbler N50–N100. Ne pas mixer N76 (`tilesBeforeBuf` — **déjà fermé**) ni N77 (`mirvTxBuf` — **déjà fermé**) ni N97 (missile live, **déjà fermé**).

---

### ISSUE-N75 — `stepDoomsday` scanne encore `0..TILE_COUNT-1` par camp qui saigne

**Priorité :** P2 cadran / perf. Leftover explicite de N9 et de N73. Distinct de N73 (`stripBuf`, **déjà fermé**) et de N74 (`stripTerritory` hashes, **déjà fermé**). Ne pas toucher `rotQuota`. **N75 hardening ≠ N75 feel historique (`pricesFor`).** Visual V13 décrit le même trou. **Non livré en passe 44** : contrat A (`tilesBySlot` maintenu dans `setOwner`) est un index d’autorité — un déréglage vs `owner` pourrit le mauvais camp. Trop structurel pour un correctif « sûr » à côté de N97/N98.

**Problème :** même avec `stripBuf` recyclé, chaque slot sous quota (10 Hz, late-game plusieurs camps) re-scanne `Config.TILE_COUNT` (40 960) jusqu’à `quota * 4` hits. Un shard 18 factions en cadran = jusqu’à ~17 scans linéaires / tick. Il n’existe pas d’index compact tuiles-par-slot : `ps.tiles` est un compteur, `ps.border` / `ps.coast` ne couvrent pas l’intérieur. N73 a volontairement laissé ce scan.

**Pourquoi 20K CCU :** leftover N9. Late-game cadran = le tick le plus cher du shard (hors combat). Recycle de la porteuse (N73) n’enlève pas les 40k reads `buffer.readu8`. Un index compact ramène le rot à O(tuiles du camp) au lieu de O(carte).

**Worker :**

1. Choisir un contrat : (A) `tilesBySlot[slot] = { number }` array compact, maintenu dans `setOwner` (insert au claim, swap-pop au loss) — `stepDoomsday` itère `1..ps.tiles` au lieu de `0..TILE_COUNT-1` ; (B) reservoir bitset 40 960 / 8 recyclé, rebuild seulement si dirty ; (C) documenter « scan O(carte) accepté, N9 fermé sans code ». **Un seul.** Feel / visual n’ont pas encore fermé V13. Pas de RemoteFunction.
2. Si A : `setOwner` est le **seul** writer. Capture, nuke crater, strip, collapse, spawn doivent tous passer par là. Test : 6000 ticks, `ps.tiles == #tilesBySlot[slot]`, rot n’émet plus de tuile `owner ~= slot`. Banc N73 / N74 **verts**.
3. Fichiers : `GameState.setOwner` + `ChantierB.stepDoomsday` (via `install()`), `tests/simulate.luau`. Pas de require GameState ↔ ChantierB nouveau.

**Contraintes :** pas de RemoteFunction. **N75 hardening ≠ N73 (`stripBuf`, déjà fait) ≠ N74 (`border`/`coast`, **déjà fait**) ≠ N76–N98 (déjà faits) ≠ N9 (umbrella — ce ticket **ferme** N9 si A ou C).** Ne pas changer `rotQuota` / drain / WARN. Overlay n’itère pas l’index. Un index déréglé vs `owner` = pourriture du mauvais camp. Ne pas `require(ChantierB)` depuis GameState. Ne pas mixer avec N99 (AimFront Heap) ni N100 (ordre missiles).

---

### ISSUE-N97 — `Nukes.launch` / `splitMirv` missile live — **FERMÉ** (passe 44)

`Nukes.missileFree` (contrat A, recette `boatFree` N96). `acquireMissile` / `despawnMissile`. Launch ATOM + splitMirv + 3 despawn de `Nukes.step`. `engaged` / `warhead` / `radius` / `troopKill` nil sauf ogive. Scission : despawn porteur **avant** acquire. Banc : rawequal ATOM, ogive `rawequal` porteur, 2e porteur `warhead == nil`, ogives live non aliasées. Ne pas rouvrir. Un leftover `engaged` = SAM skip (banc `tryIntercept`). Leftover `removePlayer` table.remove **sans** free-list (cycle GameState→Nukes — pas ticket, rare). Leftover `table.remove` O(n) → N100. Leftover AimFront Heap → N99. **Ne pas** pooler depuis `removePlayer`. **Ne pas** changer `missileSnapBuf`.

---

### ISSUE-N98 — `launchAttack` / `seedBeachhead` Attack — **FERMÉ** (passe 44)

`GameState.attackFree` (contrat A). `acquireAttack` / `releaseAttack` / `freeAttack`. `Heap.frontier` unique, `queued` unique. `BoatFront.seedBeachhead` via le helper. `parkedBuf` **ne push pas**. Abort frontier vide → `freeAttack`. Banc : rawequal land, `retreatAt == nil`, `isBeachhead` nil terre, 2 ponts leftover 3 (N68 / N29 **ouverts**). Ne pas rouvrir. Un leftover `isBeachhead` sur un front terre = park fantôme (banc N68). Leftover AimFront `Heap.new` → N99. Leftover fusion couple → N29. **Ne pas** pooler le Heap. **Ne pas** « fixer » N29 dans le même PR.

---

### ISSUE-N99 — `AimFront.focus` abandonne `Heap.new` + `queued = {}` à chaque visée

**Priorité :** P3 alloc visée. Leftover explicite de N98 (`attackFree` recycle le record Attack ; `AimFront.focus` jette encore le Heap + le hash `queued` acquis). Distinct de N98 (pool Attack, **fermé**, frontier unique **entre vies** d’un Attack). Distinct de N68 (`parkedBuf`). **N99 hardening ≠ N99 feel historique.** `Heap.clear` existe déjà (`Heap.luau`) et le banc N68 l’utilise. N98 a volontairement laissé `Heap.new()` à **chaque acquire** (alias interdit) : c’est **pendant la vie** du front que focus ré-alloue.

**Problème :** `SystemsBootstrap.launchAttack` appelle `AimFront.focus` si `ps.aimTile` est un nombre et que le couple n’existait pas. `AimFront.focus` fait `atk.frontier = Heap.new()` et `atk.queued = {}` — le Heap tout juste créé par `acquireAttack` (N98) est abandonné, plus deux tableaux `values`/`costs`. Un clash 8 humains qui cliquent une visée = autant d’allocs Heap par nouveau front, **en plus** de l’acquire. `RailPath` alloue aussi un `Heap.new` par refresh (événementiel, ticket suivant si restant).

**Pourquoi 20K CCU :** leftover naturel une fois Attack poolé. Recycle in-place `Heap.clear(atk.frontier)` + `table.clear(atk.queued)` pendant la vie du record. Pas d’autorité si la file **repart vide**. Un leftover `queued[index]=true` d’une visée précédente = tuile fantôme au debit `captures < 80` (invariants fronts).

**Worker :**

1. Dans `AimFront.focus`, `Heap.clear(atk.frontier)` + `table.clear(atk.queued)` au lieu de `Heap.new()` / `{}`. Ne **pas** réutiliser le Heap **entre** deux vies d’Attack (N98 — acquire reste `Heap.new()` neuf). Pas de RemoteFunction. Rester dans `AimFront.luau`. `SystemsBootstrap` / `GameState.acquireAttack` inchangés.
2. Ne pas changer debit `captures`/`pops`, `parkedBuf` (N68), merge couple (N29). Banc N68 / N98 / aim reinforce **verts**.
3. Test : `ps.aimTile` posé → `launchAttack` → `rawequal(atk.frontier, frontierBeforeFocus)` (identité Heap acquire), `next(queued)` seulement les tuiles de la visée. Second `launchAttack` (renfort) ne recrée pas de Heap. Client **34/34**. 6000 ticks.
4. Fichiers : `AimFront.luau` (`focus`), `tests/simulate.luau` (bloc court après N98). `GameState.luau` / `BoatFront.luau` / `Nukes.luau` / `init.server` inchangés. Pas de recette feel.

**Contraintes :** pas de RemoteFunction. **N99 hardening ≠ N98 (Attack pool, déjà fait) ≠ N68 (parkedBuf, déjà fait) ≠ N29 (no-merge, ouvert).** Overlay n’écrit pas `frontier`. Un leftover `queued` = debit du mauvais contact (banc aim reinforce). Ne pas mixer N28 / N75 / N100. Ne pas pooler le Heap **entre** Attacks. Ne pas « fixer » N29.

---

### ISSUE-N100 — `Nukes.step` `table.remove` encore O(n) sur `state.missiles`

**Priorité :** P3 ordre nucléaire. Leftover explicite de N97 (`missileFree` recycle le **record** ; l’array live `state.missiles` `table.remove` encore en reverse-iter). Distinct de N97 (pool record, **fermé**). Distinct de N52 (`missileSnapBuf`, **fermé**). Distinct de N76/N77 (hashes, **fermés**). **N100 hardening ≠ N100 feel historique.** N97 a volontairement laissé l’ordre reverse-iter : c’est **ce** ticket.

**Problème :** `Nukes.step` itère `for i = #state.missiles, 1, -1` et `despawnMissile` fait `table.remove(state.missiles, i)` (shift O(n)). Un clash 140 explosions observées / 600 s, MIRV 8 ogives : jusqu’à ~O(n²) copies de pointeurs par tick de saturation. Overlay lit le snapshot N52, pas l’ordre live. Swap-pop (`missiles[i] = missiles[#] ; missiles[#]=nil`) casse l’ordre mais pas l’autorité (chaque missile avance tout seul). Compact périodique = autre contrat.

**Pourquoi 20K CCU :** leftover naturel une fois le record poolé. 8 humains × silos × MIRV = pic d’array plus cher que l’alloc record. Pas d’autorité si **tous** les missiles du tick sont visités une fois.

**Worker :**

1. Choisir un contrat : (A) swap-pop dans `despawnMissile` (ordre live indifférent, reverse-iter devient while) ; (B) compact `writeHead` une fois par `Nukes.step` (holes nil, truncate) ; (C) documenter « reverse-iter + table.remove accepté, N100 fermé sans code ». **Un seul.** Recette (A) recommandée. Pool `missileFree` **inchangé** (push le record). Pas de RemoteFunction. Rester dans `Nukes.luau`. `GameState.removePlayer` **inchangé**.
2. Ne pas changer `tryIntercept`, contrat B inbound, `detonate`, `SAM_INTERCEPT_CHANCE`, scission despawn-avant-split (N97). Banc N76 / N77 / N97 / inbound nuke / `tryIntercept` **doivent rester verts**. Ogives **uniques**.
3. Test : launch 3 ATOM → intercept/detonate dans n’importe quel ordre → `#missiles == 0`, `missileFree` a 3, 2e launch rawequal (N97). MIRV scission + ogives : pas d’alias live. Client **34/34**. 6000 ticks.
4. Fichiers : `Nukes.luau` (`despawnMissile` / `Nukes.step`), `tests/simulate.luau` (bloc court après N99). `GameState.luau` / `Navy.luau` / `init.server` inchangés. Pas de recette feel.

**Contraintes :** pas de RemoteFunction. **N100 hardening ≠ N97 (record, déjà fait) ≠ N52 (snapshot, déjà fait) ≠ N76/N77 (déjà faits).** Overlay lit le snapshot N52, pas l’ordre live. Un missile sauté = ogive fantôme (banc MIRV / N97). Ne pas mixer N28 / N33 / N75 / N99. Ne pas pooler depuis `removePlayer`. Ne pas changer `missileSnapBuf`.

---

## 5b. N1–N100 encore ouverts ou fermés (passes 2–44)

| ID | Titre | Prio | Note passe 44 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + `SAM_INTERCEPT_CHANCE` 0.55→1 ; clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz ; … ; Building → **N95 fermé** ; bateau → **N96 fermé** ; missile → **N97 fermé** ; Attack → **N98 fermé** ; AimFront Heap → **N99** ; missiles ordre → **N100** |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` **jamais** `FireServer` côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | park `isBeachhead` → hors cap land ; **2 beachheads parked + 1 terre = 3** — voir N29 ; alloc Attack → **N98 fermé** |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions. **Ne pas** pooler. |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | refund + retraite `RETREAT_LOSS` alignés ; wrap vivant → **N67 fermé** ; `collapseFaction` remaining → **N69 fermé** ; Attack record → **N98 fermé** |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | timers slot maintenant purgés ; liste temporaire → **N73 fermé** ; hashes spawn → **N74 fermé** ; le scan rot est toujours O(tuiles) → **N75** |
| N10 | Divers P3 | P3 | donations gold sans plafond ; `pendingMode` last-writer ; … ; missile live → **N97 fermé** ; Attack → **N98 fermé** ; AimFront Heap → **N99** |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | debit = `attackTilesPerTick` × speed, **captures<80 pops<160** |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 observé) | P1 | `Bots.spawnAll` wrap + `Tribes.spawnAll(6)` hors budget |
| N13–N27 | (ère / heap / embargo / rail HUD / QuickChat / warships / …) | — | inchangés vs passe 43 ; voir rapport #141 |
| N28 | `retreatBoats` après flip | P2 | **partiel** : inbound fermé passe 8 ; `targetSlot` ouvert (recette feel N49/N53). Si porté : overwrite dans `acquireBoat` (N96). |
| N29 | `seedBeachhead` no-merge | P2 | specs only. Banc N68 / N98 documente 3 Attack (2 ponts + terre). Distinct de N98 (alloc, **fermé**). |
| N30–N32 | inbound missile / pool BFS / convoi | P2 | **fermés** |
| N33 | `findSpawn` splash / fallout | P3 | specs only (recette feel N50/N52) |
| N34–N74 | (index / snapshots / HUD / diplomatie / bots / combat wrap / pose) | — | **tous fermés** (passes 11–32). Voir rapport #102. |
| N75 | `stepDoomsday` scan O(TILE_COUNT) | P2 | specs only. Leftover N9 / N73. Ferme N9 si contrat A ou C. **Non livré ici** (A trop structurel). |
| N76–N96 | detonate / MIRV coords / TickMetrics / Intent / notify / roster / plunder / MatchUpdate / context / gravure / settled / profile / mapMeta / dispatch / portRec / factoryRec / buildingRec / boatFree | P3 | **fermés** (passes 33–43) |
| N97 | missile live `Nukes` | P3 | **fermé**. Leftover N52/N96. `engaged`/`warhead` nil. Ordre array → **N100**. |
| N98 | Attack record `launchAttack` / `seedBeachhead` | P3 | **fermé**. Leftover N67/N29. `Heap.frontier` unique. AimFront Heap pendant la vie → **N99**. |
| N99 | `AimFront.focus` Heap/queued | P3 | specs only. Leftover N98. `Heap.clear` existe. |
| N100 | `Nukes.step` `table.remove` O(n) | P3 | specs only. Leftover N97. Swap-pop ou compact. |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu ; disconnect mid-match **vivant** = `Persistence.record(..., false)` 0 XP ; wrap `launchAttack` n’applique `AimFront.focus` que si le couple n’existait pas (N99) ; spatial hash warships volontairement non fait ; `clearPlayer` reste `table.remove` ; payload Intent = référence live (N82) ; `{ index = … }` RemoteEvent = possession ; `MapGen.countByBiome` encore alloué (test-only) ; `removePlayer` bateaux/missiles **sans** free-list (cycle, rare vs 10 Hz spawn) ; `RailPath` `Heap.new` par refresh (événementiel — leftover N99 si restant).

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
| `TRAIN_STOP_BONUS` | (Config) | (apply) | **non** sur cette ligne |
| `NUKE_STATS[ATOM].radius` | 9 | 9 | oui (`detonate` — N76) |
| `NUKE_STATS[MIRV].warheads` | 6 | 6→**8** apply | oui (`splitMirv` — N77 ; ogives live → **N97 fermé**) |

---

## 7. Preuve tests

```
./tests/run.sh  → exit 0
bundle server : 37 modules
Serveur : Tous les invariants tiennent.
  … gardes #17–#141 inchangés …
  building pool : rawequal index, links distinct (N95)
  boat pool : rawequal convoi / transport / carrier (N96)
  missile pool : rawequal ATOM / ogive MIRV (N97)
  attack pool : rawequal land, 2 ponts leftover 3 (N98)
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 captures=80 pops=160
  factions : 18
  metrics : ticks=6000 avgChanged=8.9 p95Changed=19 maxChanged=479 avgTickMs=0.37 p95TickMs=0.86
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe44.log`

---

## 8. Instructions worker (si reprise)

- Vérité runtime d’équilibrage = `ChantierB.apply(Config)` après `SystemsBootstrap.install()`, PAS `Config.luau` seul.
- Combat vivant = patches ChantierB, pas `GameState.stepAttacks` (sauf `returnCommittedTroops` et `retreatAttack`, partagés). Debit **captures < 80 / pops < 160** (pas feel `guard < 80`). Despawn Attack = `self:releaseAttack(i)` (pas `table.remove` nu). `BoatFront.parkedBuf` **sans** `releaseAttack`.
- `areAllied` = deux sens **et** expiry. Ne pas revenir à un test `~= nil`. Bots / chat / tribus : **jamais** `alliances[slot][other]` comme vérité.
- `retreatAttack` = **tous** les fronts du couple. Ne pas revenir à un `return` au premier match.
- Cote déjà nôtre ≠ retraite. Allié en mer = toujours retraite 25 % (N10.8). Inbound disparu = 100 % (comme front terre).
- Purge inbound d’un slot = **dans `removePlayer`**, pas seulement dans `Diplomacy.step`. Inclut cadran + colis + **transports** + **missiles** + **convois kind==2** (avant `setOwner`).
- Ne pas `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` / `require(Placement)` / `require(MatchLifecycle)` / `require(IntentValidator)` / `require(ChantierB)` depuis GameState (cycle).
- Building live : `buildingRecPool[index]` (N95). `links` neuf à chaque pose (N65). Destroy nil l’index live. Ne pas fusionner avec `portRecPool` / `factoryRecPool`.
- Bateau live : `Navy.boatFree` (N96). `acquireBoat` overwrite + `_sink` nil. `despawnBoat` push. `path` unique (N64). Tout nouveau champ (N28 `targetSlot`) **doit** être écrit dans `acquireBoat`. Ne pas `require` Navy depuis GameState.
- Missile live : `Nukes.missileFree` (N97). `acquireMissile` overwrite + `engaged`/`warhead` nil (sauf ogive). Despawn porteur **avant** split. `path` N/A. Ne pas `require` Nukes depuis GameState.
- Attack live : `GameState.attackFree` (N98). `acquireAttack` Heap neuf + queued neuf. `releaseAttack` au despawn. `freeAttack` si abort. BoatFront wrap via le helper. Ne pas pooler `Heap.frontier`.
- Notify / sfx : `eventPool` / `soundPool` (N83). Overlay lit tout de suite.
- File d’intents : `IntentValidator.enqueue` réécrit `intentPool[n]` (N82). **Payload = référence live — ne pas pooler**.
- `init.server` / `Persistence` restent hors bundle.
- Ne pas casser le client 34/34.
- Ligne feel : rebase sur cette passe avant cherry-pick, sinon perte `missileFree` / `attackFree`. Cherry-pick seq obligatoire (N41 feel) et `targetSlot` (N49 feel) seulement — et overwrite `targetSlot` dans `acquireBoat`. **Ne pas** porter `retreating` Overlay (feel N56). **Ne pas** porter `TRAIN_STOP_BONUS` HUD. **Ne pas** porter feel `guard < 80`. Client feel = 35/35 ; client hardening = **34/34**.
