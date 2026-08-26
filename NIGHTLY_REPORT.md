# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 12)

Déclencheur : ouverture de la **PR #36** (`cursor/analyse-nocturne-du-codebase-9975`) — inbound transports/missiles, aura defense coupée, specs N46–N48.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-fd0b`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#36.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes et slot cible sont dérivés serveur.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #36 (passe 11) : claims vérifiés.** Transports inbound `kind==1` restitués 100 % avant `setOwner`, missiles contrat B (`toIndex(floor(tx),floor(ty))`, pas de refund, tiers conservé), `applyDefenseAura` plus appelé. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #36 a documenté (N46, N47, N48)**. Recettes = hardening 915c / 1dbe / 69b4, pas une nouvelle sémantique. Feel n’avait toujours pas `requestIsLive`, cadran/colis recycle, ni convois `kind==2`.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #36

| Claim #36 | Réalité à l’ouverture |
|---|---|
| Transports inbound restitués (N43) | Oui. `kind==1`, avant `setOwner`, 100 %, pas de require Navy. |
| Missiles inbound contrat B (N44) | Oui. `toIndex(floor(tx),floor(ty))`, pas de refund, tiers conservé. |
| `applyDefenseAura` writes mortes (N45 A) | Oui. Index `bunkersBySlot` inchangé. |
| Specs N46–N48 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, #17/#18/#20/#23/#25/#27/#30/#31/#33/#35 hardening, #19/#21/#22/#24/#26/#28/#29/#32/#34/#36 feel. **#36 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←#20←#23←#25←#27←#30←#31←#33←#35) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N46–N48 du rapport #36.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `Diplomacy.request` bloqué par une inverse périmée (N46) | `Diplomacy.luau` | `accept` refuse déjà une expiry et **return false sans enfiler**. `Bots.step` tourne **avant** `Diplomacy.step`. Recette 915c : `requestIsLive` ; inverse live → `accept` ; périmée → clear + enfiler. **`accept` / `areAllied` non touchés.** |
| Cadran / colis au recycle (N47) | `GameState.luau` | `doomWarnedAt` / `doomUnderSince` indexés par slot ; `tradeDeliveries` par tuile (`delivery.slot` = payeur). Recette 1dbe : purge **après** destroy / inbound boats-missiles / `setOwner` ; ceinture `addPlayer`. `stepDoomsday` inchangé. |
| Convoi marchand inbound (N48) | `GameState.luau` | `kind==2` d’autrui survivait ; JoinRequest + PORT sur la même tuile → **les deux camps encaissent**. Recette 69b4 contrat B : couler avant `setOwner` via `owner[targetTile]`, pas d’or, pas de malus vendeur, tiers conservé. Pas de require Navy. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), warships grille (N22), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), `retreatBoats` / `targetSlot` (N49), `findSpawn` splash (N50), convoi vs PORT détruit au combat (N51), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK (cadran non effacé si `tiles==0`).

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (seq obligatoire en playing, apply immédiat) → tick :
  Bots.step → Navy.step (syncCarriers si dirty) → Nukes.step → Trade.step → Diplomacy.step → GameState.step → replicate(fireDeployed)
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom), BoatFront, AimFront, tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`. Stub = `error(...)`. Deux débarquements du même couple = **deux** tas (N5 ouvert ; hardening N29).
- **`areAllied`** = deux directions **et** `tick < expiry` (`true` legacy tests reste vivant).
- **AimFront wrap** = re-visée du front terre du couple ; jamais `isBeachhead`.
- **`tryAnnex`** = BFS depuis les voisins défenseur du seed déjà capturé ; océan abort ; pool N37-like.
- **Carriers** = spawn/despawn/slot sur dirty NAVAL_BASE, pas un scan 10 Hz.
- **Posted bunker** = index `bunkersBySlot`, pas le hash `buildings` ni le buffer `defense` (écritures coupées, N45).
- **Inbound `removePlayer`** = diplo + transports `kind==1` (100 %) + missiles contrat B + cadran/colis + convois `kind==2` (coulés), **avant** `setOwner`. Bateaux/missiles **du** partant détruits.
- **`Diplomacy.request`** = inverse live → acceptation ; inverse périmée → clear + enfiler (plus de silence d’un tick).
- **Réplication :** StateDelta / UnitSnapshot / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. MatchUpdate / roster → tous (menu). Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready (nouveaux, N49–N51)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N22, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N32/N34/N36–N48 = faits. N27 = doc only.

---

### ISSUE-N49 — `retreatBoats` ignore un flip de côte (feel)

**Priorité :** P2 combat / comptabilité navale. Spécifié sur hardening 915c (N28 restant) ; **absent de la ligne feel**. Distinct de N43 (inbound `removePlayer` déjà fermé) et de N10.8 (malus allié en mer).

**Problème :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un transport n’a **pas** de `targetSlot` au `launchInvasion`. Conséquences :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers) — les troupes restent en mer vers un quai qui n’est plus B.
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs.

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite. Sans `targetSlot`, la retraite est une lecture de carte, pas une intention.

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport dans `Navy.launchInvasion`.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque — bateaux déjà en mer).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste — documenter si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N33). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % N43). Recette = hardening N28 restant. **N49 feel ≠ N28 feel historique (RequestSnapshot mort, déjà ouvert).**

---

### ISSUE-N50 — `findSpawn` ignore splash / fallout d’une frappe tiers (feel)

**Priorité :** P3 nucléaire / spawn. Reste du contrat C (hardening N33). Contrat B (ogive visée sur le disparu) = **N44 fait**.

**Problème :** une frappe **déjà visée sur un voisin** dont le cratère recouvre l’ancien capital / le `SPAWN_RADIUS` de `findSpawn`. `addPlayer` choisit un disque terrestre libre, sans lire `state.missiles` ni `state.fallout`. L’héritier spawn, `Nukes.step` explose, SAM de l’héritier n’existait pas au `engaged`.

**Pourquoi 20K CCU :** moins chaud que N44 (il faut un voisin sous missile + spawn coincé dans le rayon). Distinct du contrat B déjà livré (`nuke third-party` doit rester vert).

**Worker :**

1. Ne **pas** rouvrir le contrat B. Options : (C1) `findSpawn` refuse un centre dont un missile en vol a `toIndex(floor(tx),floor(ty))` à distance `NUKE_STATS[kind].radius` (ogive : `missile.radius`) ; (C2) `findSpawn` refuse `state.fallout[index] > tick` ; (C3) documenter « le territoire, pas le joueur » pour le splash tiers.
2. Test : A tire sur C (capitale), `removePlayer(B)`, forcer le spawn de l’héritier dans le rayon (tuiles libres), `Nukes.step`. Assert selon C1/C2/C3. `nuke third-party` inchangé.
3. Fichiers : `GameState.findSpawn` / `addPlayer`, éventuellement `Nukes`, `tests/simulate.luau`.

**Contraintes :** ne pas annuler une frappe tiers (régression N44). Ne pas rembourser l’or. Pas de RemoteFunction. Rayon lu depuis `NUKE_STATS` / `missile.radius`, pas une constante magique. Recette = hardening N33. **N50 feel ≠ N33 feel historique (`BOAT_LANDING_BONUS` mort, toujours ouvert).**

---

### ISSUE-N51 — Convoi vs PORT détruit au combat (cap `MAX_TRADE_SHIPS`) (feel)

**Priorité :** P3 économie / congestion. Reste de N48 hors recycle. Spécifié sur hardening 69b4 (N35).

**Problème :** N48 coule le convoi inbound au **recycle de slot**. Si le PORT d’arrivée est **détruit au combat** (`destroyBuilding` / capture) **sans** `removePlayer`, le `kind==2` reste en mer jusqu’à `step > #path`, puis `resolveTrade` no-op (bâtiment absent). Il occupe `MAX_TRADE_SHIPS` (24) pendant tout le transit. Pas d’or fantôme (pas de rebuild du même tick par un héritier — ça, N48 l’a fermé).

**Pourquoi 20K CCU :** late-game raids de ports + 24 slots globaux. Un camp peut saturer le cap avec des convois morts. Distinct de N20 (gold HUD) et du contrat B recycle.

**Worker — choisir UNE option :**

1. **(A)** stocker `destSlot` au spawn, `resolveTrade` exige `destination.slot == destSlot`, et `Navy.step` coule dès que `buildings[targetTile]` n’est plus un PORT ; **(B)** `Navy.step` coule tout `kind==2` dont le PORT d’arrivée a disparu (pas d’attente fin de path) ; **(C)** documenter la congestion comme volontaire.
2. **Recette livrée sur hardening fd1e / PR #37 = option B.** Dans `Navy.step`, avant resolveLanding : si `kind==TRADE` et `buildings[targetTile]` n’est plus un PORT → `table.remove`. Capture (`transferBuilding`) : le PORT existe encore → le convoi continue. Pas d’or, pas de malus vendeur.
3. Si A ou B : pas d’or. Ne pas taxer le vendeur. Ne pas recâbler N48 (recycle déjà coulé dans `removePlayer`).
4. Test : convoi A→port B, `destroyBuilding(portB)` **sans** `removePlayer`, `Navy.step`. Assert : plus de `kind==2` (A/B) **ou** commentaire + assert volontaire (C). Second test : capture du PORT (transfer) → convoi survit. Troisième : N48 recycle toujours vert.
5. Fichiers : `Navy.luau` (`Navy.step` ; ne pas toucher `spawnTradeShips` si B), `tests/simulate.luau`.

**Contraintes :** pas de `require(Navy)` depuis GameState. Ne pas toucher `TRADE_GOLD_*`. Ne pas mixer avec N49 `targetSlot` transports (champs distincts : `destSlot` convoi ≠ `targetSlot` invasion). Pas de RemoteFunction. Recette = **fd1e / PR #37**, pas une nouvelle sémantique. **N51 feel ≠ N35 feel historique (aura, déjà fait).**

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap ; deux `seedBeachhead` = deux tas) |
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
| N43 | Transports inbound `removePlayer` (feel) | P2 | **fait** passe 11 |
| N44 | Missiles inbound vs slot recyclé | P2 | **fait** passe 11 |
| N45 | `applyDefenseAura` writes mortes | P3 | **fait** passe 11 |
| N46 | `Diplomacy.request` inverse périmée | P2 | **fait** cette passe (port 915c) |
| N47 | Cadran / colis recycle feel | P2 | **fait** cette passe (port 1dbe) |
| N48 | Convoi marchand inbound | P2 | **fait** cette passe (port 69b4) |
| N49 | `retreatBoats` / `targetSlot` après flip | P2 | **nouveau** (port hardening N28 restant) |
| N50 | `findSpawn` splash / fallout | P3 | **nouveau** (port hardening N33) |
| N51 | Convoi vs PORT détruit au combat | P3 | **nouveau** (port hardening N35) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 `NIGHTLY_REPORT.md` historique.

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
request stale reverse : proposition perimee ignoree, nouvelle demande enfilee
request live reverse : croisement vivant signe le pacte
doomsday recycle : timers cadran purges au recycle de slot
colis recycle : colis / cooldown purges au recycle de slot
trade inbound : convoi coule, pas d'or a l'heritier
trade third-party : convoi A→C conserve, or verse
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=11.3 p95Changed=45 maxChanged=747 avgTickMs=0.37 p95TickMs=1.17
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **34/34 OK** — tous les écrans se construisent et s’exécutent sans erreur. N46–N48 sont server-only : banc client inchangé.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass12.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState` (snapshot `settledHumans` seulement). `bunkersBySlot` est un champ d’état, pas un module. N46 n’ajoute **pas** de require. N47/N48 n’ajoutent **pas** de `require Navy` / `require Nukes` / `require Trade` depuis `GameState`.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead`) → `GameState.launchAttack`.
