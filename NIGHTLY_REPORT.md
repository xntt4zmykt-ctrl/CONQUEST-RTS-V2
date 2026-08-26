# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 31)

Déclencheur : ouverture de la **PR #93** (`cursor/analyse-nocturne-du-codebase-e277`) — destroyBuf, validTiles, specs N91–N92.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-1e43`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#93.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. `allyBuf` est un pool module-level (hash, pas de l’état répliqué). `previewCtx` est le ctx **client** du fantôme : le serveur re-résout à l’enqueue. `ctxBuf` Buildings n’est pas le ctx client.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #93 (passe 30) : claims vérifiés.** `GameState.removePlayer` recycle `destroyBuf` (N89) ; `Placement.validTiles` recycle `blockBuf` / `candBuf` / `queueBuf` / `visitBuf` / `emptyTileBuf` (N90). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #93 a documenté (N91, N92)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #93

| Claim #93 | Réalité à l’ouverture |
|---|---|
| `destroyBuf` (N89) | Oui. Truncate leftover **avant** `destroyBuilding`. Slot vide / absent → return. Inter-instances A→B : CITY de B survit. Fallback hash conservé. |
| `validTiles` pools (N90) | Oui. Early-out → `emptyTileBuf` (`rawequal`). Truncate leftover **avant** BFS et **avant** sort. Deux `resolve` CITY → même `tile`. Hors carte `# == 0`. Preview client **n’était pas** touché. |
| Specs N91–N92 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #91 (9327), feel jusqu’à #93, visuelles #39/#44/#47/#50/#54/#57/#61/#64/#67/#69/#72/#74/#77/#79/#81/#84/#87/#90 (allyBuf/stripBuf) / #92 (parkedBuf). **#93 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#91) reste distincte. Ne pas merger visual `d3e2` / `9a1f` ni hardening `9327` / `ca14` sans rebase.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N91–N92 du rapport #93.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `Bots.decideDiplomacy` alloue `or {}` (N91) | `Bots.luau` (`decideDiplomacy` seulement), `tests/simulate.luau` | Leftover N80. `allyBuf` module + `table.clear` puis copie des clés de `state.alliances[slot]`. Itérer `allyBuf`, pas `or {}`. Bot sans pacte → `next` nil. Leftover A→C absent. Trahison force × 2.2 + frontière > 4 rompt. Recette visual V42 (hash), **pas** merger `d3e2`. Pas `contactBuf`. |
| `PlacementPreview.resolve` alloue un ctx par hover (N92) | `PlacementPreview.luau` (`resolve` seulement) | Leftover N90 / N85. `previewCtx` module + champs réécrits. Même `Placement.resolve` Shared. `setKind` / `update` / footprint inchangés. Client 35/35. Pas `Placement.luau` / `Buildings.luau`. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, `stepDoomsday` `toStrip = {}` (**N93**), `stripTerritory` `border`/`coast` (**N94**), corps mort `GameState.stepAttacks` `local collapsing`.

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (seq obligatoire en playing, apply immédiat) → tick :
  Bots.step → Navy.step (syncCarriers si dirty, spawn via navalBasesBySlot ;
    stepCarriers via carrierBuf/targetBuf, early-out 0 carrier / 0 autre slot ;
    coule TRADE si PORT absent ; TRANSPORT retraite si owner ~= targetSlot ;
    spawnTradeShips si tick % 45 == 0, via portsByTile ;
    findSeaPath via pathWalkBuf, retour unique) → Nukes.step
              (stepCooldowns SAM+silo indexés ; tryIntercept via samsBySlot ;
               launch via silosBySlot) → Trade.step (factoriesBySlot + factoryBuf)
              → Diplomacy.step (expiredBuf N79) → GameState.step → replicate(
                flushOwnerDelta via dirtyIndexBuf,
                playerStatsForReplicate + pricesFor + Research.progress (min courant),
                fireDeployed, snapshotBoats, snapshotMissiles,
                flushBuildingDelta via buildingSnapBuf)
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom,
    cancelOpposingFronts via doomedBuf, collapsingBuf 10 Hz), BoatFront
    (park isBeachhead via parkedBuf), AimFront,
    tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`. Stub = `error(...)`. Deux débarquements du même couple = **deux** tas (N5 ouvert). Wrap `launchAttack` gare via `parkedBuf` (**N87**).
- **`areAllied`** = deux directions **et** `tick < expiry` (`true` legacy tests reste vivant).
- **AimFront wrap** = re-visée du front terre du couple ; jamais `isBeachhead`.
- **`tryAnnex`** = BFS depuis les voisins défenseur du seed déjà capturé ; océan abort ; pool N37-like.
- **Carriers** = spawn/despawn/slot sur dirty NAVAL_BASE, spawn via `navalBasesBySlot` (N65). Ciblage obus = `carrierBuf`/`targetBuf` recyclés **(N67)**. Pas de spatial hash.
- **Posted bunker** = index `bunkersBySlot`. **Posted SAM** = `samsBySlot`. **Posted SILO** = `silosBySlot`. **Posted FACTORY** = `factoriesBySlot`. **Tous** = `buildingsBySlot`. **PORT** = `portsByTile`. **Posted NAVAL_BASE** = `navalBasesBySlot`.
- **`samsOf`** = lit `samsBySlot` dans `samBuf` recyclé (N68). `tryIntercept` lit l’index directement (N57).
- **Score nuke bots** = flatten `buildingsBySlot` une fois (N69), puis 90 `scoreBlast`.
- **Inbound `removePlayer`** = snapshot `destroyBuf` (**N89**) → destroy → diplo + transports `kind==1` (100 %, lit **`owner[targetTile]`**) + missiles contrat B + cadran/colis + convois `kind==2` (coulés), **avant** `setOwner`.
- **Hover spawn** = `SpawnHint` (Shared) si `tiles==0`. Serveur = `claimSpawn` (N52+N55).
- **Réplication :** StateDelta (`dirtyIndexBuf` N72, HUD fronts N74 via N76, `buildPrices` N75, records stats N76, `eraProgress` N77) / UnitSnapshot (`retreating`, `boatSnapBuf` N70, `missileSnapBuf` N71) / BuildingDelta (`buildingSnapBuf` N73) / plunder / trade / explosions / notify&sfx déployés / Diplomacy.viewFor 1 Hz (N78). `path` / `homeTile` / `progress` **non** répliqués. Playing 10 Hz ; lobby vide et ended → 1 Hz. `Diplomacy.step` recycle `expiredBuf` (**N79**). `Bots.neighborFactions` recycle `contactBuf` (**N80**). `gatherSites` recycle `siteBuf` (**N81**). `stepElimination` recycle `elimBuf` (**N82**). `findSeaPath` walk scratch, retour unique (**N83**). `refreshRailNetwork` porteuses recyclées (**N84**). `Buildings.contextFor` recycle `ctxBuf` (**N85**). `ChantierB.cancelOpposingFronts` / wrap `stepAttacks` recyclent `doomedBuf` / `collapsingBuf` (**N86**). `BoatFront.launchAttack` recycle `parkedBuf` (**N87**). `collapseFaction` recycle `collapseRemainBuf` / `collapseLeftBuf` (**N88**). `removePlayer` recycle `destroyBuf` (**N89**). `Placement.validTiles` recycle blockers/candidates/queue (**N90**). `Bots.decideDiplomacy` recycle `allyBuf` (**N91**). `PlacementPreview.resolve` recycle `previewCtx` (**N92**). `stepDoomsday` alloue encore `toStrip = {}` (**N93**). `stripTerritory` alloue encore `border = {}` / `coast = {}` (**N94**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N93–N94)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N92 = faits. N22 = **N67 fait**. N27 = doc only.

---

### ISSUE-N93 — `ChantierB.stepDoomsday` alloue `toStrip` par faction sous quota (feel)

**Priorité :** P3 alloc cadran 10 Hz. Leftover explicite de N9 (`stepDoomsday` O(TILE_COUNT) — **ne pas** fermer N9 : le scan `0..TILE_COUNT-1` reste) et de la passe 30 (`stepDoomsday` `toStrip = {}`). Distinct de N86 (`collapsingBuf` combat) et de N82 (`elimBuf` slots). Recette visual V43 (`stripBuf` déjà sur `d3e2` — **porter, ne pas merger**). Ne pas toucher `stripTerritory` (N94) ni `rotQuota`.

**Problème :** chaque faction sous le quota du cadran, chaque tick, fait `local ripped, toStrip = 0, {}` puis `table.insert` jusqu’à `quota * 4`. Un shard 18 factions en fin de partie (plusieurs sous la barre) alloue une table **par camp par tick**. La loi (WARN_SECONDS, drain troupes, `rotQuota`, leader jamais touché, `awaitingSpawn` / `tiles==0` skip, destroyBuilding puis setOwner NEUTRAL) ne change pas. Un leftover de tuiles du slot A dans un buffer non truncaté arracherait le territoire de A pendant le rot de B.

**Pourquoi 20K CCU :** leftover N9 partiel. Le cadran tourne 10 Hz dès `wave.armed`. L’alloc courte `toStrip` est le seul tableau neuf du wrap `stepDoomsday` après N47 (purge recycle). Pas d’autorité (mêmes tuiles, même quota). Ne pas fusionner avec `elimBuf` (slots, pas tuiles) ni `destroyBuf` (bâtiments `removePlayer`). Visual V43 a déjà la recette sur une autre ligne.

**Worker :**

1. Ajouter `stripBuf: { number } = table.create(64)` module-level dans `ChantierB.luau`. Dans `stepDoomsday`, à la place de `toStrip = {}` : `local ripped, n = 0, 0` ; remplir `stripBuf[n] = index` ; cap `n >= quota * 4` inchangé. Truncate leftover **avant** l’arrachage (`#stripBuf` → `n+1`). Itérer `1..n`. Après le slot : truncate à 0 (`n..1`) pour que le slot suivant du **même tick** ne ré-arrache pas les tuiles du premier. Pas de RemoteFunction. Exposer `ChantierB.stripBuf` pour le banc (pas de filaire).
2. Ne pas modifier `rotQuota` / `WARN_SECONDS` / drain / troopFloor. Ne pas retirer le skip `awaitingSpawn` / `tiles==0`. Ne pas retirer le skip leader. Ne pas toucher `stripTerritory` (N94). Ne pas câbler un index tuiles-par-slot (N9 reste ouvert : le scan `0..TILE_COUNT-1` **reste**). Ne pas require de module nouveau. `stepDoomsday` est unique par tick mais **boucle les slots** : le reset entre slots est **voulu**.
3. Test : bancs cadran / recycle N47 existants **doivent rester verts**. Ajouter : 1 humain sous quota → tuiles diminuent, `ps.tiles` == count buffer. Deux slots marqués le même tick → chacun perd le sien (un leftover sans truncate arracherait les tuiles du premier pendant le second). Leader intact. Recette visual V43 (`GameState.new(3102)` shrinkTo 40, `tick = 12000`, `doomWarnedAt` / `doomUnderSince` 70s/40s). Client 35/35. 6000 ticks.
4. Fichiers : `ChantierB.luau` (`stepDoomsday` seulement, du `local ripped, toStrip` jusqu’à la boucle `setOwner`), `tests/simulate.luau` (bloc court, pas le banc N47 recycle). **Ne pas** éditer visual `d3e2` ni `Doomsday.luau` ni `GameState.stepAttacks`.

**Contraintes :** pas de RemoteFunction. Recette visual V43 (array + truncate, pas `table.clear` hash). **N93 feel ≠ N9 (scan O(carte), reste ouvert) ≠ N86 (`collapsingBuf`) ≠ N94 (`stripTerritory` hashes) ≠ visual V43 (déjà sur `d3e2`).** `stripBuf` n’est pas réentrant. Overlay n’itère pas cette liste. Un leftover sans truncate entre slots ferait `setOwner` d’une tuile du camp précédent.

---

### ISSUE-N94 — `ChantierB.stripTerritory` alloue `border = {}` / `coast = {}` (feel)

**Priorité :** P3 alloc spawn humain. Leftover explicite de la passe 30 (`stripTerritory` `border`/`coast`). Distinct de N93 (`stripBuf` tuiles du rot 10 Hz) et de visual V43 (même sujet cadran, pas le spawn). Ne pas toucher `stepDoomsday`.

**Problème :** `stripTerritory` (humain qui rejoint : wrap `addPlayer` Instance) fait `ps.border = {}` et `ps.coast = {}`. Deux tables neuves par join, et les anciennes hashes (déjà vidées par `setOwner` → tuiles 0) sont abandonnées. `setOwner` incrémente `border`/`coast` **sur l’objet PlayerState** : un buffer module partagé entre joueurs ferait polluer le voisin au premier `claimSpawn`. La loi (`tiles = 0`, capital détruite, `awaitingSpawn = true`, `capitalTile = nil`) ne change pas.

**Pourquoi 20K CCU :** leftover spawn. 8 humains / shard, chacun strip au join puis `claimSpawn`. Moins chaud que N93 (10 Hz) mais le couple `border`/`coast` est lu par `neighborFactions` / `gatherSites` / invariants. Allouer un `{}` neuf est inutile : `table.clear` sur les hashes **déjà** possédées par `ps` suffit. Pas d’autorité. Ne pas fusionner avec N93 : rot = liste d’indices, strip spawn = hashes de tuiles du joueur.

**Worker :**

1. Dans `ChantierB.stripTerritory` : `table.clear(ps.border)` et `table.clear(ps.coast)` **au lieu de** `= {}`. Ne **pas** introduire `emptyBorderBuf` module (un hash partagé serait muté par `setOwner` du premier `claimSpawn`). Pas de RemoteFunction. Ne pas `table.clone`.
2. Ne pas modifier `stepDoomsday` / `stripBuf` (N93). Ne pas toucher `placeDisk` / `claimSpawn` / `isSpawnSafe`. Ne pas require de module nouveau. Ne pas reset `ps.border = nil` (les appelants itèrent la hash, pas nil). `tiles = 0` / `awaitingSpawn` / destroy capital **inchangés**.
3. Test : bancs spawn clic / `awaitingSpawn` / `tiles==0` existants **doivent rester verts**. Ajouter : après `stripTerritory` sur un joueur qui avait une frontière, `next(ps.border) == nil` et `next(ps.coast) == nil`, `ps.tiles == 0`, `rawequal` des hashes avant/après (même objet, pas un `{}` neuf). Un second joueur non strippé garde sa frontière (un buf partagé l’aurait vidée). Client 35/35. 6000 ticks.
4. Fichiers : `ChantierB.luau` (`stripTerritory` seulement), `tests/simulate.luau` (bloc court à côté du banc spawn / N82 strip). **Ne pas** éditer `GameState.addPlayer` hors wrap déjà installé ni visual `d3e2`.

**Contraintes :** pas de RemoteFunction. **N94 feel ≠ N93 (`stripBuf` rot) ≠ visual V43 (rot, pas spawn) ≠ N82 (`elimBuf`).** Les hashes `border`/`coast` restent **par joueur**. Overlay n’itère pas ces tables après strip (joueur en `awaitingSpawn`). Un `{}` partagé ferait `gatherSites` du voisin voir 0 côte.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; records stats → **N76 fait** ; `eraProgress` → **N77 fait** ; bateaux → **N70 fait** ; missiles → **N71 fait** ; owner indices → **N72 fait** ; bâtiments → **N73 fait** ; HUD fronts → **N74 fait** ; viewFor → **N78 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; `ChantierB` doomed/collapsing → **N86 fait** ; parked → **N87 fait** ; collapse remain → **N88 fait** ; destroyBuf → **N89 fait** ; validTiles → **N90 fait** ; allyBuf → **N91 fait** ; previewCtx → **N92 fait**) |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | ouvert |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 factions) | P1 | ouvert |
| N13 | Parité combat (ère / cost factor / constantes mortes) | P2 | ouvert |
| N14 | Apply immédiat vs lockstep (feel #19) | P1 | ouvert (produit) |
| N15 | `PREPARATION_DURATION=0` vs gardes `combatUnlocked` | P2 | ouvert |
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 | **N37+N42+N45 faits** ; path résultat → **N83 fait** |
| N17 | Humains éliminés occupent le cap | P2 | ouvert |
| N18 | Heap AimFront ≠ ChantierB / BoatFront | P2 | ouvert (frontier mixte mag vs TERRAIN_COST) |
| N19 | Embargo allié + tribus auto-accept | P2 | ouvert |
| N20 | `railIncome` vs `deliveryValue` | P2 | **fait** `stopBonus` ; reste niveau live vs snapshot colis |
| N21 | QuickChat 2-args | P3 | **fait** passe 5 |
| N22 | Warships O(carriers × boats) | P2 | **fait** passe 19 (**N67**) |
| N23 | `retreatAttack` premier front | P2 | **fait** passe 5 |
| N24 | notify/sfx `FireAllClients` | P2 | **fait** passe 5 |
| N25 | `MAX_BOATS_PER_PLAYER` 6 vs 3 | P3 | ouvert |
| N26 | SAM chance 0.55 vs 1.0 | P1 | **fait** Config=1.0 |
| N27 | Embargo land trade | P2 | **doc** maritime-only |
| N28 | `RequestSnapshot` mort client | P2 | ouvert (serveur rate-limite ; client n’envoie jamais) |
| N29 | Seq commitée avant apply | P3 | **fait** passe 9 |
| N30 | Stub `seedBeachhead` faux | P3 | **fait** `error(...)` |
| N31 | Scan bunkers O(B) | P1 | **fait** passe 10 (N42) |
| N32 | `viewFor` requests expirées | P3 | **fait** |
| N33 | `BOAT_LANDING_BONUS` mort | P2 | ouvert |
| N34 | `areAllied` ignore expiry pacte | P2 | **fait** passe 7 |
| N35 | `applyDefenseAura` buffer mort (posted) | P2 | **fait** posted=index ; écritures → **N45 fait** |
| N36 | AimFront figé après premier lancer | P2 | **fait** passe 8 |
| N37 | `findSeaPath` alloc 40k / appel | P2 | **fait** passe 8 (BFS) ; résultat → **N83 fait** |
| N38 | `syncCarriers` O(B) / tick | P2 | **fait** passe 9 (dirty ; spawn → **N65 fait**) |
| N39 | `tryAnnex` alloc + BFS mort | P2 | **fait** passe 9 |
| N40 | Éliminés skip `Persistence.record` | P1 | **fait** passe 9 |
| N41 | Sequence `nil` bypass idempotence | P2 | **fait** passe 10 |
| N42 | `attackLogic` index bunkers | P1 | **fait** passe 10 |
| N43 | Transports inbound `removePlayer` (feel) | P2 | **fait** passe 11 |
| N44 | Missiles inbound vs slot recyclé | P2 | **fait** passe 11 |
| N45 | `applyDefenseAura` writes mortes | P3 | **fait** passe 11 |
| N46 | `Diplomacy.request` inverse périmée | P2 | **fait** passe 12 |
| N47 | Cadran / colis recycle feel | P2 | **fait** passe 12 |
| N48 | Convoi marchand inbound | P2 | **fait** passe 12 |
| N49 | `retreatBoats` / `targetSlot` après flip | P2 | **fait** passe 13 |
| N50 | `findSpawn` splash / fallout | P3 | **fait** passe 13 (C1+C2) |
| N51 | Convoi vs PORT détruit au combat | P3 | **fait** passe 13 |
| N52 | `claimSpawn` splash / fallout | P3 | **fait** passe 14 |
| N53 | Débarquement auto vs côte flippée | P3 | **fait** passe 14 (option A) |
| N54 | MIRV bus vs `findSpawn` | P3 | **fait** passe 14 (`spread + warheadRadius`) |
| N55 | `claimSpawn` isolation disque | P3 | **fait** passe 15 |
| N56 | Snapshot bateau `retreating` | P3 | **fait** passe 15 (option A) ; alloc → **N70 fait** |
| N57 | SAM scan O(B) / missile | P2 | **fait** passe 15 (`samsBySlot`) |
| N58 | Hover client spawn isolation | P3 | **fait** passe 16 (`SpawnHint`) |
| N59 | `samsOf` / bots scan O(B) | P2 | **fait** passe 16 (alloc → **N68 fait**) |
| N60 | `stepCooldowns` O(B) / tick nuke | P2 | **fait** passe 16 (`samsBySlot` + `silosBySlot`) |
| N61 | `Trade.step` scan FACTORY O(B) | P2 | **fait** passe 17 (`factoriesBySlot`) |
| N62 | Bots upgrade + score nuke O(B) | P2 | **fait** passe 17 (`buildingsBySlot`) ; nested 90 → **N69 fait** |
| N63 | `spawnTradeShips` O(ports²) feel | P2 | **fait** passe 17 (`portsByTile`) |
| N64 | `refreshRailNetwork` scan gares O(B) | P3 | **fait** passe 17 (`buildingsBySlot[slot]`) ; alloc → **N84 fait** |
| N65 | `syncCarriers` spawn NAVAL_BASE O(B) dirty | P3 | **fait** passe 18 (`navalBasesBySlot`) |
| N66 | `Trade.step` alloc+sort liste usines 10 Hz | P3 | **fait** passe 18 (`factoryBuf`) |
| N67 | `stepCarriers` nested O(C × B) 10 Hz | P2 | **fait** passe 19 (`carrierBuf`/`targetBuf`) |
| N68 | `samsOf` alloc table 10 Hz bots | P3 | **fait** passe 19 (`samBuf`) |
| N69 | `blastValue` × 90 tuiles frontière | P3 | **fait** passe 20 (`fillBlastBuf`) |
| N70 | `snapshotBoats` alloc 10 Hz | P2 | **fait** passe 20 (`boatSnapBuf`) |
| N71 | `snapshotMissiles` alloc 10 Hz | P3 | **fait** passe 21 (`missileSnapBuf`) |
| N72 | `flushOwnerDelta` indices alloc | P3 | **fait** passe 21 (`dirtyIndexBuf`) |
| N73 | `flushBuildingDelta` alloc 10 Hz | P3 | **fait** passe 22 (`buildingSnapBuf`) |
| N74 | HUD fronts `replicate()` alloc 10 Hz | P3 | **fait** passe 22 (`frontHudForReplicate`) |
| N75 | `buildPrices` alloc 10 Hz × slots | P3 | **fait** passe 23 (`pricesFor`) |
| N76 | `stats[slot]` alloc 10 Hz × slots | P3 | **fait** passe 23 (`playerStatsForReplicate`) |
| N77 | `Research.progress` alloc `ratios` | P3 | **fait** passe 24 (min courant) |
| N78 | `Diplomacy.viewFor` alloc 7 tables 1 Hz | P3 | **fait** passe 24 (`viewBuf` par slot) |
| N79 | `Diplomacy.step` alloc `expired` 10 Hz | P3 | **fait** passe 25 (`expiredBuf` + pool records) |
| N80 | `Bots.neighborFactions` alloc hash contacts | P3 | **fait** passe 25 (`contactBuf`) |
| N81 | `Bots.gatherSites` alloc array / décision | P3 | **fait** passe 26 (`siteBuf`, caps 40/60/45 inchangés) |
| N82 | `stepElimination` alloc `doomed` 10 Hz | P3 | **fait** passe 26 (`elimBuf`, pas le doomed bâtiments de `removePlayer` → **N89 fait**) |
| N83 | `findSeaPath` path + reversed | P3 | **fait** passe 27 (`pathWalkBuf`, retour **unique** pour `boat.path`) |
| N84 | `refreshRailNetwork` stations / parent | P3 | **fait** passe 27 (`stationBuf`, pas de pool `building.links`) |
| N85 | `Buildings.contextFor` table + closures | P3 | **fait** passe 28 (`ctxBuf` + closures module, pas le ctx client → **N92 fait**) |
| N86 | `ChantierB` doomed / collapsing 10 Hz | P3 | **fait** passe 28 (`doomedBuf` hash + `collapsingBuf` pool records) |
| N87 | `BoatFront.parked` par lancer | P3 | **fait** passe 29 (`parkedBuf`, truncate avant origLaunch) |
| N88 | `collapseFaction` remaining / leftovers | P3 | **fait** passe 29 (`collapseRemainBuf` / `collapseLeftBuf`) |
| N89 | `removePlayer` snapshot `doomed` bâtiments | P3 | **fait** passe 30 (`destroyBuf`, pas elimBuf / doomedBuf Attack) |
| N90 | `Placement.validTiles` blockers / candidates | P3 | **fait** passe 30 (`blockBuf`/`candBuf`/`queueBuf`/`visitBuf`/`emptyTileBuf`) |
| N91 | `Bots.decideDiplomacy` `or {}` | P3 | **fait** cette passe (`allyBuf`, recette visual V42, pas contactBuf) |
| N92 | `PlacementPreview.resolve` ctx hover | P3 | **fait** cette passe (client, pas `ctxBuf` Buildings / pas `candBuf`) |
| N93 | `stepDoomsday` `toStrip` | P3 | **nouveau** (`stripBuf`, recette visual V43, scan O(carte) reste N9) |
| N94 | `stripTerritory` `border`/`coast` | P3 | **nouveau** (`table.clear` in-place, pas de hash partagé) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 `NIGHTLY_REPORT.md` historique.

---

## 6. Drift Config → `ChantierB.apply` (extrait)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | formule custom |
| `MAX_TILES_PER_TICK` | 400 | 56 | **non** (`guard<80`) |
| `DEFENSE_RADIUS` | 6 | 30 | index bunkers (N42), plus d’écritures buffer (N45) |
| `BOAT_TROOP_RATIO` | 0.2 | 0.2 | oui |
| `RETREAT_LOSS` | 0.25 | 0.25 | oui |
| `SAM_INTERCEPT_CHANCE` | **1.0** | 1.0 | oui (N26 clos) |
| `SAM_RANGE` | 34 | 70 | oui |
| `SAM_COOLDOWN` | 90 | 75 | oui |
| `SILO_COOLDOWN` | 90 | **90** (apply ne le touche pas) | oui (`Nukes.launch` + `stepCooldowns`) |
| `TRUCK_GOLD_BASE` | 10 | 14 | oui |
| `TRAIN_STOP_BONUS` | **0.12** | 0.12 | Trade + HUD (N20) |
| `BOAT_LANDING_BONUS` | 1.35 | 1.35 | **non** (N33) |
| `MAX_BOATS_PER_PLAYER` | 6 | 6 | oui (N25) |
| `PREPARATION_DURATION` | 0 | 0 | forcé true |
| `ALLIANCE_DURATION` | 3000 | 3000 | oui (`areAllied` + `Diplomacy.step`) |
| `ALLOW_UNSEQUENCED_INTENTS` | **false** | n/a | oui (N41) |
| `TRADE_SHIP_INTERVAL` | 45 | n/a | oui (N63, pas 10 Hz) |
| `MAX_TRADE_SHIPS` | 24 | n/a | oui (early-out N63) |
| `WARSHIP_SHELL_RATE` | 20 | 20 | oui (N67) |
| `RAIL_RANGE` | 56 | n/a | oui (N84, tri + union-find inchangés) |
| `COLLAPSE_MIN_TILES` | 100 | 100 | oui (N86 wrap, N88 scan) |
| `BUILD_SNAP_RADIUS` | (Config) | n/a | oui (N90 BFS) |
| `BUILD_MIN_SPACING` | (Config) | n/a | oui (N90 blockers) |
| `COALITION_MIN_LEADER_TILES` | 250 | n/a | oui (N91 `dominantLeader`) |

---

## 7. Preuve tests

`./tests/run.sh` → **exit 0**.

Serveur :

```
seed 7 / 99991 / 31337 / 1234567 : 18 factions, invariants OK
factions : 18
intentions : sequence, idempotence, apply immediat, rate limit OK
allyBuf : bot sans pacte, next nil (N91)
allyBuf : leftover A→C absent, rawequal (N91)
allyBuf : force × 2.2 + frontiere > 4 → breakAlliance (N91)
neighborFactions : contact, rawequal, slot 99 vide (N80)
validTiles : deux resolve CITY, tile identique (N90)
destroyBuf : leftover A→B, CITY B survit (N89)
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.73
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `hover spawn isolation : lisiere rouge, disque isole vert (N58)`, `accrochage du placement et bascule en amelioration` (N90 Shared + N92 Preview recycle ctx) et `identite, ere, diplomatie et classement`. Overlay `previewTile(valid=false)` ne lève pas. HUD lit `eraProgress` number (N77). HUD remplace `self.diplomacy = payload` (N78). `Placement.luau` / `tests/client.luau` **non** touchés cette passe.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass31.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N91 est un pool serveur ; N92 est le fantôme client vérifié par le banc GUI stub.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N91 n’ajoute **pas** de require (`allyBuf` vit dans Bots, déjà requis par init). N92 n’ajoute **pas** de require (`previewCtx` vit dans PlacementPreview, déjà requis par Placement). N93 restera dans ChantierB. N94 restera dans `stripTerritory` (même module).

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N80 : `contactBuf` n’est pas réentrant. Les 4 appelants (`decideDiplomacy` ×2, `decideNavy`, `decideAttack`) lisent puis abandonnent avant le prochain appel — ne pas `table.clone`. Slot 99 / sans joueur = map **vide**. Ne pas fusionner avec `allyBuf` (N91) : contacts = tuiles, allies = clés `state.alliances[slot]`.

Piège N85 : `ctxBuf` / `ctxState` ne sont pas réentrants. Ne **pas** `table.clone(ctxBuf)`. Ne pas toucher `PlacementPreview.luau` : le fantôme client a **son** ctx (**N92 fait**). GameState ne doit **pas** require Placement (cycle).

Piège N86 : `doomedBuf` / `collapsingBuf` / `collapseRecPool` ne sont pas réentrants. Distinct de N93 `stripBuf` (tuiles cadran) et de N8 (corps mort `GameState.stepAttacks` `local collapsing`).

Piège N89 : `destroyBuf` n’est pas réentrant et est **partagé entre toutes les instances** `GameState`. Distinct de N93 (tuiles rot) et de N94 (hashes spawn).

Piège N90 : `blockBuf` / `candBuf` / `queueBuf` / `visitBuf` / `emptyTileBuf` ne sont pas réentrants. Retourner `candBuf` (pas `table.clone`). Ne pas toucher `PlacementPreview` (N92 déjà).

Piège N91 : `allyBuf` n’est pas réentrant. `Bots.step` est séquentiel : un second `table.clear` au bot suivant est **voulu**. Copier les **clés** de `state.alliances[slot]`, pas itérer `state.alliances` global ni `state.players` (visual V42 fill via `areAllied` — **ne pas** porter ce fill). Garder `if not areAllied then continue` dans la boucle trahison (un pacte périmé peut encore être une clé). Ne pas `table.clone` de `state.alliances[slot]` (`breakAlliance` mute le hash live). Ne pas toucher `contactBuf` / `siteBuf` / `acceptChance` / `COALITION_*`. Overlay n’itère pas `allyBuf`. Un leftover sans `table.clear` ferait `breakAlliance` fantôme du bot précédent. `decideChat` itère encore `state.alliances[slot]` avec garde `if allies then` — **hors scope**.

Piège N92 : `previewCtx` n’est pas réentrant. `resolve` est synchrone (Heartbeat → `update` après). Réécrire **les six champs** à chaque hover, y compris `ownerAt` / `buildingAt` (une capture entre deux hovers doit recolorer). Ne **pas** `table.clone`. Ne pas cacher « ctx inchangé ». Ne pas fusionner avec `ctxBuf` Buildings (le client n’a pas de `GameState`). Ne pas retourner `candBuf` au HUD (`resolve` lit `tiles[1]` tout de suite). `setKind` / `update` / footprint inchangés. Un `ownerAt` du hover précédent ferait un fantôme vert chez le voisin.

Piège N93 (à venir) : `stripBuf` n’est pas réentrant. Truncate leftover **avant** l’arrachage **et** à 0 **après** le slot (deuxième camp du même tick). Ne pas `table.clear` (array + `#`). Ne pas fermer N9 (scan carte). Ne pas skip `awaitingSpawn`.

Piège N94 (à venir) : `table.clear(ps.border)` in-place. Ne **jamais** partager un `emptyBorderBuf` module — `setOwner` / `claimSpawn` muteraient tous les joueurs strippés. `rawequal` avant/après est la loi du banc.
