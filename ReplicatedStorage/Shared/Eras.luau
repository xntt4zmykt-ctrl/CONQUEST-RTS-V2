--!strict
--[[
	Eres technologiques.

	Ce systeme remplace l'ancien deblocage du nucleaire par pourcentage de
	terres colonisees, qui etait une erreur de conception : il mesurait la
	vitesse a laquelle la carte se remplit, pas l'effort d'un joueur. Avec douze
	factions, le terrain neutre disparaissait en quarante secondes et tout le
	monde avait la bombe avant la premiere minute.

	Ici, l'avancement est **individuel et achete**. Chaque ere coute de l'or et
	exige un developpement reel (des villes, un port, un silo). Le temps
	necessaire n'est pas un minuteur arbitraire : c'est celui qu'il faut pour
	accumuler la somme, donc un joueur qui developpe son economie y arrive plus
	vite qu'un joueur qui ne fait que conquerir.

	Regle d'equilibrage : chaque ere doit apporter un gain immediat (le bonus)
	*et* ouvrir une option nouvelle (le deblocage). Une ere qui n'apporte qu'un
	pourcentage n'est pas une decision, c'est une taxe.
]]

local Config = require(script.Parent.Config)

local B = Config.BUILDING

export type Era = {
	id: number,
	name: string,
	tagline: string,
	symbol: string,
	-- Cout et conditions pour ACCEDER a cette ere depuis la precedente.
	cost: number,
	requiredTiles: number,
	requiredBuildings: { [number]: number },
	-- Ce que l'ere rend constructible
	unlocks: { number },
	-- Bonus passifs permanents
	goldMultiplier: number,
	growthMultiplier: number,
	defenseMultiplier: number,
}

local Eras = {}

Eras.LIST = {
	{
		id = 1,
		name = "Colonisation",
		tagline = "Prendre pied et s'etendre",
		symbol = "\u{1F331}",
		cost = 0,
		requiredTiles = 0,
		requiredBuildings = {},
		unlocks = { B.CITY, B.PORT },
		goldMultiplier = 1.0,
		growthMultiplier = 1.0,
		defenseMultiplier = 1.0,
	},
	{
		id = 2,
		name = "Fortification",
		tagline = "Tenir ce qu'on a pris",
		symbol = "\u{1F6E1}",
		cost = 1400,
		requiredTiles = 260,
		requiredBuildings = { [B.CITY] = 1 },
		unlocks = { B.DEFENSE },
		goldMultiplier = 1.0,
		growthMultiplier = 1.08,
		defenseMultiplier = 1.15,
	},
	{
		id = 3,
		name = "Industrie",
		tagline = "L'economie devient une arme",
		symbol = "\u{2699}",
		cost = 7800,
		requiredTiles = 900,
		requiredBuildings = { [B.CITY] = 3, [B.PORT] = 1 },
		unlocks = { B.LAB, B.FACTORY },
		goldMultiplier = 1.35,
		growthMultiplier = 1.12,
		defenseMultiplier = 1.0,
	},
	{
		id = 4,
		name = "Atomique",
		tagline = "Le seuil que personne ne pardonne",
		symbol = "\u{2622}",
		cost = 28500,
		requiredTiles = 2200,
		requiredBuildings = { [B.CITY] = 6, [B.DEFENSE] = 2 },
		unlocks = { B.SILO, B.SAM },
		goldMultiplier = 1.1,
		growthMultiplier = 1.0,
		defenseMultiplier = 1.05,
	},
	{
		id = 5,
		name = "Thermonucleaire",
		tagline = "Rien ne survit a la seconde frappe",
		symbol = "\u{1F4A5}",
		cost = 69000,
		requiredTiles = 4500,
		requiredBuildings = { [B.SILO] = 1, [B.CITY] = 8 },
		unlocks = {},
		goldMultiplier = 1.2,
		growthMultiplier = 1.0,
		defenseMultiplier = 1.1,
	},
} :: { Era }

Eras.MAX_ID = #Eras.LIST

function Eras.get(id: number): Era
	return Eras.LIST[math.clamp(id, 1, Eras.MAX_ID)]
end

--[[
	Multiplicateurs cumules jusqu'a l'ere atteinte : les bonus s'empilent, donc
	rester en retard coute de plus en plus cher.
]]
function Eras.accumulate(eraId: number): { gold: number, growth: number, defense: number }
	local gold, growth, defense = 1.0, 1.0, 1.0
	for id = 1, math.clamp(eraId, 1, Eras.MAX_ID) do
		local era = Eras.LIST[id]
		gold *= era.goldMultiplier
		growth *= era.growthMultiplier
		defense *= era.defenseMultiplier
	end
	return { gold = gold, growth = growth, defense = defense }
end

-- Ere minimale requise pour construire un batiment donne.
local eraForBuilding: { [number]: number } = {}
for _, era in Eras.LIST do
	for _, kind in era.unlocks do
		eraForBuilding[kind] = era.id
	end
end

function Eras.requiredFor(buildingKind: number): number
	return eraForBuilding[buildingKind] or 1
end

-- La bombe H demande une ere de plus que la bombe atomique : le palier final
-- doit rester un evenement rare, pas une simple montee de gamme.
function Eras.requiredForNuke(nukeKind: number): number
	return if nukeKind == Config.NUKE.HYDROGEN then 5 else 4
end

return Eras
