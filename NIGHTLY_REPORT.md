# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 49)

Déclencheur : ouverture de la **PR #160** (`cursor/analyse-nocturne-du-codebase-93f6`) — `Navy.despawnBoat` swap-pop, `removePlayer` bateaux/missiles swap-pop, specs N107–N108.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-41e2`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #160**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#160. Pas d’outil Slack.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29/#32/#34/#36/#38/#41/#42/#45/#48/#51/#53/#56/#59/#62 + d425 + df65 + 2157 + 5c74 + e735 + 7c38 + 1fb3 + 5bf6 + 741d + 55ba + 4876 + cc42 + 2f5d + b62d + 69f4 + 07c6 + 2b37 + e277 + 1e43 + a963 + d74d + c786 + **4a67** / **8f41** / **5bbf** / **de1a** / **04b6** / **5c7e** / **04e7** / **846c** / **ab04** / **bec6** / **b19e** / **4d8e** / **71f0** / **396d** / **5bde** / **5655** / **5aa9**) : ne pas merger sur cette branche sans rebase. Les numéros N40+ feel (settledHumans feel N40, seq, N52–N134…) ne sont **pas** les N40–N110 de ce rapport. Cette passe **ferme** hardening N107 (`IntentValidator.clearPlayer` swap-pop) et N108 (`Bots.botSlots` / `Tribes.tribeSlots` swap-pop). Seq obligatoire (feel N41) et `targetSlot` (feel N49/N53) ne sont pas portés. **Pas** de `TRAIN_STOP_BONUS` dans `railIncome`. Feel N94 (`table.clear` border/coast) = N74 **déjà fermé**. N75 (scan cadran) **reste ouvert** — contrat A trop structurel. Client hardening = **34/34** (feel 35/35 — Overlay `retreating`). Payload Intent reste référence live (N82 — ne pas pooler). Persistence `UpdateAsync` **non** poolé (N6). `building.links` **unique** (N65). `boat.path` **unique** (N64). `Heap.frontier` **unique** (N98) **et** identité pendant la vie du front (N99). Path `RailPath.find` **unique** (N101). `runs` **module** (N103, Overlay sync). `removePlayer` bateaux / missiles **sans** free-list (GameState ne require pas Navy/Nukes — N106 **fermé**, leftover sémantique = fuite volontaire). `BoatFront.parkedBuf` **sans** `releaseAttack` (gare live, swap-pop N104). `Navy.despawnBoat` swap-pop **puis** `boatFree` (N105). `IntentValidator.clearPlayer` swap-pop **sans** pooler le payload (N107). `Bots.botSlots` / `Tribes.tribeSlots` swap-pop **sans** free-list (N108). `WorldRenderer.dirtyQueue` encore `table.remove(1)` (N109). `HUD.feedEntries` encore `table.remove` (N110). `freeSlots` `table.remove` **hors scope** (pop stack O(1)).

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`. `RequestSnapshot` n’est toujours jamais `FireServer` côté client (N4). DAG : `GameState` ne `require` ni Navy, ni Nukes, ni Trade, ni Bots, ni Buildings, ni Research, ni Diplomacy, ni Placement, ni MatchLifecycle, ni IntentValidator, ni ChantierB, ni BoatFront. `Buildings`, `Research`, `Diplomacy` require déjà `GameState` ; `Placement` require Shared only — ne pas inverser. `Nukes` require `GameState` + `Buildings` (pas l’inverse). `TickMetrics` require `Config` seulement. `MatchLifecycle` require `Config` seulement. `IntentValidator` require Shared only. `MapGen` require `Config` seulement. `Trade` require `GameState` (pas l’inverse). `Navy` require `GameState` (N96, pas l’inverse). N95 (`buildingRecPool`) vit dans **GameState**. N96 (`boatFree`) vit dans **Navy**. N97 (`missileFree`) vit dans **Nukes**. N98 (`attackFree`) vit dans **GameState**. N99 (`Heap.clear`) vit dans **AimFront**. N100 (`despawnMissile` swap-pop) vit dans **Nukes**. N101 (`searchHeap`) vit dans **RailPath**. N102 (`releaseAttack` swap-pop) vit dans **GameState**. N103 (`runBuf`) vit dans **RailPath**. N104 (park swap-pop) vit dans **BoatFront**. N105 (`despawnBoat` swap-pop) vit dans **Navy**. N106 (`removePlayer` bateaux/missiles swap-pop) vit dans **GameState**. N107 (`clearPlayer` swap-pop) vit dans **IntentValidator**. N108 (`botSlots` / `tribeSlots` swap-pop) vit dans **Bots** / **Tribes**. BoatFront.install appelle `GameState.acquireAttack` (pas de require nouveau). `RailPath` require `Heap` déjà — pas de require nouveau. `Tribes` require déjà `Bots` — pas de require nouveau.

La PR #160 a bien fermé `Navy.despawnBoat` swap-pop (N105) et `removePlayer` bateaux/missiles swap-pop (N106). Cette passe a **corrigé ce que #160 a spécifié** — `IntentValidator.clearPlayer` jetait encore `table.remove`, et `Bots.step` / `Tribes.step` encore `table.remove` :

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
| `RailPath.runs` records (N103) | **P3 alloc voies** | **déjà fermé** (#156, `runBuf`) |
| `BoatFront` park `table.remove` (N104) | **P3 alloc/ordre** | **déjà fermé** (#156, swap-pop **sans** `releaseAttack`) |
| `Navy.despawnBoat` `table.remove` (N105) | **P3 alloc/ordre** | **déjà fermé** (#160, swap-pop **puis** `boatFree`) |
| `removePlayer` bateaux/missiles `table.remove` (N106) | **P3 alloc/ordre** | **déjà fermé** (#160, swap-pop **sans** free-list, cycle) |
| `IntentValidator.clearPlayer` `table.remove` (N107) | **P3 alloc/ordre** | **corrigé** (swap-pop, payload live) |
| `Bots.botSlots` / `Tribes.tribeSlots` `table.remove` (N108) | **P3 alloc/ordre** | **corrigé** (swap-pop nombres, pas de free-list) |
| `WorldRenderer.dirtyQueue` `table.remove(1)` (N109) | **P3 alloc/ordre client** | **ouvert** (leftover N107 — serveur `table.remove` O(n) épuisé) |
| `HUD.feedEntries` `table.remove` (N110) | **P3 alloc/ordre client** | **ouvert** (leftover N109) |
| `stepDoomsday` scan O(TILE_COUNT) (N9 / N75) | **P2 cadran** | **ouvert** (index compact — leftover N73 ; contrat A trop structurel ici) |
| `retreatBoats` filtre `owner[targetTile]` courant | **P2 marine** | **ouvert** (reste de N28 ; feel d425/df65 a la recette) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29 ; N98 pool le record, **pas** la fusion) |
| `findSpawn` ignore splash / fallout (N33) | **P3 nucléaire** | **ouvert** (feel d425/df65 a C1+C2 + `isSpawnSafe`) |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#160 + allyBuf (N72) + stripBuf (N73) + stripTerritory hashes (N74) + detonate hashes (N76) + splitMirv hashes (N77) + TickMetrics ring (N78) + snapshot arrays (N79) + reset pool (N80) + snapBuf (N81) + intentPool (N82) + notify/sound pool (N83) + rosterBuf (N84) + plunderPool (N85) + matchUpdateBuf (N86) + contextBuf (N87) + recordBuf (N88) + settledRecPool (N89) + profileBuf (N90) + metaBuf (N91) + deliveryPool (N92) + portRecPool (N93) + factoryRecPool (N94) + buildingRecPool (N95) + boatFree (N96) + missileFree (N97) + attackFree (N98) + AimFront Heap (N99) + swap-pop missiles (N100) + RailPath Heap (N101) + swap-pop Attack (N102) + RailPath runs (N103) + park swap-pop (N104) + boat order (N105) + remove order (N106) + clear order (N107) + slot order (N108).
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #160

**À merger** (`despawnBoat` swap-pop + `removePlayer` boats/missiles swap-pop + specs N107–N108), sous réserve que cette passe 49 parte avec : **`IntentValidator.clearPlayer` jetait encore `table.remove`, et `Bots.step` / `Tribes.step` encore `table.remove`**.

Points encore vrais après #160 :

| Claim #160 | Réalité après passe 49 |
|---|---|
| N105 `Navy.despawnBoat` `table.remove` | confirmé (swap-pop + `boatFree`, 3 transports rawequal A/C) |
| N106 `removePlayer` bateaux/missiles `table.remove` | confirmé (swap-pop sans free-list, tiers reste, refund 100 %) |
| N107 `IntentValidator.clearPlayer` `table.remove` | **fermé ici** (swap-pop, payload live, no-op user absent) |
| N108 `Bots.botSlots` / `Tribes.tribeSlots` `table.remove` | **fermé ici** (swap-pop nombres, `{2,8}`, pas de free-list) |
| N75 `stepDoomsday` scan O(TILE_COUNT) | **ouvert** |
| N33 `findSpawn` splash / fallout | **ouvert** |
| N28 retraite après flip / `targetSlot` | **ouvert** |
| N29 `seedBeachhead` no-merge | specs only, inchangé (banc N68 / N98 / N102 / N104 documente 3 Attack) |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |

`init.server.luau` et `Persistence` restent **exclus du bundle**. Le helper `MatchLifecycle` est **dans** le bundle (37 modules serveur — pas de module nouveau). `clearPlayer` / `Bots.step` / `Tribes.step` sont **dans** le bundle. `Heap.frontier` **reste unique entre vies** (N98) et **identité pendant la vie** (N99). Path `RailPath.find` **unique** (N101). Overlay retrace via `RailPath.find` + `runs` (aucun octet réseau) — lit le tableau **sync**, pas le Heap. Overlay lit `snapshotBoats` / `snapshotMissiles` (N51/N52), **pas** l’ordre live. `removePlayer` missiles **sans** `missileFree` (cycle GameState→Nukes — N106). `BoatFront.parkedBuf` **ne push pas** (gare live, swap-pop N104). `Navy.despawnBoat` **push** `boatFree` après swap-pop (N105). Payload Intent **live** (N82 — N107 ne le poole pas). `WorldRenderer.dirtyQueue` encore `table.remove(1)` (N109). `HUD.feedEntries` encore `table.remove` (N110).

PR feel / visual ne doivent pas être mergées par-dessus #16/#160 sans rebase. Seq / `targetSlot` / hover `SpawnHint` / Overlay `retreating` / `TRAIN_STOP_BONUS` HUD / `previewCtx` restent feel-only.

On peut fermer #17, #18, #20, #23, #25, #27, #30, #31, #33, #35, #37, #40, #43, #46, #49, #52, #55, #58, #60, #63, #66, #70, #73, #76, #80, #83, #85, #88, #91, #95, #98, #102, #104, #109, #112, #116, #119, #123, #127, #130, #135, #138, #141, #145, #149, #152, #156 et #160 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| `IntentValidator.clearPlayer` `table.remove` (N107) | `IntentValidator.luau`, `tests/simulate.luau` | Swap-pop (`queue[i] = queue[#]` ; `# = nil`). While reverse + decrement **toujours**. Payload **live** — pas de `table.clear` du record (N82). Banc 3 intents A/B/A, rawequal B, leftover `[2]==nil`, no-op user absent **verts**. **Ne pas** changer `enqueue` / `flush`. **Ne pas** `require` GameState (cycle inverse). |
| `Bots.botSlots` / `Tribes.tribeSlots` `table.remove` (N108) | `Bots.luau`, `Tribes.luau`, `tests/simulate.luau` | Swap-pop nombres (`arr[i] = arr[#]` ; `# = nil`). While reverse + decrement **toujours** (y compris après `continue` si `ps` nil). Pas de free-list. Banc `{2,5,8}` → `{2,8}` bots **et** tribus **verts**. **Ne pas** corriger N12 (18 factions). `DECISION_INTERVAL` / `humanTargetProtected` / `areAllied` inchangés. |

**Non modifié (volontaire) :** N1–N106 restant, reste de N28 (`targetSlot`). N10.8. Cap beachheads (N5 / N29). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` / `require(Placement)` / `require(MatchLifecycle)` / `require(IntentValidator)` / `require(ChantierB)` depuis GameState. Pas de contrat C spawn (N33). Pas de seq obligatoire (feel N41). Pas de spatial hash warships. Buffer `defense` **alloué** mais plus écrit. Pas de `TRAIN_STOP_BONUS` dans `railIncome`. Scan cadran encore O(carte) (N9 / N75). `WorldRenderer.dirtyQueue` encore `table.remove(1)` (N109). `HUD.feedEntries` encore `table.remove` (N110). Pas de `retreating` Overlay. Debit `captures`/`pops` **non** remplacé par feel `guard < 80`. `PlacementPreview` / `tests/client.luau` **non** édités. Skip AFK cadran **conservé**. Payload Intent = référence live (N82). Persistence `UpdateAsync` **non** poolé (N6). `building.links` unique (N65). `boat.path` unique (N64). `Heap.frontier` unique entre vies (N98). Path `RailPath.find` unique (N101). Pools PORT / FACTORY / Building / missile / Attack **non fusionnés**. `freeSlots` `table.remove` **hors scope** (pop stack O(1)). `missileFree` / `boatFree` / `attackFree` `table.remove` **hors scope** (pop stack O(1)).

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead + parkedBuf + acquireAttack + park swap-pop), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + **captures < 80 et pops < 160**). Attack record **poolé** (N98). `AimFront.focus` **recycle** Heap/queued pendant la vie (N99). `releaseAttack` swap-pop au despawn (N102). `Heap.frontier` unique entre vies. `BoatFront.parkedBuf` **sans** `releaseAttack` (swap-pop N104).
- **Posted** : bunkers / SAM / SILO / FACTORY / PORT / NAVAL_BASE / `buildingsBySlot` inchangés vs #160. Record Building **poolé** (N95). Sidecars PORT/FACTORY **poolés** (N93/N94).
- **Têtes de pont** = `BoatFront.seedBeachhead` via `acquireAttack` (N98) : frontier = **voisins encore à la cible**, flag `isBeachhead`. `launchAttack` gare les beachheads dans `parkedBuf` **sans** `releaseAttack` (swap-pop N104). Insert sémantique encore un Attack par débarquement (N29).
- **Pacte vivant** = `areAllied` : deux sens **et** `tick < expiry` (ou `true` legacy tests). `Diplomacy.accept` `releaseAttack` swap-pop les fronts du couple (N102).
- **Porte-avions** = `syncCarriers` événementiel + spawn via `navalBasesBySlot` + `acquireBoat` (N96). `despawnBoat` swap-pop + `boatFree` (N105).
- **Commerce maritime** = `portsByTile` incrémental + `spawnTradeShips` `acquireBoat` (N96). Vague plafonnée avant flatten. Accostage / PORT détruit / own-tile = `despawnBoat` swap-pop (N105).
- **Voies** = `refreshRailNetwork` eventuel (N65 `stationBuf`). Trace client = `RailPath.find` (`searchHeap` — N101) + `runs` (`runBuf` — N103). Path **unique**. Pas d’octet réseau : le client recalcule.
- **Nucléaire** = `Nukes.missileFree` (N97) + swap-pop array (N100). Overlay lit `snapshotMissiles` (N52), pas le live. `removePlayer` missiles **sans** free-list (cycle — N106 **fermé**).
- **Intents** = `intentPool` (N82) + `clearPlayer` swap-pop (N107). Payload **live**. Disconnect mid-match n’alloue plus de décalage O(n) sur la file.
- **IA** = `botSlots` / `tribeSlots` swap-pop (N108). `elimBuf` (N63) inchangé. Collapse en chaîne plus O(n²) `table.remove` le même tick que `removePlayer`.
- **Réplication** : inchangée vs #160.
- **DataStore** : `settledHumans` poolé (N89). `endMatchRecords` poolé (N88). Persistence `UpdateAsync` **non** poolé (N6).
- **Require** : DAG. Pas de cycle. N107 dans IntentValidator. N108 dans Bots/Tribes. Ne pas `require(IntentValidator)` depuis GameState. Ne pas `require(GameState)` depuis IntentValidator.

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N110 restent ouverts** sauf N19 partiel, N21 **fermé**, N24 remplacé par N31 (**fermé**), N30–N32 **fermés**, N34–N74 **fermés**, N76–N108 **fermés**. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + N75 + le reste de N28 / N29 / N33.

---

### ISSUE-N28 — `retreatBoats` / `retreatAttack` après flip de côte (reste)

**Priorité :** P2 combat / comptabilité navale. **Partiel :** inbound `removePlayer` **fermé** en passe 8.

**Problème restant :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetSlot`. Conséquences encore vraies :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers).
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

Feel d425 (N49) + df65 (N53) : `launchInvasion` pose `targetSlot`, `retreatBoats` filtre l’intention (fallback `owner[targetTile]`), wrap 2e geste rappelle les tardifs, `Navy.step` auto-retraite si `owner[targetTile] ~= targetSlot`. **Porter, ne pas réinventer.** Distinct de N10.8 et du fix inbound. Distinct de N96 (`boatFree` — **déjà fermé**). Distinct de N97–N110.

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite.

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste, trancher si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`. Recette feel : branche `d425` / `df65`. `acquireBoat` doit overwrite `targetSlot` (N96 — leftover `targetSlot` d’un convoi recyclé en transport = retraite du mauvais camp).

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N22). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % déjà livré). Ne pas recâbler N35 (convois, `kind==2`). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).** Ne pas porter AimFront ni seq. Ne pas recâbler N50–N110. Ne pas casser `boatFree` (N96) : tout nouveau champ **doit** être écrit dans `acquireBoat`. `despawnBoat` reste swap-pop (N105).

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

**Contraintes :** ne pas fusionner beachhead avec front terre (régression BoatFront / aim). Ne pas changer `attackTilesPerTick`. Ne pas mixer avec N28 (bateaux inbound / targetSlot). Ne pas mixer avec N68 (`parkedBuf` — leftover alloc, **déjà fermé**). Ne pas mixer avec N98 (pool Attack — leftover alloc, **déjà fermé**) ni N99 (Heap pendant la vie, **déjà fermé**) ni N102 (swap-pop despawn, **déjà fermé**) ni N104 (park, **déjà fermé**) ni N105–N108 (ordre, **déjà fermé**). **N29 hardening ≠ N29 feel (seq avant apply).** Ne pas recâbler N109/N110.

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

**Contraintes :** ne pas annuler une frappe tiers (régression `nuke third-party`). Ne pas rembourser l’or. Pas de RemoteFunction. Rayon lu depuis `NUKE_STATS` / `missile.radius`, pas une constante magique. Ne pas porter isolation clic (feel N55) dans le même PR. Ne pas recâbler N50–N110. Ne pas mixer N76 (`tilesBeforeBuf` — **déjà fermé**) ni N77 (`mirvTxBuf` — **déjà fermé**) ni N97 (missile live, **déjà fermé**) ni N100 (swap-pop, **déjà fermé**) ni N106 (`removePlayer` missiles, **déjà fermé**).

---

### ISSUE-N75 — `stepDoomsday` scanne encore `0..TILE_COUNT-1` par camp qui saigne

**Priorité :** P2 cadran / perf. Leftover explicite de N9 et de N73. Distinct de N73 (`stripBuf`, **déjà fermé**) et de N74 (`stripTerritory` hashes, **déjà fermé**). Ne pas toucher `rotQuota`. **N75 hardening ≠ N75 feel historique (`pricesFor`).** Visual V13 décrit le même trou. **Non livré en passe 49** : contrat A (`tilesBySlot` maintenu dans `setOwner`) est un index d’autorité — un déréglage vs `owner` pourrit le mauvais camp. Trop structurel pour un correctif « sûr » à côté de N107/N108.

**Problème :** même avec `stripBuf` recyclé, chaque slot sous quota (10 Hz, late-game plusieurs camps) re-scanne `Config.TILE_COUNT` (40 960) jusqu’à `quota * 4` hits. Un shard 18 factions en cadran = jusqu’à ~17 scans linéaires / tick. Il n’existe pas d’index compact tuiles-par-slot : `ps.tiles` est un compteur, `ps.border` / `ps.coast` ne couvrent pas l’intérieur. N73 a volontairement laissé ce scan.

**Pourquoi 20K CCU :** leftover N9. Late-game cadran = le tick le plus cher du shard (hors combat). Recycle de la porteuse (N73) n’enlève pas les 40k reads `buffer.readu8`. Un index compact ramène le rot à O(tuiles du camp) au lieu de O(carte).

**Worker :**

1. Choisir un contrat : (A) `tilesBySlot[slot] = { number }` array compact, maintenu dans `setOwner` (insert au claim, swap-pop au loss) — `stepDoomsday` itère `1..ps.tiles` au lieu de `0..TILE_COUNT-1` ; (B) reservoir bitset 40 960 / 8 recyclé, rebuild seulement si dirty ; (C) documenter « scan O(carte) accepté, N9 fermé sans code ». **Un seul.** Feel / visual n’ont pas encore fermé V13. Pas de RemoteFunction.
2. Si A : `setOwner` est le **seul** writer. Capture, nuke crater, strip, collapse, spawn doivent tous passer par là. Test : 6000 ticks, `ps.tiles == #tilesBySlot[slot]`, rot n’émet plus de tuile `owner ~= slot`. Banc N73 / N74 **verts**.
3. Fichiers : `GameState.setOwner` + `ChantierB.stepDoomsday` (via `install()`), `tests/simulate.luau`. Pas de require GameState ↔ ChantierB nouveau.

**Contraintes :** pas de RemoteFunction. **N75 hardening ≠ N73 (`stripBuf`, déjà fait) ≠ N74 (`border`/`coast`, **déjà fait**) ≠ N76–N108 (déjà faits) ≠ N9 (umbrella — ce ticket **ferme** N9 si A ou C).** Ne pas changer `rotQuota` / drain / WARN. Overlay n’itère pas l’index. Un index déréglé vs `owner` = pourriture du mauvais camp. Ne pas `require(ChantierB)` depuis GameState. Ne pas mixer avec N109 (`dirtyQueue`) ni N110 (`feedEntries`).

---

### ISSUE-N107 — `IntentValidator.clearPlayer` `table.remove` — **FERMÉ** (passe 49)

Swap-pop **sans** pooler le payload + while reverse + decrement toujours. Banc : 3 intents A/B/A, rawequal B, leftover `[2]==nil`, no-op user absent. Ne pas rouvrir. Un intent B sauté = ordre fantôme (banc N82 `#queue==0`). Payload live (N82). Leftover client `dirtyQueue` → N109.

---

### ISSUE-N108 — `Bots.botSlots` / `Tribes.tribeSlots` `table.remove` — **FERMÉ** (passe 49)

Swap-pop nombres **sans** free-list + while reverse + decrement toujours. Banc : `{2,5,8}` → `{2,8}` bots **et** tribus, pas de trou. Ne pas rouvrir. Un bot sauté = slot recycle (banc grace / N12). Ne **pas** « corriger » 18 factions ici. Leftover client `dirtyQueue` → N109. Leftover `feedEntries` → N110.

---

### ISSUE-N109 — `WorldRenderer.dirtyQueue` `table.remove(1)` encore O(n)

**Priorité :** P3 ordre client / rebuild. Leftover explicite une fois le `table.remove` serveur O(n) **épuisé** (N100–N108 ; `freeSlots` / `boatFree` / `missileFree` / `attackFree` = pop stack O(1), hors scope). Distinct de N105–N108 (serveur, **fermés**). **N109 hardening ≠ N109 feel historique (câble PORT).** Recette feel N112 (`dirtyHead` + truncate) + N114 (compact préfixe seuil 32) — **porter, ne pas merger** la ligne feel.

**Problème :** `WorldRenderer.stepRebuilds` fait `table.remove(self.dirtyQueue, 1)` jusqu’à `CHUNK_REBUILDS_PER_FRAME`. Un delta owner late-game (p95Changed=28, maxChanged=970 sur le banc 6000 ticks) enfile des dizaines de chunks ; chaque pop décale le suffixe. Feel a déjà `dirtyHead` + compact 32 — cette ligne hardening **n’a pas** ces champs.

**Pourquoi 20K CCU :** leftover naturel une fois le serveur swap-popé. Le rebuild 60 Hz est le tick client le plus cher hors interpolation Overlay. Un `table.remove(1)` par chunk × budget = O(n × budget) copies de références par frame, sur le même joueur qui reçoit le delta owner (N53 `dirtyIndexBuf` déjà fermé côté serveur).

**Worker :**

1. Recette feel `04e7` N112 + `846c` N114 : champ `dirtyHead`, pop = `queue[dirtyHead]` puis `dirtyHead += 1`, truncate leftover après compact. Compact préfixe quand `dirtyHead >= 32` (`DIRTY_COMPACT_HEAD`). Plus de `table.remove(1)`. Pas de RemoteFunction. **Ne pas** merger Overlay `retreating` (feel N56) ni houle/feuillage (feel N107/N108).
2. Ne pas changer `rebuildChunk` / `applyDelta` (N95 feel `gainBuf` déjà sur feel, **pas** ici). Banc client **34/34** (`deltas de terrain et conquetes classees`, `construction du monde 3D`). Serveur **inchangé**.
3. Test client : enfiler 3 chunks, `stepRebuilds` budget 1 → tête avancée, leftover `[1]` encore présent jusqu’au compact, pas de trou. Second test : 40 marks, compact seuil 32, `dirtyHead` reset, queue compacte. 6000 ticks serveur **verts**.
4. Fichiers : `StarterPlayerScripts/Client/WorldRenderer.luau` (`stepRebuilds` + enqueue), `tests/client.luau` seulement si un assert nouveau est nécessaire — **préférer** le banc existant 34/34. `GameState.luau` / `IntentValidator.luau` / `Bots.luau` / `init.server` inchangés. Recette feel N112/N114 (pas merger).

**Contraintes :** pas de RemoteFunction. **N109 hardening ≠ N112 feel (déjà fait sur feel) ≠ N107 (clearPlayer, déjà fait) ≠ N108 (botSlots, déjà fait).** Un chunk sauté = terrain fantôme (banc `deltas de terrain`). Ne pas mixer N28 / N33 / N75 / N110. Ne pas porter `retreating` Overlay. Ne pas casser client **34/34**. Serveur 37 modules inchangé.

---

### ISSUE-N110 — `HUD.feedEntries` `table.remove` encore O(n)

**Priorité :** P3 ordre client / HUD. Leftover explicite de N109 (même famille `table.remove` client). Distinct de N83 (`eventPool` serveur, **fermé** — Overlay lit tout de suite). Distinct de N97 feel (`self.ranked`, **déjà** sur feel, **pas** ici). **N110 hardening ≠ N110 feel historique (lift chantier).**

**Problème :** `HUD` (fil de notifications) : (1) `removeEntry` fait `table.find` + `table.remove(self.feedEntries, index)` ; (2) le plafond `MAX_FEED_ENTRIES` fait `table.remove(self.feedEntries, 1)` **puis** rappelle `removeEntry` (double retrait aujourd’hui no-op grâce à `table.find` après le pop). Un combat late-game spam le fil (captures, trahisons, nukes) ; chaque expiration / croix / overflow décale le suffixe. Le banc client a « fil de notifications sature ».

**Pourquoi 20K CCU :** leftover client une fois `dirtyQueue` spécifié. Le fil n’est pas 10 Hz serveur mais 60 Hz UI + `task.delay(4.5)`. Un overflow + expiration le même frame = deux `table.remove` O(n) sur la même array, pire si `removeEntry` est rappelé sur une entrée déjà popée. Pas d’autorité (affichage seulement) ; un message sauté = notification serveur déjà drainée (N83) invisible.

**Worker :**

1. Recette N107 (swap-pop) pour `removeEntry(index)` : `entries[i] = entries[#]` ; `# = nil`. Pour l’overflow FIFO (`table.remove(1)`) : même `dirtyHead` que N109 **ou** swap-pop seulement si l’ordre visuel est `LayoutOrder` (déjà posé via `feedCounter`) — **trancher** : si LayoutOrder suffit, swap-pop des deux chemins ; si l’ordre du tableau = ordre d’affichage, head-pointer. Corriger le double-retrait overflow → `removeEntry` (aujourd’hui `table.remove(1)` puis `removeEntry` refait `table.find`). Pas de RemoteFunction.
2. Ne pas changer `feedGroups` / sons / `Theme`. Banc client « fil de notifications sature » **vert**. Client **34/34**. Serveur inchangé. N83 `drainEvents` **non** touché.
3. Test client : 3 messages, retirer le milieu → `# == 2`, pas de trou, groupes cohérents. Overflow `MAX_FEED_ENTRIES + 1` → oldest détruit **une** fois, pas de Label orphelin. 6000 ticks serveur **verts**.
4. Fichiers : `StarterPlayerScripts/Client/HUD.luau` (`removeEntry` + overflow seulement), éventuellement `tests/client.luau`. `WorldRenderer.luau` / `GameState.luau` / `IntentValidator.luau` / `init.server` inchangés. Recette N107 (pas feel). **N109 et N110 dans le même PR** (même leftover client, deux fichiers) — ou N109 seul si le worker reste 1 fichier.

**Contraintes :** pas de RemoteFunction. **N110 hardening ≠ N83 (events serveur, déjà fait) ≠ N109 (dirtyQueue, ticket jumeau) ≠ N97 feel (ranked).** Un message sauté = fil fantôme (banc sature). Ne pas mixer N28 / N33 / N75 / N12. Ne pas porter feel HUD ranked / Overlay. `freeSlots` `table.remove` **hors scope** (pop O(1)).

---

## 5b. N1–N110 encore ouverts ou fermés (passes 2–49)

| ID | Titre | Prio | Note passe 49 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + `SAM_INTERCEPT_CHANCE` 0.55→1 ; clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz ; … ; `clearPlayer` → **N107 fermé** ; `botSlots` → **N108 fermé** ; `dirtyQueue` → **N109** |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` **jamais** `FireServer` côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | park `isBeachhead` → hors cap land ; **2 beachheads parked + 1 terre = 3** — voir N29 ; alloc Attack → **N98 fermé** ; park ordre → **N104 fermé** |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions. **Ne pas** pooler. |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | refund + retraite `RETREAT_LOSS` alignés ; wrap vivant → **N67 fermé** ; Attack record → **N98 fermé** ; Heap visée → **N99 fermé** ; swap-pop despawn → **N102 fermé** ; park → **N104 fermé** |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | timers slot maintenant purgés ; liste temporaire → **N73 fermé** ; hashes spawn → **N74 fermé** ; le scan rot est toujours O(tuiles) → **N75** |
| N10 | Divers P3 | P3 | donations gold sans plafond ; `pendingMode` last-writer ; … ; `clearPlayer` → **N107 fermé** ; `botSlots` → **N108 fermé** ; `dirtyQueue` → **N109** |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | debit = `attackTilesPerTick` × speed, **captures<80 pops<160** |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 observé) | P1 | `Bots.spawnAll` wrap + `Tribes.spawnAll(6)` hors budget. Ne **pas** fermer dans N108. |
| N13–N27 | (ère / heap / embargo / rail HUD / QuickChat / warships / …) | — | inchangés vs passe 48 ; voir rapport #160 |
| N28 | `retreatBoats` après flip | P2 | **partiel** : inbound fermé passe 8 ; `targetSlot` ouvert (recette feel N49/N53). Si porté : overwrite dans `acquireBoat` (N96). |
| N29 | `seedBeachhead` no-merge | P2 | specs only. Banc N68 / N98 / N102 / N104 documente 3 Attack (2 ponts + terre). Distinct de N98 (alloc, **fermé**) et N104 (ordre park, **fermé**). |
| N30–N32 | inbound missile / pool BFS / convoi | P2 | **fermés** |
| N33 | `findSpawn` splash / fallout | P3 | specs only (recette feel N50/N52) |
| N34–N74 | (index / snapshots / HUD / diplomatie / bots / combat wrap / pose) | — | **tous fermés** (passes 11–32). Voir rapport #102. |
| N75 | `stepDoomsday` scan O(TILE_COUNT) | P2 | specs only. Leftover N9 / N73. Ferme N9 si contrat A ou C. **Non livré ici** (A trop structurel). |
| N76–N106 | detonate / MIRV / TickMetrics / Intent / notify / roster / plunder / MatchUpdate / context / gravure / settled / profile / mapMeta / dispatch / portRec / factoryRec / buildingRec / boatFree / missileFree / attackFree / AimFront Heap / missile order / RailPath Heap / Attack ordre / runs / park / despawnBoat / removePlayer boats | P3 | **fermés** (passes 33–48) |
| N107 | `IntentValidator.clearPlayer` `table.remove` O(n) | P3 | **fermé**. Leftover N82. Swap-pop, payload live. |
| N108 | `Bots.botSlots` / `Tribes.tribeSlots` `table.remove` | P3 | **fermé**. Leftover N63. Swap-pop nombres, pas de free-list. |
| N109 | `WorldRenderer.dirtyQueue` `table.remove(1)` | P3 | specs only. Leftover client. Recette feel N112/N114, porter ne pas merger. |
| N110 | `HUD.feedEntries` `table.remove` | P3 | specs only. Leftover N109. Swap-pop / head, corriger double-retrait overflow. |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu ; disconnect mid-match **vivant** = `Persistence.record(..., false)` 0 XP ; wrap `launchAttack` n’applique `AimFront.focus` que si le couple n’existait pas (N99 **fermé** — Heap identique au renfort) ; spatial hash warships volontairement non fait ; payload Intent = référence live (N82) ; `{ index = … }` RemoteEvent = possession ; `MapGen.countByBiome` encore alloué (test-only) ; `freeSlots` / `boatFree` / `missileFree` / `attackFree` `table.remove` (pop O(1), hors N106/N108).

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
  … gardes #17–#160 inchangés …
  boat order : swap-pop milieu, rawequal A/C + boatFree (N105)
  remove order : swap-pop inbound/own, tiers reste, pas de free-list (N106)
  clear order : swap-pop A/B/A, rawequal B, no-op absent (N107)
  slot order : botSlots swap-pop milieu rawequal {2,8} (N108)
  slot order : tribeSlots swap-pop milieu rawequal {2,8} (N108)
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 captures=80 pops=160
  factions : 18
  metrics : ticks=6000 avgChanged=10.0 p95Changed=28 maxChanged=970 avgTickMs=0.36 p95TickMs=1.31
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe49.log`

---

## 8. Instructions worker (si reprise)

- Vérité runtime d’équilibrage = `ChantierB.apply(Config)` après `SystemsBootstrap.install()`, PAS `Config.luau` seul.
- Combat vivant = patches ChantierB, pas `GameState.stepAttacks` (sauf `returnCommittedTroops` et `retreatAttack`, partagés). Debit **captures < 80 / pops < 160** (pas feel `guard < 80`). Despawn Attack = `self:releaseAttack(i)` (swap-pop N102, pas `table.remove` nu). `BoatFront.parkedBuf` **sans** `releaseAttack` (swap-pop N104).
- `areAllied` = deux sens **et** expiry. Ne pas revenir à un test `~= nil`. Bots / chat / tribus : **jamais** `alliances[slot][other]` comme vérité.
- `retreatAttack` = **tous** les fronts du couple. Ne pas revenir à un `return` au premier match.
- Cote déjà nôtre ≠ retraite. Allié en mer = toujours retraite 25 % (N10.8). Inbound disparu = 100 % (comme front terre).
- Purge inbound d’un slot = **dans `removePlayer`**, pas seulement dans `Diplomacy.step`. Inclut cadran + colis + **transports** + **missiles** + **convois kind==2** (avant `setOwner`). Swap-pop arrays (N106), **sans** free-list.
- Ne pas `require(Navy)` / `require(Nukes)` / `require(Trade)` / `require(Bots)` / `require(Buildings)` / `require(Research)` / `require(Diplomacy)` / `require(Placement)` / `require(MatchLifecycle)` / `require(IntentValidator)` / `require(ChantierB)` depuis GameState (cycle).
- Building live : `buildingRecPool[index]` (N95). `links` neuf à chaque pose (N65). Destroy nil l’index live. Ne pas fusionner avec `portRecPool` / `factoryRecPool`.
- Bateau live : `Navy.boatFree` (N96). `acquireBoat` overwrite + `_sink` nil. `despawnBoat` swap-pop **puis** push (N105). `path` unique (N64). Tout nouveau champ (N28 `targetSlot`) **doit** être écrit dans `acquireBoat`. Ne pas `require` Navy depuis GameState. `removePlayer` bateaux **sans** `despawnBoat` (N106, pas de double-free).
- Missile live : `Nukes.missileFree` (N97). `acquireMissile` overwrite + `engaged`/`warhead` nil (sauf ogive). Despawn porteur **avant** split. Swap-pop array (N100). Ne pas `require` Nukes depuis GameState. `removePlayer` missiles **sans** free-list (N106).
- Attack live : `GameState.attackFree` (N98). `acquireAttack` Heap neuf + queued neuf. `AimFront.focus` `Heap.clear` + `table.clear` (N99). `releaseAttack` swap-pop (N102). `freeAttack` si abort. BoatFront wrap via le helper. Ne pas pooler `Heap.frontier` **entre** Attacks. Park **sans** `releaseAttack` (swap-pop N104).
- Voies : `RailPath.searchHeap` + hashes `table.clear` (N101). Path **unique**. `runs` module `runBuf` (N103, Overlay sync). Overlay retrace, pas d’octet réseau.
- Notify / sfx : `eventPool` / `soundPool` (N83). Overlay lit tout de suite.
- File d’intents : `IntentValidator.enqueue` réécrit `intentPool[n]` (N82). **Payload = référence live — ne pas pooler**. `clearPlayer` swap-pop (N107).
- IA : `Bots.botSlots` / `Tribes.tribeSlots` swap-pop (N108). Pas de free-list. Ne pas corriger N12 ici.
- `init.server` / `Persistence` restent hors bundle.
- Ne pas casser le client 34/34.
- Ligne feel : rebase sur cette passe avant cherry-pick, sinon perte swap-pop `clearPlayer` / `botSlots`. Cherry-pick seq obligatoire (N41 feel) et `targetSlot` (N49 feel) seulement — et overwrite `targetSlot` dans `acquireBoat`. **Ne pas** porter `retreating` Overlay (feel N56). **Ne pas** porter `TRAIN_STOP_BONUS` HUD. **Ne pas** porter feel `guard < 80`. Client feel = 35/35 ; client hardening = **34/34**. N109/N110 = porter recette feel `dirtyHead` / HUD feed **sans** merger le reste de la ligne feel.
