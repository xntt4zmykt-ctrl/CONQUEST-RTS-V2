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

Config.TILE_SIZE = 4
Config.WORLD_WIDTH = Config.MAP_WIDTH * Config.TILE_SIZE
Config.WORLD_DEPTH = Config.MAP_HEIGHT * Config.TILE_SIZE

-- Hauteur du sol par type de terrain. Le relief est franc et etage : c'est ce
-- qui donne la lecture "carte en relief" plutot que "tapis colore".
Config.TERRAIN_HEIGHT = {
	[0] = 0, -- ocean : pas de bloc, seulement le plan d'eau
	[1] = 2,
	[2] = 4,
	[3] = 4,
	[4] = 6,
	[5] = 9,
	[6] = 13,
	[7] = 18,
	[8] = 24,
}

Config.OCEAN_LEVEL = 1.5

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
Config.MAX_TROOPS_PER_TILE = 28
Config.GROWTH_RATE = 0.012 -- fraction de l'ecart au plafond, comblee par tick
Config.MIN_GROWTH = 0.6

--=============================================================================
-- Economie
--=============================================================================
-- L'or achete les batiments. Il vient du territoire et surtout du commerce
-- maritime : c'est ce qui donne un poids economique a la diplomatie, puisqu'un
-- embargo coupe litteralement les revenus de l'autre.

Config.START_GOLD = 120

-- Le revenu territorial est volontairement sous-lineaire (tiles^0.8) : un
-- empire deux fois plus grand ne gagne pas deux fois plus. Sans cet
-- amortissement, le leader s'auto-finance a l'infini et la fin de partie
-- devient une formalite — mesure en simulation, un revenu lineaire produisait
-- 4,4 millions d'or morts en dix minutes.
Config.GOLD_TILE_EXPONENT = 0.8
Config.GOLD_TILE_SCALE = 0.0042 -- par tick

Config.GOLD_PER_PORT = 0.22 -- par tick, par port possede
-- Volontairement faible : un joueur qui accumule les capitales conquises en
-- tenait douze en simulation, soit l'equivalent de plusieurs milliers de
-- territoires en revenu. La capitale est un objectif militaire, pas une rente.
Config.GOLD_PER_CAPITAL = 0.08 -- par tick, par capitale tenue
Config.TRADE_GOLD_PER_PARTNER = 0.14 -- par tick, par partenaire commercial
Config.TRADE_SHIP_INTERVAL = 45 -- ticks entre deux navires marchands (visuel)

--=============================================================================
-- Attaque
--=============================================================================

Config.DEFAULT_ATTACK_RATIO = 0.25
Config.MIN_ATTACK_TROOPS = 20
Config.ATTACK_SPEND_RATE = 0.035 -- part du corps expeditionnaire depensee par tick
Config.TILE_BASE_COST = 1.4
Config.NEUTRAL_COST_MULT = 0.75
Config.DEFENSE_DENSITY_K = 0.9 -- poids de la densite de troupes adverse
Config.DEFENDER_LOSS_RATIO = 0.55
Config.MAX_TILES_PER_TICK = 400

--=============================================================================
-- Marine
--=============================================================================
-- Sans debarquements, un joueur insulaire est en prison et un continent est
-- imprenable. C'est la mecanique qui ouvre la carte.

Config.BOAT_SPEED = 0.85 -- tuiles par tick
Config.BOAT_TROOP_RATIO = 0.4 -- part max de la reserve embarquee
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
Config.CAPITAL_PLUNDER = 150 -- or pris par l'assaillant

Config.DEFENSE_RADIUS = 6
Config.DEFENSE_STRENGTH = 55 -- points de defense au centre, degressif vers le bord
Config.BUILD_MIN_SPACING = 4 -- tuiles entre deux batiments du meme joueur

-- Chaque batiment supplementaire du meme type coute plus cher. Sans cette
-- inflation, un empire riche empile trois cents villes et le jeu se resume a
-- cliquer partout : la simulation en produisait 357 en dix minutes. Avec un
-- facteur de 0.35, la cinquieme ville coute deja 2,4 fois la premiere.
Config.BUILD_COST_SCALING = 0.35

--=============================================================================
-- Nucleaire
--=============================================================================
-- La phase finale. Elle ne s'ouvre qu'une fois la carte largement partagee,
-- pour qu'elle soit un climax et pas une strategie d'ouverture.

Config.MISSILE_SPEED = 1.6 -- tuiles par tick
Config.SAM_RANGE = 34
Config.SAM_INTERCEPT_CHANCE = 0.55
Config.SAM_COOLDOWN = 90 -- ticks

Config.NUKE = {
	ATOM = 1,
	HYDROGEN = 2,
}

Config.NUKE_STATS = {
	[1] = { radius = 9, troopKill = 0.30, cost = 550, name = "Bombe atomique" },
	[2] = { radius = 20, troopKill = 0.55, cost = 1400, name = "Bombe H" },
}

--=============================================================================
-- Diplomatie
--=============================================================================

Config.ALLIANCE_REQUEST_TIMEOUT = 300 -- ticks avant expiration d'une demande
Config.BETRAYAL_REPUTATION_COST = 1
Config.TRAITOR_MARK_DURATION = 1800 -- ticks pendant lesquels la trahison est affichee

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
Config.MAX_PLAYERS = 48
Config.BOT_COUNT = 12

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
