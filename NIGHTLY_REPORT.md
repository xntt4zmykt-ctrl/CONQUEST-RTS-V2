# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 14)

Déclencheur : ouverture de la **PR #41** (`cursor/analyse-nocturne-du-codebase-d425`) — targetSlot retraite, findSpawn splash, convoi vs PORT, specs N52–N54.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-df65`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#41.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion et slot cible diplomatique sont dérivés serveur.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #41 (passe 13) : claims vérifiés.** `launchInvasion` pose `targetSlot` ; `retreatBoats` filtre l’intention (2e geste wrap) ; `findSpawn` C1 ogive + C2 fallout ; `Navy.step` coule un `kind==2` si le PORT d’arrivée n’existe plus (capture = continue). Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #41 a documenté (N52, N53, N54)**. Recettes du rapport #41, pas une nouvelle sémantique. Feel n’avait toujours pas `claimSpawn` anti-splash, retraite auto vs flip, ni exclusion MIRV bus.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #41

| Claim #41 | Réalité à l’ouverture |
|---|---|
| `targetSlot` au launch / `retreatBoats` (N49) | Oui. Wrap 2e geste rappelle les tardifs. inbound 100 % lit encore `owner[targetTile]`. |
| `findSpawn` C1+C2 (N50) | Oui. Ogive `blast>0` + fallout chaud. MIRV bus `radius=0` ignoré — **N54 ici**. |
| Convoi vs PORT détruit (N51) | Oui. `Navy.step` option B, capture = continue, pas d’or. |
| Specs N52–N54 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #40, feel jusqu’à #41, plus #39 visuelle. **#41 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←#20←#23←#25←#27←#30←#31←#33←#35←#37←#40) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N52–N54 du rapport #41.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `claimSpawn` ignore splash / fallout (N52) | `GameState.luau`, `ChantierB.luau` | Helper `isSpawnSafe` (C1 ogive + C2 fallout, + N54 bus). `findSpawn` et `claimSpawn` l’appellent. Clic dans un crater → r=6 cherche plus loin, **jamais** poser quand même. Contrat B inchangé. Isolation voisinage **pas** ici (N55). |
| Débarquement auto vs côte flippée (N53) | `Navy.luau` | **Option A.** `Navy.step` : `kind==TRANSPORT` et `targetSlot` numérique et `owner[targetTile] ~= targetSlot` (et pas own-tile) → `beginRetreat`. Sans `targetSlot` : fallback N49 (pas de retraite auto). inbound `removePlayer` non recâblé. N10.8 inchangé. |
| `findSpawn` ignore un MIRV bus (N54) | `GameState.luau` (`isSpawnSafe`) | Bus `kind==MIRV` et `not warhead` : exclusion = `spread + warheadRadius` autour de `(floor(tx), floor(ty))`. Choix documenté : `spread` seul raterait le crater d’une ogive en bord de dispersion. Ogives scindées : N50 C1 (`missile.radius`). Pas de `require Nukes`. Pas d’annulation du bus. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), warships grille (N22), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), isolation `claimSpawn` (N55), snapshot `retreating` (N56), SAM scan O(B) (N57), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK.

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (seq obligatoire en playing, apply immédiat) → tick :
  Bots.step → Navy.step (syncCarriers si dirty ; coule TRADE si PORT absent ;
              TRANSPORT retraite si owner ~= targetSlot) → Nukes.step → Trade.step
              → Diplomacy.step → GameState.step → replicate(fireDeployed)
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
- **Inbound `removePlayer`** = diplo + transports `kind==1` (100 %, lit **`owner[targetTile]`** même après N49/N53) + missiles contrat B + cadran/colis + convois `kind==2` (coulés), **avant** `setOwner`. Bateaux/missiles **du** partant détruits.
- **`Diplomacy.request`** = inverse live → acceptation ; inverse périmée → clear + enfiler.
- **Retraite navale** = `targetSlot` au launch ; wrap 2e geste **et** `Navy.step` auto si flip (N53).
- **Spawn** = `isSpawnSafe` (C1+C2+N54) pour RNG **et** clic. Isolation disque `claimSpawn` **pas encore** (N55).
- **Réplication :** StateDelta / UnitSnapshot / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. `targetSlot` / `retreating` bateau **non** répliqués (snapshot = id/slot/x/y/troops/kind) — N56. MatchUpdate / roster → tous (menu). Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready (nouveaux, N55–N57)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N22, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N32/N34/N36–N54 = faits. N27 = doc only.

---

### ISSUE-N55 — `claimSpawn` accepte un disque collé à un empire (feel)

**Priorité :** P3 spawn humain. Suite de N52 (splash/fallout seulement).

**Problème :** `findSpawn` exige que le carré `SPAWN_RADIUS+3` soit **entièrement NEUTRAL**. `claimSpawn` (même après N52) accepte **une** tuile terre+neutre+`isSpawnSafe`. `placeDisk` ne peint que les tuiles encore neutres : un clic en lisière d’un empire pose une capitale 1 tuile collée au voisin. Contourne la règle d’isolation du spawn RNG / timeout (`autoPlacePending` → `findSpawn`).

**Pourquoi 20K CCU :** JoinRequest late-game, clic spawn contre un blob 30 % de la carte. Moins chaud que N52 (il faut un humain et une lisière) mais c’est le dernier trou du chemin clic.

**Worker :**

1. Dans `claimSpawn`, après `isClaimable` (N52), exiger le même test d’isolation que `findSpawn` (carré `check = SPAWN_RADIUS+3` tout NEUTRAL, ou extraire `isSpawnIsolated(state, center)`). Si le `best` n’est pas isolé → chercher plus loin dans r=6, **pas** poser un disque partiel.
2. Ne **pas** relâcher N52 (`isSpawnSafe`). Ne pas toucher `stripTerritory` / `placeDisk` (il doit rester « ne peint que NEUTRAL » pour ne pas voler une tuile).
3. Test : occupier peint tout sauf une tuile terre adjacente à son territoire ; `claimSpawn` refuse (ou décale hors contact). `claimSpawn splash` / `findSpawn splash` restent verts.
4. Fichiers : `ChantierB.luau` (`claimSpawn`), éventuellement `GameState.isSpawnIsolated`, `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Ne pas poser à cheval « pour dépanner ». Recette = isolation `findSpawn` étendue au clic. **N55 feel ≠ N33 feel historique (`BOAT_LANDING_BONUS` mort).**

---

### ISSUE-N56 — `UnitSnapshot` omet `retreating` / `targetSlot` (feel)

**Priorité :** P3 réplication. Suite de N49/N53 : le serveur retraite, le client n’en sait rien.

**Problème :** `init.server` envoie `{ id, slot, x, y, troops, kind }` à 10 Hz. Après N53, un transport dont la côte a flippé **rebrousse** (`retreating`, `path` = maison) mais le client interpolé continue vers l’ancienne `target` visuelle (dernière x,y) et joue le splash d’arrivée quand l’id disparaît — identique à un débarquement. `Types.BoatSnapshot` n’a ni `retreating` ni `targetSlot`. Overlay ne peut pas afficher « retour » vs « invasion ».

**Pourquoi 20K CCU :** 10 Hz × ~24 bateaux/shard est déjà le budget. Deux bool/number de plus restent cheap. Sans eux, le HUD **mente** après une retraite auto : le joueur croit encore envahir C. Anti-exploit : pas d’autorité client, mais confusion → re-clics retraite / invasions doublons.

**Worker — choisir UNE option :**

1. **(A)** Ajouter `retreating: boolean?` (minimum) et optionnellement `targetSlot` au snapshot + `Types.BoatSnapshot`. Overlay : teinte / wake distinct si `retreating`. **(B)** documenter « le client interpolé suffit, pas de flag » + test d’assert volontaire sur le payload serveur seulement (pas de visuel).
2. Si A : ne **pas** envoyer `path` / `homeTile` (fuite d’intention + bandwidth). Pas de RemoteFunction. Ne pas changer le rate 10 Hz.
3. Test A : invasion A→B, flip vers C, `Navy.step` une fois, inspecter le payload que `init.server` construirait (extraire un helper `snapshotBoats(state)` testable — `init.server` hors bundle). Assert `retreating == true`. Banc client : Overlay accepte le champ extra (34/34). `boat auto-retreat flip` / `boat retreat flip` restent verts.
4. Fichiers : `init.server.luau` (ou helper), `Types.luau`, `Overlay.luau` si A visuel, `tests/simulate.luau`, éventuellement `tests/client.luau`.

**Contraintes :** pas de logique critique client. Ne pas répliquer `path`. **N56 feel ≠ N28 feel historique (`RequestSnapshot` mort).**

---

### ISSUE-N57 — `tryIntercept` scanne tout `buildings` par missile / tick (feel)

**Priorité :** P2 perf nucléaire. Distinct de N42 (`bunkersBySlot` combat terrestre).

**Problème :** `Nukes.tryIntercept` fait `for index, building in state.buildings` **pour chaque missile encore en vol**, chaque tick. Un MIRV scindé = 6 ogives × O(B). Late-game Classique : ~10 silos + ~19 SAM + usines/villes (90+) → O(M×B) par tick pendant une salve. SAM déjà rate-limités par cooldown, mais le **scan** n’est pas indexé. `bunkersBySlot` a montré la recette (N42) ; les SAM n’ont pas d’équivalent `samsBySlot`.

**Pourquoi 20K CCU :** un shard 18 factions / 600 s de jeu sort déjà 52 explosions dans le banc. Une salve MIRV + H concurrente sur un shard saturé fait spiker `p95TickMs` au moment où le combat terrestre `guard<80` tourne aussi. Ce n’est pas de l’autorité, c’est du budget tick.

**Worker :**

1. Index `samsBySlot[slot][tile] = true` (même pattern que `bunkersBySlot`) : `placeBuilding` / `destroyBuilding` / `transferBuilding`. `tryIntercept` itère les SAM des camps **non** tireur / non alliés, pas le hash `buildings`.
2. Ne **pas** changer `SAM_INTERCEPT_CHANCE` / range / cooldown (N26 clos). Ne pas indexer les silos ici. Pas de `require Nukes` depuis GameState si l’index vit sur l’état.
3. Test : poser 3 SAM + 1 silo, lancer ATOM, compter que l’index contient les 3 tuiles SAM et plus le silo. `transferBuilding` d’un SAM met à jour le camp. `nuke third-party` / MIRV split restent verts.
4. Fichiers : `GameState.luau` (index), `Nukes.luau` (`tryIntercept`), `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Recette N42, pas un spatial hash (N22 warships reste ouvert). **N57 feel ≠ N31 feel historique (scan bunkers — déjà N42).**

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
| N46 | `Diplomacy.request` inverse périmée | P2 | **fait** passe 12 |
| N47 | Cadran / colis recycle feel | P2 | **fait** passe 12 |
| N48 | Convoi marchand inbound | P2 | **fait** passe 12 |
| N49 | `retreatBoats` / `targetSlot` après flip | P2 | **fait** passe 13 |
| N50 | `findSpawn` splash / fallout | P3 | **fait** passe 13 (C1+C2) |
| N51 | Convoi vs PORT détruit au combat | P3 | **fait** passe 13 |
| N52 | `claimSpawn` splash / fallout | P3 | **fait** cette passe |
| N53 | Débarquement auto vs côte flippée | P3 | **fait** cette passe (option A) |
| N54 | MIRV bus vs `findSpawn` | P3 | **fait** cette passe (`spread + warheadRadius`) |
| N55 | `claimSpawn` isolation disque | P3 | **nouveau** (N52 n’a couvert que splash) |
| N56 | Snapshot bateau `retreating` | P3 | **nouveau** (N53 serveur, HUD aveugle) |
| N57 | SAM scan O(B) / missile | P2 | **nouveau** (recette N42, pas N22) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 `NIGHTLY_REPORT.md` historique.

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
boat retreat flip : targetSlot honore, 2e geste rappele le tardif
findSpawn splash : crater d'ogive refuse
findSpawn fallout : disque chaud refuse
trade port-detruit : convoi coule, pas d'or
trade port-capture : PORT transfere, convoi survit
claimSpawn splash : crater d'ogive refuse
boat auto-retreat flip : retraite auto, pas de pont vs le tiers
findSpawn MIRV bus : spread du bus refuse, ogive C1 intacte
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=6.3 p95Changed=7 maxChanged=479 avgTickMs=0.25 p95TickMs=0.42
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **34/34 OK** — tous les écrans se construisent et s’exécutent sans erreur. N52–N54 sont server-only : banc client inchangé.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass14.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState` (snapshot `settledHumans` seulement). `bunkersBySlot` est un champ d’état, pas un module. N52 n’ajoute **pas** de require (`isSpawnSafe` vit sur GameState). N53 n’ajoute **pas** de require (garde dans `Navy.step`). N54 n’ajoute **pas** de `require Nukes` depuis GameState (lit `Config.NUKE_STATS` / `missile.warhead`).

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.
