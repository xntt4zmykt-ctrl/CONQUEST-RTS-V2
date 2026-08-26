# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 46)

Déclencheur : ouverture de la **PR #149** (`cursor/analyse-nocturne-du-codebase-f593`) — `Heap.clear` visée, swap-pop missiles, specs N101–N102.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-0744`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #149**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#149. Pas d’outil Slack.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29/#32/#34/#36/#38/#41/#42/#45/#48/#51/#53/#56/#59/#62 + d425 + df65 + 2157 + 5c74 + e735 + 7c38 + 1fb3 + 5bf6 + 741d + 55ba + 4876 + cc42 + 2f5d + b62d + 69f4 + 07c6 + 2b37 + e277 + 1e43 + a963 + d74d + c786 + **4a67** / **8f41** / **5bbf** / **de1a** / **04b6** / **5c7e** / **04e7** / **846c** / **ab04** / **bec6** / **b19e** / **4d8e** / **71f0**) : ne pas merger sur cette branche sans rebase. Les numéros N40+ feel (settledHumans feel N40, seq, N52–N124…) ne sont **pas** les N40–N104 de ce rapport. Cette passe **ferme** hardening N101 (`RailPath.find` Heap/hashes) et N102 (`releaseAttack` swap-pop). Seq obligatoire (feel N41) et `targetSlot` (feel N49/N53) ne sont pas portés. **Pas** de `TRAIN_STOP_BONUS` dans `railIncome`. Feel N94 (`table.clear` border/coast) = N74 **déjà fermé**. N75 (scan cadran) **reste ouvert** — contrat A trop structurel. Client hardening = **34/34** (feel 35/35 — Overlay `retreating`). Payload Intent reste référence live (N82 — ne pas pooler). Persistence `UpdateAsync` **non** poolé (N6). `building.links` **unique** (N65). `boat.path` **unique** (N64). `Heap.frontier` **unique** (N98) **et** identité pendant la vie du front (N99). Path `RailPath.find` **unique** (N101). `removePlayer` bateaux / missiles **non** poolés (GameState ne require pas Navy/Nukes). `BoatFront.parkedBuf` **sans** `releaseAttack` (gare live, encore `table.remove` — N104).

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`. `RequestSnapshot` n’est toujours jamais `FireServer` côté client (N4). DAG : `GameState` ne `require` ni Navy, ni Nukes, ni Trade, ni Bots, ni Buildings, ni Research, ni Diplomacy, ni Placement, ni MatchLifecycle, ni IntentValidator, ni ChantierB, ni BoatFront. `Buildings`, `Research`, `Diplomacy` require déjà `GameState` ; `Placement` require Shared only — ne pas inverser. `Nukes` require `GameState` + `Buildings` (pas l’inverse). `TickMetrics` require `Config` seulement. `MatchLifecycle` require `Config` seulement. `IntentValidator` require Shared only. `MapGen` require `Config` seulement. `Trade` require `GameState` (pas l’inverse). `Navy` require `GameState` (N96, pas l’inverse). N95 (`buildingRecPool`) vit dans **GameState**. N96 (`boatFree`) vit dans **Navy**. N97 (`missileFree`) vit dans **Nukes**. N98 (`attackFree`) vit dans **GameState**. N99 (`Heap.clear`) vit dans **AimFront**. N100 (`despawnMissile` swap-pop) vit dans **Nukes**. N101 (`searchHeap`) vit dans **RailPath**. N102 (`releaseAttack` swap-pop) vit dans **GameState** (callers ChantierB / Diplomacy / `removePlayer`). BoatFront.install appelle `GameState.acquireAttack` (pas de require nouveau). `RailPath` require `Heap` déjà — pas de require nouveau.

La PR #149 a bien fermé `AimFront.focus` `Heap.clear` (N99) et `Nukes.step` swap-pop (N100). Cette passe a **corrigé ce que #149 a spécifié** — `RailPath.find` jetait encore un Heap + trois hashes, et `releaseAttack` `table.remove` encore en O(n) :

| Bug | Gravité | Statut |
|---|---|---|
| `placeBuilding` Building record (N95) | **P3 alloc pose** | **déjà fermé** (#141, `buildingRecPool`) |
| `Navy` bateau live (N96) | **P3 alloc marine** | **déjà fermé** (#141, `boatFree`) |
| `Nukes.launch` / `splitMirv` missile live (N97) | **P3 alloc nucléaire** | **déjà fermé** (#145, `missileFree`) |
| `launchAttack` / `seedBeachhead` Attack (N98) | **P3 alloc combat** | **déjà fermé** (#145, `attackFree`) |
| `AimFront.focus` `Heap.new` + `queued={}` (N99) | **P3 alloc visee** | **déjà fermé** (#149, `Heap.clear`) |
| `Nukes.step` `table.remove` O(n) (N100) | **P3 alloc/ordre** | **déjà fermé** (#149, swap-pop) |
| `RailPath.find` `Heap.new` + hashes (N101) | **P3 alloc voies** | **corrigé** (`searchHeap` + `table.clear`) |
| `GameState.releaseAttack` `table.remove` O(n) (N102) | **P3 alloc/ordre** | **corrigé** (swap-pop + while callers) |
| `RailPath.runs` records (N103) | **P3 alloc voies** | **ouvert** (leftover N101) |
| `BoatFront` park `table.remove` (N104) | **P3 alloc/ordre** | **ouvert** (leftover N102) |
| `stepDoomsday` scan O(TILE_COUNT) (N9 / N75) | **P2 cadran** | **ouvert** (index compact — leftover N73 ; contrat A trop structurel ici) |
| `retreatBoats` filtre `owner[targetTile]` courant | **P2 marine** | **ouvert** (reste de N28 ; feel d425/df65 a la recette) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29 ; N98 pool le record, **pas** la fusion) |
| `findSpawn` ignore splash / fallout (N33) | **P3 nucléaire** | **ouvert** (feel d425/df65 a C1+C2 + `isSpawnSafe`) |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#149 + allyBuf (N72) + stripBuf (N73) + stripTerritory hashes (N74) + detonate hashes (N76) + splitMirv hashes (N77) + TickMetrics ring (N78) + snapshot arrays (N79) + reset pool (N80) + snapBuf (N81) + intentPool (N82) + notify/sound pool (N83) + rosterBuf (N84) + plunderPool (N85) + matchUpdateBuf (N86) + contextBuf (N87) + recordBuf (N88) + settledRecPool (N89) + profileBuf (N90) + metaBuf (N91) + deliveryPool (N92) + portRecPool (N93) + factoryRecPool (N94) + buildingRecPool (N95) + boatFree (N96) + missileFree (N97) + attackFree (N98) + AimFront Heap (N99) + swap-pop missiles (N100) + RailPath Heap (N101) + swap-pop Attack (N102).
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #149

**À merger** (`Heap.clear` visée + swap-pop missiles + specs N101–N102), sous réserve que cette passe 46 parte avec : **`RailPath.find` jetait encore `Heap.new()` + hashes, et `releaseAttack` `table.remove` encore en reverse-iter**.

Points encore vrais après #149 :

| Claim #149 | Réalité après passe 46 |
|---|---|
| N99 `AimFront.focus` Heap/queued | confirmé (`Heap.clear` + `table.clear`) |
| N100 `Nukes.step` `table.remove` | confirmé (swap-pop, 3 ATOM free-list, MIRV ogives uniques) |
| N101 `RailPath.find` Heap/hashes | **fermé ici** (rawequal Heap module, path unique, path1 intact) |
| N102 `releaseAttack` `table.remove` | **fermé ici** (swap-pop, accept relâche B, C reste, 2e launch rawequal, 3 fronts retraite sans trou) |
| N75 `stepDoomsday` scan O(TILE_COUNT) | **ouvert** |
| N33 `findSpawn` splash / fallout | **ouvert** |
| N28 retraite après flip / `targetSlot` | **ouvert** |
| N29 `seedBeachhead` no-merge | specs only, inchangé (banc N68 / N98 / N102 documente 3 Attack) |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |

`init.server.luau` et `Persistence` restent **exclus du bundle**. Le helper `MatchLifecycle` est **dans** le bundle (37 modules serveur — pas de module nouveau). `RailPath.find` / `releaseAttack` / callers while sont **dans** le bundle. `Heap.frontier` **reste unique entre vies** (N98) et **identité pendant la vie** (N99). Path `RailPath.find` **unique** (N101). Overlay retrace via `RailPath.find` (aucun octet réseau) — lit le tableau, pas le Heap. `removePlayer` missiles **sans** `missileFree` (cycle GameState→Nukes). `BoatFront.parkedBuf` **ne push pas** (gare live, encore `table.remove` — N104). `RailPath.runs` alloue encore des records (N103). `Navy.despawnBoat` encore `table.remove`.

PR feel / visual ne doivent pas être mergées par-dessus #16/#149 sans rebase. Seq / `targetSlot` / hover `SpawnHint` / Overlay `retreating` / `TRAIN_STOP_BONUS` HUD / `previewCtx` restent feel-only.

On peut fermer #17, #18, #20, #23, #25, #27, #30, #31, #33, #35, #37, #40, #43, #46, #49, #52, #55, #58, #60, #63, #66, #70, #73, #76, #80, #83, #85, #88, #91, #95, #98, #102, #104, #109, #112, #116, #119, #123, #127, #130, #135, #138, #141, #145 et #149 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| `RailPath.find` Heap/hashes (N101) | `RailPath.luau`, `tests/simulate.luau` | Heap module `searchHeap` + `Heap.clear` au lieu de `Heap.new()`. Hashes `cameFrom` / `bestCost` / `arrivedBy` : `table.clear` avant fill. Path retourné **unique** (N64). `MAX_EXPANDED` / `TURN_PENALTY` / `fallbackPath` inchangés. Recette spec #149 N101. Banc rawequal Heap + path unique + path1 intact **verts**. **Ne pas** pooler le path. **Ne pas** toucher Overlay / `refreshRailNetwork`. |
| `releaseAttack` `table.remove` (N102) | `GameState.luau`, `ChantierB.luau`, `Diplomacy.luau`, `tests/simulate.luau` | Swap-pop (`attacks[i] = attacks[#]` ; `# = nil` ; `freeAttack`). Callers **while reverse + decrement toujours** : `removePlayer`, `GameState.stepAttacks` (mort), `ChantierB.cancelOpposingFronts`, wrap `ChantierB.stepAttacks`, `Diplomacy.accept`. Recette N100. `BoatFront.parkedBuf` **sans** `releaseAttack`. Banc accept B relâché / C reste / 2e launch rawequal + 3 fronts retraite sans trou **verts**. **Ne pas** fusionner N29. **Ne pas** porter `parkedBuf` swap-pop (N104). |

**Non modifié (volontaire) :** N1–N100 restant, reste de N28 (`targetSlot`). N10.8. Cap beachheads (N5 / N29). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` / `require(Placement)` / `require(MatchLifecycle)` / `require(IntentValidator)` / `require(ChantierB)` depuis GameState. Pas de contrat C spawn (N33). Pas de seq obligatoire (feel N41). Pas de spatial hash warships. Buffer `defense` **alloué** mais plus écrit. Pas de `TRAIN_STOP_BONUS` dans `railIncome`. Scan cadran encore O(carte) (N9 / N75). `RailPath.runs` encore alloué (N103). `BoatFront` park encore `table.remove` (N104). `Navy.despawnBoat` encore `table.remove`. `removePlayer` bateaux / missiles **non** poolés (cycle). Pas de `retreating` Overlay. Debit `captures`/`pops` **non** remplacé par feel `guard < 80`. `PlacementPreview` / `tests/client.luau` **non** édités. Skip AFK cadran **conservé**. Payload Intent = référence live (N82). Persistence `UpdateAsync` **non** poolé (N6). `building.links` unique (N65). `boat.path` unique (N64). `Heap.frontier` unique entre vies (N98). Path `RailPath.find` unique (N101). Pools PORT / FACTORY / Building / missile / Attack **non fusionnés**.

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead + parkedBuf + acquireAttack), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + **captures < 80 et pops < 160**). Attack record **poolé** (N98). `AimFront.focus` **recycle** Heap/queued pendant la vie (N99). `releaseAttack` swap-pop au despawn (N102). `Heap.frontier` unique entre vies. `BoatFront.parkedBuf` **sans** `releaseAttack` (encore `table.remove` — N104).
- **Posted** : bunkers / SAM / SILO / FACTORY / PORT / NAVAL_BASE / `buildingsBySlot` inchangés vs #149. Record Building **poolé** (N95). Sidecars PORT/FACTORY **poolés** (N93/N94).
- **Têtes de pont** = `BoatFront.seedBeachhead` via `acquireAttack` (N98) : frontier = **voisins encore à la cible**, flag `isBeachhead`. `launchAttack` gare les beachheads dans `parkedBuf` **sans** `releaseAttack`. Insert sémantique encore un Attack par débarquement (N29).
- **Pacte vivant** = `areAllied` : deux sens **et** `tick < expiry` (ou `true` legacy tests). `Diplomacy.accept` `releaseAttack` swap-pop les fronts du couple (N102).
- **Porte-avions** = `syncCarriers` événementiel + spawn via `navalBasesBySlot` + `acquireBoat` (N96).
- **Commerce maritime** = `portsByTile` incrémental + `spawnTradeShips` `acquireBoat` (N96). Vague plafonnée avant flatten.
- **Voies** = `refreshRailNetwork` eventuel (N65 `stationBuf`). Trace client = `RailPath.find` (`searchHeap` recyclé — N101). Path **unique**. `runs` encore alloué (N103). Pas d’octet réseau : le client recalcule.
- **Nucléaire** = `Nukes.missileFree` (N97) + swap-pop array (N100). Overlay lit `snapshotMissiles` (N52), pas le live. `removePlayer` missiles **sans** free-list (cycle).
- **Réplication** : inchangée vs #149.
- **DataStore** : `settledHumans` poolé (N89). `endMatchRecords` poolé (N88). Persistence `UpdateAsync` **non** poolé (N6).
- **Require** : DAG. Pas de cycle. N101 dans RailPath. N102 dans GameState. Ne pas `require(Nukes)` depuis GameState.

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N104 restent ouverts** sauf N19 partiel, N21 **fermé**, N24 remplacé par N31 (**fermé**), N30–N32 **fermés**, N34–N74 **fermés**, N76–N102 **fermés**. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + N75 + le reste de N28 / N29 / N33.

---

### ISSUE-N28 — `retreatBoats` / `retreatAttack` après flip de côte (reste)

**Priorité :** P2 combat / comptabilité navale. **Partiel :** inbound `removePlayer` **fermé** en passe 8.

**Problème restant :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetSlot`. Conséquences encore vraies :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers).
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

Feel d425 (N49) + df65 (N53) : `launchInvasion` pose `targetSlot`, `retreatBoats` filtre l’intention (fallback `owner[targetTile]`), wrap 2e geste rappelle les tardifs, `Navy.step` auto-retraite si `owner[targetTile] ~= targetSlot`. **Porter, ne pas réinventer.** Distinct de N10.8 et du fix inbound. Distinct de N96 (`boatFree` — **déjà fermé**). Distinct de N97–N104.

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite.

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste, trancher si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`. Recette feel : branche `d425` / `df65`. `acquireBoat` doit overwrite `targetSlot` (N96 — leftover `targetSlot` d’un convoi recyclé en transport = retraite du mauvais camp).

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N22). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % déjà livré). Ne pas recâbler N35 (convois, `kind==2`). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).** Ne pas porter AimFront ni seq. Ne pas recâbler N50–N104. Ne pas casser `boatFree` (N96) : tout nouveau champ **doit** être écrit dans `acquireBoat`.

---

### ISSUE-N29 — `seedBeachhead` ne fusionne plus le couple naval

**Priorité :** P2 combat / cap.

**Problème :** `GameState.seedBeachhead` de base fusionnait `(attacker, target)`. `BoatFront.install` **remplace** la fonction et `table.insert` toujours un nouvel `Attack` `isBeachhead` (via `acquireAttack` N98 — leftover **sémantique**, pas alloc). Deux débarquements vs le même défenseur = deux fronts, pools de troupes séparés, deux consommations de debit `captures < 80`. Combiné à N5 (parking hors cap land), un joueur peut tenir 2 beachheads + 1 terre = 3 offensives alors que `MAX_ACTIVE_ATTACKS_PER_PLAYER = 2`. Le banc N68 / N98 / N102 **documente** ce 3 = 2 ponts + 1 terre (ne pas le « corriger » dans N68/N98/N99/N102).

**Pourquoi 20K CCU :** late-game invasions multiples. Ce n’est pas N11 (`MAX_TILES_PER_TICK` mort) ni N98 (leftover alloc Attack, **déjà fermé**) : ici le **nombre de tas** explose, chacun avec son `while captures < 80`.

**Worker :**

1. Confirmer le contrat OpenFront : **un** front naval par couple `(attacker, target)`, distinct du front terre. Si oui : dans `BoatFront.seedBeachhead`, trouver un `isBeachhead` existant du couple, ajouter `troops`, enfiler les nouveaux voisins, **freeAttack** le record acquis non inséré, return. Si le tas est vide après enqueue, refund + `freeAttack` comme aujourd’hui.
2. Si le produit **veut** les griffes multiples : documenter dans Config, et **compter** les beachheads dans le cap (fermer N5 dans le même PR). Pas les deux à la fois.
3. Test : deux `seedBeachhead` même couple → `#attacks == 1` et `troops` somme **ou** (si multi-prong assumé) `launchAttack` refuse au-delà du cap y compris parked. Le banc N68 / N98 / N102 (3 Attack) devra alors être mis à jour.
4. Fichiers : `BoatFront.luau`, éventuellement `GameState.launchAttack` / wrapper parking, `tests/simulate.luau`. Passer par `acquireAttack` / `freeAttack` (N98). Park via N104 si déjà livré (swap-pop, **pas** `releaseAttack`).

**Contraintes :** ne pas fusionner beachhead avec front terre (régression BoatFront / aim). Ne pas changer `attackTilesPerTick`. Ne pas mixer avec N28 (bateaux inbound / targetSlot). Ne pas mixer avec N68 (`parkedBuf` — leftover alloc, **déjà fermé**). Ne pas mixer avec N98 (pool Attack — leftover alloc, **déjà fermé**) ni N99 (Heap pendant la vie, **déjà fermé**) ni N102 (swap-pop despawn, **déjà fermé**). **N29 hardening ≠ N29 feel (seq avant apply).** Ne pas recâbler N103/N104.

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

**Contraintes :** ne pas annuler une frappe tiers (régression `nuke third-party`). Ne pas rembourser l’or. Pas de RemoteFunction. Rayon lu depuis `NUKE_STATS` / `missile.radius`, pas une constante magique. Ne pas porter isolation clic (feel N55) dans le même PR. Ne pas recâbler N50–N104. Ne pas mixer N76 (`tilesBeforeBuf` — **déjà fermé**) ni N77 (`mirvTxBuf` — **déjà fermé**) ni N97 (missile live, **déjà fermé**) ni N100 (swap-pop, **déjà fermé**).

---

### ISSUE-N75 — `stepDoomsday` scanne encore `0..TILE_COUNT-1` par camp qui saigne

**Priorité :** P2 cadran / perf. Leftover explicite de N9 et de N73. Distinct de N73 (`stripBuf`, **déjà fermé**) et de N74 (`stripTerritory` hashes, **déjà fermé**). Ne pas toucher `rotQuota`. **N75 hardening ≠ N75 feel historique (`pricesFor`).** Visual V13 décrit le même trou. **Non livré en passe 46** : contrat A (`tilesBySlot` maintenu dans `setOwner`) est un index d’autorité — un déréglage vs `owner` pourrit le mauvais camp. Trop structurel pour un correctif « sûr » à côté de N101/N102.

**Problème :** même avec `stripBuf` recyclé, chaque slot sous quota (10 Hz, late-game plusieurs camps) re-scanne `Config.TILE_COUNT` (40 960) jusqu’à `quota * 4` hits. Un shard 18 factions en cadran = jusqu’à ~17 scans linéaires / tick. Il n’existe pas d’index compact tuiles-par-slot : `ps.tiles` est un compteur, `ps.border` / `ps.coast` ne couvrent pas l’intérieur. N73 a volontairement laissé ce scan.

**Pourquoi 20K CCU :** leftover N9. Late-game cadran = le tick le plus cher du shard (hors combat). Recycle de la porteuse (N73) n’enlève pas les 40k reads `buffer.readu8`. Un index compact ramène le rot à O(tuiles du camp) au lieu de O(carte).

**Worker :**

1. Choisir un contrat : (A) `tilesBySlot[slot] = { number }` array compact, maintenu dans `setOwner` (insert au claim, swap-pop au loss) — `stepDoomsday` itère `1..ps.tiles` au lieu de `0..TILE_COUNT-1` ; (B) reservoir bitset 40 960 / 8 recyclé, rebuild seulement si dirty ; (C) documenter « scan O(carte) accepté, N9 fermé sans code ». **Un seul.** Feel / visual n’ont pas encore fermé V13. Pas de RemoteFunction.
2. Si A : `setOwner` est le **seul** writer. Capture, nuke crater, strip, collapse, spawn doivent tous passer par là. Test : 6000 ticks, `ps.tiles == #tilesBySlot[slot]`, rot n’émet plus de tuile `owner ~= slot`. Banc N73 / N74 **verts**.
3. Fichiers : `GameState.setOwner` + `ChantierB.stepDoomsday` (via `install()`), `tests/simulate.luau`. Pas de require GameState ↔ ChantierB nouveau.

**Contraintes :** pas de RemoteFunction. **N75 hardening ≠ N73 (`stripBuf`, déjà fait) ≠ N74 (`border`/`coast`, **déjà fait**) ≠ N76–N102 (déjà faits) ≠ N9 (umbrella — ce ticket **ferme** N9 si A ou C).** Ne pas changer `rotQuota` / drain / WARN. Overlay n’itère pas l’index. Un index déréglé vs `owner` = pourriture du mauvais camp. Ne pas `require(ChantierB)` depuis GameState. Ne pas mixer avec N103 (RailPath runs) ni N104 (BoatFront park).

---

### ISSUE-N101 — `RailPath.find` Heap/hashes — **FERMÉ** (passe 46)

Heap module `searchHeap` + `Heap.clear`. Hashes `cameFrom` / `bestCost` / `arrivedBy` `table.clear` avant fill. Path retourné **unique**. Banc : rawequal Heap, deux traces non `rawequal`, path1 intact. Ne pas rouvrir. Un leftover `cameFrom` = voie fantôme (banc voies / N101). Leftover `RailPath.runs` records → N103. Leftover `fallbackPath` alloc (rare, `MAX_EXPANDED`). **Ne pas** pooler le path. **Ne pas** toucher Overlay.

---

### ISSUE-N102 — `releaseAttack` `table.remove` — **FERMÉ** (passe 46)

Swap-pop + callers while reverse + decrement toujours. `BoatFront.parkedBuf` **sans** `releaseAttack`. Banc : accept relâche B, C reste, pas de trou, 2e launch rawequal ; 2 ponts + terre retraite `#==0` sans trou. Ne pas rouvrir. Un front sauté = clash fantôme (banc N67). Leftover park `table.remove` → N104. Leftover `Navy.despawnBoat` / `removePlayer` bateaux-missiles `table.remove` (cycle). **Ne pas** fusionner N29. **Ne pas** pooler le Heap entre Attacks.

---

### ISSUE-N103 — `RailPath.runs` alloue encore un tableau + records par tronçon

**Priorité :** P3 alloc voies. Leftover explicite de N101 (`RailPath.find` recycle Heap/hashes ; `runs` jette encore `out = {}` + `{ fromIndex, toIndex, length, horizontal }` par segment). Distinct de N101 (A* Heap, **fermé**). Distinct de N65 (`stationBuf` serveur, **fermé** — le serveur **ne** calcule **pas** les runs). **N103 hardening ≠ N103 feel historique (Overlay lookAt).** Overlay `buildFactoryRoute` itère `runs` **synchroniquement** puis construit des Parts — il ne stocke pas le tableau.

**Problème :** chaque liaison usine→gare (recalcul client à la pose / capture de gare) alloue 1 tableau + N records. Une grappe 4 gares × 8 humains = pic d’alloc records sur le rendu, pas sur le tick serveur. N101 a volontairement laissé `runs` : le path A* est unique, les tronçons sont un dérivé jetable.

**Pourquoi 20K CCU :** leftover naturel une fois `find` poolé. Recycle in-place `table.clear` / truncate (recette `stationBuf` N65) ramène le pic à zéro alloc au régime. Pas d’autorité si Overlay a **fini** d’itérer avant le prochain `runs` (sync aujourd’hui). Un leftover `out[i]` d’une voie précédente = tronçon fantôme (banc `RailPath.runs` simulate).

**Worker :**

1. Dans `RailPath.runs`, tableau module + pool de records Run. `table.clear` / truncate **avant** fill. Pas de pool du **path** (N101 unique). Pas de RemoteFunction. Rester dans `RailPath.luau`. `find` / `searchHeap` / Overlay / `refreshRailNetwork` inchangés.
2. Ne pas changer `TURN_PENALTY`, `fallbackPath`, `MAX_EXPANDED`. Banc voies / N65 / N101 **verts**. Client **34/34**.
3. Test : deux `RailPath.runs` distincts → si contrat A (retour module) second `rawequal` le tableau, leftover `#` ; si contrat B (copie unique comme N64) tableaux **non** `rawequal`. **Un seul contrat.** Overlay sync → A est sûr **aujourd’hui**. 6000 ticks.
4. Fichiers : `RailPath.luau` (`runs`), `tests/simulate.luau` (bloc court après N102). `Overlay.luau` / `init.server` inchangés. Pas de recette feel.

**Contraintes :** pas de RemoteFunction. **N103 hardening ≠ N101 (Heap find, déjà fait) ≠ N65 (`stationBuf`, déjà fait) ≠ N64 (`path` unique).** Overlay lit `fromIndex`/`toIndex` tout de suite. Un leftover run = voie sur la mauvaise gare. Ne pas mixer N28 / N75 / N104. Ne pas pooler le **path** `find`. Ne pas porter Overlay `retreating`. Client **34/34**.

---

### ISSUE-N104 — `BoatFront.launchAttack` `table.remove` encore O(n) pour gare les ponts

**Priorité :** P3 ordre combat. Leftover explicite de N102 (`releaseAttack` swap-pop le **despawn** ; le wrap park fait encore `table.remove(self.attacks, i)` **sans** `freeAttack`). Distinct de N102 (despawn, **fermé**). Distinct de N68 (`parkedBuf` leftover alloc, **fermé**). Distinct de N98 (pool record, **fermé**). Distinct de N29 (no-merge, **ouvert**). **N104 hardening ≠ N104 feel historique (`rebuildChunk`).** N102 a volontairement laissé le park : gare live, le pont **revient**.

**Problème :** `BoatFront.install` wrap `launchAttack` reverse-iter `isBeachhead`, `parkedBuf[n] = atk`, `table.remove` (shift O(n)). Puis `origLaunch`, puis `table.insert` les ponts. Un joueur 2 ponts + 1 terre (banc N68 / N98 / N102) = 2 shifts à chaque `launchAttack` / renfort. Overlay lit `frontHudForReplicate` (N55), pas l’ordre live. Mélanger `table.remove` (park) et swap-pop (N102 despawn) sur le **même** array est correct sémantiquement mais O(n²) au cap.

**Pourquoi 20K CCU :** leftover naturel une fois `releaseAttack` swap-pop. Late-game invasions + renfort terre = park à chaque geste. Pas d’autorité si **tous** les ponts reviennent (banc leftover 3). Un pont sauté = fusion terre/mer (régression BoatFront).

**Worker :**

1. Recette N102 **sans** `freeAttack` : swap-pop dans le wrap (`attacks[i] = attacks[#]` ; `# = nil` ; **pas** `releaseAttack`). Convertir le reverse-iter park en `while i >= 1` + decrement toujours. `parkedBuf` truncate avant origLaunch **inchangé** (N68). Réinsert après origLaunch **inchangé**. Pas de RemoteFunction. `acquireAttack` / `freeAttack` / `releaseAttack` inchangés.
2. Ne pas changer debit `captures`/`pops`, merge couple (N29), leftover 3. Banc N67 / N68 / N69 / N98 / N99 / N102 / aim reinforce **doivent rester verts**. 2 ponts leftover 3 **inchangé**.
3. Test : 2 ponts + terre (recette N68) → `launchAttack` renfort → `#attacks == 3`, `nBeach == 2`, pas de trou, `rawequal` les 2 ponts parked. Client **34/34**. 6000 ticks.
4. Fichiers : `BoatFront.luau` (wrap `launchAttack` seulement), `tests/simulate.luau` (bloc court après N103). `GameState.luau` / `Nukes.luau` / `AimFront.luau` / `init.server` inchangés. Recette N102 (pas feel). Leftover `Navy.despawnBoat` `table.remove` = ticket **suivant**, pas celui-ci.

**Contraintes :** pas de RemoteFunction. **N104 hardening ≠ N102 (despawn, déjà fait) ≠ N68 (`parkedBuf` alloc, déjà fait) ≠ N29 (no-merge, ouvert) ≠ N98 (record, déjà fait).** Overlay lit N55, pas l’ordre live. Un pont non réinséré = cap land qui mange le beachhead. Ne pas mixer N28 / N33 / N75 / N103. Ne pas `releaseAttack` au park. Ne pas « fixer » N29. `Navy.despawnBoat` / `removePlayer` bateaux-missiles **hors scope**.

---

## 5b. N1–N104 encore ouverts ou fermés (passes 2–46)

| ID | Titre | Prio | Note passe 46 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + `SAM_INTERCEPT_CHANCE` 0.55→1 ; clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz ; … ; AimFront Heap → **N99 fermé** ; missiles ordre → **N100 fermé** ; RailPath Heap → **N101 fermé** ; Attack ordre → **N102 fermé** ; `runs` → **N103** ; park → **N104** |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` **jamais** `FireServer` côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | park `isBeachhead` → hors cap land ; **2 beachheads parked + 1 terre = 3** — voir N29 ; alloc Attack → **N98 fermé** |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions. **Ne pas** pooler. |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | refund + retraite `RETREAT_LOSS` alignés ; wrap vivant → **N67 fermé** ; Attack record → **N98 fermé** ; Heap visée → **N99 fermé** ; swap-pop despawn → **N102 fermé** |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | timers slot maintenant purgés ; liste temporaire → **N73 fermé** ; hashes spawn → **N74 fermé** ; le scan rot est toujours O(tuiles) → **N75** |
| N10 | Divers P3 | P3 | donations gold sans plafond ; `pendingMode` last-writer ; … ; RailPath Heap → **N101 fermé** ; Attack ordre → **N102 fermé** ; `runs` → **N103** ; park → **N104** |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | debit = `attackTilesPerTick` × speed, **captures<80 pops<160** |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 observé) | P1 | `Bots.spawnAll` wrap + `Tribes.spawnAll(6)` hors budget |
| N13–N27 | (ère / heap / embargo / rail HUD / QuickChat / warships / …) | — | inchangés vs passe 45 ; voir rapport #149 |
| N28 | `retreatBoats` après flip | P2 | **partiel** : inbound fermé passe 8 ; `targetSlot` ouvert (recette feel N49/N53). Si porté : overwrite dans `acquireBoat` (N96). |
| N29 | `seedBeachhead` no-merge | P2 | specs only. Banc N68 / N98 / N102 documente 3 Attack (2 ponts + terre). Distinct de N98 (alloc, **fermé**) et N102 (ordre despawn, **fermé**). |
| N30–N32 | inbound missile / pool BFS / convoi | P2 | **fermés** |
| N33 | `findSpawn` splash / fallout | P3 | specs only (recette feel N50/N52) |
| N34–N74 | (index / snapshots / HUD / diplomatie / bots / combat wrap / pose) | — | **tous fermés** (passes 11–32). Voir rapport #102. |
| N75 | `stepDoomsday` scan O(TILE_COUNT) | P2 | specs only. Leftover N9 / N73. Ferme N9 si contrat A ou C. **Non livré ici** (A trop structurel). |
| N76–N100 | detonate / MIRV / TickMetrics / Intent / notify / roster / plunder / MatchUpdate / context / gravure / settled / profile / mapMeta / dispatch / portRec / factoryRec / buildingRec / boatFree / missileFree / attackFree / AimFront Heap / missile order | P3 | **fermés** (passes 33–45) |
| N101 | `RailPath.find` Heap/hashes | P3 | **fermé**. Leftover N99. Path unique. `runs` → **N103**. |
| N102 | `releaseAttack` `table.remove` O(n) | P3 | **fermé**. Leftover N98/N100. Swap-pop + while. Park → **N104**. |
| N103 | `RailPath.runs` records | P3 | specs only. Leftover N101. Overlay sync. |
| N104 | BoatFront park `table.remove` O(n) | P3 | specs only. Leftover N102. **Sans** `releaseAttack`. |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu ; disconnect mid-match **vivant** = `Persistence.record(..., false)` 0 XP ; wrap `launchAttack` n’applique `AimFront.focus` que si le couple n’existait pas (N99 **fermé** — Heap identique au renfort) ; spatial hash warships volontairement non fait ; `clearPlayer` reste `table.remove` ; payload Intent = référence live (N82) ; `{ index = … }` RemoteEvent = possession ; `MapGen.countByBiome` encore alloué (test-only) ; `removePlayer` bateaux/missiles **sans** free-list (cycle, rare vs 10 Hz spawn) ; `Navy.despawnBoat` encore `table.remove` (leftover N96/N100, ticket après N104).

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
| `NUKE_STATS[MIRV].warheads` | 6 | 6→**8** apply | oui (`splitMirv` — N77 ; ogives live → **N97 fermé** ; ordre → **N100 fermé**) |

---

## 7. Preuve tests

```
./tests/run.sh  → exit 0
bundle server : 37 modules
Serveur : Tous les invariants tiennent.
  … gardes #17–#149 inchangés …
  missile pool : rawequal ATOM / ogive MIRV (N97)
  attack pool : rawequal land, 2 ponts leftover 3 (N98)
  aim heap : rawequal frontier visée / renfort (N99)
  missile order : swap-pop 3 ATOM / MIRV unique (N100)
  rail heap : rawequal Heap, path unique (N101)
  attack order : swap-pop accept / 3 fronts retraite (N102)
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 captures=80 pops=160
  factions : 18
  metrics : ticks=6000 avgChanged=10.4 p95Changed=33 maxChanged=479 avgTickMs=0.38 p95TickMs=0.80
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe46.log`

---

## 8. Instructions worker (si reprise)

- Vérité runtime d’équilibrage = `ChantierB.apply(Config)` après `SystemsBootstrap.install()`, PAS `Config.luau` seul.
- Combat vivant = patches ChantierB, pas `GameState.stepAttacks` (sauf `returnCommittedTroops` et `retreatAttack`, partagés). Debit **captures < 80 / pops < 160** (pas feel `guard < 80`). Despawn Attack = `self:releaseAttack(i)` (swap-pop N102, pas `table.remove` nu). `BoatFront.parkedBuf` **sans** `releaseAttack` (encore `table.remove` — N104).
- `areAllied` = deux sens **et** expiry. Ne pas revenir à un test `~= nil`. Bots / chat / tribus : **jamais** `alliances[slot][other]` comme vérité.
- `retreatAttack` = **tous** les fronts du couple. Ne pas revenir à un `return` au premier match.
- Cote déjà nôtre ≠ retraite. Allié en mer = toujours retraite 25 % (N10.8). Inbound disparu = 100 % (comme front terre).
- Purge inbound d’un slot = **dans `removePlayer`**, pas seulement dans `Diplomacy.step`. Inclut cadran + colis + **transports** + **missiles** + **convois kind==2** (avant `setOwner`).
- Ne pas `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` / `require(Placement)` / `require(MatchLifecycle)` / `require(IntentValidator)` / `require(ChantierB)` depuis GameState (cycle).
- Building live : `buildingRecPool[index]` (N95). `links` neuf à chaque pose (N65). Destroy nil l’index live. Ne pas fusionner avec `portRecPool` / `factoryRecPool`.
- Bateau live : `Navy.boatFree` (N96). `acquireBoat` overwrite + `_sink` nil. `despawnBoat` push. `path` unique (N64). Tout nouveau champ (N28 `targetSlot`) **doit** être écrit dans `acquireBoat`. Ne pas `require` Navy depuis GameState.
- Missile live : `Nukes.missileFree` (N97). `acquireMissile` overwrite + `engaged`/`warhead` nil (sauf ogive). Despawn porteur **avant** split. Swap-pop array (N100). Ne pas `require` Nukes depuis GameState.
- Attack live : `GameState.attackFree` (N98). `acquireAttack` Heap neuf + queued neuf. `AimFront.focus` `Heap.clear` + `table.clear` (N99). `releaseAttack` swap-pop (N102). `freeAttack` si abort. BoatFront wrap via le helper. Ne pas pooler `Heap.frontier` **entre** Attacks. Park **sans** `releaseAttack`.
- Voies : `RailPath.searchHeap` + hashes `table.clear` (N101). Path **unique**. `runs` encore alloué (N103). Overlay retrace, pas d’octet réseau.
- Notify / sfx : `eventPool` / `soundPool` (N83). Overlay lit tout de suite.
- File d’intents : `IntentValidator.enqueue` réécrit `intentPool[n]` (N82). **Payload = référence live — ne pas pooler**.
- `init.server` / `Persistence` restent hors bundle.
- Ne pas casser le client 34/34.
- Ligne feel : rebase sur cette passe avant cherry-pick, sinon perte `searchHeap` / swap-pop Attack. Cherry-pick seq obligatoire (N41 feel) et `targetSlot` (N49 feel) seulement — et overwrite `targetSlot` dans `acquireBoat`. **Ne pas** porter `retreating` Overlay (feel N56). **Ne pas** porter `TRAIN_STOP_BONUS` HUD. **Ne pas** porter feel `guard < 80`. Client feel = 35/35 ; client hardening = **34/34**.
