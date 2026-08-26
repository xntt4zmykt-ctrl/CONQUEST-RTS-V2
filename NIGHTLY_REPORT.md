# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 5)

Déclencheur : ouverture de la **PR #23** (`cursor/analyse-nocturne-du-codebase-0751`) — refund troupes, viewFor expiry, intents, specs N21–N23.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-5233`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #23**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#23.

Ligne parallèle **feel** (#19/#21/#22) : ne pas merger sur cette branche sans rebase. Les numéros N24+ feel (SAM, embargo land, RequestSnapshot, seq) ne sont **pas** les N24–N25 de ce rapport.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`.

La PR #23 a bien fermé le P0 refund troupes (défenseur disparu), le HUD `viewFor` des propositions périmées, le clamp de ratio, QuickChat slot 99, et JoinRequest `nationId` entier. Cette passe a **corrigé ce que #23 a manqué** — encore de l’autorité / comptabilité, pas de l’équilibrage :

| Bug | Gravité | Statut |
|---|---|---|
| `areAllied` ignorait l’expiry numérique (1 tick de paix fantôme, même classe que `viewFor`) | **P0 diplomatie / anti-exploit** | **corrigé** |
| Transport dont la cote a déjà été prise : malus `BOAT_RETREAT_LOSS` 25 % | **P0 combat / comptabilité** | **corrigé** |
| `removePlayer` laissait embargo / proposition / extension **inbound** (slot recyclé) | **P2 anti-exploit** | **corrigé** |
| Diplomatie `targetSlot == self` occupait la file | **P3 validation** | **corrigé** |
| `isInteger` remote n’excluait pas `inf` | **P3 schema** | **corrigé** (`init.server`, hors bundle) |
| `Diplomacy.accept` refundait hors `returnCommittedTroops` | **P3 DRY** | **corrigé** |
| Combat mort : retraite sans `RETREAT_LOSS` | **P3 code mort** | **aligné** (chemin non installé) |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : **exit 0**.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#23 + areAllied expiry + boat own-tile + inbound removePlayer + diplomatie self.
- Client : **34/34 OK**.
- Metrics 6000 ticks : `avgChanged=11.4 p95Changed=12 maxChanged=479 avgTickMs=0.36 p95TickMs=0.64`.
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #23

**À merger** (refund troupes + specs N21–N23), sous réserve que cette passe 5 parte avec : **un pacte expiré bloquait encore Attack/Boat/Nuke pendant 1 tick**, et **un débarquement sur une côte déjà prise taxait 25 %**.

Points encore vrais après #23 :

| Claim #23 | Réalité après passe 5 |
|---|---|
| `returnCommittedTroops` si défenseur nil | confirmé ; `accept` l’emprunte maintenant aussi |
| `viewFor` masque proposition périmée | confirmé ; **`areAllied` fuyait encore sur l’expiry du pacte** — corrigé ici |
| Ratio clamp enqueue | confirmé |
| QuickChat slot 99 | confirmé (N19 partiel inchangé : 2-args petit N + `needsTarget` = cible) |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N21–N23 specs only | inchangé |

`init.server.luau` est **exclu du bundle** : `isInteger` inf / JoinRequest entier = revue manuelle + tests IntentValidator pour l’enqueue.

PR #22 (feel, `5ba6`) est une **branche divergente**. Ne pas la merger par-dessus #16/#23 sans rebase.

On peut fermer #17, #18, #20 et #23 au profit de celle-ci (sur-ensemble hardening).

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| Paix fantôme 1 tick après expiry | `GameState.areAllied` (`tick < expiry`, `true` reste vivant pour les tests) | `flush` avant `Diplomacy.step`. Attack/Boat/Nuke/dons voyaient encore le pacte. Même garde que `requestIsLive`. |
| HUD alliés périmés | `viewFor` via `areAllied` ; QuickChat / marque alliés | `viewFor` itérait déjà `areAllied` — le garde d’expiry suffit. Notify alliés skippe les expirés. |
| Bots trahison / coalition sur pacte mort | `Bots.luau` | `allies[other]` était un tick d’expiry truthy. |
| Cote déjà prise = retraite 25 % | `Navy.step`, `Navy.resolveLanding` | Armes combinées (terre puis bateau) : restitution 100 %. Une vraie retraite (`retreating`) garde le malus. |
| Slot recyclé héritait d’un embargo | `GameState.removePlayer` | `addPlayer` reprend le slot : l’inbound n’était pas nettoyé. |
| Diplomatie vers soi en file | `IntentValidator` | `targetSlot == slot` → `InvalidTarget` à l’enqueue. |
| Sequence `inf` | `init.server` `isInteger` | Aligné sur IntentValidator (`abs ~= huge`). |
| Accept double-crédit futur | `Diplomacy.accept` | Passe par `returnCommittedTroops` (troops=0). |
| Retraite chemin mort 100 % | `GameState.stepAttacks` (non installé) | Aligné `RETREAT_LOSS` si quelqu’un désinstalle ChantierB. |

**Non modifié (volontaire) :** N1–N23 (sauf N19 partiel déjà en #23). N10.8 (bateau allié = retraite 25 % vs refund 100 %) : **inchangé**, décision design. Cap beachheads (N5), `MAX_TILES_PER_TICK` (N11), 18 factions (N12).

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + `guard < 80`).
- **Têtes de pont** = `BoatFront.seedBeachhead` : frontier = **voisins encore à la cible**, flag `isBeachhead`.
- **Pacte vivant** = `areAllied` : deux sens **et** `tick < expiry` (ou `true` legacy tests).
- **Comptabilité fronts** = `GameState.returnCommittedTroops` (pacte, défenseur disparu). Retraite terre = `RETREAT_LOSS`. Cote déjà nôtre = 100 %.
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients`.
- **DataStore** : inchangé (N6). Éliminés : toujours pas de `Persistence.record` si `players[slot]` nil à `endMatch` (N14 / N25).
- **Require** : DAG. Pas de cycle. `ChantierB`/`BoatFront`/`AimFront` dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N23 restent ouverts** sauf N19 partiel. Ci-dessous les **nouveaux** tickets.

---

### ISSUE-N24 — `findSeaPath` alloue `visited` + `parent` à chaque trajet

**Priorité :** P2 perf / GC marine.

**Problème :** `Navy.findSeaPath` fait `buffer.create(TILE_COUNT)` (40 960 octets) + table `parent` + queue **par appel**. Appelé à `launchInvasion`, `beginRetreat` (échec de path = malus immédiat), et `spawnTradeShips` (tous les ports armés × `TRADE_SHIP_INTERVAL`). Late-game : dizaines de ports × BFS 24k nœuds.

**Pourquoi 20K CCU :** 1 700 shards. Le path mer est déjà listé en N20 (warships O(carriers×boats) + spawn). Ici c’est le **GC du BFS lui-même**, pas la nested loop warship. Deux tickets pour ne pas tout mixer.

**Worker :**

1. Pool module-level : 1 buffer `visited` réutilisé (generation-stamp u8, reset par `buffer.fill` ou stamp++), 1 table `parent` + `table.clear`, 1 queue.
2. Cap `MAX_BFS_NODES = 24000` déjà en place : le garder.
3. Banc : 6000 ticks, `p95TickMs` ne doit pas monter. Test beachhead + boat own-tile restent verts.
4. Fichiers : `Navy.luau`, `tests/simulate.luau`.

**Contraintes :** déterminisme (même path). Pas de RemoteFunction. Ne pas mixer avec N20 (warships) ni N16 (buffer defense) dans le même PR.

---

### ISSUE-N25 — `checkVictory` jette `aliveHumans` ; `stepElimination` n’avertit pas `init.server`

**Priorité :** P2 matchmaking / persistence / cap 8.

**Problème :** deux trous liés.

1. `checkVictory` calcule `aliveHumans` puis `local _ = aliveHumans`. Le commentaire promet « la dernière faction debout compte comme domination » : **non implémenté**. Seuls ratio territorial et chrono ferment la partie.
2. `GameState.stepElimination` → `removePlayer` sans callback vers `init.server`. Conséquences :
   - `slotByPlayer` fantôme : le cap `MAX_HUMAN_PLAYERS=8` reste plein.
   - `endMatch` skip `Persistence.record` (`players[slot]` nil).
   - `fireDeployed` continue d’envoyer le firehose 10 Hz au mort (N14).

**Pourquoi 20K CCU :** 8 humains/shard est le vrai plafond Place. Un mort qui occupe le cap = file d’attente artificielle × 1 700 shards. XP/trahisons non gravées = ranking cassé.

**Worker :**

1. Décision produit d’abord : (A) victoire dès 1 faction restante (tribus comptent ?), (B) victoire dès 0 humains, (C) chrono + ratio seulement (alors supprimer le commentaire et `aliveHumans`).
2. Hook élimination : `state:step()` renvoie déjà les slots doomed. Dans `init.server` `stepOnce` : **avant** `removePlayer` ou via stats snapshot, `Persistence.record(userId, betrayals, false, experienceFor(ps, false))`, `resultRecorded[player]=true`, notify, **puis** libérer le cap (`slotByPlayer[player]=nil`) **ou** garder le spectateur sans le compter dans `humanCount`.
3. Ne pas double-compter avec `onPlayerRemoving`.
4. Test : simuler `stepElimination` d’un humain (fake Player) + vérifier qu’un 9e `deployPlayer` passerait. `init.server` hors bundle : extraire `humanCount(slotByPlayer, state)` testable, ou documenter un test Studio.
5. Fichiers : `init.server.luau`, `GameState.stepElimination`, éventuellement `Persistence.luau`, `tests/simulate.luau`.

**Contraintes :** ne pas kick le client au milieu d’une cinématique sans ticket HUD. Pas de RemoteFunction. Ne pas mixer avec N6 (DataStore debounce) : un `record` unique à l’élimination suffit ; le retry DataStore est N6.

---

## 5b. N1–N23 encore ouverts (passes 2–4)

| ID | Titre | Prio | Note passe 5 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` ; `MAX_BOATS or 3` mort (`Config=6`) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` jamais fire côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | park `isBeachhead` → hors cap |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | refund + **retraite RETREAT_LOSS** alignés ; le reste du corps est mort |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | inchangé |
| N10 | Divers P3 | P3 | donations gold sans plafond ; `pendingMode` last-writer ; README SmoothTerrain |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | debit = `attackTilesPerTick` × speed, `guard<80` |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 observé) | P1 | `Bots.spawnAll` wrap + `Tribes.spawnAll(6)` hors budget |
| N13 | Parité ère / cost factor `attackLogic` | P2 | doctrines oui, `Eras.accumulate` non |
| N14 | Humains éliminés occupent cap + firehose + **pas de Persistence.record** | P2 | **précisé en N25** (hook `stepElimination`) |
| N15 | Heap AimFront ≠ ChantierB | P2 | `terrainMag` vs `TERRAIN_COST/2` |
| N16 | `attackLogic` scanne tous les DEF | P1 | buffer `state.defense` non lu |
| N17 | Embargo allié + tribus auto-accept | P2 | design |
| N18 | `railIncome` HUD ≠ `deliveryValue` | P2 | snapshot niveau OK ; `links`/`stopBonus` absents du HUD |
| N19 | QuickChat 2-args target vs sequence | P3 | **partiel** : slot hors 1..48 refusé ; 2-args petit N + `needsTarget` = encore une cible |
| N20 | `findSeaPath` + warships O(carriers×boats) | P2 | **N24 isole le GC BFS** ; N20 garde nested loop + spawn ports |
| N21 | `tryAnnex` alloc `visited`/`queue` par capture | P2 | specs only |
| N22 | `BOAT_LANDING_BONUS` jamais lu | P2 | specs only |
| N23 | Trade / Navy gold ignorent doctrine, ère, `HUMAN_GOLD_MULTIPLIER` | P2 | specs only |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**. `Navy.step` convertit encore un transport allié en retraite (25 %). `resolveLanding` allié = 100 % si le check mid-transit est contourné.

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
  removePlayer inbound : embargo et proposition purges
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
  factions : 18
  metrics : ticks=6000 avgChanged=11.4 p95Changed=12 maxChanged=479 avgTickMs=0.36 p95TickMs=0.64
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe5.log`

---

## 8. Instructions worker (si reprise)

- Vérité runtime d’équilibrage = `ChantierB.apply(Config)` après `SystemsBootstrap.install()`, PAS `Config.luau` seul.
- Combat vivant = patches ChantierB, pas `GameState.stepAttacks` (sauf `returnCommittedTroops`, partagé).
- `areAllied` = deux sens **et** expiry. Ne pas revenir à un test `~= nil`.
- Cote déjà nôtre ≠ retraite. Allié en mer = toujours retraite 25 % (N10.8).
- Ne pas casser le client 34/34. `init.server` / `Persistence` exclus du bundle : extraire un helper testable ou documenter un test Studio.
- Ligne feel (#19/#22) : rebase sur cette passe avant cherry-pick, sinon perte de `areAllied` expiry + boat own-tile.
