# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 33)

Déclencheur : ouverture de la **PR #99** (`cursor/analyse-nocturne-du-codebase-a963`) — stripBuf, stripTerritory, specs N95–N96.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-d74d`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#100.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur. Les index posted ne sont pas répliqués. `gainBuf` / `lossBuf` / `otherBuf` sont des pools module-level (arrays, pas de l’état répliqué). `sumXBuf` / `sumYBuf` / `countBuf` sont des hash module-level (`table.clear`, pas un hash partagé avec Overlay).

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #99 (passe 32) : claims vérifiés.** `ChantierB.stepDoomsday` recycle `stripBuf` (N93) ; `stripTerritory` fait `table.clear` in-place (N94). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #99 a documenté (N95, N96)**.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #99

| Claim #99 | Réalité à l’ouverture |
|---|---|
| `stripBuf` (N93) | Oui. Array module, truncate leftover **avant** arrachage, reset à 0 **après** chaque slot. Deux camps le même tick perdent chacun le sien. Leader intact. Scan O(carte) reste N9. Recette visual V43, pas merger `d3e2`. Banc feel `keep=8`. |
| `stripTerritory` (N94) | Oui. `table.clear(ps.border/coast)` in-place, `rawequal`. Second joueur non strippé garde sa frontière. Pas de hash module partagé. |
| Specs N95–N96 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #98 (b4c1), feel jusqu’à #99, visuelles #39/…/#97 (gainBuf/countBuf) / #100 (ranked/previewCtxBuf). **#99 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←…←#98) reste distincte. Ne pas merger visual `bee8` / `2932` ni hardening `b4c1` / `ae35` sans rebase.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N95–N96 du rapport #99.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `WorldRenderer.applyDelta` alloue gains/losses/others (N95) | `WorldRenderer.luau` (`applyDelta` seulement), `tests/client.luau` (check existant) | Leftover N2 côté client. Trois arrays module + truncate leftover **avant** return. Early-out `count == 0` → pools vides, pas `{}`. Colonisation du neutre sans effet ; prise locale → `gainBuf`. Recette visual V48, **pas** merger `bee8`. `Effects` itère tout de suite. |
| `FactionLabels.surveyTerritories` alloue sumX/sumY/counts (N96) | `FactionLabels.luau` (`surveyTerritories` seulement), `tests/client.luau` (check existant) | Leftover N95. Trois hash module + `table.clear` **avant** le scan. Owner tout NEUTRAL → plus d’ancres. Recette visual V49, **pas** merger `bee8`. Pas de truncate d’array. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence skip-si-inchangé (N2 restant), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK, `seedBeachhead` Attack+queued+Heap (N5 ouvert), pool `building.links`, scan cadran O(carte) (**N9**), corps mort `GameState.stepAttacks` `local collapsing` (**N8**), `HUD.update` ranked (**N97**), `Overlay.applyUnits` track/extra (**N98**). `PlacementPreview.resolve` ctx déjà **N92**.

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
    cancelOpposingFronts via doomedBuf, collapsingBuf 10 Hz,
    stepDoomsday via stripBuf, stripTerritory table.clear), BoatFront
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
- **Réplication :** StateDelta (`dirtyIndexBuf` N72, HUD fronts N74 via N76, `buildPrices` N75, records stats N76, `eraProgress` N77) / UnitSnapshot (`retreating`, `boatSnapBuf` N70, `missileSnapBuf` N71) / BuildingDelta (`buildingSnapBuf` N73) / plunder / trade / explosions / notify&sfx déployés / Diplomacy.viewFor 1 Hz (N78). `path` / `homeTile` / `progress` **non** répliqués. Playing 10 Hz ; lobby vide et ended → 1 Hz. `Diplomacy.step` recycle `expiredBuf` (**N79**). `Bots.neighborFactions` recycle `contactBuf` (**N80**). `gatherSites` recycle `siteBuf` (**N81**). `stepElimination` recycle `elimBuf` (**N82**). `findSeaPath` walk scratch, retour unique (**N83**). `refreshRailNetwork` porteuses recyclées (**N84**). `Buildings.contextFor` recycle `ctxBuf` (**N85**). `ChantierB.cancelOpposingFronts` / wrap `stepAttacks` recyclent `doomedBuf` / `collapsingBuf` (**N86**). `BoatFront.launchAttack` recycle `parkedBuf` (**N87**). `collapseFaction` recycle `collapseRemainBuf` / `collapseLeftBuf` (**N88**). `removePlayer` recycle `destroyBuf` (**N89**). `Placement.validTiles` recycle blockers/candidates/queue (**N90**). `Bots.decideDiplomacy` recycle `allyBuf` (**N91**). `PlacementPreview.resolve` recycle `previewCtx` (**N92**). `stepDoomsday` recycle `stripBuf` (**N93**). `stripTerritory` `table.clear` in-place (**N94**). `WorldRenderer.applyDelta` recycle `gainBuf`/`lossBuf`/`otherBuf` (**N95**). `FactionLabels.surveyTerritories` recycle `sumXBuf`/`countBuf` (**N96**). `HUD.update` alloue encore `ranked` + records (**N97**). `Overlay.applyUnits` alloue encore closure `track` + extra missile (**N98**). N2 restant = skip-si-inchangé (payloads encore envoyés chaque tick).

---

## 5. Issues worker-ready (nouveaux, N97–N98)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N96 = faits. N22 = **N67 fait**. N27 = doc only. **V51 / N92** (Preview ctx) déjà fermé sur feel — ne pas re-spécifier.

---

### ISSUE-N97 — `HUD.update` alloue `ranked` + records 10 Hz (feel)

**Priorité :** P3 alloc client 10 Hz. Leftover explicite de N96 (hash étiquettes). Distinct de N76 (`playerStatsForReplicate` serveur) et de visual V50 (déjà **fermé** sur `2932` — **porter, ne pas merger**). Ne pas toucher `surveyTerritories` (N96) ni Overlay (N98). V51 Preview ctx = **N92 déjà**.

**Problème :** chaque `HUD.update` (StateDelta 10 Hz playing) fait `local ranked: Ranking = {}` puis `table.insert(ranked, { slot, tiles, troops, gold })` par faction vivante, puis `self.ranked = ranked`. Nouvelle array + N records par tick. Un leftover non truncaté afficherait une faction éliminée dans la fiche diplomatique / l’écran de victoire (`VictoryScreen.show(hud.ranked)` lit `ranked[i]`). Distinct de N96 (hash barycentre, pas le classement).

**Pourquoi 20K CCU :** leftover N96. 8 clients × 10 Hz × (1 array + jusqu’à 18 records). Pas d’autorité (le tri est cosmétique ; la victoire se décide serveur). `self.ranked` **est stocké** et lu plus tard (`selectFaction`, `VictoryScreen.show`) : on ne peut pas renvoyer un pool et le muter sous un écran qui le rangerait. Visual V50 a déjà la recette sur une autre ligne.

**Worker :**

1. Réutiliser `self.ranked` (déjà `{}` dans `HUD.new`). `n = 0` ; pour chaque `stats[slot]` : `n += 1` ; si `ranked[n]` existe, muter `slot/tiles/troops/gold` ; sinon poser un nouveau record. Truncate leftover **avant** `table.sort` (`for i = #ranked, n+1, -1 do ranked[i] = nil`). Ne **pas** `table.insert`. Ne **pas** remplacer `self.ranked` par une nouvelle table. `VictoryScreen.show` lit tout de suite et copie vers `row.Text` — il ne stocke pas l’identité. Pas de RemoteFunction.
2. Ne pas modifier la clé de tri (tuiles desc, tie-break troupes). Ne pas recréer le panneau classement maison. Ne pas toucher Overlay / WorldRenderer / FactionLabels (N95–N96 déjà). Après N96. Ne pas porter Overlay `track` (N98) en même temps. Recette visual V50.
3. Test : banc client « identite, ere, diplomatie et classement » **doit rester vert** (tri décroissant + `# > 0`). Étendre **ce** check (ne **pas** ajouter un 36e) : deux `HUD.update` — premier avec 3 slots, second stats d’un seul slot → `#hud.ranked == 1` et `hud.ranked[1].slot` = le vivant. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
4. Fichiers : `HUD.luau` (`HUD.update` classement seulement), `tests/client.luau` **seulement** le check existant « identite, ere, diplomatie et classement ». `VictoryScreen.luau` **seulement si** un champ conserve `ranked` (sinon ne pas toucher). **Ne pas** éditer le serveur ni visual `2932`.

**Contraintes :** pas de RemoteFunction. Recette visual V50 (arrays truncate + records internes recyclés, comme `boatSnapBuf` inner). **N97 feel ≠ N96 (`countBuf` hash) ≠ N76 (`playerStatsForReplicate` serveur) ≠ N98 (`Overlay.track`) ≠ visual V50 (déjà fermé sur `2932`).** Les buf ne sont pas réentrants. Un leftover non truncaté ferait une ligne fantôme (`#hud.ranked` trop grand).

---

### ISSUE-N98 — `Overlay.applyUnits` closure `track` + extra missile 10 Hz (feel)

**Priorité :** P3 alloc client 10 Hz. Leftover explicite de N97 (HUD ranked). Distinct de N70/N71 (`boatSnapBuf` / `missileSnapBuf` **serveur**) et de visual V52 (spec déjà sur `2932` — **porter la recette, ne pas merger**). Ne pas toucher HUD ranked (N97). **V51 Preview ctx = N92 déjà** — ne pas re-porter.

**Problème :** chaque `UnitSnapshot` (10 Hz playing) fait `local function track(...)` dans `applyUnits` (une closure neuve par lot) puis, pour **chaque** missile, `extra = { tx = missile.tx, ty = missile.ty }`. `stepInterpolation` lit `unit.extra.tx/ty` plus tard. Distinct de `Vector2.new` sur `current`/`target` (hors passe : Vector2 Roblox est immuable ; changer la représentation est un refactor). Distinct de N97 (HUD ranked) et N92 (ctx Preview).

**Pourquoi 20K CCU :** leftover N97. 8 clients × 10 Hz × (1 closure + 1 table / missile en vol). Pas d’autorité (interpolation cosmétique). Un leftover `extra` d’un navire réutilisé en missile (ids recyclés côté serveur) viserait un `tx/ty` fantôme. Visual V52 a déjà la spec worker-ready.

**Worker :**

1. Hoister `track` en fonction module (`trackUnit(self, id, slot, kind, x, y, isMissile, extra)`) — plus de closure par snapshot. `self.seen` / `self.units` inchangés (`table.clear(self.seen)` déjà). Pas de RemoteFunction.
2. Extra missile : à l’insert, poser `unit.extra = { tx, ty }` **une fois**. Sur un missile déjà suivi : muter `unit.extra.tx` / `unit.extra.ty` (créer extra si nil). Ne **pas** remplacer `unit.extra` par une nouvelle table à chaque lot. Navire : `extra` reste nil.
3. Ne **pas** changer `current` / `target` Vector2 (hors passe). Ne pas porter HUD ranked (N97). Ne pas retoucher `snapshotBoats` / `snapshotMissiles` serveur (N70/N71 déjà, **avec** `retreating` côté feel). Après N97. Recette visual V52.
4. Test : banc client « navires, missiles et interpolation » **doit rester vert** (pieces, Name, `applyUnits({}, {})` détruit). Étendre **ce** check (ne **pas** ajouter un 36e) : deux `applyUnits` du même missile (`id=3`, `tx/ty` différents) → `overlay.units[3].extra.tx` = le second, `rawequal` du record extra. Client **35/35**. `./tests/run.sh`. 6000 ticks serveur inchangé.
5. Fichiers : `Overlay.luau` (`applyUnits` / `track` seulement), `tests/client.luau` **seulement** le check existant « navires, missiles et interpolation ». `UnitModels.luau` **non**. **Ne pas** éditer le serveur ni visual `2932`.

**Contraintes :** pas de RemoteFunction. Recette visual V52 (hoist + inner extra muté). **N98 feel ≠ N97 (`ranked`) ≠ N70/N71 (payload serveur) ≠ N92 (`previewCtx`) ≠ Vector2 refactor ≠ visual V52 (spec ouverte sur `2932`).** Non réentrant — un seul `applyUnits` / lot. Un leftover `extra` d’un id recyclé viserait un `tx/ty` fantôme.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés ; **SILO_COOLDOWN** Config=90, apply ne le touche pas) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert (`buildPrices` → **N75 fait** ; records stats → **N76 fait** ; `eraProgress` → **N77 fait** ; bateaux → **N70 fait** ; missiles → **N71 fait** ; owner indices → **N72 fait** ; bâtiments → **N73 fait** ; HUD fronts → **N74 fait** ; viewFor → **N78 fait** ; listes effets client → **N95 fait** ; reste skip-si-inchangé) |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas ; `parked` → **N87 fait**) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert (corps `GameState.stepAttacks` alloue encore `collapsing`) |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert (alloc `toStrip` → **N93**) |
| N10 | Divers P3 | P3 | ouvert (`Buildings.contextFor` → **N85 fait** ; `ChantierB` doomed/collapsing → **N86 fait** ; parked → **N87 fait** ; collapse remain → **N88 fait** ; destroyBuf → **N89 fait** ; validTiles → **N90 fait** ; allyBuf → **N91 fait** ; previewCtx → **N92 fait** ; stripBuf → **N93 fait** ; stripTerritory → **N94 fait** ; gainBuf → **N95 fait** ; surveyTerritories → **N96 fait**) |
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
| N91 | `Bots.decideDiplomacy` `or {}` | P3 | **fait** passe 31 (`allyBuf`, recette visual V42, pas contactBuf) |
| N92 | `PlacementPreview.resolve` ctx hover | P3 | **fait** passe 31 (client, pas `ctxBuf` Buildings / pas `candBuf`) |
| N93 | `stepDoomsday` `toStrip` | P3 | **fait** passe 32 (`stripBuf`, recette visual V43, scan O(carte) reste N9) |
| N94 | `stripTerritory` `border`/`coast` | P3 | **fait** passe 32 (`table.clear` in-place, pas de hash partagé) |
| N95 | `WorldRenderer.applyDelta` gains/losses/others | P3 | **fait** cette passe (`gainBuf`/`lossBuf`/`otherBuf`, recette visual V48) |
| N96 | `FactionLabels.surveyTerritories` sumX/sumY/counts | P3 | **fait** cette passe (`sumXBuf` hash `table.clear`, recette visual V49) |
| N97 | `HUD.update` ranked + records | P3 | **nouveau** (`self.ranked` inner, recette visual V50) |
| N98 | `Overlay.applyUnits` track + extra | P3 | **nouveau** (hoist `trackUnit`, extra muté, recette visual V52) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 / #45 / #48 / #51 / #53 / #56 / #59 / #62 / #65 / #68 / #71 / #75 / #78 / #82 / #86 / #89 / #93 / #96 / #99 `NIGHTLY_REPORT.md` historique.

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
| `SPAWN_RADIUS` | 3 | n/a | oui (N93 banc `keep=8`, N94 strip, N55 isolation) |
| `DOOMSDAY.WARN_SECONDS` | 20 | n/a | oui (N93 rot, N9 scan) |
| `DOOMSDAY.ROT_DEATH_SECONDS` | 90 | n/a | oui (`rotQuota` inchangé) |

---

## 7. Preuve tests

`./tests/run.sh` → **exit 0**.

Serveur :

```
seed 7 / 99991 / 31337 / 1234567 : 18 factions, invariants OK
factions : 18
intentions : sequence, idempotence, apply immediat, rate limit OK
stripBuf : rot sous quota, deux camps, tiles vs buffer (N93)
stripTerritory : table.clear in-place, voisin intact (N94)
allyBuf : bot sans pacte, next nil (N91)
validTiles : deux resolve CITY, tile identique (N90)
destroyBuf : leftover A→B, CITY B survit (N89)
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=12.0 p95Changed=26 maxChanged=479 avgTickMs=0.32 p95TickMs=0.73
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **35/35 OK** — dont `hover spawn isolation : lisiere rouge, disque isole vert (N58)`, `accrochage du placement et bascule en amelioration` (N90 Shared + N92 Preview recycle ctx), `deltas de terrain et conquetes classees` (N95 `gainBuf` recycle, prise + delta vide `rawequal`) et `etiquettes de faction : centre, contenu et disparition` (N96 owner neutre → plus d’ancres). Overlay `previewTile(valid=false)` ne lève pas. HUD lit `eraProgress` number (N77). HUD remplace `self.diplomacy = payload` (N78). Serveur **non** touché cette passe. `Placement.luau` **non** touché.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass33.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live). N95/N96 sont des pools client vérifiés par le banc headless.

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `SpawnHint` → `Config` + `MapGen` seulement (Shared). `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState`. Les index posted sont des champs d’état, pas des modules. N95 n’ajoute **pas** de require (`gainBuf` vit dans WorldRenderer). N96 n’ajoute **pas** de require (`sumXBuf` vit dans FactionLabels). N97 restera dans HUD. N98 restera dans Overlay.

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

Piège N93 : `stripBuf` n’est pas réentrant. Truncate leftover **avant** l’arrachage **et** à 0 **après** le slot (deuxième camp du même tick). Ne pas `table.clear` (array + `#`). Ne pas fermer N9 (scan carte). Ne pas skip `awaitingSpawn`. Banc feel : `keep=8` (`SPAWN_RADIUS=3`) — ne pas copier visual `shrinkTo 40` tel quel (disque visuel plus large). `ChantierB.stripBuf` exposé banc, pas de filaire. Un leftover sans truncate entre slots ferait `setOwner` d’une tuile du camp précédent.

Piège N94 : `table.clear(ps.border)` in-place. Ne **jamais** partager un `emptyBorderBuf` module — `setOwner` / `claimSpawn` muteraient tous les joueurs strippés. `rawequal` avant/après est la loi du banc. Ne pas `ps.border = nil` (les appelants itèrent la hash). Distinct de N93 (`stripBuf` array d’indices du rot).

Piège N95 : `gainBuf` / `lossBuf` / `otherBuf` ne sont pas réentrants. Trois bufs **séparés** (les trois listes vivent dans la même frame). Truncate leftover **avant** return. Early-out `count == 0` → pools vides, pas `{}`. `Effects.conquestWave` / `lossWave` itèrent tout de suite — ne pas cloner. Ne pas fusionner avec `dirtyIndexBuf` (serveur). Un leftover sans truncate rejouerait un splash. `Effects.lossWave` divise par `#conquests` : un leftover fausserait le barycentre.

Piège N96 : `sumXBuf` / `sumYBuf` / `countBuf` sont des **hash** (`table.clear`, pas truncate `#`). Un leftover sans clear afficherait une étiquette pour un slot éliminé. Ne pas fusionner avec N95 (arrays de tuiles) ni N80 (`contactBuf` serveur). Overlay n’itère pas ces hashes.

Piège N97 (à venir) : `self.ranked` **est stocké**. Muter les records in-place, truncate **avant** sort. Ne pas `table.insert`. Ne pas remplacer `self.ranked` par une nouvelle table. Un leftover non truncaté ferait une ligne fantôme dans `VictoryScreen.show`. Distinct de N76 (records stats serveur).

Piège N98 (à venir) : hoister `track`, ne pas allouer une closure par lot. Muter `unit.extra.tx/ty` (ne pas remplacer la table). Navire : `extra` reste nil. Ne pas changer `Vector2` current/target. Un leftover extra d’un id recyclé viserait un `tx/ty` fantôme. Distinct de N70/N71 (payload serveur, feel **avec** `retreating`).
