--!strict
--[[
	Tribus PvE — port tribus PvE / TribeSpawner.

	IA allégée vs bots :
	  - colonise d'abord le neutre (terra nullius)
	  - accepte toutes les alliances
	  - n'attaque les humains que rarement (sauf rancune)
	  - pas de nuke / marine

	Décisions espacées pour le CCU (20 % Roblox).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local GameState = require(script.Parent.GameState)
local Diplomacy = require(script.Parent.Diplomacy)

type GameState = GameState.GameState

local Tribes = {}

local NEUTRAL = Config.NEUTRAL_SLOT
local DECISION_INTERVAL = 12
local scratch = table.create(4, 0)

local TRIBE_NAMES = {
	"Horde des Brumes",
	"Clan de pierre",
	"Peuple des dunes",
	"Marcheurs du sel",
	"Tribu de l'ardoise",
	"Fils du delta",
	"Veilleurs du col",
	"Bande du bas-marais",
	"Cercle des pins",
	"Nomades du plateau",
	"Freres de la faille",
	"Garde des roseaux",
}

local tribeSlots: { number } = {}

function Tribes.spawnAll(state: GameState, rng: Random, count: number?)
	table.clear(tribeSlots)
	local n = count or (Config.TRIBE_COUNT or 6)
	local startTroops = Config.TRIBE_START_TROOPS or 4000
	for i = 1, n do
		local name = TRIBE_NAMES[((i - 1) % #TRIBE_NAMES) + 1]
		if i > #TRIBE_NAMES then
			name = `{name} {i}`
		end
		local ps = state:addPlayer(nil, name, rng, 0)
		if ps then
			ps.isBot = true
			ps.isTribe = true
			ps.troops = startTroops
			ps.attackRatio = rng:NextNumber(0.35, 0.55)
			table.insert(tribeSlots, ps.slot)
		end
	end
end

local function acceptAlliances(state: GameState, slot: number)
	for other, targets in state.requests do
		if targets[slot] then
			Diplomacy.accept(state, other, slot)
		end
	end
end

local function contactsNeutral(state: GameState, ps): boolean
	for index in ps.border do
		local n = MapGen.neighbors(index, scratch)
		for i = 1, n do
			local nb = scratch[i]
			if state:isLand(nb) and buffer.readu8(state.owner, nb) == NEUTRAL then
				return true
			end
		end
	end
	return false
end

local function contactCount(state: GameState, ps, other: number): number
	local contact = 0
	for index in ps.border do
		local n = MapGen.neighbors(index, scratch)
		for i = 1, n do
			if buffer.readu8(state.owner, scratch[i]) == other then
				contact += 1
			end
		end
	end
	return contact
end

local function decideAttack(state: GameState, ps, rng: Random)
	if contactsNeutral(state, ps) then
		state:launchAttack(ps.slot, NEUTRAL)
		return
	end

	local best: number? = nil
	local bestScore = -math.huge
	for other, target in state.players do
		if other == ps.slot or not target.alive then
			continue
		end
		if state:areAllied(ps.slot, other) then
			continue
		end
		if not target.isBot and not target.isTribe then
			if not state:holdsGrudge(ps.slot, other) and rng:NextNumber() > 0.12 then
				continue
			end
		end
		local contact = contactCount(state, ps, other)
		if contact == 0 then
			continue
		end
		local density = target.troops / math.max(1, target.tiles)
		local score = 80 / (1 + density) + contact
		if state:holdsGrudge(ps.slot, other) then
			score += 40
		end
		if target.isTribe then
			score *= 0.6
		end
		score += rng:NextNumber(0, 10)
		if score > bestScore then
			bestScore = score
			best = other
		end
	end
	if best then
		state:launchAttack(ps.slot, best)
	end
end

function Tribes.step(state: GameState, rng: Random)
	for i = #tribeSlots, 1, -1 do
		local slot = tribeSlots[i]
		local ps = state.players[slot]
		if not ps or not ps.isTribe then
			table.remove(tribeSlots, i)
			continue
		end
		if (state.tick + slot * 5) % DECISION_INTERVAL ~= 0 then
			continue
		end
		acceptAlliances(state, slot)
		decideAttack(state, ps, rng)
	end
end

return Tribes
