# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 30)

Déclencheur : ouverture de la **PR #89** (`cursor/analyse-nocturne-du-codebase-2b37`) — parkedBuf, collapseRemainBuf, specs N89–N90.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-e277`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#89.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. `destroyBuf` / `blockBuf` / `candBuf` / `queueBuf` / `visitBuf` sont des pools module-level, pas de l’état répliqué. `emptyTileBuf` ne reçoit **jamais** d’insert. `candBuf` est lu tout de suite par `Placement.resolve` (`#tiles` / `tiles[1]`), pas stocké côté HUD. `ctxBuf` n’est pas le ctx client (`PlacementPreview`).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #89 (passe 29) : claims vérifiés.** `BoatFront.launchAttack` recycle `parkedBuf` (N87) ; `GameState.collapseFaction` recycle `collapseRemainBuf` / `collapseLeftBuf` / `collapseScratch` (N88). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #89 a documenté (N89, N90)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #89

| Claim #89 | Réalité à l’ouverture |
|---|---|
| `parkedBuf` (N87) | Oui. Truncate leftover **avant** `origLaunch`. Réinsert `1..n`. 0 pont → 1 front terre. 2 `seedBeachhead` + terre → 3 Attack, troupes de pont intactes. Wrap sans pont après un wrap à ponts (autre instance) → pas de pont fantôme. Identité des Attack parkés. |
| `collapseRemainBuf` (N88) | Oui. Truncate leftover **avant** plunder et **avant** swap. Slot sans tuile → return, plunder inchangé. Victime déjà à 0 → second appel inerte. Inter-instances A→B sans leftover. `collapseScratch` distinct de `scratch`. |
| Specs N89–N90 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #88 (ca14), feel jusqu’à #89, visuelles #39/#44/#47/#50/#54/#57/#61/#64/#67/#69/#72/#74/#77/#79/#81/#84/#87/#90 (allyBuf/stripBuf). **#89 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#88) reste distincte. Ne pas merger visual `d3e2` / hardening `ca14` sur cette branche sans rebase.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N89–N90 du rapport #89.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `GameState.removePlayer` alloue `doomed` snapshot bâtiments (N89) | `GameState.luau` (`removePlayer` snapshot seulement), `tests/simulate.luau` | Leftover N82 / N88. `destroyBuf` module + truncate leftover **avant** `destroyBuilding`. Itérer `1..n`. Slot sans bâtiment / déjà absent → return. Inter-instances A→B : CITY de B (autre index) survit. Fallback hash conservé. |
| `Placement.validTiles` alloue blockers / candidates / queue / visited (N90) | `Placement.luau` (`validTiles` seulement), `tests/simulate.luau` | Leftover N85. `blockBuf` / `candBuf` / `queueBuf` / `visitBuf` / `emptyTileBuf` / `placeScratch`. Early-out → `emptyTileBuf` (`rawequal`). Truncate leftover **avant** BFS et **avant** sort. Retourner `candBuf` (pas un clone). Deux `resolve` CITY → même `tile`. Hors carte `# == 0`. Pas `PlacementPreview`. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, ctx client `PlacementPreview` (**N92**), `Bots.decideDiplomacy` `or {}` (**N91**), corps mort `GameState.stepAttacks` `local collapsing`, `stripTerritory` `border`/`coast`.

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
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`. Stub = `error(...)`. Deux débarquements du même couple = **deux** tas (N5 ouvert ; hardening N29). Wrap `launchAttack` gare via `parkedBuf` (**N87**).
- **`areAllied`** = deux directions **et** `tick < expiry` (`true` legacy tests reste vivant).
- **AimFront wrap** = re-visée du front terre du couple ; jamais `isBeachhead`.
- **`tryAnnex`** = BFS depuis les voisins défenseur du seed déjà capturé ; océan abort ; pool N37-like.
- **Carriers** = spawn/despawn/slot sur dirty NAVAL_BASE, spawn via `navalBasesBySlot` (N65). Ciblage obus = `carrierBuf`/`targetBuf` recyclés **(N67)**. Pas de spatial hash.
- **Posted bunker** = index `bunkersBySlot`. **Posted SAM** = `samsBySlot`. **Posted SILO** = `silosBySlot`. **Posted FACTORY** = `factoriesBySlot`. **Tous** = `buildingsBySlot`. **PORT** = `portsByTile`. **Posted NAVAL_BASE** = `navalBasesBySlot`.
- **`samsOf`** = lit `samsBySlot` dans `samBuf` recyclé (N68). `tryIntercept` lit l’index directement (N57).
- **Score nuke bots** = flatten `buildingsBySlot` une fois (N69), puis 90 `scoreBlast`.
- **Inbound `removePlayer`** = snapshot `destroyBuf` (**N89**) → destroy → diplo + transports `kind==1` (100 %, lit **`owner[targetTile]`**) + missiles contrat B + cadran/colis + convois `kind==2` (coulés), **avant** `setOwner`.
- **Hover spawn** = `SpawnHint` (Shared) si `tiles==0`. Serveur = `claimSpawn` (N52+N55).
- **Réplication :** StateDelta (`dirtyIndexBuf` N72, HUD fronts N74 via N76, `buildPrices` N75, records stats N76, `eraProgress` N77) / UnitSnapshot (`retreating`, `boatSnapBuf` N70, `missileSnapBuf` N71) / BuildingDelta (`buildingSnapBuf` N73) / plunder / trade / explosions / notify&sfx déployés / Diplomacy.viewFor 1 Hz (N78). `path` / `homeTile` / `progress` **non** répliqués. Playing 10 Hz ; lobby vide et ended → 1 Hz. `Diplomacy.step` recycle `expiredBuf` (**N79**). `Bots.neighborFactions` recycle `contactBuf` (**N80**). `gatherSites` recycle `siteBuf` (**N81**). `stepElimination` recycle `elimBuf` (**N82**). `findSeaPath` walk scratch, retour unique (**N83**). `refreshRailNetwork` porteuses recyclées (**N84**). `Buildings.contextFor` recycle `ctxBuf` (**N85**). `ChantierB.cancelOpposingFronts` / wrap `stepAttacks` recyclent `doomedBuf` / `collapsingBuf` (**N86**). `BoatFront.launchAttack` recycle `parkedBuf` (**N87**). `collapseFaction` recycle `collapseRemainBuf` / `collapseLeftBuf` (**N88**). `removePlayer` recycle `destroyBuf` (**N89**). `Placement.validTiles` recycle blockers/candidates/queue (**N90**). `Bots.decideDiplomacy` alloue encore `or {}` (**N91**). `PlacementPreview.resolve` alloue encore un ctx par hover (**N92**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N91–N92)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N90 = faits. N22 = **N67 fait**. N27 = doc only.

---

### ISSUE-N91 — `Bots.decideDiplomacy` alloue `or {}` à chaque bot (feel)

**Priorité :** P3 alloc bots 10 Hz. Leftover explicite de N80 (`neighborFactions` / `contactBuf`, pas la table `alliances`). Distinct de N80 (`contactBuf` voisins de tuiles) et de visual V42 (`allyBuf` déjà sur `d3e2` — **porter la recette, ne pas merger**). Ne pas toucher `contactBuf` / `siteBuf` / seuils d’acceptation.

**Problème :** chaque `decideDiplomacy` fait `local allies = state.alliances[slot] or {}`. Un bot sans pacte alloue une table vide **à chaque tick** (16 bots × 10 Hz). La boucle `for ally in allies` sert la trahison (force × 2.2, frontière > 4, `breakAlliance`). La loi (seuils `acceptChance` 0.75/0.35, `COALITION_ALLY_CHANCE`, `COALITION_EMBARGO_CHANCE`, jamais trahir un compagnon pendant une coalition) ne change pas. Un leftover de clés d’un bot précédent dans un buffer non clear ferait `breakAlliance` fantôme.

**Pourquoi 20K CCU :** leftover N80. Un shard 16 bots appelle `decideDiplomacy` 10 Hz. `or {}` est l’alloc courte la plus chaude qui reste dans Bots après `contactBuf` / `siteBuf`. Pas d’autorité (mêmes `areAllied` / `breakAlliance`). Ne pas fusionner avec `contactBuf` : contacts = tuiles frontalières, allies = hash `state.alliances`. Visual V42 a déjà la recette sur une autre ligne.

**Worker :**

1. Ajouter `allyBuf: { [number]: true } = {}` module-level dans `Bots.luau`. `decideDiplomacy` : `table.clear(allyBuf)` ; si `state.alliances[slot]` alors copier les clés (`allyBuf[other] = true`) ; sinon laisser vide. Itérer `allyBuf`, pas `or {}`. Pas de RemoteFunction. Exposer `Bots.allyBuf` pour le banc (pas de filaire).
2. Ne pas modifier `neighborFactions` / `contactBuf` (N80 déjà). Ne pas modifier `gatherSites` / `siteBuf` (N81 déjà). Ne pas toucher `acceptChance` / `COALITION_*` / `dominantLeader`. Ne pas require de module nouveau. `Bots.step` est séquentiel : un second `clear` au bot suivant est **voulu**. Ne pas `table.clone` de `state.alliances[slot]` (hash live que `breakAlliance` mute).
3. Test : bancs diplomatie / `areAllied` / `breakAlliance` existants **doivent rester verts**. Ajouter : bot sans pacte → `next(Bots.allyBuf) == nil` après `decideDiplomacy` (via un tick `Bots.step` ou appel direct si le module l’expose). Deux bots : A allié à B, `decideDiplomacy(A)` puis `decideDiplomacy(C sans pacte)` → leftover A absent (`allyBuf[B] == nil`). `breakAlliance` vivant : un allié trop faible + frontière > 4 rompt toujours. Client 35/35. 6000 ticks.
4. Fichiers : `Bots.luau` (`decideDiplomacy` seulement, du `local allies = … or {}` jusqu’à la boucle trahison), `tests/simulate.luau` (bloc court à côté du banc `neighborFactions` N80). **Ne pas** éditer visual `d3e2` ni `Diplomacy.luau`.

**Contraintes :** pas de RemoteFunction. Recette visual V42 (hash `table.clear`, pas de truncate — c’est un hash). **N91 feel ≠ N80 (`contactBuf`, déjà fait) ≠ visual V42 (déjà sur `d3e2`).** `allyBuf` n’est pas réentrant. Ne pas itérer `state.alliances` global. Overlay n’itère pas cette table. Un leftover sans `table.clear` ferait rompre un pacte du bot précédent.

---

### ISSUE-N92 — `PlacementPreview.resolve` alloue un ctx à chaque hover (feel)

**Priorité :** P3 alloc client hover. Leftover explicite de N90 (`Ne pas éditer PlacementPreview.luau` / ctx client) et de N85 (`pas le ctx client`). Distinct de N90 (`candBuf` Shared) et de N85 (`ctxBuf` Buildings serveur). Ne pas toucher `Placement.luau`.

**Problème :** chaque `PlacementPreview.resolve` (donc chaque mouvement de souris en mode Construire) fait `local ctx: Placement.Context = { slot, era, gold, terrain, ownerAt, buildingAt }`. Six champs + une table porteuse par hover. Le serveur a déjà `ctxBuf` (N85) ; le fantôme client construit **le sien** avec les closures fournies par `init.client`. La loi (même `Placement.resolve` Shared, vert/bleu/rouge, snap vs exact) ne change pas.

**Pourquoi 20K CCU :** leftover N90. Un humain en pose survole des dizaines de tuiles par seconde ; 8 humains / shard. Recycle de la porteuse élimine l’alloc courte du fantôme. Pas d’autorité (le serveur re-résout à l’enqueue). Unique call site = `PlacementPreview.resolve` qui lit `resolution.tile` / `action` **immédiatement**. Ne pas fusionner avec `ctxBuf` Buildings : le client n’a pas de `GameState`. Ne pas retourner `candBuf` au HUD (N90 : `resolve` lit `tiles[1]` tout de suite, Preview ne voit que `resolution`).

**Worker :**

1. Ajouter `previewCtx: Placement.Context` module-level dans `PlacementPreview.luau` (record + champs réécrits à chaque `resolve`). `previewCtx.slot/era/gold/terrain/ownerAt/buildingAt = …` puis `Placement.resolve(previewCtx, …)`. Slot / kind inchangés. Pas de RemoteFunction. Ne **pas** `table.clone`. Deux hovers successifs → `rawequal` du ctx interne si exposé ; le banc client existant lit `landing` / `status`, pas l’identité du ctx.
2. Ne pas modifier `Placement.validTiles` / `emptyTileBuf` (N90 déjà). Ne pas toucher `Buildings.contextFor` (N85 déjà). Ne pas require de module nouveau. Ne pas cacher « ctx inchangé » si `ownerAt` change (capture / perte de tuile). `setKind` / `update` / footprint **inchangés**.
3. Test : banc client **35/35** existant **doit rester vert** — surtout `accrochage du placement et bascule en amelioration` (terrain libre exact, snap, upgrade, hors territoire invalid, sans or invalid). Ne pas ajouter de test d’identité ctx dans `tests/client.luau` sauf s’il est trivial (`previewTile(valid=false)` ne lève pas déjà). Serveur 6000 ticks inchangé. **Ne pas** casser le contrat Shared : client et serveur appellent le même `Placement.resolve`.
4. Fichiers : `PlacementPreview.luau` (`resolve` seulement). **Ne pas** éditer `Placement.luau` / `Buildings.luau` / `tests/simulate.luau` / `tests/client.luau` sauf si un assert client casse.

**Contraintes :** pas de RemoteFunction. Recette N85 (`ctxBuf` leftover interdit de toucher Preview — c’est **ce** leftover). **N92 feel ≠ N90 (`candBuf`, déjà fait) ≠ N85 (`ctxBuf` serveur, déjà fait).** Le ctx n’est pas réentrant. `update` peut être appelé depuis Heartbeat pendant un `resolve` — rester synchrone. Overlay / HUD n’appellent pas `validTiles`. Un ctx dont `ownerAt` resterait celui du hover précédent ferait un fantôme vert chez le voisin.

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
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; `ChantierB` doomed/collapsing → **N86 fait** ; parked → **N87 fait** ; collapse remain → **N88 fait** ; destroyBuf → **N89 fait** ; validTiles → **N90 fait**) |
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
| N85 | `Buildings.contextFor` table + closures | P3 | **fait** passe 28 (`ctxBuf` + closures module, pas le ctx client → **N92**) |
| N86 | `ChantierB` doomed / collapsing 10 Hz | P3 | **fait** passe 28 (`doomedBuf` hash + `collapsingBuf` pool records) |
| N87 | `BoatFront.parked` par lancer | P3 | **fait** passe 29 (`parkedBuf`, truncate avant origLaunch) |
| N88 | `collapseFaction` remaining / leftovers | P3 | **fait** passe 29 (`collapseRemainBuf` / `collapseLeftBuf`) |
| N89 | `removePlayer` snapshot `doomed` bâtiments | P3 | **fait** cette passe (`destroyBuf`, pas elimBuf / doomedBuf Attack) |
| N90 | `Placement.validTiles` blockers / candidates | P3 | **fait** cette passe (`blockBuf`/`candBuf`/`queueBuf`/`visitBuf`/`emptyTileBuf`) |
| N91 | `Bots.decideDiplomacy` `or {}` | P3 | **nouveau** (`allyBuf`, recette visual V42, pas contactBuf) |
| N92 | `PlacementPreview.resolve` ctx hover | P3 | **nouveau** (client, pas `ctxBuf` Buildings / pas `candBuf`) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 `NIGHTLY_REPORT.md` historique.

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

---

## 7. Preuve tests

`./tests/run.sh` → **exit 0**.

Serveur :

```
seed 7 / 99991 / 31337 / 1234567 : 18 factions, invariants OK
factions : 18
intentions : sequence, idempotence, apply immediat, rate limit OK
findSeaPath pool : 5 tuiles, 4 appels identiques
findSeaPath pathWalk : identite unique, p1 intact (N83)
stationBuf : liens usine, income, identite (N84)
contextFor : rawequal, slot 99, resolve CITY, ownerAt lit B (N85)
validTiles : etrangere #0, rawequal emptyTileBuf (N90)
validTiles : deux resolve CITY, tile identique (N90)
validTiles : hors carte #0, pas d'erreur (N90)
removePlayer index : snapshot buildingsBySlot, rien ne reste
destroyBuf : slot vide / absent, pas d'erreur (N89)
destroyBuf : leftover A→B, CITY B survit (N89)
elimBuf : vivant length 0, rawequal (N82)
doomedBuf : deux cancel vides, next nil (N86)
parkedBuf : 0 pont, deux lancers, 1 front (N87)
parkedBuf : 2 ponts + 1 terre, troupes intactes (N87)
parkedBuf : leftover 2→0, pas de pont fantome (N87)
collapse remain : slot sans tuile, return, plunder inchange (N88)
collapse remain : victime a 0, second appel inerte (N88)
collapse remain : truncate A→B inter-instances (N88)
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.71
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `hover spawn isolation : lisiere rouge, disque isole vert (N58)`, `accrochage du placement et bascule en amelioration` (N90 Shared, Preview inchangé) et `identite, ere, diplomatie et classement`. Overlay `previewTile(valid=false)` ne lève pas. HUD lit `eraProgress` number (N77). HUD remplace `self.diplomacy = payload` (N78). Aucune surface client Preview/`tests/client.luau` touchée cette passe.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass30.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). Les correctifs N89–N90 sont pools serveur / Shared, pas un Play Solo.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N89 n’ajoute **pas** de require (`destroyBuf` vit dans GameState). N90 n’ajoute **pas** de require (`blockBuf` vit dans Placement, déjà requis par Buildings — pas GameState depuis Placement). N91 restera dans Bots. N92 restera dans PlacementPreview (client).

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead` via `parkedBuf`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.

Piège N64 (toujours vrai) : ne **pas** référencer `IS_STATION` depuis `refreshRailNetwork` — le `local` est déclaré plus bas, la closure verrait `nil` au runtime.

Piège N66 : `factoryBuf` n’est pas réentrant. `Trade.step` est unique par tick. Ne pas appeler `Trade.step` depuis `dispatch` / `resolve`.

Piège N67 : `carrierBuf` / `targetBuf` ne sont pas réentrants. `stepCarriers` est unique par `Navy.step`. Dead carriers (`health <= 0`) restent dans `state.boats` (respawn) mais **hors** `carrierBuf` et hors cibles.

Piège N68 : `samBuf` n’est pas réentrant. `samsOf` n’est appelé que depuis `Bots.decideNuke` (synchrone). Un appelant concurrent doit dupliquer le buffer. Le test N59 lit le **contenu**, pas `rawequal`.

Piège N69 : `blastX/Y/Level` ne sont pas réentrants. `decideNuke` flatten une fois puis `scoreBlast` ; `Bots.blastValue` re-fill (banc unitaire). Ne pas appeler `blastValue` depuis la boucle 90. Index présent + set nil = score 0, **pas** de fallback hash.

Piège N70 : `boatSnapBuf` n’est pas réentrant et est **partagé entre toutes les instances** `GameState` (module-level). `replicate()` est unique par tick. Overlay / tests doivent lire les champs tout de suite, pas stocker l’identité de table d’un tick sur l’autre. Truncate obligatoire : Overlay itère `for _, boat in boats`.

Piège N71 : `missileSnapBuf` n’est pas réentrant et est **partagé entre toutes les instances** `GameState`. Overlay copie `tx`/`ty` dans `extra` à `applyUnits` — ne pas garder l’enregistrement du buffer. Truncate obligatoire : Overlay itère `for _, missile in missiles`. Ne **pas** répliquer `progress` : le client interpolé n’en a pas besoin.

Piège N72 : `dirtyIndexBuf` n’est pas réentrant. Un seul `flushOwnerDelta` par tick (`replicate` + banc). Le `buffer.create` outbound **doit** rester neuf — RemoteEvent. Early-out vide ne doit **pas** allouer le buffer. Ne pas itérer `dirty` deux fois.

Piège N73 : `buildingSnapBuf` n’est pas réentrant et est **partagé entre toutes les instances** `GameState`. Overlay / tests lisent `entry.index` / `kind` / `slot` / `level` / `links` tout de suite. Truncate obligatoire : Overlay itère `for _, entry in deltas`. Early-out dirty vide ne doit **pas** allouer. Ne **pas** cloner `links` : Overlay.syncFactoryRoutes itère immédiatement ; un `table.clone` casserait un test `rawequal` éventuel et allouerait. `refreshRailNetwork` ne dirty que les FACTORY dont les liens changent — poser une CITY seule flush length 1.

Piège N74 : `activeAttackBuf` / `committedTroopBuf` / `attackTargetBuf` / `attackTargetPool` ne sont pas réentrants. `playerStatsForReplicate` (N76) appelle N74 **une** fois. HUD / tests lisent les champs tout de suite. Slots sans front : **absents**, pas `{}` — N76 garde `activeAttacks[slot] or 0`. Ne pas merger beachhead et terre. Inner listes : `table.clear` au premier front du slot ce tick, puis `table.insert`.

Piège N75 : `priceBuf[slot]` / `emptyPriceBuf` ne sont pas réentrants. `replicate()` pose `rec.buildPrices = Buildings.pricesFor(...)` **après** N76, une fois par slot vivant (séquentiel : chaque slot a sa propre map). HUD client reçoit une copie désérialisée : recycle serveur OK. Slot inconnu = `emptyPriceBuf` partagé — ne pas le remplir avec `math.huge`. Ne **pas** cacher « prix inchangés » : le doublement `2^units` après pose CITY doit rester visible (le test N75 l’attrape). GameState ne doit **pas** require Buildings.

Piège N76 : `statsBuf` / `statsRecPool` ne sont pas réentrants et sont **partagés entre toutes les instances** `GameState`. `table.clear(statsBuf)` détache les records ; le pool les réécrit. Slots disparus **absents** de la porteuse (le test `removePlayer` l’attrape). `eraProgress` / `buildPrices` sont `nil` jusqu’à `init.server` — le banc N76 vérifie ce contrat ; le client ne voit que le payload déjà remplis. Ne **pas** cloner `attackTargets`. Ne pas merger `priceFor` dans ce helper (cycle).

Piège N77 : `progress` ne retourne **pas** de table — ne pas introduire un `ratiosBuf`. Le min courant **est** le goulot HUD (ne pas moyenner). `requiredBuildings` vide (ère 1 → 2 a CITY=1 ; une ère future à `{}` est légale). `count == 0` n’existe pas dans `Eras.LIST` actuel — ne pas ajouter de garde qui changerait la formule. `init.server` pose `rec.eraProgress` **après** N76 : le banc N76 continue de voir `nil`.

Piège N78 : `viewBuf[slot]` n’est **pas** un buffer global unique. Un seul `viewBuf` partagé entre slots casserait le `FireClient` précédent (la boucle humains est séquentielle, le payload n’est pas cloné avant l’envoi — RemoteEvent sérialise de façon synchrone dans le banc, mais Studio queue le même table). HUD client fait `self.diplomacy = payload` (copie wire). Tests existants appellent `viewFor` pour 3 slots puis lisent les 3 vues — d’où un record **par slot**. `table.clear` des inners, pas de nouvelle table porteuse. Slot sans joueur : maps vides, **pas** de scan `requests`/`traitors`. Ne pas cloner `marks`.

Piège N79 : `expiredBuf` / `expiredRecPool` ne sont pas réentrants. `step` est unique par tick. Truncate **après** traitement (`#` → 0) : aucun lecteur fantôme en prod, le banc N79 rappelle `step` tout de suite. Ne pas fusionner A–B et B–A en deux expirations (`a < b`). `true` legacy : **ne pas** faire `tick >= expiry` nu — en Luau le mixte number/boolean peut lever ; `typeof == "number"` est la loi `pactStillLive`. Ne pas marquer traître (ce n’est pas `breakAlliance`). Les records ne sont pas répliqués.

Piège N80 : `contactBuf` n’est pas réentrant. Les 4 appelants (`decideDiplomacy` ×2, `decideNavy`, `decideAttack`) lisent puis abandonnent avant le prochain appel — ne pas `table.clone`. Slot 99 / sans joueur = map **vide** (le test `next(buf) == nil` l’attrape), pas nil. Ne pas cacher NEUTRAL : `decideAttack` le score. Après `removePlayer`, les tuiles du disparu sont NEUTRAL : `contacts[gone] == nil`, la clé peut être `NEUTRAL_SLOT`. Ne pas itérer `buildings` / `owner` global (rester sur `ps.border`).

Piège N81 : `siteBuf` n’est pas réentrant. `decideBuild` lit puis abandonne avant le prochain bot — ne pas `table.clone`. Caps 40 (côte) / 60 (frontière) / 45 tirages (intérieur) inchangés. Pas de shuffle : l’ordre de hash `coast`/`border` est la loi. Slot / `ps.coast` vide pour PORT → `# == 0`, pas nil. Le tirage CITY **reste RNG** : ne pas tester `rawequal` de contenu sur CITY. Ne pas itérer `owner` global pour DEFENSE/PORT (rester sur `ps.border` / `ps.coast`). Truncate leftover (recette N68) : `table.clear(ps.border)` puis rappel → `# == 0`.

Piège N82 : `elimBuf` n’est pas réentrant et est **partagé entre toutes les instances** `GameState`. Truncate leftover **avant** `removePlayer`, **pas** à 0 après return (l’appelant et le banc lisent `#`). Ne pas nommer le buffer `doomed` (`removePlayer` snapshot → **N89** `destroyBuf`). Ne pas merger beachhead/terre dans le skip offensive : n’importe quel `atk.attacker == slot` suffit. Overlay n’itère pas cette liste (retour ignoré en prod). Un leftover d’état A dans l’état B sans truncate ferait `# > 0` pour un vivant — le banc inter-instances l’attrape.

Piège N83 : `pathWalkBuf` n’est pas réentrant. `findSeaPath` est synchrone et unique. Ne **jamais** `return pathWalkBuf` : `launchInvasion` / retraite / `spawnTradeShips` font `boat.path = path` — un second BFS aliaserait le trajet du premier transport. Ne pas `table.clone` du walk (ça réintroduit la deuxième alloc). Overlay n’itère pas `boat.path` (non répliqué). Le test d’identité (`not rawequal`, `p1[i]` intact) est pour les call sites serveur. `visitBuf` / `parentScratch` / `queueScratch` inchangés (`buffer.fill(visitBuf, 0, 0)`). Échec BFS / `MAX_BFS_NODES` → `nil`. Origine terrestre **exclue** du path (loi N37).

Piège N84 : `stationBuf` / `railParentBuf` / `railXsBuf` / `railYsBuf` / maps de grappe ne sont pas réentrants. `refreshRailNetwork` est unique par mutation. Truncate leftover **avant** `table.sort` : un leftover non truncaté mélange d’anciennes gares dans le tri et les liens répliqués. Itérer `1..count`, pas `#` sur parent/xs/ys. Ne **pas** pooler les inners `neighborsOf[i]` : elles deviennent `building.links` si usine + changed. Option B (`table.clear` in-place sur `building.links`) **interdite** : Overlay / BuildingDelta (N73) tiennent `links` live. Ne pas référencer `IS_STATION`. Ne pas `table.clone(links)` au dirty. Capital spawn est une gare : `railRoutes == 0` tant qu’il n’y a pas d’usine dans une grappe à 2+ gares. `stationBuf` n’est pas `factory.links` (l’usine ne se lie pas à elle-même).

Piège N85 : `ctxBuf` / `ctxState` ne sont pas réentrants. `resolve` est synchrone et unique. Ne **pas** `table.clone(ctxBuf)`. Slot inconnu → `return nil` **sans** muter (le test N85 l’attrape). Après `contextFor(A)` puis `contextFor(B)`, un `ownerAt` conservé lit B — c’est la loi, ne pas « corriger » en clonant. `terrain` est le buffer live (pas une copie). Ne pas toucher `Placement.luau` (N90 déjà) ni `PlacementPreview.luau` : le fantôme client construit **son** ctx (**N92**). GameState ne doit **pas** require Placement (cycle). `ctxOwnerAt` sans `ctxState` → `NEUTRAL_SLOT` (jamais renvoyé en prod).

Piège N86 : `doomedBuf` / `collapsingBuf` / `collapseRecPool` ne sont pas réentrants. `stepAttacks` est unique par tick. Ne **pas** itérer `#doomedBuf` (hash sparse — la boucle `for i = #state.attacks, 1, -1` reste). Truncate leftover collapsing **avant** le traitement : un leftover d’état A ferait collapse d’un slot fantôme. Compteur nommé `collapseN` (pas `n`) : le wrap a déjà `local n = MapGen.neighbors` dans la boucle de capture. `doomedBuf` est exporté pour le banc (`ChantierB.doomedBuf`) — Overlay ne le lit pas. Clash égal : leftover 0, **pas** de refund des troupes clashed (le banc N86 l’attrape). Collapse ≠ élimination : `collapseFaction` redistribue, `removePlayer` vient via `stepElimination`. `origStepAttacks` reste ignoré. Notify humain inchangé (`not victim.isBot`).

Piège N87 : `parkedBuf` n’est pas réentrant. `launchAttack` est synchrone. Truncate leftover **avant** `origLaunch` : un leftover non truncaté réinsèrerait un pont fantôme d’un lancer (ou d’une instance) précédent — le banc N87 l’attrape inter-instances. Réinsert `1..n`, pas `#` sans truncate. Les Attack parkés sont les **mêmes** objets (identité), pas des copies. Ne pas `table.clone`. Ne pas merger deux ponts du même couple. Ne pas toucher `seedBeachhead` / AimFront / `MAX_ACTIVE_ATTACKS_PER_PLAYER`. Overlay n’itère pas `parkedBuf`. Ordre des wraps inchangé : Bootstrap (AimFront) **autour** de BoatFront.

Piège N88 : `collapseRemainBuf` / `collapseLeftBuf` / `collapseScratch` ne sont pas réentrants et sont **partagés entre toutes les instances** `GameState`. Truncate leftover **avant** plunder (`n == 0` → return) et **avant** chaque swap. Itérer `1..n`, pas `#`. `where = collapseRemainBuf[1]` **avant** le premier swap (aliases locaux ensuite). `collapseScratch` est distinct de `scratch` (`setOwner` l’écrase). Ne pas pooler `self.plunders` (payload répliqué). Ne pas câbler `MAX_TILES_PER_TICK`. Un leftover d’état A dans l’état B sans truncate ferait `setOwner` d’une tuile fantôme — le banc N88 l’attrape. `COLLAPSE_MAX_PASSES` / `COLLAPSE_MIN_TILES` / plunder inchangés.

Piège N89 : `destroyBuf` n’est pas réentrant et est **partagé entre toutes les instances** `GameState`. Truncate leftover **avant** `destroyBuilding` : un leftover d’état A ferait détruire un bâtiment fantôme d’état B au même index de tuile — le banc N89 l’attrape (CITY de B, autre index). Itérer `1..nDestroy`, pas `#`. `stepElimination` peut enchaîner plusieurs slots : n recompté **à chaque** `removePlayer`. Ne pas nommer le buffer `doomed` (N82 `elimBuf` / N86 `doomedBuf`). Fallback hash `buildings` **conservé** (tests partiels sans index). Ne pas `table.clone` de `buildingsBySlot[slot]` (destroy mute l’index). Ne pas modifier `settledHumans` / inbound boats / missiles / cadran. Overlay n’itère pas cette liste. Slot déjà absent → return **avant** le snapshot (leftover non touché).

Piège N90 : `blockBuf` / `candBuf` / `queueBuf` / `visitBuf` / `emptyTileBuf` / `placeScratch` ne sont pas réentrants. `resolve` est synchrone et unique. Early-out kind/index/owner → `emptyTileBuf` — **jamais** d’insert. Truncate leftover **avant** le BFS (queue) et **avant** `table.sort` (un leftover mélange `tiles[1]`). Itérer `1..nB` / `1..nQ` / `nC` après truncate, pas `#` sans truncate. Retourner `candBuf` (pas `table.clone`) : `resolve` lit `tiles[1]` tout de suite. Ne pas stocker l’identité côté HUD / Preview. Ne pas trier au-delà de nC. `table.clear(visitBuf)` à chaque appel vivant. Ne pas toucher `PlacementPreview.luau` (**N92**) ni `Buildings.contextFor` (N85). GameState ne doit **pas** require Placement. Deux early-outs → `rawequal` (`emptyTileBuf`). Un leftover non truncaté ferait poser sur une tuile d’un resolve précédent — le banc N90 (`tile` identique + territoire) l’attrape.
