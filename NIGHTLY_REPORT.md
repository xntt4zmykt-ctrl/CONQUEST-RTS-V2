# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 13)

Déclencheur : ouverture de la **PR #38** (`cursor/analyse-nocturne-du-codebase-fd0b`) — request croisée, cadran/colis, convois inbound, specs N49–N51.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-d425`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#38.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion et slot cible diplomatique sont dérivés serveur.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #38 (passe 12) : claims vérifiés.** `requestIsLive` (inverse périmée enfilée, inverse live → pacte), cadran/colis purgés au recycle, convois `kind==2` inbound coulés avant `setOwner`. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #38 a documenté (N49, N50, N51)**. Recettes = hardening N28 restant / N33 / fd1e option B, pas une nouvelle sémantique. Feel n’avait toujours pas `targetSlot` au launch, `findSpawn` anti-splash, ni convoi vs PORT détruit au combat.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #38

| Claim #38 | Réalité à l’ouverture |
|---|---|
| `Diplomacy.request` inverse périmée (N46) | Oui. `requestIsLive` ; inverse live → `accept` ; périmée → clear + enfiler. `accept` / `areAllied` non touchés. |
| Cadran / colis recycle (N47) | Oui. `doomWarnedAt` / `doomUnderSince` / `tradeDeliveries` purgés avant héritage. `stepDoomsday` inchangé. |
| Convoi inbound `kind==2` (N48) | Oui. Coulé avant `setOwner`, pas d’or, tiers conservé. |
| Specs N49–N51 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #37, feel jusqu’à #38. **#38 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←#20←#23←#25←#27←#30←#31←#33←#35←#37) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N49–N51 du rapport #38.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `retreatBoats` ignore un flip de côte (N49) | `Navy.luau`, `SystemsBootstrap.luau` | `launchInvasion` pose `targetSlot` (faction visée). `retreatBoats` filtre ce champ (fallback `owner[targetTile]` si absent). Le wrap `retreatAttack` appelle **toujours** `retreatBoats` : un 2e geste rappelle les transports tardifs. **N10.8 / inbound 100 % N43 non touchés.** |
| `findSpawn` ignore splash / fallout (N50) | `GameState.luau` | **C1+C2.** C1 : refuse un centre dont une ogive en vol a `toIndex(floor(tx),floor(ty))` à distance `missile.radius` ou `NUKE_STATS[kind].radius` (+ `SPAWN_RADIUS`). C2 : refuse `fallout[index] > tick` dans le disque. Contrat B (N44) inchangé — on n’annule pas la frappe. MIRV bus `radius=0` ignoré (N54). |
| Convoi vs PORT détruit au combat (N51) | `Navy.luau` | Recette fd1e / PR #37 option B. Dans `Navy.step`, avant resolveLanding : `kind==TRADE` et `buildings[targetTile]` n’est plus un PORT → `table.remove`. Capture (`transferBuilding`) : le PORT existe encore → le convoi continue. Pas d’or, pas de malus vendeur. N48 recycle inchangé. Pas de `destSlot` (≠ N49 `targetSlot`). |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), warships grille (N22), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), `claimSpawn` splash (N52), débarquement auto vs flip (N53), MIRV bus vs spawn (N54), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK.

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (seq obligatoire en playing, apply immédiat) → tick :
  Bots.step → Navy.step (syncCarriers si dirty ; coule TRADE si PORT absent) → Nukes.step → Trade.step → Diplomacy.step → GameState.step → replicate(fireDeployed)
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
- **Inbound `removePlayer`** = diplo + transports `kind==1` (100 %, lit **`owner[targetTile]`** même après N49) + missiles contrat B + cadran/colis + convois `kind==2` (coulés), **avant** `setOwner`. Bateaux/missiles **du** partant détruits.
- **`Diplomacy.request`** = inverse live → acceptation ; inverse périmée → clear + enfiler.
- **Retraite navale** = `targetSlot` au launch ; wrap 2e geste rappelle les tardifs.
- **`findSpawn`** = disque neutre **et** hors crater ogive / fallout chaud. `claimSpawn` (clic humain) **pas encore** (N52).
- **Réplication :** StateDelta / UnitSnapshot / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. `targetSlot` bateau **non** répliqué (snapshot = id/slot/x/y/troops/kind). MatchUpdate / roster → tous (menu). Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready (nouveaux, N52–N54)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N22, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N32/N34/N36–N51 = faits. N27 = doc only.

---

### ISSUE-N52 — `claimSpawn` ignore splash / fallout (feel)

**Priorité :** P3 nucléaire / spawn humain. Suite de N50 (C1+C2 livrés dans `findSpawn` / `autoPlacePending` seulement).

**Problème :** un humain en `awaitingSpawn` clique une tuile. `ChantierB.claimSpawn` accepte toute terre neutre (ou le plus proche dans r=6) **sans** lire `state.missiles` ni `state.fallout`. `placeDisk` pose la capitale dans le crater. N50 a fermé le chemin RNG / timeout ; le clic contourne.

**Pourquoi 20K CCU :** JoinRequest + clic spawn en fin de partie nucléaire. Moins chaud que N50 (il faut un humain, pas un bot auto-placé) mais c’est le seul chemin spawn encore naïf.

**Worker :**

1. Extraire un helper `isSpawnSafe(state, center)` (C1 ogive + C2 fallout, même formule que `findSpawn` : rayon `missile.radius` ou `NUKE_STATS[kind].radius`, + `SPAWN_RADIUS` ; `fallout[index] > tick` dans le disque). L’appeler depuis `findSpawn` **et** `claimSpawn` (si le `best` n’est pas sûr → refuser ou chercher plus loin, pas poser quand même).
2. Ne **pas** annuler une frappe tiers (N44 / N50). Pas de refund. MIRV bus `radius=0` = N54, pas ici.
3. Test : missile ATOM en vol sur une tuile neutre, `claimSpawn(slot, tile)` refuse (ou décale hors rayon). `findSpawn splash` / `findSpawn fallout` / `nuke third-party` restent verts.
4. Fichiers : `ChantierB.luau` (`claimSpawn` / éventuellement helper partagé), `GameState.findSpawn`, `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Ne pas poser un disque à cheval sur un crater « pour dépanner ». Ne pas toucher `stripTerritory`. Recette = N50 C1+C2 étendu au clic. **N52 feel ≠ N33 feel historique (`BOAT_LANDING_BONUS` mort).**

---

### ISSUE-N53 — Débarquement auto sur une côte flippée (feel)

**Priorité :** P3 combat naval. Suite de N49 : `retreatBoats` honore `targetSlot`, mais `Navy.step` **n’en tient pas compte**.

**Problème :** si le joueur **ne** retraite **pas**, un transport dont `targetSlot == B` continue vers `targetTile` même si `owner[targetTile]` est devenu C (neutre / tiers). À l’arrivée : `resolveLanding` lit le proprio courant, `setOwner` + `seedBeachhead(A, C, …)`. Conséquence : une invasion ordonnée contre B ouvre un pont contre C sans second clic. Distinct de N49 (geste retraite) et de N10.8 (allié en mer → retraite 25 %).

Le wrap 2e geste (N49) ne couvre que le cas « le joueur reclique retraite ». Un AFK / bot qui a lancé l’invasion ne reclique pas.

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même transit. Sans garde, un shard 18 factions accumule des têtes de pont « accidentelles » hors cap mental du joueur.

**Worker — choisir UNE option :**

1. **(A)** `Navy.step` : si `kind==TRANSPORT` et `not retreating` et `typeof(targetSlot)=="number"` et `owner[targetTile] ~= targetSlot` et `owner ~= boat.slot` → `beginRetreat` (même classe que allié / océan). **(B)** documenter « on débarque chez qui tient la plage » (comportement actuel) + test d’assert volontaire. **(C)** retarget `targetSlot` au proprio courant (mutation d’intention serveur — déconseillé).
2. Si A : fallback identique N49 (pas de `targetSlot` → lire `owner`). Ne pas maluser une côte déjà nôtre (own-tile 100 % inchangé). Ne pas recâbler inbound `removePlayer` (lit encore `owner[targetTile]`, volontaire).
3. Test A : invasion A→B, flip côte vers C, **sans** `retreatAttack`, `Navy.step` jusqu’à arrivée. Assert : transport en retraite / coulé, **pas** de `seedBeachhead` vs C. Test B : pont vs C + commentaire. `boat retreat flip` (N49) et `boat inbound` (N43) restent verts.
4. Fichiers : `Navy.luau` (`Navy.step` seulement si A), `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N33). Ne pas merger `targetSlot` convoi (N51 n’en a pas). **N53 feel ≠ N28 feel historique (RequestSnapshot).**

---

### ISSUE-N54 — `findSpawn` ignore un MIRV bus en vol (feel)

**Priorité :** P3 nucléaire / spawn. Trou restant de N50 C1.

**Problème :** C1 refuse seulement `blast > 0`. Un MIRV a `NUKE_STATS[3].radius = 0` (le bus ne cratère pas ; les ogives portent `missile.radius` après `MIRV_SEPARATION`). Tant que le bus n’a pas scindé, `findSpawn` / (futur N52) `claimSpawn` peuvent poser une capitale dans le `spread` de la cible. Après séparation, N50 C1 s’applique aux ogives — trop tard si le disque est déjà posé.

**Pourquoi 20K CCU :** une frappe MIRV late-game + recycle de slot / clic spawn pendant le vol du bus. Plus rare que ATOM/H (N50) mais le MIRV est *l’*arme de fin de partie.

**Worker :**

1. Si `kind == MIRV` et `not missile.warhead` : traiter le rayon d’exclusion comme `stats.spread` (ou `warheadRadius + spread`, documenter le choix) autour de `(floor(tx), floor(ty))`. Ogives déjà scindées : N50 C1 inchangé (`missile.radius`).
2. Ne **pas** annuler le MIRV (N44). Pas de refund. Ne pas inventer un crater bus (radius reste 0 à la détonation).
3. Test : MIRV en vol (`progress < MIRV_SEPARATION`) visé sur une poche neutre, `findSpawn` refuse. Après mock séparation (insérer des ogives `warhead=true`), C1 ogive continue de refuser. `nuke third-party` inchangé.
4. Fichiers : `GameState.findSpawn` (et le helper N52 s’il existe), `tests/simulate.luau`. `Nukes.luau` seulement si on lit `spread` via une fonction déjà exportée — **pas** de `require Nukes` depuis GameState.

**Contraintes :** pas de RemoteFunction. Rayon lu depuis `NUKE_STATS` / `missile.radius` / `spread`, pas une constante magique. Ne pas casser N50 C1 ATOM/H. **N54 feel ≠ N26 feel historique (SAM).**

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
| N49 | `retreatBoats` / `targetSlot` après flip | P2 | **fait** cette passe (port hardening N28 restant) |
| N50 | `findSpawn` splash / fallout | P3 | **fait** cette passe (C1+C2 ; MIRV bus → N54) |
| N51 | Convoi vs PORT détruit au combat | P3 | **fait** cette passe (port fd1e / PR #37) |
| N52 | `claimSpawn` splash / fallout | P3 | **nouveau** (N50 n’a couvert que `findSpawn`) |
| N53 | Débarquement auto vs côte flippée | P3 | **nouveau** (`Navy.step` ignore `targetSlot`) |
| N54 | MIRV bus vs `findSpawn` | P3 | **nouveau** (N50 C1 `blast>0` rate radius=0) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 `NIGHTLY_REPORT.md` historique.

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
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=11.3 p95Changed=45 maxChanged=747 avgTickMs=0.36 p95TickMs=1.19
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **34/34 OK** — tous les écrans se construisent et s’exécutent sans erreur. N49–N51 sont server-only : banc client inchangé.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass13.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState` (snapshot `settledHumans` seulement). `bunkersBySlot` est un champ d’état, pas un module. N49 n’ajoute **pas** de require. N50 n’ajoute **pas** de `require Nukes` depuis `GameState`. N51 n’ajoute **pas** de `require Navy` depuis GameState (la garde vit dans `Navy.step`).

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.
