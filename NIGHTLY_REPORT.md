# CONQUEST RTS — Rapport nocturne (2026-08-26, passe 6)

Déclencheur : ouverture de la **PR #24** (`cursor/analyse-nocturne-du-codebase-a9d9`) — retraite couple, QuickChat 3-args, refund disconnect, specs N26–N32.

Branche de ce rapport : `cursor/analyse-nocturne-du-codebase-ec34`.
`gh` est en lecture seule : les issues ci-dessous sont des **spec worker-ready**. Aucun commentaire n’a pu être posté sur #16–#24.

---

## 1. Verdict

Le moteur reste **server-authoritative**. Aucun `RemoteFunction`. Aucun **cycle de `require`**. Les clients n’envoient que tuile / kind / sequence ; or, troupes et slot cible sont dérivés serveur.

**Feel #19 conservé :** `PREPARATION_DURATION = 0`, `combatUnlocked` dès le déploiement, intentions **appliquées à l’enqueue**.

**20K CCU** = ~1 700 shards × 8 humains / 12 factions publiques (+ 6 tribus = **18** slots Classique), pas un monde unique.

**PR #24 (passe 5) : claims vérifiés.** Retraite couple, QuickChat 3-args, refund défenseur, notify/sfx `fireDeployed`. Combat vivant = `ChantierB.stepAttacks`. `MAX_TILES_PER_TICK` non lu par le combat installé.

Banc headless (`./tests/run.sh`) : voir §7.

---

## 2. Revue PR #24

| Claim #24 | Réalité à l’ouverture |
|---|---|
| `removePlayer` défenseur restitue `atk.troops` | Oui. Manquait le GC des propositions *vers* le slot (corrigé ici). |
| `retreatAttack` marque tout le couple | Oui, testé. |
| QuickChat `needsTarget` exige sequence | Oui, testé. |
| notify/sfx → `fireDeployed` | Oui. MatchUpdate / Roster restent `FireAllClients` (menu). |
| Specs N26–N32 | N26 chance, N30, N32 **corrigés ici**. N20 `stopBonus` HUD **corrigé**. N27 documenté maritime-only. |

PRs ouvertes au moment de la revue : #16 P0, #17/#18 nightly P0, #19 feel, #20/#23 hardening, #21/#22/#24 feel. **#24 + cette passe** est le sur-ensemble feel à merger. La ligne P0 sans feel (#16←#20←#23) reste distincte.

---

## 3. Correctifs livrés (sûrs, server-authoritative)

| Bug | Fichiers | Pourquoi 20K CCU / autorité |
|---|---|---|
| `launchAttack` pouvait fusionner dans une tête de pont | `GameState.luau` | Defense-in-depth si `BoatFront` park absent : troupes de débarquement avalées par un clic terre |
| Stub `seedBeachhead` encore faux (N30) | `GameState.luau` | Un outil sans bootstrap réintroduit skip+refund |
| `viewFor` exposait les requests expirées (N32) | `Diplomacy.luau` | Bouton Accepter fantôme ; feel apply honore `accept` avant `Diplomacy.step` |
| `removePlayer` laissait propositions / embargos / marques vers le disparu | `GameState.luau` | HUD et `canTrade` gardaient des cibles fantômes |
| HUD `railIncome` sans `TRAIN_STOP_BONUS` (N20) | `GameState.luau` | "+x/s" menteur dès 2+ liaisons |
| `SAM_INTERCEPT_CHANCE` Config 0.55 vs apply 1.0 (N26) | `Config.luau` | Tuner lisait 45 % de fuites ; prod = 100 % dans `SAM_RANGE` |
| Embargo commenté comme revenu global (N27 doc) | `Config.luau` | Aligné sur `Navy.canTrade` (maritime-only) |

**Non modifié (volontaire) :** apply immédiat (N14), câblage `MAX_TILES_PER_TICK` (N11), coalescence stats (N2), DataStore (N6), tribus vs capa (N12), fusion Config/ChantierB (N1), cap humains éliminés (N17), heap AimFront (N18), embargo allié (N19), warships grille (N22), MAX_BOATS (N25), scan bunkers (N31), RequestSnapshot client (N28), seq avant apply (N29).

---

## 4. Cartographie

```
init.server  → IntentValidator.enqueue (apply immédiat) → tick : Bots/Navy/Nukes/Trade/Diplomacy → GameState.step → replicate(fireDeployed)
SystemsBootstrap.install()  monkey-patch : ChantierB (combat/éco/spawn/doom), BoatFront, AimFront, tribus, spawn bots différé 15 s
```

- **Combat vivant** = `ChantierB.stepAttacks`, pas le corps de `GameState.stepAttacks`.
- **Vérité d’équilibrage** = `ChantierB.apply(Config)` après `install()`, pas `Config.luau` seul.
- **Beachhead vivant** = `BoatFront.seedBeachhead` : frontier = voisins encore à la cible, flag `isBeachhead`. Stub = `error(...)`.
- **Réplication :** StateDelta / UnitSnapshot / BuildingDelta / plunder / trade / explosions / notify&sfx déployés. MatchUpdate / roster → tous (menu). Playing 10 Hz ; lobby vide et ended → 1 Hz.

---

## 5. Issues worker-ready (nouveaux, N33–N35)

`gh issue create` n’est pas disponible. Copier chaque bloc. **N1–N16, N17–N19, N22, N25, N28, N29, N31 restent ouverts.** N20/N26/N30/N32 = faits §3. N27 = doc only.

---

### ISSUE-N33 — `BOAT_LANDING_BONUS` mort

**Priorité :** P2 honesty marine / parité OF.

**Problème :** `Config.BOAT_LANDING_BONUS = 1.35` n’est **jamais lu**. `Navy.resolveLanding` pose la tuile puis `seedBeachhead` ; le combat côtier utilise le même `attackLogic` que la terre. Un tuner croit taxer le débarquement ; la cote n’est pas plus chère.

**Pourquoi 20K CCU :** invasions sous-coûtées → snowball îles / continents, tickets « boats OP ». Identité OF `landing` non honorée.

**Worker :**

1. Décision : (A) multiplier le coût / les pertes du premier tick côtier par 1.35 dans `attackLogic` si `atk.isBeachhead`, (B) appliquer au `committed` de `resolveLanding`, (C) supprimer la constante et le commentaire.
2. Test : débarquement vs front terre, même troupes, même tuile ; (A/B) pertes ou débit distincts, (C) plus de symbole.
3. Fichiers : `Config.luau`, `Navy.luau` et/ou `ChantierB.luau`, `tests/simulate.luau`.

**Contraintes :** ne pas mixer avec N5 (cap beachheads) ni N25 (MAX_BOATS). Server-authoritative. Commentaire « Mort » déjà posé cette passe.

---

### ISSUE-N34 — `areAllied` ignore l’expiry du pacte

**Priorité :** P2 autorité diplomatie / feel apply.

**Problème :** `alliances[a][b]` stocke le tick d’expiry. `areAllied` teste seulement la présence des deux directions. `Diplomacy.step` purge ensuite. Feel apply immédiat : un `Attack` reçu **entre** l’échéance et `Diplomacy.step` (début du tick suivant) est encore refusé (« Tu es allie »). Inverse de N32 : ici le HUD/l’ordre sont **trop** stricts d’un tick, pas trop lâches.

**Pourquoi 20K CCU :** 100 ms de pacte fantôme. Faible en isolation ; couplé à apply immédiat, le premier clic guerre après expiry « ne marche pas » → double-clic, rage. `launchAttack` / `Navy.resolveLanding` / dons lisent tous `areAllied`.

**Worker :**

1. **Porter** le garde hardening (branche `5233` / passe 5-hardening) : `areAllied` exige `tick < expiry` (legacy `true` reste vivant). Ne pas réinventer.
2. Ne pas compter ça comme trahison (déjà le cas dans `Diplomacy.step`).
3. Test existant `alliances — le pacte ne tombe jamais` : étendre **sans** `Diplomacy.step`, `tick = ALLIANCE_DURATION` → `areAllied` false, `launchAttack` ok.
4. Fichiers : `GameState.luau`, `tests/simulate.luau`.

**Contraintes :** ne pas casser le test « expire avant son terme » (`tick = DURATION - 1`). Ne pas mixer avec N19 (embargo allié). Feel apply inchangé.

---

### ISSUE-N35 — `applyDefenseAura` écrit un buffer que le combat vivant ignore

**Priorité :** P2 perf + honesty (étend N16).

**Problème :** `placeBuilding` / `destroyBuilding` d’un bunker appellent `applyDefenseAura`, qui balaie un disque `DEFENSE_RADIUS` (30 après apply) et écrit `state.defense`. `ChantierB.attackLogic` **ne lit jamais** ce buffer : il re-scanne `state.buildings` (N31). `GameState.tileCost` (mort) le lisait. CPU payé deux fois, aura gradient vs bonus binaire OF.

**Pourquoi 20K CCU :** pose/destruction bunker = O(πr²) + chaque pop de heap = O(#buildings). Sous 8 humains le banc bots (p95 ≈ 0.6 ms) sous-estime.

**Worker :**

1. Décision : (A) `attackLogic` lit `state.defense` et on **supprime** le scan buildings, (B) on **supprime** `applyDefenseAura` et on garde N31 index, (C) les deux temporairement mais aura non appelée hors bootstrap skip.
2. (A) change le feel (gradient vs binaire) — **ticket de design**, pas un drive-by.
3. Fichiers : `GameState.luau`, `ChantierB.luau`, `tests/simulate.luau`.

**Contraintes :** ne pas mixer avec N31 (index) dans le même PR si (A). Déterminisme. Ne pas changer `DEFENSE_POST_BONUS`.

---

## 5b. Backlog encore ouvert

| ID | Titre | Prio | Statut |
|---|---|---|---|
| N1 | Source unique Config vs `ChantierB.apply` | P1 | ouvert (SAM chance aligné ; range/CD encore driftés) |
| N2 | Delta `stats` + UnitSnapshot dirty | P1 | ouvert |
| N3 | Timebase tick vs `os.clock()` | P1 | ouvert |
| N4 | Resync bâtiments (`structureHash` ignoré) | P1 | ouvert ; étendu N28 |
| N5 | Beachheads hors `MAX_ACTIVE_ATTACKS_PER_PLAYER` | P2 | ouvert |
| N6 | DataStore debounce / retry / merge additif | P2 | ouvert |
| N7 | Matchmaking 20K CCU (MemoryStore / Teleport) | P2 | ouvert |
| N8 | Combat mort vs combat vivant | P2 | ouvert |
| N9 | `stepDoomsday` O(TILE_COUNT) par faction | P2 | ouvert |
| N10 | Divers P3 | P3 | ouvert |
| N11 | Câbler ou supprimer `MAX_TILES_PER_TICK` | P1 | ouvert |
| N12 | Tribus vs `PUBLIC_MATCH_CAPACITY` (18 factions) | P1 | ouvert |
| N13 | Parité combat (ère / cost factor / constantes mortes) | P2 | ouvert |
| N14 | Apply immédiat vs lockstep (feel #19) | P1 | ouvert (produit) |
| N15 | `PREPARATION_DURATION=0` vs gardes `combatUnlocked` | P2 | ouvert |
| N16 | Buffer `defense` vs scan bunkers + `findSeaPath` 40k | P2 | ouvert ; aura → N35 |
| N17 | Humains éliminés occupent le cap | P2 | ouvert |
| N18 | Heap AimFront ≠ ChantierB / BoatFront | P2 | ouvert |
| N19 | Embargo allié + tribus auto-accept | P2 | ouvert |
| N20 | `railIncome` vs `deliveryValue` | P2 | **fait** `stopBonus` ; reste niveau live vs snapshot colis |
| N21 | QuickChat 2-args | P3 | **fait** passe 5 |
| N22 | Warships O(carriers × boats) | P2 | ouvert |
| N23 | `retreatAttack` premier front | P2 | **fait** passe 5 |
| N24 | notify/sfx `FireAllClients` | P2 | **fait** passe 5 |
| N25 | `MAX_BOATS_PER_PLAYER` 6 vs 3 | P3 | ouvert |
| N26 | SAM chance 0.55 vs 1.0 | P1 | **fait** Config=1.0 |
| N27 | Embargo land trade | P2 | **doc** maritime-only ; (A) land embargo si produit le veut |
| N28 | `RequestSnapshot` mort client | P2 | ouvert |
| N29 | Seq commitée avant apply | P3 | ouvert |
| N30 | Stub `seedBeachhead` faux | P3 | **fait** `error(...)` |
| N31 | Scan bunkers O(B) | P1 | ouvert |
| N32 | `viewFor` requests expirées | P3 | **fait** |
| N33 | `BOAT_LANDING_BONUS` mort | P2 | **nouveau** |
| N34 | `areAllied` ignore expiry pacte | P2 | **nouveau** |
| N35 | `applyDefenseAura` buffer mort | P2 | **nouveau** |

Textes worker-ready N1–N25, N28, N29, N31 : PR #21 / #22 / #24 `NIGHTLY_REPORT.md` historique.

---

## 6. Drift Config → `ChantierB.apply` (extrait)

| Clé | Config | Après apply | Lu en prod ? |
|---|---|---|---|
| `START_TROOPS` | 150 | 8000 | oui |
| `GROWTH_RATE` | 0.012 | 0 | formule custom |
| `MAX_TILES_PER_TICK` | 400 | 56 | **non** (`guard<80`) |
| `DEFENSE_RADIUS` | 6 | 30 | scan buildings (N31), pas le buffer (N35) |
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
railIncome bonus : TRAIN_STOP_BONUS dans l'estime HUD
accept expire : proposition perimee refusee
viewFor expire : request perimee absente du HUD
retraite couple : terre + tete de pont marques
refund disconnect : troupes restituees a l'attaquant
removePlayer GC : propositions vers disparu nettoyees
beachhead merge : front terre separe, troupes de pont intactes
combat vivant : MAX_TILES_PER_TICK=56 (inutilise) attackTilesPerTick(10k,nil,1)=2 guard=80
metrics : ticks=6000 avgChanged=7.4 p95Changed=6 maxChanged=790 avgTickMs=0.30 p95TickMs=0.62
MAX_TILES_PER_TICK reste 56
Tous les invariants tiennent.
```

Client : **34/34 OK** — tous les écrans se construisent et s’exécutent sans erreur.

Artefact : `/opt/cursor/artifacts/headless-tests-nightly-pass6.log`

---

## 8. Require DAG (re-vérifié)

Pas de cycle. `ChantierB` / `BoatFront` / `AimFront` dans ReplicatedStorage (`install()` serveur seulement). `IntentValidator` ne require pas `GameState`. `Research` reste sans Remotes.
