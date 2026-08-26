# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 7)

Déclencheur : ouverture de la **PR #26** (`cursor/analyse-nocturne-du-codebase-ec34`) — beachhead merge, viewFor expiry, SAM 1.0, specs N33–N35.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-4fe1`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#26.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes et slot cible sont dérivés serveur.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #26 (passe 6) : claims vérifiés.** Beachhead merge (`isBeachhead`), stub `seedBeachhead` = error, `viewFor` expiry, inbound GC requests/embargos/marks, HUD `railIncome` × `TRAIN_STOP_BONUS`, `SAM_INTERCEPT_CHANCE=1.0`. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **porté ce que #26 a documenté (N34) et ce que le hardening 5233 avait déjà livré** : paix fantôme 1 tick, malus 25 % sur une côte déjà prise, extension inbound, diplomatie self / `inf`.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #26

| Claim #26 | Réalité à l’ouverture |
|---|---|
| `launchAttack` ne fusionne plus dans une tête de pont | Oui. `not atk.isBeachhead` + park BoatFront. |
| Stub `seedBeachhead` = `error(...)` | Oui. |
| `viewFor` masque propositions périmées | Oui. **`areAllied` fuyait encore sur l’expiry du pacte** — corrigé ici (N34). |
| `removePlayer` purge requests / embargos / marques inbound | Oui. **Manquait `allianceExtensions` inbound** (slot recyclé) — corrigé ici. |
| HUD `railIncome` × `TRAIN_STOP_BONUS` | Oui. |
| `SAM_INTERCEPT_CHANCE` Config = 1.0 | Oui. |
| Specs N33–N35 | N34 **corrigé ici**. N33 / N35 restent design. |

PRs ouvertes au moment de la revue : #16 P0, #17/#18/#20/#23/#25 hardening, #19/#21/#22/#24/#26 feel. **#26 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←#20←#23←#25) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Port depuis hardening `5233` / PR #25 — **pas de réinvention**. Feel #19 inchangé.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `areAllied` ignorait l’expiry numérique (N34) | `GameState.luau` (`pactStillLive`, `true` legacy vivant) | 1 tick de paix fantôme : Attack/Boat/Nuke/dons refusés après échéance. `Bots.step` tourne **avant** `Diplomacy.step`. |
| Bots / notify alliés sur pacte mort | `Bots.luau`, `Diplomacy.luau` | `alliances[a][b]` = tick truthy. Coalition, trahison, `help_defend`, QuickChat alliésOnly. |
| Transport dont la côte a déjà été prise : malus 25 % | `Navy.luau` (`step` + `resolveLanding`) | Armes combinées (terre puis bateau) : restitution 100 %. Une vraie retraite (`retreating`) garde `BOAT_RETREAT_LOSS`. |
| `removePlayer` laissait `allianceExtensions` inbound | `GameState.luau` | `addPlayer` recycle le slot : une prolongation héritée. |
| Diplomatie `targetSlot == self` à l’enqueue | `IntentValidator.luau` | Occupait la séquence (N29) pour un no-op métier. |
| `isInteger` acceptait `inf` | `IntentValidator.luau`, `init.server.luau` | `math.floor(inf)==inf`. Hors bundle pour `init.server` ; le banc couvre IntentValidator. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront (N18), embargo allié (N19), warships grille (N22), MAX_BOATS (N25), scan bunkers (N31), RequestSnapshot client (N28), seq avant apply (N29), landing bonus mort (N33), buffer defense mort (N35), bateau allié = retraite 25 % (N10.8 design).

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
- **Réplication :** StateDelta / UnitSnapshot / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. MatchUpdate / roster → tous (menu). Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready (nouveaux, N36–N37)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N16, N17–N19, N22, N25, N28, N29, N31, N33, N35 restent ouverts.** N20/N21/N23/N24/N26/N30/N32/N34 = faits. N27 = doc only.

---

### ISSUE-N36 — AimFront figé après le premier lancer

**Priorité :** P2 feel / fronts visés.

**Problème :** `SystemsBootstrap.install` enveloppe `launchAttack` ainsi :

1. `already` = un front du couple avec `sourceTile == nil`
2. `origLaunch` (merge terre, pas `isBeachhead`)
3. `AimFront.focus` seulement si `aim` est posé **et** `not already`, en cherchant un front `sourceTile == nil`

Conséquences :

- Premier clic **sans** visée : front `sourceTile = nil`. Second clic **avec** visée : `already = true` → l’aim est jeté.
- Premier clic **avec** visée : `AimFront.focus` pose `sourceTile`. Second clic avec une **nouvelle** visée : `already = false` (plus de `sourceTile == nil`) mais la boucle de focus ne trouve plus le front → l’aim n’est jamais mis à jour.

`BoatFront` pose `sourceTile` **et** `isBeachhead` ; le wrap bootstrap n’a pas basculé sur `not atk.isBeachhead` (le critère de `GameState.launchAttack` depuis la passe 6).

**Pourquoi 20K CCU :** tickets « le front n’écoute plus le clic ». Pas un exploit ; c’est du feel mort après le premier ordre, exactement le levier OF `sourceTile`. Sous 8 humains ça se voit tout de suite.

**Worker :**

1. Décision : (A) re-viser un front terre existant (`AimFront.focus` même si `sourceTile` est déjà posé, jamais sur `isBeachhead`), (B) documenter « visée = premier lancer seulement » et court-circuiter `ps.aimTile` si un front terre du couple existe déjà, (C) aligner le wrap sur `not atk.isBeachhead` **sans** changer le re-aim (min diff, bug de re-visée reste).
2. Tests : (1) premier lancer sans aim, second avec `aimTile` — (A) le front a `sourceTile`, (B) toujours nil. (2) deux visées successives — (A) la seconde gagne. (3) une tête de pont du même couple n’est pas re-visée. Réutiliser le banc `aim reinforce : un seul front`.
3. Fichiers : `SystemsBootstrap.luau`, éventuellement `AimFront.luau`, `tests/simulate.luau`.

**Contraintes :** ne pas mixer avec N18 (heap AimFront ≠ ChantierB). Ne pas fusionner terre et `isBeachhead`. Feel apply immédiat inchangé. Ne pas casser `aim reinforce` (un seul front après deux lancers).

---

### ISSUE-N37 — `findSeaPath` alloue 40 960 octets + table `parent` à chaque trajet

**Priorité :** P2 perf marine (détache le volet mer de N16).

**Problème :** `Navy.findSeaPath` fait `buffer.create(Config.TILE_COUNT)` (40 960) et une table `parent` jusqu’à `MAX_BFS_NODES = 24 000` **par appel**. Appelé à `launchInvasion`, `beginRetreat`, et potentiellement plusieurs fois par tick (bots + humains + retraites). Le visited n’est pas pooled. N16 mélangeait ça avec le buffer `defense` ; N35 traite l’aura. Ici c’est uniquement le BFS mer.

**Pourquoi 20K CCU :** 8 humains + 10 bots peuvent lancer / reculer des transports le même tick. 5 BFS = ~200 Ko + tables hash. Le p95 headless (0.45 ms, 0 humain) **sous-estime** : les bots n’envahissent pas en rafale comme un lobby humain. Allocator Luau + GC sur shard chargé = hitch 10 Hz.

**Worker :**

1. Pool : un `visited` buffer réutilisé (memset 0 via `buffer.fill` si dispo, sinon writeu8 par nœud visité en unwind), table `parent` recycled (`table.clear`).
2. Ne pas baisser `MAX_BFS_NODES` dans le même PR (changement de reachability = ticket design).
3. Test : même seed, même origine/destination → même path avant/après. Banc existant `beachhead` / `boat own-tile` reste vert. Optionnel : 100 `findSeaPath` d’affilée, pas de croissance de mémoire mesurable si le runner le permet.
4. Fichiers : `Navy.luau`, `tests/simulate.luau`.

**Contraintes :** déterminisme du path. Ne pas mixer avec N22 (warships O(carriers × boats)) ni N25 (`MAX_BOATS`). Server-only. `MAX_BFS_NODES` inchangé.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert |
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
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 | aura → N35 ; mer → **N37** |
| N17 | Humains éliminés occupent le cap | P2 | ouvert |
| N18 | Heap AimFront ≠ ChantierB / BoatFront | P2 | ouvert |
| N19 | Embargo allié + tribus auto-accept | P2 | ouvert |
| N20 | `railIncome` vs `deliveryValue` | P2 | **fait** `stopBonus` ; reste niveau live vs snapshot colis |
| N21 | QuickChat 2-args | P3 | **fait** passe 5 |
| N22 | Warships O(carriers × boats) | P2 | ouvert |
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
| N34 | `areAllied` ignore expiry pacte | P2 | **fait** cette passe |
| N35 | `applyDefenseAura` buffer mort | P2 | ouvert |
| N36 | AimFront figé après premier lancer | P2 | **nouveau** |
| N37 | `findSeaPath` alloc 40k / appel | P2 | **nouveau** (détaché de N16) |

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
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=8.0 p95Changed=8 maxChanged=479 avgTickMs=0.30 p95TickMs=0.45
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **34/34 OK** — tous les écrans se construisent et s’exécutent sans erreur.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass7.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes.
