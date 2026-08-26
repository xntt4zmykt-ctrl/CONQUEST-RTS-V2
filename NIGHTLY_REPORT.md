# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 4)

Déclencheur : ouverture de la **PR #21** (`cursor/analyse-nocturne-du-codebase-e863`) — hardening feel + rapport N1–N16. Base : feel #19 + P0 #16.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-5ba6`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#21.

Cette passe **porte les correctifs sûrs de #20** (branche P0 sans feel) **sur le HEAD feel**, et ajoute les specs nées du croisement feel × marine.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes et slot cible sont dérivés serveur.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #21 (feel + nightly N1–N16)

| Claim #21 | Réalité à l’ouverture |
|---|---|
| Cap 8 humains, Join ended, fireDeployed | Oui. **Mais** Join `ended` était dans `deployPlayer` : `pendingMode` était déjà voté. Corrigé ici. |
| `areAllied` 2-ways, `removePlayer` via `setOwner` | Oui. |
| Charge bateau 0.2 | Oui. |
| Têtes de pont OF | **Non.** `BoatFront.seedBeachhead` enfilait la tuile déjà conquise → skip+remboursement. Porté depuis #20. |
| Front visé (AimFront `sourceTile`) | **Bug.** `BoatFront` garait **tous** les `sourceTile`, donc un 2e clic créait un 2e Attack. Porté depuis #20 (`isBeachhead` seulement). |
| Dual Config / ChantierB | Toujours ouvert (N1, N11). |

PRs ouvertes au moment de la revue : #16 P0, #17/#18 nightly P0, #19 feel, #20 nightly P0 passe 3, #21 nightly feel. **#21 + cette passe** est le sur-ensemble feel à merger. #20 reste utile seulement si on abandonne feel.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| Beachhead enfile la tuile déjà à soi | `BoatFront.luau` | Invasions mortes le tick d’atterrissage (skip + heap vide + refund) |
| Park `sourceTile` (fronts visés) | `BoatFront.luau` | 2e clic = 2e Attack, cap 2 saturé, isolation terre/mer cassée |
| Colis payé au niveau d’arrivée | `Trade.luau` | Upgrade usine en transit = or extra-server |
| `Diplomacy.accept` ignore expiry / pacte actif | `Diplomacy.luau` | Accept le tick d’expiry (apply immédiat avant `step`) |
| `JoinRequest` ended vote `pendingMode` | `init.server.luau` | Spam victoire change le mode du round suivant + brûle le cooldown |
| `RETREAT_LOSS` / `BOAT_RETREAT_LOSS` absents de Config | `Config.luau` | Tuning mort : seules les valeurs `ChantierB.apply` / `or 0.25` vivaient |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17).

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (apply immédiat) → tick : Bots/Navy/Nukes/Trade/Diplomacy → GameState.step → replicate(fireDeployed)
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom), BoatFront, AimFront, tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`. `sourceTile` d’AimFront n’est plus un critère de parking.
- **Réplication :** StateDelta / UnitSnapshot / BuildingDelta / plunder / trade / explosions → déployés. MatchUpdate / roster / notify global / sfx global → tous (menu). Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N16 de #21 restent ouverts** (sauf les bugs §3). Ci-dessous les **nouveaux** tickets (N17–N25). N1–N16 : résumé §5b.

---

### ISSUE-N17 — Humains éliminés occupent `MAX_HUMAN_PLAYERS`

**Priorité :** P2 anti-exploit / salon.

**Problème :** `slotByPlayer` n’est vidé qu’au disconnect (`onPlayerRemoving`). `deployPlayer` compte **toutes** les entrées. Un commandant éliminé (`removePlayer` / `stepElimination`) reste spectateur **et** bloque le 8e/9e join. `fireDeployed` continue de lui envoyer le firehose 10 Hz.

**Pourquoi 20K CCU :** spectateurs = destinataires RemoteEvent facturés. Salon 8 humains morts = salon mort jusqu’au restart.

**Worker :**

1. Distinguer `slotByPlayer` (autorité / intents) et `spectators` (réplication HUD).
2. Décision produit (documenter) : (A) mid-match join interdit, mais **ne plus compter** les éliminés dans le cap, (B) libérer le slot pour un nouveau JoinRequest.
3. Si (A) : `humanCount` = joueurs dont `state.players[slot]` existe encore ; refuser Join si `matchPhase == "playing"` et pas déjà slot.
4. Test : impossible via bundle (`init.server` exclu). Extraire `countActiveHumans` testable **ou** test Studio documenté.
5. Fichiers : `init.server.luau`. Ne pas casser `fireDeployed` pour les vivants.

**Contraintes :** server-authoritative. Pas de 9e humain vivant. Ne pas réintroduire JoinRequest en `ended`.

---

### ISSUE-N18 — Priorités de heap AimFront ≠ ChantierB / BoatFront

**Priorité :** P2 combat.

**Problème :** `AimFront.priority` pèse `terrainMag` (1 / 1.5 / 2). L’expansion `ChantierB.enqueueFront` et `BoatFront.frontPriority` pèsent `TERRAIN_COST/2` (plage 0.85 … sommet 4). Un même front mélange deux ordres dès qu’AimFront a seed puis ChantierB étend.

**Pourquoi 20K CCU :** frontier plus chaotique = plus de pops/`guard` gaspillés.

**Worker :**

1. Une fonction `frontPriority` partagée (AimFront **ou** ChantierB, pas les trois copies).
2. L’utiliser dans `AimFront.enqueue`, `ChantierB.enqueueFront`, `BoatFront.frontPriority`.
3. Test : même tuile, même tick, même owner → même coût de heap.
4. **Ne pas retuner** `attackLogic`. Mesurer 6000 ticks `p95TickMs` / `maxChanged`.

**Contraintes :** zéro changement d’équilibrage volontaire. Coupler conceptuellement à N13.

---

### ISSUE-N19 — Embargo sur un allié + tribus auto-accept

**Priorité :** P2 design / anti-grief.

**Problème :**

1. `Diplomacy.setEmbargo` n’a **pas** de garde `areAllied`. Un allié coupe le commerce maritime tout en bloquant l’attaque terrestre.
2. `Tribes.luau` accepte **toute** proposition. Une carte Classique peut se recouvrir d’alliances via les 6 tribus.

**Pourquoi 20K CCU :** graphe d’alliances saturé = moins de fronts légaux, plus de donations, diplomatie HUD O(N²) à 1 Hz.

**Worker :**

1. Décision : (A) embargo interdit entre alliés, (B) embargo rompt le pacte, (C) gardé et documenté.
2. Tribus : (A) jamais d’alliance, (B) quota / force relative, (C) cooldown comme les bots.
3. Tests simulate pour la décision retenue.
4. Fichiers : `Diplomacy.luau`, `Tribes.luau`, `tests/simulate.luau`.

**Contraintes :** ticket de design avant code. Ne pas mixer avec N12 (capa).

---

### ISSUE-N20 — `railIncome` HUD ≠ formule camion

**Priorité :** P2 honesty éco.

**Problème :** `Trade.deliveryValue` = `(base + dist×tile) * level * links * stopBonus`. `GameState.refreshRailNetwork` estime `(goldSum * level) / avgPeriod` : omet `× links` et `stopBonus`. Le leaderboard ment. Cette passe a fixé le **niveau snapshot** ; le HUD n’est toujours pas aligné.

**Worker :**

1. Extraire `deliveryValue` dans un module partagé testable (`Trade` ou helper Config).
2. `refreshRailNetwork` / estimate = même fonction, mêmes hypothèses (1 colis / usine, cadence).
3. Test : usine 3 liens, `railIncome` proportionnel à `deliveryValue`.
4. Fichiers : `Trade.luau`, `GameState.luau`, `tests/simulate.luau`.

**Contraintes :** ne pas changer la formule de payout, seulement l’affichage — **ou** documenter un nerf `links` comme ticket séparé.

---

### ISSUE-N21 — QuickChat 2-args : `target` vs `sequence`

**Priorité :** P3 anti-exploit fil.

**Problème :** handler `(messageId, targetSlot, sequence)`. Ancien client 2-args : l’entier arg2 est **toujours** lu comme `targetSlot`. Un `needsTarget` avec petit N vise la faction N.

**Worker :**

1. Exiger 3 args pour les messages `needsTarget`, **ou** si arg3 nil et arg2 > MAX_TOTAL_FACTIONS alors arg2 = sequence.
2. Test IntentValidator : `(id, 99)` sans 3e arg ne doit pas viser le slot 99.
3. Fichiers : `init.server.luau`, éventuellement `IntentValidator.luau`.

**Contraintes :** ne pas casser le client officiel qui envoie déjà 3 args (`init.client.luau` `fireOrder`).

---

### ISSUE-N22 — Warships O(carriers × boats) par tick

**Priorité :** P2 perf mer.

**Problème :** `Navy` ciblage warship = double boucle porte-avions × tous les bateaux, chaque tick. (Le pool `visited` de `findSeaPath` reste N16.)

**Pourquoi 20K CCU :** 6 transports × 8 porte-avions × 10 Hz. Classique 18 factions avec bases navales.

**Worker :**

1. Grille spatiale (cellule 8–16 tuiles) ou cap de cibles scannées / carrier.
2. Banc : ne pas augmenter `p95TickMs` ; test pathfinding existant (`commerce` mer) reste vert.
3. Fichiers : `Navy.luau`, `tests/simulate.luau`.

**Contraintes :** déterminisme (même graine → même cible). Pas de RemoteFunction. Ne pas mixer avec N16 (pool BFS).

---

### ISSUE-N23 — `retreatAttack` ne marque que le premier front

**Priorité :** P2 feel / marine.

**Problème :** `GameState.retreatAttack` s’arrête au **premier** `attacker+target`. Terre + tête de pont contre le même slot : un seul recule. `SystemsBootstrap` appelle ensuite `Navy.retreatBoats` (OK mer), mais le 2e Attack terrestre/beachhead continue.

**Pourquoi 20K CCU / OF :** un clic retraite doit vider le couple, sinon le joueur croit s’être retiré et continue de saigner.

**Worker :**

1. Décision : (A) marquer **tous** les Attacks du couple (sauf si `isBeachhead` a sa propre sémantique), (B) retraite ciblée par `aimTile` / `sourceTile`.
2. Si (A) : boucle complète, même `retreatAt`. Test : land + beachhead → les deux ont `retreatAt`.
3. Fichiers : `GameState.luau`, `SystemsBootstrap.luau`, `tests/simulate.luau`.

**Contraintes :** ne pas casser `RETREAT_DELAY` / malus 25 %. Server-authoritative.

---

### ISSUE-N24 — `notify` / `sfx` globaux encore en `FireAllClients`

**Priorité :** P2 perf réplication.

**Problème :** `fireDeployed` couvre StateDelta / unités / bâtiments / plunder / trade / explosions. `flushEvents` envoie les notifies/sfx **sans `only`** à tout le Place (menu compris). Roster + MatchUpdate idem (volontaire pour le lobby).

**Pourquoi 20K CCU :** Place MaxPlayers > 8 → joueurs menu facturés à chaque trahison / alliance / sfx combat, 10 Hz playing.

**Worker :**

1. Notifies/sfx globaux → `fireDeployed` (même audience que le monde).
2. Garder MatchUpdate + RosterUpdate en `FireAllClients` (menu a besoin du compte à rebours).
3. Test : pas d’E2E bundle. Documenter. Ne pas casser Overlay sfx des déployés.

**Fichiers :** `init.server.luau`.
**Contraintes :** pas de RemoteFunction. Menu reste informé via MatchUpdate.

---

### ISSUE-N25 — `MAX_BOATS_PER_PLAYER` Config 6 vs OF 3

**Priorité :** P3 honesty / perf mer.

**Problème :** `Config.MAX_BOATS_PER_PLAYER = 6`. `SystemsBootstrap` fait `or 3` (no-op, la clé existe). Navy cap vivant = **6**. Commentaires chantier F / memories disent cap 3.

**Pourquoi 20K CCU :** 18 factions × 6 transports = 108 BFS/paths + overlay bateaux.

**Worker :** (A) baisser Config à 3 (lift OF, mesurer), ou (B) documenter 6 et retirer le `or 3`. Test `Navy.countBoats` au 4e/7e launch. **Ne pas** retuner `BOAT_TROOP_RATIO`.

**Fichiers :** `Config.luau`, `SystemsBootstrap.luau`, `Navy.luau`, `tests/simulate.luau`.

---

## 5b. N1–N16 encore ouverts (#21, non traités ici)

| ID | Titre | Prio |
|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 |
| N3 | Timebase tick vs `os.clock()` | P1 |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 |
| N6 | DataStore debounce / retry / merge additif | P2 |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 |
| N8 | Combat mort vs combat vivant | P2 |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 |
| N10 | Divers P3 (seq nil, README SmoothTerrain, bots nuke, embargo trains, GROWTH_RATE…) | P3 |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 factions) | P1 |
| N13 | Parité combat (ère / cost factor / constantes mortes) | P2 |
| N14 | Apply immédiat vs lockstep (feel #19) | P1 |
| N15 | `PREPARATION_DURATION=0` vs gardes `combatUnlocked` | P2 |
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 |

Les textes worker-ready complets de N1–N16 sont dans la PR #21 / `NIGHTLY_REPORT.md` historique. Ne pas les dupliquer ici.

---

## 6. Drift Config → `ChantierB.apply` (extrait)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | formule custom |
| `MAX_TILES_PER_TICK` | 400 | 56 | **non** (`guard<80`) |
| `DEFENSE_RADIUS` | 6 | 30 | oui (scan buildings) |
| `BOAT_TROOP_RATIO` | 0.2 | 0.2 | **oui** (Navy) |
| `RETREAT_LOSS` | **0.25** (cette passe) | 0.25 | **oui** |
| `BOAT_RETREAT_LOSS` | **0.25** (cette passe) | 0.25 (`or`) | **oui** (Navy) |
| `MAX_BOATS_PER_PLAYER` | 6 | 6 | oui (N25) |
| `CITY_LEVELS[1].popCapBonus` | 900 | 50000 | oui |
| `PREPARATION_DURATION` | 0 | 0 | forcé true |
| `FRONT_TILES_PER_CONTACT` | — | 2.4 | **non** |
| `CITY_TROOP_INCREASE` | — | 50000 | **non** |

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
beachhead : frontier voisins, pas de remboursement
aim reinforce : un seul front apres deux lancers
colis snapshot : niveau au depart honore
accept expire : proposition perimee refusee
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=10.9 p95Changed=58 maxChanged=746 avgTickMs=0.31 p95TickMs=0.93
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **34/34 OK** — tous les écrans se construisent et s’exécutent sans erreur.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass4.log`

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `ChantierB` / `BoatFront` / `AimFront` sont dans ReplicatedStorage (formules visibles client, `install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes.
