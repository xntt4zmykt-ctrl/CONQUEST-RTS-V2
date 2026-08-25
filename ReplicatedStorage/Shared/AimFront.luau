--!strict
--[[
	Ancre une offensive sur la case cliquee (modele OpenFront sourceTile).

	Sans ca, launchAttack empile TOUT le contact avec la cible : le front
	mange tout le pourtour. Ici on ne garde que les cases de contact proches
	du clic ; le tas s'etend ensuite voisin par voisin vers le point vise.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local Heap = require(ReplicatedStorage.Shared.Heap)

local AimFront = {}

local scratch = table.create(4, 0)
local SEED_RADIUS = 8
local SEED_RADIUS2 = SEED_RADIUS * SEED_RADIUS

function AimFront.priority(state, atk, index: number): number
	local n = MapGen.neighbors(index, scratch)
	local owned = 0
	for i = 1, n do
		if buffer.readu8(state.owner, scratch[i]) == atk.attacker then
			owned += 1
		end
	end
	local terrain = buffer.readu8(state.terrain, index)
	local roughness = Config.TERRAIN_COST[terrain] or 1
	local noise = (index * 2654435761 + state.tick * 40503) % 8
	local base = (noise + 10) * (1 - owned * 0.5 + roughness / 2) + state.tick
	if atk.aimX then
		local x, y = MapGen.fromIndex(index)
		local dx, dy = x - atk.aimX, y - atk.aimY
		base += (dx * dx + dy * dy) * 0.45
	end
	return base
end

function AimFront.enqueue(state, atk, index: number)
	if atk.queued[index] then
		return
	end
	atk.queued[index] = true
	Heap.push(atk.frontier, index, AimFront.priority(state, atk, index))
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

	local bestDist = math.huge
	local best: number? = nil

	for index in attacker.border do
		local n = MapGen.neighbors(index, scratch)
		for i = 1, n do
			local nb = scratch[i]
			if buffer.readu8(state.owner, nb) == atk.target and state:isLand(nb) then
				local x, y = MapGen.fromIndex(nb)
				local dx, dy = x - ax, y - ay
				local d = dx * dx + dy * dy
				if d < bestDist then
					bestDist = d
					best = nb
				end
				if d <= SEED_RADIUS2 then
					AimFront.enqueue(state, atk, nb)
				end
			end
		end
	end

	if Heap.isEmpty(atk.frontier) and best then
		AimFront.enqueue(state, atk, best)
	end
end

return AimFront
