--!strict
-- Toutes les constantes de gameplay au meme endroit.
-- C'est ici qu'on tune l'equilibrage : ne pas eparpiller ces valeurs ailleurs.

local Config = {}

-- Identite
Config.GAME_NAME = "CONQUEST RTS"
Config.STUDIO_NAME = "Blackline Studio"

-- Carte (en tuiles). 256x160 = 40 960 tuiles : assez grand pour ~30 joueurs,
-- assez petit pour tenir dans une EditableImage sans compromis de perf.
Config.MAP_WIDTH = 256
Config.MAP_HEIGHT = 160
Config.TILE_COUNT = Config.MAP_WIDTH * Config.MAP_HEIGHT

-- Fraction de la carte qui doit etre de la terre. Le generateur calibre
-- ses seuils pour atteindre ce ratio quelle que soit la seed.
Config.LAND_RATIO = 0.42
Config.HILL_RATIO = 0.28 -- part des terres qui devient colline
Config.MOUNTAIN_RATIO = 0.10 -- part des terres qui devient montagne

-- Terrains
Config.TERRAIN = {
	OCEAN = 0,
	PLAINS = 1,
	HILLS = 2,
	MOUNTAIN = 3,
}

-- Multiplicateur de cout de conquete par terrain.
Config.TERRAIN_COST = {
	[0] = math.huge, -- ocean : infranchissable sans bateau (phase 2)
	[1] = 1.0,
	[2] = 1.6,
	[3] = 2.8,
}

-- Boucle de simulation
Config.TICK_RATE = 10 -- ticks serveur par seconde
Config.TICK_DT = 1 / Config.TICK_RATE

-- Population
Config.START_TROOPS = 120
Config.BASE_MAX_TROOPS = 200 -- plafond meme sans territoire
Config.MAX_TROOPS_PER_TILE = 28
Config.GROWTH_RATE = 0.012 -- fraction de l'ecart au plafond, comblee par tick
Config.MIN_GROWTH = 0.5 -- croissance plancher, evite de rester bloque a 0

-- Attaque
Config.DEFAULT_ATTACK_RATIO = 0.25
Config.MIN_ATTACK_TROOPS = 20
Config.ATTACK_SPEND_RATE = 0.035 -- part du corps expeditionnaire depensee par tick
Config.TILE_BASE_COST = 1.4 -- cout de base pour prendre une tuile
Config.NEUTRAL_COST_MULT = 0.75 -- le terrain vierge est plus facile a prendre
Config.DEFENSE_DENSITY_K = 0.9 -- poids de la densite de troupes adverse
Config.DEFENDER_LOSS_RATIO = 0.55 -- part du cout qui est aussi retiree au defenseur
Config.MAX_TILES_PER_TICK = 400 -- garde-fou anti-freeze

-- Spawn
Config.SPAWN_RADIUS = 3 -- rayon (en tuiles) du territoire de depart

-- Reseau
Config.NEUTRAL_SLOT = 0
Config.MAX_PLAYERS = 48

-- Palette des factions. Choisies pour rester distinctes une fois cote a cote
-- et lisibles sur le fond ocean/terrain desature.
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

-- Couleurs du terrain neutre
Config.TERRAIN_COLORS = {
	[0] = Color3.fromRGB(28, 44, 68), -- ocean
	[1] = Color3.fromRGB(122, 133, 96), -- plaines
	[2] = Color3.fromRGB(104, 110, 84), -- collines
	[3] = Color3.fromRGB(88, 88, 88), -- montagnes
}

return Config
