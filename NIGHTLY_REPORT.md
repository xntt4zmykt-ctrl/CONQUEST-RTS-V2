# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 47)

Déclencheur : ouverture de la **PR #152** (`cursor/analyse-nocturne-du-codebase-0744`) — `RailPath.find` Heap, `releaseAttack` swap-pop, specs N103–N104.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-e291`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #152**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#152. Pas d’outil Slack.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29/#32/#34/#36/#38/#41/#42/#45/#48/#51/#53/#56/#59/#62 + d425 + df65 + 2157 + 5c74 + e735 + 7c38 + 1fb3 + 5bf6 + 741d + 55ba + 4876 + cc42 + 2f5d + b62d + 69f4 + 07c6 + 2b37 + e277 + 1e43 + a963 + d74d + c786 + **4a67** / **8f41** / **5bbf** / **de1a** / **04b6** / **5c7e** / **04e7** / **846c** / **ab04** / **bec6** / **b19e** / **4d8e** / **71f0** / **396d** / **5bde**) : ne pas merger sur cette branche sans rebase. Les numéros N40+ feel (settledHumans feel N40, seq, N52–N128…) ne sont **pas** les N40–N106 de ce rapport. Cette passe **ferme** hardening N103 (`RailPath.runs` pool) et N104 (BoatFront park swap-pop). Seq obligatoire (feel N41) et `targetSlot` (feel N49/N53) ne sont pas portés. **Pas** de `TRAIN_STOP_BONUS` dans `railIncome`. Feel N94 (`table.clear` border/coast) = N74 **déjà fermé**. N75 (scan cadran) **reste ouvert** — contrat A trop structurel. Client hardening = **34/34** (feel 35/35 — Overlay `retreating`). Payload Intent reste référence live (N82 — ne pas pooler). Persistence `UpdateAsync` **non** poolé (N6). `building.links` **unique** (N65). `boat.path` **unique** (N64). `Heap.frontier` **unique** (N98) **et** identité pendant la vie du front (N99). Path `RailPath.find` **unique** (N101). `runs` **module** (N103, Overlay sync). `removePlayer` bateaux / missiles **non** poolés (GameState ne require pas Navy/Nukes — N106). `BoatFront.parkedBuf` **sans** `releaseAttack` (gare live, swap-pop N104). `Navy.despawnBoat` encore `table.remove` (N105).

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`. `RequestSnapshot` n’est toujours jamais `FireServer` côté client (N4). DAG : `GameState` ne `require` ni Navy, ni Nukes, ni Trade, ni Bots, ni Buildings, ni Research, ni Diplomacy, ni Placement, ni MatchLifecycle, ni IntentValidator, ni ChantierB, ni BoatFront. `Buildings`, `Research`, `Diplomacy` require déjà `GameState` ; `Placement` require Shared only — ne pas inverser. `Nukes` require `GameState` + `Buildings` (pas l’inverse). `TickMetrics` require `Config` seulement. `MatchLifecycle` require `Config` seulement. `IntentValidator` require Shared only. `MapGen` require `Config` seulement. `Trade` require `GameState` (pas l’inverse). `Navy` require `GameState` (N96, pas l’inverse). N95 (`buildingRecPool`) vit dans **GameState**. N96 (`boatFree`) vit dans **Navy**. N97 (`missileFree`) vit dans **Nukes**. N98 (`attackFree`) vit dans **GameState**. N99 (`Heap.clear`) vit dans **AimFront**. N100 (`despawnMissile` swap-pop) vit dans **Nukes**. N101 (`searchHeap`) vit dans **RailPath**. N102 (`releaseAttack` swap-pop) vit dans **GameState**. N103 (`runBuf`) vit dans **RailPath**. N104 (park swap-pop) vit dans **BoatFront**. BoatFront.install appelle `GameState.acquireAttack` (pas de require nouveau). `RailPath` require `Heap` déjà — pas de require nouveau.

La PR #152 a bien fermé `RailPath.find` Heap (N101) et `releaseAttack` swap-pop (N102). Cette passe a **corrigé ce que #152 a spécifié** — `RailPath.runs` jetait encore un tableau + records, et le wrap park `table.remove` encore en O(n) :

| Bug | Gravité | Statut |
|---|---|---|
| `placeBuilding` Building record (N95) | **P3 alloc pose** | **déjà fermé** (#141, `buildingRecPool`) |
| `Navy` bateau live (N96) | **P3 alloc marine** | **déjà fermé** (#141, `boatFree`) |
| `Nukes.launch` / `splitMirv` missile live (N97) | **P3 alloc nucléaire** | **déjà fermé** (#145, `missileFree`) |
| `launchAttack` / `seedBeachhead` Attack (N98) | **P3 alloc combat** | **déjà fermé** (#145, `attackFree`) |
| `AimFront.focus` `Heap.new` + `queued={}` (N99) | **P3 alloc visee** | **déjà fermé** (#149, `Heap.clear`) |
| `Nukes.step` `table.remove` O(n) (N100) | **P3 alloc/ordre** | **déjà fermé** (#149, swap-pop) |
| `RailPath.find` `Heap.new` + hashes (N101) | **P3 alloc voies** | **déjà fermé** (#152, `searchHeap`) |
| `GameState.releaseAttack` `table.remove` O(n) (N102) | **P3 alloc/ordre** | **déjà fermé** (#152, swap-pop) |
| `RailPath.runs` records (N103) | **P3 alloc voies** | **corrigé** (`runBuf` + `runRecPool`, contrat A) |
| `BoatFront` park `table.remove` (N104) | **P3 alloc/ordre** | **corrigé** (swap-pop **sans** `releaseAttack`) |
| `Navy.despawnBoat` `table.remove` (N105) | **P3 alloc/ordre** | **ouvert** (leftover N96/N100) |
| `removePlayer` bateaux/missiles `table.remove` (N106) | **P3 alloc/ordre** | **ouvert** (leftover N102, cycle) |
| `stepDoomsday` scan O(TILE_COUNT) (N9 / N75) | **P2 cadran** | **ouvert** (index compact — leftover N73 ; contrat A trop structurel ici) |
| `retreatBoats` filtre `owner[targetTile]` courant | **P2 marine** | **ouvert** (reste de N28 ; feel d425/df65 a la recette) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29 ; N98 pool le record, **pas** la fusion) |
| `findSpawn` ignore splash / fallout (N33) | **P3 nucléaire** | **ouvert** (feel d425/df65 a C1+C2 + `isSpawnSafe`) |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#152 + allyBuf (N72) + stripBuf (N73) + stripTerritory hashes (N74) + detonate hashes (N76) + splitMirv hashes (N77) + TickMetrics ring (N78) + snapshot arrays (N79) + reset pool (N80) + snapBuf (N81) + intentPool (N82) + notify/sound pool (N83) + rosterBuf (N84) + plunderPool (N85) + matchUpdateBuf (N86) + contextBuf (N87) + recordBuf (N88) + settledRecPool (N89) + profileBuf (N90) + metaBuf (N91) + deliveryPool (N92) + portRecPool (N93) + factoryRecPool (N94) + buildingRecPool (N95) + boatFree (N96) + missileFree (N97) + attackFree (N98) + AimFront Heap (N99) + swap-pop missiles (N100) + RailPath Heap (N101) + swap-pop Attack (N102) + RailPath runs (N103) + park swap-pop (N104).
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #152

**À merger** (`searchHeap` + `releaseAttack` swap-pop + specs N103–N104), sous réserve que cette passe 47 parte avec : **`RailPath.runs` jetait encore `out = {}` + records, et le wrap park `table.remove` encore en reverse-iter**.

Points encore vrais après #152 :

| Claim #152 | Réalité après passe 47 |
|---|---|
| N101 `RailPath.find` Heap/hashes | confirmé (`searchHeap` + `table.clear`) |
| N102 `releaseAttack` `table.remove` | confirmé (swap-pop, accept relâche B, C reste) |
| N103 `RailPath.runs` records | **fermé ici** (rawequal module, leftover `#`, pool records) |
| N104 BoatFront park `table.remove` | **fermé ici** (swap-pop sans `releaseAttack`, 2 ponts rawequal, leftover 3) |
| N75 `stepDoomsday` scan O(TILE_COUNT) | **ouvert** |
| N33 `findSpawn` splash / fallout | **ouvert** |
| N28 retraite après flip / `targetSlot` | **ouvert** |
| N29 `seedBeachhead` no-merge | specs only, inchangé (banc N68 / N98 / N102 / N104 documente 3 Attack) |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |

`init.server.luau` et `Persistence` restent **exclus du bundle**. Le helper `MatchLifecycle` est **dans** le bundle (37 modules serveur — pas de module nouveau). `RailPath.runs` / wrap park sont **dans** le bundle. `Heap.frontier` **reste unique entre vies** (N98) et **identité pendant la vie** (N99). Path `RailPath.find` **unique** (N101). Overlay retrace via `RailPath.find` + `runs` (aucun octet réseau) — lit le tableau **sync**, pas le Heap. `removePlayer` missiles **sans** `missileFree` (cycle GameState→Nukes). `BoatFront.parkedBuf` **ne push pas** (gare live, swap-pop N104). `Navy.despawnBoat` encore `table.remove` (N105).

PR feel / visual ne doivent pas être mergées par-dessus #16/#152 sans rebase. Seq / `targetSlot` / hover `SpawnHint` / Overlay `retreating` / `TRAIN_STOP_BONUS` HUD / `previewCtx` restent feel-only.

On peut fermer #17, #18, #20, #23, #25, #27, #30, #31, #33, #35, #37, #40, #43, #46, #49, #52, #55, #58, #60, #63, #66, #70, #73, #76, #80, #83, #85, #88, #91, #95, #98, #102, #104, #109, #112, #116, #119, #123, #127, #130, #135, #138, #141, #145, #149 et #152 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| `RailPath.runs` records (N103) | `RailPath.luau`, `tests/simulate.luau` | Tableau module `runBuf` + pool `runRecPool`. Truncate leftover **avant** fill. Contrat A : retour module (Overlay sync). Path `find` **unique** (N101). `TURN_PENALTY` / `fallbackPath` / `MAX_EXPANDED` / Overlay / `refreshRailNetwork` inchangés. Recette spec #152 N103. Banc rawequal module + leftover `#` + pool **verts**. **Ne pas** pooler le path. **Ne pas** toucher Overlay. |
| BoatFront park `table.remove` (N104) | `BoatFront.luau`, `tests/simulate.luau` | Swap-pop **sans** `releaseAttack` (`attacks[i] = attacks[#]` ; `# = nil`). `while i >= 1` + decrement toujours. `parkedBuf` truncate avant origLaunch **inchangé** (N68). Réinsert après origLaunch **inchangé**. Recette N102. Banc 2 ponts rawequal / leftover 3 / renfort **verts**. **Ne pas** fusionner N29. **Ne pas** `releaseAttack` au park. |

**Non modifié (volontaire) :** N1–N102 restant, reste de N28 (`targetSlot`). N10.8. Cap beachheads (N5 / N29). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` / `require(Placement)` / `require(MatchLifecycle)` / `require(IntentValidator)` / `require(ChantierB)` depuis GameState. Pas de contrat C spawn (N33). Pas de seq obligatoire (feel N41). Pas de spatial hash warships. Buffer `defense` **alloué** mais plus écrit. Pas de `TRAIN_STOP_BONUS` dans `railIncome`. Scan cadran encore O(carte) (N9 / N75). `Navy.despawnBoat` encore `table.remove` (N105). `removePlayer` bateaux / missiles encore `table.remove` (N106). Pas de `retreating` Overlay. Debit `captures`/`pops` **non** remplacé par feel `guard < 80`. `PlacementPreview` / `tests/client.luau` **non** édités. Skip AFK cadran **conservé**. Payload Intent = référence live (N82). Persistence `UpdateAsync` **non** poolé (N6). `building.links` unique (N65). `boat.path` unique (N64). `Heap.frontier` unique entre vies (N98). Path `RailPath.find` unique (N101). Pools PORT / FACTORY / Building / missile / Attack **non fusionnés**.

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead + parkedBuf + acquireAttack + park swap-pop), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + **captures < 80 et pops < 160**). Attack record **poolé** (N98). `AimFront.focus` **recycle** Heap/queued pendant la vie (N99). `releaseAttack` swap-pop au despawn (N102). `Heap.frontier` unique entre vies. `BoatFront.parkedBuf` **sans** `releaseAttack` (swap-pop N104).
- **Posted** : bunkers / SAM / SILO / FACTORY / PORT / NAVAL_BASE / `buildingsBySlot` inchangés vs #152. Record Building **poolé** (N95). Sidecars PORT/FACTORY **poolés** (N93/N94).
- **Têtes de pont** = `BoatFront.seedBeachhead` via `acquireAttack` (N98) : frontier = **voisins encore à la cible**, flag `isBeachhead`. `launchAttack` gare les beachheads dans `parkedBuf` **sans** `releaseAttack` (swap-pop N104). Insert sémantique encore un Attack par débarquement (N29).
- **Pacte vivant** = `areAllied` : deux sens **et** `tick < expiry` (ou `true` legacy tests). `Diplomacy.accept` `releaseAttack` swap-pop les fronts du couple (N102).
- **Porte-avions** = `syncCarriers` événementiel + spawn via `navalBasesBySlot` + `acquireBoat` (N96). `despawnBoat` encore `table.remove` (N105).
- **Commerce maritime** = `portsByTile` incrémental + `spawnTradeShips` `acquireBoat` (N96). Vague plafonnée avant flatten.
- **Voies** = `refreshRailNetwork` eventuel (N65 `stationBuf`). Trace client = `RailPath.find` (`searchHeap` — N101) + `runs` (`runBuf` — N103). Path **unique**. Pas d’octet réseau : le client recalcule.
- **Nucléaire** = `Nukes.missileFree` (N97) + swap-pop array (N100). Overlay lit `snapshotMissiles` (N52), pas le live. `removePlayer` missiles **sans** free-list (cycle — N106).
- **Réplication** : inchangée vs #152.
- **DataStore** : `settledHumans` poolé (N89). `endMatchRecords` poolé (N88). Persistence `UpdateAsync` **non** poolé (N6).
- **Require** : DAG. Pas de cycle. N103 dans RailPath. N104 dans BoatFront. Ne pas `require(Nukes)` depuis GameState.

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N106 restent ouverts** sauf N19 partiel, N21 **fermé**, N24 remplacé par N31 (**fermé**), N30–N32 **fermés**, N34–N74 **fermés**, N76–N104 **fermés**. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + N75 + le reste de N28 / N29 / N33.

---

### ISSUE-N28 — `retreatBoats` / `retreatAttack` après flip de côte (reste)

**Priorité :** P2 combat / comptabilité navale. **Partiel :** inbound `removePlayer` **fermé** en passe 8.

**Problème restant :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetSlot`. Conséquences encore vraies :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers).
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

Feel d425 (N49) + df65 (N53) : `launchInvasion` pose `targetSlot`, `retreatBoats` filtre l’intention (fallback `owner[targetTile]`), wrap 2e geste rappelle les tardifs, `Navy.step` auto-retraite si `owner[targetTile] ~= targetSlot`. **Porter, ne pas réinventer.** Distinct de N10.8 et du fix inbound. Distinct de N96 (`boatFree` — **déjà fermé**). Distinct de N97–N106.

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite.

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste, trancher si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`. Recette feel : branche `d425` / `df65`. `acquireBoat` doit overwrite `targetSlot` (N96 — leftover `targetSlot` d’un convoi recyclé en transport = retraite du mauvais camp).

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N22). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % déjà livré). Ne pas recâbler N35 (convois, `kind==2`). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).** Ne pas porter AimFront ni seq. Ne pas recâbler N50–N106. Ne pas casser `boatFree` (N96) : tout nouveau champ **doit** être écrit dans `acquireBoat`.

---

### ISSUE-N29 — `seedBeachhead` ne fusionne plus le couple naval

**Priorité :** P2 combat / cap.

**Problème :** `GameState.seedBeachhead` de base fusionnait `(attacker, target)`. `BoatFront.install` **remplace** la fonction et `table.insert` toujours un nouvel `Attack` `isBeachhead` (via `acquireAttack` N98 — leftover **sémantique**, pas alloc). Deux débarquements vs le même défenseur = deux fronts, pools de troupes séparés, deux consommations de debit `captures < 80`. Combiné à N5 (parking hors cap land), un joueur peut tenir 2 beachheads + 1 terre = 3 offensives alors que `MAX_ACTIVE_ATTACKS_PER_PLAYER = 2`. Le banc N68 / N98 / N102 / N104 **documente** ce 3 = 2 ponts + 1 terre (ne pas le « corriger » dans N68/N98/N99/N102/N104).

**Pourquoi 20K CCU :** late-game invasions multiples. Ce n’est pas N11 (`MAX_TILES_PER_TICK` mort) ni N98 (leftover alloc Attack, **déjà fermé**) : ici le **nombre de tas** explose, chacun avec son `while captures < 80`.

**Worker :**

1. Confirmer le contrat OpenFront : **un** front naval par couple `(attacker, target)`, distinct du front terre. Si oui : dans `BoatFront.seedBeachhead`, trouver un `isBeachhead` existant du couple, ajouter `troops`, enfiler les nouveaux voisins, **freeAttack** le record acquis non inséré, return. Si le tas est vide après enqueue, refund + `freeAttack` comme aujourd’hui.
2. Si le produit **veut** les griffes multiples : documenter dans Config, et **compter** les beachheads dans le cap (fermer N5 dans le même PR). Pas les deux à la fois.
3. Test : deux `seedBeachhead` même couple → `#attacks == 1` et `troops` somme **ou** (si multi-prong assumé) `launchAttack` refuse au-delà du cap y compris parked. Le banc N68 / N98 / N102 / N104 (3 Attack) devra alors être mis à jour.
4. Fichiers : `BoatFront.luau`, éventuellement `GameState.launchAttack` / wrapper parking, `tests/simulate.luau`. Passer par `acquireAttack` / `freeAttack` (N98). Park via N104 (swap-pop, **pas** `releaseAttack`).

**Contraintes :** ne pas fusionner beachhead avec front terre (régression BoatFront / aim). Ne pas changer `attackTilesPerTick`. Ne pas mixer avec N28 (bateaux inbound / targetSlot). Ne pas mixer avec N68 (`parkedBuf` — leftover alloc, **déjà fermé**). Ne pas mixer avec N98 (pool Attack — leftover alloc, **déjà fermé**) ni N99 (Heap pendant la vie, **déjà fermé**) ni N102 (swap-pop despawn, **déjà fermé**) ni N104 (park, **déjà fermé**). **N29 hardening ≠ N29 feel (seq avant apply).** Ne pas recâbler N105/N106.

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

**Contraintes :** ne pas annuler une frappe tiers (régression `nuke third-party`). Ne pas rembourser l’or. Pas de RemoteFunction. Rayon lu depuis `NUKE_STATS` / `missile.radius`, pas une constante magique. Ne pas porter isolation clic (feel N55) dans le même PR. Ne pas recâbler N50–N106. Ne pas mixer N76 (`tilesBeforeBuf` — **déjà fermé**) ni N77 (`mirvTxBuf` — **déjà fermé**) ni N97 (missile live, **déjà fermé**) ni N100 (swap-pop, **déjà fermé**).

---

### ISSUE-N75 — `stepDoomsday` scanne encore `0..TILE_COUNT-1` par camp qui saigne

**Priorité :** P2 cadran / perf. Leftover explicite de N9 et de N73. Distinct de N73 (`stripBuf`, **déjà fermé**) et de N74 (`stripTerritory` hashes, **déjà fermé**). Ne pas toucher `rotQuota`. **N75 hardening ≠ N75 feel historique (`pricesFor`).** Visual V13 décrit le même trou. **Non livré en passe 47** : contrat A (`tilesBySlot` maintenu dans `setOwner`) est un index d’autorité — un déréglage vs `owner` pourrit le mauvais camp. Trop structurel pour un correctif « sûr » à côté de N103/N104.

**Problème :** même avec `stripBuf` recyclé, chaque slot sous quota (10 Hz, late-game plusieurs camps) re-scanne `Config.TILE_COUNT` (40 960) jusqu’à `quota * 4` hits. Un shard 18 factions en cadran = jusqu’à ~17 scans linéaires / tick. Il n’existe pas d’index compact tuiles-par-slot : `ps.tiles` est un compteur, `ps.border` / `ps.coast` ne couvrent pas l’intérieur. N73 a volontairement laissé ce scan.

**Pourquoi 20K CCU :** leftover N9. Late-game cadran = le tick le plus cher du shard (hors combat). Recycle de la porteuse (N73) n’enlève pas les 40k reads `buffer.readu8`. Un index compact ramène le rot à O(tuiles du camp) au lieu de O(carte).

**Worker :**

1. Choisir un contrat : (A) `tilesBySlot[slot] = { number }` array compact, maintenu dans `setOwner` (insert au claim, swap-pop au loss) — `stepDoomsday` itère `1..ps.tiles` au lieu de `0..TILE_COUNT-1` ; (B) reservoir bitset 40 960 / 8 recyclé, rebuild seulement si dirty ; (C) documenter « scan O(carte) accepté, N9 fermé sans code ». **Un seul.** Feel / visual n’ont pas encore fermé V13. Pas de RemoteFunction.
2. Si A : `setOwner` est le **seul** writer. Capture, nuke crater, strip, collapse, spawn doivent tous passer par là. Test : 6000 ticks, `ps.tiles == #tilesBySlot[slot]`, rot n’émet plus de tuile `owner ~= slot`. Banc N73 / N74 **verts**.
3. Fichiers : `GameState.setOwner` + `ChantierB.stepDoomsday` (via `install()`), `tests/simulate.luau`. Pas de require GameState ↔ ChantierB nouveau.

**Contraintes :** pas de RemoteFunction. **N75 hardening ≠ N73 (`stripBuf`, déjà fait) ≠ N74 (`border`/`coast`, **déjà fait**) ≠ N76–N104 (déjà faits) ≠ N9 (umbrella — ce ticket **ferme** N9 si A ou C).** Ne pas changer `rotQuota` / drain / WARN. Overlay n’itère pas l’index. Un index déréglé vs `owner` = pourriture du mauvais camp. Ne pas `require(ChantierB)` depuis GameState. Ne pas mixer avec N105 (`despawnBoat`) ni N106 (`removePlayer` bateaux).

---

### ISSUE-N103 — `RailPath.runs` records — **FERMÉ** (passe 47)

Tableau module `runBuf` + pool `runRecPool`. Truncate leftover **avant** fill. Contrat A : retour module, Overlay itère sync. Banc : rawequal module, leftover `#`, records recyclés. Ne pas rouvrir. Un leftover `runBuf[i]` = tronçon fantôme (banc N103). Path `find` **unique** (N101). **Ne pas** pooler le path. **Ne pas** toucher Overlay.

---

### ISSUE-N104 — BoatFront park `table.remove` — **FERMÉ** (passe 47)

Swap-pop **sans** `releaseAttack` + while reverse + decrement toujours. `parkedBuf` truncate avant origLaunch **inchangé**. Banc : 2 ponts rawequal, leftover 3, renfort sans trou. Ne pas rouvrir. Un pont sauté = fusion terre/mer (banc N68). Leftover `Navy.despawnBoat` → N105. Leftover `removePlayer` bateaux/missiles → N106. **Ne pas** fusionner N29. **Ne pas** `releaseAttack` au park.

---

### ISSUE-N105 — `Navy.despawnBoat` `table.remove` encore O(n)

**Priorité :** P3 ordre marine. Leftover explicite de N96 (`boatFree` pool le **record** ; l’array live `state.boats` `table.remove` encore) et de N100/N104 (swap-pop missiles / park). Distinct de N96 (alloc record, **fermé**). Distinct de N104 (park Attack, **fermé**). Distinct de N106 (`removePlayer` sans free-list, **ouvert**). **N105 hardening ≠ N105 feel historique (camion lookAt).** Overlay lit `snapshotBoats` (N51), pas l’ordre live.

**Problème :** `despawnBoat` fait `table.remove(state.boats, i)` puis `table.insert(boatFree, boat)`. Callers déjà reverse (`syncCarriers`, sink `stepCarriers`, `Navy.step` transports/convois). Un shard late-game 24 convois + 18 carriers + transports : chaque accostage / PORT détruit / own-tile shift O(n). Mélanger `table.remove` (Navy) et swap-pop (N100 missiles) sur des arrays 10 Hz est O(n²) au cap `MAX_TRADE_SHIPS`.

**Pourquoi 20K CCU :** leftover naturel une fois `boatFree` + missiles swap-pop. Vague commerce 10 Hz / `TRADE_SHIP_INTERVAL` + own-tile 100 % (N10.8 inbound) = despawn en rafale. Pas d’autorité si Overlay lit le snapshot. Un bateau sauté = convoi fantôme / carrier orphelin (banc N48 / N96).

**Worker :**

1. Recette N100 : swap-pop dans `despawnBoat` (`boats[i] = boats[#]` ; `# = nil` ; **puis** `table.insert(boatFree, boat)`). Convertir les callers reverse-for en `while i >= 1` + decrement **toujours** après despawn (l’item swappé venait d’un indice plus haut). `continue` après despawn inchangé. Pas de RemoteFunction. `acquireBoat` / `_sink` / `path` unique (N64) inchangés.
2. Ne pas changer debit combat, `targetSlot` (N28), `MAX_TRADE_SHIPS`, `_carriersDirty`. Banc N48 / N51 / N64 / N96 / trade inbound / port-détruit **doivent rester verts**.
3. Test : 3 transports, couler le milieu (PORT détruit ou own-tile) → pas de trou, rawequal `boatFree`, les 2 restants identiques. Client **34/34**. 6000 ticks.
4. Fichiers : `Navy.luau` (`despawnBoat` + callers `syncCarriers` / `stepCarriers` / `Navy.step`), `tests/simulate.luau` (bloc court après N104). `GameState.luau` / `BoatFront.luau` / `init.server` inchangés. Recette N100 (pas feel). Leftover `removePlayer` bateaux = **N106**, pas celui-ci.

**Contraintes :** pas de RemoteFunction. **N105 hardening ≠ N96 (record, déjà fait) ≠ N100 (missiles, déjà fait) ≠ N104 (park Attack, déjà fait) ≠ N106 (`removePlayer`, ouvert).** Overlay lit N51, pas l’ordre live. Un carrier sauté = `_carriersDirty` respawn double. Ne pas mixer N28 / N33 / N75 / N106. Ne pas `require` Navy depuis GameState. `path` **unique** (N64). `acquireBoat` overwrite `_sink` nil.

---

### ISSUE-N106 — `removePlayer` bateaux / missiles encore `table.remove` O(n)

**Priorité :** P3 ordre déco. Leftover explicite de N102 (`releaseAttack` swap-pop les **fronts** ; bateaux/missiles inbound encore `table.remove`) et de N105 (Navy.step live). Distinct de N105 (`despawnBoat` + `boatFree`, **ouvert / suivant**). Distinct de N43/N44/N48 (inbound **sémantique** 100 % / contrat B, **fermés**). **N106 hardening ≠ N106 feel historique (recycle Parts).** GameState **ne** require **pas** Navy/Nukes — **pas** de `boatFree` / `missileFree` ici (cycle). Overlay lit snapshots N51/N52.

**Problème :** `removePlayer` reverse-iter `self.boats` / `self.missiles` avec `table.remove` : (1) bateaux du slot qui part, (2) transports `kind==1` inbound (refund 100 %), (3) convois `kind==2` inbound (pas d’or), (4) missiles du tireur, (5) ogives visées sur le disparu (contrat B). Rare (déco / élimin) mais un shard 18 factions + 24 convois + MIRV 8 ogives = O(n²) au moment le plus chaud (collapse + cadran). Les records **fuient** (pas de push free-list) — volontaire, cycle.

**Pourquoi 20K CCU :** leftover naturel une fois Attack/missiles live swap-pop. Déco mid-collapse = le tick le plus cher hors combat. Pas d’autorité si Overlay a **fini** le snapshot du tick précédent. Un bateau tiers sauté = invasion fantôme vs héritier (banc `boat inbound` / `nuke third-party`).

**Worker :**

1. Recette N102 **sans** `freeAttack` / **sans** `boatFree` / **sans** `missileFree` : swap-pop (`arr[i] = arr[#]` ; `# = nil`). Convertir les deux boucles en `while i >= 1` + decrement toujours. Sémantique inbound **inchangée** (100 % troops, pas d’or convoi, contrat B ogive, tiers conservé). Pas de RemoteFunction. Pas de `require(Navy)` / `require(Nukes)`.
2. Ne pas changer `setOwner` après, `destroyBuf` (N70), cadran/colis recycle. Banc boat inbound / nuke inbound / trade inbound / third-party / N51 / N52 / N96 / N97 **verts**.
3. Test : 2 inbound transports + 1 own + 1 third-party ; `removePlayer` ; pas de trou ; third-party reste ; inbound refunded ; own disparu. Même schéma missiles (ogive visée vs tiers). Client **34/34**. 6000 ticks.
4. Fichiers : `GameState.luau` (`removePlayer` bateaux + missiles seulement), `tests/simulate.luau` (bloc court après N105). `Navy.luau` / `Nukes.luau` / `init.server` inchangés. Recette N102 (pas feel). Si N105 déjà livré : ne pas double-free (removePlayer **n’appelle pas** `despawnBoat`).

**Contraintes :** pas de RemoteFunction. **N106 hardening ≠ N105 (Navy.step, ticket jumeau) ≠ N102 (Attack, déjà fait) ≠ N43/N44 (sémantique inbound, déjà fait).** Overlay lit snapshots, pas le live. Un inbound sauté = têtes de pont vs disparu (régression `boat inbound`). Ne pas mixer N28 / N33 / N75 / N29. Ne pas pooler les records ici (cycle). `freeSlots` `table.remove` **hors scope**.

---

## 5b. N1–N106 encore ouverts ou fermés (passes 2–47)

| ID | Titre | Prio | Note passe 47 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + `SAM_INTERCEPT_CHANCE` 0.55→1 ; clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz ; … ; `runs` → **N103 fermé** ; park → **N104 fermé** ; `despawnBoat` → **N105** ; `removePlayer` boats → **N106** |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` **jamais** `FireServer` côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | park `isBeachhead` → hors cap land ; **2 beachheads parked + 1 terre = 3** — voir N29 ; alloc Attack → **N98 fermé** ; park ordre → **N104 fermé** |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions. **Ne pas** pooler. |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | refund + retraite `RETREAT_LOSS` alignés ; wrap vivant → **N67 fermé** ; Attack record → **N98 fermé** ; Heap visée → **N99 fermé** ; swap-pop despawn → **N102 fermé** ; park → **N104 fermé** |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | timers slot maintenant purgés ; liste temporaire → **N73 fermé** ; hashes spawn → **N74 fermé** ; le scan rot est toujours O(tuiles) → **N75** |
| N10 | Divers P3 | P3 | donations gold sans plafond ; `pendingMode` last-writer ; … ; `runs` → **N103 fermé** ; park → **N104 fermé** ; `despawnBoat` → **N105** |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | debit = `attackTilesPerTick` × speed, **captures<80 pops<160** |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 observé) | P1 | `Bots.spawnAll` wrap + `Tribes.spawnAll(6)` hors budget |
| N13–N27 | (ère / heap / embargo / rail HUD / QuickChat / warships / …) | — | inchangés vs passe 46 ; voir rapport #152 |
| N28 | `retreatBoats` après flip | P2 | **partiel** : inbound fermé passe 8 ; `targetSlot` ouvert (recette feel N49/N53). Si porté : overwrite dans `acquireBoat` (N96). |
| N29 | `seedBeachhead` no-merge | P2 | specs only. Banc N68 / N98 / N102 / N104 documente 3 Attack (2 ponts + terre). Distinct de N98 (alloc, **fermé**) et N104 (ordre park, **fermé**). |
| N30–N32 | inbound missile / pool BFS / convoi | P2 | **fermés** |
| N33 | `findSpawn` splash / fallout | P3 | specs only (recette feel N50/N52) |
| N34–N74 | (index / snapshots / HUD / diplomatie / bots / combat wrap / pose) | — | **tous fermés** (passes 11–32). Voir rapport #102. |
| N75 | `stepDoomsday` scan O(TILE_COUNT) | P2 | specs only. Leftover N9 / N73. Ferme N9 si contrat A ou C. **Non livré ici** (A trop structurel). |
| N76–N102 | detonate / MIRV / TickMetrics / Intent / notify / roster / plunder / MatchUpdate / context / gravure / settled / profile / mapMeta / dispatch / portRec / factoryRec / buildingRec / boatFree / missileFree / attackFree / AimFront Heap / missile order / RailPath Heap / Attack ordre | P3 | **fermés** (passes 33–46) |
| N103 | `RailPath.runs` records | P3 | **fermé**. Leftover N101. Contrat A Overlay sync. |
| N104 | BoatFront park `table.remove` O(n) | P3 | **fermé**. Leftover N102. **Sans** `releaseAttack`. |
| N105 | `Navy.despawnBoat` `table.remove` O(n) | P3 | specs only. Leftover N96/N100. Swap-pop + `boatFree`. |
| N106 | `removePlayer` bateaux/missiles `table.remove` | P3 | specs only. Leftover N102. **Sans** free-list (cycle). |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu ; disconnect mid-match **vivant** = `Persistence.record(..., false)` 0 XP ; wrap `launchAttack` n’applique `AimFront.focus` que si le couple n’existait pas (N99 **fermé** — Heap identique au renfort) ; spatial hash warships volontairement non fait ; `clearPlayer` reste `table.remove` ; payload Intent = référence live (N82) ; `{ index = … }` RemoteEvent = possession ; `MapGen.countByBiome` encore alloué (test-only) ; `freeSlots` `table.remove` (hors N106).

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
  … gardes #17–#152 inchangés …
  rail heap : rawequal Heap, path unique (N101)
  attack order : swap-pop accept / 3 fronts retraite (N102)
  rail runs : rawequal module, leftover #, pool (N103)
  park order : swap-pop 2 ponts rawequal, leftover 3 (N104)
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 captures=80 pops=160
  factions : 18
  metrics : ticks=6000 avgChanged=10.0 p95Changed=28 maxChanged=970 avgTickMs=0.35 p95TickMs=1.26
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe47.log`

---

## 8. Instructions worker (si reprise)

- Vérité runtime d’équilibrage = `ChantierB.apply(Config)` après `SystemsBootstrap.install()`, PAS `Config.luau` seul.
- Combat vivant = patches ChantierB, pas `GameState.stepAttacks` (sauf `returnCommittedTroops` et `retreatAttack`, partagés). Debit **captures < 80 / pops < 160** (pas feel `guard < 80`). Despawn Attack = `self:releaseAttack(i)` (swap-pop N102, pas `table.remove` nu). `BoatFront.parkedBuf` **sans** `releaseAttack` (swap-pop N104).
- `areAllied` = deux sens **et** expiry. Ne pas revenir à un test `~= nil`. Bots / chat / tribus : **jamais** `alliances[slot][other]` comme vérité.
- `retreatAttack` = **tous** les fronts du couple. Ne pas revenir à un `return` au premier match.
- Cote déjà nôtre ≠ retraite. Allié en mer = toujours retraite 25 % (N10.8). Inbound disparu = 100 % (comme front terre).
- Purge inbound d’un slot = **dans `removePlayer`**, pas seulement dans `Diplomacy.step`. Inclut cadran + colis + **transports** + **missiles** + **convois kind==2** (avant `setOwner`).
- Ne pas `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` / `require(Placement)` / `require(MatchLifecycle)` / `require(IntentValidator)` / `require(ChantierB)` depuis GameState (cycle).
- Building live : `buildingRecPool[index]` (N95). `links` neuf à chaque pose (N65). Destroy nil l’index live. Ne pas fusionner avec `portRecPool` / `factoryRecPool`.
- Bateau live : `Navy.boatFree` (N96). `acquireBoat` overwrite + `_sink` nil. `despawnBoat` push (encore `table.remove` — N105). `path` unique (N64). Tout nouveau champ (N28 `targetSlot`) **doit** être écrit dans `acquireBoat`. Ne pas `require` Navy depuis GameState.
- Missile live : `Nukes.missileFree` (N97). `acquireMissile` overwrite + `engaged`/`warhead` nil (sauf ogive). Despawn porteur **avant** split. Swap-pop array (N100). Ne pas `require` Nukes depuis GameState. `removePlayer` missiles **sans** free-list (N106).
- Attack live : `GameState.attackFree` (N98). `acquireAttack` Heap neuf + queued neuf. `AimFront.focus` `Heap.clear` + `table.clear` (N99). `releaseAttack` swap-pop (N102). `freeAttack` si abort. BoatFront wrap via le helper. Ne pas pooler `Heap.frontier` **entre** Attacks. Park **sans** `releaseAttack` (swap-pop N104).
- Voies : `RailPath.searchHeap` + hashes `table.clear` (N101). Path **unique**. `runs` module `runBuf` (N103, Overlay sync). Overlay retrace, pas d’octet réseau.
- Notify / sfx : `eventPool` / `soundPool` (N83). Overlay lit tout de suite.
- File d’intents : `IntentValidator.enqueue` réécrit `intentPool[n]` (N82). **Payload = référence live — ne pas pooler**.
- `init.server` / `Persistence` restent hors bundle.
- Ne pas casser le client 34/34.
- Ligne feel : rebase sur cette passe avant cherry-pick, sinon perte `runBuf` / park swap-pop. Cherry-pick seq obligatoire (N41 feel) et `targetSlot` (N49 feel) seulement — et overwrite `targetSlot` dans `acquireBoat`. **Ne pas** porter `retreating` Overlay (feel N56). **Ne pas** porter `TRAIN_STOP_BONUS` HUD. **Ne pas** porter feel `guard < 80`. Client feel = 35/35 ; client hardening = **34/34**.
