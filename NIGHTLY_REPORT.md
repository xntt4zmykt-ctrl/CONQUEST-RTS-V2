# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 10)

Déclencheur : ouverture de la **PR #32** (`cursor/analyse-nocturne-du-codebase-e541`) — carriers dirty, tryAnnex réparé, seq après apply, settledHumans, specs N41–N42.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-350e`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#32.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes et slot cible sont dérivés serveur.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #32 (passe 9) : claims vérifiés.** `_carriersDirty` NAVAL_BASE, `tryAnnex` BFS depuis voisins défenseur du seed déjà capturé, `lastSequence` seulement si `applyOne` OK, `settledHumans` pour Persistence. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #32 a documenté (N41, N42)**. Option B pour les bunkers : le buffer `defense` n’encode pas le slot, donc Option A (lire u8) aurait donné le bonus à l’ancien proprio après capture.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #32

| Claim #32 | Réalité à l’ouverture |
|---|---|
| `syncCarriers` dirty NAVAL_BASE | Oui. pose / capture / destroy. `table.clear(carrierSeen)`. |
| `tryAnnex` pool + BFS voisins du seed capturé | Oui. Océan abort. Plafond 280. |
| Sequence commitée après apply réussi (N29) | Oui. |
| `settledHumans` Persistence des éliminés (N40) | Oui. Bots ignorés. |
| Specs N41–N42 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, #17/#18/#20/#23/#25/#27/#30/#31 hardening, #19/#21/#22/#24/#26/#28/#29/#32 feel. **#32 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←#20←#23←#25←#27←#30←#31) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N41 et N42 du rapport #32.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `sequence == nil` bypass idempotence (N41) | `IntentValidator.luau`, `Config.luau` | Playing : entier `>= 1` obligatoire. Lobby `SetAttackRatio` / `ChooseDoctrine` : nil OK. `ALLOW_UNSEQUENCED_INTENTS` défaut false. Un client modifié ne rejoue plus Attack/Build/Boat dans la fenêtre 20/s sans numéro. Client officiel déjà séquencé : banc client inchangé. |
| `attackLogic` scan O(B) par tuile (N42) | `ChantierB.luau`, `GameState.luau` | `bunkersBySlot[slot][tile]` maintenu à pose / destroy / transfer / removePlayer. Combat itère 0–8 bunkers du défenseur, plus le hash ~90–200. Capture : l’index suit le camp (le buffer u8 ne le peut pas). `DEFENSE_POST_*` / rayon / `guard < 80` inchangés. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), warships grille (N22), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), `applyDefenseAura` écritures (N45), bateau allié = retraite 25 % (N10.8 design).

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
- **Posted bunker** = index `bunkersBySlot`, pas le hash `buildings` ni le buffer `defense` (falloff sans slot).
- **Réplication :** StateDelta / UnitSnapshot / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. MatchUpdate / roster → tous (menu). Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready (nouveaux, N43–N45)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N22, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29/N30/N32/N34/N36–N42 = faits. N27 = doc only. N31+N35 fermés par N42 (posted) ; N35 restant = écritures buffer → **N45**.

---

### ISSUE-N43 — Transports inbound non restitués dans `removePlayer` (feel)

**Priorité :** P2 comptabilité marine. Déjà livré sur hardening 915c / PR #31 ; **absent de la ligne feel**.

**Problème :** `removePlayer` détruit les bateaux `boat.slot == slot` (le partant) puis `setOwner` → NEUTRAL. Les transports **ennemis** en route vers ses côtes survivent. Au tick suivant `Navy.step` voit `destOwner == NEUTRAL` (terre), n’enclenche pas la retraite, et `resolveLanding` pose une tête de pont gratuite sur un empire vide.

Hardening 915c restitue 100 % des `kind == 1` inbound **avant** `setOwner`, sans `require Navy`.

**Pourquoi 20K CCU :** 1 700 shards. Un kick / une élimination au moment d’un débarquement crée une tête de pont hors `MAX_ACTIVE_ATTACKS` (BoatFront gare seulement au cap, N5). Troupes « nées » d’un joueur disparu faussent `troops` vs tuiles.

**Worker :**

1. Dans `GameState.removePlayer`, **avant** la boucle `setOwner` → NEUTRAL, parcourir `self.boats` à l’envers. Si `kind == 1` et `slot ~= departing` et `buffer.readu8(owner, targetTile) == departing` : `players[boat.slot].troops += boat.troops` (100 %, pas `BOAT_RETREAT_LOSS`), `table.remove`. Pas de `require Navy`.
2. Les bateaux du partant restent détruits sans restitution (plus de `PlayerState`).
3. Test : A envahit une côte de B ; `removePlayer(B)` ; troupes de A = avant + cargo ; 0 transport A en mer ; aucune beachhead `isBeachhead` A→ex-B. Banc 6000 ticks vert.
4. Fichiers : `GameState.luau`, `tests/simulate.luau`. Ne pas toucher `Navy.step` / `resolveLanding` dans le même PR.

**Contraintes :** server-authoritative. Feel apply immédiat inchangé. Ne pas mixer avec N33 (`BOAT_LANDING_BONUS`) ni N10.8 (allié = retraite 25 %). Recette = 915c, pas une nouvelle sémantique.

---

### ISSUE-N44 — Missiles inbound vs slot recyclé (feel)

**Priorité :** P2 anti-grief / spawn. Déjà livré sur hardening c68a (contrat B, pas de refund) ; **absent de la ligne feel**.

**Problème :** `removePlayer` jette `missiles[i].slot == slot` (tirs du partant) mais **pas** les ogives en vol vers ses tuiles. `Nukes.step` explose sur `tx, ty` sans re-vérifier le propriétaire. `addPlayer` recycle le slot ; `findSpawn` peut poser le suivant dans le rayon d’un MIRV encore en vol.

Hardening c68a : annulation inbound **avant** `setOwner`, `toIndex(floor(tx), floor(ty))`, pas de refund, tirs vers un **tiers** conservés.

**Pourquoi 20K CCU :** 8 humains / shard, déconnexions fréquentes. Nuke lancé → victime kick → spawn du suivant dans le splash = wipe hors intention.

**Worker :**

1. Porter la recette c68a, ne pas inventer. Dans `removePlayer`, **avant** `setOwner` : pour chaque missile dont l’épicentre tombe sur une tuile `owner == departing`, `table.remove` (pas de refund `NUKE_STATS`). Conserver les missiles du partant (déjà filtrés par `slot == departing`) et ceux qui visent un autre camp.
2. Ne pas changer SAM / chance / range / CD / `SPAWN_NUKE_IMMUNITY`.
3. Test : silo A → capitale B ; `removePlayer(B)` avant impact ; nouveau spawn B2 survit ; un missile A→C (tiers) reste en vol. Banc client inchangé.
4. Fichiers : `GameState.luau` (et `Nukes.luau` seulement si l’index tuile n’est pas dérivable de `tx, ty`). `tests/simulate.luau`.

**Contraintes :** server-only. Feel prep=0 inchangé. Ne pas mixer avec N9 (`stepDoomsday`) ni N45. Recette = c68a, pas une nouvelle sémantique.

---

### ISSUE-N45 — `applyDefenseAura` écrit un buffer que plus personne ne lit

**Priorité :** P3 perf pose/destroy. Suite de N35 après N42.

**Problème :** `placeBuilding` / `destroyBuilding` DEFENSE appellent encore `applyDefenseAura` : disque `DEFENSE_RADIUS=30` → jusqu’à 3721 `readu8`+`writeu8` par pose/destroy. Après `ChantierB.install()`, `GameState.tileCost` (seul lecteur) est **remplacé** par `attackLogic`. Le buffer `defense` n’est lu nulle part en prod. N42 a fermé le combat ; les écritures restent.

**Pourquoi 20K CCU :** pas la hot path tick, mais un humain qui pose 8 bunkers = ~30k writes synchrones dans l’intent (apply immédiat). Hitch perceptible sur shard chargé. Mémoire 40 960 octets mortes par match.

**Worker — choisir UNE option :**

**Option A :** supprimer les appels `applyDefenseAura` et, plus tard, le buffer. Garder la fonction un tick pour le `tileCost` mort (tests hors install). Documenter.

**Option B :** restaurer `ChantierB` `tileCost` pour **additionner** posted (index) et falloff buffer — alors les écritures redeviennent vivantes. Change l’éco (coût tuile), pas seulement posted ×5. Interdit dans le même PR que N11 / N18.

3. Test : pose + destroy bunker, 6000 ticks vert. Si A : aucun `buffer.readu8(state.defense)` dans `ChantierB`. Si B : coût d’une tuile sous bunker > tuile nue, capture du bunker ne change pas le falloff (même tuile).
4. Fichiers : `GameState.luau` (appels), éventuellement `ChantierB.luau` si B.

**Contraintes :** ne pas casser N42 (posted = index, pas u8). Server-only. Feel inchangé.

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
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 | **N37+N42 faits** ; écritures → **N45** |
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
| N29 | Seq commitée avant apply | P3 | **fait** passe 9 |
| N30 | Stub `seedBeachhead` faux | P3 | **fait** `error(...)` |
| N31 | Scan bunkers O(B) | P1 | **fait** cette passe (N42) |
| N32 | `viewFor` requests expirées | P3 | **fait** |
| N33 | `BOAT_LANDING_BONUS` mort | P2 | ouvert |
| N34 | `areAllied` ignore expiry pacte | P2 | **fait** passe 7 |
| N35 | `applyDefenseAura` buffer mort (posted) | P2 | **fait** posted=index ; écritures → **N45** |
| N36 | AimFront figé après premier lancer | P2 | **fait** passe 8 |
| N37 | `findSeaPath` alloc 40k / appel | P2 | **fait** passe 8 |
| N38 | `syncCarriers` O(B) / tick | P2 | **fait** passe 9 |
| N39 | `tryAnnex` alloc + BFS mort | P2 | **fait** passe 9 |
| N40 | Éliminés skip `Persistence.record` | P1 | **fait** passe 9 |
| N41 | Sequence `nil` bypass idempotence | P2 | **fait** cette passe |
| N42 | `attackLogic` index bunkers | P1 | **fait** cette passe (ferme N31 + posted N35) |
| N43 | Transports inbound `removePlayer` (feel) | P2 | **nouveau** (port 915c) |
| N44 | Missiles inbound vs slot recyclé | P2 | **nouveau** |
| N45 | `applyDefenseAura` writes mortes | P3 | **nouveau** |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 `NIGHTLY_REPORT.md` historique.

---

## 6. Drift Config → `ChantierB.apply` (extrait)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | formule custom |
| `MAX_TILES_PER_TICK` | 400 | 56 | **non** (`guard<80`) |
| `DEFENSE_RADIUS` | 6 | 30 | index bunkers (N42), pas le buffer (N45) |
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
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=11.3 p95Changed=45 maxChanged=747 avgTickMs=0.37 p95TickMs=1.20
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **34/34 OK** — tous les écrans se construisent et s’exécutent sans erreur. Le client officiel envoie déjà `nextSequence()` : N41 ne le touche pas.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass10.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState` (snapshot `settledHumans` seulement). `bunkersBySlot` est un champ d’état, pas un module.

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead`) → `GameState.launchAttack`.
