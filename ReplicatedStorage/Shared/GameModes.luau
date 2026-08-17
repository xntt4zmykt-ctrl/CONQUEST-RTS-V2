--!strict
--[[
	Modes de jeu.

	Chaque mode n'est qu'un jeu de reglages appliques par-dessus Config : la
	simulation est strictement identique. C'est deliberé — un mode qui change
	les regles doublerait la surface a equilibrer et a tester, alors qu'un mode
	qui change le rythme produit deja des parties tres differentes.

	Le multiplicateur d'ere est le levier central : en Blitz, atteindre l'arme
	nucleaire doit rester possible dans une partie deux fois plus courte, donc
	les paliers coutent moitie moins.
]]

export type GameMode = {
	id: string,
	name: string,
	tagline: string,
	symbol: string,
	duration: number, -- secondes
	botCount: number,
	eraCostMultiplier: number,
	goldMultiplier: number,
}

local GameModes = {}

GameModes.LIST = {
	{
		id = "classic",
		name = "Classique",
		tagline = "25 minutes · 12 nations · le rythme de reference",
		symbol = "\u{1F30D}",
		duration = 25 * 60,
		botCount = 12,
		eraCostMultiplier = 1.0,
		goldMultiplier = 1.0,
	},
	{
		id = "blitz",
		name = "Blitz",
		tagline = "10 minutes · 8 nations · tout va deux fois plus vite",
		symbol = "\u{26A1}",
		duration = 10 * 60,
		botCount = 8,
		eraCostMultiplier = 0.45,
		goldMultiplier = 1.6,
	},
	{
		id = "marathon",
		name = "Marathon",
		tagline = "45 minutes · 16 nations · la carte entiere en jeu",
		symbol = "\u{1F5FA}",
		duration = 45 * 60,
		botCount = 16,
		eraCostMultiplier = 1.5,
		goldMultiplier = 0.85,
	},
} :: { GameMode }

GameModes.DEFAULT = "classic"

function GameModes.get(id: string?): GameMode
	for _, mode in GameModes.LIST do
		if mode.id == id then
			return mode
		end
	end
	return GameModes.LIST[1]
end

return GameModes
