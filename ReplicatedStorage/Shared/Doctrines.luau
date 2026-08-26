--!strict
--[[
	Doctrines : le choix d'ouverture du joueur.

	Chaque doctrine est un jeu de multiplicateurs applique partout dans la
	simulation. Elles sont volontairement asymetriques — chacune a une vraie
	faiblesse — pour que le choix soit un pari et pas une optimisation.

	Regle d'equilibrage : aucune doctrine ne doit etre meilleure partout. Si tu
	ajoutes un bonus ici, ajoute le malus correspondant.
]]

export type Doctrine = {
	id: number,
	name: string,
	tagline: string,
	symbol: string,
	-- Multiplicateurs, 1.0 = neutre
	growth: number, -- vitesse de croissance de population
	goldRate: number, -- revenus
	attack: number, -- efficacite offensive (baisse le cout par tuile)
	defense: number, -- resistance (monte le cout paye par l'assaillant)
	buildCost: number, -- prix des batiments
	boatSpeed: number,
	boatCapacity: number,
}

local Doctrines = {}

Doctrines.LIST = {
	{
		id = 1,
		name = "Industrielle",
		tagline = "Economie forte, armee lente a demarrer",
		symbol = "\u{2699}",
		growth = 0.9,
		goldRate = 1.45,
		attack = 1.0,
		defense = 1.0,
		buildCost = 0.85,
		boatSpeed = 1.0,
		boatCapacity = 1.0,
	},
	{
		id = 2,
		name = "Maritime",
		tagline = "Maitrise des mers, faible en terrain montagneux",
		symbol = "\u{2693}",
		growth = 1.0,
		goldRate = 1.15,
		attack = 0.95,
		defense = 0.95,
		buildCost = 1.0,
		boatSpeed = 1.5,
		boatCapacity = 1.6,
	},
	{
		id = 3,
		name = "Zelote",
		tagline = "Offensive devastatrice, defense de papier",
		symbol = "\u{2694}",
		growth = 1.15,
		goldRate = 0.85,
		attack = 1.35,
		defense = 0.7,
		buildCost = 1.15,
		boatSpeed = 1.0,
		boatCapacity = 1.0,
	},
	{
		id = 4,
		name = "Ingenieur",
		tagline = "Imprenable, mais conquiert lentement",
		symbol = "\u{1F6E1}",
		growth = 0.95,
		goldRate = 1.0,
		attack = 0.8,
		defense = 1.45,
		buildCost = 0.7,
		boatSpeed = 0.9,
		boatCapacity = 1.0,
	},
} :: { Doctrine }

Doctrines.DEFAULT_ID = 1

function Doctrines.isValid(id: number?): boolean
	if typeof(id) ~= "number" or id ~= math.floor(id) then
		return false
	end
	for _, doctrine in Doctrines.LIST do
		if doctrine.id == id then
			return true
		end
	end
	return false
end

function Doctrines.get(id: number?): Doctrine
	for _, doctrine in Doctrines.LIST do
		if doctrine.id == id then
			return doctrine
		end
	end
	return Doctrines.LIST[Doctrines.DEFAULT_ID]
end

return Doctrines
