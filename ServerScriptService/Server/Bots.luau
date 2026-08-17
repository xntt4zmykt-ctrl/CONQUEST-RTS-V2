--!strict
--[[
	Bots de remplissage.

	Leur vrai role est de rendre le prototype testable en solo : sans eux la
	carte est vide et on ne peut rien juger de l'equilibrage. Leur IA est
	volontairement basique (attaquer le voisin le plus faible au contact), elle
	sera remplacee quand la boucle de base sera validee.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local GameState = require(script.Parent.GameState)

type GameState = GameState.GameState

local Bots = {}

local BOT_COUNT = 10
local DECISION_INTERVAL = 12 -- ticks entre deux decisions d'un bot

local BOT_NAMES = {
	"Aurelia",
	"Kessrin",
	"Vodark",
	"Meridia",
	"Tarnhold",
	"Ozmark",
	"Cindral",
	"Halvern",
	"Ruskaya",
	"Belmoro",
	"Ysgard",
	"Corvane",
}

local botSlots: { number } = {}
local tickCounter = 0
local scratch = table.create(4, 0)

function Bots.spawnAll(state: GameState, rng: Random)
	table.clear(botSlots)
	for i = 1, BOT_COUNT do
		local name = BOT_NAMES[((i - 1) % #BOT_NAMES) + 1]
		local ps = state:addPlayer(nil, name, rng)
		if ps then
			ps.attackRatio = rng:NextNumber(0.2, 0.45)
			table.insert(botSlots, ps.slot)
		end
	end
end

--[[
	Renvoie les factions au contact terrestre du slot donne, avec le nombre de
	tuiles de contact (utilise comme mesure grossiere de la longueur du front).
]]
local function neighborFactions(state: GameState, slot: number): { [number]: number }
	local ps = state.players[slot]
	local contacts: { [number]: number } = {}
	if not ps then
		return contacts
	end

	for index in ps.border do
		local n = MapGen.neighbors(index, scratch)
		for i = 1, n do
			local nb = scratch[i]
			if state:isLand(nb) then
				local other = buffer.readu8(state.owner, nb)
				if other ~= slot then
					contacts[other] = (contacts[other] or 0) + 1
				end
			end
		end
	end

	return contacts
end

function Bots.step(state: GameState, rng: Random)
	tickCounter += 1

	for i = #botSlots, 1, -1 do
		local slot = botSlots[i]
		local ps = state.players[slot]
		if not ps then
			table.remove(botSlots, i)
			continue
		end

		-- Decisions decalees dans le temps : sinon tous les bots attaquent au
		-- meme tick et la carte explose d'un coup.
		if (tickCounter + slot * 3) % DECISION_INTERVAL ~= 0 then
			continue
		end

		if ps.troops < Config.MIN_ATTACK_TROOPS * 3 then
			continue -- on laisse remonter la reserve
		end

		local contacts = neighborFactions(state, slot)
		local bestTarget: number? = nil
		local bestScore = -math.huge

		for other, contactTiles in contacts do
			local score: number
			if other == Config.NEUTRAL_SLOT then
				-- Le terrain vierge est prioritaire tant qu'il en reste :
				-- c'est le comportement humain naturel en debut de partie.
				score = 1000 + contactTiles
			else
				local target = state.players[other]
				if not target then
					continue
				end
				-- Cible d'autant plus attirante qu'elle est faible par tuile.
				local density = target.troops / math.max(1, target.tiles)
				score = 100 / (1 + density) + contactTiles * 0.5
			end

			score += rng:NextNumber(0, 15) -- un peu d'imprevisibilite
			if score > bestScore then
				bestScore = score
				bestTarget = other
			end
		end

		if bestTarget then
			state:launchAttack(slot, bestTarget)
		end
	end
end

return Bots
