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
	cost: number,
	description: string,
	coastalOnly: boolean,
	-- Une capitale est posee par le moteur au spawn et ne s'achete jamais.
	buildable: boolean,
	class: string,
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
		popCapBonus = 1500,
		goldBonus = 0.35,
	},
	{
		id = B.CITY,
		class = Config.BUILD_CLASS.ECONOMY,
		name = "Ville",
		symbol = "\u{25C6}",
		cost = 180,
		description = "+900 de population maximum",
		coastalOnly = false,
		buildable = true,
		popCapBonus = 900,
		goldBonus = 0,
	},
	{
		id = B.PORT,
		class = Config.BUILD_CLASS.ECONOMY,
		name = "Port",
		symbol = "\u{2693}",
		cost = 240,
		description = "Debarquements et routes commerciales",
		coastalOnly = true,
		buildable = true,
		popCapBonus = 0,
		goldBonus = Config.GOLD_PER_PORT,
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

return BuildingDefs
