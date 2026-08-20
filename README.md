# CONQUEST RTS

Jeu de conquête territoriale temps réel sur Roblox, par **Blackline Studio**.

Inspiré du genre `.io` de conquête de territoire (OpenFront, Territorial.io), poussé
plus loin : économie maritime, diplomatie mécanique, réputation persistante et
phase nucléaire.

---

## Pitch

> **Conquiers le monde. Trahis tes alliés.**
> Commence avec une seule province. Fais croître ta population, lance des offensives,
> fais évoluer tes villes en métropoles puis en mégapoles, connecte des usines par
> des routes logistiques, construis des ports et des silos nucléaires. Négocie des traités — puis
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

Teste avec **Play Solo** : la carte reste figée tant que le menu est ouvert,
puis 11 bots rejoignent le commandant dans le mode Classique. Ils construisent,
débarquent, s'allient et se trahissent sans obtenir de faux départ.

### Commandes

| Touche | Action |
|---|---|
| `ZQSD` / `WASD` / flèches | Déplacer la vue |
| Molette | Zoom |
| `A` / `E` | Pivoter la caméra |
| Clic droit maintenu | Orbiter (rotation + inclinaison) |
| `R` / `T` | Incliner la caméra |
| Clic | Agir sur la tuile, selon le mode armé |
| `1` `2` `3` `4` | Attaquer · Débarquer · Construire · Nucléaire |
| `Espace` | Recentrer sur ta capitale |
| `F` | Basculer vue stratégique ↔ avatar |
| `G` | Défilement par les bords de l'écran |

Sur **tactile** : un doigt glisse pour déplacer la vue, pincement pour zoomer,
torsion à deux doigts pour pivoter, tap pour agir, appui long pour le menu
radial. Une barre d'action en bas d'écran (modes + retour à la capitale)
remplace les raccourcis clavier — elle n'existe que sur appareil tactile sans
clavier, le bureau garde le bas de l'écran libre.

Au lancement : **menu principal** (nation + mode) → écran de chargement pendant
la construction du monde → compte à rebours de 5 s → partie.

Le survol tactique colore la case avant l'ordre : couleur d'action si la cible
est exploitable, rouge si elle est manifestement invalide. Le centre de commande
affiche aussi le nombre de fronts et les troupes qui ne défendent plus la réserve.

---

## Tests

La simulation serveur tourne **hors de Studio**, dans le Luau standard :

```bash
brew install luau && ./tests/run.sh
```

Deux bancs d'essai tournent :

**Serveur** — `tests/simulate.luau` joue cinq parties complètes en vérifiant des
invariants, et mesure le rythme des ères et le coût en Parts.

**Client** — `tests/client.luau` construit chaque écran et rejoue le parcours
complet (menu → chargement → jeu → fin de partie). Il ne vérifie pas
l'apparence : il vérifie que **rien ne lève d'erreur**. C'est la classe de bug
qui a le plus coûté — une propriété mal nommée dans un module d'interface se
présente au joueur comme un écran noir muet, et n'apparaît nulle part ailleurs.

`tests/bundle.js` assemble les modules en un fichier exécutable (les `require`
de Roblox désignent des Instances, pas des chemins : ils sont réécrits),
`tests/stubs.luau` et `tests/guistubs.luau` bouchonnent les API utilisées.

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
  Eras.luau         Les cinq ères technologiques et leurs conditions
  Nations.luau      Nations jouables et leurs drapeaux (dessinés, pas importés)
  GameModes.luau    Classique · Blitz · Marathon
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
  Research.luau     Avancement d'ère : conditions, coûts, progression
  WorldBuilder.luau Collision statique du monde
  Bots.luau         IA de remplissage

StarterPlayerScripts/Client/
  init.client.luau  Orchestration : saisie des ordres, réseau, avatar
  WorldRenderer.luau Géométrie colorée du monde, par chunks
  WorldCamera.luau  Caméra stratégique et sélection par lancer de rayon
  BuildingModels.luau Modèles 3D procéduraux et animation de chantier
  PlacementPreview.luau Fantôme de construction suivant le curseur
  Effects.luau      Éclats de conquête, ondes, textes flottants
  MainMenu.luau     Choix de nation et de mode
  Intro.luau        Écran de chargement et compte à rebours
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

### Génération de terrain

Quatre mécanismes se combinent, chacun corrigeant un défaut précis :

- **Déformation du domaine** — on perturbe les coordonnées avant de tirer le
  bruit. Un bruit fractal brut donne des côtes molles et arrondies ; la
  déformation les étire en péninsules, golfes et fjords.
- **Masque continental** — décide où la terre a le droit d'exister. Sans lui,
  l'atténuation radiale produisait une seule masse centrale à chaque partie.
- **Bruit de crête** (`1 - |bruit|`) — produit des lignes au lieu de taches,
  donc de vraies chaînes de montagnes orientées.
- **Humidité** — un champ indépendant du relief qui répartit plaines, savanes et
  forêts à altitude égale.

Huit types de terrain (plage → sommet enneigé), chacun avec sa hauteur, sa
couleur et son **coût de conquête** : une armée traverse une plaine, elle s'use
en montagne.

Niveau de la mer **et** limites de bandes sont calibrés par percentile. Répartir
les bandes linéairement entre mer et sommet ne marche pas : la somme de
plusieurs bruits concentre les altitudes autour de la moyenne et le point
culminant est une valeur aberrante — presque toute la terre tombait dans la
première bande, produisant des continents plats.

**Le monde est de la vraie géométrie.** 256×160 tuiles sur 4 studs donnent un
monde de 1024×640 studs, posé dans le Workspace. On y navigue en caméra
stratégique, et on peut y descendre avec son avatar (touche F).

**40 960 tuiles ne peuvent pas être 40 960 Parts.** Les tuiles voisines de même
couleur et même relief sont fusionnées en rectangles par
[GreedyMesh.luau](ReplicatedStorage/Shared/GreedyMesh.luau). Le sol n'est plus
compose de Parts : le serveur remplit une fois le **SmoothTerrain Roblox** avec
les materiaux naturels des biomes. Le monde reste plat pour l'avatar, tandis que
les cotes et les transitions ne ressemblent plus a des blocs Minecraft.

**Le terrain ne change jamais, seule la souverainete change.** C'est ce qui
permet de separer les responsabilites :

| | Contenu | Coût |
|---|---|---|
| Serveur | SmoothTerrain naturel, eau et collision | Zones de biomes remplies une fois |
| Client | Voile politique transparent, fusionné par propriétaire | Parts très fines et locales |

Le Terrain serveur porte directement la collision : un avatar marche sur le
sol naturel et nage dans une vraie eau Roblox.

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

### Progression technologique

Cinq ères, achetées individuellement : **Colonisation → Fortification →
Industrie → Atomique → Thermonucléaire**. Chacune coûte de l'or *et* exige un
développement réel (des villes, un port, un silo, du territoire).

La version précédente déverrouillait le nucléaire quand 55 % des terres étaient
colonisées. C'était une erreur de conception : ce seuil mesure la vitesse à
laquelle la carte se remplit, pas l'effort d'un joueur. Avec douze factions, il
tombait **en moins d'une minute** et toute la branche technologique était
décorative.

Rythme mesuré en simulation sur une partie de 10 minutes :

| Ère | Atteinte à |
|---|---|
| Fortification | 0m19 |
| Industrie | 2m45 |
| **Atomique** | **8m24** |
| Thermonucléaire | hors de portée en 10 min |

Le banc d'essai échoue si l'ère Atomique tombe avant 4 minutes ou n'arrive
jamais — cette régression ne peut donc plus passer inaperçue.

Le coût des bâtiments croît avec le nombre déjà possédé (`BUILD_COST_SCALING`) :
sans cette inflation, un empire riche empilait 357 villes en dix minutes.
Les prix affichés dans le HUD viennent désormais du calcul serveur réel, doctrine
et inflation comprises.

Les villes ont trois niveaux : **Ville → Métropole → Mégapole**. Chaque évolution
augmente simultanément le plafond de population, le revenu et la silhouette 3D.
Le niveau survit aux captures : prendre une mégapole ennemie est donc un objectif
économique concret, pas seulement une case colorée supplémentaire.

### Industrie et logistique

L'ère **Industrie** débloque l'usine. Elle doit être construite à moins de 56
cases d'une ville et se relie automatiquement au centre urbain allié le plus
proche. La liaison crée une vraie route 3D, parcourue par un camion de fret, et
produit un revenu continu dont le rendement baisse légèrement avec la distance.

Capturer ou détruire une ville recalcule immédiatement les réseaux de sa faction :
les usines se reconnectent si une autre ville est à portée, sinon leur production
s'arrête. Le HUD affiche le nombre de routes et leur revenu en or par seconde.

Les modèles sont procéduraux et sans asset externe : villes à trois silhouettes,
usine animée avec quai et fumée, silo ouvert avec missile complet, batterie SAM à
quatre intercepteurs et radar motorisé. Les matériaux, ombres, vitrages et lumières
restent lisibles aussi bien depuis la vue stratégique qu'en avatar.

### Marine

Les débarquements sont le seul moyen d'ouvrir la carte : sans eux un joueur
insulaire est en prison. Les transports suivent une vraie route maritime
calculée en BFS — ils ne traversent jamais la terre.

La **base navale** entretient un porte-avions qui orbite autour d'elle et saigne
les transports ennemis passant à portée. Longer une côte défendue coûte cher, la
contourner coûte du temps. C'est ce qui transforme une invasion maritime en pari
plutôt qu'en simple dépense.

Le modèle 3D importé se branche en une ligne : `UnitModels.CARRIER_MESH_ID`.
Tant que le champ est vide, une coque procédurale prend le relais — le jeu
n'attend jamais l'asset. Le fichier source est versionné dans
`assets/models/aircraft-carrier.glb`.

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
8 bâtiments · villes évolutives · industrie et routes logistiques · 4 doctrines · alliances, trahisons, embargos · réputation
persistante · phase nucléaire avec interception · élimination · condition de
victoire et relance automatique · bots complets · rendu enrichi, minimap, HUD,
écran de victoire, sons, classement, notifications.

**Pas encore fait**, par ordre de priorité :

1. **Chat vocal de proximité** pour les négociations.
4. **Brouillard de guerre.**
5. **Saisons et classement de clans.**

### Limites connues

⚠️ **L'équilibrage humain reste à playtester à plusieurs.** Le mode solo possède
maintenant un départ assisté (320 or, 230 troupes), 75 secondes de préparation,
3 minutes de grâce contre l'IA et une pression bot progressive sur 6 minutes.
Les leviers sont regroupés dans la section `Accessibilite de l'IA` de
`Config.luau`.

⚠️ **Les bots construisent peu** (une trentaine de villes pour 12 factions sur
10 minutes) parce qu'ils épargnent pour l'ère suivante. C'est cohérent avec la
progression voulue, mais à revérifier quand des humains joueront à côté d'eux.

⚠️ **Les simulations 100 % bots restent plus brutales qu'une partie solo** :
elles n'utilisent volontairement ni la grâce humaine ni son bonus économique.
Elles servent de stress test de fin de partie, pas de référence de difficulté.

⚠️ **Le coût de rendu n'a été mesuré qu'en simulation**, pas sur un vrai
appareil. `./tests/run.sh` reporte les zones SmoothTerrain et les Parts de la
couche politique ; si tu changes `TILE_SIZE` ou `CHUNK_SIZE`, relance-le.

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
