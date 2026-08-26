# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 9)

Déclencheur : ouverture de la **PR #29** (`cursor/analyse-nocturne-du-codebase-6be5`) — AimFront re-vise, findSeaPath pool, specs N38–N39.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-e541`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#29.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes et slot cible sont dérivés serveur.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #29 (passe 8) : claims vérifiés.** AimFront re-vise le front terre (`not isBeachhead`) y compris si `sourceTile` est déjà posé. `findSeaPath` pool `visitBuf` / `parentScratch` / `queueScratch` (`buffer.fill(buf, 0, 0)`). JoinRequest refuse `nan` / `inf`. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #29 a documenté (N38, N39)** plus deux correctifs d’autorité clairs : N29 (sequence après apply) et N40 (snapshot réputation des éliminés). **Bug collatéral N39 :** `tryAnnex` était mort — le seed est déjà capturé (`setOwner` avant l’appel), la file `{ seed }` faisait `continue` sans étendre les voisins.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #29

| Claim #29 | Réalité à l’ouverture |
|---|---|
| AimFront re-vise le front terre (`not isBeachhead`) | Oui. Wrap Bootstrap **après** BoatFront. Tests aim re-vise / aim beachhead. |
| `findSeaPath` pool `visitBuf` / `parent` / `queue` | Oui. `buffer.fill(buf, 0, 0)`. Test 4 appels identiques. |
| JoinRequest refuse `nan` / `inf` | Oui. `nationId ~= nationId` + `math.abs == math.huge`. Hors bundle. |
| Specs N38–N39 | **Corrigés ici.** N39 incluait un BFS mort (voir §3). |

PRs ouvertes au moment de la revue : #16 P0, #17/#18/#20/#23/#25/#27/#30 hardening, #19/#21/#22/#24/#26/#28/#29 feel. **#29 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←#20←#23←#25←#27←#30) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N38 dirty flag du rapport #29, N39 pooling + réparation du BFS.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `syncCarriers` O(B) + `seen` jetable chaque tick (N38) | `Navy.luau`, `GameState.luau` | Dirty `_carriersDirty` levé par `placeBuilding` / `destroyBuilding` / `transferBuilding` si `NAVAL_BASE`. `table.clear(carrierSeen)` module-level. No-op 9 ticks sur 10. Cadence / portée / priorité shells **inchangées** (N22). |
| `tryAnnex` allouait visited/queue/pocket + **BFS mort** (N39) | `ChantierB.luau` | Pool `annexVisitBuf` / `annexQueue` / `annexPocket`. Seed déjà attaquant : départ = voisins défenseur (coupe). Océan = abort. Plafond 280 inchangé. Sans le fix seed, **aucune enclave n’était annexée**. |
| Sequence commitée avant apply (N29) | `IntentValidator.luau` | `lastSequence` seulement si `applyOne` renvoie true. Un clic océan / or insuffisant ne brûle plus le numéro. Doublon d’un succès = toujours `DuplicateSequence`. |
| Éliminés jamais `Persistence.record` (N40) | `GameState.luau`, `init.server.luau` | `removePlayer` snapshotte `settledHumans[slot]` (humains only). `endMatch` / `onPlayerRemoving` gravent défaite + XP + trahisons. Bots ignorés. DataStore hors bundle. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), warships grille (N22), MAX_BOATS (N25), scan bunkers combat (N31), RequestSnapshot client (N28), landing bonus mort (N33), buffer defense mort (N35), bateau allié = retraite 25 % (N10.8 design), sequence nil compat (N41).

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (apply immédiat, seq après succès) → tick :
  Bots.step → Navy.step (syncCarriers si dirty) → Nukes.step → Trade.step → Diplomacy.step → GameState.step → replicate(fireDeployed)
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom), BoatFront, AimFront, tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`. Stub = `error(...)`.
- **`areAllied`** = deux directions **et** `tick < expiry` (`true` legacy tests reste vivant).
- **AimFront wrap** = re-visée du front terre du couple ; jamais `isBeachhead`.
- **`tryAnnex`** = BFS depuis les voisins défenseur du seed déjà capturé ; océan abort ; pool N37-like.
- **Carriers** = spawn/despawn/slot sur dirty NAVAL_BASE, pas un scan 10 Hz.
- **Réplication :** StateDelta / UnitSnapshot / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. MatchUpdate / roster → tous (menu). Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready (nouveaux, N41–N42)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N22, N25, N28, N31, N33, N35 restent ouverts.** N20/N21/N23/N24/N26/N29/N30/N32/N34/N36–N40 = faits. N27 = doc only.

---

### ISSUE-N41 — `IntentValidator` accepte `sequence == nil` (bypass idempotence)

**Priorité :** P2 anti-exploit (le client officiel envoie toujours un entier).

**Problème :** `checkSequence` :

```
if sequence == nil then
    -- Compat : intention sans numero — acceptee mais non idempotente.
    return true, nil
end
```

Un client modifié omet le dernier argument RemoteEvent et rejoue le même ordre dans la fenêtre `INTENT_RATE_LIMIT_PER_SEC` (20/s). L’or / les troupes restent serveur, donc ce n’est **pas** un give-item. Ça double les `launchAttack` / `Build` / dons dans la limite.

N29 vient de rendre la sequence **non brûlée** sur apply raté : un client honnête retry le même numéro. Un client sans numéro n’a toujours aucun garde d’idempotence.

**Pourquoi 20K CCU :** 1 700 shards. Un exploit de spam d’intents n’explose pas l’économie (prix serveur) mais sature `stepAttacks` / `Navy.launchInvasion` (fronts, bateaux, `guard < 80`). Le rate limit 20/s est le seul filet.

**Worker :**

1. Exiger un entier `sequence >= 1` pour toute action mutante en `playing` (`Attack`, `Boat`, `Build`, `Nuke`, `Diplomacy`, `Research`, `Retreat`, `Upgrade`, `QuickChat`). Garder `nil` **uniquement** si un flag `Config.ALLOW_UNSEQUENCED_INTENTS` (défaut false) — ou supprimer le branchement.
2. `SetAttackRatio` / `ChooseDoctrine` en lobby : sequence optionnelle OK (pas de mutation de carte).
3. Test : `enqueue(..., nil, { index = land })` → `InvalidSchema`. `enqueue(..., 1, ...)` puis `enqueue(..., 1, ...)` → `DuplicateSequence`. Banc client inchangé (le client officiel envoie déjà un compteur).
4. Fichiers : `IntentValidator.luau`, `tests/simulate.luau`. Ne pas toucher `init.client.luau` sauf si le compteur n’est pas envoyé sur un remote (vérifier `AttackOrder` etc.).

**Contraintes :** server-authoritative. Feel apply immédiat inchangé. Ne pas mixer avec N14 (lockstep). Pas de RemoteFunction.

---

### ISSUE-N42 — `attackLogic` scanne tous les `buildings` par tuile capturée (ferme N31 + N35)

**Priorité :** P1 perf combat. Détache le buffer `defense` mort (N35) du scan bunkers (N31).

**Problème :** combat vivant, **chaque tuile** dans `guard < 80` :

```
for index, building in state.buildings do
    if building.kind == DEF and building.slot == defender.slot then
        -- distance DEFENSE_RADIUS (30 après apply)
```

Jusqu’à 80 × N fronts × hash `buildings` (~90–200 en milieu de partie) par tick. `GameState.applyDefenseAura` **écrit** déjà `state.defense` (u8, falloff) à pose/destroy bunker, mais `attackLogic` **ne le lit jamais**. Deux systèmes, un seul utilisé, le plus cher.

**Pourquoi 20K CCU :** hitch dans `stepAttacks`, déjà borné par `guard < 80`. 8 humains qui percent le même tick = 80 scans hash. Le p95 headless (1.27 ms, 0 humain) **sous-estime** : pas de 8 clients + IntentValidator. N38/N39 ont retiré l’allocator marine/annex ; le scan bunkers est le prochain O(B) dans la hot path.

**Worker — choisir UNE option, pas les deux dans le même PR :**

**Option A (recommandée, OpenFront-like) :** `posted = buffer.readu8(state.defense, tile) > 0` (ou seuil `Config.DEFENSE_POST_THRESHOLD`). Supprimer la boucle buildings dans `attackLogic`. Vérifier que `applyDefenseAura` est bien appelé à pose **et** destroy (déjà le cas). Capture d’un bunker : `transferBuilding` ne réapplique PAS l’aura (même tuile, même rayon, seul `slot` change) — `posted` doit tester le **défenseur actuel**, donc option A est fausse si le buffer n’est pas par-camp.

**Donc option A ne marche que si** le buffer encode le slot, ou si on passe à l’option B.

**Option B (sûre, index) :** table `state.bunkersBySlot[slot] = { tile, ... }` maintenue dans `placeBuilding` / `destroyBuilding` / `transferBuilding` / `removePlayer`. `attackLogic` itère **uniquement** les bunkers du défenseur (O(bunkers_défenseur), typiquement 0–8). Recyclage `table.clear` interdit de recréer la liste par tuile.

3. Ne pas changer `DEFENSE_POST_BONUS` / `DEFENSE_POST_SPEED_BONUS` / `DEFENSE_RADIUS`. Ne pas baisser `guard < 80` dans le même PR.
4. Test : bunker à portée → `posted` (pertes attaquant ×5) ; bunker hors rayon → pas de bonus ; capture du bunker → le nouveau proprio bénéficie, l’ancien non. Banc 6000 ticks vert.
5. Fichiers : `ChantierB.luau` (`attackLogic`), `GameState.luau` (index si B). Pas le stub `GameState.stepAttacks`.

**Contraintes :** déterminisme identique à l’ancien scan (même rayon euclidien). Server-only. Feel apply immédiat inchangé. Ne pas mixer avec N18 (heap) ni N11 (`MAX_TILES_PER_TICK`).

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert (`math.max` perd les +1 concurrents) |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert |
| N10 | Divers P3 | P3 | ouvert |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | ouvert |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 factions) | P1 | ouvert |
| N13 | Parité combat (ère / cost factor / constantes mortes) | P2 | ouvert |
| N14 | Apply immédiat vs lockstep (feel #19) | P1 | ouvert (produit) |
| N15 | `PREPARATION_DURATION=0` vs gardes `combatUnlocked` | P2 | ouvert |
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 | aura → N35 / **N42** ; mer → **N37 fait** |
| N17 | Humains éliminés occupent le cap | P2 | ouvert |
| N18 | Heap AimFront ≠ ChantierB / BoatFront | P2 | ouvert (frontier mixte mag vs TERRAIN_COST) |
| N19 | Embargo allié + tribus auto-accept | P2 | ouvert |
| N20 | `railIncome` vs `deliveryValue` | P2 | **fait** `stopBonus` ; reste niveau live vs snapshot colis |
| N21 | QuickChat 2-args | P3 | **fait** passe 5 |
| N22 | Warships O(carriers × boats) | P2 | ouvert (shells ; spawn → **N38 fait**) |
| N23 | `retreatAttack` premier front | P2 | **fait** passe 5 |
| N24 | notify/sfx `FireAllClients` | P2 | **fait** passe 5 |
| N25 | `MAX_BOATS_PER_PLAYER` 6 vs 3 | P3 | ouvert |
| N26 | SAM chance 0.55 vs 1.0 | P1 | **fait** Config=1.0 |
| N27 | Embargo land trade | P2 | **doc** maritime-only |
| N28 | `RequestSnapshot` mort client | P2 | ouvert |
| N29 | Seq commitée avant apply | P3 | **fait** cette passe |
| N30 | Stub `seedBeachhead` faux | P3 | **fait** `error(...)` |
| N31 | Scan bunkers O(B) | P1 | ouvert → **N42** pour le worker |
| N32 | `viewFor` requests expirées | P3 | **fait** |
| N33 | `BOAT_LANDING_BONUS` mort | P2 | ouvert |
| N34 | `areAllied` ignore expiry pacte | P2 | **fait** passe 7 |
| N35 | `applyDefenseAura` buffer mort | P2 | ouvert → **N42** |
| N36 | AimFront figé après premier lancer | P2 | **fait** passe 8 |
| N37 | `findSeaPath` alloc 40k / appel | P2 | **fait** passe 8 |
| N38 | `syncCarriers` O(B) / tick | P2 | **fait** cette passe |
| N39 | `tryAnnex` alloc + BFS mort | P2 | **fait** cette passe |
| N40 | Éliminés skip `Persistence.record` | P1 | **fait** cette passe |
| N41 | Sequence `nil` bypass idempotence | P2 | **nouveau** |
| N42 | `attackLogic` index bunkers / lire `defense` | P1 | **nouveau** (ferme N31+N35) |

Textes worker-ready N1–N25, N28, N31, N33, N35 : PR #21 / #22 / #24 / #26 / #29 `NIGHTLY_REPORT.md` historique.

---

## 6. Drift Config → `ChantierB.apply` (extrait)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | formule custom |
| `MAX_TILES_PER_TICK` | 400 | 56 | **non** (`guard<80`) |
| `DEFENSE_RADIUS` | 6 | 30 | scan buildings (N31/N42), pas le buffer (N35) |
| `BOAT_TROOP_RATIO` | 0.2 | 0.2 | oui |
| `RETREAT_LOSS` | 0.25 | 0.25 | oui |
| `SAM_INTERCEPT_CHANCE` | **1.0** | 1.0 | oui (N26 clos) |
| `SAM_RANGE` | 34 | 70 | oui |
| `SAM_COOLDOWN` | 90 | 75 | oui |
| `TRUCK_GOLD_BASE` | 10 | 14 | oui |
| `TRAIN_STOP_BONUS` | **0.12** | 0.12 | Trade + HUD (N20) |
| `BOAT_LANDING_BONUS` | 1.35 | 1.35 | **non** (N33) |
| `MAX_BOATS_PER_PLAYER` | 6 | 6 | oui (N25) |
| `PREPARATION_DURATION` | 0 | 0 | forcé true |
| `ALLIANCE_DURATION` | 3000 | 3000 | oui (`areAllied` + `Diplomacy.step`) |

---

## 7. Preuve tests

`./tests/run.sh` → **exit 0**.

Serveur :

```
seed 7 / 99991 / 31337 / 1234567 : 18 factions, invariants OK
factions : 18
intentions : sequence, idempotence, apply immediat, rate limit OK
intentions : schema doctrine/nuke/diplomatie, ended OK
intentions : QuickChat cooldown honore
intentions : QuickChat 2-args refuse, 3-args marque
intentions : diplomatie self et sequence inf refusees
intentions : sequence committee apres apply reussi (N29)
beachhead : frontier voisins, pas de remboursement
aim reinforce : un seul front apres deux lancers
aim re-vise : second lancer ancre sourceTile
aim re-vise : seconde visée remplace la premiere
aim beachhead : tete de pont intacte, front terre vise
colis snapshot : niveau au depart honore
railIncome bonus : TRAIN_STOP_BONUS dans l'estime HUD
accept expire : proposition perimee refusee
viewFor expire : request perimee absente du HUD
retraite couple : terre + tete de pont marques
refund disconnect : troupes restituees a l'attaquant
removePlayer GC : propositions / embargos / extensions vers disparu nettoyees
beachhead merge : front terre separe, troupes de pont intactes
areAllied expiry : pacte perime refuse avant step
boat own-tile : restitution integrale, pas de malus
findSeaPath pool : 5 tuiles, 4 appels identiques
syncCarriers dirty : pose / capture / destroy OK
tryAnnex poche terrestre : 8 tuiles annexees, pool reutilise
tryAnnex ocean : poche cotiere refusee
settledHumans : snapshot humain elimine, bot ignore
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=11.3 p95Changed=45 maxChanged=747 avgTickMs=0.37 p95TickMs=1.27
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **34/34 OK** — tous les écrans se construisent et s’exécutent sans erreur.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass9.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState` (snapshot `settledHumans` seulement).

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead`) → `GameState.launchAttack`.
