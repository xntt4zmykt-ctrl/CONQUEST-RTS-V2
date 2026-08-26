# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 15)

Déclencheur : ouverture de la **PR #42** (`cursor/analyse-nocturne-du-codebase-df65`) — claimSpawn splash, retraite auto vs flip, MIRV bus, specs N55–N57.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-2157`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#42.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes, `targetSlot` invasion, `retreating` et slot cible diplomatique sont dérivés serveur.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #42 (passe 14) : claims vérifiés.** `isSpawnSafe` partagé `findSpawn`/`claimSpawn` ; `Navy.step` retraite si `owner[targetTile] ~= targetSlot` ; MIRV bus exclu via `spread + warheadRadius`. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Cette passe a **livré ce que #42 a documenté (N55, N56, N57)**. Recettes du rapport #42, pas une nouvelle sémantique. Feel n’avait toujours pas isolation clic, HUD retraite, ni index SAM.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #42

| Claim #42 | Réalité à l’ouverture |
|---|---|
| `isSpawnSafe` partagé findSpawn/claimSpawn (N52) | Oui. Clic dans un crater → r=6, jamais poser. Isolation **pas** encore — **N55 ici**. |
| `Navy.step` auto-retraite vs flip (N53) | Oui. Option A, fallback sans `targetSlot` = N49. Snapshot **sans** `retreating` — **N56 ici**. |
| MIRV bus `spread + warheadRadius` (N54) | Oui. Pas de `require Nukes`. Ogives C1 inchangées. |
| Specs N55–N57 | **Corrigés ici.** |

PRs ouvertes au moment de la revue : #16 P0, hardening jusqu’à #40, feel jusqu’à #42, plus #39 visuelle. **#42 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←#20←#23←#25←#27←#30←#31←#33←#35←#37←#40) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

Feel #19 inchangé. Pas de réinvention : N55–N57 du rapport #42.

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `claimSpawn` accepte un disque collé (N55) | `GameState.luau`, `ChantierB.luau` | Helper `isSpawnIsolated` (carré `SPAWN_RADIUS+3` tout NEUTRAL). `findSpawn` et `claimSpawn` l’appellent. Clic en lisière → r=6 cherche plus loin, **jamais** poser un disque partiel. `placeDisk` inchangé (ne peint que NEUTRAL). N52 splash conservé. |
| `UnitSnapshot` omet `retreating` (N56) | `GameState.luau` (`snapshotBoats`), `init.server.luau`, `Types.luau`, `Overlay.luau` | **Option A.** Payload `{ id, slot, x, y, troops, kind, retreating }`. Pas de `path` / `homeTile`. Overlay : teinte froide + **pas de splash d’arrivée** si retraite (sinon le client confond avec un débarquement). Rate 10 Hz inchangé. |
| `tryIntercept` scanne tout `buildings` (N57) | `GameState.luau` (`samsBySlot`), `Nukes.luau` | Index `samsBySlot[slot][tile]` (recette `bunkersBySlot`) : pose / capture / destroy / `removePlayer`. `tryIntercept` itère les SAM des camps non tireur / non alliés. `SAM_INTERCEPT_CHANCE` / range / CD inchangés (N26 clos). Pas d’index silos. |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore merge additif (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront vs ChantierB (N18), embargo allié (N19), warships grille (N22), MAX_BOATS (N25), RequestSnapshot client (N28), landing bonus mort (N33), hover client spawn (N58), `samsOf` bots (N59), `stepCooldowns` O(B) (N60), bateau allié = retraite 25 % (N10.8 design), `stepDoomsday` skip AFK.

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (seq obligatoire en playing, apply immédiat) → tick :
  Bots.step → Navy.step (syncCarriers si dirty ; coule TRADE si PORT absent ;
              TRANSPORT retraite si owner ~= targetSlot) → Nukes.step (tryIntercept via samsBySlot)
              → Trade.step → Diplomacy.step → GameState.step → replicate(fireDeployed, snapshotBoats)
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
- **Posted SAM** = index `samsBySlot` (N57). `tryIntercept` ne scanne plus `buildings`.
- **Inbound `removePlayer`** = diplo + transports `kind==1` (100 %, lit **`owner[targetTile]`** même après N49/N53) + missiles contrat B + cadran/colis + convois `kind==2` (coulés), **avant** `setOwner`. Bateaux/missiles **du** partant détruits. `samsBySlot[slot]` / `bunkersBySlot[slot]` nil.
- **`Diplomacy.request`** = inverse live → acceptation ; inverse périmée → clear + enfiler.
- **Retraite navale** = `targetSlot` au launch ; wrap 2e geste **et** `Navy.step` auto si flip (N53). Snapshot porte `retreating` (N56).
- **Spawn** = `isSpawnSafe` (C1+C2+N54) **et** `isSpawnIsolated` (N55) pour RNG **et** clic.
- **Réplication :** StateDelta / UnitSnapshot (`retreating`) / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. `path` / `homeTile` **non** répliqués. MatchUpdate / roster → tous (menu). Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready (nouveaux, N58–N60)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N19, N22, N25, N28, N33 restent ouverts.** N20/N21/N23/N24/N26/N29–N32/N34–N57 = faits. N27 = doc only.

---

### ISSUE-N58 — Hover client spawn ignore l’isolation (feel)

**Priorité :** P3 UX spawn. Suite de N55 (serveur refuse, HUD encore vert).

**Problème :** `init.client` mode attaque colore `valid = land and owner ~= mySlot`. Après N55, une tuile neutre collée à un empire est **rouge côté serveur** (`claimSpawn` → IntentValidator `"Spawn invalide."`) mais **verte côté curseur**. Le late-joiner spam-clic la lisière, croit à un lag, re-envoie des AttackOrder. Le serveur reste autoritaire ; le client n’a pas le carré `SPAWN_RADIUS+3`.

**Pourquoi 20K CCU :** JoinRequest late-game, 8 humains, carte déjà 30 %+ blob. Ce n’est pas de l’exploit (le serveur refuse) mais de la confusion → re-clics, IntentReject, bruit réseau 10 Hz pendant le spawn. Moins chaud que N55 (autorité) ; c’est le dernier trou **visible** du chemin clic.

**Worker — choisir UNE option :**

1. **(A)** Heuristique client : en `awaitingSpawn` (ex. `tiles==0` / flag roster), `valid` exige le même carré `SPAWN_RADIUS+3` tout `owner==0` **ou** un voisin r=6 isolé. Source = buffer `owner` déjà local. **(B)** HUD copy seulement (« trop près d’un empire ») sans changer le hover. Ne **pas** faire du client la source de vérité : un refus serveur reste possible (splash N52, fallout).
2. Ne pas envoyer `isSpawnIsolated` depuis le serveur (nouveau remote). Pas de RemoteFunction. Ne pas dupliquer `isSpawnSafe` (missiles/fallout) côté client — trop d’état.
3. Test A : Overlay/Effects hover n’est pas dans le banc serveur. Banc client : un `previewTile` avec `valid=false` sur tuile neutre collée ne lève pas. `claimSpawn isolation` / `claimSpawn splash` restent verts. 34/34 (ou 35/35 si nouveau check).
4. Fichiers : `init.client.luau` (bloc hover ~L1060), éventuellement `Effects.luau`, `tests/client.luau`.

**Contraintes :** pas de logique critique client. Recette = hint, pas un second `claimSpawn`. **N58 feel ≠ N28 feel historique (`RequestSnapshot` mort).**

---

### ISSUE-N59 — `Buildings.samsOf` scanne encore tout `buildings` (feel)

**Priorité :** P2 perf nucléaire / bots. Suite de N57 (`tryIntercept` indexé, bots non).

**Problème :** `Nukes.tryIntercept` lit `samsBySlot` (N57). `Buildings.samsOf` fait encore `for index, building in state.buildings` et `Bots.luau` l’appelle **à chaque décision de frappe** pour `coveredBy`. Late-game Classique : ~19 SAM + 90+ bâtiments, 11 bots qui pensent au nuke → O(B) par bot par tick de décision. L’index existe déjà ; `samsOf` ne le lit pas.

**Pourquoi 20K CCU :** le spike nuke n’est plus seulement `tryIntercept` (N57) : c’est aussi 11 bots qui rescannent le hash pour ne pas tirer sous SAM. Un shard 18 factions / ère 5 (4 factions ère 5 dans le banc 6000 ticks) empile décision bot + salve + `guard<80`. Budget tick, pas autorité.

**Worker :**

1. `Buildings.samsOf` itère `state.samsBySlot[slot]` (clés = tuiles), fallback hash si l’index est nil (tests partiels). Ne **pas** changer la sémantique (liste des tuiles SAM de **ce** slot, pas des alliés).
2. Ne pas changer `SAM_RANGE` / chance / cooldown (N26). Ne pas faire viser les SAM alliés. Pas de spatial hash (N22 reste ouvert).
3. Test : 3 SAM + 1 silo déjà posés (N57) ; `samsOf` renvoie 3 tuiles, pas le silo. `samsBySlot` / `nuke third-party` / MIRV restent verts. Invariant 5c déjà en place.
4. Fichiers : `Buildings.luau` (`samsOf`), éventuellement `Bots.luau` (plus d’appel direct au hash), `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Recette N57, pas un nouveau index. **N59 feel ≠ N31 feel historique (scan bunkers — déjà N42).**

---

### ISSUE-N60 — `Buildings.stepCooldowns` O(B) à chaque `Nukes.step` (feel)

**Priorité :** P2 perf nucléaire. Distinct de N57 (ciblage) et N59 (bots).

**Problème :** `Nukes.step` appelle `Buildings.stepCooldowns` qui décrémente `building.cooldown` **sur tout le hash** `buildings`. Seules les batteries SAM portent un cooldown (post-interception). Villes / ports / usines / silos sont visités pour un no-op. Pendant une salve MIRV (6 ogives) le tick nuke fait déjà `tryIntercept` × M ; le cooldown scan O(B) s’ajoute **même sans missile** (appel inconditionnel).

**Pourquoi 20K CCU :** 10 Hz × O(B) (~90–150 bâtiments late-game) pour décrémenter ~0–19 SAM. Cheap en isolation, pas cheap **en plus** du combat `guard<80` + `stepDoomsday` O(TILE_COUNT) (N9 ouvert) + bots N59. C’est le dernier scan `buildings` du chemin nuke par tick.

**Worker — choisir UNE option :**

1. **(A)** N’itérer que `samsBySlot` (toutes factions) : `building.cooldown -= 1` si `> 0`. **(B)** Liste `cooldownsPending` des tuiles SAM encore chaudes, retirée à 0. Ne **pas** changer `SAM_COOLDOWN` (75 après apply). Ne pas tick-er d’autres kinds ici (aucun autre cooldown vivant).
2. Si un futur bâtiment gagne un cooldown, l’ajouter à l’index — pas revenir au scan global « au cas où ».
3. Test : poser un SAM, forcer `cooldown = 3`, `Nukes.step` × 3, assert 0. Un silo / ville `cooldown` reste 0 et n’a pas besoin d’être visité (compteur d’itérations optionnel). `samsBySlot` / intercept chance 1.0 restent verts.
4. Fichiers : `Buildings.luau` (`stepCooldowns`), `Nukes.luau` (appel inchangé), `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Recette N57, pas un spatial hash. **N60 feel ≠ N38 feel historique (`syncCarriers` dirty).**

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
| N52 | `claimSpawn` splash / fallout | P3 | **fait** passe 14 |
| N53 | Débarquement auto vs côte flippée | P3 | **fait** passe 14 (option A) |
| N54 | MIRV bus vs `findSpawn` | P3 | **fait** passe 14 (`spread + warheadRadius`) |
| N55 | `claimSpawn` isolation disque | P3 | **fait** cette passe |
| N56 | Snapshot bateau `retreating` | P3 | **fait** cette passe (option A) |
| N57 | SAM scan O(B) / missile | P2 | **fait** cette passe (`samsBySlot`) |
| N58 | Hover client spawn isolation | P3 | **nouveau** (N55 serveur, curseur encore vert) |
| N59 | `samsOf` / bots scan O(B) | P2 | **nouveau** (N57 indexé, bots non) |
| N60 | `stepCooldowns` O(B) / tick nuke | P2 | **nouveau** (dernier scan buildings du chemin nuke) |

Textes worker-ready N1–N25, N28, N33 : PR #21 / #22 / #24 / #26 / #29 / #32 / #34 / #36 / #38 / #41 / #42 `NIGHTLY_REPORT.md` historique.

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
claimSpawn isolation : lisiere refusee
boat snapshot retreat : retreating=true, pas de path
samsBySlot : pose / transfer / destroy OK
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=6.3 p95Changed=7 maxChanged=479 avgTickMs=0.25 p95TickMs=0.44
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **34/34 OK** — tous les écrans se construisent et s’exécutent sans erreur. Overlay accepte `retreating` (N56) sans nouveau check. N55/N57 sont server-only.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass15.log`

Studio / client Roblox réel : non exercé dans cet environnement (pas de DataModel live).

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes. `Persistence` n’est pas requis par `GameState` (snapshot `settledHumans` seulement). `bunkersBySlot` / `samsBySlot` sont des champs d’état, pas des modules. N55 n’ajoute **pas** de require (`isSpawnIsolated` vit sur GameState). N56 n’ajoute **pas** de require (`snapshotBoats` sur GameState ; Overlay lit le champ extra). N57 n’ajoute **pas** de `require Nukes` depuis GameState (index local ; `tryIntercept` lit `state.samsBySlot`).

Ordre des wraps `launchAttack` : Bootstrap (AimFront) → BoatFront (park `isBeachhead`) → `GameState.launchAttack`.
Wrap `retreatAttack` : Bootstrap appelle `Navy.retreatBoats` **même si** `origRetreat` a dit déjà ordonnée.
