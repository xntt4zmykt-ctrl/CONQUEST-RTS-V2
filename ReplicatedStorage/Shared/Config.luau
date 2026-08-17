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

Config.LAND_RATIO = 0.42
Config.HILL_RATIO = 0.28 -- part des terres qui devient colline
Config.MOUNTAIN_RATIO = 0.10 -- part des terres qui devient montagne

Config.TERRAIN = {
	OCEAN = 0,
	PLAINS = 1,
	HILLS = 2,
	MOUNTAIN = 3,
}

-- Multiplicateur de cout de conquete par terrain.
Config.TERRAIN_COST = {
	[0] = math.huge, -- ocean : uniquement par debarquement
	[1] = 1.0,
	[2] = 1.6,
	[3] = 2.8,
}

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
Config.GOLD_TILE_SCALE = 0.0045 -- par tick

Config.GOLD_PER_PORT = 0.22 -- par tick, par port possede
Config.GOLD_PER_CAPITAL = 0.35 -- par tick, tant qu'on tient sa capitale
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
}

-- Perdre sa capitale doit etre un desastre, pas une tuile de plus : c'est ce
-- qui donne un objectif lisible a une offensive et un enjeu a la defense.
Config.CAPITAL_TROOP_LOSS = 0.45 -- part de la reserve perdue par l'ancien proprietaire
Config.CAPITAL_PLUNDER = 400 -- or pris par l'assaillant

Config.DEFENSE_RADIUS = 6
Config.DEFENSE_STRENGTH = 55 -- points de defense au centre, degressif vers le bord
Config.BUILD_MIN_SPACING = 4 -- tuiles entre deux batiments du meme joueur

--=============================================================================
-- Nucleaire
--=============================================================================
-- La phase finale. Elle ne s'ouvre qu'une fois la carte largement partagee,
-- pour qu'elle soit un climax et pas une strategie d'ouverture.

Config.NUKE_UNLOCK_LAND_RATIO = 0.55 -- part des terres colonisees avant deblocage
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

Config.TERRAIN_COLORS = {
	[0] = Color3.fromRGB(22, 38, 62), -- ocean
	[1] = Color3.fromRGB(122, 133, 96), -- plaines
	[2] = Color3.fromRGB(104, 110, 84), -- collines
	[3] = Color3.fromRGB(88, 88, 88), -- montagnes
}

-- Les jetons visuels (couleurs d'interface, espacements, typographie) vivent
-- dans Theme.luau : une seule source de verite pour toute la presentation.

return Config
