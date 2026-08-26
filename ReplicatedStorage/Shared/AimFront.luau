--!strict
--[[
	Sélection de cases = AttackExecution.addNeighbors / sourceTile CONQUEST.

	Land click : on ancre UNE case source (la case cliquée si elle touche
	notre bordure, sinon le contact le plus proche). Pas de disque, pas de
	biais distance. La direction vient de la formule OF :
	  (noise+10) * (1 - voisinsAMoi*0.5 + mag/2) + tick
	  mag = plaine 1 / highland 1.5 / montagne 2
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local Heap = require(ReplicatedStorage.Shared.Heap)

local AimFront = {}

local scratch = table.create(4, 0)
local innerScratch = table.create(4, 0)

function AimFront.terrainMag(terrain: number): number
	local T = Config.TERRAIN
	if terrain == T.MOUNTAIN or terrain == T.PEAK then
		return 2
	end
	if terrain == T.HILLS or terrain == T.HIGHLAND then
		return 1.5
	end
	return 1
end

function AimFront.priority(state, atk, index: number): number
	local n = MapGen.neighbors(index, innerScratch)
	local owned = 0
	for i = 1, n do
		if buffer.readu8(state.owner, innerScratch[i]) == atk.attacker then
			owned += 1
		end
	end
	local mag = AimFront.terrainMag(buffer.readu8(state.terrain, index))
	local noise = (index * 2654435761 + state.tick * 40503) % 8
	return (noise + 10) * (1 - owned * 0.5 + mag / 2) + state.tick
end

function AimFront.enqueue(state, atk, index: number)
	if atk.queued[index] then
		return
	end
	atk.queued[index] = true
	Heap.push(atk.frontier, index, AimFront.priority(state, atk, index))
end

local function isTargetLand(state, index: number, targetSlot: number): boolean
	return state:isLand(index) and buffer.readu8(state.owner, index) == targetSlot
end

local function touchesAttacker(state, index: number, attackerSlot: number): boolean
	local n = MapGen.neighbors(index, scratch)
	for i = 1, n do
		if buffer.readu8(state.owner, scratch[i]) == attackerSlot then
			return true
		end
	end
	return false
end

function AimFront.addNeighbors(state, atk, tile: number)
	local n = MapGen.neighbors(tile, scratch)
	for i = 1, n do
		local nb = scratch[i]
		if isTargetLand(state, nb, atk.target) then
			AimFront.enqueue(state, atk, nb)
		end
	end
end

function AimFront.focus(state, atk, aimTile: number)
	if aimTile < 0 or aimTile >= Config.TILE_COUNT then
		return
	end

	local ax, ay = MapGen.fromIndex(aimTile)
	atk.aimX = ax
	atk.aimY = ay
	atk.sourceTile = aimTile

	local attacker = state.players[atk.attacker]
	if not attacker then
		return
	end

	atk.frontier = Heap.new()
	atk.queued = {}

	-- OF sourceTile : addNeighbors(source) seulement.
	-- Si le clic est déjà une case cible au contact, c'est la source.
	if isTargetLand(state, aimTile, atk.target) and touchesAttacker(state, aimTile, atk.attacker) then
		AimFront.enqueue(state, atk, aimTile)
		AimFront.addNeighbors(state, atk, aimTile)
		return
	end

	-- Clic à l'intérieur / loin : une seule case de contact, la plus proche.
	local bestDist = math.huge
	local best: number? = nil
	for index in attacker.border do
		local n = MapGen.neighbors(index, scratch)
		for i = 1, n do
			local nb = scratch[i]
			if isTargetLand(state, nb, atk.target) then
				local x, y = MapGen.fromIndex(nb)
				local dx, dy = x - ax, y - ay
				local d = dx * dx + dy * dy
				if d < bestDist then
					bestDist = d
					best = nb
				end
			end
		end
	end

	if best then
		AimFront.enqueue(state, atk, best)
		AimFront.addNeighbors(state, atk, best)
	end
end

return AimFront
