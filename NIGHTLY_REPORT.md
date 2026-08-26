# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 3)

Déclencheur : ouverture de la **PR #18** (`cursor/analyse-nocturne-du-codebase-4548`) — réplication déployés, JoinRequest `ended`, specs N11–N13.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-84fb`.
Base : PR #16 (`cursor/p0-framework-hardening-5b2e`). Cette passe est un **sur-ensemble de #18**.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16 / #17 / #18.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que des intentions + `JoinRequest` ; `IntentValidator` enfile, le tick applique.

La PR #18 a bien réduit l’audience de réplication (`fireDeployed`) et fermé JoinRequest en `ended` **côté `deployPlayer`**. Cette passe a **corrigé ce que #18 a manqué** :

| Bug | Gravité | Statut |
|---|---|---|
| Tête de pont : tuile déjà à nous enfilée → skip + remboursement immédiat | **P0 combat** | **corrigé** |
| Renfort d’un front visé (`AimFront.sourceTile`) → 2e Attack | **P1 CPU/exploit** | **corrigé** |
| Colis camion payé au niveau d’arrivée, pas au snapshot | **P2 éco** | **corrigé** |
| `JoinRequest` en `ended` votait quand même `pendingMode` | **P2 lobby** | **corrigé** |
| `Diplomacy.accept` ignorait l’expiry (1 tick de trop) | **P2 diplo** | **corrigé** |

**20K CCU** = ~1 700 shards × 12 factions publiques / 8 humains, pas un monde unique.

Banc headless (`./tests/run.sh`) : **exit 0**.

- Serveur : 5 seeds + invariants + P0 + gardes #17/#18 + beachhead + aim reinforce + colis snapshot + accept expiré.
- Client : **34/34 OK**.
- Metrics 6000 ticks : `avgChanged=9.9 p95Changed=9 maxChanged=978 avgTickMs=0.29 p95TickMs=0.23`.
- **Factions observées : 18** (toujours 12 + 6 tribus). ISSUE-N12 ouvert.

---

## 2. Revue PR #18

**À merger** (autorité + audience + specs), sous réserve que cette passe 3 parte avec : les invasions navales de #18 **ne progressaient pas**.

Points encore vrais après #18 :

| Claim #18 | Réalité après passe 3 |
|---|---|
| `MAX_TILES_PER_TICK=56` inutilisé | inchangé (N11) |
| Banc Classique = 18 factions | inchangé (N12) |
| `JoinRequest` refusé en `ended` | oui pour le spawn ; **`pendingMode` fuyait** — corrigé ici |
| `fireDeployed` pour StateDelta/Units | oui ; `MatchUpdate` / `RosterUpdate` / Notify global restent `FireAllClients` |
| Beachheads hors cap 2 fronts | toujours vrai (N5) ; **en plus** la frontier était morte |

`init.server.luau` est **exclu du bundle** : le garde `ended` de JoinRequest n’est pas exécuté par `./tests/run.sh`. Revue manuelle uniquement.

---

## 3. Correctifs livrés dans cette passe (sûrs)

| Bug | Fichiers | Pourquoi |
|---|---|---|
| Beachhead skip+refund | `BoatFront.seedBeachhead` | `Navy.resolveLanding` fait `setOwner` puis enfilait **cette** tuile. `stepAttacks` exige `owner == atk.target` → pop, skip, heap vide, troupes rendues **le même tick**. Les invasions ne s’étendaient jamais. |
| Parking `sourceTile` trop large | `BoatFront.launchAttack`, `SystemsBootstrap` | `AimFront.focus` pose `sourceTile` sur les fronts **terre**. BoatFront les garait → `launchAttack` ne voyait pas le front → 2e Attack. On ne gare plus que `isBeachhead`. |
| `delivery.level` mort | `Trade.resolve` | Champ écrit au départ, lu `factory.level` à l’arrivée. Upgrade en transit = or gratuit. |
| `pendingMode` en `ended` | `init.server` JoinRequest | Le vote mode passait **avant** `deployPlayer`. Un spectateur post-match changeait le round suivant. |
| Accept hors délai | `Diplomacy.accept` | `flush` tourne avant `Diplomacy.step`. Proposition expirée encore honorable 1 tick. Garde `already allied` aussi. |
| `RETREAT_LOSS` / `BOAT_RETREAT_LOSS` absents de Config | `Config.luau` | Injectés seulement par apply / bootstrap. Banc sans apply lisait `or 0`. |
| Types Attack incomplets | `GameState.luau` | `sourceTile`, `aimX/Y`, `isBeachhead` documentés. |

**Non modifié (volontaire) :** N1–N13 (sauf la partie beachhead **expansion**, le **cap** N5 reste), donations troupes overflow (commenté comme voulu), embargo allié, tribus auto-accept, payload stats (N2).

---

## 4. Cartographie des systèmes critiques

```
init.server  → IntentValidator.flush → Bots / Navy / Nukes / Trade / Diplomacy → GameState.step → replicate
SystemsBootstrap.install()  monkey-patch : ChantierB, BoatFront (isBeachhead), AimFront, tribus, spawn bots différé
```

- **Combat vivant** = `ChantierB.stepAttacks` (`attackLogic` + `attackTilesPerTick` + `guard < 80`).
- **Têtes de pont** = `BoatFront.seedBeachhead` : frontier = **voisins encore à la cible**, flag `isBeachhead`.
- **Réplication** : hot path → `fireDeployed`. `MatchUpdate` / `RosterUpdate` / Notify-Sfx globaux → `FireAllClients`.
- **DataStore** : inchangé (N6).
- **Require** : DAG. Pas de cycle. `ChantierB`/`BoatFront`/`AimFront` sont dans ReplicatedStorage (formules visibles client, `install()` serveur seulement).

---

## 5. Issues worker-ready (à créer dans GitHub)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N13 de la passe 2 restent ouverts** (résumés §5b). Ci-dessous les **nouveaux** tickets.

---

### ISSUE-N14 — Humains éliminés occupent `MAX_HUMAN_PLAYERS`

**Priorité :** P2 anti-exploit / salon.

**Problème :** `slotByPlayer` n’est vidé qu’au disconnect (`onPlayerRemoving`). `deployPlayer` compte **toutes** les entrées. Un commandant éliminé (`removePlayer` / `stepElimination`) reste spectateur **et** bloque le 8e/9e join. `fireDeployed` continue de lui envoyer le firehose 10 Hz.

**Pourquoi 20K CCU :** spectateurs = destinataires RemoteEvent facturés. Salon 8 humains morts = salon mort jusqu’au restart.

**Worker :**

1. Distinguer `slotByPlayer` (autorité / intents) et `spectators` (réplication HUD).
2. Décision produit (documenter) : (A) mid-match join interdit, mais **ne plus compter** les éliminés dans le cap, (B) libérer le slot pour un nouveau JoinRequest.
3. Si (A) : `humanCount` = joueurs dont `state.players[slot]` existe encore.
4. Test : impossible via bundle (`init.server` exclu). Ajouter un extrait testable (`countActiveHumans`) **ou** un test Studio documenté.
5. Fichiers : `init.server.luau`. Ne pas casser `fireDeployed` pour les vivants.

**Contraintes :** server-authoritative. Pas de 9e humain vivant. Ne pas réintroduire JoinRequest en `ended`.

---

### ISSUE-N15 — Priorités de heap AimFront ≠ ChantierB

**Priorité :** P2 combat.

**Problème :** `AimFront.priority` pèse `terrainMag` (1 / 1.5 / 2). L’expansion `ChantierB.enqueueFront` pèse `TERRAIN_COST/2` (plage 0.85 … sommet 4). Un même front mélange deux ordres.

**Pourquoi 20K CCU :** frontier plus chaotique = plus de pops/`guard` gaspillés.

**Worker :**

1. Une fonction `frontPriority` partagée (AimFront **ou** ChantierB, pas les deux).
2. L’utiliser dans `AimFront.enqueue`, `ChantierB.enqueueFront`, `BoatFront.frontPriority`.
3. Test : même tuile, même tick, même owner → même coût de heap.
4. **Ne pas retuner** `attackLogic`. Mesurer 6000 ticks `p95TickMs` / `maxChanged`.

**Contraintes :** zéro changement d’équilibrage volontaire. Coupler conceptuellement à N13.

---

### ISSUE-N16 — `attackLogic` ignore le buffer `defense`, scanne tous les DEF

**Priorité :** P1 perf combat.

**Problème :** `ChantierB.attackLogic` parcourt `state.buildings` pour les bunkers dans le rayon, **par tuile conquise**. Le buffer `state.defense` (maintenu par `GameState`) n’est pas lu. Coût O(bâtiments × tuiles × fronts) par tick.

**Pourquoi 20K CCU :** late-game 50+ villes/bunkers × `guard<80` × N fronts. C’est le 1er levier CPU combat après N11.

**Worker :**

1. Lire `buffer.readu8(state.defense, tile)` (ou densité locale) dans `attackLogic`.
2. Supprimer le scan global des DEF **si** le buffer est la source de vérité.
3. Vérifier que `setOwner` / pose / destruction de bunker maintiennent le buffer (déjà le cas dans `GameState` — confirmer par test).
4. Banc : 6000 ticks, `p95TickMs` ne doit pas monter.
5. Fichiers : `ChantierB.luau`, éventuellement `GameState.luau`, `tests/simulate.luau`.

**Contraintes :** ne pas changer le bonus bunker ressenti sans dump avant/après sur une graine fixe.

---

### ISSUE-N17 — Embargo sur un allié + tribus auto-accept

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

### ISSUE-N18 — `railIncome` HUD ≠ formule camion

**Priorité :** P2 honesty éco.

**Problème :** `Trade.deliveryValue` = `(base + dist×tile) * level * links * stopBonus`. `GameState` HUD `railIncome` omet `× links` et `stopBonus`. Le leaderboard ment. Cette passe a fixé le **niveau snapshot** ; le HUD n’est toujours pas aligné.

**Worker :**

1. Extraire `deliveryValue` dans un module partagé testable (`Trade` ou `Config` helper).
2. `refreshRailNetwork` / estimate = même fonction, même hypothèses (1 colis / usine, cadence).
3. Test : usine 3 liens, `railIncome` proportionnel à `deliveryValue`.
4. Fichiers : `Trade.luau`, `GameState.luau`, `tests/simulate.luau`.

**Contraintes :** ne pas changer la formule de payout, seulement l’affichage — **ou** documenter un nerf `links` (N10.10) comme ticket séparé.

---

### ISSUE-N19 — QuickChat 2-args : `target` vs `sequence`

**Priorité :** P3 anti-exploit fil.

**Problème :** handler `(messageId, targetSlot, sequence)`. Ancien client 2-args : l’entier arg2 est **toujours** lu comme `targetSlot`. Un `needsTarget` avec petit N vise la faction N.

**Worker :**

1. Exiger 3 args pour les messages `needsTarget`, **ou** si arg3 nil et arg2 > MAX_TOTAL_FACTIONS alors arg2 = sequence.
2. Test IntentValidator : `(id, 99)` sans 3e arg ne doit pas viser le slot 99.
3. Fichiers : `init.server.luau`, éventuellement `IntentValidator.luau`.

**Contraintes :** ne pas casser le client officiel qui envoie déjà 3 args (`init.client.luau` `fireOrder`).

---

### ISSUE-N20 — Navy `findSeaPath` + warships O(carriers×boats)

**Priorité :** P2 perf mer.

**Problème :** `findSeaPath` alloue une map parent par appel (GC sous burst d’ordres bateau). Ciblage warship : double boucle carriers × boats chaque tick.

**Pourquoi 20K CCU :** 6 transports × 8 porte-avions × 10 Hz + pathfinding à chaque `BoatOrder`.

**Worker :**

1. Buffers `visited`/`parent` module-level (pattern `scratch` MapGen).
2. Warships : grille spatiale (cellule 8–16 tuiles) ou cap de cibles scannées.
3. Banc : ne pas augmenter `p95TickMs` ; test pathfinding existant (`commerce` mer) reste vert.
4. Fichiers : `Navy.luau`, `tests/simulate.luau`.

**Contraintes :** déterminisme (même graine → même chemin). Pas de RemoteFunction.

---

## 5b. N1–N13 encore ouverts (passe 2, non traités ici)

| ID | Titre | Prio |
|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 |
| N3 | Timebase tick vs `os.clock()` | P1 |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 |
| N5 | Cap beachheads (`MAX_ACTIVE_ATTACKS`) — **expansion corrigée**, cap ouvert | P2 |
| N6 | DataStore debounce / retry / session | P2 |
| N7 | Matchmaking MemoryStore / Teleport | P2 |
| N8 | Combat mort `GameState.stepAttacks` vs vivant | P2 |
| N9 | `stepDoomsday` O(TILE_COUNT) | P2 |
| N10 | Divers P3 (seq nil, README SmoothTerrain, `justClaimed` test mort, catalogue « +900 », bunker « 6 tuiles » vs rayon 30, donations overflow documenté, `pendingMode` last-writer **en lobby**) | P3 |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 observé) | P1 |
| N13 | Parité ère / cost factor `attackLogic` | P2 |

N10.8 (refund allié 100 % vs `BOAT_RETREAT_LOSS`) : **inchangé**, décision design.

---

## 6. Drift Config → `ChantierB.apply` (extrait, inchangé)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | oui (formule custom) |
| `MAX_TILES_PER_TICK` | 400→écrit 56 | 56 | **non** |
| `RETREAT_LOSS` | **0.25 (ajouté ici)** | 0.25 | oui |
| `BOAT_RETREAT_LOSS` | **0.25 (ajouté ici)** | 0.25 | oui |
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
  beachhead : frontier voisins, pas de remboursement
  aim reinforce : un seul front apres deux lancers
  colis snapshot : niveau au depart honore
  accept expire : proposition perimee refusee
  combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
  factions : 18
Client  : 34 OK — Tous les ecrans se construisent et s'executent sans erreur.
```

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-passe3.log`
