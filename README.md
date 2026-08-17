# CONQUEST RTS

Jeu de conquête territoriale temps réel sur Roblox, par **Blackline Studio**.

Inspiré du genre `.io` de conquête de territoire (OpenFront, Territorial.io), poussé
plus loin : rendu 3D, avatar-commandeur, diplomatie vocale et réputation persistante.

---

## Pitch

> **Conquiers le monde. Trahis tes alliés.**
> Commence avec une seule province. Fais croître ta population, lance des offensives,
> construis des ports et des silos nucléaires. Négocie des traités en vocal — puis
> brise-les au pire moment.
>
> 🌍 48 joueurs par carte · ⚔️ Parties de 25 minutes · 🤝 Alliances réelles
> ☢️ Fin de partie nucléaire · 🏆 Saisons de clans
>
> Ta réputation te suit d'une partie à l'autre. Choisis bien.

---

## Lancer le projet

Prérequis : [Aftman](https://github.com/LPGhatguy/aftman) (déjà installé) et le
plugin **Rojo** dans Roblox Studio.

```bash
cd "/Users/billy/Documents/CONQUEST RTS" && aftman install && rojo serve
```

Puis, dans Studio : onglet Rojo → **Connect**. Le code se synchronise en direct ;
chaque sauvegarde de fichier est répercutée immédiatement dans le DataModel.

Pour générer un fichier `.rbxlx` autonome à la place :

```bash
cd "/Users/billy/Documents/CONQUEST RTS" && rojo build -o CONQUEST_RTS.rbxlx
```

Teste avec **Play Solo** : 10 bots peuplent la carte automatiquement, donc la
partie est jouable et observable sans autre joueur.

---

## Architecture

```
ReplicatedStorage/Shared/
  Config.luau      Toutes les constantes d'équilibrage (le seul fichier à tuner)
  MapGen.luau      Génération de carte déterministe à partir d'une seed
  Remotes.luau     Création/récupération des RemoteEvents
  Types.luau       Types partagés serveur ↔ client

ServerScriptService/Server/
  init.server.luau Cycle de vie des joueurs, boucle de tick, réplication
  GameState.luau   État autoritaire : territoires, troupes, offensives
  Bots.luau        IA de remplissage (temporaire, pour le playtest solo)

StarterPlayerScripts/Client/
  init.client.luau Caméra 2D (pan/zoom), saisie des ordres, réseau
  MapRenderer.luau Peinture de la carte via EditableImage
  HUD.luau         Barre de commandement, classement, statut
```

### Décisions structurantes

**La carte est un buffer plat, pas des instances.** 256×160 = 40 960 tuiles.
`terrain` et `owner` sont deux `buffer` d'un octet par tuile. Aucune Part, aucun
Instance par tuile — c'est la seule approche qui tient sur mobile.

**On réplique la seed, pas la carte.** Serveur et client appellent
`MapGen.generate(seed)` et obtiennent un résultat identique. 4 octets au lieu de 40 Ko.

**On ne réplique que les deltas de propriété.** Chaque tick, le serveur envoie les
tuiles ayant changé de main au format `[u32 index][u8 slot]`. Une partie calme
coûte quelques dizaines d'octets par tick.

**Le rendu est isolé.** `MapRenderer` ne connaît rien de la simulation. Quand on
passera au rendu 3D, c'est le seul fichier à remplacer.

**Simulation à pas fixe.** 10 ticks/seconde avec accumulateur : l'équilibrage ne
dépend pas du FPS serveur.

### Modèle d'attaque

On n'ordonne pas des unités, on engage un **corps expéditionnaire** contre une
faction. Les troupes engagées quittent immédiatement la réserve — elles ne
défendent plus. C'est la décision tactique centrale du jeu.

Chaque tick, ce corps dépense des troupes pour absorber les tuiles ennemies au
contact. Le coût d'une tuile dépend du terrain et de la **densité de troupes** du
défenseur (`troupes / territoires`) — ce qui punit l'expansion incontrôlée et
récompense l'empire compact.

Quand le corps est épuisé, l'offensive s'arrête là où elle en est et les
survivants rentrent.

---

## État actuel

**Fait** — boucle de base jouable :
génération de carte · spawn · croissance de population · offensives et capture ·
front qui progresse · bots · rendu carte · pan/zoom · HUD · classement.

**Pas encore fait** — dans l'ordre de priorité :

1. **Bateaux et débarquements** — l'océan est actuellement infranchissable, ce qui
   enferme les joueurs insulaires.
2. **Bâtiments** — villes (plafond de population), ports, défenses côtières.
3. **Alliances** — pactes de non-agression, partage de vision, et le score de
   réputation persistant qui rend la trahison coûteuse.
4. **Phase nucléaire** — silos, interception, hiver nucléaire.
5. **Rendu 3D** — remplacer `MapRenderer` par du terrain low-poly avec bâtiments.
6. **Condition de victoire et fin de partie.**

⚠️ Les valeurs de `Config.luau` sont des estimations de départ : elles n'ont pas
encore été soumises à un vrai playtest. Attends-toi à devoir tuner
`ATTACK_SPEND_RATE`, `GROWTH_RATE` et `DEFENSE_DENSITY_K` en priorité.
