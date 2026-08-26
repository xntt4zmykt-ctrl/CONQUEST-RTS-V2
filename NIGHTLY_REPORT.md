# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 8)

Déclencheur : ouverture de la **PR #28** (`cursor/analyse-nocturne-du-codebase-4fe1`) — areAllied expiry, boat own-tile, specs N36–N37.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-6be5`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#28.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes et slot cible sont dérivés serveur.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #28 (passe 7) : claims vérifiés.** `areAllied` honore `tick < expiry` (`true` legacy vivant), restitution bateau 100 % sur côte déjà prise, `removePlayer` purge `allianceExtensions` inbound, diplomatie self / `inf` refusées à l’enqueue. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #28 a documenté (N36, N37)** plus un garde JoinRequest `nan`/`inf` hors bundle.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #28

| Claim #28 | Réalité à l’ouverture |
|---|---|
| `areAllied` = deux sens **et** `tick < expiry` | Oui. `pactStillLive` : nombre = `tick < expiry`, `true` legacy vivant. |
| Bots / notify ignorent un pacte périmé | Oui. `Bots.step` tourne **avant** `Diplomacy.step` ; les décisions passent par `areAllied`. |
| Transport côte déjà prise : restitution 100 % | Oui. `Navy.step` + `resolveLanding`. Retraite vraie (`retreating`) garde `BOAT_RETREAT_LOSS`. |
| `removePlayer` purge `allianceExtensions` inbound | Oui. |
| Diplomatie `targetSlot == self` et séquence `inf` | Oui, à l’enqueue (`IntentValidator`). |
| Specs N36–N37 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, #17/#18/#20/#23/#25/#27 hardening, #19/#21/#22/#24/#26/#28 feel. **#28 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←#20←#23←#25←#27) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N36 option A du rapport #28, N37 pooling tel que spécifié.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| AimFront figé après le premier lancer (N36) | `SystemsBootstrap.luau` | `sourceTile == nil` n’est pas « front terre ». Re-visée du couple (`not isBeachhead`), y compris si `sourceTile` est déjà posé. Ticket « le front n’écoute plus le clic ». |
| `findSeaPath` allouait 40 960 octets + `parent` + `queue` par appel (N37) | `Navy.luau` | Invasions + retraites + vague commerciale (tous les 45 ticks). Pool `visitBuf` / `parentScratch` / `queueScratch`, `buffer.fill(buf, 0, 0)`, `table.clear`. `MAX_BFS_NODES` inchangé. |
| `JoinRequest` acceptait `nan` / `inf` | `init.server.luau` | `typeof(inf)=="number"` ; `nan` traverse `math.clamp` vers `Nations.get`. Hors bundle ; même garde que `isInteger`. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18 — **plus visible après N36**, ne pas mixer), embargo allié (N19), warships grille (N22), MAX_BOATS (N25), scan bunkers combat (N31), RequestSnapshot client (N28), seq avant apply (N29), landing bonus mort (N33), buffer defense mort (N35), bateau allié = retraite 25 % (N10.8 design).

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (apply immédiat) → tick :
  Bots.step → Navy.step → Nukes.step → Trade.step → Diplomacy.step → GameState.step → replicate(fireDeployed)
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom), BoatFront, AimFront, tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`. Stub = `error(...)`.
- **`areAllied`** = deux directions **et** `tick < expiry` (`true` legacy tests reste vivant).
- **AimFront wrap** = re-visée du front terre du couple ; jamais `isBeachhead`.
- **Réplication :** StateDelta / UnitSnapshot / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. MatchUpdate / roster → tous (menu). Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready (nouveaux, N38–N39)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N22, N25, N28, N29, N31, N33, N35 restent ouverts.** N20/N21/N23/N24/N26/N30/N32/N34/N36/N37 = faits. N27 = doc only.

---

### ISSUE-N38 — `syncCarriers` scan O(B) + table `seen` chaque tick

**Priorité :** P2 perf marine (détache le spawn warship de N22).

**Problème :** `Navy.step` appelle `syncCarriers` **avant** `stepCarriers`, **chaque tick** (10 Hz) :

1. Parcourt `state.boats` à l’envers, alloue `seen: { [number]: boolean } = {}`.
2. Parcourt **tous** `state.buildings` pour spawner un porte-avions sur chaque `NAVAL_BASE` absent de `seen`.

N22 = boucle imbriquée shells O(carriers × boats). Ici c’est uniquement le **maintien** des warships. Un salon Classique en milieu de partie a ~20 bases navales + ~90+ bâtiments : 10 scans complets/s pour recréer une table hash jetable.

**Pourquoi 20K CCU :** 1 700 shards. Sur un shard chargé (18 factions, 200+ bâtiments), c’est du travail dupliqué avec N31 (scan bunkers **par tuile capturée**). Allocator Luau + itération du dictionnaire `buildings` (hash, pas array) au tick. Le p95 headless (0.45 ms, 0 humain) **sous-estime** : pas de 8 clients + IntentValidator dans la mesure.

**Worker :**

1. Spawn/despawn **événementiel** : à `placeBuilding` / `destroyBuilding` / capture de `NAVAL_BASE` seulement. Ou dirty flag `state._carriersDirty` levé par ces chemins, `syncCarriers` no-op si false.
2. Réutiliser un `seen` module-level (`table.clear`), ne pas allouer chaque tick si le scan reste.
3. Test : poser une base → un carrier ; détruire la base → carrier retiré ; capture de base → `boat.slot` suit le nouveau proprio. Banc warships / commerce mer reste vert. Ne pas changer portée, cadence, priorité de cibles (N22).
4. Fichiers : `Navy.luau`, éventuellement `GameState.placeBuilding` / `destroyBuilding`, `tests/simulate.luau`.

**Contraintes :** déterminisme du slot carrier = slot de la base. Ne pas mixer avec N22 (shells) ni N25 (`MAX_BOATS`). Server-only. Pas de RemoteEvent. Feel apply immédiat inchangé.

---

### ISSUE-N39 — `ChantierB.tryAnnex` alloue `visited` + `queue` + `pocket` par tuile annexée

**Priorité :** P2 perf combat (feel n’a pas reçu le N21 GC du hardening 0751 — **N21 feel = QuickChat**, collision d’IDs).

**Problème :** `tryAnnex` (appelé depuis le combat vivant quand une enclave est coupée) fait à chaque invocation :

```
visited: { [number]: boolean } = {}
queue = { seed }
pocket: { number } = {}
```

BFS jusqu’à 280 tuiles ou océan (enclave terrestre ; océan = abort, **pas un bug**). Une offensive qui casse une côte peut annexer plusieurs poches le même tick. Tables hash jetables × N captures.

**Pourquoi 20K CCU :** le hitch n’est pas le BFS 280, c’est l’allocator pendant `stepAttacks` (déjà `guard < 80` tuiles/front). 8 humains qui percent le même tick = rafale `tryAnnex`. GC Luau sur shard 10 Hz.

**Worker :**

1. Pool module-level : `visited` (buffer u8 TILE_COUNT **ou** table recyclée `table.clear`), `queue` / `pocket` arrays recyclés. Si buffer : `buffer.fill(buf, 0, 0)` en unwind ou generation-stamp (même pattern que N37).
2. Ne pas changer la règle océan = abort (enclave terrestre only). Ne pas baisser le plafond 280 dans le même PR.
3. Test : poche terrestre close annexée ; poche touchant l’océan **non** annexée. Réutiliser un banc d’enclave si présent, sinon construire une poche 3×3 entourée d’attaquant.
4. Fichiers : `ChantierB.luau`, `tests/simulate.luau`.

**Contraintes :** déterminisme du set annexé. Ne pas mixer avec N31 (scan bunkers) ni N35 (buffer `defense`). Combat vivant = `ChantierB.tryAnnex`, pas un nouveau chemin dans le stub `GameState`. Server-authoritative.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert (BoatFront **gare** les ponts pendant le cap) |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert |
| N10 | Divers P3 | P3 | ouvert |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | ouvert |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 factions) | P1 | ouvert |
| N13 | Parité combat (ère / cost factor / constantes mortes) | P2 | ouvert |
| N14 | Apply immédiat vs lockstep (feel #19) | P1 | ouvert (produit) |
| N15 | `PREPARATION_DURATION=0` vs gardes `combatUnlocked` | P2 | ouvert |
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 | aura → N35 ; mer → **N37 fait** |
| N17 | Humains éliminés occupent le cap | P2 | ouvert |
| N18 | Heap AimFront ≠ ChantierB / BoatFront | P2 | ouvert (**plus visible après N36** : frontier mixte mag vs TERRAIN_COST) |
| N19 | Embargo allié + tribus auto-accept | P2 | ouvert |
| N20 | `railIncome` vs `deliveryValue` | P2 | **fait** `stopBonus` ; reste niveau live vs snapshot colis |
| N21 | QuickChat 2-args | P3 | **fait** passe 5 |
| N22 | Warships O(carriers × boats) | P2 | ouvert (shells ; spawn → **N38**) |
| N23 | `retreatAttack` premier front | P2 | **fait** passe 5 |
| N24 | notify/sfx `FireAllClients` | P2 | **fait** passe 5 |
| N25 | `MAX_BOATS_PER_PLAYER` 6 vs 3 | P3 | ouvert |
| N26 | SAM chance 0.55 vs 1.0 | P1 | **fait** Config=1.0 |
| N27 | Embargo land trade | P2 | **doc** maritime-only |
| N28 | `RequestSnapshot` mort client | P2 | ouvert |
| N29 | Seq commitée avant apply | P3 | ouvert (self-diplo n’occupe plus la seq) |
| N30 | Stub `seedBeachhead` faux | P3 | **fait** `error(...)` |
| N31 | Scan bunkers O(B) | P1 | ouvert |
| N32 | `viewFor` requests expirées | P3 | **fait** |
| N33 | `BOAT_LANDING_BONUS` mort | P2 | ouvert |
| N34 | `areAllied` ignore expiry pacte | P2 | **fait** passe 7 |
| N35 | `applyDefenseAura` buffer mort | P2 | ouvert |
| N36 | AimFront figé après premier lancer | P2 | **fait** cette passe |
| N37 | `findSeaPath` alloc 40k / appel | P2 | **fait** cette passe |
| N38 | `syncCarriers` O(B) / tick | P2 | **nouveau** (détaché de N22) |
| N39 | `tryAnnex` alloc visited/queue | P2 | **nouveau** (feel ; N21 feel ≠ N21 hardening) |

Textes worker-ready N1–N25, N28, N29, N31, N33, N35 : PR #21 / #22 / #24 / #26 `NIGHTLY_REPORT.md` historique.

---

## 6. Drift Config → `ChantierB.apply` (extrait)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | formule custom |
| `MAX_TILES_PER_TICK` | 400 | 56 | **non** (`guard<80`) |
| `DEFENSE_RADIUS` | 6 | 30 | scan buildings (N31), pas le buffer (N35) |
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
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=8.0 p95Changed=8 maxChanged=479 avgTickMs=0.27 p95TickMs=0.45
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **34/34 OK** — tous les écrans se construisent et s’exécutent sans erreur.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass8.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead`) → `GameState.launchAttack`.
