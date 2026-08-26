--!strict
-- Toutes les constantes d'equilibrage au meme endroit.
-- C'est ici qu'on tune le jeu : ne pas eparpiller ces valeurs ailleurs.

local Config = {}

-- Identite
Config.GAME_NAME = "CONQUEST RTS"
Config.STUDIO_NAME = "Blackline Studio"

--=============================================================================
-- Carte
--=============================================================================

Config.MAP_WIDTH = 256
Config.MAP_HEIGHT = 160
Config.TILE_COUNT = Config.MAP_WIDTH * Config.MAP_HEIGHT

Config.LAND_RATIO = 0.38

--[[
	Types de terrain.

	Huit paliers de relief au lieu de trois : c'est ce qui fait la difference
	entre une carte en escalier et un paysage. Les identifiants restent sous 16
	parce que la cle de fusion du rendu encode le proprietaire et le terrain
	dans un seul entier (voir WorldRenderer.chunkKeyAt).
]]
Config.TERRAIN = {
	OCEAN = 0,
	BEACH = 1,
	PLAINS = 2,
	SAVANNA = 3,
	FOREST = 4,
	HILLS = 5,
	HIGHLAND = 6,
	MOUNTAIN = 7,
	PEAK = 8,
}

-- Repartition des terres par altitude, du niveau de la mer vers les sommets.
-- Les plages sont fines, les sommets rares : c'est ce qui rend une chaine de
-- montagnes remarquable plutot que banale.
Config.TERRAIN_BANDS = {
	{ upTo = 0.06, kind = Config.TERRAIN.BEACH },
	{ upTo = 0.44, kind = Config.TERRAIN.PLAINS }, -- module par l'humidite
	{ upTo = 0.64, kind = Config.TERRAIN.HILLS },
	{ upTo = 0.82, kind = Config.TERRAIN.HIGHLAND },
	{ upTo = 0.95, kind = Config.TERRAIN.MOUNTAIN },
	{ upTo = 1.01, kind = Config.TERRAIN.PEAK },
}

-- Multiplicateur de cout de conquete par terrain. Une armee traverse une
-- plaine, elle s'use en montagne : c'est ce qui donne une valeur strategique au
-- relief au lieu d'en faire une simple decoration.
Config.TERRAIN_COST = {
	[0] = math.huge, -- ocean : uniquement par debarquement
	[1] = 0.85, -- plage : indefendable
	[2] = 1.0, -- plaines
	[3] = 1.05, -- savane
	[4] = 1.35, -- foret
	[5] = 1.7, -- collines
	[6] = 2.2, -- hautes terres
	[7] = 3.0, -- montagne
	[8] = 4.0, -- sommet
}

--=============================================================================
-- Monde 3D
--=============================================================================
-- La carte est batie en vraie geometrie sur la baseplate. Une tuile fait
-- TILE_SIZE studs de cote, donc le monde mesure 1024 x 640 studs : assez grand
-- pour qu'un avatar s'y sente petit, assez compact pour le traverser.

--[[
	Echelle du monde.

	TILE_SIZE est le seul bouton : tout ce qui est dessine en studs en derive.
	Le monde a ete auteur a 4 studs par tuile — un personnage Roblox faisait
	alors plus d'une tuile de haut, ce qui donnait la sensation de marcher sur
	un damier de jouet.

	WORLD_SCALE rapporte l'echelle courante a celle d'origine. Les modeles, les
	frontieres, les routes et les effets sont ecrits une fois en coordonnees
	lisibles puis multiplies par ce facteur — plutot que de reecrire cent
	soixante-dix nombres a chaque changement.

	Plafond dur : au-dela de 2048 studs une Part est rognee par Roblox sans
	erreur. Le maillage borne donc ses dalles (voir GreedyMesh), ce qui coute
	752 dalles au lieu de 441 a l'echelle x30 — negligeable.
]]
Config.TILE_SIZE = 12
-- Echelle de reference : celle a laquelle toute la geometrie a ete dessinee.
Config.AUTHORED_TILE_SIZE = 4
Config.WORLD_SCALE = Config.TILE_SIZE / Config.AUTHORED_TILE_SIZE
Config.WORLD_WIDTH = Config.MAP_WIDTH * Config.TILE_SIZE
Config.WORLD_DEPTH = Config.MAP_HEIGHT * Config.TILE_SIZE

-- Bordures invisibles cote serveur : l'avatar ne peut pas sortir du monde 3D
-- et tomber sous la carte. Elles sont hors de la derniere tuile pour ne pas
-- reduire la surface jouable.
Config.WORLD_BORDER_THICKNESS = 4 * Config.WORLD_SCALE
Config.WORLD_BORDER_HEIGHT = 80 * Config.WORLD_SCALE

--[[
	Altitude du terrain, en studs. **Une seule pour toute la terre ferme.**

	Le monde est bati en blocs et non en SmoothTerrain : la carte est une grille
	de tuiles, et un terrain voxel lisse se bat en permanence contre cette
	grille — les frontieres politiques suivent des cases, pas des courbes.

	Le relief etage a ete retire. Il donnait une lecture du cout de conquete,
	qui varie toujours par terrain (voir TERRAIN_COST), mais au prix de trois
	defauts qui pesaient plus lourd que ce gain :

	  - les sommets a 24 studs masquaient le territoire derriere eux depuis une
	    camera strategique, sur un jeu ou lire la carte EST le jeu ;
	  - chaque palier d'altitude coupait la fusion des blocs, cote client comme
	    cote serveur ;
	  - les batiments, routes et effets devaient composer avec neuf altitudes
	    alors qu'ils ne represent qu'une couche politique posee sur la carte.

	Le type de terrain reste parfaitement lisible : il porte toujours sa propre
	couleur. Ce qui disparait, c'est uniquement la troisieme dimension.

	La table est construite en boucle plutot qu'ecrite a la main : neuf valeurs
	identiques recopiees derivent tot ou tard, celle-ci ne le peut pas.
]]
-- Epaisseur du sol, a l'echelle. Sans le facteur, une tuile de douze studs de
-- cote n'aurait que quatre studs d'epaisseur : le monde deviendrait une feuille.
Config.LAND_HEIGHT = 4 * Config.WORLD_SCALE

Config.TERRAIN_HEIGHT = { [0] = 0 } -- ocean : pas de bloc, seulement le plan d'eau
for kind = 1, 8 do
	Config.TERRAIN_HEIGHT[kind] = Config.LAND_HEIGHT
end

-- Altitude de reference des basses terres, utilisee par tout ce qui doit se
-- poser "au niveau du sol" sans connaitre la tuile exacte. Desormais la seule
-- altitude qui existe.
Config.BASE_LAND_HEIGHT = Config.LAND_HEIGHT

Config.OCEAN_LEVEL = 1.5 * Config.WORLD_SCALE

-- La carte est decoupee en chunks reconstruits independamment. Plus petit =
-- reconstruction moins couteuse mais moins de fusion possible entre blocs ;
-- 16x16 est le compromis retenu.
Config.CHUNK_SIZE = 16
Config.CHUNKS_X = Config.MAP_WIDTH // Config.CHUNK_SIZE
Config.CHUNKS_Y = Config.MAP_HEIGHT // Config.CHUNK_SIZE

-- Nombre maximal de chunks reconstruits par frame. Pendant une grande
-- offensive, des dizaines de chunks changent en un tick : les etaler evite de
-- faire chuter le framerate au pire moment de la partie.
Config.CHUNK_REBUILDS_PER_FRAME = 3

--=============================================================================
-- Boucle de simulation
--=============================================================================

Config.TICK_RATE = 10
Config.TICK_DT = 1 / Config.TICK_RATE

--=============================================================================
-- Population
--=============================================================================

Config.START_TROOPS = 150
Config.BASE_MAX_TROOPS = 250

--[[
	Plafond de troupes apporte par le territoire — **sous-lineaire**.

	C'est la correction la plus importante de tout l'equilibrage, et elle a ete
	trouvee a la mesure. Le plafond etait auparavant lineaire (28 troupes par
	tuile) : un empire dix fois plus grand levait dix fois plus d'hommes. C'etait
	le vrai moteur de l'emballement, bien plus que le cout de conquete — tout
	frein applique au cout se faisait rattraper en un instant par une armee qui
	grossissait a la meme vitesse que la carte.

	La preuve : une fois les alliances rendues temporaires (elles gelaient la fin
	de partie et masquaient le probleme), le debuff de taille seul laissait
	encore le leader monter a 99 % des terres. Avec un plafond en ^0.6, quinze
	fois plus de territoire ne donne plus que cinq fois plus d'armee.

	Consequence recherchee : **les villes deviennent le vrai levier militaire**,
	puisque leur bonus de population, lui, reste plein. Un empire compact et
	urbanise bat un empire etale, ce qui donne enfin une raison de construire
	autre chose que la prochaine offensive.
]]
Config.MAX_TROOPS_TILE_EXPONENT = 0.6
-- Calibre pour laisser inchange un empire moyen (1 000 tuiles) et n'ecraser que
-- les geants : 28 x 1000 = 28 000, et 444 x 1000^0.6 = 28 000.
Config.MAX_TROOPS_TILE_SCALE = 444

Config.GROWTH_RATE = 0.012 -- fraction de l'ecart au plafond, comblee par tick
Config.MIN_GROWTH = 0.6

-- Un joueur humain doit pouvoir prendre une premiere decision interessante
-- immediatement. Les bots savent optimiser chaque tick ; ce petit avantage de
-- depart compense l'apprentissage de l'interface sans rendre les combats
-- gratuits une fois la partie installee.
Config.HUMAN_START_TROOPS = 230
Config.HUMAN_GROWTH_MULTIPLIER = 1.18

--=============================================================================
-- Economie
--=============================================================================
-- L'or achete les batiments. Il vient du territoire et surtout du commerce
-- maritime : c'est ce qui donne un poids economique a la diplomatie, puisqu'un
-- embargo coupe litteralement les revenus de l'autre.

Config.START_GOLD = 120
Config.HUMAN_START_GOLD = 320 -- permet de construire une ville des le deploiement
Config.HUMAN_GOLD_MULTIPLIER = 1.12

-- Le revenu territorial est volontairement sous-lineaire (tiles^0.8) : un
-- empire deux fois plus grand ne gagne pas deux fois plus. Sans cet
-- amortissement, le leader s'auto-finance a l'infini et la fin de partie
-- devient une formalite — mesure en simulation, un revenu lineaire produisait
-- 4,4 millions d'or morts en dix minutes.
Config.GOLD_TILE_EXPONENT = 0.8
Config.GOLD_TILE_SCALE = 0.0042 -- par tick

Config.GOLD_PER_PORT = 0.22 -- par tick, par port possede
Config.GOLD_PER_CITY = 0.08 -- par tick, par ville possedee
-- Volontairement faible : un joueur qui accumule les capitales conquises en
-- tenait douze en simulation, soit l'equivalent de plusieurs milliers de
-- territoires en revenu. La capitale est un objectif militaire, pas une rente.
Config.GOLD_PER_CAPITAL = 0.08 -- par tick, par capitale tenue
--[[
	Commerce maritime.

	Le commerce n'est plus un revenu abstrait. Il l'etait : un compteur de
	"partenaires" multiplie par une constante, verse a chaque tick, pendant que
	des navires marchands purement decoratifs traversaient la carte sans rien
	transporter. Deux systemes qui parlaient de la meme chose et ne se
	connaissaient pas — donc couler un navire ne coutait rien a personne, et un
	embargo agissait instantanement sans qu'on voie jamais une route se fermer.

	Desormais l'or arrive **a l'arrivee du navire**, et les deux ports touchent
	la meme somme : celui qui expedie comme celui qui recoit. C'est ce qui rend
	un port etranger precieux vivant plutot que mort, et c'est ce qui donne un
	sens a la piraterie — un navire coule est de l'or qui n'arrivera jamais, des
	deux cotes.

	La distance paie : une longue route rapporte plus, donc le commerce
	lointain vaut le risque de traverser des eaux hostiles.
]]
-- Vitesse de construction d'une voie, en studs par seconde. A vitesse constante
-- plutot qu'a duree fixe : une voie de dix cases se batit vite, une de cent
-- prend son temps. L'inverse donnerait l'impression que la longueur ne coute rien.
Config.ROUTE_BUILD_SPEED = 110

Config.TRADE_GOLD_BASE = 14 -- or verse a chaque port a l'arrivee d'un navire
Config.TRADE_GOLD_PER_TILE = 0.22 -- supplement par tuile parcourue
Config.TRADE_SHIP_INTERVAL = 45 -- ticks entre deux vagues de departs
-- Chance qu'un port donne arme un navire, tiree une fois par niveau : un port
-- de niveau 3 a trois fois plus d'occasions qu'un port neuf.
Config.TRADE_SHIP_CHANCE = 0.22
-- Plafond global. Sans lui, une carte couverte de ports saturerait la mer de
-- navires et la replication avec eux.
Config.MAX_TRADE_SHIPS = 24

--[[
	Commerce terrestre, meme philosophie que le maritime : l'or n'est plus un
	revenu abstrait verse au tick, il arrive **avec le colis**.

	Trois regles, alignees sur notre boucle territoriale :

	  1. Une usine n'a qu'UN colis en route a la fois. Le debit d'une usine,
	     c'est sa cadence, pas le nombre de villes dans son cercle.
	  2. Apres chaque livraison, un temps de rechargement avant l'expedition
	     suivante — le camion doit bien faire le retour.
	  3. L'or est verse a l'arrivee, proportionnel a la distance et au niveau
	     de l'usine. Entre le depart et l'arrivee, la gare cible a pu tomber :
	     on ne paie que ce qui est reellement livre.

	Le chargement grossit avec le reseau : une usine qui dessert dix gares
	expedie des colis dix fois plus riches qu'une usine au bout du monde. Le
	debit reste plafonne par la cadence — un seul colis a la fois — mais la
	taille du reseau compte autant que dans l'ancienne economie par liaisons.

	Equilibrage : calibre sur l'ancien revenu passif (~5 or/tick et par usine
	en milieu de partie, mesure en simulation) pour que le passage aux colis
	ne change ni le rythme de partie ni la course aux eres.
]]
Config.TRUCK_GOLD_BASE = 10 -- or verse a l'arrivee d'un colis, avant distance
Config.TRUCK_GOLD_PER_TILE = 1.2 -- supplement par tuile de liaison
Config.TRUCK_SPEED = 4 -- tuiles parcourues par tick
Config.TRUCK_COOLDOWN = 60 -- ticks de rechargement entre deux expeditions

--=============================================================================
-- Attaque
--=============================================================================

Config.DEFAULT_ATTACK_RATIO = 0.25
Config.MIN_ATTACK_TROOPS = 20
Config.ATTACK_SPEND_RATE = 0.035 -- part du corps expeditionnaire depensee par tick
-- Delai avant qu'une retraite soit honoree, en ticks : le front continue de
-- se battre pendant ce temps. Aligne sur notre boucle territoriale (20 ticks).
Config.RETREAT_DELAY = 20
-- Malus OF : 25 % des troupes du front contre un joueur, 0 % contre le neutre.
-- ChantierB.apply reecrit les memes valeurs ; les garder ici pour le tuning.
Config.RETREAT_LOSS = 0.25
Config.RETREAT_LOSS_NEUTRAL = 0
Config.TILE_BASE_COST = 1.4
Config.NEUTRAL_COST_MULT = 0.75
Config.DEFENSE_DENSITY_K = 0.9 -- poids de la densite de troupes adverse
Config.DEFENDER_LOSS_RATIO = 0.55
Config.MAX_TILES_PER_TICK = 400

-- Ouverture lisible : on peut coloniser et construire immediatement, mais les
-- guerres entre nations attendent quelques secondes. Deux fronts simultanes
-- restent possibles ; au-dela le jeu devient une suite d'ordres illisibles.
Config.PREPARATION_DURATION = 0 -- OpenFront : pas de gel des guerres ; le combat ouvre tout de suite
-- Immunite nucleaire post-spawn (OF : 5 s), distincte de la preparation.
Config.SPAWN_NUKE_IMMUNITY = 5
Config.DOCTRINE_CHOICE_DURATION = 120
Config.MAX_ACTIVE_ATTACKS_PER_PLAYER = 2

--=============================================================================
-- Accessibilite de l'IA
--=============================================================================
-- Les bots ne doivent pas jouer comme douze speedrunners contre un debutant.
-- Ils colonisent encore et savent finir une partie, mais leur pression monte
-- progressivement. La grace ne bloque que les attaques IA -> humain : le
-- joueur reste libre d'ouvrir lui-meme une guerre quand il se sent pret.

Config.BOT_ATTACK_RATIO_MIN = 0.12
Config.BOT_ATTACK_RATIO_MAX = 0.25
Config.BOT_ATTACK_CHANCE_EARLY = 0.35
Config.BOT_ATTACK_CHANCE_LATE = 0.78
Config.BOT_FULL_PRESSURE_AFTER = 6 * 60 -- secondes apres le premier deploiement
Config.BOT_HUMAN_GRACE_DURATION = 3 * 60
Config.BOT_HUMAN_PROTECTION_TILES = 120

-- Progression persistante du commandant. Elle recompense surtout le fait de
-- terminer une partie et de prendre des objectifs, pas le grind de tuiles.
Config.XP_PER_MATCH = 50
Config.XP_PER_WIN = 150
Config.XP_PER_CAPITAL = 40
Config.XP_PER_BUILDING = 8
Config.XP_TILE_DIVISOR = 12
Config.XP_LEVEL_BASE = 220

--=============================================================================
-- Frein a l'emballement
--=============================================================================
--[[
	Le probleme qu'on corrige : mesure en simulation, une partie se terminait sur
	8 266 / 7 177 / 36 / 24 tuiles. Deux joueurs possedaient 99 % des terres et il
	n'y avait aucun milieu de partie. Plus un empire etait gros, plus il lui etait
	facile de grossir — l'expansion etait un cliquet, jamais une decision.

	La premiere tentative etait une penalite de ravitaillement : conquerir loin de
	ses villes coutait plus cher. Elle a ete retiree parce qu'elle **aggravait**
	le probleme, et c'est mesure : resserrer la portee franche a 14 tuiles faisait
	passer le leader de 55 % a 72 % des terres, a 10 tuiles a 99 %. La raison est
	structurelle — une penalite indexee sur la distance aux villes amplifie
	l'avantage de qui en possede le plus. Elle paralysait les petits, qui n'ont
	pas les moyens d'en construire, sans jamais gener celui qui en avait dix.

	Le remplacement s'indexe directement sur **la taille de l'empire**, comme
	CONQUEST. Trois effets continus, sans seuil brutal :

	  1. un gros defenseur defend moins bien (sa densite de troupes s'effondre) ;
	  2. un gros attaquant conquiert plus lentement ;
	  3. en compensation, il perd moins de troupes par tuile.

	Le troisieme point est essentiel : sans lui le geant est simplement puni, et
	le jeu devient une course a rester deuxieme. Avec, le geant reste efficace
	mais lent — donc rattrapable, et surtout attaquable.
]]

-- Taille a partir de laquelle un empire est "grand", en part des terres. La
-- sigmoide est centree ici : a ce point exact, la moitie du debuff est appliquee.
Config.LARGE_EMPIRE_MIDPOINT_RATIO = 0.10
-- Largeur de la transition, en part du point median. Plus c'est petit, plus le
-- passage de "normal" a "grand" est brutal ; un tiers donne une pente lisible
-- sans jamais produire de marche d'escalier.
Config.LARGE_EMPIRE_SPREAD = 0.333
-- Defense minimale d'un empire immense, en part de sa defense normale.
Config.LARGE_DEFENDER_FLOOR = 0.70
-- Seuil, en part du point median, au-dela duquel l'attaquant ralentit.
Config.LARGE_ATTACKER_THRESHOLD_RATIO = 0.66
Config.LARGE_ATTACKER_SPEED_EXPONENT = 0.6
Config.LARGE_ATTACKER_SPEED_FLOOR = 0.35 -- un geant reste jouable, pas paralyse
Config.LARGE_ATTACKER_COST_EXPONENT = 0.35 -- compensation : il perd moins par tuile

--[[
	Effondrement d'une faction agonisante.

	Sans cette regle, la carte se termine avec des factions a trois tuiles qui ne
	peuvent plus rien faire mais ne meurent jamais : elles n'ont plus assez de
	troupes pour attaquer, et personne ne prend la peine de finir le travail. La
	simulation en produisait quatre a la fois, et le milieu de partie etait vide.

	Des qu'un defenseur passe sous ce seuil **pendant qu'on l'attaque**, son
	territoire est reparti : les tuiles au contact vont a l'assaillant, les
	autres a n'importe quel voisin hostile. La condition "pendant qu'on
	l'attaque" est ce qui protege un joueur qui vient de spawner.
]]
Config.COLLAPSE_TILE_RATIO = 0 -- OF : seuil absolu, pas un ratio de carte
Config.COLLAPSE_MIN_TILES = 100 -- handleDeadDefender : sous 100 tuiles, absorption

--=============================================================================
-- Cadran de la fin du monde (anti-impasse)
--=============================================================================

--[[
	Une faction sous la barre requise est marquee, saignee, puis emportee par
	le rot. Les courbes vivent dans Shared/Doomsday pour que le client lise
	les memes chiffres que le serveur.
]]
Config.DOOMSDAY = {
	WARN_SECONDS = 20, -- le crane s'affiche avant toute saignee
	DRAIN_START_PERCENT = 2, -- % du maximum de troupes perdu par seconde au debut
	DRAIN_MAX_PERCENT = 8, -- ... et a plein regime
	DRAIN_RAMP_SECONDS = 60, -- duree de la montee du taux
	FLOOR_START_PERCENT = 40, -- plancher de troupes initial (% du maximum)
	DRAIN_FLOOR_PERCENT = 5, -- plancher final, une fois effondre
	FLOOR_DECAY_SECONDS = 45, -- duree de l'effondrement du plancher
	ROT_DEATH_SECONDS = 90, -- le rot emporte la faction en 90 s, garanti
	ROT_GRAIN_SECONDS = 8, -- ouverture granuleuse avant la croissance dendritique
	ROT_SPECKLE_PERCENT = 2, -- trous d'ouverture, en % du territoire de depart
}
Config.COLLAPSE_MAX_PASSES = 24 -- garde-fou de la redistribution

--=============================================================================
-- Marine
--=============================================================================
--[[
	Porte-avions de patrouille.

	Ils comblent un trou identifie de longue date : les transports de troupes
	etaient strictement inarretables. Une invasion maritime etait donc une
	depense, jamais un pari — l'adversaire ne pouvait rien y opposer.

	Chaque base navale entretient un porte-avions qui tourne autour d'elle. Un
	transport ennemi qui passe a portee perd des troupes a chaque tick : longer
	une cote defendue coute cher, la contourner coute du temps. C'est ce choix
	qui rend la carte maritime interessante.

	Le porte-avions n'est pas pilotable. Il defend une zone, il ne poursuit
	personne : une unite qu'on dirige demanderait une interface de selection que
	le jeu n'a pas, et transformerait un RTS de territoire en jeu d'escarmouche.
]]

Config.CARRIER_PATROL_RADIUS = 13 -- tuiles, rayon de l'orbite autour de la base
Config.CARRIER_PATROL_SPEED = 0.022 -- radians par tick
Config.CARRIER_INTERCEPT_RANGE = 11 -- tuiles
Config.CARRIER_INTERCEPT_DAMAGE = 0.075 -- part des troupes du transport, par tick
-- Sans debarquements, un joueur insulaire est en prison et un continent est
-- imprenable. C'est la mecanique qui ouvre la carte.

Config.BOAT_SPEED = 0.85 -- tuiles par tick
-- Charge 1/5 (port OF). La valeur 0.4 n'etait jamais lue : Navy embarquait `troops / 5`.
Config.BOAT_TROOP_RATIO = 0.2 -- part max de la reserve embarquee
Config.BOAT_RETREAT_LOSS = 0.25 -- part perdue si le transport rentre au port
Config.MIN_BOAT_TROOPS = 30
Config.BOAT_MAX_RANGE = 220 -- longueur max du trajet, en tuiles
Config.BOAT_LANDING_BONUS = 1.35 -- surcout d'un debarquement contre une cote defendue
Config.MAX_BOATS_PER_PLAYER = 6

--=============================================================================
-- Batiments
--=============================================================================

Config.BUILDING = {
	NONE = 0,
	CITY = 1,
	PORT = 2,
	DEFENSE = 3,
	SILO = 4,
	SAM = 5,
	CAPITAL = 6,
	LAB = 7,
	FACTORY = 8,
	NAVAL_BASE = 9,
}

-- Classes de batiments. Elles structurent le menu de construction, mais surtout
-- elles obligent a se demander, pour chaque nouveau batiment, a quelle question
-- strategique il repond. Un batiment qui n'entre dans aucune classe est un
-- batiment dont on n'a pas defini le role.
Config.BUILD_CLASS = {
	ECONOMY = "economy",
	MILITARY = "military",
	SCIENCE = "science",
}

-- Chaque laboratoire reduit le cout de la prochaine ere. Le plafond est
-- essentiel : sans lui, un joueur qui empile les laboratoires atteint
-- l'arme nucleaire gratuitement.
Config.LAB_ERA_DISCOUNT = 0.07
Config.LAB_DISCOUNT_CAP = 0.35

-- Perdre sa capitale doit etre un desastre, pas une tuile de plus : c'est ce
-- qui donne un objectif lisible a une offensive et un enjeu a la defense.
Config.CAPITAL_TROOP_LOSS = 0.45 -- part de la reserve perdue par l'ancien proprietaire
-- Butin volontairement modeste : mesure en simulation, 45 capitales prises en
-- dix minutes a 400 d'or injectaient 18 000 d'or et faisaient exploser toute la
-- progression technologique. La capitale doit valoir pour ce qu'elle retire a
-- l'adversaire, pas pour ce qu'elle rapporte.
-- Part du plafond d'armee au-dela de laquelle la jauge passe en alerte. Valeur
-- de la reference : prevenir a 80 % laisse le temps de depenser, prevenir a
-- 97 % ne fait que constater.
Config.ARMY_LIMIT_WARNING = 0.8

Config.CAPITAL_PLUNDER = 150 -- or pris par l'assaillant

--[[
	Butin de mise a mort : ce qu'on ramasse en achevant une faction.

	Achever quelqu'un ne rapportait rien. Un joueur pouvait donc passer trois
	minutes a demanteler un voisin et n'obtenir, en retour, qu'une ligne dans le
	fil de notifications — la recompense de l'effort le plus long du jeu etait
	invisible.

	Les proportions viennent CONQUEST : tout l'or d'un bot, la moitie
	de celui d'un humain. L'asymetrie est deliberee — depouiller entierement un
	joueur reel transformerait sa defaite en aubaine pour son bourreau, et
	donnerait a tout le monde une raison de s'acharner sur le plus faible.
]]
Config.CONQUEST_PLUNDER_BOT = 1.0
Config.CONQUEST_PLUNDER_HUMAN = 0.5

Config.DEFENSE_RADIUS = 6
Config.DEFENSE_STRENGTH = 55 -- points de defense au centre, degressif vers le bord

--[[
	Espacement minimal entre deux batiments, **tous types confondus**.

	Auparavant la regle ne comparait qu'un batiment a un autre du meme type : on
	pouvait donc coller une ville, une usine et un laboratoire sur trois tuiles
	voisines et concentrer tout un empire sur un mouchoir de poche. Les batiments
	forment maintenant une grille reguliere, ce qui rend une frappe nucleaire
	reellement dangereuse et donne une lecture immediate du developpement.

	La valeur a baisse de 4 a 3 en passant de "meme type" a "tous types" : c'est
	nettement plus contraignant au total (un seul batiment par disque de 28
	tuiles, au lieu d'un par type), et surtout c'est ce qui garde le premier
	batiment constructible dans le territoire de depart, qui n'est qu'un disque
	de rayon SPAWN_RADIUS.
]]
Config.BUILD_MIN_SPACING = 3

--[[
	Rayon d'accrochage du placement.

	Le clic n'est pas une coordonnee, c'est une intention : le serveur cherche la
	meilleure tuile valide dans ce rayon et construit la, plutot que de refuser.
	Avant, poser un batiment etait un clic dans le vide suivi d'un message
	d'erreur — le joueur se battait contre son curseur au lieu de jouer.

	Le rayon est un peu plus large que l'espacement minimal : il faut toujours
	qu'il existe un anneau de tuiles libres au-dela du disque bloque par un
	batiment voisin, sinon l'accrochage echouerait exactement dans le cas ou il
	sert le plus — un joueur qui essaie de densifier une zone deja batie.

	La recherche est un parcours en largeur **connexe** a travers son propre
	territoire : une enclave separee par des terres ennemies n'est pas
	atteignable, meme si elle est proche a vol d'oiseau. Le placement respecte la
	topologie du front.
]]
Config.BUILD_SNAP_RADIUS = Config.BUILD_MIN_SPACING + 2
-- Un port doit trouver une cote : sa recherche porte plus loin, sinon cliquer a
-- deux tuiles du rivage echouerait sans raison lisible.
Config.BUILD_SNAP_RADIUS_COASTAL = 9
--[[
	Reseau logistique.

	Une usine ne dessert plus une ville, ni meme plusieurs villes : elle
	**transforme en gares** toutes les structures a portee — villes, capitales,
	ports et autres usines — et ces gares se relient entre elles de proche en
	proche pour former un reseau connexe.

	La difference est enorme en jeu. Avec des routes usine -> ville, poser une
	usine ajoutait simplement k liaisons independantes : le placement etait une
	optimisation locale. Avec un reseau, une usine posee au bon endroit **fusionne
	deux grappes** et debloque d'un coup toutes leurs destinations. Le placement
	devient une decision de carte.
]]
Config.RAIL_RANGE = 56 -- portee de liaison entre deux gares, en tuiles
-- Conserve sous son ancien nom : le rayon de recherche d'une usine reste le
-- meme, seule la nature des cibles a change.
Config.FACTORY_ROUTE_RANGE = Config.RAIL_RANGE

--[[
	Inflation des couts de construction.

	Sans inflation, un empire riche empile trois cents villes et le jeu se resume
	a cliquer partout : la simulation en produisait 357 en dix minutes.

	La courbe est un **doublement borne** et non une progression lineaire. Le
	lineaire precedent (facteur 0.35) etait trop mou tot et trop dur tard : la
	cinquieme ville ne coutait que 2,4 fois la premiere, la vingtieme 8 fois, et
	rien ne s'arretait jamais. Ici chaque batiment double le prix du suivant
	jusqu'au plafond, atteint des le quatrieme. Le message est clair : les trois
	premiers sont bon marche, ensuite il vaut mieux **ameliorer** que multiplier.
]]
Config.BUILD_COST_CAP_MULT = 8 -- plafond, en multiples du prix de base

--[[
	Le port et l'usine partagent le meme compteur d'inflation.

	Construire un port rencherit donc tes usines, et inversement. C'est un vrai
	arbitrage economique entre l'axe maritime et l'axe ferroviaire, a budget
	commun, au lieu de deux echelles independantes qu'on empile sans reflechir.
]]
Config.BUILD_COST_GROUPS = {
	[Config.BUILDING.PORT] = { Config.BUILDING.PORT, Config.BUILDING.FACTORY },
	[Config.BUILDING.FACTORY] = { Config.BUILDING.PORT, Config.BUILDING.FACTORY },
}

-- Une ville n'est plus un achat que l'on oublie : elle peut devenir une
-- metropole puis une megapole. Les bonus sont des valeurs TOTALES par niveau
-- (et non des gains incrementaux), ce qui simplifie captures et destructions.
-- `upgradeCost` est le prix pour atteindre le niveau suivant.
Config.CITY_MAX_LEVEL = 3
Config.CITY_LEVELS = {
	[1] = {
		name = "Ville",
		popCapBonus = 900,
		goldBonus = Config.GOLD_PER_CITY,
		upgradeCost = 480,
		requiredEra = 1,
	},
	[2] = {
		name = "Metropole",
		popCapBonus = 2200,
		goldBonus = 0.18,
		upgradeCost = 1250,
		requiredEra = 2,
	},
	[3] = {
		name = "Megapole",
		popCapBonus = 4200,
		goldBonus = 0.38,
		upgradeCost = nil,
		requiredEra = 3,
	},
}

--[[
	Niveaux des ports et des usines.

	Ils n'ont pas de paliers nommes comme la ville : leur effet est un simple
	multiplicateur. Le prix d'une amelioration est **exactement celui du batiment
	suivant du meme type** — ameliorer et construire coutent donc pareil, et le
	joueur choisit sur le seul critere qui compte : a-t-il de la place, et
	a-t-il besoin de couvrir une nouvelle zone ?
]]
Config.PORT_MAX_LEVEL = 3
Config.FACTORY_MAX_LEVEL = 3

--=============================================================================
-- Nucleaire
--=============================================================================
-- La phase finale. Elle ne s'ouvre qu'une fois la carte largement partagee,
-- pour qu'elle soit un climax et pas une strategie d'ouverture.

Config.MISSILE_SPEED = 1.6 -- tuiles par tick
Config.SAM_RANGE = 34
Config.SAM_INTERCEPT_CHANCE = 0.55
Config.SAM_COOLDOWN = 90 -- ticks
--[[
	Rechargement d'un silo.

	Il n'y en avait aucun : un silo pouvait tirer a chaque tick, et la simulation
	sur une partie complete produisait 216 explosions — un missile toutes les
	quatre secondes. La phase finale n'etait plus un climax, c'etait un tapis de
	bombes. Neuf secondes par silo font du nombre de silos, et donc de leur
	placement, la vraie variable de la puissance de frappe.
]]
Config.SILO_COOLDOWN = 90 -- ticks

Config.NUKE = {
	ATOM = 1,
	HYDROGEN = 2,
	MIRV = 3,
}

Config.NUKE_STATS = {
	[1] = { radius = 9, troopKill = 0.30, cost = 550, name = "Bombe atomique" },
	[2] = { radius = 20, troopKill = 0.55, cost = 1400, name = "Bombe H" },
	-- Le MIRV ne fait pas de craterre unique : a mi-parcours il se scinde en
	-- ogives independantes qui retombent sur le territoire de la victime,
	-- chacune interceptable separement. C'est l'arme ultime du jeu de
	-- reference — chere, tardive, mais sans parade totale.
	[3] = {
		radius = 0,
		troopKill = 0,
		cost = 2600,
		name = "MIRV",
		warheads = 6,
		spread = 16,
		warheadRadius = 5,
		warheadTroopKill = 0.12,
	},
}

-- Point de la trajectoire ou le MIRV libere ses ogives (fraction du vol).
Config.MIRV_SEPARATION = 0.55

--=============================================================================
-- Diplomatie
--=============================================================================

Config.ALLIANCE_REQUEST_TIMEOUT = 300 -- ticks avant expiration d'une demande
Config.BETRAYAL_REPUTATION_COST = 1
Config.TRAITOR_MARK_DURATION = 1800 -- ticks pendant lesquels la trahison est affichee

--[[
	Une alliance expire.

	Le probleme qu'on corrige, et il etait fatal : les pactes etaient permanents.
	En fin de partie, les quatre survivants finissaient tous allies deux a deux —
	graphe complet, plus une seule cible legale sur la carte. La simulation se
	terminait sur zero offensive et zero frappe nucleaire. Le jeu ne se bloquait
	pas, il **s'arretait**, ce qui est pire parce que rien ne le signale.

	Une alliance dure maintenant cinq minutes puis tombe d'elle-meme. Ce n'est
	pas une trahison : personne n'est marque, les deux camps peuvent resigner.
	Mais la relation redevient une decision recurrente au lieu d'un clic unique,
	et il existe toujours une fenetre ou la guerre est possible.

	Le delai de carence apres la fin d'un pacte est ce qui empeche deux bots de
	le resigner au tick suivant et de recreer le blocage.
]]
--[[
	Rancune : combien de temps un bot se souvient de qui l'a frappe.

	C'etait le manque le plus profond de notre IA, et il ne se voyait pas dans le
	code : nos bots recalculaient une cible optimale a chaque decision, sans
	aucun souvenir de qui venait de leur prendre deux cents tuiles. Une partie ne
	racontait donc rien — pas de rivalite, juste une suite d'etats optimaux.

	Trente secondes, soit environ vingt decisions de bot : assez pour qu'une
	riposte parte et aboutisse, trop court pour qu'un bot s'acharne toute la
	partie sur un voisin devenu inoffensif.
]]
Config.GRUDGE_DURATION = 300 -- ticks
-- Poids de la rancune dans le choix de cible. Volontairement eleve : une
-- riposte doit l'emporter sur un calcul d'opportunite, sinon le joueur ne fait
-- jamais le lien entre son agression et ce qui lui tombe dessus.
Config.GRUDGE_ATTACK_BONUS = 140

-- Bavardage des bots. Faible a dessein : le catalogue a son propre anti-spam,
-- mais douze factions qui parlent chacune une fois sur huit decisions suffisent
-- a peupler le fil sans le saturer.
--[[
	Plan de construction des bots : des ratios, pas des seuils.

	Ce qui est remplace : une cascade de `elseif` avec des seuils en dur et des
	`roll < 0.45`. Elle avait deux defauts que CONQUEST evite.

	D'abord, tous les bots suivaient la MEME cascade dans le MEME ordre — douze
	empires batis a l'identique, ce qui se remarque en une partie. Ensuite un
	seuil en dur ne s'adapte pas : "moins de 8 villes" veut dire la meme chose
	pour un empire de cent tuiles et pour un empire de cinq mille.

	Ici le bot compare ce qu'il POSSEDE a ce qu'il DEVRAIT posseder pour sa
	taille, et achete l'ecart le plus criant rapporte au prix.

	`perCity` : combien d'exemplaires pour une ville.
	`costBias` : de combien le prix PERCU monte par exemplaire deja possede.
	C'est ce second terme qui empeche un bot riche de couvrir la carte du meme
	batiment — le manque peut rester, il finit par ne plus valoir son prix.
]]
-- Diviseur de la courbe SOUS-lineaire de villes visees : voir decideBuild, une
-- courbe lineaire y reintroduisait l'emballement du leader.
Config.BOT_CITY_DIVISOR = 8
Config.BOT_STRUCTURE_PLAN = {
	{ kind = Config.BUILDING.CITY, perCity = 1.0, costBias = 0.05, minEra = 1 },
	--[[
		Le port et l'usine partagent leur compteur d'inflation : chaque port rend
		l'usine plus chere. Un ratio de port trop genereux etouffait donc l'axe
		industriel — mesure : 20 ports et ZERO usine sur toute la carte. Les deux
		valeurs se lisent ensemble, pas separement.
	]]
	{ kind = Config.BUILDING.PORT, perCity = 0.22, costBias = 0.20, minEra = 1 },
	{ kind = Config.BUILDING.DEFENSE, perCity = 0.28, costBias = 0.16, minEra = 2 },
	{ kind = Config.BUILDING.NAVAL_BASE, perCity = 0.16, costBias = 0.18, minEra = 2 },
	-- Sans ere requise : le jeu ne la verrouille pas non plus (Eras.requiredFor
	-- renvoie 1), et un plan plus strict que la regle du jeu est un piege.
	{ kind = Config.BUILDING.FACTORY, perCity = 0.40, costBias = 0.10, minEra = 1 },
	{ kind = Config.BUILDING.LAB, perCity = 0.20, costBias = 0.15, minEra = 3 },
	{ kind = Config.BUILDING.SAM, perCity = 0.25, costBias = 0.20, minEra = 4 },
	{ kind = Config.BUILDING.SILO, perCity = 0.15, costBias = 0.25, minEra = 4 },
}

Config.BOT_CHAT_CHANCE = 0.12
Config.BOT_CHAT_GREETING_TICKS = 600

--[[
	Delai avant de pouvoir redire EXACTEMENT la meme chose de la meme faction.

	L'anti-spam par simple cooldown ne suffisait pas : une fois la guerre
	commencee, la rancune reste fraiche en permanence, donc le bot repetait son
	appel a l'aide des que le delai tombait. Mesure sur trois mille ticks : 88 %
	des messages emis etaient la meme phrase sur la meme cible.

	Le fil doit rester lisible ; un message qu'on a deja lu n'apporte rien.
]]
Config.QUICKCHAT_REPEAT_TICKS = 900

Config.ALLIANCE_DURATION = 3000 -- ticks, soit 5 minutes
Config.ALLIANCE_COOLDOWN = 150 -- ticks avant de pouvoir resigner avec le meme camp

-- Dons entre allies. Un plancher evite les transferts symboliques d'une
-- unite, qui n'ont d'autre effet que de spammer le fil de notifications.
Config.MIN_DONATION = 100 -- or minimal par don
Config.MIN_DONATION_TROOPS = 100 -- troupes minimales par don
-- Part du tresor envoyee par un don : proportionnelle, elle reste pertinente
-- du debut a la fin de partie sans qu'on ait a la retarifer.
Config.DONATION_SHARE = 0.1

--=============================================================================
-- Coalition anti-leader (bots)
--=============================================================================
-- Sans contrepoids collectif, le premier empire qui decroche gagne en 5 a 10
-- minutes : chacun grignote son voisin plus faible et personne ne s'attaque au
-- leader. Les bots detectent donc une faction dominante et se comportent comme
-- une coalition improvisee : embargos, alliances entre menaces, offensives
-- preferees contre le leader — exactement ce que font les joueurs humains sur
-- Territorial.io.

Config.COALITION_LEADER_RATIO = 1.7 -- tuiles du leader / tuiles moyennes pour etre "dominant"
Config.COALITION_MIN_LEADER_TILES = 250 -- en dessous, c'est juste un bon depart, pas une menace
Config.COALITION_ATTACK_BONUS = 350 -- bonus de score pour attaquer le leader
Config.COALITION_NON_LEADER_DAMPING = 0.4 -- reluctance a se battre entre menaces tant que le leader domine
Config.COALITION_EMBARGO_CHANCE = 0.5 -- par decision, tant que l'embargo n'est pas pose
Config.COALITION_ALLY_CHANCE = 0.6 -- chance de proposer un pacte a un autre menace

--=============================================================================
-- Partie
--=============================================================================

Config.SPAWN_RADIUS = 3
Config.NEUTRAL_SLOT = 0

--[[
	Capacite produit — ne jamais deduire humains/bots de MAX_PLAYERS seul.

	MAX_TOTAL_FACTIONS (alias historique MAX_PLAYERS) est la capacite theorique
	du slot u8 / palette, pas l'objectif de lancement. Le MVP public est 1 humain
	+ bots ; l'alpha multi plafonne les humains separement.
]]
Config.MAX_TOTAL_FACTIONS = 48
Config.MAX_PLAYERS = Config.MAX_TOTAL_FACTIONS -- compat : palette, boucles, remotes
Config.MAX_HUMAN_PLAYERS = 8
Config.MAX_BOTS = 16
Config.PUBLIC_MATCH_CAPACITY = 12 -- MVP : 1 humain + jusqu'a 11 bots (mode classique)
Config.BOT_COUNT = 12 -- defaut mode classique ; les GameModes peuvent surcharger

-- Carte : identite et version pour hash / resync
Config.MAP_ID = "procedural_continents"
Config.MAP_VERSION = 1
Config.GENERATOR_VERSION = 1

-- Rendu : Blocks est le seul chemin de production. CanvasExperimental est
-- reserve a des essais Studio instrumentes, jamais active par defaut.
Config.RENDER_MODE = "Blocks" -- "Blocks" | "CanvasExperimental" | "LowDetail"

-- Intentions reseau
Config.INTENT_RATE_LIMIT_PER_SEC = 20
Config.MAX_PENDING_INTENTS = 32 -- par joueur, file avant flush (dormant si apply immediat)
Config.JOIN_COOLDOWN_SEC = 2 -- anti-spam JoinRequest
Config.SNAPSHOT_COOLDOWN_SEC = 5
Config.MAX_SNAPSHOTS_PER_MATCH = 12

Config.VICTORY_LAND_RATIO = 0.65 -- part des terres a controler pour gagner
Config.MATCH_DURATION = 25 * 60 -- secondes
Config.POST_MATCH_DELAY = 20 -- secondes avant relance

--=============================================================================
-- Presentation
--=============================================================================

-- Palette des factions, choisies pour rester distinctes cote a cote.
Config.PLAYER_COLORS = {
	Color3.fromRGB(231, 76, 60),
	Color3.fromRGB(52, 152, 219),
	Color3.fromRGB(46, 204, 113),
	Color3.fromRGB(241, 196, 15),
	Color3.fromRGB(155, 89, 182),
	Color3.fromRGB(230, 126, 34),
	Color3.fromRGB(26, 188, 156),
	Color3.fromRGB(236, 64, 122),
	Color3.fromRGB(121, 134, 203),
	Color3.fromRGB(205, 220, 57),
	Color3.fromRGB(0, 172, 193),
	Color3.fromRGB(255, 138, 101),
	Color3.fromRGB(124, 179, 66),
	Color3.fromRGB(171, 71, 188),
	Color3.fromRGB(255, 213, 79),
	Color3.fromRGB(38, 198, 218),
}

--[[
	La palette est completee jusqu'a MAX_PLAYERS par rotation d'angle d'or.

	Les 16 teintes ci-dessus sont choisies a la main et restent les plus
	lisibles, donc elles sont attribuees en premier. Au-dela, un simple modulo
	ferait partager la meme couleur a deux factions — sur une carte ou la
	couleur *est* l'identite, deux empires rouges rendent la partie illisible.
	L'angle d'or (137,5 degres) garantit que chaque nouvelle teinte tombe aussi
	loin que possible de toutes les precedentes.
]]
do
	local GOLDEN_ANGLE = 137.507764
	local extra = 0
	while #Config.PLAYER_COLORS < Config.MAX_PLAYERS do
		local hue = ((#Config.PLAYER_COLORS * GOLDEN_ANGLE) % 360) / 360
		-- On alterne saturation et luminosite pour separer aussi les teintes
		-- voisines une fois le cercle chromatique parcouru.
		local saturation = if extra % 2 == 0 then 0.72 else 0.52
		local value = if extra % 3 == 0 then 0.95 else 0.78
		table.insert(Config.PLAYER_COLORS, Color3.fromHSV(hue, saturation, value))
		extra += 1
	end
end

-- Palette du terrain neutre. Volontairement desaturee : les couleurs vives
-- sont reservees aux factions, sinon la carte politique devient illisible.
Config.TERRAIN_COLORS = {
	[0] = Color3.fromRGB(22, 38, 62), -- ocean
	[1] = Color3.fromRGB(206, 190, 148), -- plage
	[2] = Color3.fromRGB(122, 148, 92), -- plaines
	[3] = Color3.fromRGB(164, 160, 104), -- savane
	[4] = Color3.fromRGB(76, 106, 72), -- foret
	[5] = Color3.fromRGB(114, 118, 84), -- collines
	[6] = Color3.fromRGB(124, 114, 98), -- hautes terres
	[7] = Color3.fromRGB(122, 120, 120), -- montagne
	[8] = Color3.fromRGB(226, 230, 236), -- sommet enneige
}

-- Les jetons visuels (couleurs d'interface, espacements, typographie) vivent
-- dans Theme.luau : une seule source de verite pour toute la presentation.

return Config
