# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 7)

Déclencheur : ouverture de la **PR #27** (`cursor/analyse-nocturne-du-codebase-04c7`) — retraite couple, marque inbound, specs N26–N27.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-1dbe`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #27**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#27.

Ligne parallèle **feel** (#19/#21/#22/#24/#26) : ne pas merger sur cette branche sans rebase. Les numéros N28+ feel (RequestSnapshot, seq, stub seedBeachhead…) ne sont **pas** les N28–N29 de ce rapport.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`.

La PR #27 a bien fermé le P0 retraite-couple et la marque inbound. Cette passe a **corrigé ce que #27 a manqué** — encore de l’autorité / comptabilité de slot recyclé, pas de l’équilibrage :

| Bug | Gravité | Statut |
|---|---|---|
| `doomWarnedAt` / `doomUnderSince` hérités au recycle de slot (et à un claimSpawn après strip AFK) | **P1 anti-exploit / cadran** | **corrigé** |
| Colis `tradeDeliveries` d’un disparu encaissable par le slot recyclé | **P2 économie** | **corrigé** |
| Tribus ignoraient `BOT_HUMAN_GRACE_DURATION` | **P2 bots / fairness** | **corrigé** |
| Bots lisaient `alliances[]` brut (pacte périmé = 1 tick fantôme, même classe que `areAllied`) | **P2 IA** | **corrigé** |
| `joinCooldown` survivait à `startMatch` | **P3 UX join** | **corrigé** (`init.server`, hors bundle) |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#27 + cadran recycle + colis inbound + grâce humaine / tribus.
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #27

**À merger** (retraite couple + marque inbound + specs N26–N27), sous réserve que cette passe 7 parte avec : **le cadran et les colis fuyaient encore au recycle de slot**, et **les tribus contournaient la grâce humaine**.

Points encore vrais après #27 :

| Claim #27 | Réalité après passe 7 |
|---|---|
| `retreatAttack` marque tous les fronts du couple | confirmé |
| `removePlayer` purge embargo / request / `targetMarks` inbound | confirmé ; **cadran + colis fuyaient encore** — corrigé ici |
| `areAllied` honore `tick < expiry` | confirmé ; **Bots.decideDiplomacy / decideChat lisaient encore la table brute** — corrigé ici |
| N26 notify FireAllClients / N27 guard frontier | specs only, inchangé |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |
| `tryAnnex` océan = enclave terrestre | volontaire, pas un bug |

`init.server.luau` est **exclu du bundle**. Le fix `joinCooldown` n’a donc pas de test headless : relance Studio, spam JoinRequest en fin de round, le déploiement du round suivant doit passer sans attendre 2 s.

PR #26 (feel, `ec34` / suite `4fe1`) ne doit pas être mergée par-dessus #16/#27 sans rebase.

On peut fermer #17, #18, #20, #23, #25 et #27 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| Timers cadran hérités | `GameState.removePlayer`, `GameState.addPlayer`, `ChantierB.stepDoomsday` | Indexés par slot. `Diplomacy.step` / `stepDoomsday` skip `tiles==0` **sans effacer**. Un `JoinRequest` recycle le slot, ou un AFK `stripTerritory` puis `claimSpawn` saigne au premier tick armé. |
| Colis du disparu | `GameState.removePlayer` | `Trade.step` tourne **avant** `stepElimination`. Payload keyed par tuile d’usine + `delivery.slot`. Usine reposée sur la même tuile avec le slot recyclé → `factory.slot == delivery.slot` → or volé. |
| Tribus vs grâce humaine | `Tribes.decideAttack`, `Bots.humanTargetProtected` (export) | Les bots honorent `BOT_HUMAN_GRACE_DURATION` (180 s) + protection tuiles. Les tribus n’avaient que 12 %/décision. Contournement PvE du tutoriel. |
| Bots table brute | `Bots.decideDiplomacy`, `Bots.decideChat` | `Bots.step` **avant** `Diplomacy.step` : un pacte périmé reste dans `alliances[]`. `not allies[other]` bloquait une re-proposition ; `hasAlly = next(allies)` choisissait `help_defend` qui échoue (alliesOnly) et avalait `attack_target`. |
| JoinRequest throttle cross-round | `init.server.startMatch` | `joinCooldown` n’était vidé que sur `PlayerRemoving`. |

**Non modifié (volontaire) :** N1–N27. N10.8. Cap beachheads (N5 : le parking `isBeachhead` **contourne** encore `MAX_ACTIVE_ATTACKS` — c’est le ticket, pas un oubli de cette passe). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après `apply`.

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + `guard < 80`).
- **Têtes de pont** = `BoatFront.seedBeachhead` : frontier = **voisins encore à la cible**, flag `isBeachhead`. `launchAttack` gare les beachheads avant fusion.
- **Retraite** = couple `(attacker, target)` : tous les fronts + `Navy.retreatBoats`.
- **Pacte vivant** = `areAllied` : deux sens **et** `tick < expiry` (ou `true` legacy tests). Bots et tribus doivent passer par là, pas `alliances[]`.
- **Comptabilité fronts** = `GameState.returnCommittedTroops` (pacte, défenseur disparu). Retraite terre = `RETREAT_LOSS`. Cote déjà nôtre = 100 %.
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients` (N26).
- **DataStore** : inchangé (N6). Éliminés : toujours pas de `Persistence.record` si `players[slot]` nil à `endMatch` (N14 / N25).
- **Require** : DAG. Pas de cycle. `Tribes` → `Bots` (export `humanTargetProtected` seulement). `ChantierB`/`BoatFront`/`AimFront` dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N27 restent ouverts** sauf N19 partiel. Ci-dessous les **nouveaux** tickets.

---

### ISSUE-N28 — Transports inbound / retraite par propriétaire de tuile, pas par couple

**Priorité :** P2 combat / comptabilité navale.

**Problème :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetFaction`. Conséquences :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers, ou `removePlayer(B)` qui neutralise).
2. `removePlayer` rembourse les **fronts terre** inbound (`returnCommittedTroops`) mais laisse les transports du disparu / vers le disparu naviguer. Ils `seedBeachhead` sur NEUTRAL — expansion gratuite, troupes jamais restituées.
3. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

**Pourquoi 20K CCU :** disconnect / recycle de slot est le chemin chaud du lobby 8 humains. Un transport fantôme qui colonise la côte neutre d’un disparu fausse la comptabilité du shard et le cap `MAX_ACTIVE_ATTACKS` (beachhead hors cap, N5). Distinct de N10.8 (malus allié en mer).

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport, **ou** rappeler tous les transports non-retirants de `slot` dont `targetTile` appartenait à `targetOwner` au launch.
2. Dans `removePlayer(defender)` : pour chaque transport ennemi vers une tuile qui était au disparu — soit `beginRetreat` (remboursement, pas `BOAT_RETREAT_LOSS` si la côte est déjà neutre — aligner sur own-tile 100 %), soit `returnCommittedTroops` équivalent bateau. Trancher **un** comportement dans le PR, pas les deux.
3. Transports **du** disparu : déjà `table.remove` (troupes perdues, cohérent avec les fronts de l’attaquant qui part). Ne pas changer.
4. Test : invasion en mer vs B → `removePlayer(B)` → `retreatAttack(A, B)` **ou** assert automatique : pas de `seedBeachhead` vs NEUTRAL, troupes de A restituées. Second test : `retreatAttack` après flip de la côte à un tiers.
5. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`, éventuellement `step`/`resolveLanding`), `GameState.removePlayer`, `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8 (allié mid-transit = 25 %). Ne pas câbler `BOAT_LANDING_BONUS` (N22). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).**

---

### ISSUE-N29 — `seedBeachhead` ne fusionne plus le couple naval

**Priorité :** P2 combat / cap.

**Problème :** `GameState.seedBeachhead` de base fusionnait `(attacker, target)`. `BoatFront.install` **remplace** la fonction et `table.insert` toujours un nouvel `Attack` `isBeachhead`. Deux débarquements vs le même défenseur = deux fronts, pools de troupes séparés, deux consommations de debit `guard < 80`. Combiné à N5 (parking hors cap land), un joueur peut tenir 2 beachheads + 1 terre = 3 offensives alors que `MAX_ACTIVE_ATTACKS_PER_PLAYER = 2`.

**Pourquoi 20K CCU :** late-game invasions multiples. Ce n’est pas N11 (`MAX_TILES_PER_TICK` mort) ni N27 (pops stale) : ici le **nombre de tas** explose, chacun avec son `while guard < 80`.

**Worker :**

1. Confirmer le contrat OpenFront : **un** front naval par couple `(attacker, target)`, distinct du front terre. Si oui : dans `BoatFront.seedBeachhead`, trouver un `isBeachhead` existant du couple, ajouter `troops`, enfiler les nouveaux voisins, return. Si le tas est vide après enqueue, refund comme aujourd’hui.
2. Si le produit **veut** les griffes multiples : documenter dans Config, et **compter** les beachheads dans le cap (fermer N5 dans le même PR). Pas les deux à la fois.
3. Test : deux `seedBeachhead` même couple → `#attacks == 1` et `troops` somme **ou** (si multi-prong assumé) `launchAttack` refuse au-delà du cap y compris parked.
4. Fichiers : `BoatFront.luau`, éventuellement `GameState.launchAttack` / wrapper parking, `tests/simulate.luau`.

**Contraintes :** ne pas fusionner beachhead avec front terre (régression BoatFront / aim). Ne pas changer `attackTilesPerTick`. Ne pas mixer avec N28 (bateaux inbound). **N29 hardening ≠ N29 feel (seq avant apply).**

---

## 5b. N1–N27 encore ouverts (passes 2–6)

| ID | Titre | Prio | Note passe 7 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + `SAM_INTERCEPT_CHANCE` 0.55→1 ; clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` **jamais** `FireServer` côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | park `isBeachhead` → hors cap land ; **2 beachheads parked + 1 terre = 3** — voir N29 |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | refund + retraite `RETREAT_LOSS` alignés ; le reste du corps est mort |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | timers slot maintenant purgés ; le scan rot est toujours O(tuiles) |
| N10 | Divers P3 | P3 | donations gold sans plafond ; `pendingMode` last-writer ; README SmoothTerrain |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | debit = `attackTilesPerTick` × speed, `guard<80` |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 observé) | P1 | `Bots.spawnAll` wrap + `Tribes.spawnAll(6)` hors budget |
| N13 | Parité ère / cost factor `attackLogic` | P2 | doctrines oui ; `Eras.accumulate` et `sizeAttackFactors` coût **non** |
| N14 | Humains éliminés occupent cap + firehose + **pas de Persistence.record** | P2 | **précisé en N25** |
| N15 | Heap AimFront ≠ ChantierB | P2 | `terrainMag` vs `TERRAIN_COST/2` |
| N16 | `attackLogic` scanne tous les DEF | P1 | buffer `state.defense` non lu |
| N17 | Embargo allié + tribus auto-accept | P2 | design |
| N18 | `railIncome` HUD ≠ `deliveryValue` | P2 | snapshot niveau OK ; `links`/`stopBonus` absents du HUD |
| N19 | QuickChat 2-args target vs sequence | P3 | **partiel** : slot hors 1..48 refusé ; 2-args petit N + `needsTarget` = encore une cible |
| N20 | `findSeaPath` + warships O(carriers×boats) | P2 | **N24 isole le GC BFS** ; N20 garde nested loop + spawn ports |
| N21 | `tryAnnex` alloc `visited`/`queue` par capture | P2 | océan = abort **volontaire** (enclave terrestre) |
| N22 | `BOAT_LANDING_BONUS` jamais lu | P2 | specs only |
| N23 | Trade / Navy gold ignorent doctrine, ère, `HUMAN_GOLD_MULTIPLIER` | P2 | specs only |
| N24 | `findSeaPath` pool BFS | P2 | specs only. **≠ N24 feel (notify fireDeployed).** |
| N25 | `checkVictory` / `stepElimination` → Persistence + cap | P2 | specs only. `Diplomacy.step` **avant** `state:step` : tout GC « disparu » dans `Diplomacy.step` rate l’élimination du même tick — les purges doivent vivre dans `removePlayer`. |
| N26 | Notify / Sfx globaux `FireAllClients` | P2 | specs only. **≠ N26 feel (SAM 100 %).** |
| N27 | Pops de frontier périmés brûlent `guard` | P2 | specs only. Ne pas compter les `continue` stale ; garder un cap brut (ex. 160). |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu (reset à `startMatch` suffit) ; disconnect mid-match = `Persistence.record(..., false)` 0 XP ; `Navy.syncCarriers` bascule le porte-avions au capteur de la base le même tick.

---

## 6. Drift Config → `ChantierB.apply` (extrait, inchangé)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | oui (formule custom) |
| `MAX_TILES_PER_TICK` | 400→écrit 56 | 56 | **non** |
| `RETREAT_LOSS` | 0.25 | 0.25 | oui |
| `BOAT_RETREAT_LOSS` | 0.25 | 0.25 | oui (retraite vraie seulement) |
| `BOAT_LANDING_BONUS` | 1.35 | 1.35 | **non** (N22) |
| `SAM_INTERCEPT_CHANCE` | 0.55 | **1** | oui (100 % si à portée) |
| `CITY_LEVELS[1].popCapBonus` | 900 | 50000 | oui |
| `FRONT_TILES_PER_CONTACT` | — | 2.4 | **non** |
| `MAX_BOATS_PER_PLAYER` | 6 | 6 (`or 3` mort) | oui |

---

## 7. Preuve tests

```
./tests/run.sh  → exit 0
Serveur : Tous les invariants tiennent.
  intentions : sequence, idempotence, rate limit OK
  intentions : schema doctrine/nuke/diplomatie, ended, file OK
  intentions : QuickChat cooldown honore
  intentions : ratio borne, QuickChat slot hors catalogue refuse
  intentions : diplomatie vers soi refusee
  refund defenseur : removePlayer rend les troupes
  refund orphelin : stepAttacks rend les troupes
  beachhead : frontier voisins, pas de remboursement
  aim reinforce : un seul front apres deux lancers
  colis snapshot : niveau au depart honore
  accept expire : proposition perimee refusee
  viewFor expiry : proposition perimee masquee
  areAllied expiry : pacte perime refuse avant step
  boat own-tile : restitution integrale, pas de malus
  removePlayer inbound : embargo, proposition et marque purges
  retraite couple : tous les fronts du meme adversaire marques
  doomsday recycle : timers cadran purges au recycle de slot
  doomsday AFK clear : timers effaces pendant strip / spawn
  trade inbound : colis purges au recycle de slot
  human grace : BOT_HUMAN_GRACE_DURATION et protection tuiles
  tribe grace : tribu n'attaque pas l'humain pendant la grace
  bot expiry ally : areAllied + request ignorent un pacte perime en table
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
  factions : 18
  metrics : ticks=6000 avgChanged=11.4 p95Changed=12 maxChanged=479 avgTickMs=0.37 p95TickMs=0.65
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe7.log`

---

## 8. Instructions worker (si reprise)

- Vérité runtime d’équilibrage = `ChantierB.apply(Config)` après `SystemsBootstrap.install()`, PAS `Config.luau` seul.
- Combat vivant = patches ChantierB, pas `GameState.stepAttacks` (sauf `returnCommittedTroops` et `retreatAttack`, partagés).
- `areAllied` = deux sens **et** expiry. Ne pas revenir à un test `~= nil`. Bots / chat / tribus : **jamais** `alliances[slot][other]` comme vérité.
- `retreatAttack` = **tous** les fronts du couple. Ne pas revenir à un `return` au premier match.
- Cote déjà nôtre ≠ retraite. Allié en mer = toujours retraite 25 % (N10.8).
- Purge inbound d’un slot = **dans `removePlayer`**, pas seulement dans `Diplomacy.step` (ordre : Diplomacy puis `state:step`). Inclut désormais cadran + colis, pas seulement diplo.
- `tryAnnex` océan = enclave terrestre, pas un bug.
- Grâce humaine = `Bots.humanTargetProtected` (bots **et** tribus). Ne pas dupliquer une 2e courbe.
- Ne pas casser le client 34/34. `init.server` / `Persistence` exclus du bundle : extraire un helper testable ou documenter un test Studio.
- Ligne feel (#19/#22/#24/#26) : rebase sur cette passe avant cherry-pick, sinon perte cadran/colis/tribus grace.
