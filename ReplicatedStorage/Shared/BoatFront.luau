--!strict
--[[
	Chantier 5 — isolation des fronts bateau (CONQUEST AttackExecution).

	OF : si sourceTile != null, l'attaque ne se combine jamais avec un front terre.
	seedBeachhead créait / renforçait le même Attack que le land → bug.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local Heap = require(ReplicatedStorage.Shared.Heap)

local BoatFront = {}

local priorityScratch = table.create(4, 0)

local function frontPriority(state, index: number, attackerSlot: number): number
	local n = MapGen.neighbors(index, priorityScratch)
	local owned = 0
	for i = 1, n do
		if buffer.readu8(state.owner, priorityScratch[i]) == attackerSlot then
			owned += 1
		end
	end
	local terrain = buffer.readu8(state.terrain, index)
	local roughness = Config.TERRAIN_COST[terrain] or 1
	local noise = (index * 2654435761 + state.tick * 40503) % 8
	return (noise + 10) * (1 - owned * 0.5 + roughness / 2) + state.tick
end

local function enqueueFront(state, atk, index: number)
	if atk.queued[index] then
		return
	end
	atk.queued[index] = true
	Heap.push(atk.frontier, index, frontPriority(state, index, atk.attacker))
end

function BoatFront.install(GameState)
	if GameState.__boatFront then
		return
	end
	GameState.__boatFront = true

	-- Débarquement = toujours un Attack séparé avec sourceTile.
	function GameState.seedBeachhead(self, attackerSlot: number, targetSlot: number, troops: number, tile: number)
		local attack = {
			attacker = attackerSlot,
			target = targetSlot,
			troops = troops,
			frontier = Heap.new(),
			queued = {},
			sourceTile = tile,
		}
		enqueueFront(self, attack, tile)
		table.insert(self.attacks, attack)
	end

	-- launchAttack ne doit fusionner qu'avec des fronts terre (sourceTile nil).
	-- On retire temporairement les fronts bateau pendant l'appel original.
	local origLaunch = GameState.launchAttack
	function GameState.launchAttack(self, attackerSlot: number, targetSlot: number)
		local parked = {}
		for i = #self.attacks, 1, -1 do
			local atk = self.attacks[i]
			if atk.sourceTile ~= nil then
				table.insert(parked, atk)
				table.remove(self.attacks, i)
			end
		end

		local ok, message = origLaunch(self, attackerSlot, targetSlot)

		for _, atk in parked do
			table.insert(self.attacks, atk)
		end

		-- Marquer le front terre nouvellement créé / renforcé
		for _, atk in self.attacks do
			if atk.attacker == attackerSlot and atk.target == targetSlot and atk.sourceTile == nil then
				-- ok land front
			end
		end

		return ok, message
	end
end

return BoatFront
