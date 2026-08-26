# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 5)

Déclencheur : ouverture de la **PR #22** (`cursor/analyse-nocturne-du-codebase-5ba6`) — beachheads + fronts visés sur feel #21, specs N17–N25.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-a9d9`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#22.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes et slot cible sont dérivés serveur.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #22 (passe 4) : claims vérifiés.** Beachhead = voisins encore à la cible ; park `isBeachhead` seulement ; combat vivant = `ChantierB.stepAttacks` ; `MAX_TILES_PER_TICK` non lu par le combat installé. Join `ended` avant `pendingMode`. Colis snapshot et `Diplomacy.accept` expiry tiennent.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #22

| Claim #22 | Réalité à l’ouverture |
|---|---|
| Frontier beachhead = voisins cible, pas tuile debarquée | Oui (`BoatFront.seedBeachhead`). Stub mort `GameState.seedBeachhead` encore faux (N30). |
| Park `isBeachhead` seulement | Oui. |
| Colis payé au niveau snapshot | Oui, testé. |
| `Diplomacy.accept` refuse expiry / pacte actif | Oui, testé. |
| Join `ended` ne vote plus `pendingMode` | Oui. |
| N17–N25 specs | N21, N23, N24 **corrigés ici**. Le reste reste ouvert. |

PRs ouvertes au moment de la revue : #16 P0, #17/#18 nightly P0, #19 feel, #20 nightly P0 passe 3, #21 nightly feel, **#22 sur-ensemble feel**. **#22 + cette passe** est le sur-ensemble feel à merger. #20 reste utile seulement si on abandonne feel.

**Correction N20 :** `refreshRailNetwork` **inclut** déjà `× links` (via `/ (periodSum/n)`). L’écart restant est `stopBonus` + niveau live vs snapshot.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `removePlayer` jette les troupes des attaquants | `GameState.luau`, `ChantierB.luau` | Déconnexion défenseur = disparition silencieuse de population (anti-comptabilité) |
| `retreatAttack` ne marquait que le 1er front (N23) | `GameState.luau` | Terre + tête de pont : un clic doit vider le couple |
| QuickChat 2-args mark hijack (N21) | `IntentValidator.luau`, `init.server.luau` | `(attack_target, N)` sans sequence visait le slot N |
| `notify` / `sfx` globaux `FireAllClients` (N24) | `init.server.luau` | Menu / Place MaxPlayers > 8 facturés à chaque trahison / sfx |
| Commentaire SAM + stub beachhead | `Config.luau`, `GameState.luau` | Honesty tuner (N26) / piège hors bootstrap (N30) |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront (N18), embargo/tribus (N19), railIncome (N20), warships grille (N22), MAX_BOATS (N25).

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (apply immédiat) → tick : Bots/Navy/Nukes/Trade/Diplomacy → GameState.step → replicate(fireDeployed)
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom), BoatFront, AimFront, tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`.
- **Réplication :** StateDelta / UnitSnapshot / BuildingDelta / plunder / trade / explosions / **notify&sfx globaux** → déployés. MatchUpdate / roster → tous (menu). Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready (nouveaux, N26–N32)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N16 et N17/N18/N19/N20/N22/N25 restent ouverts.** N21/N23/N24 = faits §3.

---

### ISSUE-N26 — `SAM_INTERCEPT_CHANCE` Config 0.55 vs apply 1.0

**Priorité :** P1 honesty / identité nucléaire.

**Problème :** `Config.SAM_INTERCEPT_CHANCE = 0.55`. `ChantierB.apply` force **1.0**. En prod, tout missile dans `SAM_RANGE` (70 après apply) est intercepté. Les nukes ne passent que hors portée ou par saturation MIRV. Un tuner qui lit Config croit encore à 45 % de fuites.

**Pourquoi 20K CCU :** identité de fin de partie fausse → tilt, rage-quit, tickets « SAM OP ». Ce n’est pas un buff documenté.

**Worker :**

1. Décision : (A) garder 100 % OF et **écrire 1.0 dans Config** + README, (B) ramener apply à 0.55 et retuner range/CD, (C) garder le drift et documenter dans Config (commentaire déjà posé cette passe).
2. Si (A) ou (B) : un seul littéral. Test `Nukes` : SAM in-range vs out-of-range, même graine.
3. Fichiers : `Config.luau`, `ChantierB.luau`, `Nukes.luau`, `tests/simulate.luau`.

**Contraintes :** ne pas mixer avec N1 (fusion Config). Ne pas changer `SAM_RANGE` / cooldown dans le même PR que le roll du chance.

---

### ISSUE-N27 — Commerce terrestre ignore l’embargo

**Priorité :** P2 honesty éco / anti-grief.

**Problème :** `Navy.canTrade` coupe les routes maritimes. `Trade.luau` (camions / trains) **ne lit jamais** `state.embargoes`. Config commente « embargo coupe les revenus » ; `Diplomacy.luau` documente maritime-only. Un embargo allié (N19) ou non ne touche pas l’or usine.

**Pourquoi 20K CCU :** levier diplomatique mort sur la majeure partie de l’éco (rails >> bateaux commerce).

**Worker :**

1. Décision : (A) embargo aussi sur `Trade.resolve` / spawn colis, (B) maritime-only et corriger Config/HUD.
2. Test simulate : usine + embargo → (A) pas de pay, (B) pay inchangé + commentaire Config.
3. Fichiers : `Trade.luau` et/ou `Config.luau`, `tests/simulate.luau`.

**Contraintes :** ticket de design. Ne pas mixer avec N19 (allié) ni N20 (HUD).

---

### ISSUE-N28 — `RequestSnapshot` mort côté client (étend N4)

**Priorité :** P2 resync.

**Problème :** le serveur rate-limite (5 s, 12/match) et envoie `OwnerSnapshot` + `structureHash`. **Aucun** `FireServer("RequestSnapshot")` client. `structureHash` est `_` ignoré. Un client désynchronisé n’a pas de bouton / retry.

**Pourquoi 20K CCU :** un seul client drifté spam en vain s’il existait un retry auto ; aujourd’hui il reste faux jusqu’à reconnexion. 8 humains × overlay bâtiments faux = support.

**Worker :**

1. Client : retry borné (ex. après 3 deltas incohérents, ou bouton HUD debug) via le remote existant.
2. Appliquer `structureHash` : si mismatch, demander un `BuildingDelta` full ou rejouer overlay.
3. Tests : pas d’E2E bundle pour le remote. Extraire un helper de hash testable ; documenter Studio.
4. Fichiers : `init.client.luau`, `Overlay.luau` / `WorldRenderer.luau`, éventuellement `init.server.luau`.

**Contraintes :** respecter cooldown/quota. Pas de RemoteFunction. Ne pas envoyer toute la carte bâtiments en clair à 10 Hz.

---

### ISSUE-N29 — Séquence commitée avant le résultat métier

**Priorité :** P3 idempotence.

**Problème :** `IntentValidator.enqueue` écrit `lastSequence` **puis** `applyOne`. Un apply qui refuse (or, cible, cooldown QuickChat) a déjà consommé le numéro. Le client incrémente ; pas d’exploit de doublon, mais l’idempotence « même seq = même intent » est trouée pour le debug.

**Worker :**

1. Commit seq seulement si apply `ok`, **ou** garder le commit et documenter « seq = accepté schéma, pas métier ».
2. Si on recule le commit : rejouer le test cooldown QuickChat (enqueue 2e doit rester ok schéma, apply false).
3. Fichiers : `IntentValidator.luau`, `tests/simulate.luau`.

**Contraintes :** ne pas casser DuplicateSequence / StaleSequence. Feel apply immédiat inchangé.

---

### ISSUE-N30 — Stub `GameState.seedBeachhead` encore faux

**Priorité :** P3 hygiène.

**Problème :** le vivant est `BoatFront.install`. Le stub de `GameState.luau` enfile encore la tuile d’atterrissage et fusionne avec un front terre. Un test / outil qui saute `SystemsBootstrap.install()` réintroduit le bug #22.

**Worker :**

1. Stub = `error("BoatFront.install() requis")` **ou** déléguer la même logique que BoatFront (voisins + `isBeachhead`, jamais merge terre).
2. Ne pas dupliquer deux implémentations vivantes.
3. Fichiers : `GameState.luau`. Commentaire déjà posé cette passe.

**Contraintes :** ne pas casser le test beachhead (il passe par BoatFront).

---

### ISSUE-N31 — `attackLogic` scan O(#buildings) par pop de heap

**Priorité :** P1 perf combat.

**Problème :** chaque tuile combattue (`guard < 80` × N fronts) itère **tous** les bâtiments pour trouver un bunker dans `DEFENSE_RADIUS` (30). Pas d’index spatial. 18 factions × villes/SAM/usines × 80 pops.

**Pourquoi 20K CCU :** hotspot #1 du tick sous pression humaine (le banc bots sous-estime : `p95TickMs` headless ≈ 1 ms). Couplé à `tryAnnex` 280 nœuds / capture et `stepDoomsday` O(TILE_COUNT).

**Worker :**

1. Index `defensePostsBySlot` maintenu dans `placeBuilding` / `destroyBuilding` / `setOwner` transfer.
2. `attackLogic` ne scanne que cet index (ou grille cellule 16).
3. Banc 6000 ticks : `p95TickMs` ne doit pas monter ; ajouter un micro-bench « 200 bunkers, 20 fronts ».
4. Fichiers : `ChantierB.luau`, `GameState.luau`, `tests/simulate.luau`.

**Contraintes :** déterminisme. Ne pas changer `DEFENSE_POST_BONUS`. Ne pas mixer avec N16 (buffer defense / sea path).

---

### ISSUE-N32 — `viewFor` propose des requests expirées

**Priorité :** P3 HUD.

**Problème :** `Diplomacy.accept` refuse l’expiry (passe 4). `viewFor` copie `state.requests` sans filtrer `tick >= expiry`. Le HUD peut afficher un bouton Accepter fantôme jusqu’au prochain `Diplomacy.step`.

**Worker :**

1. Filtrer dans `viewFor` (et incoming) `expiry > state.tick`.
2. Test : request périmée absente de `viewFor` même avant `step`.
3. Fichiers : `Diplomacy.luau`, `tests/simulate.luau`.

**Contraintes :** ne pas changer `ALLIANCE_REQUEST_TIMEOUT`. Server-authoritative (le HUD n’accepte pas tout seul).

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert |
| N10 | Divers P3 | P3 | ouvert ; embargo trains → N27 |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | ouvert |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 factions) | P1 | ouvert |
| N13 | Parité combat (ère / cost factor / constantes mortes) | P2 | ouvert |
| N14 | Apply immédiat vs lockstep (feel #19) | P1 | ouvert (produit) |
| N15 | `PREPARATION_DURATION=0` vs gardes `combatUnlocked` | P2 | ouvert |
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 | ouvert ; scan bunkers → N31 |
| N17 | Humains éliminés occupent le cap | P2 | ouvert |
| N18 | Heap AimFront ≠ ChantierB / BoatFront | P2 | ouvert |
| N19 | Embargo allié + tribus auto-accept | P2 | ouvert |
| N20 | `railIncome` vs `deliveryValue` | P2 | **affiné** : `stopBonus` + live level ; `× links` déjà là |
| N21 | QuickChat 2-args | P3 | **fait** cette passe |
| N22 | Warships O(carriers × boats) | P2 | ouvert |
| N23 | `retreatAttack` premier front | P2 | **fait** cette passe |
| N24 | notify/sfx `FireAllClients` | P2 | **fait** cette passe |
| N25 | `MAX_BOATS_PER_PLAYER` 6 vs 3 | P3 | ouvert |

Textes worker-ready N1–N20, N22, N25 : PR #21 / #22 `NIGHTLY_REPORT.md` historique. Ne pas les dupliquer ici.

---

## 6. Drift Config → `ChantierB.apply` (extrait)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | formule custom |
| `MAX_TILES_PER_TICK` | 400 | 56 | **non** (`guard<80`) |
| `DEFENSE_RADIUS` | 6 | 30 | oui (scan buildings, N31) |
| `BOAT_TROOP_RATIO` | 0.2 | 0.2 | oui |
| `RETREAT_LOSS` | 0.25 | 0.25 | oui |
| `SAM_INTERCEPT_CHANCE` | 0.55 (commentaire N26) | **1.0** | oui |
| `SAM_RANGE` | 34 | 70 | oui |
| `TRUCK_GOLD_BASE` | 10 | 14 | oui |
| `TRAIN_STOP_BONUS` | absent Config | 0.12 | Trade oui ; HUD **non** (N20) |
| `MAX_BOATS_PER_PLAYER` | 6 | 6 | oui (N25) |
| `PREPARATION_DURATION` | 0 | 0 | forcé true |

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
beachhead : frontier voisins, pas de remboursement
aim reinforce : un seul front apres deux lancers
colis snapshot : niveau au depart honore
accept expire : proposition perimee refusee
retraite couple : terre + tete de pont marques
refund disconnect : troupes restituees a l'attaquant
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=7.4 p95Changed=6 maxChanged=790 avgTickMs=0.30 p95TickMs=0.60
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **34/34 OK** — tous les écrans se construisent et s’exécutent sans erreur.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass5.log`


---

## 8. Require DAG (re-vérifié)

Pas de cycle. `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes.
