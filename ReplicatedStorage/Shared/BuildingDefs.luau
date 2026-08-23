--!strict
--[[
	Definitions des batiments.

	Chaque batiment doit repondre a une question strategique distincte :
	  Capitale -> "voici mon coeur, et sa perte me ruine"
	  Ville    -> "je veux plus d'armee"
	  Port     -> "je veux sortir de mon continent et gagner de l'or"
	  Bunker   -> "je veux tenir cette frontiere"
	  Silo     -> "je veux frapper loin"
	  Batterie -> "je veux survivre a la phase nucleaire"

	Si deux batiments repondent a la meme question, il y en a un de trop.
]]

local Config = require(script.Parent.Config)

export type BuildingDef = {
	id: number,
	name: string,
	symbol: string,
	--[[
		Icone televersee, si elle existe.

		Le `symbol` reste la valeur de repli : tous les batiments n'ont pas
		encore leur image, et un glyphe geometrique vaut mieux qu'une case vide.
		Les icones sont **blanches sur fond transparent** pour pouvoir etre
		teintees par le code (ImageColor3) — verrouillee, trop chere, selectionnee
		— au lieu de demander un fichier par etat.
	]]
	icon: string?,
	cost: number,
	description: string,
	coastalOnly: boolean,
	-- Une capitale est posee par le moteur au spawn et ne s'achete jamais.
	buildable: boolean,
	class: string,
	-- Un batiment ameliorable ne se multiplie pas : cliquer a cote d'un
	-- exemplaire existant fait monter son niveau au lieu d'en poser un second.
	-- Les autres (bunker, silo, batterie, laboratoire) n'ont pas de palier :
	-- leur effet est binaire ou deja plafonne.
	upgradable: boolean,
	maxLevel: number,
	-- Effets
	popCapBonus: number,
	goldBonus: number,
}

local BuildingDefs = {}

local B = Config.BUILDING

BuildingDefs.LIST = {
	{
		id = B.CAPITAL,
		class = Config.BUILD_CLASS.ECONOMY,
		name = "Capitale",
		symbol = "\u{2605}",
		cost = 0,
		description = "Ton coeur. Sa chute te coute la moitie de ton armee.",
		coastalOnly = false,
		buildable = false,
		upgradable = false,
		maxLevel = 1,
		popCapBonus = 1500,
		goldBonus = 0.35,
	},
	{
		id = B.CITY,
		class = Config.BUILD_CLASS.ECONOMY,
		name = "Ville",
		symbol = "\u{25C6}",
		icon = "rbxassetid://93337869483061",
		cost = 180,
		description = "+900 population · evolue jusqu'a la megapole",
		coastalOnly = false,
		buildable = true,
		upgradable = true,
		maxLevel = 3,
		popCapBonus = 900,
		goldBonus = Config.GOLD_PER_CITY,
	},
	{
		id = B.PORT,
		class = Config.BUILD_CLASS.ECONOMY,
		name = "Port",
		symbol = "\u{2693}",
		icon = "rbxassetid://97420837111496",
		cost = 240,
		description = "Debarquements et routes commerciales",
		coastalOnly = true,
		buildable = true,
		upgradable = true,
		maxLevel = 3,
		popCapBonus = 0,
		goldBonus = Config.GOLD_PER_PORT,
	},
	{
		id = B.FACTORY,
		class = Config.BUILD_CLASS.ECONOMY,
		name = "Usine",
		symbol = "\u{2699}",
		icon = "rbxassetid://90043183233347",
		cost = 520,
		description = "Expedie des colis vers les gares proches : chaque livraison rapporte de l'or",
		coastalOnly = false,
		buildable = true,
		upgradable = true,
		maxLevel = 3,
		popCapBonus = 0,
		goldBonus = 0,
	},
	{
		id = B.DEFENSE,
		class = Config.BUILD_CLASS.MILITARY,
		name = "Bunker",
		symbol = "\u{25A0}",
		cost = 200,
		description = "Renforce la defense sur 6 tuiles",
		coastalOnly = false,
		buildable = true,
		upgradable = false,
		maxLevel = 1,
		popCapBonus = 0,
		goldBonus = 0,
	},
	{
		id = B.NAVAL_BASE,
		class = Config.BUILD_CLASS.MILITARY,
		name = "Base navale",
		symbol = "\u{2388}",
		cost = 380,
		description = "Entretient un porte-avions qui intercepte les debarquements",
		coastalOnly = true,
		buildable = true,
		upgradable = false,
		maxLevel = 1,
		popCapBonus = 0,
		goldBonus = 0,
	},
	{
		id = B.SILO,
		class = Config.BUILD_CLASS.MILITARY,
		name = "Silo",
		symbol = "\u{25B2}",
		cost = 700,
		description = "Lance des frappes nucleaires",
		coastalOnly = false,
		buildable = true,
		upgradable = false,
		maxLevel = 1,
		popCapBonus = 0,
		goldBonus = 0,
	},
	{
		id = B.SAM,
		class = Config.BUILD_CLASS.MILITARY,
		name = "Batterie SAM",
		symbol = "\u{25CF}",
		cost = 450,
		description = "Intercepte les missiles dans un rayon de 34",
		coastalOnly = false,
		buildable = true,
		upgradable = false,
		maxLevel = 1,
		popCapBonus = 0,
		goldBonus = 0,
	},
	{
		id = B.LAB,
		class = Config.BUILD_CLASS.SCIENCE,
		name = "Laboratoire",
		symbol = "\u{2697}",
		cost = 420,
		description = "-7 % sur le cout de chaque ere (max -35 %)",
		coastalOnly = false,
		buildable = true,
		upgradable = false,
		maxLevel = 1,
		popCapBonus = 0,
		goldBonus = 0,
	},
} :: { BuildingDef }

--[[
	Ordre d'affichage des classes dans le menu de construction. L'economie
	d'abord : c'est ce qu'on construit en premier et le plus souvent.
]]
BuildingDefs.CLASSES = {
	{ id = Config.BUILD_CLASS.ECONOMY, name = "Economie", symbol = "\u{1F3E0}" },
	{ id = Config.BUILD_CLASS.MILITARY, name = "Militaire", symbol = "\u{2694}" },
	{ id = Config.BUILD_CLASS.SCIENCE, name = "Science", symbol = "\u{2697}" },
}

local byId: { [number]: BuildingDef } = {}
for _, def in BuildingDefs.LIST do
	byId[def.id] = def
end

-- Uniquement ce que le joueur peut acheter : c'est cette liste que l'interface
-- affiche, la capitale n'y figure jamais.
BuildingDefs.BUILDABLE = {}
for _, def in BuildingDefs.LIST do
	if def.buildable then
		table.insert(BuildingDefs.BUILDABLE, def)
	end
end

-- Constructibles regroupes par classe, prets a alimenter les onglets.
BuildingDefs.BY_CLASS = {}
for _, class in BuildingDefs.CLASSES do
	local group = {}
	for _, def in BuildingDefs.BUILDABLE do
		if def.class == class.id then
			table.insert(group, def)
		end
	end
	BuildingDefs.BY_CLASS[class.id] = group
end

function BuildingDefs.get(id: number): BuildingDef?
	return byId[id]
end

function BuildingDefs.isUpgradable(id: number): boolean
	local def = byId[id]
	return def ~= nil and def.upgradable and def.maxLevel > 1
end

function BuildingDefs.maxLevel(id: number): number
	local def = byId[id]
	return if def then def.maxLevel else 1
end

return BuildingDefs
