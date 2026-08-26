# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 6)

Déclencheur : ouverture de la **PR #25** (`cursor/analyse-nocturne-du-codebase-5233`) — areAllied expiry, boat own-tile, inbound removePlayer, specs N24–N25.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-04c7`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #25**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#25.

Ligne parallèle **feel** (#19/#21/#22/#24) : ne pas merger sur cette branche sans rebase. Les numéros N26+ feel (SAM, embargo land, RequestSnapshot, seq) ne sont **pas** les N26–N27 de ce rapport.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`.

La PR #25 a bien fermé le P0 paix fantôme (`areAllied` + expiry), le malus bateau sur cote déjà prise, et la purge inbound embargo/proposition. Cette passe a **corrigé ce que #25 a manqué** — encore de l’autorité / comptabilité, pas de l’équilibrage :

| Bug | Gravité | Statut |
|---|---|---|
| `retreatAttack` ne marquait que le premier front du couple (terre + `isBeachhead`) | **P0 combat / autorité** | **corrigé** |
| `removePlayer` laissait les **marques de cible inbound** (slot recyclé) | **P2 anti-exploit** | **corrigé** |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : voir section 7.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#25 + retraite couple + marque inbound.
- Client : **34/34 OK** (inchangé).
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #25

**À merger** (areAllied expiry + boat own-tile + inbound embargo/request + specs N24–N25), sous réserve que cette passe 6 parte avec : **une retraite ne rappelait qu’un front sur deux**, et **une marque d’alliance survivait au recyclage de slot**.

Points encore vrais après #25 :

| Claim #25 | Réalité après passe 6 |
|---|---|
| `areAllied` honore `tick < expiry` (`true` legacy vivant) | confirmé |
| Boat own-tile = restitution 100 % | confirmé |
| Inbound embargo / request / extension | confirmé ; **`targetMarks` inbound fuyait encore** — corrigé ici |
| Diplomatie `targetSlot == self` | confirmé |
| `accept` emprunte `returnCommittedTroops` | confirmé ; **ne rappelle toujours pas les transports** (N10.8) |
| N24 findSeaPath GC / N25 checkVictory | specs only, inchangé |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |

`init.server.luau` est **exclu du bundle**. `tryAnnex` qui `return` sur voisin océan est **volontaire** : poche enclavée = terre uniquement (accès mer = pas d’annexion auto). Ne pas « corriger » en `continue`.

PR #24 (feel, `a9d9`) a déjà livré la retraite-couple sur la ligne feel. Ne pas la merger par-dessus #16/#25 sans rebase.

On peut fermer #17, #18, #20, #23 et #25 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| Retraite partielle terre + tête de pont | `GameState.retreatAttack` | BoatFront isole `isBeachhead`. Un `return` au premier match laissait l’autre se battre ; le 2e geste disait « déjà ordonnée ». Cap `MAX_ACTIVE_ATTACKS=2` rend le cas fréquent. |
| Marque de cible héritée au recycle | `GameState.removePlayer` | Même classe que l’embargo inbound de #25. `Diplomacy.step` tourne **avant** `state:step()` / `removePlayer` : le GC des disparus rate le tick d’élimination, et un `JoinRequest` recycle le slot avant le step suivant. |

**Non modifié (volontaire) :** N1–N25. N10.8 (bateau allié = retraite 25 % vs refund 100 %). Cap beachheads (N5). `tryAnnex` océan = enclave terrestre. `SAM_INTERCEPT_CHANCE=1` après `apply` (N1 / feel N26).

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + `guard < 80`).
- **Têtes de pont** = `BoatFront.seedBeachhead` : frontier = **voisins encore à la cible**, flag `isBeachhead`. `launchAttack` gare les beachheads avant fusion.
- **Retraite** = couple `(attacker, target)` : tous les fronts + `Navy.retreatBoats`.
- **Pacte vivant** = `areAllied` : deux sens **et** `tick < expiry` (ou `true` legacy tests).
- **Comptabilité fronts** = `GameState.returnCommittedTroops` (pacte, défenseur disparu). Retraite terre = `RETREAT_LOSS`. Cote déjà nôtre = 100 %.
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients` (N26).
- **DataStore** : inchangé (N6). Éliminés : toujours pas de `Persistence.record` si `players[slot]` nil à `endMatch` (N14 / N25).
- **Require** : DAG. Pas de cycle. `ChantierB`/`BoatFront`/`AimFront` dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N25 restent ouverts** sauf N19 partiel. Ci-dessous les **nouveaux** tickets.

---

### ISSUE-N26 — Notify / Sfx globaux encore `FireAllClients`

**Priorité :** P2 perf / bande passante lobby.

**Problème :** `flushEvents` envoie `notify` et `sfx` **sans `only`** via `FireAllClients`. `Place.MaxPlayers` peut dépasser 8 (file d’attente menu). Le hot path StateDelta est déjà bridé à `fireDeployed` ; les alertes nuke / alliance / SAM taxent encore tout le salon, y compris les joueurs au menu.

**Pourquoi 20K CCU :** 1 700 shards × (MaxPlayers − 8) clients menu × 10 Hz d’événements globaux. Ce n’est pas le tick sim, c’est la facture réplication Roblox. Distinct de N2 (payload stats complet aux déployés).

**Worker :**

1. Pour les événements **sans `only`** : `fireDeployed(notify, …)` / `fireDeployed(sfx, …)` par défaut.
2. Exception produit : départ nuke / fin de partie — garder `FireAllClients` **ou** documenter que le menu n’entend plus la sirène. Trancher dans le PR, pas les deux.
3. Ne pas toucher `MatchUpdate` 1 Hz (volontaire pour le lobby) ni `RosterUpdate`.
4. Banc : client 34/34 inchangé. Pas de test `init.server` dans le bundle : extraire `flushEvents(state, fireDeployed, fireAll)` testable **ou** documenter un test Studio (un joueur menu ne reçoit pas `allianceFormed`).
5. Fichiers : `init.server.luau` uniquement.

**Contraintes :** pas de RemoteFunction. Ne pas mixer avec N2 (delta stats) ni N14 (firehose des éliminés). **N26 hardening ≠ N26 feel (SAM 100 %).**

---

### ISSUE-N27 — Pops de frontier périmés brûlent `guard` sans capturer

**Priorité :** P2 combat / debit.

**Problème :** `ChantierB.stepAttacks` fait `guard += 1` **avant** de vérifier `owner == atk.target`. Jusqu’à 80 pops/tick peuvent produire **zéro** capture si le tas contient des tuiles déjà prises (beachhead voisin, nuke, autre front). `numTiles` n’est décrémenté qu’après un vrai `attackLogic`.

**Pourquoi 20K CCU :** late-game, fronts larges + têtes de pont : le debit réel tombe sous `attackTilesPerTick` alors que le tick consomme déjà son budget. Ce n’est pas N11 (`MAX_TILES_PER_TICK` mort) : ici le cap vivant `guard < 80` est mal compté.

**Worker :**

1. Incrémenter `guard` seulement sur une tuile encore ennemie, **ou** ne pas compter les `continue` stale. Garder un cap dur (ex. 160 pops bruts) pour éviter une boucle infinie sur un tas pourri.
2. Test : frontier de 80 tuiles déjà à l’attaquant + 1 tuile ennemie en fond de tas → la tuile ennemie doit être tentée dans le tick.
3. Fichiers : `ChantierB.luau` (`install` `stepAttacks`), `tests/simulate.luau`.
4. Banc 6000 ticks : `p95TickMs` ne doit pas monter.

**Contraintes :** ne pas changer `attackTilesPerTick` ni câbler `MAX_TILES_PER_TICK` (N11). Pas d’équilibrage. Ne pas mixer avec N16 (buffer defense) ni N21 (`tryAnnex` alloc).

---

## 5b. N1–N25 encore ouverts (passes 2–5)

| ID | Titre | Prio | Note passe 6 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + `SAM_INTERCEPT_CHANCE` 0.55→1 ; clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` **jamais** `FireServer` côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | park `isBeachhead` → hors cap land ; retraite couple corrigée ici |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | refund + retraite `RETREAT_LOSS` alignés ; le reste du corps est mort |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | inchangé |
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

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `Diplomacy.accept` ne rappelle pas les bateaux ; le tick Navy suivant taxe 25 %. `resolveLanding` allié = 100 % si le check mid-transit est contourné.

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
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
  factions : 18
  metrics : ticks=6000 avgChanged=11.4 p95Changed=12 maxChanged=479 avgTickMs=0.37 p95TickMs=0.65
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe6.log`

---

## 8. Instructions worker (si reprise)

- Vérité runtime d’équilibrage = `ChantierB.apply(Config)` après `SystemsBootstrap.install()`, PAS `Config.luau` seul.
- Combat vivant = patches ChantierB, pas `GameState.stepAttacks` (sauf `returnCommittedTroops` et `retreatAttack`, partagés).
- `areAllied` = deux sens **et** expiry. Ne pas revenir à un test `~= nil`.
- `retreatAttack` = **tous** les fronts du couple. Ne pas revenir à un `return` au premier match.
- Cote déjà nôtre ≠ retraite. Allié en mer = toujours retraite 25 % (N10.8).
- Purge inbound d’un slot = **dans `removePlayer`**, pas seulement dans `Diplomacy.step` (ordre : Diplomacy puis `state:step`).
- `tryAnnex` océan = enclave terrestre, pas un bug.
- Ne pas casser le client 34/34. `init.server` / `Persistence` exclus du bundle : extraire un helper testable ou documenter un test Studio.
- Ligne feel (#19/#22/#24) : rebase sur cette passe avant cherry-pick, sinon perte de retraite-couple hardening + marque inbound (feel a déjà la retraite-couple, pas forcément la marque).
