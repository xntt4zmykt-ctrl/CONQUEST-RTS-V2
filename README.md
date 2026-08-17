# CONQUEST RTS

Jeu de conquête territoriale temps réel sur Roblox, par **Blackline Studio**.

Inspiré du genre `.io` de conquête de territoire (OpenFront, Territorial.io), poussé
plus loin : économie maritime, diplomatie mécanique, réputation persistante et
phase nucléaire.

---

## Pitch

> **Conquiers le monde. Trahis tes alliés.**
> Commence avec une seule province. Fais croître ta population, lance des offensives,
> construis des ports et des silos nucléaires. Négocie des traités — puis
> brise-les au pire moment.
>
> 🌍 48 joueurs par carte · ⚔️ Parties de 25 minutes · 🤝 Alliances réelles
> ☢️ Fin de partie nucléaire · 🏆 Réputation persistante
>
> Ta réputation te suit d'une partie à l'autre. Choisis bien.

---

## Lancer le projet

Prérequis : [Aftman](https://github.com/LPGhatguy/aftman) et le plugin **Rojo**
dans Roblox Studio.

```bash
cd "/Users/billy/Documents/CONQUEST RTS" && aftman install && rojo serve
```

Puis, dans Studio : onglet Rojo → **Connect**. Chaque sauvegarde de fichier est
répercutée immédiatement dans le DataModel.

Teste avec **Play Solo** : 12 bots peuplent la carte, construisent, débarquent,
s'allient et se trahissent. La partie est jouable et observable sans autre joueur.

### Commandes

| Touche | Action |
|---|---|
| `ZQSD` / `WASD` / flèches | Déplacer la vue |
| Molette | Zoom |
| `A` / `E` | Pivoter la caméra |
| Clic | Agir sur la tuile, selon le mode armé |
| `1` `2` `3` `4` | Attaquer · Débarquer · Construire · Nucléaire |
| `Espace` | Recentrer sur ta capitale |
| `F` | Basculer vue stratégique ↔ avatar |
| `G` | Défilement par les bords de l'écran |

---

## Tests

La simulation serveur tourne **hors de Studio**, dans le Luau standard :

```bash
brew install luau && ./tests/run.sh
```

`tests/bundle.js` assemble les modules partagés et serveur en un seul fichier
exécutable (les `require` de Roblox désignent des Instances, pas des chemins :
ils sont réécrits), `tests/stubs.luau` bouchonne les API Roblox utilisées, et
`tests/simulate.luau` joue cinq parties complètes en vérifiant des invariants.

Les invariants ciblent la classe de bug la plus dangereuse ici : **la
comptabilité incrémentale**. `tiles`, `border`, `coast`, `portCount` sont
maintenus à la main à chaque capture ; s'ils dérivent de la réalité du buffer
`owner`, l'équilibrage se fausse silencieusement sans jamais lever d'erreur.

Le dossier `tests/` n'est pas monté dans `default.project.json` : rien de tout
ça n'est synchronisé vers Roblox.

---

## Architecture

```
ReplicatedStorage/Shared/
  Config.luau       Toutes les constantes d'équilibrage (le seul fichier à tuner)
  Theme.luau        Jetons de design : couleurs, espacements, typographie, animation
  Audio.luau        Catalogue sonore
  MapGen.luau       Génération de carte déterministe à partir d'une seed
  GreedyMesh.luau   Fusion de tuiles en rectangles (partagée serveur/client)
  WorldSpace.luau   Conversions grille ↔ monde 3D
  Doctrines.luau    Les quatre doctrines et leurs multiplicateurs
  BuildingDefs.luau Définitions et coûts des bâtiments
  Remotes.luau      Création/récupération des RemoteEvents
  Types.luau        Types partagés serveur ↔ client

ServerScriptService/Server/
  init.server.luau  Orchestration : ordres, boucle de tick, réplication, match
  GameState.luau    État autoritaire : territoire, population, économie, offensives
  Buildings.luau    Validation et pose des bâtiments
  Navy.luau         Débarquements, pathfinding maritime, commerce
  Nukes.luau        Tirs, interception SAM, détonation
  Diplomacy.luau    Alliances, trahisons, embargos
  Persistence.luau  Réputation persistante (DataStore)
  WorldBuilder.luau Collision statique du monde
  Bots.luau         IA de remplissage

StarterPlayerScripts/Client/
  init.client.luau  Orchestration : saisie des ordres, réseau, avatar
  WorldRenderer.luau Géométrie colorée du monde, par chunks
  WorldCamera.luau  Caméra stratégique et sélection par lancer de rayon
  Overlay.luau      Bâtiments, navires, missiles, explosions
  Minimap.luau      Vue d'ensemble (facultative)
  HUD.luau          Commandement, construction, diplomatie, classement
  VictoryScreen.luau Écran de fin de partie
  SoundManager.luau Lecture sonore : bridage, variation, recyclage
```

### Décisions structurantes

**La carte est un buffer plat, pas des instances.** 256×160 = 40 960 tuiles.
`terrain`, `owner` et `defense` sont trois `buffer` d'un octet par tuile. Aucune
Part, aucun Instance par tuile.

**On réplique la seed, pas la carte.** Serveur et client appellent
`MapGen.generate(seed)` et obtiennent un résultat identique. 4 octets au lieu de 40 Ko.

**On ne réplique que les deltas.** Chaque tick, le serveur envoie les tuiles ayant
changé de main au format `[u32 index][u8 slot]`.

**Tout le travail par tick est en O(tuiles modifiées), jamais en O(carte).** Les
ensembles `border` et `coast` de chaque joueur sont maintenus à l'incrémentale.
C'est ce qui permet de tenir 40 000 tuiles à 10 ticks/seconde.

**Le monde est de la vraie géométrie.** 256×160 tuiles sur 4 studs donnent un
monde de 1024×640 studs, posé dans le Workspace. On y navigue en caméra
stratégique, et on peut y descendre avec son avatar (touche F).

**40 960 tuiles ne peuvent pas être 40 960 Parts.** Les tuiles voisines de même
couleur et même relief sont fusionnées en rectangles par
[GreedyMesh.luau](ReplicatedStorage/Shared/GreedyMesh.luau). Mesuré sur une
partie de fin de match : **1 337 Parts pour 17 319 tuiles de terre**, soit une
compression de 13×.

**Le relief ne change jamais, seule la couleur change.** C'est ce qui permet de
séparer les responsabilités :

| | Contenu | Coût |
|---|---|---|
| Serveur | Collision invisible, fusionnée par relief seul | 311 blocs, répliqués une fois |
| Client | Géométrie colorée, fusionnée par relief + propriétaire | 1 337 Parts, locale |

Sans collision serveur, un avatar posé sur sa capitale tomberait indéfiniment :
le rendu du client est local, le serveur n'en voit rien.

**Les reconstructions sont locales et étalées.** Une conquête ne salit que les
chunks concernés, et le budget est de 3 chunks par frame — parce qu'une grande
offensive en salit des dizaines dans le même tick, exactement quand le joueur
regarde l'écran.

**Le rendu reste isolé de la simulation.** `WorldRenderer` et `Overlay` ne
connaissent rien du jeu : le passage du 2D au 3D n'a touché aucune ligne de
`GameState`, `Navy`, `Nukes` ou `Diplomacy`.

**Simulation à pas fixe.** 10 ticks/seconde avec accumulateur : l'équilibrage ne
dépend pas du FPS serveur.

### Modèle d'attaque

On n'ordonne pas des unités, on engage un **corps expéditionnaire** contre une
faction. Les troupes engagées quittent immédiatement la réserve — elles ne
défendent plus. C'est la décision tactique centrale du jeu.

Le coût d'une tuile dépend du terrain, des bunkers alentour, de la doctrine des
deux camps, et surtout de la **densité de troupes** du défenseur
(`troupes / territoires`) — ce qui punit l'expansion incontrôlée et récompense
l'empire compact.

### Diplomatie

Les traités sont **mécaniques**, pas déclaratifs. Une alliance empêche
réellement l'attaque au niveau du moteur ; pour frapper un allié il faut rompre
le pacte publiquement, ce qui laisse à la victime le temps de réagir et inscrit
la trahison au compteur permanent du traître (DataStore, visible dans le
classement de toutes les parties suivantes).

L'embargo donne à la diplomatie un poids économique : couper les routes
commerciales d'un rival lui retire de l'or à chaque tick.

---

## État actuel

**Fait** : génération de carte · spawn · population · offensives · marine et
débarquements avec pathfinding maritime · économie et commerce · capitales ·
5 bâtiments · 4 doctrines · alliances, trahisons, embargos · réputation
persistante · phase nucléaire avec interception · élimination · condition de
victoire et relance automatique · bots complets · rendu enrichi, minimap, HUD,
écran de victoire, sons, classement, notifications.

**Pas encore fait**, par ordre de priorité :

1. **Chat vocal de proximité** pour les négociations.
2. **Navires de guerre** — actuellement les transports sont inarrêtables en mer.
3. **Modèles de bâtiments** — ce sont pour l'instant des piliers colorés.
4. **Brouillard de guerre.**
5. **Saisons et classement de clans.**

### Limites connues

⚠️ **L'équilibrage n'a pas été playtesté par des humains.** Les valeurs de
`Config.luau` ont été réglées contre la simulation headless uniquement. Les
premiers paramètres à revoir : `ATTACK_SPEND_RATE`, `GROWTH_RATE`,
`DEFENSE_DENSITY_K` et `GOLD_TILE_SCALE`.

⚠️ **Les parties contre des bots seuls se terminent en 5 à 10 minutes**, bien
avant les 25 minutes prévues — les bots ne se coalisent pas contre le leader.

⚠️ **Le coût de rendu n'a été mesuré qu'en simulation**, pas sur un vrai
appareil. `./tests/run.sh` reporte le nombre de Parts en fin de rapport ; si tu
changes `TILE_SIZE` ou `CHUNK_SIZE`, relance-le pour vérifier que ça tient.

⚠️ **Les symboles de bâtiments sont des caractères Unicode.** S'ils ne
s'affichent pas correctement dans Studio, remplacer `symbol` dans
`BuildingDefs.luau` par des images.

⚠️ **DataStore désactivé en Studio** tant que l'accès API n'est pas activé. La
réputation est alors conservée en mémoire pour la session, sans erreur bloquante.

⚠️ **Les sons sont des doublures.** `Audio.luau` référence les sons intégrés au
moteur (`rbxasset://sounds/...`) : aucun upload nécessaire, retour audible
immédiat, mais ce sont des sons utilitaires génériques, pas du design sonore.
Pour du vrai son, remplacer les `id` par des `rbxassetid://` du Creator Store —
rien d'autre à changer. Un identifiant absent du client est désactivé
automatiquement au premier échec, sans casser le jeu.
