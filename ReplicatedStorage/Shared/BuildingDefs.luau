--!strict
--[[
	Definitions des batiments.

	Chaque batiment doit repondre a une question strategique distincte :
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
	-- Effets
	popCapBonus: number,
	goldBonus: number,
}

local BuildingDefs = {}

local B = Config.BUILDING

BuildingDefs.LIST = {
	{
		id = B.CITY,
		name = "Ville",
		symbol = "\u{25C6}",
		cost = 180,
		description = "+900 de population maximum",
		coastalOnly = false,
		popCapBonus = 900,
		goldBonus = 0,
	},
	{
		id = B.PORT,
		name = "Port",
		symbol = "\u{2693}",
		cost = 240,
		description = "Debarquements et routes commerciales",
		coastalOnly = true,
		popCapBonus = 0,
		goldBonus = Config.GOLD_PER_PORT,
	},
	{
		id = B.DEFENSE,
		name = "Bunker",
		symbol = "\u{25A0}",
		cost = 200,
		description = "Renforce la defense sur 6 tuiles",
		coastalOnly = false,
		popCapBonus = 0,
		goldBonus = 0,
	},
	{
		id = B.SILO,
		name = "Silo",
		symbol = "\u{25B2}",
		cost = 700,
		description = "Lance des frappes nucleaires",
		coastalOnly = false,
		popCapBonus = 0,
		goldBonus = 0,
	},
	{
		id = B.SAM,
		name = "Batterie SAM",
		symbol = "\u{25CF}",
		cost = 450,
		description = "Intercepte les missiles dans un rayon de 34",
		coastalOnly = false,
		popCapBonus = 0,
		goldBonus = 0,
	},
} :: { BuildingDef }

local byId: { [number]: BuildingDef } = {}
for _, def in BuildingDefs.LIST do
	byId[def.id] = def
end

function BuildingDefs.get(id: number): BuildingDef?
	return byId[id]
end

return BuildingDefs
