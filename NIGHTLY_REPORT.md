# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 8)

Déclencheur : ouverture de la **PR #30** (`cursor/analyse-nocturne-du-codebase-1dbe`) — cadran/colis recycle, grâce tribus, specs N28–N29.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-915c`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #30**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#30.

Ligne parallèle **feel** (#19/#21/#22/#24/#26/#28/#29) : ne pas merger sur cette branche sans rebase. Les numéros N28+ feel (RequestSnapshot, seq, AimFront, findSeaPath pool…) ne sont **pas** les N28–N31 de ce rapport.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`.

La PR #30 a bien fermé le P1 cadran/colis et la grâce tribus. Cette passe a **corrigé ce que #30 a manqué** — encore de l’autorité / comptabilité de slot recyclé, pas de l’équilibrage :

| Bug | Gravité | Statut |
|---|---|---|
| Transports inbound d’un disparu → `seedBeachhead` vs NEUTRAL / slot recyclé, troupes jamais restituées | **P1 combat / comptabilité navale** | **corrigé** (partie inbound de N28) |
| `Diplomacy.request` auto-acceptait une proposition inverse **périmée** et bloquait la nouvelle demande | **P2 diplomatie / IA** | **corrigé** |
| `retreatBoats` filtre `owner[targetTile]` courant, pas la faction visée au launch | **P2 marine** | **ouvert** (reste de N28) |
| `seedBeachhead` insert toujours un nouvel `Attack` | **P2 cap** | **ouvert** (N29) |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#30 + transports inbound + request croisée.
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #30

**À merger** (cadran/colis recycle + grâce tribus + bots `areAllied` + specs N28–N29), sous réserve que cette passe 8 parte avec : **les transports inbound fuyaient encore au recycle de slot**, et **une proposition inverse périmée bloquait `Diplomacy.request`**.

Points encore vrais après #30 :

| Claim #30 | Réalité après passe 8 |
|---|---|
| `doomWarnedAt` / `doomUnderSince` purgés au recycle | confirmé |
| Colis `tradeDeliveries` du disparu purgés | confirmé |
| Tribus honorent `Bots.humanTargetProtected` | confirmé |
| Bots `decideDiplomacy` / `decideChat` passent par `areAllied` | confirmé |
| `joinCooldown` vidé à `startMatch` | confirmé (`init.server`, hors bundle) |
| N28 bateaux inbound | **inbound `removePlayer` fermé ici** ; retraite après flip de côte reste ouverte |
| N29 `seedBeachhead` no-merge | specs only, inchangé |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N10.8 bateau allié = retraite 25 % | inchangé |
| `tryAnnex` océan = enclave terrestre | volontaire, pas un bug |

`init.server.luau` est **exclu du bundle**. Le fix `joinCooldown` n’a toujours pas de test headless.

PR #29 (feel, `6be5`) ne doit pas être mergée par-dessus #16/#30 sans rebase.

On peut fermer #17, #18, #20, #23, #25, #27 et #30 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| Transports inbound | `GameState.removePlayer` | Navy.step tourne **avant** `stepElimination`. Un transport vers la côte du disparu voyait `destOwner==NEUTRAL` (pas allié, pas own-tile) → `setOwner` + `seedBeachhead` vs NEUTRAL. Disconnect / JoinRequest entre deux ticks : le slot recyclé spawnait sur cette côte et se faisait envahir par des troupes jamais restituées à A. Contrôle **avant** `setOwner` (pas de `targetSlot` sur le bateau). Restitution 100 %, pas `BOAT_RETREAT_LOSS`. Transports **du** disparu : toujours `table.remove` (attaquant qui part). |
| Proposition inverse périmée | `Diplomacy.request` | `Bots.step` **avant** `Diplomacy.step`. `theirs[from]` vrai même si expiry dépassée → `accept` refuse « expirée » et **n’envoie pas** la nouvelle demande. Même classe que `areAllied` / `viewFor` (1 tick fantôme ; 12 ticks pour une tribu). Une demande inverse **vivante** signe toujours le pacte. |

**Non modifié (volontaire) :** N1–N27, N29, reste de N28 (retraite après flip). N10.8. Cap beachheads (N5). `tryAnnex` océan. `SAM_INTERCEPT_CHANCE=1` après apply. Pas de `require(Navy)` depuis GameState (cycle).

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
- **Proposition vivante** = `requestIsLive` (`tick < expiry`). Croisement = accept **seulement** si encore live.
- **Comptabilité fronts** = `GameState.returnCommittedTroops` (pacte, défenseur disparu). Retraite terre = `RETREAT_LOSS`. Cote déjà nôtre = 100 %. **Transports inbound d’un disparu = 100 %** (cette passe).
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients` (N26).
- **DataStore** : inchangé (N6). Éliminés : toujours pas de `Persistence.record` si `players[slot]` nil à `endMatch` (N14 / N25).
- **Require** : DAG. Pas de cycle. `Tribes` → `Bots` (export `humanTargetProtected` seulement). `Navy` → `GameState` (unidirectionnel). `ChantierB`/`BoatFront`/`AimFront` dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N27 restent ouverts** sauf N19 partiel. N28 est **partiel** (inbound fermé). Ci-dessous les **nouveaux** tickets + le reste de N28.

---

### ISSUE-N28 — `retreatBoats` / `retreatAttack` après flip de côte (reste)

**Priorité :** P2 combat / comptabilité navale. **Partiel :** inbound `removePlayer` **fermé** en passe 8.

**Problème restant :** `Navy.retreatBoats(state, slot, targetOwner)` filtre `buffer.readu8(owner, boat.targetTile) == targetOwner`. Un bateau n’a pas de `targetSlot`. Conséquences encore vraies :

1. `retreatAttack(A, B)` ne rappelle **pas** une invasion si la côte a déjà changé de main (neutre, tiers).
2. Le wrapper `SystemsBootstrap.retreatAttack` appelle `retreatBoats` même si `origRetreat` a dit « déjà ordonnée » : un 2e geste peut encore rappeler des bateaux tardifs (parfois voulu) avec le message « front terrestre et N transport(s) ».

**Pourquoi 20K CCU :** late-game invasions + flip de côte le même tick que la retraite. Distinct de N10.8 (malus allié en mer) et du fix inbound (déjà livré).

**Worker :**

1. Stocker `targetSlot` (faction visée au launch) sur le transport.
2. `retreatBoats` filtre `boat.targetSlot == targetOwner` (fallback `owner[targetTile]` si le champ manque).
3. Test : invasion en mer vs B → flip de la côte à un tiers → `retreatAttack(A, B)` rappelle le transport. Second test : wrapper 2e geste, trancher si les bateaux tardifs doivent partir.
4. Fichiers : `Navy.luau` (`launchInvasion`, `retreatBoats`), éventuellement `SystemsBootstrap.retreatAttack`, `tests/simulate.luau`.

**Contraintes :** pas de RemoteFunction. Ne pas toucher N10.8. Ne pas câbler `BOAT_LANDING_BONUS` (N22). Ne pas réintroduire un malus sur inbound `removePlayer` (100 % déjà livré). Pas d’équilibrage. **N28 hardening ≠ N28 feel (RequestSnapshot mort).**

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

**Contraintes :** ne pas fusionner beachhead avec front terre (régression BoatFront / aim). Ne pas changer `attackTilesPerTick`. Ne pas mixer avec N28 (bateaux inbound / targetSlot). **N29 hardening ≠ N29 feel (seq avant apply).**

---

### ISSUE-N30 — Missile inbound vs spawn recyclé

**Priorité :** P2 nucléaire / fairness.

**Problème :** `removePlayer` retire les missiles **du** disparu, pas ceux **vers** ses tuiles. Un `JoinRequest` entre deux ticks peut `addPlayer` sur (ou près de) l’ancien capital. `Nukes.step` explose ensuite sur le nouvel occupant, qui n’a pas payé la frappe et n’a pas eu de fenêtre SAM.

**Pourquoi 20K CCU :** disconnect mid-nuke est le chemin chaud du lobby 8 humains. Distinct de N26 (notify FireAllClients) et du fix transports (troupes commises vs ogive déjà payée).

**Worker :**

1. Trancher **un** contrat : (A) le missile continue (territoire, pas joueur — documenter) ; (B) `removePlayer` retarget NEUTRAL / annule si la tuile visée appartenait au disparu ; (C) `addPlayer` refuse un spawn dans un rayon de missile en vol.
2. Si B : identifier la cible par `toIndex(floor(tx), floor(ty))` **avant** `setOwner`. Ne pas retirer une frappe qui vise déjà un tiers.
3. Test : silo A → capital B → `removePlayer(B)` → `addPlayer` recycle → `Nukes.step` jusqu’à impact. Assert selon le contrat choisi (pas de pertes sur l’héritier, **ou** commentaire + assert volontaire).
4. Fichiers : `GameState.removePlayer` et/ou `Nukes.step` / `addPlayer`, `tests/simulate.luau`.

**Contraintes :** ne pas rembourser l’or du tireur (ogive déjà dépensée, sauf si le contrat B annule **avant** départ — ce n’est pas le cas ici). Ne pas toucher SAM / MIRV split. Pas de RemoteFunction.

---

### ISSUE-N31 — Pooler `findSeaPath` (visite 40k)

**Priorité :** P2 perf marine. Recette déjà livrée sur la ligne **feel** (N37, PR #29) : ne pas cherry-pick le wrap AimFront avec.

**Problème :** `Navy.findSeaPath` alloue `buffer.create(TILE_COUNT)` + `parent{}` + `queue` **par** appel. `launchInvasion`, `beginRetreat`, `spawnTradeShips` (jusqu’à `MAX_TRADE_SHIPS` × paires de ports). 40 000 tuiles, 10 Hz, late-game ports.

**Pourquoi 20K CCU :** GC stutter sur le shard, pas un monde unique. Distinct de N20 (nested warship loop) et N24 (même sujet GC BFS, specs only depuis passe 6 — **cette issue la remplace comme ticket actionnable**).

**Worker :**

1. Port de la recette feel N37 : buffers `visitBuf` / `parent` / `queue` réutilisés. `buffer.fill(buf, 0, 0)` = **offset + value** (pas `fill(buf, 0)`).
2. Ne **pas** porter le wrap AimFront (feel N36) dans le même PR.
3. Test : `findSeaPath` A→B deux fois de suite (pas de visite fantôme). Invasion + retraite + trade ship sur le banc existant.
4. Fichiers : `Navy.luau`, `tests/simulate.luau`.

**Contraintes :** `MAX_BFS_NODES` inchangé. Pas d’équilibrage portée. Signature `buffer.fill` Luau 0.640+. **N31 hardening ≠ N31 feel (viewFor HUD / stub seedBeachhead selon la passe feel).**

---

## 5b. N1–N27 encore ouverts (passes 2–7)

| ID | Titre | Prio | Note passe 8 |
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
| N20 | `findSeaPath` + warships O(carriers×boats) | P2 | **N31 isole le pool BFS** ; N20 garde nested loop + spawn ports |
| N21 | `tryAnnex` alloc `visited`/`queue` par capture | P2 | océan = abort **volontaire** (enclave terrestre) |
| N22 | `BOAT_LANDING_BONUS` jamais lu | P2 | specs only |
| N23 | Trade / Navy gold ignorent doctrine, ère, `HUMAN_GOLD_MULTIPLIER` | P2 | specs only |
| N24 | `findSeaPath` pool BFS | P2 | **remplacé par N31** comme ticket actionnable. **≠ N24 feel (notify fireDeployed).** |
| N25 | `checkVictory` / `stepElimination` → Persistence + cap | P2 | specs only. `Diplomacy.step` **avant** `state:step` : tout GC « disparu » dans `Diplomacy.step` rate l’élimination du même tick — les purges doivent vivre dans `removePlayer`. |
| N26 | Notify / Sfx globaux `FireAllClients` | P2 | specs only. **≠ N26 feel (SAM 100 %).** |
| N27 | Pops de frontier périmés brûlent `guard` | P2 | specs only. Ne pas compter les `continue` stale ; garder un cap brut (ex. 160). |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

P3 notés, pas tickets : `IntentValidator.Context.matchId` jamais lu (reset à `startMatch` suffit) ; disconnect mid-match = `Persistence.record(..., false)` 0 XP ; `Navy.syncCarriers` bascule le porte-avions au capteur de la base le même tick ; convois marchands vers un port détruit occupent `MAX_TRADE_SHIPS` jusqu’à l’arrivée (no-op `resolveTrade`) ; wrap `launchAttack` n’applique `AimFront.focus` que si le couple n’existait pas (renfort = pas de re-visée — feel N36).

---

## 6. Drift Config → `ChantierB.apply` (extrait, inchangé)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | oui (formule custom) |
| `MAX_TILES_PER_TICK` | 400→écrit 56 | 56 | **non** |
| `RETREAT_LOSS` | 0.25 | 0.25 | oui |
| `BOAT_RETREAT_LOSS` | 0.25 | 0.25 | oui (retraite vraie seulement ; inbound disparu = 100 %) |
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
  boat inbound : transports restitues, pas de tete de pont vs disparu
  boat attacker leave : transports de l'attaquant detruits
  request stale reverse : proposition perimee ignoree, nouvelle demande enfilee
  request live reverse : croisement vivant signe le pacte
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
  factions : 18
  metrics : ticks=6000 avgChanged=11.4 p95Changed=12 maxChanged=479 avgTickMs=0.37 p95TickMs=0.67
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe8.log`

---

## 8. Instructions worker (si reprise)

- Vérité runtime d’équilibrage = `ChantierB.apply(Config)` après `SystemsBootstrap.install()`, PAS `Config.luau` seul.
- Combat vivant = patches ChantierB, pas `GameState.stepAttacks` (sauf `returnCommittedTroops` et `retreatAttack`, partagés).
- `areAllied` = deux sens **et** expiry. Ne pas revenir à un test `~= nil`. Bots / chat / tribus : **jamais** `alliances[slot][other]` comme vérité.
- Croisement diplomatique = accept **seulement** si `requestIsLive`. Une inverse périmée s’efface et on enfile une nouvelle demande.
- `retreatAttack` = **tous** les fronts du couple. Ne pas revenir à un `return` au premier match.
- Cote déjà nôtre ≠ retraite. Allié en mer = toujours retraite 25 % (N10.8). Inbound disparu = 100 % (comme front terre).
- Purge inbound d’un slot = **dans `removePlayer`**, pas seulement dans `Diplomacy.step` (ordre : Diplomacy puis `state:step`). Inclut cadran + colis + **transports** (avant `setOwner`).
- Transports : `kind == 1`. Ne pas `require(Navy)` depuis GameState (cycle).
- `tryAnnex` océan = enclave terrestre, pas un bug.
- Grâce humaine = `Bots.humanTargetProtected` (bots **et** tribus). Ne pas dupliquer une 2e courbe.
- Ne pas casser le client 34/34. `init.server` / `Persistence` exclus du bundle : extraire un helper testable ou documenter un test Studio.
- Ligne feel (#19/#22/#24/#26/#28/#29) : rebase sur cette passe avant cherry-pick, sinon perte transports inbound / request croisée.
