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
-- V44 : wrap launchAttack recycle la liste des tetes de pont (recette
-- collapsingBuf / V41). Attack live, pas des copies. Truncate leftover
-- AVANT origLaunch — un leftover reinserait un pont fantome. Non reentrant
-- (launchAttack synchrone). Distinct de seedBeachhead / AimFront / V29 HUD.
local parkedBuf: { any } = table.create(8)

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

	-- Debarquement = Attack separe avec isBeachhead. sourceTile reste l'ancre
	-- visuelle ; AimFront pose aussi sourceTile sur un front terre, donc le
	-- parking ne doit jamais se fier a sourceTile seul.
	function GameState.seedBeachhead(self, attackerSlot: number, targetSlot: number, troops: number, tile: number)
		local attack = {
			attacker = attackerSlot,
			target = targetSlot,
			troops = troops,
			frontier = Heap.new(),
			queued = {},
			sourceTile = tile,
			isBeachhead = true,
		}
		local n = MapGen.neighbors(tile, priorityScratch)
		local seeded = false
		for i = 1, n do
			local nb = priorityScratch[i]
			if self:isLand(nb) and buffer.readu8(self.owner, nb) == targetSlot then
				enqueueFront(self, attack, nb)
				seeded = true
			end
		end
		if not seeded then
			enqueueFront(self, attack, tile)
		end
		table.insert(self.attacks, attack)
	end

	-- launchAttack ne doit fusionner qu'avec des fronts terre (pas isBeachhead).
	local origLaunch = GameState.launchAttack
	function GameState.launchAttack(self, attackerSlot: number, targetSlot: number)
		local n = 0
		for i = #self.attacks, 1, -1 do
			local atk = self.attacks[i]
			if atk.isBeachhead then
				n += 1
				parkedBuf[n] = atk
				table.remove(self.attacks, i)
			end
		end
		for i = #parkedBuf, n + 1, -1 do
			parkedBuf[i] = nil
		end

		local ok, message = origLaunch(self, attackerSlot, targetSlot)

		for i = 1, n do
			table.insert(self.attacks, parkedBuf[i])
		end

		return ok, message
	end
end

return BoatFront
