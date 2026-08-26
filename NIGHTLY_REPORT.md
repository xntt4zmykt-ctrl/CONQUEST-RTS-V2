# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 11)

Déclencheur : ouverture de la **PR #34** (`cursor/analyse-nocturne-du-codebase-350e`) — sequence playing obligatoire, `bunkersBySlot`, specs N43–N45.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-9975`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#34.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes et slot cible sont dérivés serveur.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #34 (passe 10) : claims vérifiés.** Sequence playing `>= 1` (`ALLOW_UNSEQUENCED_INTENTS=false`), `bunkersBySlot` Option B, lobby ratio/doctrine nil OK. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #34 a documenté (N43, N44, N45 Option A)**. Recettes = hardening 915c / c68a, pas une nouvelle sémantique. Feel n’avait toujours pas les inbound transports/missiles.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #34

| Claim #34 | Réalité à l’ouverture |
|---|---|
| Playing : sequence entière `>= 1` (N41) | Oui. Lobby `SetAttackRatio` / `ChooseDoctrine` : nil OK. |
| `attackLogic` lit `bunkersBySlot` (N42) | Oui. pose / destroy / transfer / removePlayer. Capture suit le camp. |
| Specs N43–N45 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, #17/#18/#20/#23/#25/#27/#30/#31/#33 hardening, #19/#21/#22/#24/#26/#28/#29/#32/#34 feel. **#34 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←#20←#23←#25←#27←#30←#31←#33) reste distincte. Hardening 69b4 (convois `kind==2`) n’est pas encore une PR listée ici au moment du fetch.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N43–N45 du rapport #34.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Transports inbound non restitués (N43) | `GameState.luau` | `removePlayer` détruisait seulement `boat.slot == departing`. Un transport ennemi vers la côte survivait ; après `setOwner` → NEUTRAL, `Navy.step` ne retraite pas et `resolveLanding` pose une tête de pont hors `MAX_ACTIVE_ATTACKS`. Recette 915c : `kind==1`, **avant** `setOwner`, restitution 100 %, pas `require Navy`. |
| Missiles inbound vs slot recyclé (N44) | `GameState.luau` | `Nukes.step` explose sur `tx, ty` sans re-vérifier le propriétaire. Kick → `addPlayer` recycle → `findSpawn` dans le splash. Recette c68a contrat B : `toIndex(floor(tx),floor(ty))`, pas de refund, tiers conservé. |
| `applyDefenseAura` writes mortes (N45 A) | `GameState.luau`, `ChantierB.luau` | Disque `DEFENSE_RADIUS=30` → jusqu’à 3721 `readu8`+`writeu8` par pose/destroy. Après `install()`, `attackLogic` lit `bunkersBySlot`, pas le buffer. Appels retirés ; fonction conservée pour `tileCost` hors install. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), warships grille (N22), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), `Diplomacy.request` inverse périmée (N46), cadran/colis recycle (N47), convoi marchand inbound (N48), bateau allié = retraite 25 % (N10.8 design).

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (seq obligatoire en playing, apply immédiat) → tick :
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
- **Posted bunker** = index `bunkersBySlot`, pas le hash `buildings` ni le buffer `defense` (écritures coupées, N45).
- **Inbound `removePlayer`** = transports `kind==1` restitués 100 % + missiles contrat B, **avant** `setOwner`. Bateaux/missiles **du** partant détruits.
- **Réplication :** StateDelta / UnitSnapshot / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. MatchUpdate / roster → tous (menu). Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready (nouveaux, N46–N48)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N22, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N32/N34/N36–N45 = faits. N27 = doc only. N35 restant écritures → **N45 fait**.

---

### ISSUE-N46 — `Diplomacy.request` bloqué par une inverse périmée (feel)

**Priorité :** P2 diplomatie / bots. Déjà livré sur hardening 915c / PR #31 ; **absent de la ligne feel**.

**Problème :** `Diplomacy.request` voit `requests[to][from]` et appelle `accept`. `accept` refuse déjà une expiry (`tick >= expiry`) et **return false sans enfiler** la nouvelle demande. `Bots.step` tourne **avant** `Diplomacy.step` : une proposition inverse périmée reste dans `requests[]` ce tick. 1 tick (ou 12 pour une tribu) de diplomatie bloquée — même classe que `areAllied` / `viewFor`.

Feel a le garde `accept` (passe 4) mais **pas** le `requestIsLive` dans `request`. Hardening 915c : si inverse périmée → `theirs[from] = nil` puis enfiler.

**Pourquoi 20K CCU :** 18 factions Classique, bots qui se proposent en boucle. Un tick de silence diplomatique à chaque expiration croisée fausse les pactes late-game (et donc les fronts autorisés).

**Worker :**

1. Porter la recette 915c, ne pas inventer. Extraire `requestIsLive(state, expiry) = typeof(expiry)=="number" and state.tick < expiry` (true legacy). Dans `Diplomacy.request`, si inverse présente et live → `accept` ; si périmée → clear + enfiler la nouvelle. Ne **pas** signer un pacte sur une expiry.
2. Inverse **vivante** : toujours acceptation (croisement).
3. Test : B→A enfilée, `requests[B][A]=0`, `tick=1`, `request(A,B)` OK, pacte **non** signé, `requests[A][B]` posé, inverse B→A absente. Second test : inverse live → pacte signé. Banc 6000 ticks vert.
4. Fichiers : `Diplomacy.luau`, `tests/simulate.luau`. Ne pas toucher `accept` / `areAllied` dans le même PR.

**Contraintes :** server-authoritative. Feel apply immédiat inchangé. Recette = 915c. Ne pas mixer avec N19 (embargo allié).

---

### ISSUE-N47 — Cadran `doomWarnedAt` / colis `tradeDeliveries` au recycle (feel)

**Priorité :** P2 slot recyclé. Déjà livré sur hardening 1dbe / PR #30 ; **absent de la ligne feel**.

**Problème :** `removePlayer` feel purge diplo inbound + transports/missiles (N43/N44) mais **pas** `doomWarnedAt` / `doomUnderSince` (indexés par slot, créés par `ChantierB.new`) ni `tradeDeliveries` (indexés par tuile, `delivery.slot` = payeur). `Trade.step` tourne **avant** `stepElimination`. Un `JoinRequest` entre deux ticks recycle le slot : l’héritier hérite warn/drain/rot, ou une usine reposée sur la même tuile encaisse le colis du disparu.

**Pourquoi 20K CCU :** 8 humains / shard, déconnexions lobby. Doomsday drain sur un spawn neuf = wipe hors intention. Or fantôme = comptabilité cassée.

**Worker :**

1. Porter 1dbe, ne pas inventer. Dans `removePlayer`, **après** destroy buildings / inbound boats-missiles / `setOwner` : `doomWarnedAt[slot]=nil`, `doomUnderSince[slot]=nil` ; pour chaque `tradeDeliveries[index]` si `delivery.slot==departing` alors nil ; `tradeCooldowns[index]` nil si plus de bâtiment.
2. Ne pas changer `stepDoomsday` / `Doomsday` / `TRADE_GOLD_*`.
3. Test : poser `doomWarnedAt[B]=999`, `removePlayer(B)`, `addPlayer` recycle → cadran nil. Colis `tradeDeliveries[usineB]` → nil après `removePlayer(B)`. Banc 6000 ticks vert.
4. Fichiers : `GameState.luau`, `tests/simulate.luau`. Ne pas mixer avec N9 (`stepDoomsday` O(TILE_COUNT)) ni N48 (navire trade, pas colis terrestre).

**Contraintes :** server-only. Feel inchangé. Recette = 1dbe.

---

### ISSUE-N48 — Convoi marchand inbound vers le port d’un disparu (feel)

**Priorité :** P2 économie / slot recyclé. Spécifié sur hardening c68a (N32) ; **livré sur hardening 69b4** (contrat B, coulé avant `setOwner`) ; **absent de la ligne feel**. Distinct de N47 (colis terrestre `tradeDeliveries`).

**Problème :** `removePlayer` détruit les bâtiments **du** disparu, puis laisse les `kind==2` (trade) d’**autrui** en mer. `resolveTrade` no-op si le port d’arrivée a disparu — jusqu’ici anodin. Un `JoinRequest` recycle + `placeBuilding(PORT)` sur **la même tuile** avant l’arrivée : `destination.slot` est l’héritier, `canTrade` passe, **les deux camps encaissent**. Le convoi occupe aussi `MAX_TRADE_SHIPS` jusqu’à l’arrivée.

**Pourquoi 20K CCU :** disconnect lobby 8 humains + rebuild port sur l’ancienne côte. Or fantôme + congestion `MAX_TRADE_SHIPS`.

**Worker — choisir UNE option :**

1. **(A)** stocker `destSlot` au spawn, `resolveTrade` exige `destination.slot == destSlot` ; **(B)** `removePlayer` coule les trade ships dont `owner[targetTile]` / bâtiment port == disparu **avant** `destroyBuilding` ; **(C)** documenter le paiement à l’héritier comme volontaire.
2. Si A ou B : pas de gold à l’héritier. Ne pas taxer le vendeur (le convoi n’est pas une retraite).
3. Test : convoi A→port B → `removePlayer(B)` → `addPlayer` recycle → reposer un PORT sur la même tuile → `Navy.step` jusqu’à arrivée. Assert : or héritier inchangé (A/B) **ou** commentaire + assert volontaire (C). Second test : convoi A→C, B part, or A et C versés.
4. Fichiers : `Navy.luau` (`spawnTradeShips`, `resolveTrade`) et/ou `GameState.removePlayer`, `tests/simulate.luau`.

**Contraintes :** pas de `require(Navy)` depuis GameState (si purge dans `removePlayer`, filtrer `kind==2` comme `kind==1`). Ne pas toucher `TRADE_GOLD_*`. Ne pas mixer avec N43 (transports `kind==1` déjà livrés) ni N47 (colis terrestre). Recette = 69b4, pas une nouvelle sémantique. Pas de RemoteFunction.

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
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 | **N37+N42+N45 faits** |
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
| N28 | `RequestSnapshot` mort client | P2 | ouvert (serveur rate-limite ; client n’envoie jamais) |
| N29 | Seq commitée avant apply | P3 | **fait** passe 9 |
| N30 | Stub `seedBeachhead` faux | P3 | **fait** `error(...)` |
| N31 | Scan bunkers O(B) | P1 | **fait** passe 10 (N42) |
| N32 | `viewFor` requests expirées | P3 | **fait** |
| N33 | `BOAT_LANDING_BONUS` mort | P2 | ouvert |
| N34 | `areAllied` ignore expiry pacte | P2 | **fait** passe 7 |
| N35 | `applyDefenseAura` buffer mort (posted) | P2 | **fait** posted=index ; écritures → **N45 fait** |
| N36 | AimFront figé après premier lancer | P2 | **fait** passe 8 |
| N37 | `findSeaPath` alloc 40k / appel | P2 | **fait** passe 8 |
| N38 | `syncCarriers` O(B) / tick | P2 | **fait** passe 9 |
| N39 | `tryAnnex` alloc + BFS mort | P2 | **fait** passe 9 |
| N40 | Éliminés skip `Persistence.record` | P1 | **fait** passe 9 |
| N41 | Sequence `nil` bypass idempotence | P2 | **fait** passe 10 |
| N42 | `attackLogic` index bunkers | P1 | **fait** passe 10 |
| N43 | Transports inbound `removePlayer` (feel) | P2 | **fait** cette passe (port 915c) |
| N44 | Missiles inbound vs slot recyclé | P2 | **fait** cette passe (port c68a) |
| N45 | `applyDefenseAura` writes mortes | P3 | **fait** cette passe (Option A) |
| N46 | `Diplomacy.request` inverse périmée | P2 | **nouveau** (port 915c) |
| N47 | Cadran / colis recycle feel | P2 | **nouveau** (port 1dbe) |
| N48 | Convoi marchand inbound | P2 | **nouveau** (port 69b4 / spec c68a N32) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 `NIGHTLY_REPORT.md` historique.

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
| `TRUCK_GOLD_BASE` | 10 | 14 | oui |
| `TRAIN_STOP_BONUS` | **0.12** | 0.12 | Trade + HUD (N20) |
| `BOAT_LANDING_BONUS` | 1.35 | 1.35 | **non** (N33) |
| `MAX_BOATS_PER_PLAYER` | 6 | 6 | oui (N25) |
| `PREPARATION_DURATION` | 0 | 0 | forcé true |
| `ALLIANCE_DURATION` | 3000 | 3000 | oui (`areAllied` + `Diplomacy.step`) |
| `ALLOW_UNSEQUENCED_INTENTS` | **false** | n/a | oui (N41) |

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
intentions : sequence nil refusee en playing, optionnelle en lobby (N41)
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
attackLogic bunkers : posted / hors rayon / capture OK
boat inbound : transports restitues, pas de tete de pont vs disparu
boat attacker leave : transports de l'attaquant detruits
nuke inbound : ogive annulee, pas de remboursement, heritier intact
nuke third-party : frappe visee sur un tiers conservee
nuke attacker leave : missiles du tireur detruits
defense aura : buffer non ecrit, index pose/destroy OK
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=11.3 p95Changed=45 maxChanged=747 avgTickMs=0.36 p95TickMs=1.17
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **34/34 OK** — tous les écrans se construisent et s’exécutent sans erreur. N43–N45 sont server-only : banc client inchangé.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass11.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState` (snapshot `settledHumans` seulement). `bunkersBySlot` est un champ d’état, pas un module. N43/N44 n’ajoutent **pas** de `require Navy` / `require Nukes` depuis `GameState`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead`) → `GameState.launchAttack`.
