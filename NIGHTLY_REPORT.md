# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 4)

Déclencheur : ouverture de la **PR #20** (`cursor/analyse-nocturne-du-codebase-84fb`) — beachheads, fronts visés, snapshot colis, specs N14–N20.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-0751`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #20**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#20.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest`.

La PR #20 a bien fermé le P0 beachhead (skip+refund), le double front AimFront, le snapshot colis, `pendingMode` en `ended`, et `accept` hors délai. Cette passe a **corrigé ce que #20 a manqué** — de la comptabilité de troupes, pas de l’équilibrage :

| Bug | Gravité | Statut |
|---|---|---|
| Front vivant quand le défenseur est éliminé / déco : troupes engagées détruites | **P0 combat / anti-exploit** | **corrigé** |
| `removePlayer` droppait les Attack sans rendre l’or de sang à l’attaquant | **P0 combat** | **corrigé** |
| `Diplomacy.viewFor` affichait une proposition déjà expirée | **P3 HUD** | **corrigé** |
| `SetAttackRatio` 99 enfilé puis clampé seulement à l’apply | **P3 validation** | **corrigé** |
| QuickChat `needsTarget` + slot 99 (hors catalogue) | **P3 anti-exploit fil** | **corrigé** (N19 partiel) |
| `JoinRequest` nationId NaN / non-entier | **P3 lobby** | **corrigé** (`init.server`, hors bundle) |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : **exit 0**.

- Serveur : 5 seeds + invariants + P0 + gardes #17–#20 + refund défenseur + refund orphelin + viewFor expiry + ratio borné + QuickChat slot 99.
- Client : **34/34 OK**.
- Metrics 6000 ticks : `avgChanged=13.8 p95Changed=27 maxChanged=479 avgTickMs=0.28 p95TickMs=0.41`.
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #20

**À merger** (combat naval vivant + specs N14–N20), sous réserve que cette passe 4 parte avec : **les troupes engagées disparaissaient** à l’élimination de la cible.

Points encore vrais après #20 :

| Claim #20 | Réalité après passe 4 |
|---|---|
| Beachhead frontier = voisins cible | confirmé (test vert) |
| AimFront reinforce = 1 front | confirmé |
| Colis `delivery.level` | confirmé |
| `accept` refuse l’expiry | confirmé ; **HUD `viewFor` fuyait encore** — corrigé ici |
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| N14–N20 specs only | N19 **partiellement** implémenté (slot hors 1..48 refusé à l’enqueue) |

`init.server.luau` est **exclu du bundle** : JoinRequest entier / QuickChat 2-args côté remote = revue manuelle + test IntentValidator pour la partie enqueue.

PR #19 (`cursor/of-feel-parity-5b2e`, feel OpenFront) est une **branche divergente** (intents immédiats, prep=0). Ne pas la merger par-dessus #16/#20 sans rebase : elle reporte #17/#18, pas #20.

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| Troupes perdues si défenseur nil | `GameState.returnCommittedTroops`, `ChantierB.stepAttacks`, `GameState.stepAttacks` (chemin mort) | `Diplomacy.accept` remboursait déjà ; combat et `removePlayer` non. Un disconnect mid-front volait l’armée. |
| `removePlayer` sans refund attaquant | `GameState.removePlayer` | L’attaquant survit : on lui rend `atk.troops`. L’attaquant éliminé : ses troupes meurent avec lui (voulu). |
| HUD proposition périmée | `Diplomacy.requestIsLive` + `viewFor` | `flush` avant `Diplomacy.step` : 1 tick de bouton Accepter fantôme. |
| Ratio non borné à l’enqueue | `IntentValidator` | `math.clamp(0.05, 1)` avant la file. Apply inchangé. |
| QuickChat slot 99 | `IntentValidator` enqueue + `init.server` remote | `needsTarget` exige 1..`MAX_TOTAL_FACTIONS`. 2-args avec arg2 > 48 = sequence. |
| NationId non-entier | `init.server` JoinRequest | NaN / inf / float ne passent plus. |

**Non modifié (volontaire) :** N1–N18, N20, cap beachheads (N5), embargo allié (N17), HUD rail (N18), 18 factions (N12), `MAX_TILES_PER_TICK` (N11). Compat QuickChat 2-args `needsTarget` + petit N (ancienne UI) : toujours lu comme cible.

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + `guard < 80`).
- **Têtes de pont** = `BoatFront.seedBeachhead` : frontier = **voisins encore à la cible**, flag `isBeachhead`.
- **Comptabilité fronts** = `GameState.returnCommittedTroops` (pacte, défenseur disparu). Retraite = malus `RETREAT_LOSS`.
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients`.
- **DataStore** : inchangé (N6). Éliminés : toujours pas de `Persistence.record` (N14).
- **Require** : DAG. Pas de cycle. `ChantierB`/`BoatFront`/`AimFront` dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N20 de la passe 3 restent ouverts** sauf N19 partiel (§5b). Ci-dessous les **nouveaux** tickets.

---

### ISSUE-N21 — `tryAnnex` alloue `visited`/`queue` par tuile conquise

**Priorité :** P2 perf / GC combat.

**Problème :** `ChantierB.tryAnnex` crée `{ [number]: boolean }` + `queue` + `pocket` **à chaque capture**. Late-game, `guard<80` × N fronts × annexes = pression GC 10 Hz.

**Pourquoi 20K CCU :** 1 700 shards × 10 Hz. Le combat vivant est déjà le 1er levier CPU (N16 DEF scan). L’annexe est le 2e levier GC.

**Worker :**

1. Buffers module-level (pattern `annexScratch`, `MapGen` scratch) : `visited` generation-stamp (u32 tick+seq) pour ne pas `table.clear` 40k clés.
2. Cap `pocket > 280` déjà en place : le garder.
3. Banc : 6000 ticks, `p95TickMs` ne doit pas monter. Test annex existant (enclave) reste vert.
4. Fichiers : `ChantierB.luau`, `tests/simulate.luau`.

**Contraintes :** déterminisme (même poche annexée). Ne pas changer le seuil 280. Pas de RemoteFunction. Ne pas mixer avec N16 (buffer defense) dans le même PR.

---

### ISSUE-N22 — `BOAT_LANDING_BONUS` jamais lu

**Priorité :** P2 équilibrage naval.

**Problème :** `Config.BOAT_LANDING_BONUS = 1.35` (surcharge côte défendue). Aucune référence dans `Navy.resolveLanding` ni `ChantierB.attackLogic`. Les têtes de pont coûtent comme de la terre.

**Pourquoi 20K CCU :** pas CPU — sensation « invasion gratuite ». OpenFront punit le débarquement contre une côte tenue.

**Worker :**

1. Décision : (A) multiplier `attackLogic` loss quand `atk.isBeachhead` et tuile côtière, (B) appliquer seulement à la **première** tuile après `seedBeachhead`, (C) supprimer la clé morte (N1).
2. Si (A)/(B) : dump avant/après sur graine fixe (tuiles prises / troupes restantes à T+30 ticks post-land).
3. Fichiers : `ChantierB.luau` et/ou `BoatFront.luau`, `Config.luau`, `tests/simulate.luau`.

**Contraintes :** ticket de design avant code. Ne pas retuner `attackTilesPerTick`. Test beachhead passe 3 (pas de refund immédiat) doit rester vert.

---

### ISSUE-N23 — Trade / Navy gold ignorent doctrine, ère, `HUMAN_GOLD_MULTIPLIER`

**Priorité :** P2 honesty éco.

**Problème :** `ChantierB.stepEconomy` applique doctrine × ère × mode × 1.12 humain. `Trade.resolve` et `Navy.resolveTrade` ajoutent l’or **brut**. Un humain Industriel gagne **moins** (relatif) du camion que des tuiles.

**Pourquoi 20K CCU :** pas shard CPU — meta « ignore les usines, stack des tuiles ». Couplé à N18 (HUD déjà faux sur `links`).

**Worker :**

1. Décision produit : (A) appliquer les mêmes multiplicateurs au payout, (B) documenter l’or brut comme voulu.
2. Si (A) : extraire `goldMultipliers(state, ps)` partagé, l’utiliser dans economy + Trade + Navy.
3. Test : même `ps`, payout camion × `doctrine.goldRate`. Snapshot `delivery.level` inchangé.
4. Fichiers : `Trade.luau`, `Navy.luau`, `ChantierB.luau` / `GameState.luau`, `tests/simulate.luau`.

**Contraintes :** ne pas changer le double crédit maritime (vendeur+acheteur, testé) sans ticket séparé. Ne pas mixer avec N18 (HUD) sauf extraction `deliveryValue` partagée.

---

## 5b. N1–N20 encore ouverts (passes 2–3)

| ID | Titre | Prio | Note passe 4 |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | + clés mortes `FRONT_TILES_PER_CONTACT`, `CITY_TROOP_INCREASE` |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | `replicate()` envoie stats+unités complets à 10 Hz |
| N3 | Timebase tick vs `os.clock()` | P1 | combat/match = clock ; sim = tick |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | `RequestSnapshot` jamais fire côté client |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) | P2 | expansion OK ; cap ouvert |
| N6 | DataStore debounce / retry / session | P2 | `UpdateAsync` max-merge ≠ somme XP 2 sessions |
| N7 | Matchmaking MemoryStore / Teleport | P2 | absent du tree |
| N8 | Combat mort `GameState.stepAttacks` | P2 | **refund aligné** sur le vivant ; le reste du corps est mort |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 | inchangé |
| N10 | Divers P3 | P3 | donations overflow, `pendingMode` last-writer lobby, README SmoothTerrain |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | debit = `attackTilesPerTick` × speed, `guard<80` |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 observé) | P1 | `Bots.spawnAll` wrap + `Tribes.spawnAll(6)` hors budget |
| N13 | Parité ère / cost factor `attackLogic` | P2 | doctrines oui, `Eras.accumulate` non |
| N14 | Humains éliminés occupent cap + firehose + **pas de Persistence.record** | P2 | `endMatch` skip si `players[slot]` nil |
| N15 | Heap AimFront ≠ ChantierB | P2 | `terrainMag` vs `TERRAIN_COST/2` |
| N16 | `attackLogic` scanne tous les DEF | P1 | buffer `state.defense` non lu |
| N17 | Embargo allié + tribus auto-accept | P2 | design |
| N18 | `railIncome` HUD ≠ `deliveryValue` | P2 | snapshot niveau OK ; `links`/`stopBonus` absents du HUD |
| N19 | QuickChat 2-args target vs sequence | P3 | **partiel** : slot hors 1..48 refusé ; 2-args petit N + `needsTarget` = encore une cible (compat) |
| N20 | `findSeaPath` + warships O(carriers×boats) | P2 | + `spawnTradeShips` ports × path à l’intervalle |

N10.8 (refund allié bateau 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**, décision design.

---

## 6. Drift Config → `ChantierB.apply` (extrait, inchangé)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | oui (formule custom) |
| `MAX_TILES_PER_TICK` | 400→écrit 56 | 56 | **non** |
| `RETREAT_LOSS` | 0.25 | 0.25 | oui |
| `BOAT_RETREAT_LOSS` | 0.25 | 0.25 | oui |
| `BOAT_LANDING_BONUS` | 1.35 | 1.35 | **non** (N22) |
| `CITY_LEVELS[1].popCapBonus` | 900 | 50000 | oui |
| `FRONT_TILES_PER_CONTACT` | — | 2.4 | **non** |

---

## 7. Preuve tests

```
./tests/run.sh  → exit 0
Serveur : Tous les invariants tiennent.
  intentions : sequence, idempotence, rate limit OK
  intentions : schema doctrine/nuke/diplomatie, ended, file OK
  intentions : QuickChat cooldown honore
  intentions : ratio borne, QuickChat slot hors catalogue refuse
  refund defenseur : removePlayer rend les troupes
  refund orphelin : stepAttacks rend les troupes
  beachhead : frontier voisins, pas de remboursement
  aim reinforce : un seul front apres deux lancers
  colis snapshot : niveau au depart honore
  accept expire : proposition perimee refusee
  viewFor expiry : proposition perimee masquee
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
  factions : 18
  metrics : ticks=6000 avgChanged=13.8 p95Changed=27 maxChanged=479 avgTickMs=0.28 p95TickMs=0.41
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe4.log`

---

## 8. Instructions worker (si reprise)

- Vérité runtime d’équilibrage = `ChantierB.apply(Config)` après `SystemsBootstrap.install()`, PAS `Config.luau` seul.
- Combat vivant = patches ChantierB, pas `GameState.stepAttacks` (sauf `returnCommittedTroops`, partagé).
- Ne pas casser le client 34/34. `init.server` / `Persistence` exclus du bundle : extraire un helper testable ou documenter un test Studio.
- PR #19 feel-parity : rebase sur cette passe avant tout cherry-pick, sinon perte du refund troupes.
